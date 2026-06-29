import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/search_service.dart';
import 'document_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _search = SearchService();
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Document> _results = [];

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final res = await _search.search(q);
      if (mounted) setState(() => _results = res);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Buscar en nombres y contenido…',
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
        ),
      ),
      body: ListView.builder(
        itemCount: _results.length,
        itemBuilder: (_, i) {
          final d = _results[i];
          final snippet = (d.ocrText ?? '').trim();
          return ListTile(
            title: Text(d.displayName,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: snippet.isEmpty
                ? null
                : Text(snippet, maxLines: 2, overflow: TextOverflow.ellipsis),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DocumentDetailScreen(document: d),
              ),
            ),
          );
        },
      ),
    );
  }
}
