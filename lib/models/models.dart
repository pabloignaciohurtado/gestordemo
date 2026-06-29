// Modelos de dominio. Mapean 1:1 con las tablas de SQLite.
// Mantener los modelos "tontos" (solo datos + serialización) y dejar la
// lógica en los servicios.

class Category {
  final int? id;
  final String name;
  final String color; // hex, ej. "#1E88E5"
  final int? parentId;

  Category({this.id, required this.name, this.color = '#607D8B', this.parentId});

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'color': color,
        'parent_id': parentId,
      };

  factory Category.fromMap(Map<String, dynamic> m) => Category(
        id: m['id'] as int?,
        name: m['name'] as String,
        color: m['color'] as String? ?? '#607D8B',
        parentId: m['parent_id'] as int?,
      );
}

class Tag {
  final int? id;
  final String name;

  Tag({this.id, required this.name});

  Map<String, dynamic> toMap() => {'id': id, 'name': name};

  factory Tag.fromMap(Map<String, dynamic> m) =>
      Tag(id: m['id'] as int?, name: m['name'] as String);
}

enum OcrStatus { pending, done, failed, notApplicable }

class Document {
  final int? id;

  /// URI de contenido SAF (content://...) o ruta. Es la referencia al archivo
  /// físico, que NUNCA se mueve: solo se indexa.
  final String uri;
  final String displayName;
  final String? mimeType;
  final int sizeBytes;
  final int modifiedAtMillis;

  /// Texto extraído (OCR de imágenes o texto nativo de PDF). Va a FTS5.
  final String? ocrText;
  final OcrStatus ocrStatus;

  final int? categoryId;
  final int? syncedAtMillis; // null = aún no sincronizado

  /// Origen del archivo: 'Descargas', 'WhatsApp', 'Cámara', 'Manual', etc.
  /// Se deriva de la ruta al indexar; 'Manual' cuando el usuario lo agrega.
  final String? source;

  /// Si está en la bóveda (carpeta oculta protegida por PIN). Los documentos
  /// en la bóveda no aparecen en listados ni búsquedas normales.
  final bool inVault;

  /// Marcado como favorito/destacado por el usuario.
  final bool favorite;

  Document({
    this.id,
    required this.uri,
    required this.displayName,
    this.mimeType,
    this.sizeBytes = 0,
    this.modifiedAtMillis = 0,
    this.ocrText,
    this.ocrStatus = OcrStatus.pending,
    this.categoryId,
    this.syncedAtMillis,
    this.source,
    this.inVault = false,
    this.favorite = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'uri': uri,
        'display_name': displayName,
        'mime_type': mimeType,
        'size_bytes': sizeBytes,
        'modified_at': modifiedAtMillis,
        'ocr_text': ocrText,
        'ocr_status': ocrStatus.name,
        'category_id': categoryId,
        'synced_at': syncedAtMillis,
        'source': source,
        'in_vault': inVault ? 1 : 0,
        'favorite': favorite ? 1 : 0,
      };

  factory Document.fromMap(Map<String, dynamic> m) => Document(
        id: m['id'] as int?,
        uri: m['uri'] as String,
        displayName: m['display_name'] as String,
        mimeType: m['mime_type'] as String?,
        sizeBytes: (m['size_bytes'] as int?) ?? 0,
        modifiedAtMillis: (m['modified_at'] as int?) ?? 0,
        ocrText: m['ocr_text'] as String?,
        ocrStatus: OcrStatus.values.firstWhere(
          (e) => e.name == m['ocr_status'],
          orElse: () => OcrStatus.pending,
        ),
        categoryId: m['category_id'] as int?,
        syncedAtMillis: m['synced_at'] as int?,
        source: m['source'] as String?,
        inVault: (m['in_vault'] as int?) == 1,
        favorite: (m['favorite'] as int?) == 1,
      );

  Document copyWith({
    int? id,
    String? ocrText,
    OcrStatus? ocrStatus,
    int? categoryId,
    int? syncedAtMillis,
  }) =>
      Document(
        id: id ?? this.id,
        uri: uri,
        displayName: displayName,
        mimeType: mimeType,
        sizeBytes: sizeBytes,
        modifiedAtMillis: modifiedAtMillis,
        ocrText: ocrText ?? this.ocrText,
        ocrStatus: ocrStatus ?? this.ocrStatus,
        categoryId: categoryId ?? this.categoryId,
        syncedAtMillis: syncedAtMillis ?? this.syncedAtMillis,
      );
}
