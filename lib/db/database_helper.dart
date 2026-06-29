import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import '../models/document_filter.dart';

/// Capa de acceso a SQLite. Centraliza el esquema, la tabla virtual FTS5 y
/// los triggers que mantienen el índice de búsqueda al día.
///
/// Patrón clave: la tabla `documents_fts` es de tipo "external content"
/// (content='documents'), es decir, NO duplica el texto: apunta a las
/// columnas de `documents`. Los triggers la mantienen sincronizada en cada
/// INSERT/UPDATE/DELETE. Esto da búsqueda full-text instantánea sobre miles
/// de documentos sin doblar el almacenamiento.
///
/// Nota sobre FTS5: requiere SQLite >= 3.9, presente de forma nativa en
/// Android 7 (API 24) en adelante. Si necesitas soportar dispositivos más
/// antiguos, agrega `sqlite3_flutter_libs` para empaquetar tu propia copia
/// de SQLite. Para una flota corporativa moderna, lo nativo basta.
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static const _dbName = 'gestor_docs.db';
  static const _dbVersion = 1;

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (db) async {
        // Necesario para que los ON DELETE CASCADE funcionen.
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _createSchema,
    );
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE categories (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        name      TEXT NOT NULL,
        color     TEXT NOT NULL DEFAULT '#607D8B',
        parent_id INTEGER REFERENCES categories(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE documents (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        uri          TEXT NOT NULL UNIQUE,
        display_name TEXT NOT NULL,
        mime_type    TEXT,
        size_bytes   INTEGER NOT NULL DEFAULT 0,
        modified_at  INTEGER NOT NULL DEFAULT 0,
        ocr_text     TEXT,
        ocr_status   TEXT NOT NULL DEFAULT 'pending',
        category_id  INTEGER REFERENCES categories(id) ON DELETE SET NULL,
        synced_at    INTEGER,
        source       TEXT,
        deleted_at   INTEGER,
        in_vault     INTEGER NOT NULL DEFAULT 0,
        favorite     INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE tags (
        id   INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE
      )
    ''');

    await db.execute('''
      CREATE TABLE document_tags (
        document_id INTEGER NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
        tag_id      INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
        PRIMARY KEY (document_id, tag_id)
      )
    ''');

    // --- Tabla virtual FTS5 (external content) ---
    // unicode61 + remove_diacritics 2 => búsqueda insensible a tildes,
    // imprescindible para español ("informe" encuentra "informé").
    await db.execute('''
      CREATE VIRTUAL TABLE documents_fts USING fts5(
        display_name,
        ocr_text,
        content='documents',
        content_rowid='id',
        tokenize='unicode61 remove_diacritics 2'
      )
    ''');

    // --- Triggers que mantienen el índice FTS al día ---
    await db.execute('''
      CREATE TRIGGER documents_ai AFTER INSERT ON documents BEGIN
        INSERT INTO documents_fts(rowid, display_name, ocr_text)
        VALUES (new.id, new.display_name, new.ocr_text);
      END
    ''');

    await db.execute('''
      CREATE TRIGGER documents_ad AFTER DELETE ON documents BEGIN
        INSERT INTO documents_fts(documents_fts, rowid, display_name, ocr_text)
        VALUES ('delete', old.id, old.display_name, old.ocr_text);
      END
    ''');

    await db.execute('''
      CREATE TRIGGER documents_au AFTER UPDATE ON documents BEGIN
        INSERT INTO documents_fts(documents_fts, rowid, display_name, ocr_text)
        VALUES ('delete', old.id, old.display_name, old.ocr_text);
        INSERT INTO documents_fts(rowid, display_name, ocr_text)
        VALUES (new.id, new.display_name, new.ocr_text);
      END
    ''');

    // Índices de apoyo para los listados habituales.
    await db.execute(
        'CREATE INDEX idx_documents_category ON documents(category_id)');
    await db.execute(
        'CREATE INDEX idx_documents_ocr_status ON documents(ocr_status)');

    // Historial de búsquedas (para sugerir "recientes" con la caja vacía).
    await db.execute('''
      CREATE TABLE recent_searches (
        query TEXT PRIMARY KEY,
        ts    INTEGER NOT NULL
      )
    ''');

    // Configuración (clave-valor). Aquí vive el hash del PIN de la bóveda.
    await db.execute('''
      CREATE TABLE settings (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  // -------------------- Operaciones sobre documentos --------------------

  /// Inserta o actualiza por URI (el archivo físico es la fuente de verdad).
  Future<int> upsertDocument(Document doc) async {
    final db = await database;
    return db.insert(
      'documents',
      doc.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateOcr(int docId, String text, OcrStatus status) async {
    final db = await database;
    await db.update(
      'documents',
      {'ocr_text': text, 'ocr_status': status.name},
      where: 'id = ?',
      whereArgs: [docId],
    );
  }

  /// Consulta con filtros combinables + ordenamiento. Construye la cláusula
  /// WHERE dinámicamente: cada dimensión con valores aporta una condición; las
  /// vacías se omiten. Es la consulta que respalda la barra de filtros del UI.
  Future<List<Document>> queryDocuments({
    DocumentFilter filter = const DocumentFilter(),
    DocSort sort = DocSort.recent,
  }) async {
    final db = await database;
    // Nunca mostrar la papelera ni la bóveda en listados normales.
    final where = <String>['deleted_at IS NULL', 'in_vault = 0'];
    final args = <Object?>[];

    // --- Tipo (por MIME / extensión) ---
    if (filter.types.isNotEmpty) {
      final ors = <String>[];
      for (final t in filter.types) {
        switch (t) {
          case 'pdf':
            ors.add("(mime_type LIKE '%pdf%' OR display_name LIKE '%.pdf')");
          case 'image':
            ors.add("mime_type LIKE 'image/%'");
          case 'csv':
            ors.add("(mime_type LIKE '%csv%' OR display_name LIKE '%.csv')");
          case 'text':
            ors.add("(mime_type LIKE 'text/%' OR display_name LIKE '%.txt')");
        }
      }
      if (ors.isNotEmpty) where.add('(${ors.join(' OR ')})');
    }

    // --- Categoría ---
    if (filter.categoryIds.isNotEmpty) {
      final ph = List.filled(filter.categoryIds.length, '?').join(',');
      where.add('category_id IN ($ph)');
      args.addAll(filter.categoryIds);
    }

    // --- Origen ---
    if (filter.sources.isNotEmpty) {
      final ph = List.filled(filter.sources.length, '?').join(',');
      where.add('source IN ($ph)');
      args.addAll(filter.sources);
    }

    // --- Solo favoritos ---
    if (filter.favoritesOnly) where.add('favorite = 1');

    // --- Estado OCR ---
    if (filter.ocrStatuses.isNotEmpty) {
      final ph = List.filled(filter.ocrStatuses.length, '?').join(',');
      where.add('ocr_status IN ($ph)');
      args.addAll(filter.ocrStatuses.map((e) => e.name));
    }

    // --- Fecha ---
    if (filter.dateRange != null) {
      where.add('modified_at BETWEEN ? AND ?');
      args.addAll([filter.dateRange!.fromMillis, filter.dateRange!.toMillis]);
    }

    // --- Etiquetas (coincide si tiene CUALQUIERA de las elegidas) ---
    // Se resuelve con subconsulta para no duplicar filas por el join N:M.
    if (filter.tagIds.isNotEmpty) {
      final ph = List.filled(filter.tagIds.length, '?').join(',');
      where.add('''id IN (
        SELECT document_id FROM document_tags WHERE tag_id IN ($ph)
      )''');
      args.addAll(filter.tagIds);
    }

    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final rows = await db.rawQuery(
      'SELECT * FROM documents $whereSql ORDER BY ${sort.orderBy}',
      args,
    );
    return rows.map(Document.fromMap).toList();
  }

  Future<List<Document>> documentsByCategory(int? categoryId) async {
    final db = await database;
    final rows = await db.query(
      'documents',
      where: categoryId == null ? null : 'category_id = ?',
      whereArgs: categoryId == null ? null : [categoryId],
      orderBy: 'modified_at DESC',
    );
    return rows.map(Document.fromMap).toList();
  }

  /// Documentos pendientes de OCR, para procesarlos en segundo plano.
  Future<List<Document>> pendingOcr({int limit = 20}) async {
    final db = await database;
    final rows = await db.query(
      'documents',
      where: "ocr_status = 'pending'",
      limit: limit,
    );
    return rows.map(Document.fromMap).toList();
  }

  // -------------------- Categorías --------------------

  Future<List<Category>> categories() async {
    final db = await database;
    final rows = await db.query('categories', orderBy: 'name COLLATE NOCASE');
    return rows.map(Category.fromMap).toList();
  }

  Future<int> insertCategory(Category c) async {
    final db = await database;
    return db.insert('categories', c.toMap()..remove('id'));
  }

  /// Devuelve el id de la categoría, creándola si no existe (idempotente).
  Future<int> getOrCreateCategory(String name) async {
    final db = await database;
    final existing = await db.query('categories',
        where: 'name = ?', whereArgs: [name.trim()], limit: 1);
    if (existing.isNotEmpty) return existing.first['id'] as int;
    return db.insert('categories', {'name': name.trim(), 'color': '#607D8B'});
  }

  Future<void> setDocumentCategory(int docId, int? categoryId) async {
    final db = await database;
    await db.update('documents', {'category_id': categoryId},
        where: 'id = ?', whereArgs: [docId]);
  }

  Future<void> setFavorite(int docId, bool fav) async {
    final db = await database;
    await db.update('documents', {'favorite': fav ? 1 : 0},
        where: 'id = ?', whereArgs: [docId]);
  }

  // -------------------- Etiquetas --------------------

  Future<List<Tag>> allTags() async {
    final db = await database;
    final rows = await db.query('tags', orderBy: 'name COLLATE NOCASE');
    return rows.map(Tag.fromMap).toList();
  }

  /// Devuelve el id de la etiqueta, creándola si no existe (idempotente).
  Future<int> getOrCreateTag(String name) async {
    final db = await database;
    final existing = await db.query('tags',
        where: 'name = ?', whereArgs: [name.trim()], limit: 1);
    if (existing.isNotEmpty) return existing.first['id'] as int;
    return db.insert('tags', {'name': name.trim()});
  }

  Future<List<Tag>> tagsForDocument(int docId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT t.* FROM tags t
      JOIN document_tags dt ON dt.tag_id = t.id
      WHERE dt.document_id = ?
      ORDER BY t.name COLLATE NOCASE
    ''', [docId]);
    return rows.map(Tag.fromMap).toList();
  }

  /// Reemplaza por completo las etiquetas de un documento (transacción).
  Future<void> setDocumentTags(int docId, List<int> tagIds) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('document_tags',
          where: 'document_id = ?', whereArgs: [docId]);
      for (final tagId in tagIds) {
        await txn.insert('document_tags',
            {'document_id': docId, 'tag_id': tagId});
      }
    });
  }

  // -------------------- Papelera (borrado suave) --------------------
  // IMPORTANTE: "quitar del índice" NO borra el archivo del teléfono. Solo
  // marca el registro como eliminado; el archivo físico sigue intacto.

  Future<void> softDelete(int docId) async {
    final db = await database;
    await db.update('documents',
        {'deleted_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?', whereArgs: [docId]);
  }

  Future<void> restore(int docId) async {
    final db = await database;
    await db.update('documents', {'deleted_at': null},
        where: 'id = ?', whereArgs: [docId]);
  }

  Future<List<Document>> trashedDocuments() async {
    final db = await database;
    final rows = await db.query('documents',
        where: 'deleted_at IS NOT NULL', orderBy: 'deleted_at DESC');
    return rows.map(Document.fromMap).toList();
  }

  /// Elimina definitivamente del índice (no toca el archivo en disco).
  Future<void> removeFromIndex(int docId) async {
    final db = await database;
    await db.delete('documents', where: 'id = ?', whereArgs: [docId]);
  }

  Future<void> emptyTrash() async {
    final db = await database;
    await db.delete('documents', where: 'deleted_at IS NOT NULL');
  }

  // -------------------- Búsquedas recientes --------------------

  Future<void> addRecentSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final db = await database;
    await db.insert('recent_searches',
        {'query': q, 'ts': DateTime.now().millisecondsSinceEpoch},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<String>> recentSearches({int limit = 8}) async {
    final db = await database;
    final rows = await db.query('recent_searches',
        orderBy: 'ts DESC', limit: limit);
    return rows.map((r) => r['query'] as String).toList();
  }

  Future<void> clearRecentSearches() async {
    final db = await database;
    await db.delete('recent_searches');
  }

  // -------------------- Bóveda (carpeta oculta con PIN) --------------------
  // Los documentos en la bóveda quedan fuera de listados y búsquedas normales.
  // El PIN se guarda como hash SHA-256 con sal, nunca en texto plano.
  //
  // NOTA DE SEGURIDAD: esto oculta y controla el acceso dentro de la app, pero
  // no cifra el archivo en disco. Para protección real en reposo, en producción
  // conviene mover el PIN a `flutter_secure_storage` y cifrar los archivos de
  // la bóveda (p. ej. copiándolos a un área cifrada con AES).

  Future<bool> isVaultConfigured() async {
    final db = await database;
    final r = await db.query('settings',
        where: 'key = ?', whereArgs: ['vault_pin'], limit: 1);
    return r.isNotEmpty;
  }

  String _hashPin(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  Future<void> setVaultPin(String pin) async {
    final db = await database;
    final salt = (Random.secure().nextDouble()).toString();
    await db.insert(
        'settings', {'key': 'vault_salt', 'value': salt},
        conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert(
        'settings', {'key': 'vault_pin', 'value': _hashPin(pin, salt)},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> verifyVaultPin(String pin) async {
    final db = await database;
    final saltRow = await db.query('settings',
        where: 'key = ?', whereArgs: ['vault_salt'], limit: 1);
    final pinRow = await db.query('settings',
        where: 'key = ?', whereArgs: ['vault_pin'], limit: 1);
    if (saltRow.isEmpty || pinRow.isEmpty) return false;
    final salt = saltRow.first['value'] as String;
    return _hashPin(pin, salt) == pinRow.first['value'];
  }

  Future<void> moveToVault(int docId) async {
    final db = await database;
    await db.update('documents', {'in_vault': 1},
        where: 'id = ?', whereArgs: [docId]);
  }

  Future<void> removeFromVault(int docId) async {
    final db = await database;
    await db.update('documents', {'in_vault': 0},
        where: 'id = ?', whereArgs: [docId]);
  }

  /// Documentos de la bóveda. Llamar solo después de verificar el PIN.
  Future<List<Document>> vaultDocuments() async {
    final db = await database;
    final rows = await db.query('documents',
        where: 'in_vault = 1 AND deleted_at IS NULL',
        orderBy: 'modified_at DESC');
    return rows.map(Document.fromMap).toList();
  }
}
