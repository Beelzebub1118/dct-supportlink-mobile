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
  await NotificationService.firebaseMessagingBackgroundHandler(message);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await NotificationService.initForegroundHandlers(context);

      if (FirebaseAuth.instance.currentUser != null) {
        await NotificationService.saveTokenToFirestore(context);
      }

      NotificationService.listenTokenRefresh(context);

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
