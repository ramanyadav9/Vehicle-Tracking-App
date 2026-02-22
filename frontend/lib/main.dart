import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/map_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0D1117),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const BusTrackerApp());
}

class BusTrackerApp extends StatelessWidget {
  const BusTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: themeNotifier,
      builder: (_, dark, __) {
        final brightness = dark ? Brightness.dark : Brightness.light;
        final bg = AppColors.bg;

        SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: bg,
          systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        ));

        return MaterialApp(
          title: 'Transit Track',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            brightness: brightness,
            scaffoldBackgroundColor: bg,
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppColors.accent,
              brightness: brightness,
              surface: bg,
            ),
          ),
          home: const MapScreen(),
        );
      },
    );
  }
}
