import '../db/database_helper.dart';
import '../models/models.dart';

/// Búsqueda full-text sobre nombre de archivo + texto OCR usando FTS5.
class SearchService {
  final _dbHelper = DatabaseHelper.instance;

  /// Busca [rawQuery] en el índice FTS y devuelve los documentos ordenados
  /// por relevancia (rank de FTS5: más negativo = más relevante).
  ///
  /// Soporta la sintaxis de FTS5: prefijos con `*`, frases con comillas,
  /// operadores AND/OR/NOT. Aquí limpiamos la entrada del usuario y, por
  /// defecto, hacemos búsqueda por prefijo en cada término.
  Future<List<Document>> search(String rawQuery, {int limit = 100}) async {
    final query = _buildMatchExpression(rawQuery);
    if (query.isEmpty) return [];

    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT d.*
      FROM documents_fts f
      JOIN documents d ON d.id = f.rowid
      WHERE documents_fts MATCH ?
        AND d.deleted_at IS NULL
        AND d.in_vault = 0
      ORDER BY rank
      LIMIT ?
    ''', [query, limit]);

    return rows.map(Document.fromMap).toList();
  }

  /// Convierte texto libre en una expresión MATCH segura.
  /// Ej.: "factura claro" => "factura* claro*"
  String _buildMatchExpression(String raw) {
    final terms = raw
        .toLowerCase()
        .replaceAll(RegExp(r'["()]'), ' ') // evita romper la sintaxis FTS
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .map((t) => '$t*') // búsqueda por prefijo
        .toList();
    return terms.join(' ');
  }
}
