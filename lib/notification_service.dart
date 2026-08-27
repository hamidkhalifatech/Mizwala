import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'prayer_times.dart';

/// Clés des préférences pour les réglages de notification.
const kPrefPrefix = 'notif_enabled_';
const kPrefDelay = 'notif_delay_minutes';
const kPrefCustomSoundPath = 'custom_sound_path';
const kPrefCustomSoundName = 'custom_sound_name';

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
  static final AudioPlayer _audioPlayer = AudioPlayer();
  static bool _initialized = false;

  static const String channelId = 'mizwala_prayers_v2';
  static const String channelName = 'Horaires de Prière Mizwala';

  static Future<void> init() async {
    if (_initialized) return;
    try {
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

      // Créer le canal Android haute priorité avec son et vibration
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      if (androidImpl != null) {
        // Demande de permission Android 13+ (POST_NOTIFICATIONS)
        await androidImpl.requestNotificationsPermission();
        await androidImpl.requestExactAlarmsPermission();

        const channel = AndroidNotificationChannel(
          channelId,
          channelName,
          description: 'Rappels et alertes avant chaque prière',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          enableLights: true,
          ledColor: Color(0xFFFF9F0A),
        );
        await androidImpl.createNotificationChannel(channel);
      }

      _initialized = true;
    } catch (e) {
      debugPrint('Notification init error: $e');
    }
  }

  /// Joue le son d'alarme personnalisé ou par défaut
  static Future<void> playCustomAlarmSound(String? path) async {
    try {
      await stopAlarmSound();
      if (path != null && path.isNotEmpty && File(path).existsSync()) {
        await _audioPlayer.setVolume(1.0);
        await _audioPlayer.play(DeviceFileSource(path));
      }
    } catch (e) {
      debugPrint('Error playing custom alarm sound: $e');
    }
  }

  /// Arrête la lecture audio
  static Future<void> stopAlarmSound() async {
    try {
      await _audioPlayer.stop();
    } catch (_) {}
  }

  /// Déclenche une notification de test immédiate avec sonnerie
  static Future<void> sendTestNotification() async {
    try {
      await init();
      final prefs = await SharedPreferences.getInstance();
      final customPath = prefs.getString(kPrefCustomSoundPath);

      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: 'Rappels et alertes avant chaque prière',
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          color: Color(0xFFFF9F0A),
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      await _plugin.show(
        9999,
        '🕌 Mizwala — Test d\'alarme',
        'L\'alarme et les notifications de prière fonctionnent avec succès !',
        details,
      );

      if (customPath != null && customPath.isNotEmpty) {
        await playCustomAlarmSound(customPath);
      }
    } catch (e) {
      debugPrint('Error sending test notification: $e');
    }
  }

  /// Replanifie toutes les notifications pour aujourd'hui et demain.
  static Future<void> reschedule(PrayerTimes todayTimes) async {
    try {
      await init();
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

          const details = NotificationDetails(
            android: AndroidNotificationDetails(
              channelId,
              channelName,
              channelDescription: 'Rappels et alertes avant chaque prière',
              importance: Importance.max,
              priority: Priority.max,
              playSound: true,
              enableVibration: true,
              color: Color(0xFFFF9F0A),
              icon: '@mipmap/ic_launcher',
            ),
            iOS: DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
          );

          try {
            await _plugin.zonedSchedule(
              notifId++,
              '🕌 $label — $timeStr',
              delayMin == 0
                  ? 'C\'est l\'heure de la prière à Marrakech'
                  : 'Prière dans $delayMin min',
              tzTime,
              details,
              androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
              uiLocalNotificationDateInterpretation:
                  UILocalNotificationDateInterpretation.absoluteTime,
            );
          } catch (_) {
            // Fallback si l'appareil restreint les alarmes exactes
            try {
              await _plugin.zonedSchedule(
                notifId++,
                '🕌 $label — $timeStr',
                delayMin == 0
                    ? 'C\'est l\'heure de la prière à Marrakech'
                    : 'Prière dans $delayMin min',
                tzTime,
                details,
                androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
                uiLocalNotificationDateInterpretation:
                    UILocalNotificationDateInterpretation.absoluteTime,
              );
            } catch (e) {
              debugPrint('Schedule notification error: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Reschedule error: $e');
    }
  }

  /// Demander les permissions au premier lancement.
  static Future<bool> requestPermission() async {
    try {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        await androidImpl.requestNotificationsPermission();
        await androidImpl.requestExactAlarmsPermission();
      }

      final iosImpl = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final result = await iosImpl?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return result ?? true;
    } catch (_) {
      return true;
    }
  }
}
