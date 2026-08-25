import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'prayer_times.dart';

/// Clés des préférences pour les réglages de notification.
const kPrefPrefix = 'notif_enabled_';
const kPrefDelay = 'notif_delay_minutes';

class PrayerNotificationItem {
  final String key;
  final String label;
  const PrayerNotificationItem(this.key, this.label);
}

/// Liste des prières supportant des notifications.
const List<PrayerNotificationItem> kNotifPrayers = [
  PrayerNotificationItem('fajr', 'Fajr'),
  PrayerNotificationItem('dhuhr', 'Dohr'),
  PrayerNotificationItem('asr', 'Asr'),
  PrayerNotificationItem('maghrib', 'Maghrib'),
  PrayerNotificationItem('isha', 'Icha'),
];

class _DaySchedule {
  final DateTime dayRef;
  final PrayerTimes times;
  const _DaySchedule(this.dayRef, this.times);
}

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _plugin.initialize(settings);

    // Créer le canal Android
    const channel = AndroidNotificationChannel(
      'mizwala_prayers',
      'Horaires de prière',
      description: 'Rappels avant chaque prière',
      importance: Importance.high,
      playSound: true,
      enableLights: true,
      ledColor: Color(0xFFC9A24B),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
  }

  /// Replanifie toutes les notifications pour aujourd'hui et demain.
  static Future<void> reschedule(PrayerTimes todayTimes) async {
    await _plugin.cancelAll();

    final prefs = await SharedPreferences.getInstance();
    final delayMin = prefs.getInt(kPrefDelay) ?? 10;

    // UTC Marrakech fixe = UTC+1
    final nowUtc = DateTime.now().toUtc();
    final nowMarrakech = nowUtc.add(const Duration(hours: 1));

    // Calculer pour aujourd'hui et demain
    final tomorrow = nowMarrakech.add(const Duration(days: 1));
    final tomorrowTimes = MizwalaCalculator.compute(
        tomorrow.year, tomorrow.month, tomorrow.day);

    final days = [
      _DaySchedule(nowMarrakech, todayTimes),
      _DaySchedule(tomorrow, tomorrowTimes),
    ];

    int notifId = 0;
    for (final schedule in days) {
      final dayRef = schedule.dayRef;
      final pTimes = schedule.times;
      final map = pTimes.asMap();
      for (final prayerItem in kNotifPrayers) {
        final key = prayerItem.key;
        final label = prayerItem.label;
        final enabled = prefs.getBool('$kPrefPrefix$key') ?? true;
        if (!enabled) continue;

        final prayerDecimal = map[key]!;
        final prayerHour = prayerDecimal.floor();
        final prayerMin = ((prayerDecimal - prayerHour) * 60).round();

        // Heure de la notification = heure de la prière - délai
        DateTime notifUtc = DateTime.utc(
          dayRef.year,
          dayRef.month,
          dayRef.day,
          prayerHour,
          prayerMin,
        )
            .subtract(Duration(minutes: delayMin))
            .subtract(const Duration(hours: 1)); // UTC Marrakech → vrai UTC

        // Ne pas planifier dans le passé
        if (notifUtc.isBefore(nowUtc)) continue;

        final tzTime = tz.TZDateTime.from(notifUtc, tz.UTC);
        final timeStr = MizwalaCalculator.format(prayerDecimal);

        await _plugin.zonedSchedule(
          notifId++,
          '🕌 $label — $timeStr',
          delayMin == 0
              ? 'C\'est l\'heure de la prière'
              : 'Dans $delayMin min',
          tzTime,
          NotificationDetails(
            android: AndroidNotificationDetails(
              'mizwala_prayers',
              'Horaires de prière',
              channelDescription: 'Rappels avant chaque prière',
              importance: Importance.high,
              priority: Priority.high,
              color: const Color(0xFFC9A24B),
              icon: '@mipmap/ic_launcher',
            ),
            iOS: const DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    }
  }

  /// Demander la permission iOS (à appeler au premier lancement).
  static Future<bool> requestPermission() async {
    final impl = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final result = await impl?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
    return result ?? true;
  }
}
