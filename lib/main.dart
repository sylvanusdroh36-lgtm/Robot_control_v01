// FILE: lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/control_page.dart';
import 'screens/settings_page.dart';
import 'services/esp32_service.dart';

void main() {
  runApp(const RobotApp());
}

class RobotApp extends StatelessWidget {
  const RobotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => Esp32Service(),
      child: MaterialApp(
        title: 'Robot Wi‑Fi Control',
        theme: ThemeData.dark().copyWith(
          primaryColor: Colors.blueAccent,
          scaffoldBackgroundColor: const Color(0xFF0B0E13),
        ),
        initialRoute: '/',
        routes: {
          '/': (_) => const ControlPage(),
          '/settings': (_) => const SettingsPage(),
        },
      ),
    );
  }
}