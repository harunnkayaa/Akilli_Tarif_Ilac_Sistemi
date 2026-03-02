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

  // ✅ Channel reset (ses/heads-up için)
  static const String _channelId = 'drug_reminders_v3';
  static const String _channelName = 'İlaç Hatırlatıcıları';
  static const String _channelDesc = 'İlaç saatleri için bildirimler';

  // Bildirime tıklama olayını UI tarafına taşımak için
  static final ValueNotifier<Map<String, String>?> tappedPayload =
      ValueNotifier<Map<String, String>?>(null);

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
  }) async {
    await _secure.write(
      key: _pendingSnoozeKey(userDrugId),
      value: jsonEncode({
        'user_drug_id': userDrugId,
        'time_of_day': timeStr,
        'scheduled_at': scheduledAtIso,
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
    } catch (_) {}

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

    _inited = true;
  }

  static Future<void> _logPending(String tag) async {
    final pending = await _plugin.pendingNotificationRequests();
    log(
      '[NOTIF][$tag] pending=${pending.length} ids=${pending.map((e) => e.id).toList()}',
    );
  }

  // ------------------ IDS ------------------

  static int stableIdFrom(String userDrugId, String time) {
    final s = '$userDrugId|$time';
    var hash = 0;
    for (final c in s.codeUnits) {
      hash = ((hash << 5) - hash) + c;
      hash |= 0;
    }
    return hash.abs() % 1000000000;
  }

  static int fallbackIdFrom(int stableId) => stableId + 1;

  // snooze id space
  static int snoozeBaseFromStable(int stableId) => stableId + 100000;

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
    return 'evt|$userDrugId|$timeStr|$scheduledAtIso';
  }

  static NotificationDetails _detailsPlain() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        enableVibration: true,
      ),
    );
  }

  // ------------------ DAILY SCHEDULE ------------------

  static Future<void> rescheduleAllFromServerList(List<dynamic> drugs) async {
    await ensureInitialized();

    // sadece daily + daily fallback temizle (snooze'a dokunma)
    for (final d0 in drugs) {
      final d = d0 as Map<String, dynamic>;
      final userDrugId = d['user_drug_id'].toString();
      final schedules = (d['schedules'] ?? []) as List<dynamic>;

      for (final s0 in schedules) {
        final s = s0 as Map<String, dynamic>;
        final isActive = (s['is_active'] ?? true) == true;
        if (!isActive) continue;

        final timeStr = (s['time_of_day'] ?? '09:00:00').toString();
        final stableId = stableIdFrom(userDrugId, timeStr);
        final fallbackId = fallbackIdFrom(stableId);

        await _plugin.cancel(stableId);
        await _plugin.cancel(fallbackId);
      }
    }

    for (final d in drugs) {
      await scheduleFromDrug(d as Map<String, dynamic>);
    }

    await _logPending('after_reschedule_all');
  }

  static Future<void> scheduleFromDrug(Map<String, dynamic> drug) async {
    await ensureInitialized();

    final userDrugId = drug['user_drug_id'].toString();
    final name = (drug['drug_name'] ?? 'İlaç').toString();
    final schedules = (drug['schedules'] ?? []) as List<dynamic>;

    for (final s0 in schedules) {
      final s = s0 as Map<String, dynamic>;
      final isActive = (s['is_active'] ?? true) as bool;
      if (!isActive) continue;

      final timeStr = (s['time_of_day'] ?? '09:00:00').toString();
      final parts = timeStr.split(':');
      final hh = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 9 : 9;
      final mm = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

      final stableId = stableIdFrom(userDrugId, timeStr);
      final fallbackId = fallbackIdFrom(stableId);

      final now = tz.TZDateTime.now(tz.local);
      var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hh, mm);
      if (!scheduled.isAfter(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }

      final scheduledAtIso = scheduled.toIso8601String();

      final payload = jsonEncode({
        'user_drug_id': userDrugId,
        'time_of_day': timeStr,
        'scheduled_at': scheduledAtIso,
        'stable_id': stableId,
        'fallback_id': fallbackId,
        'is_snooze': false,
      });

      // MAIN daily
      await _plugin.zonedSchedule(
        stableId,
        'İlaç zamanı',
        '$name • $timeStr',
        scheduled,
        _detailsPlain(),
        payload: payload,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );

      // FALLBACK 5dk
      final fallbackWhen = scheduled.add(const Duration(minutes: 5));
      await _plugin.zonedSchedule(
        fallbackId,
        'Hatırlatma',
        '$name • $timeStr (5 dk hatırlatma)',
        fallbackWhen,
        _detailsPlain(),
        payload: payload,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: null,
      );
    }
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
    final scheduledAtIso = payload['scheduled_at']?.toString();
    final stableId = int.tryParse(payload['stable_id']?.toString() ?? '');
    final fallbackId = int.tryParse(payload['fallback_id']?.toString() ?? '');

    if (userDrugId == null || timeStr == null || scheduledAtIso == null || stableId == null) {
      log('[NOTIF][action] payload missing fields: $payload');
      return;
    }

    // Varsayılan tıklama: sadece UI'ya haber ver, intake gönderme
    // Kullandığımız paket sürümünde defaultActionId sabiti olmadığından
    // sadece actionId'nin boş olmasını "tap" olarak kabul ediyoruz.
    final bool isDefaultTap = actionId.isEmpty;
    if (isDefaultTap) {
      if (fallbackId != null) {
        await cancelFallbackByIds(fallbackId: fallbackId);
      }

      tappedPayload.value = {
        'user_drug_id': userDrugId,
        'time_of_day': timeStr,
        'scheduled_at': scheduledAtIso,
      };
      return;
    }

    final baseEventId = baseEventIdFrom(
      userDrugId: userDrugId,
      timeStr: timeStr,
      scheduledAtIso: scheduledAtIso,
    );

    // daily fallback iptal
    if (fallbackId != null) {
      await cancelFallbackByIds(fallbackId: fallbackId);
    }

    // ✅ SNOOZE: pending kaydet + 5dk sonra one-off kur
    if (actionId == 'SNOOZE') {
      // burada scheduledAtIso daily'nin scheduled_at'i olabilir,
      // gerçek snooze zamanı = now+5dk -> onu kaydediyoruz
      await _scheduleOneOffSnooze(
        userDrugId: userDrugId,
        timeStr: timeStr,
        minutes: 5,
        stableId: stableId,
      );
    }

    // ✅ TAKEN/SKIP: snooze iptal + pending snooze temizle
    if (actionId == 'TAKEN' || actionId == 'SKIP') {
      await cancelLastSnoozeIfAny(userDrugId: userDrugId, timeStr: timeStr);
      await clearPendingSnooze(userDrugId);
    }

    final normalizedAction = actionId == 'TAKEN'
        ? 'TAKEN'
        : actionId == 'SKIP'
            ? 'SKIP'
            : actionId == 'SNOOZE'
                ? 'SNOOZE'
                : 'SKIP';

    await _sendIntakeOrQueue(
      userDrugId: userDrugId,
      clientEventId: baseEventId,
      action: normalizedAction,
      scheduledAtIso: scheduledAtIso,
      snoozeMinutes: 5,
    );
  }

  // ------------------ SNOOZE SCHEDULING ------------------

  static Future<void> scheduleOneOffSnoozeFromApp({
    required String userDrugId,
    required String timeStr,
    required int minutes,
  }) async {
    final stableId = stableIdFrom(userDrugId, timeStr);
    await _scheduleOneOffSnooze(
      userDrugId: userDrugId,
      timeStr: timeStr,
      minutes: minutes,
      stableId: stableId,
    );
  }

  static Future<void> _scheduleOneOffSnooze({
    required String userDrugId,
    required String timeStr,
    required int minutes,
    required int stableId,
  }) async {
    await ensureInitialized();

    // önceki snooze'u iptal et
    final lastKey = _lastSnoozeKey(userDrugId, timeStr);
    final prevRaw = await _secure.read(key: lastKey);
    final prevId = int.tryParse(prevRaw ?? '');
    if (prevId != null) {
      await _plugin.cancel(prevId);
    }

    final now = tz.TZDateTime.now(tz.local);
    final when = now.add(Duration(minutes: minutes));
    final snoozeScheduledAtIso = when.toIso8601String();

    // UI'a pending snooze taşı
    await savePendingSnooze(
      userDrugId: userDrugId,
      timeStr: timeStr,
      scheduledAtIso: snoozeScheduledAtIso,
    );

    final base = snoozeBaseFromStable(stableId);
    final uniqueSuffix = DateTime.now().millisecondsSinceEpoch % 10000;
    final id = base + uniqueSuffix;

    await _secure.write(key: lastKey, value: id.toString());

    final payload = jsonEncode({
      'user_drug_id': userDrugId,
      'time_of_day': timeStr,
      'scheduled_at': snoozeScheduledAtIso, // ✅ snooze occurrence zamanı
      'stable_id': stableId,
      'fallback_id': null,
      'is_snooze': true,
    });

    // exact dene; yasaksa inexact
    try {
      await _plugin.zonedSchedule(
        id,
        'Hatırlatma',
        'Erteleme • $timeStr (+$minutes dk)',
        when,
        _detailsPlain(),
        payload: payload,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: null,
      );
    } catch (e) {
      log('[NOTIF][snooze] exact not permitted -> inexact. err=$e');
      await _plugin.zonedSchedule(
        id,
        'Hatırlatma',
        'Erteleme • $timeStr (+$minutes dk)',
        when,
        _detailsPlain(),
        payload: payload,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: null,
      );
    }

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
    if (_api == null) return false;

    try {
      await _api!.intake(
        userDrugId: payload['user_drug_id'].toString(),
        clientEventId: payload['client_event_id'].toString(),
        action: payload['action'].toString(),
        scheduledAtIso: payload['scheduled_at']?.toString(),
        snoozeMinutes: int.tryParse(payload['snooze_minutes'].toString()) ?? 5,
      );
      return true;
    } catch (e) {
      log('[NOTIF][intake] send failed: $e');
      return false;
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

      final stableId = stableIdFrom(userDrugId, timeStr);
      final fallbackId = fallbackIdFrom(stableId);

      await _plugin.cancel(stableId);
      await _plugin.cancel(fallbackId);

      await cancelLastSnoozeIfAny(
        userDrugId: userDrugId,
        timeStr: timeStr,
      );
    }

    await clearPendingSnooze(userDrugId);
    await _logPending('after_cancel_drug_$userDrugId');
  }
}