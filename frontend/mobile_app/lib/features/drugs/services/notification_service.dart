import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/api_client.dart';
import '../drugs_api.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
  FlutterLocalNotificationsPlugin();
  static bool _inited = false;

  static ApiClient? _client;
  static DrugsApi? _api;

  static const _secure = FlutterSecureStorage();
  static const String _queueKey = 'pending_intake_events_v1';

  // ✅ snooze notification id (tek snooze kalsın)
  static const String _lastSnoozeIdKeyPrefix = 'last_snooze_id_v1|';

  // ✅ UI'a snooze pending taşımak için
  static const String _pendingSnoozeKeyPrefix = 'pending_snooze_v1|';

  /// Günlük doz kapanışı (Aldım/Atla/MISSED) — drug_detail ile aynı anahtar.
  static const String _handledKeyPrefix = 'handled_intake_v1|';

  // ✅ Channel reset (ses/heads-up için)
  static const String _channelId = 'drug_reminders_v3';
  static const String _channelName = 'İlaç Hatırlatıcıları';
  static const String _channelDesc = 'İlaç saatleri için bildirimler';

  // Bildirime tıklama olayını UI tarafına taşımak için
  static final ValueNotifier<Map<String, String>?> tappedPayload =
      ValueNotifier<Map<String, String>?>(null);

  /// Aldım sonrası stok / pasif durumu — liste ve detay anında güncellenir.
  static final ValueNotifier<Map<String, dynamic>?> drugStockUpdate =
      ValueNotifier<Map<String, dynamic>?>(null);

  static void configure(ApiClient client) {
    _client = client;
    _api = DrugsApi(client);
  }

  // ------------------ PENDING SNOOZE STORE ------------------

  static String _pendingSnoozeKey(String userDrugId) =>
      '$_pendingSnoozeKeyPrefix$userDrugId';

  static Future<void> savePendingSnooze({
    required String userDrugId,
    required String timeStr,
    required String scheduledAtIso,
    required String doseScheduledAtIso,
  }) async {
    await _secure.write(
      key: _pendingSnoozeKey(userDrugId),
      value: jsonEncode({
        'user_drug_id': userDrugId,
        'time_of_day': timeStr,
        'scheduled_at': scheduledAtIso,
        'dose_scheduled_at_iso': doseScheduledAtIso,
      }),
    );
  }

  static Future<Map<String, dynamic>?> loadPendingSnooze(
      String userDrugId,
      ) async {
    final raw = await _secure.read(key: _pendingSnoozeKey(userDrugId));
    if (raw == null || raw.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      await _secure.delete(key: _pendingSnoozeKey(userDrugId));
      return null;
    }
  }

  static Future<void> clearPendingSnooze(String userDrugId) async {
    await _secure.delete(key: _pendingSnoozeKey(userDrugId));
  }

  // ------------------ INIT ------------------

  static Future<void> ensureInitialized() async {
    if (_inited) return;

    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));
      log('[NOTIF][init] timezone=${tz.local.name}');
    } catch (e) {
      log('[NOTIF][init] Europe/Istanbul failed ($e), using device local');
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings();

    const init = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
    );

    await _plugin.initialize(
      init,
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: _onNotificationResponse,
    );

    final androidPlugin =
    _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
    );
    await androidPlugin?.createNotificationChannel(channel);

    // Android 13+ izin
    await androidPlugin?.requestNotificationsPermission();
    // Yakın zamandaki alarmlar için (Android 12+)
    await androidPlugin?.requestExactAlarmsPermission();

    _inited = true;
  }

  static Future<void> _logPending(String tag) async {
    final pending = await _plugin.pendingNotificationRequests();
    log(
      '[NOTIF][$tag] pending=${pending.length} ids=${pending.map((e) => e.id).toList()}',
    );
  }

  // ------------------ TIME HELPERS ------------------

  /// API/form farklarını tek forma çeker: HH:mm:ss
  static String normalizeTimeOfDay(String raw) {
    final p = raw.trim().split(':');
    final h = int.tryParse(p.isNotEmpty ? p[0] : '') ?? 9;
    final m = int.tryParse(p.length > 1 ? p[1] : '') ?? 0;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:00';
  }

  /// Backend'e timezone'suz gitmesin (+03:00 ile gider).
  static String iso8601WithOffset(tz.TZDateTime dt) {
    final s = dt.toIso8601String();
    if (RegExp(r'([Zz]|[+-]\d{2}:?\d{2})$').hasMatch(s)) return s;
    final off = dt.timeZoneOffset;
    final sign = off.isNegative ? '-' : '+';
    final oh = off.inHours.abs().toString().padLeft(2, '0');
    final om = (off.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return '$s$sign$oh:$om';
  }

  static bool isSchedulingAllowed(Map<String, dynamic> drug) {
    final inv = drug['inventory'] as Map<String, dynamic>?;
    if (inv != null) {
      final qty = int.tryParse(inv['quantity']?.toString() ?? '') ?? 0;
      if (qty <= 0) return false;
    }
    for (final s0 in (drug['schedules'] ?? []) as List<dynamic>) {
      final s = s0 as Map<String, dynamic>;
      if ((s['is_active'] ?? true) == true) return true;
    }
    return false;
  }

  static List<String> scheduleTimesFromDrug(Map<String, dynamic> drug) {
    final out = <String>[];
    for (final s0 in (drug['schedules'] ?? []) as List<dynamic>) {
      final s = s0 as Map<String, dynamic>;
      if ((s['is_active'] ?? true) != true) continue;
      final t = (s['time_of_day'] ?? '').toString();
      if (t.isNotEmpty) out.add(t);
    }
    return out;
  }

  static Future<void> _cancelScheduleSlot({
    required String userDrugId,
    required String timeRaw,
  }) async {
    final timeStr = normalizeTimeOfDay(timeRaw);
    final stableId = stableIdFrom(userDrugId, timeStr);
    final fallbackId = fallbackIdFrom(stableId);
    await _plugin.cancel(stableId);
    await _plugin.cancel(fallbackId);
    await _plugin.cancel(stableId + 2);
    await _plugin.cancel(stableId + 3);
    await _plugin.cancel(stableId + 4);
    await cancelLastSnoozeIfAny(userDrugId: userDrugId, timeStr: timeStr);
  }

  /// Cevap yoksa: ana + 5 dk yedekten sonra dozu MISSED yap (en fazla 1 yedek).
  static Future<void> reconcileMissedDoses(List<dynamic> drugs) async {
    if (_api == null) return;
    await ensureInitialized();

    final now = tz.TZDateTime.now(tz.local);
    const graceAfterFallback = Duration(minutes: 6);

    for (final d0 in drugs) {
      final drug = d0 as Map<String, dynamic>;
      final userDrugId = drug['user_drug_id'].toString();
      final handled = await loadHandledDoseIds(userDrugId);
      final pendingSnooze = await loadPendingSnooze(userDrugId);

      for (final s0 in (drug['schedules'] ?? []) as List<dynamic>) {
        final s = s0 as Map<String, dynamic>;
        if ((s['is_active'] ?? true) != true) continue;

        final timeStr = normalizeTimeOfDay(
          (s['time_of_day'] ?? '09:00:00').toString(),
        );
        final parts = timeStr.split(':');
        final hh = int.tryParse(parts[0]) ?? 9;
        final mm = int.tryParse(parts[1]) ?? 0;
        final todayAt = tz.TZDateTime(
          tz.local,
          now.year,
          now.month,
          now.day,
          hh,
          mm,
        );
        final doseIso = iso8601WithOffset(todayAt);
        final baseEventId = baseEventIdFrom(
          userDrugId: userDrugId,
          timeStr: timeStr,
          scheduledAtIso: doseIso,
        );

        if (handled.contains(baseEventId)) continue;

        final snoozeTimeStr = pendingSnooze != null
            ? normalizeTimeOfDay(
                pendingSnooze['time_of_day']?.toString() ?? '',
              )
            : null;

        if (snoozeTimeStr == timeStr) {
          final rawRemind = pendingSnooze!['scheduled_at']?.toString();
          tz.TZDateTime? remindAt;
          if (rawRemind != null) {
            try {
              remindAt = tz.TZDateTime.parse(tz.local, rawRemind);
            } catch (_) {
              final p = DateTime.tryParse(rawRemind);
              if (p != null) remindAt = tz.TZDateTime.from(p, tz.local);
            }
          }
          if (remindAt != null) {
            if (now.isBefore(remindAt.add(graceAfterFallback))) continue;
          } else if (now.isBefore(todayAt.add(graceAfterFallback))) {
            continue;
          }
        } else {
          if (now.isBefore(todayAt.add(graceAfterFallback))) continue;
        }

        log('[NOTIF][missed] marking $baseEventId');
        final ok = await _trySendIntake({
          'user_drug_id': userDrugId,
          'client_event_id': baseEventId,
          'action': 'MISSED',
          'scheduled_at': doseIso,
          'snooze_minutes': 5,
        });
        if (!ok) continue;

        await finishDoseAndScheduleNext(
          userDrugId: userDrugId,
          timeStr: timeStr,
          baseEventId: baseEventId,
          intakeResult: {
            'new_quantity': null,
            'stock_depleted': false,
            'action': 'MISSED',
          },
        );
      }
    }
  }

  /// Ana + yedek + catch-up; snooze hariç (Ertele sonrası çift bildirim önlenir).
  static Future<void> cancelDailyAlarmsForSlot({
    required String userDrugId,
    required String timeRaw,
  }) async {
    final timeStr = normalizeTimeOfDay(timeRaw);
    final stableId = stableIdFrom(userDrugId, timeStr);
    await _plugin.cancel(stableId);
    await _plugin.cancel(fallbackIdFrom(stableId));
    await _plugin.cancel(stableId + 2);
    await _plugin.cancel(stableId + 3);
    await _plugin.cancel(stableId + 4);
  }

  static Future<Map<String, dynamic>?> _fetchDrug(String userDrugId) async {
    try {
      return await _api?.getDrug(userDrugId);
    } catch (e) {
      log('[NOTIF][fetch] drug $userDrugId failed: $e');
      return null;
    }
  }

  static Future<bool> applyIntakeSideEffects({
    required String userDrugId,
    required Map<String, dynamic> result,
    Map<String, dynamic>? localDrug,
  }) async {
    final newQty = result['new_quantity'];
    final depleted = result['stock_depleted'] == true;

    drugStockUpdate.value = {
      'user_drug_id': userDrugId,
      if (newQty != null) 'new_quantity': newQty,
      'stock_depleted': depleted,
    };

    if (localDrug != null && newQty != null) {
      final inv = localDrug['inventory'] as Map<String, dynamic>?;
      if (inv != null) inv['quantity'] = newQty;
      if (depleted) {
        for (final s0 in (localDrug['schedules'] ?? []) as List<dynamic>) {
          (s0 as Map<String, dynamic>)['is_active'] = false;
        }
      }
    }

    if (depleted) {
      final drug = localDrug ?? await _fetchDrug(userDrugId);
      if (drug != null) await cancelAllForDrug(drug);
      return false;
    }
    return true;
  }

  static Map<String, dynamic>? _findScheduleRow(
    Map<String, dynamic> drug,
    String normTime,
  ) {
    for (final s0 in (drug['schedules'] ?? []) as List<dynamic>) {
      final s = s0 as Map<String, dynamic>;
      if (normalizeTimeOfDay((s['time_of_day'] ?? '').toString()) == normTime) {
        return s;
      }
    }
    return null;
  }

  /// İlk kurulum / liste yenileme: bugünün saati geçmediyse bugün, geçtiyse yarın.
  static Future<void> scheduleNextOpenOccurrenceForSlot(
    Map<String, dynamic> drug,
    String timeRaw,
  ) async {
    if (!isSchedulingAllowed(drug)) return;

    final userDrugId = drug['user_drug_id'].toString();
    final timeStr = normalizeTimeOfDay(timeRaw);

    if (await isTodayDoseHandled(userDrugId: userDrugId, timeStr: timeStr)) {
      log('[NOTIF][open] today handled -> tomorrow only drug=$userDrugId time=$timeStr');
      await scheduleTomorrowOccurrenceForSlot(drug, timeRaw);
      return;
    }

    final now = tz.TZDateTime.now(tz.local);
    var nextMain = slotToday(timeStr);
    if (!nextMain.isAfter(now.add(const Duration(minutes: 1)))) {
      nextMain = slotTomorrow(timeStr);
    }

    await _scheduleOccurrenceAt(
      drug: drug,
      timeStr: timeStr,
      mainWhen: nextMain,
    );
  }

  /// Aldım / Atla / Kaçırıldı sonrası: kesinlikle yarın aynı saat.
  static Future<void> scheduleTomorrowOccurrenceForSlot(
    Map<String, dynamic> drug,
    String timeRaw,
  ) async {
    if (!isSchedulingAllowed(drug)) return;
    final timeStr = normalizeTimeOfDay(timeRaw);
    final nextMain = slotTomorrow(timeStr);
    await _scheduleOccurrenceAt(
      drug: drug,
      timeStr: timeStr,
      mainWhen: nextMain,
    );
  }

  static Future<void> _scheduleOccurrenceAt({
    required Map<String, dynamic> drug,
    required String timeStr,
    required tz.TZDateTime mainWhen,
    bool repeatDailyMain = true,
  }) async {
    await ensureInitialized();

    final userDrugId = drug['user_drug_id'].toString();
    final name = (drug['drug_name'] ?? 'İlaç').toString();
    final stableId = stableIdFrom(userDrugId, timeStr);
    final fallbackId = fallbackIdFrom(stableId);
    final doseIso = iso8601WithOffset(mainWhen);

    final scheduleRow = _findScheduleRow(drug, timeStr);
    final payload = jsonEncode({
      'user_drug_id': userDrugId,
      'schedule_id': scheduleRow?['schedule_id']?.toString(),
      'time_of_day': timeStr,
      'dose_scheduled_at': doseIso,
      'scheduled_at': doseIso,
      'stable_id': stableId,
      'fallback_id': fallbackId,
      'is_snooze': false,
    });

    log('[NOTIF][plan] drug=$userDrugId time=$timeStr main=$mainWhen repeat=$repeatDailyMain fb=${mainWhen.add(const Duration(minutes: 5))}');

    await _zonedScheduleReliable(
      id: stableId,
      title: 'İlaç zamanı',
      body: '$name • $timeStr',
      when: mainWhen,
      payload: payload,
      match: repeatDailyMain ? DateTimeComponents.time : null,
    );
    await _zonedScheduleReliable(
      id: fallbackId,
      title: 'Hatırlatma',
      body: '$name • $timeStr (5 dk hatırlatma)',
      when: mainWhen.add(const Duration(minutes: 5)),
      payload: payload,
    );
  }

  static Future<void> finishDoseAndScheduleNext({
    required String userDrugId,
    required String timeStr,
    required String baseEventId,
    required Map<String, dynamic> intakeResult,
    Map<String, dynamic>? localDrug,
  }) async {
    log('[NOTIF][finish] dose closed $userDrugId $timeStr event=$baseEventId');

    await markDoseHandled(userDrugId: userDrugId, baseEventId: baseEventId);

    await cancelDailyAlarmsForSlot(userDrugId: userDrugId, timeRaw: timeStr);
    await cancelLastSnoozeIfAny(userDrugId: userDrugId, timeStr: timeStr);
    await clearPendingSnooze(userDrugId);

    final canSchedule = await applyIntakeSideEffects(
      userDrugId: userDrugId,
      result: intakeResult,
      localDrug: localDrug,
    );

    if (!canSchedule) return;

    final drug = localDrug ?? await _fetchDrug(userDrugId);
    if (drug != null) {
      await scheduleTomorrowOccurrenceForSlot(drug, timeStr);
    }

    await _logPending('after_finish_dose');
  }

  /// Kayıt sonrası: sadece silinen/düzenlenen saatleri iptal et, sadece yeni eklenen saatleri planla.
  /// Değişmeyen saatlere dokunma (bir ilaçta birden fazla saat bildirimi korunur).
  static Future<void> rescheduleSingleDrug(
    Map<String, dynamic> drug, {
    required List<String> previousTimeStrs,
  }) async {
    await ensureInitialized();
    final userDrugId = drug['user_drug_id'].toString();

    final prev = previousTimeStrs
        .map(normalizeTimeOfDay)
        .where((t) => t.isNotEmpty)
        .toSet();
    final next = scheduleTimesFromDrug(drug).map(normalizeTimeOfDay).toSet();

    final removed = prev.difference(next);
    final added = next.difference(prev);
    final unchanged = prev.intersection(next);

    log(
      '[NOTIF][sync] drug=$userDrugId removed=$removed added=$added unchanged=$unchanged',
    );

    for (final t in removed) {
      await _cancelScheduleSlot(userDrugId: userDrugId, timeRaw: t);
    }

    if (added.isNotEmpty) {
      await scheduleFromDrug(drug, onlyNormalizedTimes: added);
    }

    await reconcileMissedDoses([drug]);
    await _logPending('after_sync_drug_$userDrugId');
  }

  // ------------------ IDS ------------------

  static int stableIdFrom(String userDrugId, String time) {
    final t = normalizeTimeOfDay(time);
    final s = '$userDrugId|$t';
    var hash = 0;
    for (final c in s.codeUnits) {
      hash = ((hash << 5) - hash) + c;
      hash |= 0;
    }
    return hash.abs() % 1000000000;
  }

  static int fallbackIdFrom(int stableId) => stableId + 1;

  // snooze id space (günlük stableId/fallback ile çakışmasın)
  static int snoozeNotificationId(String userDrugId, String timeStr) {
    final s = 'snooze|$userDrugId|${normalizeTimeOfDay(timeStr)}';
    var hash = 0;
    for (final c in s.codeUnits) {
      hash = ((hash << 5) - hash) + c;
      hash |= 0;
    }
    return 1500000000 + (hash.abs() % 400000000);
  }

  static String _lastSnoozeKey(String userDrugId, String timeStr) =>
      '$_lastSnoozeIdKeyPrefix$userDrugId|$timeStr';

  // ------------------ CANCEL HELPERS ------------------

  static Future<void> cancelFallbackByIds({required int fallbackId}) async {
    await ensureInitialized();
    await _plugin.cancel(fallbackId);
  }

  /// ✅ TAKEN/SKIP olduğunda snooze'ı da öldürmek için
  static Future<void> cancelLastSnoozeIfAny({
    required String userDrugId,
    required String timeStr,
  }) async {
    await ensureInitialized();

    final k = _lastSnoozeKey(userDrugId, timeStr);
    final raw = await _secure.read(key: k);
    final prevId = int.tryParse(raw ?? '');
    if (prevId != null) {
      await _plugin.cancel(prevId);
    }
    await _secure.delete(key: k);
  }

  // ------------------ PAYLOAD/DETAILS ------------------

  static String baseEventIdFrom({
    required String userDrugId,
    required String timeStr,
    required String scheduledAtIso,
  }) {
    return 'evt|$userDrugId|${normalizeTimeOfDay(timeStr)}|$scheduledAtIso';
  }

  /// Ertele bildiriminden Aldım/Atla: ayrı id → yeni kayıt, stok düşer (SNOOZE ile çakışmaz).
  static String takeAfterSnoozeClientEventId({
    required String userDrugId,
    required String timeStr,
    required String doseScheduledAtIso,
    required String snoozeAlarmAtIso,
  }) {
    final t = normalizeTimeOfDay(timeStr);
    var id =
        'evt|$userDrugId|$t|$doseScheduledAtIso|ring|$snoozeAlarmAtIso';
    if (id.length > 190) {
      id = id.substring(0, 190);
    }
    return id;
  }

  static tz.TZDateTime slotToday(String timeRaw) {
    final timeStr = normalizeTimeOfDay(timeRaw);
    final parts = timeStr.split(':');
    final hh = int.tryParse(parts[0]) ?? 9;
    final mm = int.tryParse(parts[1]) ?? 0;
    final now = tz.TZDateTime.now(tz.local);
    return tz.TZDateTime(tz.local, now.year, now.month, now.day, hh, mm);
  }

  /// Doz kapatıldıktan sonra: her zaman yarın aynı saat.
  static tz.TZDateTime slotTomorrow(String timeRaw) {
    return slotToday(timeRaw).add(const Duration(days: 1));
  }

  static Future<bool> isTodayDoseHandled({
    required String userDrugId,
    required String timeStr,
  }) async {
    final doseIso = doseScheduledAtIsoForToday(timeStr);
    final baseEventId = baseEventIdFrom(
      userDrugId: userDrugId,
      timeStr: timeStr,
      scheduledAtIso: doseIso,
    );
    return isDoseHandled(userDrugId: userDrugId, baseEventId: baseEventId);
  }

  /// Bugünkü planlı doz anı (client_event_id için tarih dahil).
  static String doseScheduledAtIsoForToday(String timeRaw) {
    final timeStr = normalizeTimeOfDay(timeRaw);
    final parts = timeStr.split(':');
    final hh = int.tryParse(parts[0]) ?? 9;
    final mm = int.tryParse(parts[1]) ?? 0;
    final now = tz.TZDateTime.now(tz.local);
    final todayAt = tz.TZDateTime(tz.local, now.year, now.month, now.day, hh, mm);
    return iso8601WithOffset(todayAt);
  }

  static String _handledStorageKey(String userDrugId) {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$_handledKeyPrefix$userDrugId|$y-$m-$d';
  }

  static Future<Set<String>> loadHandledDoseIds(String userDrugId) async {
    final raw = await _secure.read(key: _handledStorageKey(userDrugId));
    if (raw == null || raw.isEmpty) return {};
    try {
      final arr = jsonDecode(raw) as List<dynamic>;
      return arr.map((e) => e.toString()).toSet();
    } catch (_) {
      await _secure.delete(key: _handledStorageKey(userDrugId));
      return {};
    }
  }

  static Future<void> markDoseHandled({
    required String userDrugId,
    required String baseEventId,
  }) async {
    final set = await loadHandledDoseIds(userDrugId);
    if (set.contains(baseEventId)) return;
    set.add(baseEventId);
    await _secure.write(
      key: _handledStorageKey(userDrugId),
      value: jsonEncode(set.toList()),
    );
  }

  static Future<bool> isDoseHandled({
    required String userDrugId,
    required String baseEventId,
  }) async {
    final set = await loadHandledDoseIds(userDrugId);
    return set.contains(baseEventId);
  }

  static NotificationDetails _detailsPlain() {
    return _detailsWithActions();
  }

  /// Aldım / Ertele / Atla — bildirim gölgesinden doğrudan seçim.
  static NotificationDetails _detailsWithActions() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        enableVibration: true,
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(
            'TAKEN',
            'Aldım',
            showsUserInterface: true,
          ),
          AndroidNotificationAction(
            'SNOOZE',
            'Ertele',
            showsUserInterface: false,
          ),
          AndroidNotificationAction(
            'SKIP',
            'Atla',
            showsUserInterface: false,
          ),
        ],
      ),
    );
  }

  static String? doseScheduledAtFromPayload(Map<String, dynamic> payload) {
    final dose = payload['dose_scheduled_at']?.toString();
    if (dose != null && dose.isNotEmpty) return dose;
    return payload['scheduled_at']?.toString();
  }

  // ------------------ DAILY SCHEDULE ------------------

  /// Sunucuda artık olmayan ilaçların telefonda kalan planlı bildirimlerini iptal eder.
  /// Eski sürümde silinen ilaçlar için alarm iptal edilmemiş olabilir.
  static Future<int> cancelOrphanedNotifications(
    Set<String> knownUserDrugIds,
  ) async {
    await ensureInitialized();
    final pending = await _plugin.pendingNotificationRequests();
    var cancelled = 0;
    final orphanDrugIds = <String>{};

    for (final req in pending) {
      final payloadStr = req.payload;
      if (payloadStr == null || payloadStr.isEmpty) continue;
      Map<String, dynamic> payload;
      try {
        payload = Map<String, dynamic>.from(
          jsonDecode(payloadStr) as Map,
        );
      } catch (_) {
        continue;
      }
      final uid = payload['user_drug_id']?.toString();
      if (uid == null || uid.isEmpty) continue;
      if (knownUserDrugIds.contains(uid)) continue;

      await _plugin.cancel(req.id);
      cancelled++;
      orphanDrugIds.add(uid);
      log('[NOTIF][orphan] cancelled id=${req.id} drug=$uid');
    }

    for (final uid in orphanDrugIds) {
      await clearPendingSnooze(uid);
    }

    if (cancelled > 0) {
      log('[NOTIF][orphan] total cancelled=$cancelled drugs=$orphanDrugIds');
    }
    return cancelled;
  }

  static Future<void> pruneOrphanedForDrugList(List<dynamic> drugs) async {
    final known = <String>{};
    for (final d0 in drugs) {
      known.add((d0 as Map<String, dynamic>)['user_drug_id'].toString());
    }
    await cancelOrphanedNotifications(known);
  }

  static Future<void> rescheduleAllFromServerList(List<dynamic> drugs) async {
    await ensureInitialized();

    await pruneOrphanedForDrugList(drugs);

    // Önceki davranış: tüm aktif slotları iptal et, sonra scheduleFromDrug ile yeniden kur (günlük tekrar dahil).
    for (final d0 in drugs) {
      final drug = d0 as Map<String, dynamic>;
      if (!isSchedulingAllowed(drug)) {
        await cancelAllForDrug(drug);
        continue;
      }
      final userDrugId = drug['user_drug_id'].toString();
      for (final s0 in (drug['schedules'] ?? []) as List<dynamic>) {
        final s = s0 as Map<String, dynamic>;
        if ((s['is_active'] ?? true) != true) continue;
        final timeStr = (s['time_of_day'] ?? '09:00:00').toString();
        // Snooze’a dokunma: liste yenilenince kullanıcıdaki aktif (+5 dk) ertelemeyi
        // iptal etmek yerine günlük slotları sıfırlayıp yeniden kur.
        await cancelDailyAlarmsForSlot(userDrugId: userDrugId, timeRaw: timeStr);
      }
    }

    for (final d0 in drugs) {
      final drug = d0 as Map<String, dynamic>;
      if (!isSchedulingAllowed(drug)) continue;
      await scheduleFromDrug(drug);
    }

    await reconcileMissedDoses(drugs);
    await _logPending('after_reschedule_all');
  }

  static Future<void> _zonedScheduleReliable({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
    required String payload,
    DateTimeComponents? match,
  }) async {
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        _detailsPlain(),
        payload: payload,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: match,
      );
    } catch (e) {
      log('[NOTIF][schedule] exact failed id=$id when=$when err=$e -> inexact');
      await _plugin.cancel(id);
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        _detailsPlain(),
        payload: payload,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: match,
      );
    }
  }

  static Future<void> scheduleFromDrug(
    Map<String, dynamic> drug, {
    Set<String>? onlyNormalizedTimes,
  }) async {
    await ensureInitialized();
    if (!isSchedulingAllowed(drug)) return;

    final userDrugId = drug['user_drug_id'].toString();
    final name = (drug['drug_name'] ?? 'İlaç').toString();
    final schedules = (drug['schedules'] ?? []) as List<dynamic>;
    final now = tz.TZDateTime.now(tz.local);

    for (final s0 in schedules) {
      final s = s0 as Map<String, dynamic>;
      if ((s['is_active'] ?? true) != true) continue;

      final timeStr = normalizeTimeOfDay(
        (s['time_of_day'] ?? '09:00:00').toString(),
      );
      if (onlyNormalizedTimes != null && !onlyNormalizedTimes.contains(timeStr)) {
        continue;
      }

      if (await isTodayDoseHandled(
        userDrugId: userDrugId,
        timeStr: timeStr,
      )) {
        log('[NOTIF][schedule] dose already handled today -> tomorrow $timeStr');
        await scheduleTomorrowOccurrenceForSlot(drug, timeStr);
        continue;
      }

      final todayAt = slotToday(timeStr);
      final minutesLate = now.difference(todayAt).inMinutes;

      // Catch-up (~30 sn): YALNIZCA forma YENİ eklenen geçmiş saatlerde.
      // Liste yenileme / Aldım sonrası asla tetiklenmez.
      final allowCatchUp = onlyNormalizedTimes != null &&
          onlyNormalizedTimes.contains(timeStr);
      if (allowCatchUp && minutesLate >= 2 && minutesLate <= 12 * 60) {
        final stableId = stableIdFrom(userDrugId, timeStr);
        final fallbackId = fallbackIdFrom(stableId);
        final doseIso = iso8601WithOffset(todayAt);
        final payload = jsonEncode({
          'user_drug_id': userDrugId,
          'schedule_id': s['schedule_id']?.toString(),
          'time_of_day': timeStr,
          'dose_scheduled_at': doseIso,
          'scheduled_at': doseIso,
          'stable_id': stableId,
          'fallback_id': fallbackId,
          'is_snooze': false,
        });
        final catchMain = now.add(const Duration(seconds: 30));
        log('[NOTIF][catchup] new slot $timeStr in ${minutesLate}m -> $catchMain');
        await _zonedScheduleReliable(
          id: stableId + 2,
          title: 'İlaç zamanı',
          body: '$name • $timeStr',
          when: catchMain,
          payload: payload,
        );
        await _zonedScheduleReliable(
          id: stableId + 3,
          title: 'Hatırlatma',
          body: '$name • $timeStr (5 dk hatırlatma)',
          when: catchMain.add(const Duration(minutes: 5)),
          payload: payload,
        );
      }

      await scheduleNextOpenOccurrenceForSlot(drug, timeStr);
    }

    await _logPending('after_schedule_drug');
  }

  // ------------------ ACTION HANDLING ------------------

  static Future<void> _onNotificationResponse(NotificationResponse resp) async {
    final actionId = (resp.actionId ?? '').trim();
    final payloadStr = resp.payload;

    if (payloadStr == null || payloadStr.isEmpty) {
      log('[NOTIF][action] missing payload action=$actionId');
      return;
    }

    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(payloadStr) as Map<String, dynamic>;
    } catch (e) {
      log('[NOTIF][action] payload decode error: $e');
      return;
    }

    final userDrugId = payload['user_drug_id']?.toString();
    final timeStr = payload['time_of_day']?.toString();

    if (userDrugId == null || timeStr == null) {
      log('[NOTIF][action] payload missing fields: $payload');
      return;
    }

    // Varsayılan tıklama: sadece UI'ya haber ver, intake gönderme
    // Kullandığımız paket sürümünde defaultActionId sabiti olmadığından
    // sadece actionId'nin boş olmasını "tap" olarak kabul ediyoruz.
    final doseIso = doseScheduledAtFromPayload(payload) ??
        doseScheduledAtIsoForToday(timeStr);

    final bool isDefaultTap = actionId.isEmpty;
    if (isDefaultTap) {
      // Dokunma: otomatik 5 dk yedeği İPTAL ETME — kullanıcı cevap vermedi sayılır.
      tappedPayload.value = {
        'user_drug_id': userDrugId,
        'time_of_day': timeStr,
        'scheduled_at': doseIso,
      };
      return;
    }

    final baseEventId = baseEventIdFrom(
      userDrugId: userDrugId,
      timeStr: timeStr,
      scheduledAtIso: doseIso,
    );

    final bool payloadSnooze =
        payload['is_snooze'] == true || payload['is_snooze'] == 'true';
    final String? snoozeRingIso = payload['scheduled_at']?.toString();

    final normalizedAction = actionId == 'TAKEN'
        ? 'TAKEN'
        : actionId == 'SKIP'
            ? 'SKIP'
            : actionId == 'SNOOZE'
                ? 'SNOOZE'
                : 'SKIP';

    String intakeScheduledAt = doseIso;
    if (normalizedAction == 'SNOOZE') {
      final when = tz.TZDateTime.now(tz.local).add(const Duration(minutes: 5));
      intakeScheduledAt = iso8601WithOffset(when);
    }

    final intakeClientId = normalizedAction == 'SNOOZE'
        ? baseEventId
        : ((payloadSnooze &&
                snoozeRingIso != null &&
                snoozeRingIso.isNotEmpty &&
                (normalizedAction == 'TAKEN' || normalizedAction == 'SKIP'))
            ? takeAfterSnoozeClientEventId(
                userDrugId: userDrugId,
                timeStr: timeStr,
                doseScheduledAtIso: doseIso,
                snoozeAlarmAtIso: snoozeRingIso,
              )
            : baseEventId);

    final intakePayload = <String, dynamic>{
      'user_drug_id': userDrugId,
      'client_event_id': intakeClientId,
      'action': normalizedAction,
      'scheduled_at':
          normalizedAction == 'SNOOZE' ? intakeScheduledAt : doseIso,
      'snooze_minutes': 5,
    };

    if (normalizedAction == 'SNOOZE') {
      await cancelDailyAlarmsForSlot(userDrugId: userDrugId, timeRaw: timeStr);
      final result = await _sendIntakeReturning(intakePayload);
      final doseForSnooze = doseScheduledAtFromPayload(payload) ?? doseIso;
      if (result != null) {
        await scheduleSnoozeFromIntakeResult(
          userDrugId: userDrugId,
          timeStr: timeStr,
          intakeResult: result,
          doseScheduledAtIso: doseForSnooze,
        );
      } else {
        await _sendIntakeOrQueue(
          userDrugId: userDrugId,
          clientEventId: intakeClientId,
          action: normalizedAction,
          scheduledAtIso: intakeScheduledAt,
          snoozeMinutes: 5,
        );
        await scheduleOneOffSnoozeFromApp(
          userDrugId: userDrugId,
          timeStr: timeStr,
          minutes: 5,
          doseScheduledAtIso: doseForSnooze,
        );
      }
    } else {
      Map<String, dynamic>? result = await _sendIntakeReturning(intakePayload);
      result ??= {
        'new_quantity': null,
        'stock_depleted': false,
        'action': normalizedAction,
      };
      if (result['new_quantity'] == null && normalizedAction == 'TAKEN') {
        await _sendIntakeOrQueue(
          userDrugId: userDrugId,
          clientEventId: intakeClientId,
          action: normalizedAction,
          scheduledAtIso: doseIso,
          snoozeMinutes: 5,
        );
      }
      await finishDoseAndScheduleNext(
        userDrugId: userDrugId,
        timeStr: timeStr,
        baseEventId: baseEventId,
        intakeResult: result,
      );
    }
  }

  // ------------------ SNOOZE SCHEDULING ------------------

  static Future<void> scheduleOneOffSnoozeFromApp({
    required String userDrugId,
    required String timeStr,
    required int minutes,
    String? doseScheduledAtIso,
  }) async {
    final normTime = normalizeTimeOfDay(timeStr);
    final when = tz.TZDateTime.now(tz.local).add(Duration(minutes: minutes));
    await _scheduleOneOffSnoozeAt(
      userDrugId: userDrugId,
      timeStr: normTime,
      when: when,
      minutes: minutes,
      doseScheduledAtIso:
          doseScheduledAtIso ?? doseScheduledAtIsoForToday(normTime),
    );
  }

  /// Backend `remind_at` ile yerel snooze bildirimini hizalar.
  static Future<void> scheduleSnoozeFromIntakeResult({
    required String userDrugId,
    required String timeStr,
    required Map<String, dynamic> intakeResult,
    int fallbackMinutes = 5,
    String? doseScheduledAtIso,
  }) async {
    final normTime = normalizeTimeOfDay(timeStr);
    tz.TZDateTime when;

    final rawRemind = intakeResult['remind_at'];
    if (rawRemind != null) {
      final parsed = DateTime.tryParse(rawRemind.toString());
      if (parsed != null) {
        when = tz.TZDateTime.from(parsed.toUtc(), tz.local);
        log('[NOTIF][snooze] using backend remind_at=$rawRemind -> $when');
      } else {
        when = tz.TZDateTime.now(tz.local).add(Duration(minutes: fallbackMinutes));
      }
    } else {
      final rawScheduled = intakeResult['scheduled_at'];
      final parsed = rawScheduled != null
          ? DateTime.tryParse(rawScheduled.toString())
          : null;
      if (parsed != null) {
        when = tz.TZDateTime.from(parsed.toUtc(), tz.local);
      } else {
        when = tz.TZDateTime.now(tz.local).add(Duration(minutes: fallbackMinutes));
      }
    }

    await _scheduleOneOffSnoozeAt(
      userDrugId: userDrugId,
      timeStr: normTime,
      when: when,
      minutes: fallbackMinutes,
      doseScheduledAtIso:
          doseScheduledAtIso ?? doseScheduledAtIsoForToday(normTime),
    );
  }

  static Future<void> _scheduleOneOffSnoozeAt({
    required String userDrugId,
    required String timeStr,
    required tz.TZDateTime when,
    required int minutes,
    required String doseScheduledAtIso,
  }) async {
    await ensureInitialized();

    final normTime = normalizeTimeOfDay(timeStr);
    final stableId = stableIdFrom(userDrugId, normTime);
    final id = snoozeNotificationId(userDrugId, normTime);

    // önceki snooze'u iptal et (eski id formatı dahil)
    final lastKey = _lastSnoozeKey(userDrugId, normTime);
    final prevRaw = await _secure.read(key: lastKey);
    final prevId = int.tryParse(prevRaw ?? '');
    if (prevId != null && prevId != id) {
      await _plugin.cancel(prevId);
    }
    await _plugin.cancel(id);

    final snoozeScheduledAtIso = iso8601WithOffset(when);

    await savePendingSnooze(
      userDrugId: userDrugId,
      timeStr: normTime,
      scheduledAtIso: snoozeScheduledAtIso,
      doseScheduledAtIso: doseScheduledAtIso,
    );

    await _secure.write(key: lastKey, value: id.toString());

    final payload = jsonEncode({
      'user_drug_id': userDrugId,
      'time_of_day': normTime,
      'dose_scheduled_at': doseScheduledAtIso,
      'scheduled_at': snoozeScheduledAtIso,
      'stable_id': stableId,
      'fallback_id': null,
      'is_snooze': true,
    });

    // Günlük hatırlatıcıyla aynı: önce exact (izin veriliyorsa); gecikmelerde daha güvenilir.
    await _zonedScheduleReliable(
      id: id,
      title: 'Hatırlatma',
      body: 'Erteleme • $normTime (+$minutes dk)',
      when: when,
      payload: payload,
      match: null,
    );

    log('[NOTIF][snooze] scheduled id=$id when=$when iso=$snoozeScheduledAtIso');
    await _logPending('after_snooze_schedule');
  }

  // ---------------- QUEUE / BACKEND ----------------

  static Future<void> flushQueuedIntakesIfPossible() async {
    if (_client == null || _api == null) return;

    final raw = await _secure.read(key: _queueKey);
    if (raw == null || raw.isEmpty) return;

    List<dynamic> arr;
    try {
      arr = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      await _secure.delete(key: _queueKey);
      return;
    }

    if (arr.isEmpty) return;

    final remaining = <dynamic>[];
    for (final x in arr) {
      final m = Map<String, dynamic>.from(x as Map);
      final ok = await _trySendIntake(m);
      if (!ok) remaining.add(m);
    }

    await _secure.write(key: _queueKey, value: jsonEncode(remaining));
  }

  // debug helpers
  static Future<void> showNow({
    required String title,
    required String body,
  }) async {
    await ensureInitialized();
    final id = DateTime.now().millisecondsSinceEpoch.remainder(0x7FFFFFFF);
    await _plugin.show(id, title, body, _detailsPlain());
  }

  static Future<void> scheduleTestInOneMinute() async {
    await ensureInitialized();
    final now = tz.TZDateTime.now(tz.local);
    final when = now.add(const Duration(minutes: 1));
    await _plugin.zonedSchedule(
      999999,
      'İlaç hatırlatıcı (test)',
      '1 dakika sonra planlı bildirim çalıştı.',
      when,
      _detailsPlain(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: null,
    );
  }

  static Future<void> _sendIntakeOrQueue({
    required String userDrugId,
    required String clientEventId,
    required String action,
    String? scheduledAtIso,
    int snoozeMinutes = 5,
  }) async {
    final payload = <String, dynamic>{
      'user_drug_id': userDrugId,
      'client_event_id': clientEventId,
      'action': action,
      'scheduled_at': scheduledAtIso,
      'snooze_minutes': snoozeMinutes,
    };

    final ok = await _trySendIntake(payload);
    if (ok) return;

    final raw = await _secure.read(key: _queueKey);
    List<dynamic> arr = [];
    if (raw != null && raw.isNotEmpty) {
      try {
        arr = jsonDecode(raw) as List<dynamic>;
      } catch (_) {
        arr = [];
      }
    }
    arr.add(payload);
    await _secure.write(key: _queueKey, value: jsonEncode(arr));
    log('[NOTIF][queue] intake queued. size=${arr.length}');
  }

  static Future<bool> _trySendIntake(Map<String, dynamic> payload) async {
    final res = await _sendIntakeReturning(payload);
    return res != null;
  }

  static Future<Map<String, dynamic>?> _sendIntakeReturning(
    Map<String, dynamic> payload,
  ) async {
    if (_api == null) return null;

    try {
      return await _api!.intake(
        userDrugId: payload['user_drug_id'].toString(),
        clientEventId: payload['client_event_id'].toString(),
        action: payload['action'].toString(),
        scheduledAtIso: payload['scheduled_at']?.toString(),
        snoozeMinutes: int.tryParse(payload['snooze_minutes'].toString()) ?? 5,
      );
    } catch (e) {
      log('[NOTIF][intake] send failed: $e');
      return null;
    }
  }

  // ---------------- DRUG CLEANUP HELPERS ----------------

  /// Bir ilaca ait tüm günlük, fallback ve snooze bildirimlerini iptal eder.
  /// Böylece silinen ilaç için ertesi gün tekrar bildirim çalmaz.
  static Future<void> cancelAllForDrug(Map<String, dynamic> drug) async {
    await ensureInitialized();

    final userDrugId = drug['user_drug_id'].toString();
    final schedules = (drug['schedules'] ?? []) as List<dynamic>;

    for (final s0 in schedules) {
      final s = s0 as Map<String, dynamic>;
      final timeStr = (s['time_of_day'] ?? '09:00:00').toString();
      await _cancelScheduleSlot(userDrugId: userDrugId, timeRaw: timeStr);
    }

    await clearPendingSnooze(userDrugId);
    await _logPending('after_cancel_drug_$userDrugId');
  }
}