import 'dart:developer';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
  FlutterLocalNotificationsPlugin();
  static bool _inited = false;

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

    await _plugin.initialize(init);

    const channel = AndroidNotificationChannel(
      'drug_reminders_v2',
      'İlaç Hatırlatıcıları',
      description: 'İlaç saatleri için bildirimler',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(channel);

    // Android 13+: izin
    await androidPlugin?.requestNotificationsPermission();

    _inited = true;
  }

  static Future<void> _logPending(String tag) async {
    final pending = await _plugin.pendingNotificationRequests();
    log('[NOTIF][$tag] pending=${pending.length} ids=${pending.map((e) => e.id).toList()}');
    if (pending.isNotEmpty) {
      log('[NOTIF][$tag] titles=${pending.map((e) => e.title).toList()}');
    }
  }

  static Future<void> cancelAll() async {
    await ensureInitialized();
    await _plugin.cancelAll();
    await _logPending('after_cancelAll');
  }

  static Future<void> showNow({
    required String title,
    required String body,
  }) async {
    await ensureInitialized();

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'drug_reminders_v2',
        'İlaç Hatırlatıcıları',
        channelDescription: 'İlaç saatleri için bildirimler',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        enableVibration: true,
      ),
    );

    final id = DateTime.now().millisecondsSinceEpoch.remainder(0x7FFFFFFF);
    await _plugin.show(id, title, body, details);
  }

  /// 1 dk sonra planlı bildirim (TEK SEFERLİK).
  static Future<void> scheduleTestInOneMinute() async {
    await ensureInitialized();

    final now = tz.TZDateTime.now(tz.local);
    final when = now.add(const Duration(minutes: 1));

    log('[NOTIF][test] now=$now local=${tz.local.name} when=$when');

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'drug_reminders_v2',
        'Drug Reminders',
        channelDescription: 'İlaç hatırlatıcı bildirimleri',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      ),
    );

    await _plugin.zonedSchedule(
      999999,
      'İlaç hatırlatıcı (test)',
      '1 dakika sonra planlı bildirim çalıştı.',
      when,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: null, // tek seferlik
    );

    await _logPending('after_test_schedule');
  }

  static int _stableIdFrom(String userDrugId, String time) {
    final s = '$userDrugId|$time';
    var hash = 0;
    for (final c in s.codeUnits) {
      hash = ((hash << 5) - hash) + c;
      hash |= 0;
    }
    return hash.abs() % 1000000000;
  }

  static Future<void> rescheduleAllFromServerList(List<dynamic> drugs) async {
    await cancelAll();
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

      final id = _stableIdFrom(userDrugId, timeStr);

      final now = tz.TZDateTime.now(tz.local);
      var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hh, mm);
      if (!scheduled.isAfter(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }

      await _plugin.zonedSchedule(
        id,
        'İlaç zamanı',
        '$name • $timeStr',
        scheduled,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'drug_reminders_v2',
            'Drug Reminders',
            channelDescription: 'İlaç hatırlatıcı bildirimleri',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time, // her gün aynı saat
      );
    }
  }
}