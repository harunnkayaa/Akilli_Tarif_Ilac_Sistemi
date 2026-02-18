import 'dart:async';
import 'package:flutter/material.dart';
import '../profile_api.dart';

class DiseasesScreen extends StatefulWidget {
  final ProfileApi api;
  const DiseasesScreen({super.key, required this.api});

  @override
  State<DiseasesScreen> createState() => _DiseasesScreenState();
}

class _DiseasesScreenState extends State<DiseasesScreen> {
  List<dynamic> _items = [];
  bool _loading = true;
  String? _error;

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
      final items = await widget.api.listDiseases();
      if (!mounted) return;
      setState(() => _items = items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showAddFailedDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hastalık Eklenemedi'),
        content: const Text(
          'Girilen hastalık, Dünya Sağlık Örgütü (WHO) tarafından tanımlanan '
              'besin sınırları kapsamında sistemimizde yer almamaktadır.\n\n'
              'Tarif önerilerinin doğru hesaplanabilmesi için yalnızca tanımlı '
              'hastalıklar eklenebilir.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  Future<void> _add() async {
    final nameCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        List<String> suggestions = [];
        bool searching = false;
        Timer? debounce;

        Future<void> runSearch(String q, void Function(void Function()) setLocal) async {
          final query = q.trim();
          if (query.length < 2) {
            setLocal(() {
              suggestions = [];
              searching = false;
            });
            return;
          }

          setLocal(() => searching = true);
          try {
            final res = await widget.api.searchKnownDiseases(query);
            setLocal(() => suggestions = res);
          } catch (_) {
            setLocal(() => suggestions = []);
          } finally {
            setLocal(() => searching = false);
          }
        }

        return StatefulBuilder(
          builder: (ctx, setLocal) {
            void triggerSearch(String v) {
              debounce?.cancel();
              debounce = Timer(const Duration(milliseconds: 250), () {
                runSearch(v, setLocal);
              });
            }

            return AlertDialog(
              title: const Text('Hastalık Ekle'),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 360,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          labelText: 'Hastalık',
                          hintText: 'örn: Hipertansiyon',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onChanged: (v) => triggerSearch(v),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(Icons.info_outline, size: 16, color: Theme.of(context).colorScheme.outline),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '  ',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      if (searching)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                              SizedBox(width: 10),
                              Text('Aranıyor...'),
                            ],
                          ),
                        ),

                      if (!searching && nameCtrl.text.trim().length >= 2 && suggestions.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Sonuç bulunamadı.',
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                          ),
                        ),

                      if (suggestions.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Theme.of(context).dividerColor),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: SizedBox(
                            height: 210,
                            child: ListView.separated(
                              itemCount: suggestions.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final s = suggestions[i];
                                return ListTile(
                                  leading: const Icon(Icons.monitor_heart),
                                  title: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  onTap: () {
                                    nameCtrl.text = s;
                                    setLocal(() => suggestions = []);
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 12),

                      TextField(
                        controller: notesCtrl,
                        decoration: InputDecoration(
                          labelText: 'Not (opsiyonel)',
                          hintText: 'örn: doktor kontrolünde',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        minLines: 1,
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    debounce?.cancel();
                    Navigator.pop(dialogCtx, false);
                  },
                  child: const Text('İptal'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    debounce?.cancel();
                    Navigator.pop(dialogCtx, true);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Ekle'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) return;

    final typed = nameCtrl.text.trim();
    if (typed.isEmpty) return;

    try {
      await widget.api.addDisease(
        diseaseName: typed,
        notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
        diagnosedAt: null,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hastalık başarıyla eklendi.')),
      );
      _load();
    } catch (_) {
      // Dataset/WHO limit yoksa düzgün uyarı ver
      await _showAddFailedDialog();
    }
  }

  Future<void> _delete(String diseaseName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Silme Onayı'),
        content: Text('“$diseaseName” kaydını silmek istiyor musunuz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sil')),
        ],
      ),
    );

    if (confirm != true) return;

    await widget.api.deleteDisease(diseaseName);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Hastalık silindi.')),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hastalıklar'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: _loading ? null : _add,
            icon: const Icon(Icons.add),
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
            Expanded(
              child: _items.isEmpty
                  ? const Center(child: Text('Henüz eklenmiş hastalık yok.'))
                  : ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final it = _items[i] as Map;
                  final name = it['disease_name']?.toString() ?? '-';
                  final notes = it['notes']?.toString();

                  return ListTile(
                    leading: const Icon(Icons.monitor_heart),
                    title: Text(name),
                    subtitle: (notes != null && notes.trim().isNotEmpty) ? Text(notes) : null,
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => _delete(name),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 12),

            // ✅ Belirgin uyarı kartı
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.08),
                border: Border.all(color: Colors.orange.shade300),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Tarif önerileri, Dünya Sağlık Örgütü (WHO) tarafından tanımlanan '
                          'hastalık bazlı besin sınırlarına göre hesaplanmaktadır.\n\n'
                          'Bu uygulama tıbbi tanı veya tedavi amacı taşımaz. '
                          'Sağlık durumunuza ilişkin kararlar için mutlaka doktorunuza '
                          'veya diyetisyeninize danışınız.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
