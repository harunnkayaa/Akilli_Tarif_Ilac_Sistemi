import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../core/api_client.dart';
import '../ingredients_api.dart';
import '../profile_api.dart';

class AllergiesScreen extends StatefulWidget {
  final ProfileApi api;
  final ApiClient client;

  const AllergiesScreen({super.key, required this.api, required this.client});

  @override
  State<AllergiesScreen> createState() => _AllergiesScreenState();
}

class _AllergiesScreenState extends State<AllergiesScreen> {
  late final IngredientsApi _ingApi;

  List<dynamic> _items = [];
  bool _loading = true;
  String? _error;

  final _qCtrl = TextEditingController();
  List<Map<String, dynamic>> _suggestions = [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _ingApi = IngredientsApi(widget.client);
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final items = await widget.api.listAllergies();
      if (!mounted) return;
      setState(() => _items = items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _search(String q) async {
    if (q.trim().length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final res = await _ingApi.search(q.trim());
      if (!mounted) return;
      setState(() => _suggestions = res);
    } catch (_) {
      // sessiz geç (UI'ı kilitleme)
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _addBySelection(Map<String, dynamic> ing) async {
    final reactionCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Ekle: ${ing['canonical_name_tr']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: reactionCtrl, decoration: const InputDecoration(labelText: 'Reaction (opsiyonel)')),
            TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes (opsiyonel)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ekle')),
        ],
      ),
    );

    if (ok != true) return;

    await widget.api.addAllergy(
      ingredientId: ing['id'].toString(),
      reaction: reactionCtrl.text.trim().isEmpty ? null : reactionCtrl.text.trim(),
      notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
    );

    _qCtrl.clear();
    setState(() => _suggestions = []);
    _load();
  }

  Future<void> _delete(String ingredientId) async {
    await widget.api.deleteAllergy(ingredientId);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alerjiler')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Text('Error: $_error')
            : Column(
          children: [
            TextField(
              controller: _qCtrl,
              decoration: InputDecoration(
                labelText: 'Besin ara (örn. Süt)',
                suffixIcon: _searching ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                ) : const Icon(Icons.search),
              ),
              onChanged: _search,
            ),
            const SizedBox(height: 8),
            if (_suggestions.isNotEmpty)
              Card(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final ing = _suggestions[i];
                    return ListTile(
                      title: Text(ing['canonical_name_tr']?.toString() ?? '-'),
                      subtitle: Text('id: ${ing['id']}'),
                      onTap: () => _addBySelection(ing),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final it = _items[i] as Map;
                  final ingredientId = it['ingredient_id']?.toString() ?? '';
                  final display = it['ingredient_name']?.toString() ?? ingredientId; // backend isterse döner
                  return ListTile(
                    leading: const Icon(Icons.warning_amber),
                    title: Text(display),
                    subtitle: Text(it['reaction']?.toString() ?? ''),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: ingredientId.isEmpty ? null : () => _delete(ingredientId),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
