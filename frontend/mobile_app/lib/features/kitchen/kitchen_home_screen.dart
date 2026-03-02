// lib/features/kitchen/kitchen_home_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import 'kitchen_api.dart';
import 'shopping_list_screen.dart';
import 'pantry_list_screen.dart';

class KitchenHomeScreen extends StatefulWidget {
  final KitchenApi api;
  const KitchenHomeScreen({super.key, required this.api});

  @override
  State<KitchenHomeScreen> createState() => _KitchenHomeScreenState();
}

class _KitchenHomeScreenState extends State<KitchenHomeScreen> {
  bool _loading = true;
  List<dynamic> _pantry = [];
  List<dynamic> _alerts = [];

  // suggestions (recipes.malzemeler_json -> Malzeme_Adi)
  final _nameCtrl = TextEditingController();
  List<String> _suggestions = [];
  bool _searching = false;
  Timer? _debounce;

  static const double _eggGramPerPiece = 50.0; // ✅ sadece yumurta

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final pantry = await widget.api.getPantry();
      final alerts = await widget.api.getPantryAlerts();
      setState(() {
        _pantry = pantry;
        _alerts = alerts;
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  String _norm(String s) {
    var x = s.trim().toLowerCase();
    x = x.replaceAll(RegExp(r'\([^)]*\)'), ' ');
    x = x.replaceAll(RegExp(r'[^a-zçğıöşü0-9\s]+', caseSensitive: false), ' ');
    x = x.replaceAll(RegExp(r'\s+'), ' ').trim();
    return x;
  }

  bool _isEggName(String name) {
    final n = _norm(name);
    // “yumurta” geçen her şeyi yumurta say
    return n.contains('yumurta');
  }

  List<String> _dedupeByContainment(List<String> input) {
    final normMap = <String, String>{};
    for (final s in input) {
      final n = _norm(s);
      if (n.isNotEmpty) normMap[s] = n;
    }

    final byNorm = <String, String>{}; // norm -> original
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

  void _triggerSuggest(String v, void Function(void Function()) setLocal) {
    _debounce?.cancel();

    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final q = v.trim();
      if (q.length < 2) {
        setLocal(() {
          _suggestions = [];
          _searching = false;
        });
        return;
      }

      setLocal(() => _searching = true);

      try {
        final res = await widget.api.searchRecipeIngredients(q);
        final deduped = _dedupeByContainment(res);
        setLocal(() => _suggestions = deduped);
      } catch (_) {
        setLocal(() => _suggestions = []);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Malzeme önerileri alınamadı (API).')),
          );
        }
      } finally {
        setLocal(() => _searching = false);
      }
    });
  }

  String _fmtQty(dynamic v) {
    final d = (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '0') ?? 0;
    if ((d - d.round()).abs() < 0.000001) return d.round().toString();
    return d.toStringAsFixed(2);
  }

  Future<void> _openAddDialog({Map<String, dynamic>? existing}) async {
    _nameCtrl.text = existing?['ingredient_id']?.toString() ?? '';
    _suggestions = [];
    _searching = false;

    final qtyCtrl = TextEditingController(text: existing?['quantity']?.toString() ?? '0');
    final lowCtrl = TextEditingController(text: existing?['low_threshold']?.toString() ?? '');

    // mevcut unit
    String unitValue = (existing?['unit']?.toString() == 'ml') ? 'ml' : 'g';

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final isEgg = _isEggName(_nameCtrl.text);

            // ✅ sadece yumurta için "adet" seçeneği göster
            final unitItems = <DropdownMenuItem<String>>[
              const DropdownMenuItem(value: 'g', child: Text('g')),
              const DropdownMenuItem(value: 'ml', child: Text('ml')),
              if (isEgg) const DropdownMenuItem(value: 'adet', child: Text('adet')),
            ];

            // yumurta değilken unitValue "adet" kalmışsa düzelt
            if (!isEgg && unitValue == 'adet') {
              unitValue = 'g';
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      existing == null ? 'Stok Ekle' : 'Stoğu Güncelle',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 14),

                    TextField(
                      controller: _nameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Malzeme',
                        prefixIcon: const Icon(Icons.search),
                        helperText: 'Listeden seçebilir ya da kendi malzemenizi yazabilirsiniz.',
                        suffixIcon: _searching
                            ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                            : null,
                      ),
                      onChanged: (v) {
                        setLocal(() {});
                        _triggerSuggest(v, setLocal);
                      },
                    ),

                    const SizedBox(height: 10),

                    if (_nameCtrl.text.trim().length >= 2 && !_searching && _suggestions.isNotEmpty)
                      Card(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _suggestions.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final s = _suggestions[i];
                            return ListTile(
                              leading: const Icon(Icons.kitchen_outlined),
                              title: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis),
                              onTap: () {
                                setLocal(() {
                                  _nameCtrl.text = s;
                                  _suggestions = [];
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
                        labelText: 'Miktar',
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
                      items: unitItems,
                      onChanged: (v) {
                        if (v == null) return;
                        setLocal(() => unitValue = v);
                      },
                    ),

                    if (isEgg && unitValue == 'adet')
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('1 adet yumurta = 50g olarak kaydedilir.', style: TextStyle(color: Colors.black54)),
                        ),
                      ),

                    const SizedBox(height: 12),

                    TextField(
                      controller: lowCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Uyarı eşiği',
                        helperText: 'Miktar bunun altına inince uyarı verir.',
                        prefixIcon: Icon(Icons.warning_amber_rounded),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),

                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pop(context, true),
                        icon: const Icon(Icons.check),
                        label: const Text('Kaydet'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (ok != true) return;

    final ingredientKey = _nameCtrl.text.trim();
    if (ingredientKey.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Malzeme adı boş olamaz.')));
      return;
    }

    double qty = double.tryParse(qtyCtrl.text.trim()) ?? 0;
    final low = lowCtrl.text.trim().isEmpty ? null : double.tryParse(lowCtrl.text.trim());

    // ✅ sadece yumurta + adet => gram’a çevir
    String sendUnit = unitValue;
    if (_isEggName(ingredientKey) && unitValue == 'adet') {
      qty = qty * _eggGramPerPiece;
      sendUnit = 'g';
    }

    await widget.api.upsertPantry(
      ingredientId: ingredientKey,
      quantity: qty,
      unit: sendUnit,
      lowThreshold: low,
      mode: existing == null ? 'add' : 'set', // ✅ aynı ürün eklenince biriktirme
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stok güncellendi')));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final consumed = 260.0;
    final target = 2300.0;
    final progress = (target <= 0) ? 0.0 : (consumed / target).clamp(0.0, 1.0);

    final preview = _pantry.take(3).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mutfak Yönetimi'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.surface,
        elevation: 2,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.backgroundTop,
              AppColors.backgroundBottom,
            ],
          ),
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset(
                        'assets/images/kitchen_hero.png',
                        height: 140,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(height: 80),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      elevation: 4,
                      shadowColor: Colors.black.withOpacity(0.08),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            const Icon(Icons.local_fire_department_outlined),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Günlük Kalori',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w900),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                      '${consumed.toInt()} / ${target.toInt()} kcal'),
                                  const SizedBox(height: 10),
                                  LinearProgressIndicator(value: progress),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      elevation: 4,
                      shadowColor: Colors.black.withOpacity(0.08),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.kitchen_outlined),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Mutfak Stok Yönetimi',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => _openAddDialog(),
                                  icon:
                                      const Icon(Icons.add_circle_outline),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Hangi besinden ne kadar var kayıt edilir.',
                              style: TextStyle(color: Colors.black54),
                            ),
                            const SizedBox(height: 12),
                            if (_pantry.isEmpty)
                              const Padding(
                                padding:
                                    EdgeInsets.symmetric(vertical: 18),
                                child: Center(
                                  child:
                                      Text('Henüz stok yok. + ile ekle.'),
                                ),
                              )
                            else
                              Column(
                                children: preview.map((e) {
                                  final m =
                                      e as Map<String, dynamic>;
                                  final name = m['ingredient_id']
                                          ?.toString() ??
                                      '-';
                                  final qty =
                                      _fmtQty(m['quantity']);
                                  final unit =
                                      m['unit']?.toString() ?? 'g';
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(
                                        Icons.check_circle_outline),
                                    title: Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight:
                                              FontWeight.w800),
                                    ),
                                    subtitle:
                                        Text('Miktar: $qty $unit'),
                                    trailing: IconButton(
                                      icon: const Icon(
                                          Icons.edit_outlined),
                                      onPressed: () => _openAddDialog(
                                          existing: m),
                                    ),
                                  );
                                }).toList(),
                              ),
                            if (_pantry.length > 3)
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 6),
                                child: Text(
                                  '+ ${_pantry.length - 3} ürün daha',
                                  style: const TextStyle(
                                      color: Colors.black54),
                                ),
                              ),
                            if (_pantry.isNotEmpty)
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              PantryListScreen(
                                            api: widget.api,
                                          ),
                                        ),
                                      ).then((_) => _load());
                                    },
                                    icon: const Icon(Icons.list),
                                    label:
                                        const Text('Tümünü Gör'),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () => _openAddDialog(),
                                icon: const Icon(Icons.add),
                                label: const Text('Stok Ekle'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_alerts.isNotEmpty)
                      Card(
                        elevation: 4,
                        shadowColor: Colors.black.withOpacity(0.08),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              const Icon(Icons
                                  .warning_amber_rounded),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '${_alerts.length} ürün kritik/bitti. Listeye eklendi.',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800),
                                ),
                              ),
                              TextButton(
                                onPressed: () async {
                                  await widget.api
                                      .refreshShoppingFromPantry();
                                  if (!mounted) return;
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          ShoppingListScreen(
                                              api: widget.api),
                                    ),
                                  );
                                },
                                child: const Text('Göster'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Card(
                      elevation: 4,
                      shadowColor: Colors.black.withOpacity(0.08),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                    Icons.shopping_cart_outlined),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Alışveriş Listesi',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () async {
                                    await widget.api
                                        .refreshShoppingFromPantry();
                                    if (!mounted) return;
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            ShoppingListScreen(
                                                api: widget.api),
                                      ),
                                    );
                                  },
                                  icon: const Icon(
                                      Icons.open_in_new),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Azalan ürünler veritabanından otomatik çekilir.',
                              style: TextStyle(
                                  color: Colors.black54),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  await widget.api
                                      .refreshShoppingFromPantry();
                                  if (!mounted) return;
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          ShoppingListScreen(
                                              api: widget.api),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.list_alt),
                                label: const Text(
                                    'Market Listesini Gör'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}