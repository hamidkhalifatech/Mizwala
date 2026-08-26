import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'prayer_times.dart';
import 'weather_service.dart';

/// Palette Apple / Liquid Glass
class MizwalaTheme {
  static const bg0 = Color(0xFF0A0A0C);
  static const bg1 = Color(0xFF151519);
  static const bgCard = Color(0xFF1A1A1E);
  static const glass = Color(0x12FFFFFF); // rgba(255,255,255,0.07)
  static const glassStrong = Color(0x1CFFFFFF); // rgba(255,255,255,0.11)
  static const glassBorder = Color(0x24FFFFFF); // rgba(255,255,255,0.14)
  static const label1 = Color(0xF0FFFFFF); // rgba(255,255,255,0.94)
  static const label2 = Color(0x94FFFFFF); // rgba(255,255,255,0.58)
  static const label3 = Color(0x57FFFFFF); // rgba(255,255,255,0.34)
  static const accent = Color(0xFFFF9F0A); // Apple Orange / Amber
  static const accentDim = Color(0x38FF9F0A); // rgba(255,159,10,0.22)
  static const accentBorder = Color(0x59FF9F0A); // rgba(255,159,10,0.35)
}

const List<List<String>> kPrayerLabels = [
  ['fajr', 'Fajr'],
  ['sunrise', 'Chourouk'],
  ['dhuhr', 'Dohr'],
  ['asr', 'Asr'],
  ['maghrib', 'Maghrib'],
  ['isha', 'Icha'],
];

class MizwalaDial extends StatelessWidget {
  final PrayerTimes times;
  final double currentHourDecimal;
  final double size;
  final WeatherData? weatherData;
  final double? sleepBedtime;
  final double? sleepWakeup;
  final bool sleepEnabled;

  const MizwalaDial({
    super.key,
    required this.times,
    required this.currentHourDecimal,
    this.size = 280,
    this.weatherData,
    this.sleepBedtime = 23.0,
    this.sleepWakeup = 6.5,
    this.sleepEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _MizwalaApplePainter(
        times: times,
        currentHour: currentHourDecimal,
        weatherData: weatherData,
        sleepBedtime: sleepBedtime,
        sleepWakeup: sleepWakeup,
        sleepEnabled: sleepEnabled,
      ),
    );
  }
}

class _MizwalaApplePainter extends CustomPainter {
  final PrayerTimes times;
  final double currentHour;
  final WeatherData? weatherData;
  final double? sleepBedtime;
  final double? sleepWakeup;
  final bool sleepEnabled;

  _MizwalaApplePainter({
    required this.times,
    required this.currentHour,
    this.weatherData,
    this.sleepBedtime,
    this.sleepWakeup,
    this.sleepEnabled = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final scale = size.width / 300; // Base 300px
    final center = Offset(cx, cy);
    final values = times.asMap();

    Offset pt(double angleDeg, double r) {
      final rad = angleDeg * math.pi / 180;
      return Offset(
        cx + r * scale * math.sin(rad),
        cy - r * scale * math.cos(rad),
      );
    }

    // 1. Cercle extérieur subtil
    final outerRing = Paint()
      ..color = const Color(0x1AFFFFFF) // rgba(255,255,255,0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 * scale;
    canvas.drawCircle(center, 130 * scale, outerRing);

    // 2. Arc du jour solaire (Chourouk -> Maghrib)
    final aSunrise = MizwalaCalculator.angleFromTop(times.sunrise, times.dhuhr);
    final aMaghrib = MizwalaCalculator.angleFromTop(times.maghrib, times.dhuhr);
    final dayArcPaint = Paint()
      ..color = MizwalaTheme.accent.withOpacity(0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 * scale
      ..strokeCap = StrokeCap.round;
    final startRad = (aSunrise - 90) * math.pi / 180;
    final sweepDeg = (aMaghrib - aSunrise + 360) % 360;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 120 * scale),
      startRad,
      sweepDeg * math.pi / 180,
      false,
      dayArcPaint,
    );

    // 3. Arc de Sommeil (Coucher -> Réveil) si activé
    if (sleepEnabled && sleepBedtime != null && sleepWakeup != null) {
      final aBed = MizwalaCalculator.angleFromTop(sleepBedtime!, times.dhuhr);
      final aWake = MizwalaCalculator.angleFromTop(sleepWakeup!, times.dhuhr);
      final sleepArcPaint = Paint()
        ..color = const Color(0x2EFFFFFF) // rgba(255,255,255,0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 * scale
        ..strokeCap = StrokeCap.round;
      final sleepStartRad = (aBed - 90) * math.pi / 180;
      final sleepSweepDeg = (aWake - aBed + 360) % 360;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: 120 * scale),
        sleepStartRad,
        sleepSweepDeg * math.pi / 180,
        false,
        sleepArcPaint,
      );
    }

    // 4. Graduations des 24 heures
    for (int h = 0; h < 24; h++) {
      final a = MizwalaCalculator.angleFromTop(h.toDouble(), times.dhuhr);
      final major = h % 6 == 0;
      final semi = h % 3 == 0 && !major;
      final p1 = pt(a, 130);
      final p2 = pt(a, major ? 116 : (semi ? 120 : 123));

      final tickPaint = Paint()
        ..color = major
            ? const Color(0x73FFFFFF) // rgba(255,255,255,0.45)
            : (semi ? const Color(0x40FFFFFF) : const Color(0x29FFFFFF))
        ..strokeWidth = (major ? 1.6 : 1) * scale
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(p1, p2, tickPaint);
    }

    // 5. Repères des prières sur l'anneau intérieur
    for (final entry in kPrayerLabels) {
      final key = entry[0];
      final isDohr = key == 'dhuhr';
      final a = MizwalaCalculator.angleFromTop(values[key]!, times.dhuhr);
      final m = pt(a, 112);

      final markPaint = Paint()
        ..color = isDohr ? MizwalaTheme.accent : const Color(0x8CFFFFFF);
      canvas.drawCircle(m, (isDohr ? 5.5 : 3.4) * scale, markPaint);
    }

    // Repère de Sommeil
    if (sleepEnabled && sleepBedtime != null) {
      final a = MizwalaCalculator.angleFromTop(sleepBedtime!, times.dhuhr);
      final m = pt(a, 112);
      final sleepMarkPaint = Paint()..color = const Color(0x66FFFFFF);
      canvas.drawCircle(m, 3.4 * scale, sleepMarkPaint);
    }

    // 6. Curseur Soleil / Lune sur l'arc (suivant l'heure actuelle)
    final needleAngle =
        MizwalaCalculator.angleFromTop(currentHour, times.dhuhr);
    final isDay = currentHour >= times.sunrise && currentHour <= times.maghrib;
    final sunPos = pt(needleAngle, 120);

    // Halo
    final haloPaint = Paint()
      ..color = isDay
          ? MizwalaTheme.accent.withOpacity(0.25)
          : const Color(0x2EFFFFFF);
    canvas.drawCircle(sunPos, 7 * scale, haloPaint);

    // Noyau
    final corePaint = Paint()
      ..color = isDay ? MizwalaTheme.accent : const Color(0xD9FFFFFF);
    canvas.drawCircle(sunPos, 3.4 * scale, corePaint);

    // 7. Aiguille unique orange
    final rad = needleAngle * math.pi / 180;
    final tip = Offset(
      cx + 90 * scale * math.sin(rad),
      cy - 90 * scale * math.cos(rad),
    );

    // Ligne aiguille
    final needlePaint = Paint()
      ..color = MizwalaTheme.accent
      ..strokeWidth = 3 * scale
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, tip, needlePaint);

    // Point pivot central
    final centerDotPaint = Paint()..color = MizwalaTheme.accent;
    canvas.drawCircle(center, 4.5 * scale, centerDotPaint);

    // 8. Météo temps réel au centre (discret)
    if (weatherData != null) {
      _drawWeatherInfo(canvas, cx, cy, scale);
    }
  }

  void _drawWeatherInfo(Canvas canvas, double cx, double cy, double scale) {
    final weather = weatherData!;

    // Symbole météo (☀️, 🌙, 🌅, 🌧️, ⛅...)
    final symbolPainter = TextPainter(
      text: TextSpan(
        text: weather.iconSymbol,
        style: TextStyle(
          fontSize: 16 * scale,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    symbolPainter.paint(
      canvas,
      Offset(cx - symbolPainter.width / 2, cy + 42 * scale),
    );

    // Température actuelle et max : "24° · Max 31°"
    final tempStr = '${weather.currentTemp.round()}° · Max ${weather.maxTemp.round()}°';
    final tempPainter = TextPainter(
      text: TextSpan(
        text: tempStr,
        style: TextStyle(
          color: MizwalaTheme.label2,
          fontSize: 11.5 * scale,
          fontWeight: FontWeight.w500,
          fontFeatures: const [FontFeature.tabularFigures()],
          fontFamily: '-apple-system',
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    tempPainter.paint(
      canvas,
      Offset(cx - tempPainter.width / 2, cy + 62 * scale),
    );
  }

  @override
  bool shouldRepaint(covariant _MizwalaApplePainter oldDelegate) {
    return oldDelegate.currentHour != currentHour ||
        oldDelegate.times.dhuhr != times.dhuhr ||
        oldDelegate.weatherData != weatherData ||
        oldDelegate.sleepBedtime != sleepBedtime ||
        oldDelegate.sleepWakeup != sleepWakeup ||
        oldDelegate.sleepEnabled != sleepEnabled;
  }
}
