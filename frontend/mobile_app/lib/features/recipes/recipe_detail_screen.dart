import 'package:flutter/material.dart';

import '../profile/recipes_api.dart';

class RecipeDetailScreen extends StatefulWidget {
  final RecipesApi api;
  final String recipeId;
  final String initialTitle;
  /// 1 = stok olmadan (partial stock allowed), 2 = stoka göre (show add-pantry popup if missing)
  final int initialMode;

  const RecipeDetailScreen({
    super.key,
    required this.api,
    required this.recipeId,
    required this.initialTitle,
    this.initialMode = 1,
  });

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  RecipeDetail? _detail;
  bool _loading = true;
  String? _error;
  bool _cooking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await widget.api.getRecipeDetail(widget.recipeId);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Tarif detayı alınamadı. Lütfen tekrar deneyin.';
        _loading = false;
      });
    }
  }

  Future<void> _handleCook({List<Map<String, dynamic>>? addPantry}) async {
    if (_cooking) return;
    final allowPartialStock = widget.initialMode == 1;
    setState(() {
      _cooking = true;
    });
    try {
      final result = await widget.api.cookRecipe(
        recipeId: widget.recipeId,
        allowPartialStock: allowPartialStock,
        addPantry: addPantry,
      );
      if (!mounted) return;
      setState(() {
        _cooking = false;
      });

      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tarif kaydedildi. Günlük besin değerleriniz güncellendi.'),
          ),
        );
        return;
      }

      final missing = result.missing;
      if (widget.initialMode == 2 &&
          missing != null &&
          missing.isNotEmpty &&
          addPantry == null) {
        _showAddPantryDialog(missing);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.error ??
                'Tarif pişirilirken bir sorun oluştu. Lütfen tekrar deneyin.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cooking = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tarif pişirilirken bir hata oluştu.'),
        ),
      );
    }
  }

  void _showAddPantryDialog(List<String> missing) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _AddPantryDialog(
        missing: missing,
        onSave: (addPantry) {
          Navigator.of(ctx).pop();
          if (addPantry != null && addPantry.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _handleCook(addPantry: addPantry);
            });
          }
        },
        onCancel: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _detail?.title.isNotEmpty == true ? _detail!.title : widget.initialTitle;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Tekrar dene'),
                        ),
                      ],
                    ),
                  ),
                )
              : _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final d = _detail!;
    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (d.imageUrl != null && d.imageUrl!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                d.imageUrl!,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 200,
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  alignment: Alignment.center,
                  child: const Icon(Icons.restaurant, size: 48),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            d.title,
            style: textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (d.category != null && d.category!.isNotEmpty)
                Chip(
                  label: Text(d.category!),
                  visualDensity: VisualDensity.compact,
                ),
              if (d.servings != null && d.servings! > 0)
                Chip(
                  label: Text('${d.servings} porsiyon'),
                  visualDensity: VisualDensity.compact,
                ),
              if (d.caloriesPerServingKcal != null)
                Chip(
                  label: Text('${d.caloriesPerServingKcal!.round()} kcal / porsiyon'),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Malzemeler',
            style: textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (d.ingredients.isEmpty)
            Text(
              'Bu tarif için malzeme listesi bulunamadı.',
              style: textTheme.bodyMedium,
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: d.ingredients.map((ing) {
                final parts = <String>[];
                if (ing.displayAmount != null && ing.displayAmount!.isNotEmpty) {
                  parts.add(ing.displayAmount!);
                } else if (ing.amount != null) {
                  final unit = ing.unit ?? '';
                  final numeric = ing.amount!
                      .toStringAsFixed(2)
                      .replaceAll(RegExp(r'\.0+$'), '');
                  parts.add('$numeric $unit'.trim());
                }
                parts.add(ing.name);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('• ${parts.where((p) => p.isNotEmpty).join(' ')}'),
                );
              }).toList(),
            ),
          const SizedBox(height: 16),
          Text(
            'Yapılışı',
            style: textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            (d.steps != null && d.steps!.trim().isNotEmpty)
                ? d.steps!.trim()
                : 'Bu tarif için hazırlanış adımları metni bulunamadı.',
            style: textTheme.bodyMedium,
          ),
          if (d.sourceUrl != null && d.sourceUrl!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Kaynak: ${d.sourceUrl}',
              style: textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _cooking ? null : _handleCook,
              icon: const Icon(Icons.playlist_add_check),
              label: Text(_cooking ? 'İşleniyor...' : 'Bu tarifi yap'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Eksik malzemeleri stoka ekleme dialog'u. Controller'lar bu widget'ın State'inde tutulur ve
/// sadece dialog kapatıldığında dispose edilir; böylece _dependents.isEmpty hatası oluşmaz.
class _AddPantryDialog extends StatefulWidget {
  final List<String> missing;
  final void Function(List<Map<String, dynamic>>? addPantry) onSave;
  final VoidCallback onCancel;

  const _AddPantryDialog({
    required this.missing,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<_AddPantryDialog> createState() => _AddPantryDialogState();
}

class _AddPantryDialogState extends State<_AddPantryDialog> {
  late final List<TextEditingController> _qtyControllers;
  late final List<TextEditingController> _thresholdControllers;

  @override
  void initState() {
    super.initState();
    _qtyControllers = List.generate(
      widget.missing.length,
      (_) => TextEditingController(text: ''),
    );
    _thresholdControllers = List.generate(
      widget.missing.length,
      (_) => TextEditingController(text: ''),
    );
  }

  @override
  void dispose() {
    for (final c in _qtyControllers) {
      c.dispose();
    }
    for (final c in _thresholdControllers) {
      c.dispose();
    }
    super.dispose();
  }

  static double? _parseOptional(String s) {
    final t = s.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  void _onSave() {
    final addPantry = <Map<String, dynamic>>[];
    for (var i = 0; i < widget.missing.length; i++) {
      final qty = _parseOptional(_qtyControllers[i].text) ?? 0;
      if (qty <= 0) continue;
      final entry = <String, dynamic>{
        'ingredient_id': widget.missing[i],
        'quantity': qty,
      };
      final threshold = _parseOptional(_thresholdControllers[i].text);
      if (threshold != null && threshold >= 0) {
        entry['low_threshold'] = threshold;
      }
      addPantry.add(entry);
    }
    widget.onSave(addPantry.isNotEmpty ? addPantry : null);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Eksik malzemeleri stoka ekle'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Aşağıdaki malzemeler stokta yok. Kaç gram ekleyeceksiniz? İsterseniz eşik değeri (gram) girebilirsiniz; stok bu değerin altına düşünce uyarı verilir.',
            ),
            const SizedBox(height: 12),
            ...List.generate(widget.missing.length, (i) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.missing[i],
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _qtyControllers[i],
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Gram',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _thresholdControllers[i],
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Eşik (gram)',
                              hintText: 'Opsiyonel',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: widget.onCancel,
          child: const Text('İptal'),
        ),
        FilledButton(
          onPressed: _onSave,
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}

