import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/models.dart';
import 'tag_category_editor.dart';

/// Detalle de un documento: metadatos, categoría/etiquetas editables y vista
/// previa del texto extraído.
class DocumentDetailScreen extends StatefulWidget {
  final Document document;
  const DocumentDetailScreen({super.key, required this.document});

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen> {
  final _db = DatabaseHelper.instance;
  List<Tag> _tags = [];
  String? _categoryName;
  late bool _fav = widget.document.favorite;

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  Future<void> _loadMeta() async {
    final tags = await _db.tagsForDocument(widget.document.id!);
    final cats = await _db.categories();
    String? catName;
    if (widget.document.categoryId != null) {
      for (final c in cats) {
        if (c.id == widget.document.categoryId) {
          catName = c.name;
          break;
        }
      }
    }
    setState(() {
      _tags = tags;
      _categoryName = catName;
    });
  }

  Future<void> _edit() async {
    final changed = await TagCategoryEditor.show(context, widget.document.id!);
    if (changed == true) _loadMeta();
  }

  Future<void> _toggleFav() async {
    setState(() => _fav = !_fav);
    await _db.setFavorite(widget.document.id!, _fav);
  }

  Future<void> _toVault() async {
    if (!await _db.isVaultConfigured()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Primero crea un código en la Bóveda.')));
      }
      return;
    }
    await _db.moveToVault(widget.document.id!);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('¿Quitar del índice?'),
        content: const Text(
            'Se quitará de la app. El archivo seguirá en tu teléfono y podrás '
            'restaurarlo desde la papelera.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Quitar')),
        ],
      ),
    );
    if (ok == true) {
      await _db.softDelete(widget.document.id!);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.document;
    final text = (d.ocrText ?? '').trim();
    return Scaffold(
      appBar: AppBar(
        title: Text(d.displayName),
        actions: [
          IconButton(
            icon: Icon(_fav ? Icons.star : Icons.star_border),
            color: _fav ? Colors.amber : null,
            tooltip: 'Destacar',
            onPressed: _toggleFav,
          ),
          IconButton(
            icon: const Icon(Icons.label_outline),
            tooltip: 'Editar categoría y etiquetas',
            onPressed: _edit,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _row('Tipo', d.mimeType ?? 'desconocido'),
          _row('Tamaño', '${(d.sizeBytes / 1024).toStringAsFixed(0)} KB'),
          _row('Categoría', _categoryName ?? 'sin categoría'),
          _row('Estado OCR', d.ocrStatus.name),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ..._tags.map((t) => Chip(label: Text('#${t.name}'))),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('Editar'),
                onPressed: _edit,
              ),
            ],
          ),
          const Divider(height: 32),
          Text('Texto extraído',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (text.isEmpty)
            const Text('Sin texto indexado todavía.')
          else
            SelectableText(text),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _toVault,
                  icon: const Icon(Icons.lock_outline, size: 18),
                  label: const Text('Bóveda'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _remove,
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Quitar'),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Quitar no borra el archivo de tu teléfono',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5)),
          ),
        ],
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(width: 110, child: Text(k)),
            Expanded(
              child: Text(v, style: const TextStyle(fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );
}
