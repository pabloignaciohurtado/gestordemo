import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// Escaneo de TODO el almacenamiento compartido usando el permiso
/// "Acceso a todos los archivos" (MANAGE_EXTERNAL_STORAGE).
///
/// A diferencia de SAF (que solo ve la carpeta que el usuario concede), esto
/// recorre el sistema de archivos completo: Descargas, DCIM, Documentos, los
/// medios de WhatsApp y las carpetas de descarga de otras apps. Es el motor
/// que resuelve el "bucear entre carpetas difíciles de encontrar".
///
/// Límite infranqueable incluso con este permiso: los directorios privados
/// `Android/data` y `Android/obb` de OTRAS apps. Se omiten para evitar errores.
class FullStorageService {
  /// Raíz del almacenamiento interno en la inmensa mayoría de dispositivos.
  static const _internalRoot = '/storage/emulated/0';

  /// Carpetas que no tiene sentido (o no se puede) recorrer.
  static const _skipDirs = {'Android/data', 'Android/obb'};

  /// Ubicaciones de alto valor para mostrarlas como "fuentes" en el UI.
  static const knownSources = {
    'Descargas': 'Download',
    'WhatsApp': 'Android/media/com.whatsapp/WhatsApp/Media',
    'Cámara': 'DCIM',
    'Documentos': 'Documents',
    'Imágenes': 'Pictures',
    'Bluetooth': 'Bluetooth',
  };

  /// Solicita el permiso de acceso total. Abre la pantalla de ajustes del
  /// sistema (no es un diálogo simple). Devuelve true si quedó concedido.
  Future<bool> requestAccess() async {
    if (await Permission.manageExternalStorage.isGranted) return true;
    final status = await Permission.manageExternalStorage.request();
    return status.isGranted;
  }

  bool get _hasRoot => Directory(_internalRoot).existsSync();

  /// Recorre todo el almacenamiento y emite cada archivo encontrado.
  /// Implementación manual (no `list(recursive:true)`) para poder saltar
  /// carpetas bloqueadas sin que reviente el recorrido.
  Stream<File> scanAll({Set<String>? extensions}) async* {
    if (!_hasRoot) return;
    yield* _walk(Directory(_internalRoot), extensions);
  }

  /// Escanea solo una fuente conocida (ej. solo WhatsApp o solo Descargas).
  Stream<File> scanSource(String sourceKey, {Set<String>? extensions}) async* {
    final rel = knownSources[sourceKey];
    if (rel == null) return;
    final dir = Directory('$_internalRoot/$rel');
    if (!dir.existsSync()) return;
    yield* _walk(dir, extensions);
  }

  Stream<File> _walk(Directory dir, Set<String>? extensions) async* {
    final rel = dir.path.replaceFirst('$_internalRoot/', '');
    if (_skipDirs.any((s) => rel == s || rel.startsWith('$s/'))) return;

    List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } catch (_) {
      return; // sin permiso sobre esta subcarpeta: la saltamos
    }

    for (final e in entries) {
      if (e is Directory) {
        yield* _walk(e, extensions);
      } else if (e is File) {
        if (extensions == null || _matches(e.path, extensions)) {
          yield e;
        }
      }
    }
  }

  bool _matches(String path, Set<String> exts) {
    final lower = path.toLowerCase();
    return exts.any((x) => lower.endsWith('.$x'));
  }

  /// Deriva un origen legible a partir de la ruta del archivo, para mostrarlo
  /// y filtrarlo en el UI. Mapea las carpetas conocidas y cae a "Otros".
  static String sourceForPath(String path) {
    final p = path.toLowerCase();
    if (p.contains('com.whatsapp')) return 'WhatsApp';
    if (p.contains('/download')) return 'Descargas';
    if (p.contains('/dcim')) return 'Cámara';
    if (p.contains('/documents')) return 'Documentos';
    if (p.contains('/pictures')) return 'Imágenes';
    if (p.contains('/bluetooth')) return 'Bluetooth';
    if (p.contains('com.android.telegram') || p.contains('/telegram')) {
      return 'Telegram';
    }
    return 'Otros';
  }
}
