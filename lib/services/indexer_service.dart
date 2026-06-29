
import 'package:file_picker/file_picker.dart';

import '../db/database_helper.dart';
import '../models/models.dart';
import 'ocr_service.dart';
import 'full_storage_service.dart';
import 'auto_classifier.dart';

/// Orquestador del indexado. Une las tres capas:
///   SAF (archivos físicos) -> SQLite (metadatos) -> FTS5 (búsqueda).
///
/// El indexado tiene dos fases para que la UI responda rápido:
///   1. Recorrido + alta de metadatos (rápido): el usuario ya ve los archivos.
///   2. OCR en segundo plano (lento): se procesa la cola `pending`.
class IndexerService {
  final _fullStorage = FullStorageService();
  final _ocr = OcrService();
  final _db = DatabaseHelper.instance;

  /// Indexa TODO el almacenamiento del teléfono (Descargas, WhatsApp, etc.)
  /// usando el permiso "Acceso a todos los archivos". Pide el permiso si hace
  /// falta; devuelve -1 si el usuario no lo concede.
  ///
  /// Ventaja extra frente a SAF: aquí trabajamos con rutas reales, así que el
  /// OCR lee el archivo directo, sin tener que copiarlo a temporal.
  Future<int> indexEntireDevice({
    Set<String> extensions = const {
      'pdf', 'jpg', 'jpeg', 'png', 'webp', 'txt', 'csv', 'doc', 'docx', 'xls', 'xlsx'
    },
  }) async {
    final granted = await _fullStorage.requestAccess();
    if (!granted) return -1;

    var count = 0;
    await for (final file in _fullStorage.scanAll(extensions: extensions)) {
      final stat = await file.stat();
      final name = file.uri.pathSegments.last;
      final doc = Document(
        uri: file.path, // ruta real, no content:// URI
        displayName: name,
        mimeType: _mimeFromName(name),
        sizeBytes: stat.size,
        modifiedAtMillis: stat.modified.millisecondsSinceEpoch,
        source: FullStorageService.sourceForPath(file.path),
        ocrStatus:
            _shouldOcr(null, name) ? OcrStatus.pending : OcrStatus.notApplicable,
      );
      await _db.upsertDocument(doc);
      count++;
    }
    return count;
  }

  /// Carga MANUAL: abre el selector del sistema (SAF) para que el usuario elija
  /// uno o varios archivos concretos. No requiere "Acceso a todos los
  /// archivos"; el usuario concede acceso solo a lo que selecciona. Los marca
  /// con origen 'Manual'. Devuelve cuántos se agregaron.
  Future<int> addFilesManually() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
      withData: false, // usamos la ruta, no cargamos bytes en memoria
    );
    if (result == null) return 0;

    var count = 0;
    for (final f in result.files) {
      if (f.path == null) continue;
      final doc = Document(
        uri: f.path!,
        displayName: f.name,
        mimeType: _mimeFromName(f.name),
        sizeBytes: f.size,
        modifiedAtMillis: DateTime.now().millisecondsSinceEpoch,
        source: 'Manual',
        ocrStatus:
            _shouldOcr(null, f.name) ? OcrStatus.pending : OcrStatus.notApplicable,
      );
      await _db.upsertDocument(doc);
      count++;
    }
    return count;
  }

  /// Aplica la clasificación automática a un documento recién OCR-eado:
  /// suma las etiquetas sugeridas (sin pisar las que el usuario ya puso) y
  /// asigna categoría solo si el documento aún no tiene una.
  Future<void> _applyClassification(Document doc, String text) async {
    final c = AutoClassifier.classify(name: doc.displayName, text: text);
    if (c.isEmpty) return;

    if (c.tags.isNotEmpty) {
      final existing = await _db.tagsForDocument(doc.id!);
      final ids = existing.map((t) => t.id!).toSet();
      for (final name in c.tags) {
        ids.add(await _db.getOrCreateTag(name));
      }
      await _db.setDocumentTags(doc.id!, ids.toList());
    }

    if (c.category != null && doc.categoryId == null) {
      final catId = await _db.getOrCreateCategory(c.category!);
      await _db.setDocumentCategory(doc.id!, catId);
    }
  }

  String _mimeFromName(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.pdf')) return 'application/pdf';
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.txt')) return 'text/plain';
    if (n.endsWith('.csv')) return 'text/csv';
    return 'application/octet-stream';
  }

  /// Fase 2: procesa la cola de OCR pendiente. Llamar repetidamente (p. ej.
  /// desde un WorkManager / tarea periódica) hasta vaciar la cola.
  Future<void> processOcrQueue({int batch = 10}) async {
    final pending = await _db.pendingOcr(limit: batch);
    for (final doc in pending) {
      try {
        // Tras el escaneo o el selector, doc.uri ya es una ruta real en disco,
        // así que ML Kit y el extractor de PDF la leen directamente.
        final text = await _ocr.extractText(
          localPath: doc.uri,
          mimeType: doc.mimeType,
        );
        await _db.updateOcr(doc.id!, text, OcrStatus.done);
        await _applyClassification(doc, text);
      } catch (_) {
        await _db.updateOcr(doc.id!, '', OcrStatus.failed);
      }
    }
  }

  bool _shouldOcr(String? mime, String name) {
    final m = (mime ?? '').toLowerCase();
    final n = name.toLowerCase();
    return m.startsWith('image/') ||
        m.contains('pdf') ||
        n.endsWith('.pdf') ||
        n.endsWith('.jpg') ||
        n.endsWith('.jpeg') ||
        n.endsWith('.png');
  }

  Future<void> dispose() => _ocr.dispose();
}
