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
  Timer? _sleepSaveDebounce;
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
    _sleepSaveDebounce?.cancel();
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

  void _saveSleepPrefsDebounced() {
    _sleepSaveDebounce?.cancel();
    _sleepSaveDebounce = Timer(const Duration(milliseconds: 500), () async {
      final prefs = await SharedPreferences.getInstance();
      final bH = _sleepBedtimeDecimal.floor();
      final bM = ((_sleepBedtimeDecimal - bH) * 60).round();
      final wH = _sleepWakeupDecimal.floor();
      final wM = ((_sleepWakeupDecimal - wH) * 60).round();

      await prefs.setInt(kPrefSleepBedtimeH, bH);
      await prefs.setInt(kPrefSleepBedtimeM, bM);
      await prefs.setInt(kPrefSleepWakeupH, wH);
      await prefs.setInt(kPrefSleepWakeupM, wM);
    });
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
            primary: MizwalaTheme.amber,
            onPrimary: Colors.black,
            surface: Color(0xFF16161A),
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
    final dialSize = (screenWidth - 48).clamp(280.0, 420.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 12),

              // Cadran central avec anneau interactif et disque météo agrandi
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                decoration: BoxDecoration(
                  color: MizwalaTheme.card,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: MizwalaTheme.glassBorder),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Center(
                      child: MizwalaDial(
                        times: _times,
                        currentHourDecimal: _currentHourDecimal,
                        size: dialSize,
                        weatherData: _weatherData,
                        sleepBedtime: _sleepBedtimeDecimal,
                        sleepWakeup: _sleepWakeupDecimal,
                        sleepEnabled: _sleepEnabled,
                        onSleepBedtimeChanged: (val) {
                          setState(() => _sleepBedtimeDecimal = val);
                          _saveSleepPrefsDebounced();
                        },
                        onSleepWakeupChanged: (val) {
                          setState(() => _sleepWakeupDecimal = val);
                          _saveSleepPrefsDebounced();
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildDateSelector(),
                  ],
                ),
              ),

              const SizedBox(height: 14),
              _buildNextPrayerBanner(nextPrayer),
              const SizedBox(height: 14),
              _buildPrayerChips(nextPrayer.key),
              const SizedBox(height: 16),
              _buildBottomTabBar(),
              const SizedBox(height: 10),
            ],
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
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mizwala',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.02,
                fontFamily: '-apple-system',
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Marrakech',
              style: TextStyle(
                color: MizwalaTheme.label2,
                fontSize: 14,
                fontWeight: FontWeight.w400,
                fontFamily: '-apple-system',
              ),
            ),
          ],
        ),
        InkWell(
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            );
            _loadSleepPrefs();
            NotificationService.reschedule(_times);
          },
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0x14FFFFFF),
              shape: BoxShape.circle,
              border: Border.all(color: MizwalaTheme.glassBorder),
            ),
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

  Widget _buildDateSelector() {
    final dateStr =
        '${_selectedDate.day} ${kFrenchMonths[_selectedDate.month - 1]}';

    return GestureDetector(
      onTap: _pickDate,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0x0DFFFFFF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: MizwalaTheme.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isManualDate) ...[
              GestureDetector(
                onTap: _resetToToday,
                child: const Row(
                  children: [
                    Icon(Icons.refresh, color: MizwalaTheme.amber, size: 14),
                    SizedBox(width: 4),
                    Text(
                      'Aujourd\'hui',
                      style: TextStyle(
                        color: MizwalaTheme.amber,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: 10),
                  ],
                ),
              ),
            ],
            Text(
              dateStr,
              style: TextStyle(
                color: _isManualDate ? MizwalaTheme.amber : MizwalaTheme.label1,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                fontFamily: '-apple-system',
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.calendar_today_outlined,
              size: 13,
              color: _isManualDate ? MizwalaTheme.amber : MizwalaTheme.label2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNextPrayerBanner(
      ({String key, String label, double time, int diffHours, int diffMinutes})
          next) {
    final diffStr = next.diffHours > 0
        ? 'dans ${next.diffHours}h ${next.diffMinutes}min'
        : 'dans ${next.diffMinutes}min';

    final isDohr = next.key == 'dhuhr';
    final accentColor = isDohr ? MizwalaTheme.amber : MizwalaTheme.teal;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0x0FFFFFFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MizwalaTheme.glassBorder),
      ),
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
                style: TextStyle(
                  color: accentColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.20),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              diffStr,
              style: TextStyle(
                color: accentColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrayerChips(String nextKey) {
    final sleepDurationDec = (_sleepWakeupDecimal - _sleepBedtimeDecimal + 24.0) % 24.0;
    final sleepH = sleepDurationDec.floor();
    final sleepM = ((sleepDurationDec - sleepH) * 60).round();
    final sleepDurationLabel = sleepM > 0 ? '${sleepH}h$sleepM' : '${sleepH}h';

    final chips = [
      ('fajr', 'Fajr', MizwalaCalculator.format(_times.fajr), MizwalaTheme.teal),
      ('sunrise', 'Chourouk', MizwalaCalculator.format(_times.sunrise), MizwalaTheme.teal),
      ('dhuhr', 'Dohr', MizwalaCalculator.format(_times.dhuhr), MizwalaTheme.amber),
      ('asr', 'Asr', MizwalaCalculator.format(_times.asr), MizwalaTheme.teal),
      ('maghrib', 'Maghrib', MizwalaCalculator.format(_times.maghrib), MizwalaTheme.teal),
      ('isha', 'Icha', MizwalaCalculator.format(_times.isha), MizwalaTheme.teal),
      if (_sleepEnabled)
        (
          'sleep',
          'Sommeil',
          '${MizwalaCalculator.format(_sleepBedtimeDecimal)} ($sleepDurationLabel)',
          MizwalaTheme.indigo
        ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: chips.map((c) {
          final isActive = c.$1 == nextKey;
          final isSleep = c.$1 == 'sleep';
          final color = c.$4;

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
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                constraints: const BoxConstraints(minWidth: 64),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                  color: isActive
                      ? color.withOpacity(0.22)
                      : const Color(0x0DFFFFFF),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isActive
                        ? color.withOpacity(0.70)
                        : MizwalaTheme.glassBorder,
                    width: 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: color,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          c.$2.toUpperCase(),
                          style: TextStyle(
                            color: isActive ? color : MizwalaTheme.label2,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.04,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      c.$3,
                      style: TextStyle(
                        color: isActive ? color : Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBottomTabBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x0DFFFFFF),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: MizwalaTheme.glassBorder),
      ),
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
              fontSize: 17,
              color: active ? MizwalaTheme.amber : MizwalaTheme.label3,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color: active ? MizwalaTheme.amber : MizwalaTheme.label3,
            ),
          ),
        ],
      ),
    );
  }
}
