import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReportStatusWatcher {
  final String uid;
  final FlutterLocalNotificationsPlugin _local;
  final _db = FirebaseFirestore.instance;

  StreamSubscription? _subSubmitted;
  StreamSubscription? _subOnProcess;
  StreamSubscription? _subResolved;

  bool _started = false;

  // de-dupe caches
  final Set<String> _seenSubmitted = {};
  final Set<String> _seenOnProcess = {};
  final Set<String> _seenResolved = {};

  ReportStatusWatcher(this.uid, this._local);

  // ---- persistence keys
  String get _kSubmitted => 'seen_submitted_$uid';
  String get _kOnProcess => 'seen_onprocess_$uid';
  String get _kResolved  => 'seen_resolved_$uid';

  Future<void> _loadSeen() async {
    final p = await SharedPreferences.getInstance();
    _seenSubmitted.addAll(p.getStringList(_kSubmitted) ?? const []);
    _seenOnProcess.addAll(p.getStringList(_kOnProcess) ?? const []);
    _seenResolved.addAll(p.getStringList(_kResolved) ?? const []);
  }

  Future<void> _persistSeen() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kSubmitted, _seenSubmitted.toList());
    await p.setStringList(_kOnProcess, _seenOnProcess.toList());
    await p.setStringList(_kResolved,  _seenResolved.toList());
  }

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

  /// Start watching. Safe to call multiple times; it only attaches once.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    await _loadSeen();

    // Skip first snapshot flags
    var skipSubmittedFirst = true;
    var skipOnProcessFirst = true;
    var skipResolvedFirst  = true;

    // (Optional) Submitted confirmation (userReport)
    _subSubmitted = _db
        .collection('userReport')
        .where('uid', isEqualTo: uid)
        .snapshots()
        .listen((snap) async {
      if (skipSubmittedFirst) { skipSubmittedFirst = false; return; }
      for (final c in snap.docChanges) {
        if (c.type != DocumentChangeType.added) continue;
        final id = c.doc.id;
        if (_seenSubmitted.contains(id)) continue;

        final data = c.doc.data() ?? {};
        final svc = (data['serviceType'] ?? 'Your report').toString();
        await _notify('Submitted', '$svc submitted successfully.');

        _seenSubmitted.add(id);
      }
      await _persistSeen();
    });

    // In Process
    _subOnProcess = _db
        .collection('onProcess')
        .where('uid', isEqualTo: uid)
        .snapshots()
        .listen((snap) async {
      if (skipOnProcessFirst) { skipOnProcessFirst = false; return; }
      for (final c in snap.docChanges) {
        if (c.type != DocumentChangeType.added) continue;
        final id = c.doc.id;
        if (_seenOnProcess.contains(id)) continue;

        final data = c.doc.data() ?? {};
        final svc = (data['serviceType'] ?? 'Your report').toString();
        await _notify('Report is now In Process', '$svc is being worked on.');

        _seenOnProcess.add(id);
      }
      await _persistSeen();
    });

    // Resolved
    _subResolved = _db
        .collection('resolvedReports')
        .where('uid', isEqualTo: uid)
        .snapshots()
        .listen((snap) async {
      if (skipResolvedFirst) { skipResolvedFirst = false; return; }
      for (final c in snap.docChanges) {
        if (c.type != DocumentChangeType.added) continue;
        final id = c.doc.id;
        if (_seenResolved.contains(id)) continue;

        final data = c.doc.data() ?? {};
        final svc = (data['serviceType'] ?? 'Your report').toString();
        await _notify('Resolved', '$svc has been marked resolved.');

        _seenResolved.add(id);
      }
      await _persistSeen();
    });
  }

  void dispose() {
    _subSubmitted?.cancel();
    _subOnProcess?.cancel();
    _subResolved?.cancel();
    _started = false;
  }
}
