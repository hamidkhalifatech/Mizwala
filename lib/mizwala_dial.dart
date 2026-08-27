import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'prayer_times.dart';
import 'weather_service.dart';

/// Palette Apple Final Design
class MizwalaTheme {
  static const bg = Color(0xFF0B0B0E);
  static const card = Color(0xFF0B0B0E);
  static const teal = Color(0xFF30B0C7);   // Prières (Fajr, Chourouk, Asr, Maghrib, Icha)
  static const amber = Color(0xFFFF9F0A);  // Dohr + Soleil
  static const indigo = Color(0xFF5E5CE6); // Sommeil
  static const moon = Color(0xFFC7D2E0);   // Lune
  static const label1 = Color(0xF2FFFFFF); // rgba(255,255,255,0.95)
  static const label2 = Color(0x99FFFFFF); // rgba(255,255,255,0.60)
  static const label3 = Color(0x80FFFFFF); // rgba(255,255,255,0.50)
  static const glassBorder = Color(0x1AFFFFFF); // rgba(255,255,255,0.10)
}

const List<String> kPrayerKeys = ['fajr', 'sunrise', 'asr', 'maghrib', 'isha'];

class MizwalaDial extends StatelessWidget {
  final PrayerTimes times;
  final double currentHourDecimal;
  final double size;
  final WeatherData? weatherData;
  final double sleepBedtime;
  final double sleepWakeup;
  final bool sleepEnabled;
  final ValueChanged<double>? onSleepBedtimeChanged;
  final ValueChanged<double>? onSleepWakeupChanged;

  const MizwalaDial({
    super.key,
    required this.times,
    required this.currentHourDecimal,
    this.size = 340,
    this.weatherData,
    this.sleepBedtime = 23.0,
    this.sleepWakeup = 6.5,
    this.sleepEnabled = true,
    this.onSleepBedtimeChanged,
    this.onSleepWakeupChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scale = size / 340.0;
    final discSize = 160.0 * scale;

    // Couleur du ciel dynamique
    final skyColor = WeatherService.computeSkyColor(
      currentHourDecimal,
      times,
      weatherData?.conditionType ?? 'clear',
    );

    // Données de l'horloge et températures
    final hh = (currentHourDecimal.floor() % 24).toString().padLeft(2, '0');
    final mm = (((currentHourDecimal - currentHourDecimal.floor()) * 60).round() % 60)
        .toString()
        .padLeft(2, '0');
    final clockStr = '$hh:$mm';

    final tempStr = weatherData != null ? '${weatherData!.currentTemp.round()}°' : '--°';
    final hlStr = weatherData != null
        ? 'H:${weatherData!.maxTemp.round()}°  L:${weatherData!.minTemp.round()}°'
        : 'H:--°  L:--°';

    // Calcul du chrono / compte à rebours avant le sommeil
    String sleepCountdownBadge = '';
    if (sleepEnabled) {
      final bool isSleeping = (sleepBedtime <= sleepWakeup)
          ? (currentHourDecimal >= sleepBedtime && currentHourDecimal < sleepWakeup)
          : (currentHourDecimal >= sleepBedtime || currentHourDecimal < sleepWakeup);

      if (isSleeping) {
        final rem = (sleepWakeup - currentHourDecimal + 24.0) % 24.0;
        final rH = rem.floor();
        final rM = ((rem - rH) * 60).round();
        sleepCountdownBadge = rM > 0
            ? '🌙 Réveil dans ${rH}h${rM.toString().padLeft(2, '0')}'
            : '🌙 Réveil dans ${rH}h';
      } else {
        final toSleep = (sleepBedtime - currentHourDecimal + 24.0) % 24.0;
        final tH = toSleep.floor();
        final tM = ((toSleep - tH) * 60).round();
        sleepCountdownBadge = tM > 0
            ? '🌙 Sommeil dans ${tH}h${tM.toString().padLeft(2, '0')}'
            : '🌙 Sommeil dans ${tH}h';
      }
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 1. Anneau interactif (prières, arc diurne bleu nuit, sommeil, durée sommeil, soleil/lune)
          _InteractiveDialRing(
            size: size,
            times: times,
            currentHour: currentHourDecimal,
            sleepBedtime: sleepBedtime,
            sleepWakeup: sleepWakeup,
            sleepEnabled: sleepEnabled,
            onSleepBedtimeChanged: onSleepBedtimeChanged,
            onSleepWakeupChanged: onSleepWakeupChanged,
          ),

          // 2. Disque central dynamique avec Chrono bien visible sous Max/Min
          AnimatedContainer(
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeInOut,
            width: discSize,
            height: discSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: skyColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.45),
                  blurRadius: 24 * scale,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Icône météo
                _buildWeatherIcon(scale),
                const SizedBox(height: 1),
                // Horloge numérique
                Text(
                  clockStr,
                  style: TextStyle(
                    fontSize: 36 * scale,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: -0.02 * (36 * scale),
                    height: 1.05,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontFamily: '-apple-system',
                  ),
                ),
                const SizedBox(height: 2),
                // Température actuelle
                Text(
                  tempStr,
                  style: TextStyle(
                    fontSize: 15 * scale,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withOpacity(0.90),
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontFamily: '-apple-system',
                  ),
                ),
                // Températures Max / Min
                Text(
                  hlStr,
                  style: TextStyle(
                    fontSize: 10.5 * scale,
                    fontWeight: FontWeight.w500,
                    color: MizwalaTheme.label3,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontFamily: '-apple-system',
                  ),
                ),
                // Chrono avant sommeil bien visible en bas de Max/Min
                if (sleepCountdownBadge.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: 8 * scale, vertical: 2 * scale),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                          color: const Color(0x4D5E5CE6), width: 0.8),
                    ),
                    child: Text(
                      sleepCountdownBadge,
                      style: TextStyle(
                        fontSize: 9.5 * scale,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFC7D2FE), // Violet clair lisible
                        letterSpacing: 0.02,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        fontFamily: '-apple-system',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherIcon(double scale) {
    final isDay = currentHourDecimal >= times.sunrise && currentHourDecimal < times.maghrib;
    final isSunset = isDay && currentHourDecimal >= (times.maghrib - 1.0);
    final condition = weatherData?.conditionType ?? 'clear';

    IconData iconData;
    Color iconColor;

    if (condition == 'rain') {
      iconData = Icons.grain;
      iconColor = const Color(0xFF8AD1E8);
    } else if (condition == 'storm') {
      iconData = Icons.flash_on;
      iconColor = const Color(0xFFFFD60A);
    } else if (condition == 'clouds') {
      iconData = Icons.cloud;
      iconColor = Colors.white70;
    } else if (isSunset) {
      iconData = Icons.wb_twilight;
      iconColor = MizwalaTheme.amber;
    } else if (isDay) {
      iconData = Icons.wb_sunny;
      iconColor = MizwalaTheme.amber;
    } else {
      iconData = Icons.nights_stay;
      iconColor = MizwalaTheme.moon;
    }

    return Icon(
      iconData,
      size: 24 * scale,
      color: iconColor,
    );
  }
}

/// Dessin de l'anneau SVG + gestion du glisser des poignées de sommeil
class _InteractiveDialRing extends StatefulWidget {
  final double size;
  final PrayerTimes times;
  final double currentHour;
  final double sleepBedtime;
  final double sleepWakeup;
  final bool sleepEnabled;
  final ValueChanged<double>? onSleepBedtimeChanged;
  final ValueChanged<double>? onSleepWakeupChanged;

  const _InteractiveDialRing({
    required this.size,
    required this.times,
    required this.currentHour,
    required this.sleepBedtime,
    required this.sleepWakeup,
    required this.sleepEnabled,
    this.onSleepBedtimeChanged,
    this.onSleepWakeupChanged,
  });

  @override
  State<_InteractiveDialRing> createState() => _InteractiveDialRingState();
}

class _InteractiveDialRingState extends State<_InteractiveDialRing> {
  String? _dragTarget; // 'start' | 'end' | null

  void _handlePointerDown(Offset localPos) {
    if (!widget.sleepEnabled) return;

    final scale = widget.size / 340.0;
    final cx = widget.size / 2;
    final cy = widget.size / 2;
    final r = 133.0 * scale;

    Offset pt(double angleDeg) {
      final rad = angleDeg * math.pi / 180.0;
      return Offset(cx + r * math.sin(rad), cy - r * math.cos(rad));
    }

    final aStart = MizwalaCalculator.angleFromTop(widget.sleepBedtime, widget.times.dhuhr);
    final aEnd = MizwalaCalculator.angleFromTop(widget.sleepWakeup, widget.times.dhuhr);

    final pStart = pt(aStart);
    final pEnd = pt(aEnd);

    final hitRadius = 26.0 * scale;

    if ((localPos - pStart).distance <= hitRadius) {
      setState(() => _dragTarget = 'start');
    } else if ((localPos - pEnd).distance <= hitRadius) {
      setState(() => _dragTarget = 'end');
    }
  }

  void _handlePointerMove(Offset localPos) {
    if (_dragTarget == null) return;

    final cx = widget.size / 2;
    final cy = widget.size / 2;
    final dx = localPos.dx - cx;
    final dy = -(localPos.dy - cy);

    var angleDeg = (math.atan2(dx, dy) * 180.0 / math.pi) % 360.0;
    if (angleDeg < 0) angleDeg += 360.0;

    var time = (widget.times.dhuhr + angleDeg / 15.0) % 24.0;
    if (time < 0) time += 24.0;

    // Arrondir au quart d'heure ou 5 minutes
    final roundedMinute = (((time - time.floor()) * 60) / 5).round() * 5;
    final roundedTime = (time.floor() + roundedMinute / 60.0) % 24.0;

    if (_dragTarget == 'start') {
      widget.onSleepBedtimeChanged?.call(roundedTime);
    } else if (_dragTarget == 'end') {
      widget.onSleepWakeupChanged?.call(roundedTime);
    }
  }

  void _handlePointerUp() {
    if (_dragTarget != null) {
      setState(() => _dragTarget = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (e) => _handlePointerDown(e.localPosition),
      onPointerMove: (e) => _handlePointerMove(e.localPosition),
      onPointerUp: (_) => _handlePointerUp(),
      onPointerCancel: (_) => _handlePointerUp(),
      child: CustomPaint(
        size: Size(widget.size, widget.size),
        painter: _AppleFinalDialPainter(
          times: widget.times,
          currentHour: widget.currentHour,
          sleepBedtime: widget.sleepBedtime,
          sleepWakeup: widget.sleepWakeup,
          sleepEnabled: widget.sleepEnabled,
        ),
      ),
    );
  }
}

class _AppleFinalDialPainter extends CustomPainter {
  final PrayerTimes times;
  final double currentHour;
  final double sleepBedtime;
  final double sleepWakeup;
  final bool sleepEnabled;

  _AppleFinalDialPainter({
    required this.times,
    required this.currentHour,
    required this.sleepBedtime,
    required this.sleepWakeup,
    required this.sleepEnabled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 340.0;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final center = Offset(cx, cy);
    final r = 133.0 * scale;

    Offset pt(double angleDeg, [double radiusOffset = 0.0]) {
      final rad = angleDeg * math.pi / 180.0;
      final currentR = r + radiusOffset;
      return Offset(cx + currentR * math.sin(rad), cy - currentR * math.cos(rad));
    }

    // 1. Cercle guide subtil
    final ringPaint = Paint()
      ..color = MizwalaTheme.glassBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 * scale;
    canvas.drawCircle(center, r, ringPaint);

    // 2. Arc Diurne Fixe (Lever du Soleil -> Maghrib en Bleu Nuit #1E3A5F)
    final aSunrise = MizwalaCalculator.angleFromTop(times.sunrise, times.dhuhr);
    final aMaghrib = MizwalaCalculator.angleFromTop(times.maghrib, times.dhuhr);
    final daySweepDeg = (aMaghrib - aSunrise + 360.0) % 360.0;
    final dayStartRad = (aSunrise - 90.0) * math.pi / 180.0;

    final dayArcPaint = Paint()
      ..color = const Color(0xFF1E3A5F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.5 * scale
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      dayStartRad,
      daySweepDeg * math.pi / 180.0,
      false,
      dayArcPaint,
    );

    // 3. Arc de Sommeil Indigo (épaisseur 6.5px)
    if (sleepEnabled) {
      final aStart = MizwalaCalculator.angleFromTop(sleepBedtime, times.dhuhr);
      final aEnd = MizwalaCalculator.angleFromTop(sleepWakeup, times.dhuhr);

      final sleepArcPaint = Paint()
        ..color = MizwalaTheme.indigo
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.5 * scale
        ..strokeCap = StrokeCap.round;

      final startRad = (aStart - 90.0) * math.pi / 180.0;
      final sweepDeg = (aEnd - aStart + 360.0) % 360.0;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        startRad,
        sweepDeg * math.pi / 180.0,
        false,
        sleepArcPaint,
      );

      // Durée de sommeil (heures et minutes)
      final sleepDurationDec = (sleepWakeup - sleepBedtime + 24.0) % 24.0;
      final sleepHours = sleepDurationDec.floor();
      final sleepMins = ((sleepDurationDec - sleepHours) * 60).round();
      final durationText = sleepMins > 0
          ? '${sleepHours}h${sleepMins.toString().padLeft(2, '0')}'
          : '${sleepHours}h';

      // Affichage de la durée sur l'arc de sommeil
      final aMid = (aStart + (sweepDeg / 2.0)) % 360.0;
      final badgePos = pt(aMid, -18.0 * scale);

      final badgePainter = TextPainter(
        text: TextSpan(
          text: durationText,
          style: TextStyle(
            color: Colors.white,
            fontSize: 9.5 * scale,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.02,
            fontFamily: '-apple-system',
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();

      final pillRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: badgePos,
          width: badgePainter.width + 12 * scale,
          height: badgePainter.height + 5 * scale,
        ),
        Radius.circular(100 * scale),
      );

      canvas.drawRRect(
        pillRect,
        Paint()..color = MizwalaTheme.indigo.withOpacity(0.90),
      );

      badgePainter.paint(
        canvas,
        badgePos - Offset(badgePainter.width / 2, badgePainter.height / 2),
      );

      // Poignées de Sommeil (r=5.5px)
      final s = pt(aStart);
      final e = pt(aEnd);

      for (final p in [s, e]) {
        // Fond noir intérieur
        canvas.drawCircle(
          p,
          5.5 * scale,
          Paint()..color = MizwalaTheme.bg,
        );
        // Bordure indigo
        canvas.drawCircle(
          p,
          5.5 * scale,
          Paint()
            ..color = MizwalaTheme.indigo
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8 * scale,
        );
      }
    }

    // 4. Repères des 5 prières Teal (r=4.5px)
    final values = times.asMap();
    for (final key in kPrayerKeys) {
      final a = MizwalaCalculator.angleFromTop(values[key]!, times.dhuhr);
      final p = pt(a);

      // Fond noir
      canvas.drawCircle(p, 4.5 * scale, Paint()..color = MizwalaTheme.bg);
      // Bordure Teal
      canvas.drawCircle(
        p,
        4.5 * scale,
        Paint()
          ..color = MizwalaTheme.teal
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 * scale,
      );
    }

    // 5. Dohr (Ambre au sommet 0°, r=4.5px)
    final aDohr = MizwalaCalculator.angleFromTop(times.dhuhr, times.dhuhr);
    final pDohr = pt(aDohr);

    // Fond noir
    canvas.drawCircle(pDohr, 4.5 * scale, Paint()..color = MizwalaTheme.bg);
    // Bordure Ambre
    canvas.drawCircle(
      pDohr,
      4.5 * scale,
      Paint()
        ..color = MizwalaTheme.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * scale,
    );

    // 6. Curseur Soleil / Lune (r=12px, noyau=6.5px, halo)
    final timeAngle = MizwalaCalculator.angleFromTop(currentHour, times.dhuhr);
    final isDay = currentHour >= times.sunrise && currentHour < times.maghrib;
    final sp = pt(timeAngle);
    final markerColor = isDay ? MizwalaTheme.amber : MizwalaTheme.moon;

    // Halo subtil pour le soleil en journée
    if (isDay) {
      canvas.drawCircle(
        sp,
        16.0 * scale,
        Paint()..color = MizwalaTheme.amber.withOpacity(0.20),
      );
    }

    // Anneau extérieur du curseur
    canvas.drawCircle(
      sp,
      12.0 * scale,
      Paint()
        ..color = markerColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * scale,
    );

    // Noyau plein central du curseur
    canvas.drawCircle(
      sp,
      6.5 * scale,
      Paint()..color = markerColor,
    );
  }

  @override
  bool shouldRepaint(covariant _AppleFinalDialPainter oldDelegate) {
    return oldDelegate.currentHour != currentHour ||
        oldDelegate.times.dhuhr != times.dhuhr ||
        oldDelegate.sleepBedtime != sleepBedtime ||
        oldDelegate.sleepWakeup != sleepWakeup ||
        oldDelegate.sleepEnabled != sleepEnabled;
  }
}
