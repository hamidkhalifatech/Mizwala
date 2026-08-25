import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'prayer_times.dart';
import 'weather_service.dart';

/// Palette et repères de la direction artistique du prototype mizwala.html.
class MizwalaTheme {
  static const bg = Color(0xFF10141B);
  static const brass = Color(0xFFC9A24B);
  static const brassDim = Color(0xFF8A7038);
  static const ochre = Color(0xFFA3402C);
  static const parchment = Color(0xFFECE3D0);
  static const muted = Color(0xFF8993A4);
  static const nightBlue = Color(0xFF23354C);
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
    this.size = 320,
    this.weatherData,
    this.sleepBedtime = 23.0,
    this.sleepWakeup = 6.5,
    this.sleepEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _MizwalaPainter(
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

class _MizwalaPainter extends CustomPainter {
  final PrayerTimes times;
  final double currentHour;
  final WeatherData? weatherData;
  final double? sleepBedtime;
  final double? sleepWakeup;
  final bool sleepEnabled;

  _MizwalaPainter({
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
    final scale = size.width / 600; // le tracé est conçu sur une base 600px
    final center = Offset(cx, cy);
    final values = times.asMap();

    Offset pt(double angleDeg, double r) {
      final rad = angleDeg * math.pi / 180;
      return Offset(
        cx + r * scale * math.sin(rad),
        cy - r * scale * math.cos(rad),
      );
    }

    // Halo central
    final bgGradient = RadialGradient(
      colors: [
        MizwalaTheme.brass.withOpacity(0.06),
        Colors.transparent,
      ],
      radius: 0.5,
    );
    canvas.drawCircle(
      center,
      200 * scale,
      Paint()
        ..shader = bgGradient.createShader(
          Rect.fromCircle(center: center, radius: 200 * scale),
        ),
    );

    // Cercles décoratifs
    final ringPaint = Paint()
      ..color = MizwalaTheme.brass.withOpacity(0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 * scale;
    canvas.drawCircle(center, 272 * scale, ringPaint);
    canvas.drawCircle(center, 182 * scale, ringPaint);

    // Arc coloré de la journée liturgique (entre Fajr et Icha)
    final fajrAngle = MizwalaCalculator.angleFromTop(values['fajr']!, times.dhuhr);
    final ishaAngle = MizwalaCalculator.angleFromTop(values['isha']!, times.dhuhr);
    final arcPaint = Paint()
      ..color = MizwalaTheme.brass.withOpacity(0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10 * scale
      ..strokeCap = StrokeCap.round;
    final startRad = (fajrAngle - 90) * math.pi / 180;
    final sweepDeg = (ishaAngle - fajrAngle + 360) % 360;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 227 * scale),
      startRad,
      sweepDeg * math.pi / 180,
      false,
      arcPaint,
    );

    // Arc de Sommeil (entre coucher et réveil)
    if (sleepEnabled && sleepBedtime != null && sleepWakeup != null) {
      final sleepStartAngle = MizwalaCalculator.angleFromTop(sleepBedtime!, times.dhuhr);
      final sleepEndAngle = MizwalaCalculator.angleFromTop(sleepWakeup!, times.dhuhr);
      final sleepArcPaint = Paint()
        ..color = MizwalaTheme.nightBlue.withOpacity(0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6 * scale
        ..strokeCap = StrokeCap.round;
      final sleepStartRad = (sleepStartAngle - 90) * math.pi / 180;
      final sleepSweepDeg = (sleepEndAngle - sleepStartAngle + 360) % 360;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: 206 * scale),
        sleepStartRad,
        sleepSweepDeg * math.pi / 180,
        false,
        sleepArcPaint,
      );
    }

    // Couronne des prières (fixe pour la journée, Dohr en haut)
    for (final entry in kPrayerLabels) {
      final key = entry[0];
      final label = entry[1];
      final isDohr = key == 'dhuhr';
      final isSunrise = key == 'sunrise';
      final a = MizwalaCalculator.angleFromTop(values[key]!, times.dhuhr);

      // Trait radial vers le point
      canvas.drawLine(
        pt(a, 218),
        pt(a, 248),
        Paint()
          ..color = (isDohr ? MizwalaTheme.brass : MizwalaTheme.ochre)
              .withOpacity(0.5)
          ..strokeWidth = 1 * scale,
      );

      canvas.drawCircle(
        pt(a, 235),
        (isDohr ? 6 : 4.4) * scale,
        Paint()
          ..color = isDohr
              ? MizwalaTheme.brass
              : (isSunrise ? MizwalaTheme.muted : MizwalaTheme.ochre),
      );

      _drawLabel(
        canvas,
        label,
        pt(a, 260),
        color: isDohr ? MizwalaTheme.brass : MizwalaTheme.parchment,
        fontSize: 13.5 * scale,
        bold: isDohr,
      );
    }

    // Repère réglable pour le Sommeil sur la même couronne
    if (sleepEnabled && sleepBedtime != null) {
      final a = MizwalaCalculator.angleFromTop(sleepBedtime!, times.dhuhr);

      canvas.drawLine(
        pt(a, 218),
        pt(a, 248),
        Paint()
          ..color = MizwalaTheme.brassDim.withOpacity(0.4)
          ..strokeWidth = 1 * scale,
      );

      canvas.drawCircle(
        pt(a, 235),
        4.4 * scale,
        Paint()..color = const Color(0xFF6B7F96),
      );

      _drawLabel(
        canvas,
        'Sommeil',
        pt(a, 260),
        color: MizwalaTheme.muted,
        fontSize: 12 * scale,
      );
    }

    // Couronne des 24 heures (calée sur la même référence Dohr = 0°)
    for (int h = 0; h < 24; h++) {
      final a = MizwalaCalculator.angleFromTop(h.toDouble(), times.dhuhr);
      final major = h % 3 == 0;
      final p1 = pt(a, 182);
      final p2 = pt(a, major ? 166 : 174);
      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..color = major ? MizwalaTheme.brass : MizwalaTheme.brassDim
          ..strokeWidth = (major ? 1.6 : 1) * scale
          ..strokeCap = StrokeCap.round,
      );
      if (major) {
        _drawLabel(
          canvas,
          h.toString().padLeft(2, '0'),
          pt(a, 150),
          color: MizwalaTheme.muted,
          fontSize: 12 * scale,
        );
      }
    }

    // --- MÉTÉO EN TEMPS RÉEL AU CŒUR DU CADRAN ---
    if (weatherData != null) {
      _drawWeather(canvas, cx, cy, scale);
    }

    // Aiguille unique, un tour complet par 24h
    final needleAngle =
        MizwalaCalculator.angleFromTop(currentHour, times.dhuhr);
    final rad = needleAngle * math.pi / 180;
    final tip = Offset(
      cx + 150 * scale * math.sin(rad),
      cy - 150 * scale * math.cos(rad),
    );
    final tail = Offset(
      cx - 45 * scale * math.sin(rad),
      cy + 45 * scale * math.cos(rad),
    );

    // Halo de l'aiguille
    canvas.drawLine(
      center,
      tip,
      Paint()
        ..color = MizwalaTheme.brass.withOpacity(0.15)
        ..strokeWidth = 10 * scale
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawLine(
      center,
      tip,
      Paint()
        ..color = MizwalaTheme.brass
        ..strokeWidth = 3.4 * scale
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      center,
      tail,
      Paint()
        ..color = MizwalaTheme.ochre
        ..strokeWidth = 3 * scale
        ..strokeCap = StrokeCap.round,
    );

    // Rose centrale
    canvas.drawCircle(center, 10 * scale, Paint()..color = MizwalaTheme.bg);
    canvas.drawCircle(
        center,
        8 * scale,
        Paint()
          ..color = MizwalaTheme.brass
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * scale);
    canvas.drawCircle(center, 3 * scale, Paint()..color = MizwalaTheme.brass);
  }

  void _drawWeather(Canvas canvas, double cx, double cy, double scale) {
    final weather = weatherData!;
    final symbolPos = Offset(cx, cy + 56 * scale);

    // Symbole météo (Emoji / Symbole dynamique : ☀️, 🌙, 🌅, 🌧️, ⛅...)
    final symbolPainter = TextPainter(
      text: TextSpan(
        text: weather.iconSymbol,
        style: TextStyle(
          fontSize: 18 * scale,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    symbolPainter.paint(
      canvas,
      symbolPos - Offset(symbolPainter.width / 2, symbolPainter.height / 2),
    );

    // Températures discrètes : "24° · Max 31°"
    final tempStr = '${weather.currentTemp.round()}°  ·  Max ${weather.maxTemp.round()}°';
    final tempPainter = TextPainter(
      text: TextSpan(
        text: tempStr,
        style: GoogleFonts.cormorantGaramond(
          color: MizwalaTheme.parchment.withOpacity(0.9),
          fontSize: 13 * scale,
          fontWeight: FontWeight.w400,
          letterSpacing: 1.2,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    tempPainter.paint(
      canvas,
      Offset(cx - tempPainter.width / 2, cy + 74 * scale),
    );

    // Libellé de condition météo (ex. "Ensoleillé", "Pluie", "Crépuscule")
    final condPainter = TextPainter(
      text: TextSpan(
        text: weather.conditionLabel.toUpperCase(),
        style: GoogleFonts.cinzel(
          color: MizwalaTheme.brassDim,
          fontSize: 8.5 * scale,
          letterSpacing: 1.5,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    condPainter.paint(
      canvas,
      Offset(cx - condPainter.width / 2, cy + 90 * scale),
    );
  }

  void _drawLabel(
    Canvas canvas,
    String text,
    Offset pos, {
    required Color color,
    required double fontSize,
    bool bold = false,
  }) {
    final style = GoogleFonts.cinzel(
      color: color,
      fontSize: fontSize,
      fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
    );
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _MizwalaPainter oldDelegate) {
    return oldDelegate.currentHour != currentHour ||
        oldDelegate.times.dhuhr != times.dhuhr ||
        oldDelegate.weatherData != weatherData ||
        oldDelegate.sleepBedtime != sleepBedtime ||
        oldDelegate.sleepWakeup != sleepWakeup ||
        oldDelegate.sleepEnabled != sleepEnabled;
  }
}
