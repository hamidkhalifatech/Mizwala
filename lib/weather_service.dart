import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'prayer_times.dart';

class WeatherData {
  final double currentTemp;
  final double maxTemp;
  final double minTemp;
  final int weatherCode;
  final bool isDay;
  final String conditionType; // 'clear' | 'clouds' | 'rain' | 'storm'
  final String iconSymbol;
  final String conditionLabel;

  const WeatherData({
    required this.currentTemp,
    required this.maxTemp,
    required this.minTemp,
    required this.weatherCode,
    required this.isDay,
    required this.conditionType,
    required this.iconSymbol,
    required this.conditionLabel,
  });

  Map<String, dynamic> toJson() => {
        'currentTemp': currentTemp,
        'maxTemp': maxTemp,
        'minTemp': minTemp,
        'weatherCode': weatherCode,
        'isDay': isDay,
        'conditionType': conditionType,
        'iconSymbol': iconSymbol,
        'conditionLabel': conditionLabel,
      };

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    return WeatherData(
      currentTemp: (json['currentTemp'] as num).toDouble(),
      maxTemp: (json['maxTemp'] as num).toDouble(),
      minTemp: (json['minTemp'] as num?)?.toDouble() ??
          ((json['maxTemp'] as num).toDouble() - 8.0),
      weatherCode: json['weatherCode'] as int,
      isDay: json['isDay'] as bool,
      conditionType: json['conditionType'] as String? ?? 'clear',
      iconSymbol: json['iconSymbol'] as String,
      conditionLabel: json['conditionLabel'] as String,
    );
  }
}

class WeatherService {
  static const String _cacheKey = 'mizwala_cached_weather';
  static const String _cacheTimeKey = 'mizwala_cached_weather_time';
  static const double lat = 31.6295;
  static const double lng = -7.9811;

  static WeatherData? _memoryCache;
  static DateTime? _lastFetchTime;

  /// Récupère la météo en temps réel (Open-Meteo sans clé API).
  /// Met en cache pendant 30 minutes. Fallback automatique sur le cache en cas d'échec réseau.
  static Future<WeatherData?> fetchWeather({
    double? currentHourDecimal,
    double? sunriseDecimal,
    double? sunsetDecimal,
    bool force = false,
  }) async {
    final now = DateTime.now();

    if (!force &&
        _memoryCache != null &&
        _lastFetchTime != null &&
        now.difference(_lastFetchTime!).inMinutes < 30) {
      return _memoryCache;
    }

    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?'
        'latitude=$lat&longitude=$lng&'
        'current=temperature_2m,weather_code,is_day&'
        'daily=temperature_2m_max,temperature_2m_min&'
        'timezone=Africa%2FCasablanca&'
        'forecast_days=1',
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final current = data['current'];
        final daily = data['daily'];

        final double currentTemp =
            (current['temperature_2m'] as num).toDouble();
        final double maxTemp =
            (daily['temperature_2m_max'][0] as num).toDouble();
        final double minTemp =
            (daily['temperature_2m_min'][0] as num).toDouble();
        final int weatherCode = current['weather_code'] as int;
        final bool isDay = (current['is_day'] as int) == 1;

        final (symbol, label, condType) = _resolveSymbolAndLabel(
          weatherCode: weatherCode,
          isDay: isDay,
          currentHour: currentHourDecimal,
          sunrise: sunriseDecimal,
          sunset: sunsetDecimal,
        );

        final weather = WeatherData(
          currentTemp: currentTemp,
          maxTemp: maxTemp,
          minTemp: minTemp,
          weatherCode: weatherCode,
          isDay: isDay,
          conditionType: condType,
          iconSymbol: symbol,
          conditionLabel: label,
        );

        _memoryCache = weather;
        _lastFetchTime = now;
        _saveToLocalCache(weather);
        return weather;
      }
    } catch (e) {
      debugPrint('Weather fetch network error: $e');
    }

    // Fallback vers le cache local SharedPreferences
    if (_memoryCache != null) return _memoryCache;
    return await _loadFromLocalCache();
  }

  static (String, String, String) _resolveSymbolAndLabel({
    required int weatherCode,
    required bool isDay,
    double? currentHour,
    double? sunrise,
    double? sunset,
  }) {
    // Vérifier si le soleil est en train de se lever ou se coucher (+/- 25 min)
    if (currentHour != null && sunrise != null && sunset != null) {
      if ((currentHour - sunrise).abs() < 0.45 ||
          (currentHour - sunset).abs() < 0.45) {
        return ('🌅', 'Crépuscule', 'clear');
      }
    }

    // Codes WMO météo
    switch (weatherCode) {
      case 0:
        return isDay
            ? ('☀️', 'Ensoleillé', 'clear')
            : ('🌙', 'Nuit claire', 'clear');
      case 1:
      case 2:
        return isDay
            ? ('⛅', 'Éclaircies', 'clouds')
            : ('☁️🌙', 'Nuit nuageuse', 'clouds');
      case 3:
        return ('☁️', 'Couvert', 'clouds');
      case 45:
      case 48:
        return ('🌫️', 'Brume', 'clouds');
      case 51:
      case 53:
      case 55:
        return ('🌦️', 'Bruine', 'rain');
      case 61:
      case 63:
      case 65:
      case 80:
      case 81:
      case 82:
        return ('🌧️', 'Pluie', 'rain');
      case 71:
      case 73:
      case 75:
      case 85:
      case 86:
        return ('❄️', 'Neige', 'clouds');
      case 95:
      case 96:
      case 99:
        return ('⛈️', 'Orage', 'storm');
      default:
        return isDay
            ? ('☀️', 'Clair', 'clear')
            : ('🌙', 'Clair', 'clear');
    }
  }

  static Future<void> _saveToLocalCache(WeatherData data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(data.toJson()));
      await prefs.setString(_cacheTimeKey, DateTime.now().toIso8601String());
    } catch (_) {}
  }

  static Future<WeatherData?> _loadFromLocalCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(_cacheKey);
      if (str != null) {
        final map = jsonDecode(str);
        final weather = WeatherData.fromJson(map);
        _memoryCache = weather;
        return weather;
      }
    } catch (_) {}
    return null;
  }

  /// Calcul dynamique de la couleur du ciel (Dégradé Nuit -> Aube -> Jour -> Coucher -> Nuit + Condition)
  static Color computeSkyColor(double t, PrayerTimes times, String condition) {
    const night = Color(0xFF0E1116); // [14, 17, 22]
    const day = Color(0xFF3D8AC7);   // [61, 138, 199]
    const sunset = Color(0xFFE8823A);// [232, 130, 58]

    Color baseColor;

    if (t >= times.isha || t < times.fajr) {
      baseColor = night;
    } else if (t < times.sunrise) {
      final double f = ((t - times.fajr) / (times.sunrise - times.fajr)).clamp(0.0, 1.0);
      baseColor = Color.lerp(night, day, f)!;
    } else {
      final double preSunset = times.maghrib - 1.0;
      if (t < preSunset) {
        baseColor = day;
      } else if (t < times.maghrib) {
        final double f = ((t - preSunset) / (times.maghrib - preSunset)).clamp(0.0, 1.0);
        baseColor = Color.lerp(day, sunset, f)!;
      } else {
        final double f2 = ((t - times.maghrib) / (times.isha - times.maghrib)).clamp(0.0, 1.0);
        baseColor = Color.lerp(sunset, night, f2)!;
      }
    }

    if (condition == 'clear') return baseColor;

    const gray = Color(0xFF646E78);  // [100, 110, 120]
    const storm = Color(0xFF3C424E); // [60, 66, 78]
    final target = condition == 'storm' ? storm : gray;
    return Color.lerp(baseColor, target, 0.75)!;
  }
}
