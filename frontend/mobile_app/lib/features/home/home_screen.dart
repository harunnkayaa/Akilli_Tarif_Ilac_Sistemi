// lib/features/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/app_colors.dart';
import '../kitchen/kitchen_api.dart';
import '../drugs/drugs_api.dart';
import '../profile/recipes_api.dart';
import '../recipes/recipe_detail_screen.dart';

/// Ana sayfa özet ekranı: günlük kalori, mutfak stok, ilaç ve uyarı özeti.
/// Sadece mevcut API'lerden veri okuyarak gösterir; hiçbir yapıyı değiştirmez.
class HomeScreen extends StatefulWidget {
  final KitchenApi kitchenApi;
  final DrugsApi drugsApi;
  final RecipesApi recipesApi;
  final ValueChanged<int>? onNavigateToTab;

  const HomeScreen({
    super.key,
    required this.kitchenApi,
    required this.drugsApi,
    required this.recipesApi,
    this.onNavigateToTab,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = true;
  double? _consumedKcal;
  Map<String, dynamic>? _dailyTotals;
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
      ]);
      if (!mounted) return;
      final totals = results[0] as Map<String, dynamic>;
      final pantry = results[1] as List;
      final drugs = results[2] as List;
      final alerts = results[3] as List;

      List<Map<String, dynamic>> recentMeals = [];
      try {
        recentMeals = await widget.recipesApi.getRecentMeals(limit: _recentMealsLimit);
      } catch (_) {
        // Son yemekler yüklenemese bile özet kartları gösterilsin.
      }

      int drugAlerts = 0;
      for (final d in drugs) {
        if (d is Map &&
            ((d['low_stock'] == true) || (d['stock_depleted'] == true))) {
          drugAlerts++;
        }
      }

      final energy = totals['total_energy_kcal'];
      setState(() {
        _dailyTotals = totals;
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

  double? _nutrientValue(String key) {
    final raw = _dailyTotals?[key];
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString());
  }

  String _fmtNutrient(double? v, {int fraction = 1}) {
    if (v == null) return '—';
    if ((v - v.round()).abs() < 0.0001) return v.round().toString();
    return v.toStringAsFixed(fraction);
  }

  void _showNutrientDetails() {
    final protein = _nutrientValue('total_protein_g');
    final fat = _nutrientValue('total_fat_g');
    final carb = _nutrientValue('total_carbohydrate_g');
    final sodium = _nutrientValue('total_sodium_mg');
    final energy = _consumedKcal ?? 0;
    final target = _defaultTargetKcal;
    final progress = (target <= 0) ? 0.0 : (energy / target).clamp(0.0, 1.0);
    final hasData = _consumedKcal != null ||
        protein != null ||
        fat != null ||
        carb != null ||
        sodium != null;
    final dateLabel = DateFormat('d MMMM yyyy', 'tr_TR').format(DateTime.now());

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.primary, Color(0xFF7EB8E8)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 88,
                          height: 88,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 88,
                                height: 88,
                                child: CircularProgressIndicator(
                                  value: progress,
                                  strokeWidth: 8,
                                  backgroundColor: Colors.white.withOpacity(0.25),
                                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
                                ),
                              ),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _fmtNutrient(energy, fraction: 0),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    'kcal',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.85),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Günlük Besin Özeti',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Bugün',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                dateLabel,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.85),
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Hedef: ${target.toInt()} kcal',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!hasData)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Column(
                        children: [
                          Icon(Icons.restaurant_menu_rounded, size: 48, color: AppColors.textSecondary.withOpacity(0.5)),
                          const SizedBox(height: 12),
                          Text(
                            'Bugün henüz tarif pişirilmedi.',
                            style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    Row(
                      children: [
                        Expanded(
                          child: _nutrientMetricTile(
                            icon: Icons.egg_alt_rounded,
                            label: 'Protein',
                            value: _fmtNutrient(protein),
                            unit: 'g',
                            color: const Color(0xFF5B9BD5),
                            bg: AppColors.primaryLight,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _nutrientMetricTile(
                            icon: Icons.water_drop_rounded,
                            label: 'Yağ',
                            value: _fmtNutrient(fat),
                            unit: 'g',
                            color: AppColors.accent,
                            bg: AppColors.accentLight,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _nutrientMetricTile(
                            icon: Icons.grain_rounded,
                            label: 'Karbonhidrat',
                            value: _fmtNutrient(carb),
                            unit: 'g',
                            color: const Color(0xFF6B8E7E),
                            bg: const Color(0xFFE8F0EC),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _nutrientMetricTile(
                            icon: Icons.bolt_rounded,
                            label: 'Sodyum',
                            value: _fmtNutrient(sodium, fraction: 0),
                            unit: 'mg',
                            color: const Color(0xFF8E7CC3),
                            bg: const Color(0xFFF0EBFA),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Tamam'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _nutrientMetricTile({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required Color color,
    required Color bg,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w900, fontSize: 20),
              children: [
                TextSpan(text: value),
                TextSpan(
                  text: ' $unit',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: Material(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  onTap: _showNutrientDetails,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.insights_rounded, size: 18, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text(
                          'Besin detayları',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
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
                label: 'Mutfak Stok',
                value: '$_pantryCount',
                sub: 'malzeme',
                color: AppColors.primary,
                onTap: () => widget.onNavigateToTab?.call(2),
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
                onTap: () => widget.onNavigateToTab?.call(1),
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
                label: 'Mutfak Uyarısı',
                value: '$_alertsCount',
                sub: _alertsCount > 0 ? 'azalan/biten' : 'yok',
                color: _alertsCount > 0 ? AppColors.warning : AppColors.textSecondary,
                onTap: () => widget.onNavigateToTab?.call(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _summaryCard(
                icon: Icons.medication_liquid,
                label: 'İlaç Uyarısı',
                value: '$_drugAlertsCount',
                sub: _drugAlertsCount > 0 ? 'azalan/biten' : 'yok',
                color: _drugAlertsCount > 0 ? AppColors.warning : AppColors.textSecondary,
                onTap: () => widget.onNavigateToTab?.call(1),
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
    VoidCallback? onTap,
  }) {
    return Card(
      elevation: 3,
      shadowColor: Colors.black.withOpacity(0.06),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
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
      ),
    );
  }

  Widget _buildRecentMealsCard() {
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
                  'Son yapılan yemekler',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_recentMeals.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Henüz kayıtlı yemek yok. Tarif sekmesinden bir tarif yaptığınızda burada görünür.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                ),
              )
            else
              ..._recentMeals.map((m) {
              final name = m['tarif_adi']?.toString().trim() ?? 'Tarif';
              final recipeId = m['tarif_id']?.toString().trim() ?? '';
              return InkWell(
                onTap: recipeId.isEmpty ? null : () => _openRecentMeal(m),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
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
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (recipeId.isNotEmpty)
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 22,
                          color: AppColors.textSecondary.withOpacity(0.7),
                        ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  void _openRecentMeal(Map<String, dynamic> meal) {
    final name = meal['tarif_adi']?.toString().trim() ?? 'Tarif';
    final recipeId = meal['tarif_id']?.toString().trim() ?? '';
    if (recipeId.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecipeDetailScreen(
          api: widget.recipesApi,
          recipeId: recipeId,
          initialTitle: name,
          showCookButton: false,
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
