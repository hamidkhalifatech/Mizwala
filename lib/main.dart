import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'home_screen.dart';
import 'mizwala_dial.dart';
import 'notification_service.dart';
import 'prayer_times.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Orientation portrait
  try {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  } catch (_) {}

  // Style barre de statut
  try {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: MizwalaTheme.bg,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
  } catch (_) {}

  // Lancement immédiat de l'UI pour ne jamais bloquer l'écran
  runApp(const MizwalaApp());

  // Initialisation des notifications en arrière-plan
  Future.microtask(() async {
    try {
      await NotificationService.init();
      final now = DateTime.now().toUtc().add(const Duration(hours: 1));
      final todayTimes = MizwalaCalculator.compute(now.year, now.month, now.day);
      await NotificationService.reschedule(todayTimes);
    } catch (e) {
      debugPrint('Background notification init error: $e');
    }
  });
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
          primary: MizwalaTheme.amber,
          secondary: MizwalaTheme.teal,
          surface: MizwalaTheme.bg,
        ),
        splashColor: MizwalaTheme.amber.withOpacity(0.1),
        highlightColor: Colors.transparent,
      ),
      home: const MizwalaHomeScreen(),
    );
  }
}
