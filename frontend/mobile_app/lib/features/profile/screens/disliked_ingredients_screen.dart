import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../profile_api.dart';
import '../recipes_api.dart';

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
  late final RecipesApi _recipesApi;

  List<dynamic> _items = [];
  bool _loading = true;
  String? _error;

  final _qCtrl = TextEditingController();
  List<String> _suggestions = [];
  bool _searching = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _recipesApi = RecipesApi(widget.client);
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _qCtrl.dispose();
    super.dispose();
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

  // ---------- UI-only normalization + dedupe ----------

  String _norm(String s) {
    var x = s.trim().toLowerCase();

    // "(...)" içini at
    x = x.replaceAll(RegExp(r'\([^)]*\)'), ' ');

    // noktalama/özel karakter -> boşluk
    x = x.replaceAll(
      RegExp(r'[^a-zçğıöşü0-9\s]+', caseSensitive: false),
      ' ',
    );

    // fazla boşluk
    x = x.replaceAll(RegExp(r'\s+'), ' ').trim();
    return x;
  }

  /// Kısa->uzun sıralar; kısa olan, uzun olanın içinde kelime sınırıyla geçiyorsa uzun olanı UI’dan eler.
  List<String> _dedupeByContainment(List<String> input) {
    final normMap = <String, String>{};
    for (final s in input) {
      final n = _norm(s);
      if (n.isNotEmpty) normMap[s] = n;
    }

    // aynı normalize olanları tekilleştir
    final byNorm = <String, String>{}; // norm -> original
    for (final e in normMap.entries) {
      byNorm.putIfAbsent(e.value, () => e.key);
    }

    final originals = byNorm.values.toList();

    // kısa -> uzun
    originals.sort(
          (a, b) => normMap[a]!.length.compareTo(normMap[b]!.length),
    );

    final kept = <String>[];

    for (final cand in originals) {
      final cNorm = normMap[cand]!;
      bool covered = false;

      for (final k in kept) {
        final kNorm = normMap[k]!;
        if (kNorm.isEmpty) continue;

        final pattern = RegExp(
          r'(^|\s)' + RegExp.escape(kNorm) + r'(\s|$)',
        );

        if (pattern.hasMatch(cNorm)) {
          covered = true;
          break;
        }
      }

      if (!covered) kept.add(cand);
    }

    return kept;
  }

  // ---------------------------------------------------

  void _triggerSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(v));
  }

  Future<void> _search(String q) async {
    final query = q.trim();
    if (query.length < 2) {
      if (!mounted) return;
      setState(() => _suggestions = []);
      return;
    }

    setState(() => _searching = true);
    try {
      final res = await _recipesApi.searchRecipeIngredients(query);
      if (!mounted) return;

      final deduped = _dedupeByContainment(res);
      setState(() => _suggestions = deduped);
    } catch (_) {
      if (!mounted) return;
      setState(() => _suggestions = []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _addSelected(String selectedName) async {
    final reasonCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Ekle: $selectedName'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(
            labelText: 'Sebep (opsiyonel)',
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

    try {
      await widget.api.addDislikedRawText(
        rawText: selectedName,
        reason: reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sevilmeyen besin eklendi. Tariflerde “$selectedName” içeren malzemeler daha az önerilecek.',
          ),
        ),
      );

      _qCtrl.clear();
      setState(() => _suggestions = []);
      _load();
    } on DioException catch (e) {
      if (!mounted) return;

      if (e.response?.statusCode == 409) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bu besin daha önce eklenmiş.')),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: ${e.message ?? e.toString()}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
    }
  }

  Future<void> _delete(int dislikedId, String displayName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Silme Onayı'),
        content: Text('“$displayName” kaydını silmek istiyor musunuz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await widget.api.deleteDisliked(dislikedId);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Kayıt silindi.')),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sevmediğim Besinler'),
        actions: [
          IconButton(
            tooltip: 'Yenile',
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
            ? Text('Error: $_error', style: TextStyle(color: cs.error))
            : Column(
          children: [
            TextField(
              controller: _qCtrl,
              decoration: InputDecoration(
                labelText: 'Tarif malzemesi ara (örn. Süt)',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searching
                    ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onChanged: _triggerSearch,
            ),
            const SizedBox(height: 10),

            if (!_searching && _qCtrl.text.trim().length >= 2 && _suggestions.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Sonuç bulunamadı.',
                  style: TextStyle(color: cs.error),
                ),
              ),

            if (_suggestions.isNotEmpty)
              Card(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final name = _suggestions[i];
                    return ListTile(
                      leading: const Icon(Icons.restaurant),
                      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => _addSelected(name),
                    );
                  },
                ),
              ),

            const SizedBox(height: 12),

            Expanded(
              child: _items.isEmpty
                  ? const Center(child: Text('Henüz eklenmiş besin yok.'))
                  : ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final it = _items[i] as Map;

                  final dislikedId = (it['id'] as num?)?.toInt() ?? 0;
                  final displayName = it['display_name']?.toString() ?? '-';
                  final reason = it['reason']?.toString();

                  return ListTile(
                    leading: const Icon(Icons.block),
                    title: Text(displayName),
                    subtitle: (reason != null && reason.trim().isNotEmpty)
                        ? Text(reason)
                        : null,
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: dislikedId == 0
                          ? null
                          : () => _delete(dislikedId, displayName),
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