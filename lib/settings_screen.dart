import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'mizwala_dial.dart';
import 'notification_service.dart';
import 'prayer_times.dart';

const kPrefSleepEnabled = 'sleep_enabled';
const kPrefSleepBedtimeH = 'sleep_bedtime_hour';
const kPrefSleepBedtimeM = 'sleep_bedtime_minute';
const kPrefSleepWakeupH = 'sleep_wakeup_hour';
const kPrefSleepWakeupM = 'sleep_wakeup_minute';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Map<String, bool> _enabled;
  late int _delayMin;
  bool _loading = true;
  bool _dirty = false;

  // Sommeil
  bool _sleepEnabled = true;
  int _bedtimeHour = 23;
  int _bedtimeMinute = 0;
  int _wakeupHour = 6;
  int _wakeupMinute = 30;

  // Horaires du jour pour l'affichage
  late PrayerTimes _todayTimes;

  @override
  void initState() {
    super.initState();
    final shifted = DateTime.now().toUtc().add(const Duration(hours: 1));
    _todayTimes =
        MizwalaCalculator.compute(shifted.year, shifted.month, shifted.day);
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, bool> enabledMap = {};
    for (final item in kNotifPrayers) {
      enabledMap[item.key] = prefs.getBool('$kPrefPrefix${item.key}') ?? true;
    }
    setState(() {
      _enabled = enabledMap;
      _delayMin = prefs.getInt(kPrefDelay) ?? 10;
      _sleepEnabled = prefs.getBool(kPrefSleepEnabled) ?? true;
      _bedtimeHour = prefs.getInt(kPrefSleepBedtimeH) ?? 23;
      _bedtimeMinute = prefs.getInt(kPrefSleepBedtimeM) ?? 0;
      _wakeupHour = prefs.getInt(kPrefSleepWakeupH) ?? 6;
      _wakeupMinute = prefs.getInt(kPrefSleepWakeupM) ?? 30;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    for (final item in kNotifPrayers) {
      await prefs.setBool('$kPrefPrefix${item.key}', _enabled[item.key] ?? true);
    }
    await prefs.setInt(kPrefDelay, _delayMin);

    await prefs.setBool(kPrefSleepEnabled, _sleepEnabled);
    await prefs.setInt(kPrefSleepBedtimeH, _bedtimeHour);
    await prefs.setInt(kPrefSleepBedtimeM, _bedtimeMinute);
    await prefs.setInt(kPrefSleepWakeupH, _wakeupHour);
    await prefs.setInt(kPrefSleepWakeupM, _wakeupMinute);

    await NotificationService.reschedule(_todayTimes);
    setState(() => _dirty = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Réglages sauvegardés',
            style: GoogleFonts.cinzel(color: MizwalaTheme.bg),
          ),
          backgroundColor: MizwalaTheme.brass,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _pickBedtime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _bedtimeHour, minute: _bedtimeMinute),
      helpText: 'Heure de coucher',
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
      setState(() {
        _bedtimeHour = picked.hour;
        _bedtimeMinute = picked.minute;
        _dirty = true;
      });
    }
  }

  Future<void> _pickWakeup() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _wakeupHour, minute: _wakeupMinute),
      helpText: 'Heure de réveil',
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
      setState(() {
        _wakeupHour = picked.hour;
        _wakeupMinute = picked.minute;
        _dirty = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MizwalaTheme.bg,
      appBar: AppBar(
        backgroundColor: MizwalaTheme.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: MizwalaTheme.brass, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Réglages',
          style: GoogleFonts.cinzel(
            color: MizwalaTheme.parchment,
            fontSize: 18,
            letterSpacing: 2,
          ),
        ),
        actions: [
          if (_dirty)
            TextButton(
              onPressed: _save,
              child: Text(
                'Sauvegarder',
                style: GoogleFonts.cinzel(
                  color: MizwalaTheme.brass,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: MizwalaTheme.brass))
          : ListView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              children: [
                _sectionTitle('Sommeil & Repos'),
                const SizedBox(height: 8),
                _sleepSection(),
                const SizedBox(height: 20),
                _sectionTitle('Notifications des Prières'),
                const SizedBox(height: 4),
                _delaySelector(),
                const SizedBox(height: 16),
                _sectionTitle('Prières'),
                const SizedBox(height: 8),
                ..._prayerToggles(),
                const SizedBox(height: 24),
                _saveButton(),
                const SizedBox(height: 32),
                _infoCard(),
              ],
            ),
    );
  }

  Widget _sectionTitle(String t) => Text(
        t.toUpperCase(),
        style: GoogleFonts.cinzel(
          color: MizwalaTheme.brass,
          fontSize: 11,
          letterSpacing: 2,
        ),
      );

  Widget _sleepSection() {
    final bedtimeStr =
        '${_bedtimeHour.toString().padLeft(2, '0')}:${_bedtimeMinute.toString().padLeft(2, '0')}';
    final wakeupStr =
        '${_wakeupHour.toString().padLeft(2, '0')}:${_wakeupMinute.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _sleepEnabled
            ? MizwalaTheme.brass.withOpacity(0.06)
            : Colors.transparent,
        border: Border.all(
          color: MizwalaTheme.brass.withOpacity(_sleepEnabled ? 0.3 : 0.12),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _sleepEnabled,
            onChanged: (v) => setState(() {
              _sleepEnabled = v;
              _dirty = true;
            }),
            activeColor: MizwalaTheme.brass,
            title: Text(
              'Afficher le Sommeil sur le cadran',
              style: GoogleFonts.cinzel(
                color: _sleepEnabled
                    ? MizwalaTheme.parchment
                    : MizwalaTheme.muted,
                fontSize: 13,
                letterSpacing: 1,
              ),
            ),
            subtitle: Text(
              'Repère et arc de nuit sur le cycle 24h',
              style: GoogleFonts.cormorantGaramond(
                color: MizwalaTheme.muted,
                fontSize: 14,
              ),
            ),
            secondary: Icon(
              Icons.bedtime_outlined,
              color: _sleepEnabled ? MizwalaTheme.brass : MizwalaTheme.muted,
            ),
          ),
          if (_sleepEnabled) ...[
            const Divider(color: Colors.white12, height: 16),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _pickBedtime,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: MizwalaTheme.brass.withOpacity(0.25)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Coucher',
                            style: GoogleFonts.cinzel(
                              color: MizwalaTheme.brassDim,
                              fontSize: 10,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            bedtimeStr,
                            style: GoogleFonts.cormorantGaramond(
                              color: MizwalaTheme.parchment,
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: _pickWakeup,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: MizwalaTheme.brass.withOpacity(0.25)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Réveil',
                            style: GoogleFonts.cinzel(
                              color: MizwalaTheme.brassDim,
                              fontSize: 10,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            wakeupStr,
                            style: GoogleFonts.cormorantGaramond(
                              color: MizwalaTheme.parchment,
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _delaySelector() {
    const delays = [0, 5, 10, 15, 20];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 10),
          child: Text(
            'Préavis avant chaque prière',
            style: GoogleFonts.cormorantGaramond(
              color: MizwalaTheme.parchment,
              fontSize: 16,
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          children: delays.map((d) {
            final selected = _delayMin == d;
            return GestureDetector(
              onTap: () => setState(() {
                _delayMin = d;
                _dirty = true;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: selected
                      ? MizwalaTheme.brass
                      : MizwalaTheme.brass.withOpacity(0.08),
                  border: Border.all(
                    color: selected
                        ? MizwalaTheme.brass
                        : MizwalaTheme.brass.withOpacity(0.3),
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  d == 0 ? 'À l\'heure' : '$d min',
                  style: GoogleFonts.cinzel(
                    color: selected ? MizwalaTheme.bg : MizwalaTheme.parchment,
                    fontSize: 12,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  List<Widget> _prayerToggles() {
    final map = _todayTimes.asMap();
    return kNotifPrayers.map((item) {
      final key = item.key;
      final label = item.label;
      final time = MizwalaCalculator.format(map[key]!);
      final isOn = _enabled[key] ?? true;
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isOn
              ? MizwalaTheme.brass.withOpacity(0.07)
              : Colors.transparent,
          border: Border.all(
            color: MizwalaTheme.brass.withOpacity(isOn ? 0.3 : 0.12),
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: SwitchListTile(
          value: isOn,
          onChanged: (v) => setState(() {
            _enabled[key] = v;
            _dirty = true;
          }),
          activeColor: MizwalaTheme.brass,
          title: Text(
            label,
            style: GoogleFonts.cinzel(
              color: isOn ? MizwalaTheme.parchment : MizwalaTheme.muted,
              fontSize: 14,
              letterSpacing: 1,
            ),
          ),
          subtitle: Text(
            time,
            style: GoogleFonts.cormorantGaramond(
              color: isOn ? MizwalaTheme.brass : MizwalaTheme.muted,
              fontSize: 16,
            ),
          ),
          secondary: Icon(
            isOn ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
            color: isOn ? MizwalaTheme.brass : MizwalaTheme.muted,
            size: 20,
          ),
        ),
      );
    }).toList();
  }

  Widget _saveButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _save,
        style: ElevatedButton.styleFrom(
          backgroundColor: MizwalaTheme.brass,
          foregroundColor: MizwalaTheme.bg,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(
          'Sauvegarder les réglages',
          style: GoogleFonts.cinzel(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  Widget _infoCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: MizwalaTheme.muted.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Les horaires sont calculés localement pour Marrakech (31.63°N / 7.98°O), '
        'UTC+1 fixe, méthode malikite. La météo temps réel est actualisée automatiquement.',
        style: GoogleFonts.cormorantGaramond(
          color: MizwalaTheme.muted,
          fontSize: 13,
          height: 1.5,
        ),
      ),
    );
  }
}
