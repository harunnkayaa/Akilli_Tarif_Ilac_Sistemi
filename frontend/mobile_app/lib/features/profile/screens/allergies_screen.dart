import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../core/api_client.dart';
import '../profile_api.dart';
import '../recipes_api.dart';

class AllergiesScreen extends StatefulWidget {
  final ProfileApi api;
  final ApiClient client;

  const AllergiesScreen({super.key, required this.api, required this.client});

  @override
  State<AllergiesScreen> createState() => _AllergiesScreenState();
}

class _AllergiesScreenState extends State<AllergiesScreen> {
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

  // ---------- NEW: Normalization + Dedupe (UI only) ----------

  String _norm(String s) {
    var x = s.trim().toLowerCase();

    // parantez içlerini at: "Enginar (haşlanmış)" -> "enginar"
    x = x.replaceAll(RegExp(r'\([^)]*\)'), ' ');

    // noktalama/özel karakterleri boşluğa çevir
    x = x.replaceAll(
      RegExp(r'[^a-zçğıöşü0-9\s]+', caseSensitive: false),
      ' ',
    );

    // fazla boşlukları temizle
    x = x.replaceAll(RegExp(r'\s+'), ' ').trim();

    return x;
  }

  /// UI için: kısa->uzun sıralar, kısa olan uzun olanın içinde (kelime sınırıyla) geçiyorsa uzun olanı eler.
  /// Dönen liste: ORİJİNAL metinler (göstermek için), dedupe edilmiş.
  List<String> _dedupeByContainment(List<String> input) {
    // normalize map (orijinal -> norm)
    final normMap = <String, String>{};
    for (final s in input) {
      final n = _norm(s);
      if (n.isNotEmpty) normMap[s] = n;
    }

    // aynı normalize olanları tekilleştir (ilk gördüğünü al)
    final byNorm = <String, String>{}; // norm -> original
    for (final e in normMap.entries) {
      byNorm.putIfAbsent(e.value, () => e.key);
    }

    final originals = byNorm.values.toList();

    // kısa -> uzun sırala (norm uzunluğuna göre)
    originals.sort(
          (a, b) => normMap[a]!.length.compareTo(normMap[b]!.length),
    );

    final kept = <String>[];

    for (final cand in originals) {
      final cNorm = normMap[cand]!;
      bool coveredByShorter = false;

      // kept listesi zaten daha kısa/eşit olanlardan oluşuyor
      for (final k in kept) {
        final kNorm = normMap[k]!;
        if (kNorm.isEmpty) continue;

        // kelime sınırıyla içerme: "enginar" -> "enginar kalbi" evet
        final pattern = RegExp(
          r'(^|\s)' + RegExp.escape(kNorm) + r'(\s|$)',
        );

        if (pattern.hasMatch(cNorm)) {
          coveredByShorter = true;
          break;
        }
      }

      if (!coveredByShorter) kept.add(cand);
    }

    return kept;
  }

  // ----------------------------------------------------------

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

      // NEW: only for UI suggestions
      final deduped = _dedupeByContainment(res);

      setState(() => _suggestions = deduped);
    } catch (_) {
      // UI'ı kilitleme
      if (!mounted) return;
      setState(() => _suggestions = []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _addSelected(String selectedName) async {
    final reactionCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Ekle: $selectedName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: reactionCtrl,
              decoration: const InputDecoration(labelText: 'Reaksiyon (opsiyonel)'),
            ),
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(labelText: 'Not (opsiyonel)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ekle')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      // Tarif malzemesi modunda ekliyoruz: raw_text
      await widget.api.addAllergyRawText(
        rawText: selectedName,
        reaction: reactionCtrl.text.trim().isEmpty ? null : reactionCtrl.text.trim(),
        notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Alerji başarıyla eklendi. Tariflerde “$selectedName” içeren malzemeler önerilmeyecek.'),
        ),
      );

      _qCtrl.clear();
      setState(() => _suggestions = []);
      _load();
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 409) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bu malzeme daha önce eklenmiş.')),
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

  Future<void> _delete(int allergyId, String displayName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Silme Onayı'),
        content: Text('“$displayName” kaydını silmek istiyor musunuz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sil')),
        ],
      ),
    );

    if (confirm != true) return;

    await widget.api.deleteAllergy(allergyId);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Alerji silindi.')),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerjiler'),
        actions: [
          IconButton(
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
                  ? const Center(child: Text('Henüz eklenmiş alerji yok.'))
                  : ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final it = _items[i] as Map;
                  final id = (it['id'] as num).toInt();
                  final displayName = it['display_name']?.toString() ?? '-';
                  final reaction = it['reaction']?.toString();

                  return ListTile(
                    leading: const Icon(Icons.warning_amber),
                    title: Text(displayName),
                    subtitle: (reaction != null && reaction.trim().isNotEmpty)
                        ? Text(reaction)
                        : null,
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => _delete(id, displayName),
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