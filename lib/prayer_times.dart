import 'dart:math' as math;

/// Les six horaires de prière d'une journée, exprimés en heures décimales
/// (ex. 13.5 = 13h30), heure du Maroc.
class PrayerTimes {
  final double fajr;
  final double sunrise;
  final double dhuhr;
  final double asr;
  final double maghrib;
  final double isha;

  const PrayerTimes({
    required this.fajr,
    required this.sunrise,
    required this.dhuhr,
    required this.asr,
    required this.maghrib,
    required this.isha,
  });

  Map<String, double> asMap() => {
        'fajr': fajr,
        'sunrise': sunrise,
        'dhuhr': dhuhr,
        'asr': asr,
        'maghrib': maghrib,
        'isha': isha,
      };
}

class _SunPosition {
  final double decl;
  final double eqt;
  const _SunPosition(this.decl, this.eqt);
}

/// Calcul des horaires de prière pour Marrakech par formule astronomique
/// (déclinaison solaire + équation du temps). 100% local, aucune API,
/// aucune connexion requise. Portage direct du prototype mizwala.html.
class MizwalaCalculator {
  static const double lat = 31.6295;
  static const double lng = -7.9811;
  static const double tz = 1; // Maroc, UTC+1 fixe (hors parenthèse Ramadan)
  static const double fajrAngle = 19;
  static const double ishaAngle = 17;
  static const double asrFactor = 1; // école malikite (ombre = longueur de l'objet)

  static double _toRad(double d) => d * math.pi / 180;
  static double _toDeg(double r) => r * 180 / math.pi;

  static double _fixAngle(double a) {
    a = a % 360;
    return a < 0 ? a + 360 : a;
  }

  static double _fixHour(double h) {
    h = h % 24;
    return h < 0 ? h + 24 : h;
  }

  static double _julianDate(int y, int m, int d) {
    if (m <= 2) {
      y -= 1;
      m += 12;
    }
    final a = (y / 100).floor();
    final b = 2 - a + (a / 4).floor();
    return (365.25 * (y + 4716)).floor() +
        (30.6001 * (m + 1)).floor() +
        d +
        b -
        1524.5;
  }

  static _SunPosition _sunPosition(double jd) {
    final d = jd - 2451545.0;
    final g = _fixAngle(357.529 + 0.98560028 * d);
    final q = _fixAngle(280.459 + 0.98564736 * d);
    final l = _fixAngle(
        q + 1.915 * math.sin(_toRad(g)) + 0.020 * math.sin(_toRad(2 * g)));
    final e = 23.439 - 0.00000036 * d;
    var ra = _toDeg(math.atan2(
            math.cos(_toRad(e)) * math.sin(_toRad(l)), math.cos(_toRad(l)))) /
        15;
    ra = _fixHour(ra);
    final eqt = q / 15 - ra;
    final decl = _toDeg(math.asin(math.sin(_toRad(e)) * math.sin(_toRad(l))));
    return _SunPosition(decl, eqt);
  }

  static double _hourAngle(double angleDeg, double lat, double decl) {
    final term = (-math.sin(_toRad(angleDeg)) -
            math.sin(_toRad(lat)) * math.sin(_toRad(decl))) /
        (math.cos(_toRad(lat)) * math.cos(_toRad(decl)));
    final c = term.clamp(-1.0, 1.0);
    return _toDeg(math.acos(c)) / 15;
  }

  static double _asrAngle(double lat, double decl, double factor) {
    final alt =
        _toDeg(math.atan(1 / (factor + math.tan(_toRad((lat - decl).abs())))));
    return -alt; // altitude positive => angle négatif (au-dessus de l'horizon)
  }

  /// Calcule les 6 horaires pour la date [y]-[m]-[d] ("jour de Marrakech",
  /// pas forcément le fuseau de l'appareil : voir MizwalaClock).
  static PrayerTimes compute(int y, int m, int d) {
    final jd = _julianDate(y, m, d);
    final sun = _sunPosition(jd);
    final dhuhr = _fixHour(12 + tz - lng / 15 - sun.eqt);
    final fajr = _fixHour(dhuhr - _hourAngle(fajrAngle, lat, sun.decl));
    final sunrise = _fixHour(dhuhr - _hourAngle(0.833, lat, sun.decl));
    final asr = _fixHour(dhuhr +
        _hourAngle(_asrAngle(lat, sun.decl, asrFactor), lat, sun.decl));
    final maghrib = _fixHour(dhuhr + _hourAngle(0.833, lat, sun.decl));
    final isha = _fixHour(dhuhr + _hourAngle(ishaAngle, lat, sun.decl));
    return PrayerTimes(
      fajr: fajr,
      sunrise: sunrise,
      dhuhr: dhuhr,
      asr: asr,
      maghrib: maghrib,
      isha: isha,
    );
  }

  /// Angle en degrés depuis le sommet du cadran (sens horaire), Dohr = 0°.
  /// C'est la formule unique qui positionne à la fois les repères de
  /// prière et l'aiguille : elles restent donc toujours cohérentes entre
  /// elles, quel que soit le jour.
  static double angleFromTop(double t, double dhuhr) {
    return _fixAngle((t - dhuhr) * 15);
  }

  /// Formate une heure décimale en "HH:MM".
  static String format(double h) {
    var hh = h.floor();
    var mm = ((h - hh) * 60).round();
    if (mm == 60) {
      mm = 0;
      hh = (hh + 1) % 24;
    }
    return '${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
  }
}
