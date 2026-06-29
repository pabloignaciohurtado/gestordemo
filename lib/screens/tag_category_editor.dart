import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/models.dart';

/// Hoja inferior para editar la categoría y las etiquetas de un documento.
/// Permite elegir categoría, marcar/desmarcar etiquetas existentes y crear
/// nuevas sobre la marcha. Devuelve true si se guardaron cambios.
class TagCategoryEditor extends StatefulWidget {
  final int documentId;
  const TagCategoryEditor({super.key, required this.documentId});

  static Future<bool?> show(BuildContext context, int documentId) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => TagCategoryEditor(documentId: documentId),
    );
  }

  @override
  State<TagCategoryEditor> createState() => _TagCategoryEditorState();
}

class _TagCategoryEditorState extends State<TagCategoryEditor> {
  final _db = DatabaseHelper.instance;
  final _newTagCtrl = TextEditingController();

  List<Category> _categories = [];
  List<Tag> _allTags = [];
  int? _selectedCategory;
  final Set<int> _selectedTags = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cats = await _db.categories();
    final tags = await _db.allTags();
    final docTags = await _db.tagsForDocument(widget.documentId);
    setState(() {
      _categories = cats;
      _allTags = tags;
      _selectedTags.addAll(docTags.map((t) => t.id!));
      _loading = false;
    });
  }

  Future<void> _createTag() async {
    final name = _newTagCtrl.text.trim();
    if (name.isEmpty) return;
    final id = await _db.getOrCreateTag(name);
    _newTagCtrl.clear();
    final tags = await _db.allTags();
    setState(() {
      _allTags = tags;
      _selectedTags.add(id);
    });
  }

  Future<void> _save() async {
    await _db.setDocumentCategory(widget.documentId, _selectedCategory);
    await _db.setDocumentTags(widget.documentId, _selectedTags.toList());
    if (mounted) Navigator.pop(context, true);
  }

  @override
  void dispose() {
    _newTagCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + bottomInset),
      child: _loading
          ? const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Categoría', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Sin categoría'),
                        selected: _selectedCategory == null,
                        onSelected: (_) => setState(() => _selectedCategory = null),
                      ),
                      ..._categories.map((c) => ChoiceChip(
                            label: Text(c.name),
                            selected: _selectedCategory == c.id,
                            onSelected: (_) =>
                                setState(() => _selectedCategory = c.id),
                          )),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text('Etiquetas', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _allTags
                        .map((t) => FilterChip(
                              label: Text('#${t.name}'),
                              selected: _selectedTags.contains(t.id),
                              onSelected: (sel) => setState(() {
                                sel
                                    ? _selectedTags.add(t.id!)
                                    : _selectedTags.remove(t.id);
                              }),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newTagCtrl,
                          decoration: const InputDecoration(
                            hintText: 'Nueva etiqueta…',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _createTag(),
                        ),
                      ),
                      IconButton(
                        onPressed: _createTag,
                        icon: const Icon(Icons.add_circle),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _save,
                      child: const Text('Guardar'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
