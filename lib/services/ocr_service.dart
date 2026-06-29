import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:read_pdf_text/read_pdf_text.dart';

/// Extracción de texto para alimentar el índice de búsqueda.
///
/// Dos caminos:
///  - Imágenes (jpg/png/...) y escaneos: OCR on-device con ML Kit (gratis,
///    offline, sin enviar nada a la nube).
///  - PDFs: primero intentamos extraer el texto nativo (rápido y exacto);
///    si el PDF es un escaneo sin capa de texto, habría que rasterizar las
///    páginas y pasarlas por OCR (ver TODO abajo).
class OcrService {
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// Decide la estrategia según el tipo de archivo.
  /// [localPath] debe ser una ruta de archivo real (no un content:// URI).
  /// Cachea el archivo desde SAF a almacenamiento temporal antes de llamar.
  Future<String> extractText({
    required String localPath,
    required String? mimeType,
  }) async {
    final mt = (mimeType ?? '').toLowerCase();

    if (mt.contains('pdf') || localPath.toLowerCase().endsWith('.pdf')) {
      return _extractFromPdf(localPath);
    }
    if (mt.startsWith('image/') || _looksLikeImage(localPath)) {
      return _ocrImage(localPath);
    }
    // Tipos de texto plano se podrían leer directo; otros se ignoran.
    return '';
  }

  Future<String> _ocrImage(String path) async {
    final input = InputImage.fromFile(File(path));
    final result = await _recognizer.processImage(input);
    return result.text;
  }

  Future<String> _extractFromPdf(String path) async {
    try {
      final text = await ReadPdfText.getPDFtext(path);
      // TODO: si `text` viene casi vacío, el PDF es un escaneo => rasterizar
      // páginas (p. ej. con el paquete `pdfx`) y pasar cada imagen por _ocrImage.
      return text;
    } catch (_) {
      return '';
    }
  }

  bool _looksLikeImage(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.heic');
  }

  Future<void> dispose() => _recognizer.close();
}
