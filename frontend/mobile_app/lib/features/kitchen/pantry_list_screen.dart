// lib/features/kitchen/pantry_list_screen.dart
import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import 'kitchen_api.dart';

class PantryListScreen extends StatefulWidget {
  final KitchenApi api;
  const PantryListScreen({super.key, required this.api});

  @override
  State<PantryListScreen> createState() => _PantryListScreenState();
}

class _PantryListScreenState extends State<PantryListScreen> {
  bool _loading = true;
  List<dynamic> _pantry = [];
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final p = await widget.api.getPantry();
      setState(() => _pantry = p);
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _q.text.trim().toLowerCase();
    final filtered = _pantry.where((e) {
      final m = e as Map<String, dynamic>;
      final name = (m['ingredient_id']?.toString() ?? '').toLowerCase();
      return query.isEmpty || name.contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tüm Stoklar'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.surface,
        elevation: 2,
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
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
            TextField(
              controller: _q,
              decoration: const InputDecoration(labelText: 'Ara', prefixIcon: Icon(Icons.search)),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            if (filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: Text('Sonuç yok.')),
              ),
            ...filtered.map((e) {
              final m = e as Map<String, dynamic>;
              final name = m['ingredient_id']?.toString() ?? '-';
              final qty = m['quantity']?.toString() ?? '0';
              final unit = m['unit']?.toString() ?? '';
              final low = m['low_threshold']?.toString() ?? '-';

              return Card(
                color: AppColors.surface,
                elevation: 2,
                child: ListTile(
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('Miktar: $qty $unit  |  Eşik: $low'),
                ),
              );
            }).toList(),
                  ],
                ),
              ),
      ),
    );
  }
}