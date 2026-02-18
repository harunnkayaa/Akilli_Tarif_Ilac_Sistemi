import 'package:flutter/material.dart';
import '../../../core/api_client.dart';
import '../ingredients_api.dart';
import '../profile_api.dart';

class DislikedIngredientsScreen extends StatefulWidget {
  final ProfileApi api;
  final ApiClient client;

  const DislikedIngredientsScreen({
    super.key,
    required this.api,
    required this.client,
  });

  @override
  State<DislikedIngredientsScreen> createState() =>
      _DislikedIngredientsScreenState();
}

class _DislikedIngredientsScreenState extends State<DislikedIngredientsScreen> {
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.api.listDisliked();
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
    final query = q.trim();
    if (query.length < 2) {
      setState(() => _suggestions = []);
      return;
    }

    setState(() => _searching = true);
    try {
      final res = await _ingApi.search(query);
      if (!mounted) return;
      setState(() => _suggestions = res);
    } catch (_) {
      // sessiz geç
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _addBySelection(Map<String, dynamic> ing) async {
    final reasonCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Ekle: ${ing['canonical_name_tr']}'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(
            labelText: 'Reason (opsiyonel)',
            hintText: 'Örn: tadını sevmiyorum',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ekle'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    await widget.api.addDisliked(
      ingredientId: ing['id'].toString(),
      reason: reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
    );

    _qCtrl.clear();
    setState(() => _suggestions = []);
    _load();
  }

  Future<void> _delete(String ingredientId) async {
    await widget.api.deleteDisliked(ingredientId);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sevmediğim Besinler'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
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
                labelText: 'Besin ara (örn. Süt, Yumurta)',
                suffixIcon: _searching
                    ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
                )
                    : const Icon(Icons.search),
              ),
              onChanged: _search,
            ),
            const SizedBox(height: 8),

            if (_suggestions.isNotEmpty)
              Card(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, __) =>
                  const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final ing = _suggestions[i];
                    return ListTile(
                      title: Text(
                        ing['canonical_name_tr']?.toString() ?? '-',
                      ),
                      subtitle: Text('id: ${ing['id']}'),
                      onTap: () => _addBySelection(ing),
                    );
                  },
                ),
              ),

            const SizedBox(height: 12),

            Expanded(
              child: _items.isEmpty
                  ? const Center(
                child: Text('Henüz eklenmiş besin yok.'),
              )
                  : ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, __) =>
                const Divider(height: 1),
                itemBuilder: (_, i) {
                  final it = _items[i] as Map;
                  final ingredientId =
                      it['ingredient_id']?.toString() ?? '';
                  final display = it['ingredient_name']
                      ?.toString() ??
                      ingredientId;

                  final reason =
                      it['reason']?.toString() ?? '';

                  return ListTile(
                    leading: const Icon(Icons.block),
                    title: Text(display),
                    subtitle: reason.isEmpty
                        ? null
                        : Text(reason),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: ingredientId.isEmpty
                          ? null
                          : () => _delete(ingredientId),
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
