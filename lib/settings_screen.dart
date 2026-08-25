import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'mizwala_dial.dart';
import 'notification_service.dart';
import 'prayer_times.dart';

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
      _loading = false;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    for (final item in kNotifPrayers) {
      await prefs.setBool('$kPrefPrefix${item.key}', _enabled[item.key] ?? true);
    }
    await prefs.setInt(kPrefDelay, _delayMin);
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
                _sectionTitle('Notifications'),
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
        'UTC+1 fixe, méthode malikite. Aucune API ni connexion réseau n\'est '
        'utilisée.',
        style: GoogleFonts.cormorantGaramond(
          color: MizwalaTheme.muted,
          fontSize: 13,
          height: 1.5,
        ),
      ),
    );
  }
}
