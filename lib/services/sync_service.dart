import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/database_helper.dart';
import '../models/models.dart';

/// Sincroniza el ÍNDICE (metadatos + texto OCR) con el equipo vía Supabase.
///
/// Decisión de arquitectura deliberada: sincronizamos solo metadatos, NUNCA
/// los archivos binarios. Compartir la taxonomía y el texto buscable entre
/// colegas es trivial y barato; replicar gigas de PDFs no lo es. Los archivos
/// pesados siguen viviendo en el Drive corporativo.
///
/// Esquema esperado en Supabase (tabla `documents`):
///   id (uuid), uri (text), display_name (text), mime_type (text),
///   ocr_text (text), category_id (int), owner (uuid),
///   updated_at (timestamptz). Con RLS para que cada equipo vea lo suyo.
class SyncService {
  SupabaseClient get _client => Supabase.instance.client;
  final _db = DatabaseHelper.instance;

  /// Inicializar una sola vez al arrancar la app (en main()).
  static Future<void> init({
    required String url,
    required String publishableKey,
  }) async {
    await Supabase.initialize(url: url, publishableKey: publishableKey);
  }

  /// Empuja los documentos aún no sincronizados (synced_at IS NULL).
  Future<int> pushUnsynced({int batch = 200}) async {
    final db = await _db.database;
    final rows = await db.query(
      'documents',
      where: 'synced_at IS NULL',
      limit: batch,
    );
    if (rows.isEmpty) return 0;

    final payload = rows.map((m) {
      final doc = Document.fromMap(m);
      return {
        'uri': doc.uri,
        'display_name': doc.displayName,
        'mime_type': doc.mimeType,
        'ocr_text': doc.ocrText,
        'category_id': doc.categoryId,
        'owner': _client.auth.currentUser?.id,
      };
    }).toList();

    await _client.from('documents').upsert(payload, onConflict: 'uri');

    final now = DateTime.now().millisecondsSinceEpoch;
    final ids = rows.map((m) => m['id']).toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE documents SET synced_at = ? WHERE id IN ($placeholders)',
      [now, ...ids],
    );
    return rows.length;
  }

  /// Trae los cambios del equipo desde la última sincronización.
  /// (Esqueleto: completar el merge según tu estrategia de conflictos.)
  Future<List<Map<String, dynamic>>> pullSince(DateTime since) async {
    final data = await _client
        .from('documents')
        .select()
        .gt('updated_at', since.toIso8601String());
    return List<Map<String, dynamic>>.from(data as List);
  }
}
