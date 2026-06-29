import 'package:flutter/material.dart';

/// Pantalla de privacidad. Comunica garantías que son ciertas por diseño de la
/// app, no promesas de marketing: el OCR corre en el dispositivo, la carga
/// manual no usa permisos amplios, y quitar del índice no borra el archivo.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacidad')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          _Point(
            icon: Icons.phonelink_lock,
            title: 'El OCR ocurre en tu teléfono',
            body: 'El texto de tus documentos se extrae en el dispositivo con '
                'un modelo local. El contenido de los archivos no se envía a '
                'ningún servidor para reconocerlo.',
          ),
          _Point(
            icon: Icons.folder_open,
            title: 'Carga manual sin permisos amplios',
            body: 'Al agregar archivos manualmente usamos el selector del '
                'sistema: solo accedemos a lo que tú eliges, sin pedir acceso '
                'a todo el almacenamiento.',
          ),
          _Point(
            icon: Icons.restore_from_trash,
            title: 'Quitar del índice no borra tus archivos',
            body: 'Cuando quitas un documento de la app, solo lo sacamos de '
                'nuestro índice. El archivo original sigue intacto en tu '
                'teléfono.',
          ),
          _Point(
            icon: Icons.groups,
            title: 'Tú controlas qué se comparte con el equipo',
            body: 'Al sincronizar con el equipo se comparten etiquetas y texto '
                'indexado, no los archivos. Nada se comparte sin que lo '
                'configures.',
          ),
        ],
      ),
    );
  }
}

class _Point extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _Point({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 4),
                Text(body,
                    style: TextStyle(
                        fontSize: 13.5,
                        height: 1.45,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
