import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'prayer_times.dart';
import 'mizwala_dial.dart';
import 'settings_screen.dart';
import 'notification_service.dart';
import 'weather_service.dart';

const List<String> kFrenchMonths = [
  'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
  'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'
];

class MizwalaHomeScreen extends StatefulWidget {
  const MizwalaHomeScreen({super.key});

  @override
  State<MizwalaHomeScreen> createState() => _MizwalaHomeScreenState();
}

class _MizwalaHomeScreenState extends State<MizwalaHomeScreen> {
  Timer? _timer;
  Timer? _weatherTimer;
  late PrayerTimes _times;
  WeatherData? _weatherData;

  /// Heure Marrakech en temps réel (UTC+1 fixe).
  late DateTime _marrakechNow;

  /// Date affichée sur le cadran (peut être une date manuelle).
  late DateTime _selectedDate;
  bool _isManualDate = false;

  late int _cachedDayKey;

  // Sommeil
  bool _sleepEnabled = true;
  double _sleepBedtimeDecimal = 23.0;
  double _sleepWakeupDecimal = 6.5;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc().add(const Duration(hours: 1));
    _marrakechNow = now;
    _selectedDate = now;
    _cachedDayKey = now.year * 10000 + now.month * 100 + now.day;
    _times = MizwalaCalculator.compute(now.year, now.month, now.day);

    _loadSleepPrefs();
    _loadWeather();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _weatherTimer =
        Timer.periodic(const Duration(minutes: 15), (_) => _loadWeather());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _weatherTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSleepPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(kPrefSleepEnabled) ?? true;
    final bH = prefs.getInt(kPrefSleepBedtimeH) ?? 23;
    final bM = prefs.getInt(kPrefSleepBedtimeM) ?? 0;
    final wH = prefs.getInt(kPrefSleepWakeupH) ?? 6;
    final wM = prefs.getInt(kPrefSleepWakeupM) ?? 30;

    if (mounted) {
      setState(() {
        _sleepEnabled = enabled;
        _sleepBedtimeDecimal = bH + bM / 60.0;
        _sleepWakeupDecimal = wH + wM / 60.0;
      });
    }
  }

  Future<void> _loadWeather() async {
    final weather = await WeatherService.fetchWeather(
      currentHourDecimal: _currentHourDecimal,
      sunriseDecimal: _times.sunrise,
      sunsetDecimal: _times.maghrib,
    );
    if (mounted && weather != null) {
      setState(() {
        _weatherData = weather;
      });
    }
  }

  void _tick() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 1));

    // Date de référence pour le calcul des horaires
    final ref = _isManualDate ? _selectedDate : now;
    final dayKey = ref.year * 10000 + ref.month * 100 + ref.day;

    PrayerTimes? newTimes;
    if (dayKey != _cachedDayKey) {
      newTimes = MizwalaCalculator.compute(ref.year, ref.month, ref.day);
      _cachedDayKey = dayKey;
      if (!_isManualDate) {
        NotificationService.reschedule(newTimes);
      }
    }

    if (mounted) {
      setState(() {
        _marrakechNow = now;
        if (!_isManualDate) _selectedDate = now;
        if (newTimes != null) _times = newTimes;
      });
    }
  }

  double get _currentHourDecimal =>
      _marrakechNow.hour +
      _marrakechNow.minute / 60 +
      _marrakechNow.second / 3600;

  Future<void> _pickDate() async {
    final now = DateTime.now().toUtc().add(const Duration(hours: 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: 'Choisir une date',
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: MizwalaTheme.accent,
            onPrimary: Colors.black,
            surface: Color(0xFF1C1C20),
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      final isSameDay = picked.year == now.year &&
          picked.month == now.month &&
          picked.day == now.day;
      setState(() {
        _selectedDate = picked;
        _isManualDate = !isSameDay;
        _cachedDayKey = picked.year * 10000 + picked.month * 100 + picked.day;
        _times =
            MizwalaCalculator.compute(picked.year, picked.month, picked.day);
      });
      _loadWeather();
    }
  }

  void _resetToToday() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 1));
    setState(() {
      _isManualDate = false;
      _selectedDate = now;
      _cachedDayKey = now.year * 10000 + now.month * 100 + now.day;
      _times = MizwalaCalculator.compute(now.year, now.month, now.day);
    });
    _loadWeather();
  }

  /// Calcule la prochaine prière et le temps restant
  ({String key, String label, double time, int diffHours, int diffMinutes})
      _getNextPrayer() {
    final map = _times.asMap();
    final prayers = [
      (key: 'fajr', label: 'Fajr', time: _times.fajr),
      (key: 'sunrise', label: 'Chourouk', time: _times.sunrise),
      (key: 'dhuhr', label: 'Dohr', time: _times.dhuhr),
      (key: 'asr', label: 'Asr', time: _times.asr),
      (key: 'maghrib', label: 'Maghrib', time: _times.maghrib),
      (key: 'isha', label: 'Icha', time: _times.isha),
    ];

    final nowH = _currentHourDecimal;
    var selected = prayers[0];
    bool found = false;

    for (final p in prayers) {
      if (map[p.key]! > nowH) {
        selected = p;
        found = true;
        break;
      }
    }

    // Si toutes les prières du jour sont passées, prochaine = Fajr du lendemain
    double diff = selected.time - nowH;
    if (!found || diff < 0) {
      diff += 24.0;
    }

    final diffHours = diff.floor();
    final diffMinutes = ((diff - diffHours) * 60).round();

    return (
      key: selected.key,
      label: selected.label,
      time: selected.time,
      diffHours: diffHours,
      diffMinutes: diffMinutes,
    );
  }

  @override
  Widget build(BuildContext context) {
    final nextPrayer = _getNextPrayer();
    final screenWidth = MediaQuery.of(context).size.width;
    final dialSize = (screenWidth - 80).clamp(220.0, 320.0);

    return Scaffold(
      backgroundColor: MizwalaTheme.bg0,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.0, -0.6),
            radius: 1.2,
            colors: [
              Color(0xFF23222A),
              Color(0xFF0A0A0C),
            ],
            stops: [0.0, 0.7],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const SizedBox(height: 14),
                _buildDialCard(dialSize),
                const SizedBox(height: 12),
                _buildNextPrayerCard(nextPrayer),
                const SizedBox(height: 12),
                _buildChipsStrip(nextPrayer.key),
                const SizedBox(height: 16),
                _buildTabBar(),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Mizwala',
              style: TextStyle(
                color: MizwalaTheme.label1,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.02,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Marrakech',
              style: TextStyle(
                color: MizwalaTheme.label2,
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        _GlassBox(
          borderRadius: 17,
          padding: const EdgeInsets.all(8),
          child: InkWell(
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              _loadSleepPrefs();
              NotificationService.reschedule(_times);
            },
            borderRadius: BorderRadius.circular(17),
            child: const Icon(
              Icons.settings_outlined,
              color: MizwalaTheme.label2,
              size: 20,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDialCard(double dialSize) {
    final hh = _marrakechNow.hour.toString().padLeft(2, '0');
    final mm = _marrakechNow.minute.toString().padLeft(2, '0');
    final dateStr =
        '${_selectedDate.day} ${kFrenchMonths[_selectedDate.month - 1]}';

    return _GlassBox(
      borderRadius: 28,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Column(
        children: [
          MizwalaDial(
            times: _times,
            currentHourDecimal: _currentHourDecimal,
            size: dialSize,
            weatherData: _weatherData,
            sleepBedtime: _sleepBedtimeDecimal,
            sleepWakeup: _sleepWakeupDecimal,
            sleepEnabled: _sleepEnabled,
          ),
          const SizedBox(height: 8),
          Text(
            '$hh:$mm',
            style: const TextStyle(
              color: MizwalaTheme.label1,
              fontSize: 34,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.01,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 3),
          GestureDetector(
            onTap: _pickDate,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isManualDate) ...[
                  GestureDetector(
                    onTap: _resetToToday,
                    child: const Row(
                      children: [
                        Icon(Icons.refresh,
                            color: MizwalaTheme.accent, size: 13),
                        SizedBox(width: 3),
                        Text(
                          'Aujourd\'hui',
                          style: TextStyle(
                            color: MizwalaTheme.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 8),
                      ],
                    ),
                  ),
                ],
                Text(
                  dateStr,
                  style: TextStyle(
                    color: _isManualDate
                        ? MizwalaTheme.accent
                        : MizwalaTheme.label2,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.calendar_today_outlined,
                  size: 12,
                  color: _isManualDate
                      ? MizwalaTheme.accent
                      : MizwalaTheme.label3,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextPrayerCard(
      ({String key, String label, double time, int diffHours, int diffMinutes})
          next) {
    final diffStr = next.diffHours > 0
        ? 'dans ${next.diffHours}h ${next.diffMinutes}min'
        : 'dans ${next.diffMinutes}min';

    return _GlassBox(
      borderRadius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'PROCHAINE PRIÈRE',
                style: TextStyle(
                  color: MizwalaTheme.label2,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.06,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                next.label,
                style: const TextStyle(
                  color: MizwalaTheme.label1,
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: MizwalaTheme.accentDim,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              diffStr,
              style: const TextStyle(
                color: MizwalaTheme.accent,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChipsStrip(String nextKey) {
    final chips = [
      ('fajr', 'Fajr', _times.fajr),
      ('sunrise', 'Chourouk', _times.sunrise),
      ('dhuhr', 'Dohr', _times.dhuhr),
      ('asr', 'Asr', _times.asr),
      ('maghrib', 'Maghrib', _times.maghrib),
      ('isha', 'Icha', _times.isha),
      if (_sleepEnabled) ('sleep', 'Sommeil', _sleepBedtimeDecimal),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: chips.map((c) {
          final isActive = c.$1 == nextKey;
          final isSleep = c.$1 == 'sleep';

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: isSleep
                  ? () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SettingsScreen()),
                      );
                      _loadSleepPrefs();
                    }
                  : null,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    constraints: const BoxConstraints(minWidth: 64),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      color: isActive
                          ? MizwalaTheme.accentDim
                          : MizwalaTheme.glass,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isActive
                            ? MizwalaTheme.accentBorder
                            : MizwalaTheme.glassBorder,
                        width: 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          c.$2.toUpperCase(),
                          style: TextStyle(
                            color: isActive
                                ? MizwalaTheme.accent
                                : MizwalaTheme.label2,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.04,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          MizwalaCalculator.format(c.$3),
                          style: TextStyle(
                            color: isActive
                                ? MizwalaTheme.accent
                                : MizwalaTheme.label1,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTabBar() {
    return _GlassBox(
      borderRadius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildTabItem(icon: '◐', label: 'Cadran', active: true),
          _buildTabItem(
            icon: '▤',
            label: 'Horaires',
            active: false,
            onTap: _pickDate,
          ),
          _buildTabItem(
            icon: '⚙',
            label: 'Réglages',
            active: false,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              _loadSleepPrefs();
              NotificationService.reschedule(_times);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTabItem({
    required String icon,
    required String label,
    required bool active,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            icon,
            style: TextStyle(
              fontSize: 16,
              color: active ? MizwalaTheme.accent : MizwalaTheme.label3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color: active ? MizwalaTheme.accent : MizwalaTheme.label3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Conteneur générique Liquid Glass avec flou gaussien et bordure spéculaire
class _GlassBox extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final Border? border;

  const _GlassBox({
    required this.child,
    this.borderRadius = 20,
    this.padding,
    this.color,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: color ?? MizwalaTheme.glass,
            borderRadius: BorderRadius.circular(borderRadius),
            border: border ??
                Border.all(
                  color: MizwalaTheme.glassBorder,
                  width: 1,
                ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 25,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
