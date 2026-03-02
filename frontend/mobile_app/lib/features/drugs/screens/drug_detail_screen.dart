import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/api_client.dart';
import '../../../core/app_colors.dart';
import '../drugs_api.dart';
import '../services/notification_service.dart';
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

  // ✅ snapshot değil: canlı state
  late Map<String, dynamic> _drug;

  bool _refreshing = false;

  bool loadingInteractions = false;
  List<dynamic> interactions = [];

  bool _intakeBusy = false;

  // ✅ Kalıcı handled storage
  static const _secure = FlutterSecureStorage();
  final Set<String> _handledBaseEventIds = {};
  bool _handledLoaded = false;

  // ✅ Snooze pending cache (UI bununla kart basacak)
  Map<String, dynamic>? _pendingSnooze;

  @override
  void initState() {
    super.initState();
    api = DrugsApi(widget.client);
    _drug = Map<String, dynamic>.from(widget.drug);

    NotificationService.configure(widget.client);

    final userDrugId = _drug['user_drug_id'].toString();

    _loadHandledForToday(userDrugId).then((_) {
      if (mounted) setState(() => _handledLoaded = true);
    });

    // ✅ sayfa açılınca snooze pending’i oku
    NotificationService.loadPendingSnooze(userDrugId).then((m) {
      if (!mounted) return;
      setState(() => _pendingSnooze = m);
    });

    // ✅ sayfa açılınca server’dan güncel ilacı çek
    _refreshDrug();
  }

  Future<void> _refreshDrug() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final id = _drug['user_drug_id'].toString();

      // ⚠️ DrugsApi içinde getDrug yoksa burada build patlar.
      // O durumda:
      // 1) DrugsApi’ya getDrug ekle, veya
      // 2) bu refresh bloğunu yorum satırı yap.
      final fresh = await api.getDrug(id);

      if (!mounted) return;
      setState(() {
        _drug = fresh;
      });

      // refresh sonrası snooze pending’i tekrar oku
      final userDrugId = _drug['user_drug_id'].toString();
      final snooze = await NotificationService.loadPendingSnooze(userDrugId);
      if (mounted) setState(() => _pendingSnooze = snooze);
    } catch (_) {
      // sessiz geç
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  // ------------------ HANDLED PERSIST ------------------

  String _todayKey(String userDrugId) {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return 'handled_intake_v1|$userDrugId|$y-$m-$d';
  }

  Future<void> _loadHandledForToday(String userDrugId) async {
    final key = _todayKey(userDrugId);
    final raw = await _secure.read(key: key);
    if (raw == null || raw.isEmpty) return;

    try {
      final arr = jsonDecode(raw) as List<dynamic>;
      _handledBaseEventIds
        ..clear()
        ..addAll(arr.map((e) => e.toString()));
    } catch (_) {
      await _secure.delete(key: key);
    }
  }

  Future<void> _saveHandledForToday(String userDrugId) async {
    final key = _todayKey(userDrugId);
    await _secure.write(
      key: key,
      value: jsonEncode(_handledBaseEventIds.toList()),
    );
  }

  // ------------------ UI HELPERS ------------------

  Future<void> _loadInteractions() async {
    setState(() => loadingInteractions = true);
    try {
      final id = _drug['user_drug_id'].toString();
      interactions = await api.interactions(id);
    } finally {
      if (mounted) setState(() => loadingInteractions = false);
    }
  }

  Map<String, dynamic>? _findPendingSchedule() {
    if (!_handledLoaded) return null;

    final userDrugId = _drug['user_drug_id'].toString();
    final now = DateTime.now();

    // ✅ 0) Önce snooze pending varsa onu göster
    if (_pendingSnooze != null) {
      final scheduledAtIso = _pendingSnooze!['scheduled_at']?.toString();
      final timeStr = _pendingSnooze!['time_of_day']?.toString() ?? '';
      if (scheduledAtIso != null && scheduledAtIso.isNotEmpty) {
        final scheduled = DateTime.tryParse(scheduledAtIso);
        if (scheduled != null) {
          final diffMin = scheduled.difference(now).inMinutes;

          // snooze penceresi: geçmiş 60dk ile gelecek 60dk
          if (diffMin >= -60 && diffMin <= 60) {
            final baseEventId = 'evt|$userDrugId|$timeStr|$scheduledAtIso';
            if (!_handledBaseEventIds.contains(baseEventId)) {
              return {
                'time_of_day': timeStr,
                'dose_text': '1',
                'scheduled_at_iso': scheduledAtIso,
                'diff_min': diffMin,
                'base_event_id': baseEventId,
                'is_snooze': true,
              };
            }
          }
        }
      }
    }

    // ✅ 1) yoksa normal schedule’dan bul
    final schedules = (_drug['schedules'] ?? []) as List<dynamic>;
    if (schedules.isEmpty) return null;

    Map<String, dynamic>? best;
    int bestAbsMin = 999999;

    for (final s0 in schedules) {
      final s = s0 as Map<String, dynamic>;
      final isActive = (s['is_active'] ?? true) == true;
      if (!isActive) continue;

      final timeStr = (s['time_of_day'] ?? '').toString();
      final parts = timeStr.split(':');
      final hh = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 9 : 9;
      final mm = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

      final scheduledToday = DateTime(now.year, now.month, now.day, hh, mm);
      final diffMin = scheduledToday.difference(now).inMinutes;

      // pencere: geçmiş 60dk ile gelecek 10dk arası
      // (erken "Aldım" için 10 dk yeterli)
      if (diffMin < -60 || diffMin > 10) continue;

      final scheduledAtIso = scheduledToday.toIso8601String();
      final baseEventId = 'evt|$userDrugId|$timeStr|$scheduledAtIso';

      if (_handledBaseEventIds.contains(baseEventId)) continue;

      final absMin = diffMin.abs();
      if (absMin < bestAbsMin) {
        bestAbsMin = absMin;
        best = {
          'time_of_day': timeStr,
          'dose_text': (s['dose_text'] ?? '').toString(),
          'scheduled_at_iso': scheduledAtIso,
          'diff_min': diffMin,
          'base_event_id': baseEventId,
          'is_snooze': false,
        };
      }
    }

    return best;
  }

  Future<void> _doIntake({
    required String action, // TAKEN/SNOOZE/SKIP
    required String userDrugId,
    required String timeStr,
    required String scheduledAtIso,
    required String baseEventId,
  }) async {
    if (_intakeBusy) return;
    setState(() => _intakeBusy = true);

    try {
      final stableId = NotificationService.stableIdFrom(userDrugId, timeStr);
      final fallbackId = NotificationService.fallbackIdFrom(stableId);

      // ✅ app içinden basınca daily fallback iptal
      await NotificationService.cancelFallbackByIds(fallbackId: fallbackId);

      // ✅ backend’e yaz
      final result = await api.intake(
        userDrugId: userDrugId,
        clientEventId: baseEventId,
        action: action,
        scheduledAtIso: scheduledAtIso,
        snoozeMinutes: 5,
      );

      // ✅ UI stok güncelle (hemen)
      final newQty = result['new_quantity'];
      if (newQty != null) {
        final inv = _drug['inventory'] as Map<String, dynamic>?;
        if (inv != null) inv['quantity'] = newQty;
      }

      // ✅ KRİTİK FIX:
      // TAKEN/SKIP olunca snooze bildirimini de öldür + pending snooze temizle.
      if (action == 'TAKEN' || action == 'SKIP') {
        await NotificationService.cancelLastSnoozeIfAny(
          userDrugId: userDrugId,
          timeStr: timeStr,
        );
        await NotificationService.clearPendingSnooze(userDrugId);
        if (mounted) setState(() => _pendingSnooze = null);
      }

      // ✅ SNOOZE olunca: local snooze schedule + pending reload
      if (action == 'SNOOZE') {
        await NotificationService.scheduleOneOffSnoozeFromApp(
          userDrugId: userDrugId,
          timeStr: timeStr,
          minutes: 5,
        );
        final snooze = await NotificationService.loadPendingSnooze(userDrugId);
        if (mounted) setState(() => _pendingSnooze = snooze);
      }

      if (!mounted) return;

      // ✅ kartı kapat + kalıcı kaydet
      _handledBaseEventIds.add(baseEventId);
      await _saveHandledForToday(userDrugId);

      setState(() {});

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'TAKEN'
                ? 'İşaretlendi: Aldım'
                : action == 'SKIP'
                ? 'İşaretlendi: Atla'
                : 'İşaretlendi: Ertele (5 dk)',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('İşlem hatası: $e')),
      );
    } finally {
      if (mounted) setState(() => _intakeBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _drug;
    final userDrugId = d['user_drug_id'].toString();
    final name = (d['drug_name'] ?? '').toString();
    final schedules = (d['schedules'] ?? []) as List<dynamic>;
    final inv = d['inventory'] as Map<String, dynamic>?;

    final pending = _findPendingSchedule();
    final int? diffMin = pending?['diff_min'] as int?;
    final bool timeArrived = diffMin != null && diffMin <= 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refreshing ? null : _refreshDrug,
          ),
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
                final id = d['user_drug_id'].toString();
                // Bu ilaç için tüm bildirimleri iptal et
                await NotificationService.cancelAllForDrug(d);
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
        child: RefreshIndicator(
          onRefresh: _refreshDrug,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!_handledLoaded)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(minHeight: 3),
                ),
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: AppColors.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primaryLight,
                      ),
                      child: const Icon(
                        Icons.vaccines_rounded,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            schedules.isEmpty
                                ? 'Saat tanımlı değil'
                                : 'Aktif saat: ${schedules.length}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (pending != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.primary.withOpacity(0.18),
                        AppColors.surface,
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            pending['is_snooze'] == true
                                ? Icons.snooze_rounded
                                : Icons.alarm_rounded,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            pending['is_snooze'] == true
                                ? 'Ertelenen doz'
                                : (timeArrived ? 'Zamanı gelen doz' : 'Zamanı yaklaşan doz'),
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Saat: ${pending['time_of_day']} • Doz: ${pending['dose_text']}',
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: _intakeBusy
                                  ? null
                                  : () => _doIntake(
                                        action: 'TAKEN',
                                        userDrugId: userDrugId,
                                        timeStr: pending['time_of_day']
                                            .toString(),
                                        scheduledAtIso: pending[
                                                'scheduled_at_iso']
                                            .toString(),
                                        baseEventId: pending['base_event_id']
                                            .toString(),
                                      ),
                              child: const Text('Aldım'),
                            ),
                          ),
                          if (timeArrived) ...[
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _intakeBusy
                                    ? null
                                    : () => _doIntake(
                                          action: 'SNOOZE',
                                          userDrugId: userDrugId,
                                          timeStr: pending['time_of_day']
                                              .toString(),
                                          scheduledAtIso: pending[
                                                  'scheduled_at_iso']
                                              .toString(),
                                          baseEventId: pending['base_event_id']
                                              .toString(),
                                        ),
                                child: const Text('Ertele'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _intakeBusy
                                    ? null
                                    : () => _doIntake(
                                          action: 'SKIP',
                                          userDrugId: userDrugId,
                                          timeStr: pending['time_of_day']
                                              .toString(),
                                          scheduledAtIso: pending[
                                                  'scheduled_at_iso']
                                              .toString(),
                                          baseEventId: pending['base_event_id']
                                              .toString(),
                                        ),
                                child: const Text('Atla'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: AppColors.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kullanım saatleri',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    if (schedules.isEmpty)
                      const Text('Saat yok.')
                    else
                      ...schedules.map((s) {
                        final time = s['time_of_day'].toString();
                        final dose = (s['dose_text'] ?? '').toString();

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: AppColors.primaryLight,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Icon(Icons.schedule_rounded, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      time,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.copyWith(
                                              fontWeight: FontWeight.w500),
                                    ),
                                    if (dose.trim().isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'Doz: $dose',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: AppColors.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Stok',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    if (inv == null)
                      const Text('Stok bilgisi girilmemiş.')
                    else
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: Text('${inv['quantity']} ${inv['unit']}'),
                        subtitle:
                            Text('Azaldı eşiği: ${inv['low_threshold']}'),
                      ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final ok = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DrugFormScreen(
                                client: widget.client,
                                existingDrug: _drug,
                              ),
                            ),
                          );
                          if (ok == true) {
                            if (!mounted) return;
                            await _refreshDrug();
                          }
                        },
                        icon: const Icon(Icons.edit_rounded, size: 22),
                        label: const Text('Saat/Stok Düzenle'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: AppColors.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed:
                            loadingInteractions ? null : _loadInteractions,
                        icon: const Icon(Icons.restaurant_rounded, size: 22),
                        label: const Text('Besin etkileşimlerini getir'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (loadingInteractions)
                      const Center(child: CircularProgressIndicator()),
                    if (!loadingInteractions && interactions.isNotEmpty) ...[
                      Text(
                        'Etkileşimler',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      ...interactions.map((x) {
                        final m = x as Map<String, dynamic>;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: AppColors.primaryLight,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m['food_name_tr'].toString(),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium,
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}