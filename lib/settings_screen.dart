import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'mizwala_dial.dart';
import 'notification_service.dart';
import 'prayer_times.dart';

const MethodChannel _settingsWidgetChannel =
    MethodChannel('com.mizwala.mizwala/widget');

Future<void> _notifyWidgetFromSettings() async {
  try {
    await _settingsWidgetChannel.invokeMethod('updateWidget');
  } catch (_) {}
}

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

  // Sonnerie personnalisée
  String? _customSoundPath;
  String? _customSoundName;
  bool _isPlayingSound = false;

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

  @override
  void dispose() {
    NotificationService.stopAlarmSound();
    super.dispose();
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
      _customSoundPath = prefs.getString(kPrefCustomSoundPath);
      _customSoundName = prefs.getString(kPrefCustomSoundName);
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

    if (_customSoundPath != null) {
      await prefs.setString(kPrefCustomSoundPath, _customSoundPath!);
      await prefs.setString(kPrefCustomSoundName, _customSoundName ?? 'Fichier audio');
    } else {
      await prefs.remove(kPrefCustomSoundPath);
      await prefs.remove(kPrefCustomSoundName);
    }

    await NotificationService.reschedule(_todayTimes);
    await _notifyWidgetFromSettings();
    setState(() => _dirty = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Réglages et sonnerie sauvegardés avec succès',
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: MizwalaTheme.amber,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _pickAudioFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'm4a', 'mp4', 'aac', 'ogg'],
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final name = result.files.single.name;

        setState(() {
          _customSoundPath = path;
          _customSoundName = name;
          _dirty = true;
        });

        // Lecture immédiate pour confirmation
        _togglePlayPreview();
      }
    } catch (e) {
      debugPrint('Error picking audio file: $e');
    }
  }

  Future<void> _togglePlayPreview() async {
    if (_isPlayingSound) {
      await NotificationService.stopAlarmSound();
      setState(() => _isPlayingSound = false);
    } else {
      if (_customSoundPath != null) {
        setState(() => _isPlayingSound = true);
        await NotificationService.playCustomAlarmSound(_customSoundPath);
      }
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
            primary: MizwalaTheme.indigo,
            onPrimary: Colors.white,
            surface: Color(0xFF16161A),
            onSurface: Colors.white,
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
            primary: MizwalaTheme.indigo,
            onPrimary: Colors.white,
            surface: Color(0xFF16161A),
            onSurface: Colors.white,
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

  String _calculateSleepDuration() {
    final bedDec = _bedtimeHour + _bedtimeMinute / 60.0;
    final wakeDec = _wakeupHour + _wakeupMinute / 60.0;
    final durationDec = (wakeDec - bedDec + 24.0) % 24.0;
    final h = durationDec.floor();
    final m = ((durationDec - h) * 60).round();
    return m > 0 ? '${h}h ${m}min' : '${h}h';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MizwalaTheme.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: MizwalaTheme.label1, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Réglages',
          style: TextStyle(
            color: MizwalaTheme.label1,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          if (_dirty)
            TextButton(
              onPressed: _save,
              child: const Text(
                'Enregistrer',
                style: TextStyle(
                  color: MizwalaTheme.amber,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: MizwalaTheme.amber))
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              children: [
                _sectionTitle('Sonnerie de l\'Alarme & Adhan'),
                const SizedBox(height: 8),
                _soundPickerCard(),
                const SizedBox(height: 22),
                _sectionTitle('Sommeil & Repos'),
                const SizedBox(height: 8),
                _sleepSection(),
                const SizedBox(height: 22),
                _sectionTitle('Notifications & Alarmes'),
                const SizedBox(height: 6),
                _testNotificationCard(),
                const SizedBox(height: 12),
                _delaySelector(),
                const SizedBox(height: 18),
                _sectionTitle('Prières'),
                const SizedBox(height: 8),
                ..._prayerToggles(),
                const SizedBox(height: 24),
                _saveButton(),
                const SizedBox(height: 28),
                _infoCard(),
                const SizedBox(height: 20),
              ],
            ),
    );
  }

  Widget _sectionTitle(String t) => Text(
        t.toUpperCase(),
        style: const TextStyle(
          color: MizwalaTheme.label2,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.08,
        ),
      );

  Widget _soundPickerCard() {
    final hasCustom = _customSoundPath != null && _customSoundPath!.isNotEmpty;
    final soundTitle = hasCustom
        ? (_customSoundName ?? 'Fichier audio personnalisé')
        : 'Sonnerie système par défaut';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x0FFFFFFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MizwalaTheme.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: MizwalaTheme.amber.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.audiotrack,
                  color: MizwalaTheme.amber,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      soundTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasCustom
                          ? 'Fichier audio chargé (.mp3, .wav, .m4a)'
                          : 'Cliquez ci-dessous pour choisir votre sonnerie ou Adhan',
                      style: const TextStyle(
                        color: MizwalaTheme.label2,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _pickAudioFile,
                  icon: const Icon(Icons.folder_open, size: 16),
                  label: Text(
                    hasCustom ? 'Changer de fichier' : 'Choisir un MP3 / WAV',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0x1AFFFFFF),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: MizwalaTheme.glassBorder),
                    ),
                  ),
                ),
              ),
              if (hasCustom) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _togglePlayPreview,
                  icon: Icon(
                    _isPlayingSound ? Icons.stop_circle : Icons.play_circle_fill,
                    color: MizwalaTheme.amber,
                    size: 32,
                  ),
                  tooltip: _isPlayingSound ? 'Arrêter' : 'Écouter',
                ),
                IconButton(
                  onPressed: () {
                    NotificationService.stopAlarmSound();
                    setState(() {
                      _customSoundPath = null;
                      _customSoundName = null;
                      _isPlayingSound = false;
                      _dirty = true;
                    });
                  },
                  icon: const Icon(
                    Icons.delete_outline,
                    color: MizwalaTheme.label3,
                    size: 22,
                  ),
                  tooltip: 'Réinitialiser au son par défaut',
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _sleepSection() {
    final bedtimeStr =
        '${_bedtimeHour.toString().padLeft(2, '0')}:${_bedtimeMinute.toString().padLeft(2, '0')}';
    final wakeupStr =
        '${_wakeupHour.toString().padLeft(2, '0')}:${_wakeupMinute.toString().padLeft(2, '0')}';
    final durationStr = _calculateSleepDuration();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x0FFFFFFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MizwalaTheme.glassBorder),
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
            activeColor: MizwalaTheme.indigo,
            title: const Text(
              'Afficher le Sommeil sur le cadran',
              style: TextStyle(
                color: MizwalaTheme.label1,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              'Durée programmée : $durationStr',
              style: const TextStyle(
                color: MizwalaTheme.indigo,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            secondary: Icon(
              Icons.bedtime_outlined,
              color: _sleepEnabled ? MizwalaTheme.indigo : MizwalaTheme.label3,
            ),
          ),
          if (_sleepEnabled) ...[
            const Divider(color: Color(0x1AFFFFFF), height: 18),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _pickBedtime,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0x14FFFFFF),
                        border: Border.all(
                            color: MizwalaTheme.indigo.withOpacity(0.4)),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Coucher',
                            style: TextStyle(
                              color: MizwalaTheme.indigo,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            bedtimeStr,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              fontFeatures: [FontFeature.tabularFigures()],
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
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0x14FFFFFF),
                        border: Border.all(
                            color: MizwalaTheme.indigo.withOpacity(0.4)),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Réveil',
                            style: TextStyle(
                              color: MizwalaTheme.indigo,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            wakeupStr,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              fontFeatures: [FontFeature.tabularFigures()],
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

  Widget _testNotificationCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: MizwalaTheme.amber.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MizwalaTheme.amber.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tester la sonnerie & notification',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Déclenche la notification et joue votre sonnerie / Adhan',
                  style: TextStyle(
                    color: MizwalaTheme.label2,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () async {
              await NotificationService.sendTestNotification();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Test d\'alarme et sonnerie déclenché !'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: MizwalaTheme.amber,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text(
              'Tester',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _delaySelector() {
    const delays = [0, 5, 10, 15, 20];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
            'Préavis avant chaque prière',
            style: TextStyle(
              color: MizwalaTheme.label2,
              fontSize: 13.5,
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
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                    horizontal: 15, vertical: 8),
                decoration: BoxDecoration(
                  color: selected
                      ? MizwalaTheme.amber
                      : const Color(0x0FFFFFFF),
                  border: Border.all(
                    color: selected
                        ? MizwalaTheme.amber
                        : MizwalaTheme.glassBorder,
                  ),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  d == 0 ? 'À l\'heure' : '$d min',
                  style: TextStyle(
                    color: selected ? Colors.black : MizwalaTheme.label1,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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
      final isDohr = key == 'dhuhr';
      final itemColor = isDohr ? MizwalaTheme.amber : MizwalaTheme.teal;

      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0x0DFFFFFF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: MizwalaTheme.glassBorder),
        ),
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: isOn,
          onChanged: (v) => setState(() {
            _enabled[key] = v;
            _dirty = true;
          }),
          activeColor: itemColor,
          title: Text(
            label,
            style: TextStyle(
              color: isOn ? Colors.white : MizwalaTheme.label3,
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            time,
            style: TextStyle(
              color: isOn ? itemColor : MizwalaTheme.label3,
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          secondary: Icon(
            isOn
                ? Icons.notifications_active_outlined
                : Icons.notifications_off_outlined,
            color: isOn ? itemColor : MizwalaTheme.label3,
            size: 22,
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
          backgroundColor: MizwalaTheme.amber,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 15),
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        child: const Text(
          'Sauvegarder les réglages',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.02,
          ),
        ),
      ),
    );
  }

  Widget _infoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x0AFFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MizwalaTheme.glassBorder),
      ),
      child: const Text(
        'Les horaires sont calculés localement pour Marrakech (31.63°N / 7.98°O), '
        'UTC+1 fixe, méthode malikite. Les alarmes et notifications jouent la sonnerie choisie au moment exact de vos prières.',
        style: TextStyle(
          color: MizwalaTheme.label3,
          fontSize: 12.5,
          height: 1.4,
        ),
      ),
    );
  }
}
