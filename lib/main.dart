import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'firebase_options.dart';
import 'login.dart';
import 'dashboard.dart';
import 'notification_service.dart';

/// Required for background messages on Android.
/// Keep this top-level (outside any class).
@pragma('vm:entry-point')
Future<void> _firebaseBackground(RemoteMessage message) async {
  await NotificationService.firebaseMessagingBackgroundHandler(message);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Register background handler before runApp.
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

    // Wait for a BuildContext, then init notification handlers & save token.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Foreground notifications + permission + local channel
      await NotificationService.initForegroundHandlers(context);

      // If already logged in, save current token
      if (FirebaseAuth.instance.currentUser != null) {
        await NotificationService.saveTokenToFirestore(context);
      }

      // Keep FCM token fresh in Firestore
      NotificationService.listenTokenRefresh(context);

      // Save token whenever auth state changes to a logged-in user
      _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
        if (user != null) {
          await NotificationService.saveTokenToFirestore(context);
        }
      });
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
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
      onUnknownRoute: (_) => MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ),
    );
  }
}
