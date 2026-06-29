import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/models.dart';
import '../models/document_filter.dart';
import '../services/indexer_service.dart';
import 'document_detail_screen.dart';
import 'search_screen.dart';
import 'vault_screen.dart';
import 'privacy_screen.dart';

enum ViewMode { list, grid, compact }
enum GroupBy { none, smart, date, category, source, type, size }

/// Pantalla principal: centro que integra escaneo, carga manual, filtros,
/// agrupaciones, tipos de vista, favoritos, selección múltiple, papelera y
/// bóveda sobre la base SQLite + FTS5 con clasificación automática.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _db = DatabaseHelper.instance;
  final _indexer = IndexerService();

  List<Document> _docs = [];
  Map<int, String> _catNames = {};
  List<String> _allSources = [];
  List<Category> _categories = [];

  DocumentFilter _filter = const DocumentFilter();
  DocSort _sort = DocSort.recent;
  ViewMode _view = ViewMode.list;
  GroupBy _group = GroupBy.none;

  bool _selectMode = false;
  final Set<int> _selected = {};
  bool _busy = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cats = await _db.categories();
    final facets = await _db.queryDocuments(); // sin filtro: para orígenes
    final docs = await _db.queryDocuments(filter: _filter, sort: _sort);
    setState(() {
      _categories = cats;
      _catNames = {for (final c in cats) c.id!: c.name};
      _allSources = facets.map((d) => d.source ?? 'Otros').toSet().toList()..sort();
      _docs = docs;
    });
  }

  // -------------------- Agregar: escanear / manual --------------------

  void _openAddSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.search),
            title: const Text('Escanear todo el teléfono'),
            subtitle: const Text('Descargas, WhatsApp, fotos y otras apps'),
            onTap: () {
              Navigator.pop(context);
              _scan();
            },
          ),
          ListTile(
            leading: const Icon(Icons.note_add),
            title: const Text('Agregar archivos manualmente'),
            subtitle: const Text('Elige archivos puntuales con el selector'),
            onTap: () {
              Navigator.pop(context);
              _manual();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _scan() async {
    setState(() {
      _busy = true;
      _status = 'Solicitando acceso…';
    });
    final count = await _indexer.indexEntireDevice();
    if (count < 0) {
      setState(() {
        _busy = false;
        _status = '';
      });
      _snack('Necesito el permiso "Acceso a todos los archivos" para escanear.');
      return;
    }
    setState(() => _status = 'Procesando OCR y clasificando…');
    await _indexer.processOcrQueue(batch: 100); // en producción: WorkManager
    await _load();
    setState(() {
      _busy = false;
      _status = '$count archivos indexados';
    });
  }

  Future<void> _manual() async {
    setState(() {
      _busy = true;
      _status = 'Agregando archivos…';
    });
    final count = await _indexer.addFilesManually();
    if (count > 0) {
      await _indexer.processOcrQueue(batch: 100);
      await _load();
    }
    setState(() {
      _busy = false;
      _status = count > 0 ? '$count archivos agregados' : '';
    });
  }

  // -------------------- Selección múltiple --------------------

  void _enterSelect(int id) => setState(() {
        _selectMode = true;
        _selected.add(id);
      });

  void _toggleSel(int id) => setState(() {
        _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
        if (_selected.isEmpty) _selectMode = false;
      });

  void _exitSelect() => setState(() {
        _selectMode = false;
        _selected.clear();
      });

  Future<void> _batchFav() async {
    for (final id in _selected) {
      await _db.setFavorite(id, true);
    }
    _exitSelect();
    await _load();
  }

  Future<void> _batchTrash() async {
    final ids = _selected.toList();
    for (final id in ids) {
      await _db.softDelete(id);
    }
    _exitSelect();
    await _load();
    _snack('${ids.length} archivos quitados (siguen en tu teléfono)',
        action: 'DESHACER', onAction: () async {
      for (final id in ids) {
        await _db.restore(id);
      }
      _load();
    });
  }

  Future<void> _batchVault() async {
    final configured = await _db.isVaultConfigured();
    if (!configured) {
      _snack('Primero crea un código en la Bóveda.');
      return;
    }
    for (final id in _selected) {
      await _db.moveToVault(id);
    }
    _exitSelect();
    await _load();
    _snack('Movidos a la bóveda');
  }

  // -------------------- Navegación --------------------

  Future<void> _openDoc(Document d) async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => DocumentDetailScreen(document: d)));
    _load(); // pudo cambiar categoría/etiquetas/favorito/bóveda
  }

  void _openTrash() => showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (_) => _TrashSheet(onChanged: _load),
      );

  void _snack(String msg, {String? action, VoidCallback? onAction}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      action: action != null
          ? SnackBarAction(label: action, onPressed: onAction ?? () {})
          : null,
    ));
  }

  // -------------------- Construcción --------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _selectMode ? _selectionBar() : _normalBar(),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (!_selectMode) _filterBar(),
          if (_status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_status, style: Theme.of(context).textTheme.bodySmall),
              ),
            ),
          Expanded(child: _docs.isEmpty ? _emptyState() : _buildBody()),
        ],
      ),
      floatingActionButton: _selectMode
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : _openAddSheet,
              icon: const Icon(Icons.add),
              label: const Text('Agregar'),
            ),
    );
  }

  AppBar _normalBar() => AppBar(
        title: const Text('Mis documentos'),
        actions: [
          IconButton(
            tooltip: 'Favoritos',
            icon: Icon(_filter.favoritesOnly ? Icons.star : Icons.star_border),
            color: _filter.favoritesOnly ? Colors.amber : null,
            onPressed: () {
              setState(() => _filter =
                  _filter.copyWith(favoritesOnly: !_filter.favoritesOnly));
              _load();
            },
          ),
          IconButton(
            tooltip: 'Visualización',
            icon: const Icon(Icons.tune),
            onPressed: _openDisplaySheet,
          ),
          IconButton(
            tooltip: 'Buscar',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SearchScreen())),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'trash') _openTrash();
              if (v == 'vault') {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const VaultScreen()));
              }
              if (v == 'privacy') {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const PrivacyScreen()));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'vault', child: Text('Bóveda')),
              PopupMenuItem(value: 'trash', child: Text('Papelera')),
              PopupMenuItem(value: 'privacy', child: Text('Privacidad')),
            ],
          ),
        ],
      );

  AppBar _selectionBar() => AppBar(
        leading: IconButton(icon: const Icon(Icons.close), onPressed: _exitSelect),
        title: Text('${_selected.length}'),
        actions: [
          IconButton(icon: const Icon(Icons.star), tooltip: 'Destacar', onPressed: _batchFav),
          IconButton(icon: const Icon(Icons.lock), tooltip: 'A la bóveda', onPressed: _batchVault),
          IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Quitar', onPressed: _batchTrash),
        ],
      );

  Widget _filterBar() {
    Widget chip(String label, bool active, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilterChip(
            label: Text(label),
            selected: active,
            onSelected: (_) => onTap(),
          ),
        );
    final hasFilters = !_filter.isEmpty;
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          chip('Tipo', _filter.types.isNotEmpty, _typeSheet),
          chip('Categoría', _filter.categoryIds.isNotEmpty, _categorySheet),
          chip('Origen', _filter.sources.isNotEmpty, _sourceSheet),
          chip('OCR', _filter.ocrStatuses.isNotEmpty, _ocrSheet),
          if (hasFilters)
            chip('✕ Limpiar', false, () {
              setState(() => _filter = const DocumentFilter());
              _load();
            }),
        ],
      ),
    );
  }

  // ---- hojas de filtro (genéricas) ----
  Future<void> _multiSheet<T>(String title, List<T> options, String Function(T) label,
      Set<T> current, void Function(Set<T>) apply) async {
    final sel = Set<T>.from(current);
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => ListView(
          shrinkWrap: true,
          children: [
            Padding(padding: const EdgeInsets.all(16), child: Text(title, style: Theme.of(ctx).textTheme.titleMedium)),
            ...options.map((o) => CheckboxListTile(
                  value: sel.contains(o),
                  title: Text(label(o)),
                  onChanged: (v) => setSheet(() => v == true ? sel.add(o) : sel.remove(o)),
                )),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: () {
                  apply(sel);
                  Navigator.pop(ctx);
                  _load();
                },
                child: const Text('Aplicar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _typeSheet() => _multiSheet<String>('Tipo', const ['pdf', 'image', 'text', 'csv'],
      (t) => {'pdf': 'PDF', 'image': 'Imagen', 'text': 'Texto', 'csv': 'CSV'}[t]!,
      _filter.types, (s) => _filter = _filter.copyWith(types: s));

  void _categorySheet() => _multiSheet<int>('Categoría', _categories.map((c) => c.id!).toList(),
      (id) => _catNames[id] ?? '—', _filter.categoryIds, (s) => _filter = _filter.copyWith(categoryIds: s));

  void _sourceSheet() => _multiSheet<String>('Origen', _allSources, (s) => s, _filter.sources,
      (s) => _filter = _filter.copyWith(sources: s));

  void _ocrSheet() => _multiSheet<OcrStatus>('Estado OCR',
      const [OcrStatus.done, OcrStatus.pending],
      (o) => o == OcrStatus.done ? 'Indexado' : 'Pendiente',
      _filter.ocrStatuses, (s) => _filter = _filter.copyWith(ocrStatuses: s));

  void _openDisplaySheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => ListView(
          shrinkWrap: true,
          children: [
            const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 4), child: Text('Tipo de vista', style: TextStyle(fontWeight: FontWeight.bold))),
            RadioGroup<ViewMode>(
              groupValue: _view,
              onChanged: (v) { if (v != null) { setState(() => _view = v); setSheet(() {}); } },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final v in ViewMode.values)
                    RadioListTile<ViewMode>(
                      value: v, dense: true,
                      title: Text(const {ViewMode.list: 'Lista', ViewMode.grid: 'Cuadrícula', ViewMode.compact: 'Compacta'}[v]!),
                    ),
                ],
              ),
            ),
            const Divider(),
            const Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 4), child: Text('Agrupar por', style: TextStyle(fontWeight: FontWeight.bold))),
            RadioGroup<GroupBy>(
              groupValue: _group,
              onChanged: (g) { if (g != null) { setState(() => _group = g); setSheet(() {}); } },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final g in GroupBy.values)
                    RadioListTile<GroupBy>(
                      value: g, dense: true,
                      title: Text(const {GroupBy.none: 'Sin agrupar', GroupBy.smart: '✨ Inteligente', GroupBy.date: 'Fecha', GroupBy.category: 'Categoría', GroupBy.source: 'Origen', GroupBy.type: 'Tipo', GroupBy.size: 'Tamaño'}[g]!),
                    ),
                ],
              ),
            ),
            const Divider(),
            const Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 4), child: Text('Ordenar por', style: TextStyle(fontWeight: FontWeight.bold))),
            RadioGroup<DocSort>(
              groupValue: _sort,
              onChanged: (s) { if (s != null) { setState(() => _sort = s); setSheet(() {}); _load(); } },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final s in DocSort.values)
                    RadioListTile<DocSort>(
                      value: s, dense: true,
                      title: Text(const {DocSort.recent: 'Más reciente', DocSort.oldest: 'Más antiguo', DocSort.nameAsc: 'Nombre A-Z', DocSort.nameDesc: 'Nombre Z-A', DocSort.sizeBig: 'Mayor tamaño', DocSort.sizeSmall: 'Menor tamaño'}[s]!),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- cuerpo: agrupado + tipo de vista ----
  Widget _buildBody() {
    final groups = _grouped();
    return CustomScrollView(
      slivers: [
        for (final entry in groups.entries) ...[
          if (_group != GroupBy.none)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Text('${entry.key} · ${entry.value.length}',
                    style: Theme.of(context).textTheme.labelMedium),
              ),
            ),
          _view == ViewMode.grid
              ? SliverPadding(
                  padding: const EdgeInsets.all(12),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2, childAspectRatio: 1.4, mainAxisSpacing: 10, crossAxisSpacing: 10),
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _gridTile(entry.value[i]),
                      childCount: entry.value.length,
                    ),
                  ),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _listTile(entry.value[i]),
                    childCount: entry.value.length,
                  ),
                ),
        ],
      ],
    );
  }

  Map<String, List<Document>> _grouped() {
    if (_group == GroupBy.none) return {'': _docs};
    final m = <String, List<Document>>{};
    for (final d in _docs) {
      final k = _groupKey(d);
      (m[k] ??= []).add(d);
    }
    return m;
  }

  String _groupKey(Document d) {
    switch (_group) {
      case GroupBy.category:
        return d.categoryId != null ? (_catNames[d.categoryId] ?? '—') : 'Sin categoría';
      case GroupBy.source:
        return d.source ?? 'Otros';
      case GroupBy.type:
        return _typeLabel(d);
      case GroupBy.size:
        final kb = d.sizeBytes / 1024;
        return kb > 1024 ? 'Pesados (>1 MB)' : kb > 100 ? 'Medianos' : 'Livianos';
      case GroupBy.date:
        return _ageBucket(d);
      case GroupBy.smart:
        if (d.favorite) return '⭐ Destacados';
        if (d.categoryId == null) return '🏷️ Sin clasificar';
        if (d.ocrStatus == OcrStatus.pending) return '⏳ Pendientes de OCR';
        if (_ageDays(d) <= 7) return '🕐 Recientes';
        if (d.sizeBytes > 1024 * 1024) return '📦 Pesados';
        return 'Otros';
      default:
        return '';
    }
  }

  int _ageDays(Document d) =>
      DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(d.modifiedAtMillis)).inDays;
  String _ageBucket(Document d) {
    final a = _ageDays(d);
    return a <= 1 ? 'Hoy' : a <= 7 ? 'Esta semana' : a <= 31 ? 'Este mes' : 'Anterior';
  }

  String _typeLabel(Document d) {
    final m = (d.mimeType ?? '').toLowerCase();
    if (m.contains('pdf')) return 'PDF';
    if (m.startsWith('image/')) return 'Imagen';
    if (m.contains('csv')) return 'CSV';
    return 'Texto';
  }

  Widget _leadingIcon(Document d) {
    final m = (d.mimeType ?? '').toLowerCase();
    final icon = m.contains('pdf')
        ? Icons.picture_as_pdf
        : m.startsWith('image/')
            ? Icons.image
            : Icons.insert_drive_file;
    return Icon(icon);
  }

  Widget _listTile(Document d) {
    final selected = _selected.contains(d.id);
    return ListTile(
      dense: _view == ViewMode.compact,
      selected: selected,
      leading: _selectMode
          ? Icon(selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? Theme.of(context).colorScheme.primary : null)
          : _leadingIcon(d),
      title: Row(children: [
        Expanded(child: Text(d.displayName, maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (d.favorite) const Icon(Icons.star, size: 14, color: Colors.amber),
      ]),
      subtitle: _view == ViewMode.compact
          ? null
          : Text([
              if (d.source != null) d.source!,
              if (d.categoryId != null) _catNames[d.categoryId] ?? '',
              if (d.ocrStatus == OcrStatus.pending) 'OCR pendiente',
              '${d.sizeBytes ~/ 1024} KB',
            ].where((s) => s.isNotEmpty).join(' · '),
              maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () => _selectMode ? _toggleSel(d.id!) : _openDoc(d),
      onLongPress: () => _selectMode ? null : _enterSelect(d.id!),
    );
  }

  Widget _gridTile(Document d) {
    final selected = _selected.contains(d.id);
    return InkWell(
      onTap: () => _selectMode ? _toggleSel(d.id!) : _openDoc(d),
      onLongPress: () => _selectMode ? null : _enterSelect(d.id!),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant),
          color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Center(child: _leadingIcon(d))),
            Row(children: [
              Expanded(child: Text(d.displayName, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
              if (d.favorite) const Icon(Icons.star, size: 13, color: Colors.amber),
            ]),
            Text('${d.source ?? ''} · ${d.sizeBytes ~/ 1024} KB',
                style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.folder_open, size: 64, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              Text('Todo tu trabajo, en un solo lugar',
                  style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                'Escanea el teléfono para encontrar tus documentos —incluso los de WhatsApp y descargas— o agrega archivos puntuales.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _openAddSheet, child: const Text('Agregar documentos')),
            ],
          ),
        ),
      );

  @override
  void dispose() {
    _indexer.dispose();
    super.dispose();
  }
}

/// Hoja de la papelera: restaurar o vaciar.
class _TrashSheet extends StatefulWidget {
  final VoidCallback onChanged;
  const _TrashSheet({required this.onChanged});
  @override
  State<_TrashSheet> createState() => _TrashSheetState();
}

class _TrashSheetState extends State<_TrashSheet> {
  final _db = DatabaseHelper.instance;
  List<Document> _docs = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final d = await _db.trashedDocuments();
    setState(() => _docs = d);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('Papelera',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('Quitar del índice no borra el archivo del teléfono.',
              style: TextStyle(fontSize: 12.5)),
        ),
        if (_docs.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('La papelera está vacía.')),
          )
        else ...[
          ..._docs.map((d) => ListTile(
                title: Text(d.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: TextButton(
                  onPressed: () async {
                    await _db.restore(d.id!);
                    _reload();
                  },
                  child: const Text('Restaurar'),
                ),
              )),
          Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton(
              onPressed: () async {
                await _db.emptyTrash();
                _reload();
              },
              child: const Text('Vaciar papelera'),
            ),
          ),
        ],
      ],
    );
  }
}
