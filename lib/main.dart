// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'firebase_options.dart';
import 'login.dart';
import 'dashboard.dart';
import 'notification_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseBackground(RemoteMessage message) async {
  // Keep empty to avoid double-showing; we handle local notifs in foreground.

}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Background FCM handler (must be a top-level/annotated function).
  FirebaseMessaging.onBackgroundMessage(_firebaseBackground);

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();

    // Delay until a frame is available so `context` is safe for NotificationService.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 1) Init local notifications + FCM foreground handling.
      await NotificationService.initForegroundHandlers(context);

      // 2) Keep token fresh
      NotificationService.listenTokenRefresh(context);

      // 3) React to login/logout and start/stop the Firestore watcher
      _authSub =
          FirebaseAuth.instance.authStateChanges().listen((User? user) async {
            if (user != null) {
              await NotificationService.saveTokenToFirestore(context);
              NotificationService.startStatusWatch(); // ✅ start only here
            } else {
              NotificationService.stopStatusWatch(); // ✅ stop on logout
            }
          });
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    NotificationService.stopStatusWatch();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DCT Supportlink',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      initialRoute: '/login',
      routes: {
        '/login': (_) => const LoginScreen(),
        '/dashboard': (_) => const Dashboard(),
      },
      onUnknownRoute: (_) =>
          MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }
}
