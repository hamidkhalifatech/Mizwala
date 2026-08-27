import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';

class QiblaService {
  // Coordonnées de la Kaaba (La Mecque)
  static const double kaabaLat = 21.422487;
  static const double kaabaLng = 39.826206;

  // Coordonnées par défaut de Marrakech (31.63°N, 7.98°O)
  static double currentLat = 31.6295;
  static double currentLng = -7.9811;

  // Angle de la Qibla par rapport au Nord géographique (vrai Nord)
  static double qiblaBearingFromNorth = 94.75;

  static bool _initialized = false;

  /// Initialise la position GPS (si permission accordée) et le calcul de la Qibla
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Calcul initial pour Marrakech
    qiblaBearingFromNorth = calculateQiblaAngle(currentLat, currentLng);

    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null) {
        currentLat = pos.latitude;
        currentLng = pos.longitude;
        qiblaBearingFromNorth = calculateQiblaAngle(currentLat, currentLng);
      }
    } catch (e) {
      debugPrint('Qibla GPS init note: $e');
    }
  }

  /// Calcule l'angle géodésique précis (Grand Cercle) de la Qibla par rapport au Vrai Nord
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

  /// Flux d'orientation de la boussole retournant l'angle relatif de la Qibla sur l'écran (0° = sommet de l'appareil)
  static Stream<double?> get qiblaScreenAngleStream {
    return FlutterCompass.events?.map((CompassEvent event) {
          final heading = event.heading;
          if (heading == null) return null;
          // Angle relatif de la Qibla à l'écran (0° = vers le haut de l'écran du smartphone)
          final screenAngle = (qiblaBearingFromNorth - heading + 360.0) % 360.0;
          return screenAngle;
        }) ??
        Stream.value(null);
  }
}
