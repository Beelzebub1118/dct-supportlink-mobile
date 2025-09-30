import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final _messaging = FirebaseMessaging.instance;
  static final _auth = FirebaseAuth.instance;
  static final _db = FirebaseFirestore.instance;

  // ----- Local notifications (foreground) -----
  static final FlutterLocalNotificationsPlugin local =
  FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _androidChannel =
  AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    importance: Importance.high,
    description: 'General notifications for SupportLink',
  );

  static bool _inited = false;

  /// Call once (e.g., from MyApp.initState after build) to set up listeners
  static Future<void> initForegroundHandlers(BuildContext context) async {
    if (_inited) return;
    _inited = true;

    // iOS / Android 13+ permission
    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    // Local notifications init
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await local.initialize(const InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    ));

    // Create Android channel
    await local
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);

    // Foreground messages: show a local notification
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final n = message.notification;
      if (n != null) {
        local.show(
          n.hashCode,
          n.title ?? 'Notification',
          n.body ?? '',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'high_importance_channel',
              'High Importance Notifications',
              priority: Priority.high,
              importance: Importance.high,
            ),
            iOS: DarwinNotificationDetails(),
          ),
          payload: message.data['route'], // optional deep link
        );
      }
    });

    // App opened from a notification (tap while app in background)
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      // Optional: Navigate using message.data['route']
      // Do not show another dialog here to avoid duplicates.
    });
  }

  /// Background handler (must be a top-level function; wired in main.dart)
  static Future<void> firebaseMessagingBackgroundHandler(
      RemoteMessage message) async {
    // If you need background processing, you can initialize firebase here.
    // Keep in mind: no BuildContext / UI here.
  }

  /// Save token under users/{uid}/fcmTokens/{token}
  static Future<void> saveTokenToFirestore(BuildContext context) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final token = await _messaging.getToken();
    if (token != null) {
      await _db
          .collection('users')
          .doc(user.uid)
          .collection('fcmTokens')
          .doc(token)
          .set({
        'token': token,
        'platform': Theme.of(context).platform.name,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  /// Keep token up-to-date
  static void listenTokenRefresh(BuildContext context) {
    _messaging.onTokenRefresh.listen((_) => saveTokenToFirestore(context));
  }
}
