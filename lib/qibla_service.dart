import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';

class QiblaService {
  // Coordonnées de la Kaaba (La Mecque)
  static const double kaabaLat = 21.422487;
  static const double kaabaLng = 39.826206;

  // Coordonnées par défaut de Marrakech (31.63°N, 7.98°O)
  static double currentLat = 31.6295;
  static double currentLng = -7.9811;

  // Direction de la Kaaba depuis le Vrai Nord (Marrakech = 94.75° Est)
  static double qiblaBearingFromNorth = 94.75;

  static const EventChannel _compassChannel =
      EventChannel('com.mizwala.mizwala/compass');

  static bool _initialized = false;

  /// Initialise la position GPS et met à jour l'angle géographique de la Qibla
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    qiblaBearingFromNorth = calculateQiblaAngle(currentLat, currentLng);

    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.whileInUse ||
          perm == LocationPermission.always) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
        currentLat = pos.latitude;
        currentLng = pos.longitude;
        qiblaBearingFromNorth = calculateQiblaAngle(currentLat, currentLng);
      }
    } catch (e) {
      debugPrint('Qibla location note: $e');
    }
  }

  /// Calcule l'angle géodésique précis (Grand Cercle) de la Kaaba par rapport au Vrai Nord
  static double calculateQiblaAngle(double lat, double lng) {
    final latRad = lat * math.pi / 180.0;
    final lngRad = lng * math.pi / 180.0;
    final kLatRad = kaabaLat * math.pi / 180.0;
    final kLngRad = kaabaLng * math.pi / 180.0;

    final dLng = kLngRad - lngRad;
    final y = math.sin(dLng) * math.cos(kLatRad);
    final x = math.cos(latRad) * math.sin(kLatRad) -
        math.sin(latRad) * math.cos(kLatRad) * math.cos(dLng);

    var angle = math.atan2(y, x) * 180.0 / math.pi;
    if (angle < 0) angle += 360.0;
    return angle;
  }

  /// Flux continu de l'orientation du smartphone (cap en degrés [0, 360[ par rapport au Nord)
  static Stream<double> get deviceHeadingStream {
    try {
      return _compassChannel
          .receiveBroadcastStream()
          .map<double>((dynamic event) {
        if (event is num) {
          return event.toDouble();
        }
        return 0.0;
      });
    } catch (_) {
      return FlutterCompass.events?.map<double>((event) {
            return event.heading ?? 0.0;
          }) ??
          Stream.value(0.0);
    }
  }

  /// Calcule la différence angulaire la plus courte entre deux angles en degrés [-180, 180]
  static double shortestAngleDiff(double from, double to) {
    var diff = (to - from) % 360.0;
    if (diff > 180.0) diff -= 360.0;
    if (diff < -180.0) diff += 360.0;
    return diff;
  }
}
