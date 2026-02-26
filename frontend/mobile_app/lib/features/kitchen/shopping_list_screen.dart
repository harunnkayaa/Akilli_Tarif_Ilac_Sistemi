import 'dart:async';
import 'package:flutter/material.dart';
import 'kitchen_api.dart';

class ShoppingListScreen extends StatefulWidget {
  final KitchenApi api;
  const ShoppingListScreen({super.key, required this.api});

  @override
  State<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends State<ShoppingListScreen> {
  bool _loading = true;
  List<dynamic> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await widget.api.getShoppingList();
      setState(() => _items = items);
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _openManualAdd() async {
    // ignore: avoid_print
    print('[SHOPPING] openManualAdd pressed');

    final nameCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    String unitValue = 'g';

    List<String> suggestions = [];
    bool searching = false;
    Timer? debounce;

    String norm(String s) {
      var x = s.trim().toLowerCase();
      x = x.replaceAll(RegExp(r'\([^)]*\)'), ' ');
      x = x.replaceAll(RegExp(r'[^a-zçğıöşü0-9\s]+', caseSensitive: false), ' ');
      x = x.replaceAll(RegExp(r'\s+'), ' ').trim();
      return x;
    }

    List<String> dedupeByContainment(List<String> input) {
      final normMap = <String, String>{};
      for (final s in input) {
        final n = norm(s);
        if (n.isNotEmpty) normMap[s] = n;
      }

      final byNorm = <String, String>{};
      for (final e in normMap.entries) {
        byNorm.putIfAbsent(e.value, () => e.key);
      }

      final originals = byNorm.values.toList();
      originals.sort((a, b) => normMap[a]!.length.compareTo(normMap[b]!.length));

      final kept = <String>[];
      for (final cand in originals) {
        final cNorm = normMap[cand]!;
        bool covered = false;
        for (final k in kept) {
          final kNorm = normMap[k]!;
          final pattern = RegExp(r'(^|\s)' + RegExp.escape(kNorm) + r'(\s|$)');
          if (pattern.hasMatch(cNorm)) {
            covered = true;
            break;
          }
        }
        if (!covered) kept.add(cand);
      }
      return kept;
    }

    void triggerSuggest(String v, void Function(void Function()) setLocal) {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 250), () async {
        final q = v.trim();
        if (q.length < 2) {
          setLocal(() {
            suggestions = [];
            searching = false;
          });
          return;
        }

        setLocal(() => searching = true);

        try {
          // ignore: avoid_print
          print('[SHOPPING][SUGGEST] query=$q');

          final res = await widget.api.searchRecipeIngredients(q);

          // ignore: avoid_print
          print('[SHOPPING][SUGGEST] rawCount=${res.length}');

          setLocal(() => suggestions = dedupeByContainment(res));
        } catch (e) {
          // ignore: avoid_print
          print('[SHOPPING][SUGGEST][ERR] $e');
          setLocal(() => suggestions = []);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Ürün önerileri alınamadı (API).')),
            );
          }
        } finally {
          setLocal(() => searching = false);
        }
      });
    }

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Listeye Ekle', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),

                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Ürün',
                    prefixIcon: const Icon(Icons.search),
                    helperText: 'Listeden seçebilir ya da kendi ürününüzü yazabilirsiniz.',
                    suffixIcon: searching
                        ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                        : null,
                  ),
                  onChanged: (v) {
                    setLocal(() {}); // ✅ UI anında rebuild
                    triggerSuggest(v, setLocal);
                  },
                ),

                const SizedBox(height: 10),

                if (nameCtrl.text.trim().length >= 2 && !searching && suggestions.isNotEmpty)
                  Card(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: suggestions.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final s = suggestions[i];
                        return ListTile(
                          leading: const Icon(Icons.shopping_bag_outlined),
                          title: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () {
                            setLocal(() {
                              nameCtrl.text = s;
                              suggestions = [];
                            });
                          },
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 12),

                TextField(
                  controller: qtyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Hedef miktar (opsiyonel)',
                    prefixIcon: Icon(Icons.scale_outlined),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),

                const SizedBox(height: 12),

                DropdownButtonFormField<String>(
                  value: unitValue,
                  decoration: const InputDecoration(
                    labelText: 'Birim',
                    prefixIcon: Icon(Icons.straighten_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'g', child: Text('g')),
                    DropdownMenuItem(value: 'ml', child: Text('ml')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setLocal(() => unitValue = v);
                  },
                ),

                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Ekle'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    debounce?.cancel();
    if (ok != true) return;

    final text = nameCtrl.text.trim();
    if (text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ürün adı boş olamaz.')));
      return;
    }

    final qty = qtyCtrl.text.trim().isEmpty ? null : double.tryParse(qtyCtrl.text.trim());

    await widget.api.addManualShoppingItem(
      itemText: text,
      targetQty: qty,
      unit: unitValue,
    );

    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alışveriş Listesi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.autorenew),
            onPressed: () async {
              await widget.api.refreshShoppingFromPantry();
              await _load();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openManualAdd,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _load,
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _items.length,
          itemBuilder: (_, i) {
            final m = _items[i] as Map<String, dynamic>;
            final id = m['item_id'].toString();
            final checked = m['is_checked'] == true;
            final ingredientId = m['ingredient_id']?.toString();
            final itemText = m['item_text']?.toString();
            final title = ingredientId ?? itemText ?? '—';
            final targetQty = m['target_qty'];
            final unit = m['unit'];

            return Card(
              child: ListTile(
                leading: Checkbox(
                  value: checked,
                  onChanged: (v) async {
                    await widget.api.setShoppingChecked(id, v == true);
                    await _load();
                  },
                ),
                title: Text(
                  title,
                  style: TextStyle(
                    decoration: checked ? TextDecoration.lineThrough : null,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text('Hedef: ${targetQty ?? "-"} ${unit ?? ""}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await widget.api.deleteShoppingItem(id);
                    await _load();
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}