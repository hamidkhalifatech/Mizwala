import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'home_screen.dart';
import 'mizwala_dial.dart';
import 'notification_service.dart';
import 'prayer_times.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Orientation portrait uniquement
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Couleur de la barre de statut
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: MizwalaTheme.bg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Initialiser les notifications
  await NotificationService.init();

  // Planification initiale (horaires du jour Marrakech)
  final now = DateTime.now().toUtc().add(const Duration(hours: 1));
  final todayTimes = MizwalaCalculator.compute(now.year, now.month, now.day);
  await NotificationService.reschedule(todayTimes);

  runApp(const MizwalaApp());
}

class MizwalaApp extends StatelessWidget {
  const MizwalaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mizwala',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: MizwalaTheme.bg,
        colorScheme: const ColorScheme.dark(
          primary: MizwalaTheme.brass,
          secondary: MizwalaTheme.ochre,
          surface: MizwalaTheme.bg,
        ),
        splashColor: MizwalaTheme.brass.withOpacity(0.1),
        highlightColor: Colors.transparent,
      ),
      home: const MizwalaHomeScreen(),
    );
  }
}
