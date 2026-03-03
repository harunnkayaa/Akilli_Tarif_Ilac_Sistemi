// lib/features/home/home_screen.dart
import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../kitchen/kitchen_api.dart';
import '../drugs/drugs_api.dart';
import '../profile/recipes_api.dart';

/// Ana sayfa özet ekranı: günlük kalori, mutfak stok, ilaç ve uyarı özeti.
/// Sadece mevcut API'lerden veri okuyarak gösterir; hiçbir yapıyı değiştirmez.
class HomeScreen extends StatefulWidget {
  final KitchenApi kitchenApi;
  final DrugsApi drugsApi;
  final RecipesApi recipesApi;

  const HomeScreen({
    super.key,
    required this.kitchenApi,
    required this.drugsApi,
    required this.recipesApi,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = true;
  double? _consumedKcal;
  int _pantryCount = 0;
  int _drugsCount = 0;
  int _alertsCount = 0;
  int _drugAlertsCount = 0;
  List<Map<String, dynamic>> _recentMeals = [];
  String? _error;

  static const double _defaultTargetKcal = 2300.0;
  static const int _recentMealsLimit = 5;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.recipesApi.getDailyTotals(),
        widget.kitchenApi.getPantry(),
        widget.drugsApi.listMyDrugs(),
        widget.kitchenApi.getPantryAlerts(),
        widget.recipesApi.getRecentMeals(limit: _recentMealsLimit),
      ]);
      if (!mounted) return;
      final totals = results[0] as Map<String, dynamic>;
      final pantry = results[1] as List;
      final drugs = results[2] as List;
      final alerts = results[3] as List;
      final recentMeals = results[4] as List<Map<String, dynamic>>;

      int drugAlerts = 0;
      for (final d in drugs) {
        if (d is Map && (d['low_stock'] == true)) drugAlerts++;
      }

      final energy = totals['total_energy_kcal'];
      setState(() {
        _consumedKcal = energy != null ? (energy is num ? energy.toDouble() : double.tryParse(energy.toString())) : null;
        _pantryCount = pantry.length;
        _drugsCount = drugs.length;
        _alertsCount = alerts.length;
        _drugAlertsCount = drugAlerts;
        _recentMeals = recentMeals;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Özet yüklenemedi.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                    _buildHeroImage(),
                    const SizedBox(height: 16),
                    _buildHeader(),
                    const SizedBox(height: 20),
                    if (_error != null) _buildErrorCard(),
                    if (_error == null) ...[
                      _buildCalorieCard(),
                      const SizedBox(height: 14),
                      _buildSummaryCards(),
                      const SizedBox(height: 14),
                      _buildRecentMealsCard(),
                      const SizedBox(height: 14),
                      _buildTipCard(),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHeroImage() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Image.asset(
        'assets/images/home_hero.png',
        height: 140,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          height: 120,
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.dashboard_rounded, size: 48, color: AppColors.primary),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.dashboard_rounded, size: 32, color: AppColors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Özet',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Günlük durumunuz bir arada',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildErrorCard() {
    return Card(
      elevation: 2,
      color: AppColors.warningLight,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: AppColors.warning),
            const SizedBox(width: 12),
            Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.textPrimary))),
          ],
        ),
      ),
    );
  }

  Widget _buildCalorieCard() {
    final consumed = _consumedKcal ?? 0.0;
    final target = _defaultTargetKcal;
    final progress = (target <= 0) ? 0.0 : (consumed / target).clamp(0.0, 1.0);

    return Card(
      elevation: 4,
      shadowColor: Colors.black.withOpacity(0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.accentLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.local_fire_department_rounded, color: AppColors.accent, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Günlük Kalori',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${consumed.toInt()} / ${target.toInt()} kcal',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: AppColors.primaryLight,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            if (_consumedKcal == null || _consumedKcal == 0) ...[
              const SizedBox(height: 8),
              Text(
                'Tarif yaptıkça günlük kaloriniz burada güncellenir.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _summaryCard(
                icon: Icons.kitchen_outlined,
                label: 'Mutfak stok',
                value: '$_pantryCount',
                sub: 'malzeme',
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _summaryCard(
                icon: Icons.medication_outlined,
                label: 'İlaç',
                value: '$_drugsCount',
                sub: 'kayıt',
                color: const Color(0xFF6B8E7E),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _summaryCard(
                icon: Icons.warning_amber_rounded,
                label: 'Mutfak uyarısı',
                value: '$_alertsCount',
                sub: _alertsCount > 0 ? 'azalan/biten' : 'yok',
                color: _alertsCount > 0 ? AppColors.warning : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _summaryCard(
                icon: Icons.medication_liquid,
                label: 'İlaç uyarısı',
                value: '$_drugAlertsCount',
                sub: _drugAlertsCount > 0 ? 'düşük stok' : 'yok',
                color: _drugAlertsCount > 0 ? AppColors.warning : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _summaryCard({
    required IconData icon,
    required String label,
    required String value,
    required String sub,
    required Color color,
  }) {
    return Card(
      elevation: 3,
      shadowColor: Colors.black.withOpacity(0.06),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        child: Column(
          children: [
            Icon(icon, size: 26, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
            if (sub.isNotEmpty && sub != 'yok')
              Text(
                sub,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentMealsCard() {
    if (_recentMeals.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 4,
      shadowColor: Colors.black.withOpacity(0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.accentLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.restaurant_menu_rounded, color: AppColors.accent, size: 22),
                ),
                const SizedBox(width: 10),
                Text(
                  'Son yapılan tarifler',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._recentMeals.map((m) {
              final name = m['tarif_adi']?.toString().trim() ?? 'Tarif';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, size: 20, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        name,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTipCard() {
    return Card(
      elevation: 2,
      color: AppColors.primaryLight.withOpacity(0.6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.lightbulb_outline_rounded, color: AppColors.primary, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'İlaç, mutfak stoku ve tarif önerileri için alt menüyü kullanın. Aşağı çekerek özeti yenileyebilirsiniz.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
