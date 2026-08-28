import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

class QiblaService {
  // Coordonnées de la Kaaba (La Mecque)
  static const double kaabaLat = 21.422487;
  static const double kaabaLng = 39.826206;

  // Coordonnées de Marrakech par défaut (31.63°N, 7.98°O)
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
      debugPrint('Qibla location init: $e');
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

  /// Flux continu combiné multi-moteurs (Capteurs natifs Android + SensorsPlus 3D Math + FlutterCompass)
  static Stream<double> get deviceHeadingStream {
    late StreamController<double> controller;
    StreamSubscription<dynamic>? subNative;
    StreamSubscription<AccelerometerEvent>? subAccel;
    StreamSubscription<MagnetometerEvent>? subMag;
    StreamSubscription<CompassEvent>? subCompass;

    double ax = 0, ay = 0, az = 9.8;
    double mx = 0, my = 0, mz = 0;
    bool hasAccel = false;
    bool hasMag = false;

    void computeFromSensors() {
      if (!hasAccel || !hasMag || controller.isClosed) return;

      // Calcul vectoriel de l'azimut (East = Mag x Accel, North = Accel x East)
      final hx = my * az - mz * ay;
      final hy = mz * ax - mx * az;
      final hz = mx * ay - my * ax;
      final hNorm = math.sqrt(hx * hx + hy * hy + hz * hz);
      if (hNorm == 0) return;

      final aNorm = math.sqrt(ax * ax + ay * ay + az * az);
      if (aNorm == 0) return;
      final aNx = ax / aNorm;
      final aNy = ay / aNorm;
      final aNz = az / aNorm;

      final mxPrime = aNy * (hz / hNorm) - aNz * (hy / hNorm);
      final myPrime = aNz * (hx / hNorm) - aNx * (hz / hNorm);

      var azimuthRad = math.atan2(hx / hNorm, myPrime);
      var deg = azimuthRad * 180.0 / math.pi;
      if (deg < 0) deg += 360.0;

      controller.add(deg % 360.0);
    }

    controller = StreamController<double>.broadcast(
      onListen: () {
        // 1. Canal natif Android 3D
        try {
          subNative = _compassChannel.receiveBroadcastStream().listen(
            (dynamic event) {
              if (event is num && !controller.isClosed) {
                var h = event.toDouble();
                if (h < 0) h += 360.0;
                controller.add(h % 360.0);
              }
            },
            onError: (_) {},
          );
        } catch (_) {}

        // 2. sensors_plus Accéléromètre + Magnétomètre en pur calcul matriciel Dart
        try {
          subAccel = accelerometerEventStream().listen(
            (event) {
              ax = ax * 0.7 + event.x * 0.3;
              ay = ay * 0.7 + event.y * 0.3;
              az = az * 0.7 + event.z * 0.3;
              hasAccel = true;
              computeFromSensors();
            },
            onError: (_) {},
          );

          subMag = magnetometerEventStream().listen(
            (event) {
              mx = mx * 0.7 + event.x * 0.3;
              my = my * 0.7 + event.y * 0.3;
              mz = mz * 0.7 + event.z * 0.3;
              hasMag = true;
              computeFromSensors();
            },
            onError: (_) {},
          );
        } catch (_) {}

        // 3. flutter_compass
        try {
          subCompass = FlutterCompass.events?.listen(
            (event) {
              if (event.heading != null && !controller.isClosed) {
                var h = event.heading!;
                if (h < 0) h += 360.0;
                controller.add(h % 360.0);
              }
            },
            onError: (_) {},
          );
        } catch (_) {}
      },
      onCancel: () {
        subNative?.cancel();
        subAccel?.cancel();
        subMag?.cancel();
        subCompass?.cancel();
      },
    );

    return controller.stream;
  }

  /// Calcule la différence angulaire la plus courte entre deux angles en degrés [-180, 180]
  static double shortestAngleDiff(double from, double to) {
    var diff = (to - from) % 360.0;
    if (diff > 180.0) diff -= 360.0;
    if (diff < -180.0) diff += 360.0;
    return diff;
  }
}
