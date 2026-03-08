import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'screens/remote_screen.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    try {
      await MobileAds.instance.initialize();
    } catch (e) {
      debugPrint('AdMob init error: $e');
    }

    runApp(const MyApp());
  }, (error, stack) {
    runApp(ErrorApp(error: error.toString()));
  });
}

class ErrorApp extends StatelessWidget {
  final String error;
  const ErrorApp({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 60),
              const Text('❌ Error', style: TextStyle(color: Colors.red, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Text(error, style: const TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Samsung Remote',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF101722),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF0d69f2),
          surface: Color(0xFF1a2235),
        ),
      ),
      home: const RemoteScreen(),
    );
  }
}