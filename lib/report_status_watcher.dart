import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class ReportStatusWatcher {
  final String uid;
  final FlutterLocalNotificationsPlugin _local;
  final _db = FirebaseFirestore.instance;

  StreamSubscription? _sub1;
  StreamSubscription? _sub2;
  StreamSubscription? _sub3;

  ReportStatusWatcher(this.uid, this._local);

  // Helper to show a local notification
  Future<void> _notify(String title, String body) async {
    await _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  // Start watching userReport → onProcess → resolvedReports for this user
  void start() {
    // When a doc appears in onProcess for me
    _sub2 = _db
        .collection('onProcess')
        .where('uid', isEqualTo: uid)
        .snapshots()
        .listen((snap) {
      for (final c in snap.docChanges) {
        if (c.type == DocumentChangeType.added) {
          final data = c.doc.data() ?? {};
          final svc = (data['serviceType'] ?? 'Your report') as String;
          _notify('Report is now In Process', '$svc is being worked on.');
        }
      }
    });

    // When a doc appears in resolvedReports for me
    _sub3 = _db
        .collection('resolvedReports')
        .where('uid', isEqualTo: uid)
        .snapshots()
        .listen((snap) {
      for (final c in snap.docChanges) {
        if (c.type == DocumentChangeType.added) {
          final data = c.doc.data() ?? {};
          final svc = (data['serviceType'] ?? 'Your report') as String;
          _notify('Resolved', '$svc has been marked resolved.');
        }
      }
    });

    // (Optional) If admin removes from onProcess back to pending (rare)
    _sub1 = _db
        .collection('userReport')
        .where('uid', isEqualTo: uid)
        .snapshots()
        .listen((snap) {
      for (final c in snap.docChanges) {
        if (c.type == DocumentChangeType.added) {
          final data = c.doc.data() ?? {};
          final svc = (data['serviceType'] ?? 'Your report') as String;
          _notify('Submitted', '$svc submitted successfully.');
        }
      }
    });
  }

  void dispose() {
    _sub1?.cancel();
    _sub2?.cancel();
    _sub3?.cancel();
  }
}
