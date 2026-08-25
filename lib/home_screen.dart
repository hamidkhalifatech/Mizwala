import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'prayer_times.dart';
import 'mizwala_dial.dart';
import 'settings_screen.dart';
import 'notification_service.dart';
import 'weather_service.dart';

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
    _weatherTimer = Timer.periodic(const Duration(minutes: 15), (_) => _loadWeather());
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
            primary: MizwalaTheme.brass,
            onPrimary: MizwalaTheme.bg,
            surface: Color(0xFF1A1F2A),
            onSurface: MizwalaTheme.parchment,
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
        _times = MizwalaCalculator.compute(picked.year, picked.month, picked.day);
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final dialSize = (size.width - 40).clamp(260.0, 420.0);

    return Scaffold(
      backgroundColor: MizwalaTheme.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              _buildHeader(context),
              const SizedBox(height: 4),
              _buildDateRow(),
              const SizedBox(height: 16),
              MizwalaDial(
                times: _times,
                currentHourDecimal: _currentHourDecimal,
                size: dialSize,
                weatherData: _weatherData,
                sleepBedtime: _sleepBedtimeDecimal,
                sleepWakeup: _sleepWakeupDecimal,
                sleepEnabled: _sleepEnabled,
              ),
              const SizedBox(height: 10),
              _buildClock(),
              const SizedBox(height: 20),
              _buildLegend(_times),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MARRAKECH · 31.63°N',
              style: GoogleFonts.cinzel(
                color: MizwalaTheme.brass,
                letterSpacing: 1.5,
                fontSize: 10,
              ),
            ),
            Text(
              'Mizwala',
              style: GoogleFonts.cinzel(
                color: MizwalaTheme.parchment,
                fontSize: 28,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined, color: MizwalaTheme.brass),
          tooltip: 'Réglages',
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            );
            _loadSleepPrefs();
            NotificationService.reschedule(_times);
          },
        ),
      ],
    );
  }

  Widget _buildDateRow() {
    final dateStr =
        '${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.year}';

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_isManualDate)
          GestureDetector(
            onTap: _resetToToday,
            child: Row(
              children: [
                const Icon(Icons.refresh, color: MizwalaTheme.ochre, size: 14),
                const SizedBox(width: 4),
                Text(
                  'Aujourd\'hui',
                  style: GoogleFonts.cinzel(
                    color: MizwalaTheme.ochre,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(width: 10),
              ],
            ),
          ),
        GestureDetector(
          onTap: _pickDate,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(
                  color: MizwalaTheme.brass.withOpacity(0.4), width: 1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  dateStr,
                  style: GoogleFonts.cinzel(
                    color: _isManualDate
                        ? MizwalaTheme.brass
                        : MizwalaTheme.muted,
                    fontSize: 11,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.calendar_today_outlined,
                  size: 12,
                  color: _isManualDate
                      ? MizwalaTheme.brass
                      : MizwalaTheme.muted,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildClock() {
    final h = MizwalaCalculator.format(_currentHourDecimal);
    final seconds = _marrakechNow.second.toString().padLeft(2, '0');
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: h,
            style: GoogleFonts.cormorantGaramond(
              color: MizwalaTheme.parchment,
              fontSize: 48,
              fontWeight: FontWeight.w300,
              letterSpacing: 3,
            ),
          ),
          TextSpan(
            text: ':$seconds',
            style: GoogleFonts.cormorantGaramond(
              color: MizwalaTheme.muted,
              fontSize: 28,
              fontWeight: FontWeight.w300,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend(PrayerTimes times) {
    final entries = [
      _PrayerEntry('Fajr', times.fajr, Icons.brightness_3),
      _PrayerEntry('Chourouk', times.sunrise, Icons.wb_twilight),
      _PrayerEntry('Dohr', times.dhuhr, Icons.wb_sunny),
      _PrayerEntry('Asr', times.asr, Icons.sunny_snowing),
      _PrayerEntry('Maghrib', times.maghrib, Icons.wb_twilight),
      _PrayerEntry('Icha', times.isha, Icons.nights_stay),
      if (_sleepEnabled)
        _PrayerEntry('Sommeil', _sleepBedtimeDecimal, Icons.bedtime_outlined),
    ];

    // Prochaine prière
    String? nextKey;
    if (!_isManualDate) {
      final nowH = _currentHourDecimal;
      final map = times.asMap();
      final keys = ['fajr', 'sunrise', 'dhuhr', 'asr', 'maghrib', 'isha'];
      for (final k in keys) {
        if (map[k]! > nowH) {
          nextKey = k;
          break;
        }
      }
    }

    final keyMap = {
      'Fajr': 'fajr',
      'Chourouk': 'sunrise',
      'Dohr': 'dhuhr',
      'Asr': 'asr',
      'Maghrib': 'maghrib',
      'Icha': 'isha',
    };

    return Column(
      children: [
        Divider(color: MizwalaTheme.brass.withOpacity(0.2), height: 1),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: entries.map((e) {
            final isSleep = e.name == 'Sommeil';
            final isNext = !isSleep && (keyMap[e.name] == nextKey);
            return GestureDetector(
              onTap: isSleep
                  ? () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SettingsScreen()),
                      );
                      _loadSleepPrefs();
                    }
                  : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  color: isNext
                      ? MizwalaTheme.brass.withOpacity(0.12)
                      : (isSleep
                          ? MizwalaTheme.nightBlue.withOpacity(0.35)
                          : Colors.transparent),
                  border: Border.all(
                    color: isNext
                        ? MizwalaTheme.brass.withOpacity(0.5)
                        : (isSleep
                            ? MizwalaTheme.brassDim.withOpacity(0.35)
                            : MizwalaTheme.brass.withOpacity(0.12)),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          e.icon,
                          size: 11,
                          color: isNext
                              ? MizwalaTheme.brass
                              : (isSleep ? MizwalaTheme.brassDim : MizwalaTheme.muted),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          e.name,
                          style: GoogleFonts.cinzel(
                            color: isNext
                                ? MizwalaTheme.brass
                                : (isSleep ? MizwalaTheme.brassDim : MizwalaTheme.muted),
                            fontSize: 10,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      MizwalaCalculator.format(e.time),
                      style: GoogleFonts.cormorantGaramond(
                        color: isNext
                            ? MizwalaTheme.parchment
                            : (isSleep
                                ? MizwalaTheme.parchment
                                : MizwalaTheme.parchment.withOpacity(0.7)),
                        fontSize: 19,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _PrayerEntry {
  final String name;
  final double time;
  final IconData icon;
  const _PrayerEntry(this.name, this.time, this.icon);
}
