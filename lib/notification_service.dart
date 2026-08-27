import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'prayer_times.dart';

/// Clés des préférences pour les réglages de notification et sons
const kPrefPrefix = 'notif_enabled_';
const kPrefDelay = 'notif_delay_minutes';

// Sonnerie Prières (Adhan)
const kPrefPrayerSoundPath = 'custom_prayer_sound_path';
const kPrefPrayerSoundName = 'custom_prayer_sound_name';

// Sonnerie Réveil / Sommeil
const kPrefSleepSoundPath = 'custom_sleep_sound_path';
const kPrefSleepSoundName = 'custom_sleep_sound_name';

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

  static const String prayerChannelId = 'mizwala_prayers_channel';
  static const String prayerChannelName = 'Horaires de Prière (Adhan)';

  static const String sleepChannelId = 'mizwala_sleep_channel';
  static const String sleepChannelName = 'Alarme Réveil & Sommeil';

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

      // Créer les canaux Android haute priorité avec son et vibration
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      if (androidImpl != null) {
        // Demande de permission Android 13+ (POST_NOTIFICATIONS)
        await androidImpl.requestNotificationsPermission();
        await androidImpl.requestExactAlarmsPermission();

        const prayerChannel = AndroidNotificationChannel(
          prayerChannelId,
          prayerChannelName,
          description: 'Rappels et alertes avant chaque prière',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          enableLights: true,
          ledColor: Color(0xFFFF9F0A),
        );
        await androidImpl.createNotificationChannel(prayerChannel);

        const sleepChannel = AndroidNotificationChannel(
          sleepChannelId,
          sleepChannelName,
          description: 'Alarme de réveil à la fin de votre période de sommeil',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          enableLights: true,
          ledColor: Color(0xFF5E5CE6),
        );
        await androidImpl.createNotificationChannel(sleepChannel);
      }

      _initialized = true;
    } catch (e) {
      debugPrint('Notification init error: $e');
    }
  }

  /// Joue un fichier audio
  static Future<void> playCustomSound(String? path) async {
    try {
      await stopAlarmSound();
      if (path != null && path.isNotEmpty && File(path).existsSync()) {
        await _audioPlayer.setVolume(1.0);
        await _audioPlayer.play(DeviceFileSource(path));
      }
    } catch (e) {
      debugPrint('Error playing sound: $e');
    }
  }

  /// Arrête la lecture audio
  static Future<void> stopAlarmSound() async {
    try {
      await _audioPlayer.stop();
    } catch (_) {}
  }

  /// Déclenche une notification de test immédiate pour les Prières (Adhan)
  static Future<void> sendTestPrayerNotification() async {
    try {
      await init();
      final prefs = await SharedPreferences.getInstance();
      final soundPath = prefs.getString(kPrefPrayerSoundPath);

      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          prayerChannelId,
          prayerChannelName,
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
        8888,
        '🕌 Mizwala — Test Sonnerie Prière',
        'L\'alerte de prière (Adhan) fonctionne avec succès !',
        details,
      );

      if (soundPath != null && soundPath.isNotEmpty) {
        await playCustomSound(soundPath);
      }
    } catch (e) {
      debugPrint('Error sending test prayer notification: $e');
    }
  }

  /// Déclenche une notification de test immédiate pour le Réveil / Sommeil
  static Future<void> sendTestSleepNotification() async {
    try {
      await init();
      final prefs = await SharedPreferences.getInstance();
      final soundPath = prefs.getString(kPrefSleepSoundPath);

      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          sleepChannelId,
          sleepChannelName,
          channelDescription: 'Alarme de réveil à la fin de votre période de sommeil',
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          color: Color(0xFF5E5CE6),
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      await _plugin.show(
        7777,
        '⏰ Mizwala — Test Alarme Réveil',
        'L\'alarme de réveil et de fin de sommeil fonctionne avec succès !',
        details,
      );

      if (soundPath != null && soundPath.isNotEmpty) {
        await playCustomSound(soundPath);
      }
    } catch (e) {
      debugPrint('Error sending test sleep notification: $e');
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
              prayerChannelId,
              prayerChannelName,
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

        // Planification de l'alarme de réveil (Sommeil)
        final sleepEnabled = prefs.getBool('sleep_enabled') ?? true;
        if (sleepEnabled) {
          final wH = prefs.getInt('sleep_wakeup_hour') ?? 6;
          final wM = prefs.getInt('sleep_wakeup_minute') ?? 30;

          DateTime wakeUtc = DateTime.utc(
            dayRef.year,
            dayRef.month,
            dayRef.day,
            wH,
            wM,
          ).subtract(const Duration(hours: 1));

          if (!wakeUtc.isBefore(nowUtc)) {
            final tzWakeTime = tz.TZDateTime.from(wakeUtc, tz.UTC);
            const wakeDetails = NotificationDetails(
              android: AndroidNotificationDetails(
                sleepChannelId,
                sleepChannelName,
                channelDescription: 'Alarme de réveil à la fin de votre période de sommeil',
                importance: Importance.max,
                priority: Priority.max,
                playSound: true,
                enableVibration: true,
                color: Color(0xFF5E5CE6),
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
                5000 + notifId++,
                '⏰ Fin de Sommeil & Réveil',
                'Il est l\'heure de votre réveil !',
                tzWakeTime,
                wakeDetails,
                androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
                uiLocalNotificationDateInterpretation:
                    UILocalNotificationDateInterpretation.absoluteTime,
              );
            } catch (_) {}
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
