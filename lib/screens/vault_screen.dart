import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/models.dart';

/// Bóveda: pantalla con candado por PIN. Si no hay PIN, pide crearlo; si lo
/// hay, pide ingresarlo. Tras desbloquear, lista los documentos ocultos.
/// El PIN se valida contra el hash guardado en la base (ver DatabaseHelper).
class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

enum _Stage { loading, setup, unlock, open }

class _VaultScreenState extends State<VaultScreen> {
  final _db = DatabaseHelper.instance;
  _Stage _stage = _Stage.loading;
  String _entry = '';
  String _error = '';
  List<Document> _docs = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final configured = await _db.isVaultConfigured();
    setState(() => _stage = configured ? _Stage.unlock : _Stage.setup);
  }

  Future<void> _onComplete() async {
    if (_stage == _Stage.setup) {
      await _db.setVaultPin(_entry);
      await _openVault();
    } else {
      final ok = await _db.verifyVaultPin(_entry);
      if (ok) {
        await _openVault();
      } else {
        setState(() {
          _error = 'Código incorrecto';
          _entry = '';
        });
      }
    }
  }

  Future<void> _openVault() async {
    final docs = await _db.vaultDocuments();
    setState(() {
      _stage = _Stage.open;
      _docs = docs;
      _entry = '';
      _error = '';
    });
  }

  void _press(String d) {
    if (_entry.length >= 4) return;
    setState(() {
      _entry += d;
      _error = '';
    });
    if (_entry.length == 4) _onComplete();
  }

  void _back() => setState(() => _entry = _entry.isEmpty ? '' : _entry.substring(0, _entry.length - 1));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bóveda')),
      body: switch (_stage) {
        _Stage.loading => const Center(child: CircularProgressIndicator()),
        _Stage.open => _buildList(),
        _ => _buildPinPad(),
      },
    );
  }

  Widget _buildPinPad() {
    final title =
        _stage == _Stage.setup ? 'Crea un código de 4 dígitos' : 'Ingresa tu código';
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.lock_outline, size: 40),
        const SizedBox(height: 12),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(4, (i) {
            final filled = i < _entry.length;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? Theme.of(context).colorScheme.primary : null,
                border: Border.all(color: Theme.of(context).colorScheme.outline, width: 2),
              ),
            );
          }),
        ),
        SizedBox(height: 20, child: Text(_error, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        _keypad(),
      ],
    );
  }

  Widget _keypad() {
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '<'];
    return SizedBox(
      width: 280,
      child: GridView.count(
        shrinkWrap: true,
        crossAxisCount: 3,
        childAspectRatio: 1.6,
        physics: const NeverScrollableScrollPhysics(),
        children: keys.map((k) {
          if (k.isEmpty) return const SizedBox();
          return InkWell(
            onTap: () => k == '<' ? _back() : _press(k),
            borderRadius: BorderRadius.circular(16),
            child: Center(
              child: k == '<'
                  ? const Icon(Icons.backspace_outlined)
                  : Text(k, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildList() {
    if (_docs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'La bóveda está vacía.\nUsa "Mover a la bóveda" en cualquier documento.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: _docs.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final d = _docs[i];
        return ListTile(
          leading: const Icon(Icons.lock),
          title: Text(d.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${d.sizeBytes ~/ 1024} KB'),
          trailing: TextButton(
            onPressed: () async {
              await _db.removeFromVault(d.id!);
              await _openVault();
            },
            child: const Text('Sacar'),
          ),
        );
      },
    );
  }
}
