// lib/notification_service.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static final _messaging = FirebaseMessaging.instance;
  static final _auth = FirebaseAuth.instance;
  static final _db = FirebaseFirestore.instance;

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

  // --- local de-dupe ---
  static const _recentKey = 'recent_notif_ids_v1';
  static const _recentCap = 100;

  static Future<bool> _alreadyShown(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_recentKey) ?? const [];
    return list.contains(id);
  }

  static Future<void> _markShown(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_recentKey) ?? <String>[];
    if (!list.contains(id)) {
      list.add(id);
      if (list.length > _recentCap) {
        list.removeRange(0, list.length - _recentCap);
      }
      await prefs.setStringList(_recentKey, list);
    }
  }

  // --- Firestore de-dupe (per user per notif) ---
  static Future<bool> _markIfFirstSeen(String notifId) async {
    final user = _auth.currentUser;
    if (user == null) return !(await _alreadyShown(notifId));

    final docRef = _db
        .collection('users')
        .doc(user.uid)
        .collection('seenNotifications')
        .doc(notifId);

    try {
      return await _db.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        if (snap.exists) return false;
        tx.set(docRef, {'seenAt': FieldValue.serverTimestamp()});
        return true;
      });
    } catch (e) {
      debugPrint('⚠️ seenNotifications transaction failed: $e');
      return !(await _alreadyShown(notifId));
    }
  }

  static String _normStatus(String s) =>
      s.toLowerCase().trim().replaceAll(RegExp(r'\s+'), '');

  // --- FCM setup ---
  static Future<void> initForegroundHandlers(BuildContext context) async {
    if (_inited) return;
    _inited = true;

    await _messaging.requestPermission(alert: true, badge: true, sound: true);
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: true,
    );

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await local.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    await local
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final n = message.notification;
      if (n == null) return;

      final notifId =
          message.data['notifId'] ?? 'fcm:${message.data['reportId'] ?? ''}:${message.data['status'] ?? ''}';

      final first = await _markIfFirstSeen(notifId);
      if (!first) return;
      if (await _alreadyShown(notifId)) return;

      final intId = notifId.hashCode & 0x7fffffff;
      await local.show(
        intId,
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
      );
      await _markShown(notifId);
    });
  }

  // --- Firestore watcher for report status changes ---
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _reportSub;
  static bool _primed = false;
  static final Map<String, String> _lastByReport = {};

  static Future<void> startStatusWatch() async {
    final user = _auth.currentUser;
    if (user == null) return;
    stopStatusWatch();

    _primed = false;
    _lastByReport.clear();

    _reportSub = _db
        .collection('userReport')
        .where('uid', isEqualTo: user.uid)
        .snapshots()
        .listen((snap) async {
      if (!_primed) {
        for (final d in snap.docs) {
          final raw = (d.data()['status'] ?? '').toString();
          _lastByReport[d.id] = _normStatus(raw);
        }
        _primed = true;
        return;
      }

      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.modified) continue;
        final doc = change.doc;
        final data = doc.data();
        if (data == null) continue;

        final raw = (data['status'] ?? '').toString();
        final norm = _normStatus(raw);
        final prev = _lastByReport[doc.id];
        if (norm == prev) continue;

        _lastByReport[doc.id] = norm;

        // 🔥 Only notify for "onprocess" or "resolved"
        if (norm != 'onprocess' && norm != 'resolved') continue;

        final notifId = 'report:${doc.id}:$norm';
        final firstTime = await _markIfFirstSeen(notifId);
        if (!firstTime) continue;
        if (await _alreadyShown(notifId)) continue;

        String title, body;
        if (norm == 'onprocess') {
          title = 'Your report is being processed';
          body =
          'Report "${data['serviceType'] ?? data['platformName'] ?? doc.id}" is now in progress.';
        } else {
          title = 'Report resolved';
          body = 'A fix was submitted for your report. Please review & approve.';
        }

        final intId = notifId.hashCode & 0x7fffffff;
        await local.show(
          intId,
          title,
          body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'high_importance_channel',
              'High Importance Notifications',
              priority: Priority.high,
              importance: Importance.high,
            ),
            iOS: DarwinNotificationDetails(),
          ),
        );
        await _markShown(notifId);
      }
    });
  }

  static void stopStatusWatch() {
    _reportSub?.cancel();
    _reportSub = null;
    _primed = false;
    _lastByReport.clear();
  }

  // --- Token helpers ---
  static Future<void> saveTokenToFirestore(BuildContext context) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final token = await _messaging.getToken();
    if (token != null && token.isNotEmpty) {
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

  static void listenTokenRefresh(BuildContext context) {
    _messaging.onTokenRefresh.listen((_) => saveTokenToFirestore(context));
  }

  static Future<void> removeCurrentTokenFromFirestore() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      final token = await _messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _db
            .collection('users')
            .doc(user.uid)
            .collection('fcmTokens')
            .doc(token)
            .delete();
      }
    } catch (e) {
      debugPrint('removeCurrentTokenFromFirestore error: $e');
    }
  }

  static Future<void> signOutCleanup(BuildContext context) async {
    stopStatusWatch();
    await removeCurrentTokenFromFirestore();
    try {
      await _messaging.deleteToken();
    } catch (e) {
      debugPrint('deleteToken failed: $e');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_recentKey);
    } catch (_) {}
  }
}
