import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../drugs_api.dart';
import 'drug_form_screen.dart';

class DrugDetailScreen extends StatefulWidget {
  final ApiClient client;
  final Map<String, dynamic> drug;

  const DrugDetailScreen({super.key, required this.client, required this.drug});

  @override
  State<DrugDetailScreen> createState() => _DrugDetailScreenState();
}

class _DrugDetailScreenState extends State<DrugDetailScreen> {
  late final DrugsApi api;
  bool loadingInteractions = false;
  List<dynamic> interactions = [];

  @override
  void initState() {
    super.initState();
    api = DrugsApi(widget.client);
  }

  Future<void> _loadInteractions() async {
    setState(() => loadingInteractions = true);
    try {
      final id = widget.drug['user_drug_id'].toString();
      interactions = await api.interactions(id);
    } finally {
      if (mounted) setState(() => loadingInteractions = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.drug;
    final name = (d['drug_name'] ?? '').toString();
    final schedules = (d['schedules'] ?? []) as List<dynamic>;
    final inv = d['inventory'] as Map<String, dynamic>?;

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          IconButton(
            tooltip: 'Sil',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('İlacı sil?'),
                  content: Text('“$name” silinecek. Bu işlem geri alınamaz.'),
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
              if (ok != true) return;

              try {
                final id = widget.drug['user_drug_id'].toString();
                await api.deleteDrug(id);
                if (!mounted) return;
                Navigator.pop(context, true);
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Silme hatası: $e')),
                );
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Text('Kullanım saatleri', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),

          if (schedules.isEmpty)
            const Text('Saat yok.')
          else
            ...schedules.map((s) {
              final time = s['time_of_day'].toString();
              final dose = (s['dose_text'] ?? '').toString();

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.schedule_rounded),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(time, style: Theme.of(context).textTheme.titleMedium),
                          if (dose.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('Doz: $dose'),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),

          const SizedBox(height: 14),
          Text('Stok', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),

          if (inv == null)
            const Text('Stok bilgisi girilmemiş.')
          else
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text('${inv['quantity']} ${inv['unit']}'),
              subtitle: Text('Azaldı eşiği: ${inv['low_threshold']}'),
            ),

          OutlinedButton.icon(
            onPressed: () async {
              final ok = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => DrugFormScreen(
                    client: widget.client,
                    existingDrug: widget.drug,
                  ),
                ),
              );
              if (ok == true) {
                if (!mounted) return;
                Navigator.pop(context, true);
              }
            },
            icon: const Icon(Icons.edit_rounded),
            label: const Text('Saat/Stok Düzenle'),
          ),

          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: loadingInteractions ? null : _loadInteractions,
            icon: const Icon(Icons.restaurant_rounded),
            label: const Text('Besin etkileşimlerini getir'),
          ),

          const SizedBox(height: 10),
          if (loadingInteractions) const Center(child: CircularProgressIndicator()),
          if (!loadingInteractions && interactions.isNotEmpty) ...[
            Text('Etkileşimler', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...interactions.map((x) {
              final m = x as Map<String, dynamic>;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m['food_name_tr'].toString(),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text('Etki: ${m['interaction_effect']}'),
                    const SizedBox(height: 4),
                    Text('Öneri: ${m['recommendation_tr']}'),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}