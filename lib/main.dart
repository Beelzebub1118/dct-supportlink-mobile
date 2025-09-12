import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'login.dart';
import 'dashboard.dart';
import 'SplashScreen.dart'; // ⬅️ import the splash screen

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DCT Supportlink',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),

      // Start with Splash
      initialRoute: '/splash',

      // Named routes
      routes: {
        '/splash': (_) => const SplashScreen(),
        '/login': (_) => const LoginScreen(),
        '/dashboard': (_) => const Dashboard(),
      },

      // Fallback route
      onUnknownRoute: (_) => MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ),
    );
  }
}
