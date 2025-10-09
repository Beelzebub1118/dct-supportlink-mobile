import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'ChangePass.dart';
import 'editprofile.dart';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'ui_messages.dart';
import 'dart:async';
import 'package:rxdart/rxdart.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'dart:convert';
import 'package:http/http.dart' as http;
class ReportStatusWatcher {
  final String uid;
  final FlutterLocalNotificationsPlugin _local;
  final _db = FirebaseFirestore.instance;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _onProcessSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _resolvedSub;

  ReportStatusWatcher(this.uid, this._local);

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

  void start() {
    // When admin moves a report to "On Process"
    _onProcessSub = _db
        .collection('onProcess')
        .where('uid', isEqualTo: uid)
        .snapshots()
        .listen((snap) {
      for (final c in snap.docChanges) {
        if (c.type == DocumentChangeType.added) {
          final data = c.doc.data() ?? {};
          final svc = (data['serviceType'] ?? 'Your report') as String;
          _notify('Report in process', '$svc is now being worked on.');
        }
      }
    });

    // When admin marks a report "Resolved"
    _resolvedSub = _db
        .collection('resolvedReports')
        .where('uid', isEqualTo: uid)
        .snapshots()
        .listen((snap) {
      for (final c in snap.docChanges) {
        if (c.type == DocumentChangeType.added) {
          final data = c.doc.data() ?? {};
          final svc = (data['serviceType'] ?? 'Your report') as String;
          _notify('Report resolved', '$svc has been marked resolved.');
        }
      }
    });
  }

  void dispose() {
    _onProcessSub?.cancel();
    _resolvedSub?.cancel();
  }
}

// Simple chat message model (used by the chat overlay below)
class _ChatMsg {
  final String text;
  final bool isUser;
  const _ChatMsg({required this.text, required this.isUser});
}

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  _DashboardState createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  int _selectedIndex = 0;
  final Color pinkColor = const Color(0xFFEB58B5);
  final Color iconColor = Colors.white;
  final Color inactiveIconColor = Colors.white70;

  // ── NEW: local notifications instance + watcher
  final _local = FlutterLocalNotificationsPlugin();
  ReportStatusWatcher? _watcher;

  Map<String, String> _customSolutions = {}; // question -> joined answers
  List<String> _customOrder = [];            // admin order (newest first)
  StreamSubscription<QuerySnapshot>? _presetSub;

  String _answerFor(String q) {
    return _customSolutions[q] ??
        _selfHelpSolutions[q] ??
        "Please select a valid question.\n$_NOTE";
  }

  void _subscribePresets() {
    _presetSub = FirebaseFirestore.instance
        .collection('chatbotPresets')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snap) {
      final map = <String, String>{};
      final order = <String>[];

      for (final d in snap.docs) {
        final data = d.data() as Map<String, dynamic>? ?? {};
        final q = (data['question'] as String?)?.trim() ?? '';
        if (q.isEmpty) continue;

        // answers can be List<String> or a single String
        String joined;
        final ansList = data['answers'];
        if (ansList is List) {
          joined = ansList.whereType<String>().join('\n');
        } else {
          joined = (data['answers'] as String?)?.trim() ?? '';
        }

        map[q] = joined;
        order.add(q);
      }

      if (mounted) {
        setState(() {
          _customSolutions = map;
          _customOrder = order;
        });
      }
    }, onError: (_) {
      if (mounted) {
        setState(() {
          _customSolutions = {};
          _customOrder = [];
        });
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _subscribePresets();

    // ── Start the Firestore watcher for this logged-in user
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _watcher = ReportStatusWatcher(uid, _local)..start();
    }
  }

  @override
  void dispose() {
    _watcher?.dispose();
    _presetSub?.cancel();
    _chatScroll.dispose();
    super.dispose();
  }

  // 3 pages now (Chat is a bubble overlay)
  final List<Widget> _pages = const [
    ReportModulePage(),
    ReportLogsPage(),
    ProfilePage(),
  ];

  // Chat bubble state
  bool _chatOpen = false;
  final List<_ChatMsg> _chatMessages = [];
  final ScrollController _chatScroll = ScrollController();
  void _clearChat() {
    setState(() {
      _chatMessages.clear();
      _mobileTab = 'issues';   // optional: jump back to the issues list
      _isReplying = false;     // optional: stop typing indicator
    });
  }

  // --- Web-like chat structure controls ---
  String _mobileTab = 'issues'; // 'issues' | 'chat'
  bool _isReplying = false;

  List<String> get _questions {
    final qs = [..._customOrder]; // admin first
    for (final k in _selfHelpSolutions.keys) {
      if (!qs.contains(k)) qs.add(k);       // then defaults
    }
    return qs;
  }

  // Quick help content (same as your ChatbotPage)
  static const String _NOTE =
      'If the issue persists, please submit an IT Support Services report or contact MIS.';

  final Map<String, String> _selfHelpSolutions = {
    "PC won't turn on":
    "1) Check power: Ensure the AVR/extension and wall outlet switches are ON.\n"
        "2) Cables: Firmly reseat the PC power cable and monitor power cable.\n"
        "3) Power button: Hold for 5 seconds, then press once to start.\n"
        "4) Power indicators: If no lights/fans at all, move the plug to a known working outlet/AVR port.\n"
        "$_NOTE",
    "No display on monitor/projector":
    "1) Monitor/Projector power: Confirm device is ON and input source is correct (HDMI/VGA).\n"
        "2) Cable check: Reseat both ends of the video cable (PC <-> Monitor/Projector).\n"
        "3) Display toggle (Windows): Press Win + P and try Duplicate or Extend.\n"
        "4) Brightness: Increase brightness or use monitor/projector menu to reset input.\n"
        "$_NOTE",
    "Wi-Fi won't connect":
    "1) Airplane mode OFF: Check Windows quick settings.\n"
        "2) Forget & reconnect: Settings → Network & Internet → Wi-Fi → Manage networks → Forget, then reconnect with the correct password.\n"
        "3) Try another SSID if available for your room/role.\n"
        "4) Reboot PC. If others are also affected, it may be a local network issue.\n"
        "$_NOTE",
    "No internet (connected but no access)":
    "1) Test another site (e.g., example.com).\n"
        "2) Browser refresh / try another browser.\n"
        "3) Flush DNS: Open Command Prompt → type: ipconfig /flushdns → Enter.\n"
        "4) Reconnect Wi-Fi or replug LAN cable (click it in until it clicks).\n"
        "$_NOTE",
    "PC is very slow or frozen":
    "1) Close heavy apps/tabs you don’t need.\n"
        "2) Press Ctrl + Shift + Esc → Task Manager → End tasks that are Not Responding (only apps you opened).\n"
        "3) Restart the PC.\n"
        "4) Free disk space: Delete large downloads/temp files if you’re allowed.\n"
        "$_NOTE",
    "No sound / audio problems":
    "1) Volume: Unmute and raise volume (system & app).\n"
        "2) Output device: Click speaker icon → choose correct device (Speakers/Headphones/Projector).\n"
        "3) Cable check: Ensure 3.5mm jack or HDMI is fully inserted; power on external speakers.\n"
        "4) Test with another app (YouTube, local file).\n"
        "$_NOTE",
    "Keyboard or mouse not working":
    "1) Wired: Unplug and replug to a different USB port; avoid USB hubs if possible.\n"
        "2) Wireless: Ensure receiver is seated; replace/charge batteries; power toggle ON.\n"
        "3) Try another known-good keyboard/mouse if available.\n"
        "$_NOTE",
    "Printer won't print":
    "1) Power & paper: Printer ON, paper loaded, no paper jam.\n"
        "2) Correct printer: In Printers & Scanners, set the correct device as default.\n"
        "3) Queue: Open print queue → cancel stuck jobs → print again.\n"
        "4) Connection: For network printers, ensure you’re on the right network; for USB, replug the cable.\n"
        "$_NOTE",
    "Projector shows \"No Signal\"":
    "1) Input source: Set projector to the correct HDMI/VGA input.\n"
        "2) Cable: Reseat the display cable at the PC and projector.\n"
        "3) Windows display: Press Win + P → select Duplicate.\n"
        "4) Wake screen: Move mouse/press a key to wake the PC.\n"
        "$_NOTE",
    "Can't access LMS/website":
    "1) Confirm internet works on other sites.\n"
        "2) Try another browser / incognito window.\n"
        "3) Clear cache (Ctrl + Shift + Del → cached images/files).\n"
        "4) Check with colleagues if the site has known downtime.\n"
        "$_NOTE",
    "App keeps crashing / won't open":
    "1) Close other apps and retry.\n"
        "2) Restart the PC.\n"
        "3) If the app needs sign-in, sign out/in again with the correct account.\n"
        "4) If it’s a lab app and still fails, report it for re-install.\n"
        "$_NOTE",
    "Account / password problems":
    "1) Verify CAPS LOCK and keyboard layout.\n"
        "2) If you recently changed your password, sign out and sign in again across apps.\n"
        "3) For locked/expired accounts, contact the MIS team via an IT Support Services report.\n"
        "$_NOTE",
  };

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      if (_selectedIndex != 0) _chatOpen = false; // hide help/chat off the report module
    });
  }


  // --- Web-like pick handler (switches to conversation on mobile + typing) ---
  void _sendChat(String q) {
    if (_isReplying) return;

    setState(() {
      _chatMessages.add(_ChatMsg(text: q, isUser: true));
      _mobileTab = 'chat'; // switch to Conversation on mobile
      _isReplying = true;  // show typing indicator
    });

    Future.delayed(const Duration(milliseconds: 320), () {
      final reply = _answerFor(q);
      setState(() {
        _chatMessages.add(_ChatMsg(text: reply, isUser: false));
        _isReplying = false;
      });

      // scroll to bottom after reply
      Future.delayed(const Duration(milliseconds: 60), () {
        if (_chatScroll.hasClients) {
          _chatScroll.animateTo(
            _chatScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final navH = (size.height * 0.085).clamp(56.0, 72.0);
    final iconSz = (size.shortestSide * 0.08).clamp(24.0, 32.0);

    return Scaffold(
      body: Stack(
        children: [
          // current page
          _pages[_selectedIndex],

          // chat side tab
          // chat side tab (ONLY on ReportModulePage)
          if (_selectedIndex == 0)
            Positioned(
              right: 0,
              top: size.height * 0.3,
              child: GestureDetector(
                onTap: () => setState(() => _chatOpen = true),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFEB58B5),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                    ),
                  ),
                  child: const RotatedBox(
                    quarterTurns: 1,
                    child: Text(
                      'Help',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // chat overlay panel (ONLY on ReportModulePage)
          // chat overlay panel (ONLY on ReportModulePage)
          // chat overlay panel (ONLY on ReportModulePage)
          if (_selectedIndex == 0 && _chatOpen) _buildChatOverlay(context),


        ],

      ),
      bottomNavigationBar: CurvedNavigationBar(
        height: navH,
        backgroundColor: const Color(0xFFFDE2FF),
        color: const Color(0xFFEB58B5),
        buttonBackgroundColor: const Color(0xFFEB58B5),
        animationDuration: const Duration(milliseconds: 300),
        items: <Widget>[
          Icon(
            Icons.assessment_outlined,
            size: iconSz,
            color: _selectedIndex == 0 ? Colors.white : Colors.white70,
          ),
          Icon(
            Icons.history_outlined,
            size: iconSz,
            color: _selectedIndex == 1 ? Colors.white : Colors.white70,
          ),
          Icon(
            Icons.account_circle_outlined,
            size: iconSz,
            color: _selectedIndex == 2 ? Colors.white : Colors.white70,
          ),
        ],
        index: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }

  Widget _buildChatOverlay(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width >= 700;
    final panelW = isWide ? 380.0 : size.width * 0.94;
    final panelH = isWide ? 520.0 : size.height * 0.75;

    return Stack(
      children: [
        // dim background (tap to close)
        Positioned.fill(
          child: GestureDetector(
            onTap: () => setState(() => _chatOpen = false),
            child: Container(color: Colors.black.withOpacity(.45)),
          ),
        ),
        // panel
        Align(
          alignment: isWide ? Alignment.bottomRight : Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(
              right: isWide ? 16 : 0,
              bottom: isWide ? 16 : 8,
            ),
            child: Material(
              color: Colors.white,
              elevation: 10,
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: isWide ? 720 : panelW, // wider to fit two columns on wide
                height: panelH,
                child: Column(
                  children: [
                    // header (same colors)
                    Container(
                      height: 56,
                      decoration: const BoxDecoration(
                        color: Color(0xFF0A1936),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: Colors.white,
                            child: Icon(Icons.support_agent, color: Color(0xFF0A1936)),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Maintenance Self-Help',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _clearChat,
                            child: const Text('Clear', style: TextStyle(color: Colors.white)),
                          ),
                          IconButton(
                            onPressed: () => setState(() => _chatOpen = false),
                            icon: const Icon(Icons.close, color: Colors.white),
                          ),
                        ],
                      ),
                    ),

                    // body: web-like structure
                    Expanded(
                      child: isWide
                          ? Row(
                        children: [
                          // LEFT: issues list (border-right)
                          SizedBox(
                            width: 300,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border(
                                      right: BorderSide(color: Colors.grey.shade300),
                                      bottom: BorderSide(color: Colors.grey.shade300),
                                    ),
                                  ),
                                  child: Row(
                                    children: const [
                                      CircleAvatar(
                                        radius: 12,
                                        backgroundColor: Color(0xFFEB58B5),
                                        child: Icon(Icons.smart_toy, color: Colors.white, size: 14),
                                      ),
                                      SizedBox(width: 8),
                                      Text('Common Issues', style: TextStyle(fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.all(12),
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: _questions.map((q) {
                                        return ActionChip(
                                          label: Text(q),
                                          onPressed: () => _sendChat(q),
                                          backgroundColor: const Color(0xFFEB58B5),
                                          labelStyle: const TextStyle(color: Colors.white),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // RIGHT: conversation
                          Expanded(child: _conversationArea(panelW: panelW, isWide: true)),
                        ],
                      )
                          : Column(
                        children: [
                          // mobile tabs
                          Container(
                            color: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Row(
                              children: [
                                _tabBtn('Common Issues', _mobileTab == 'issues', () {
                                  setState(() => _mobileTab = 'issues');
                                }),
                                const SizedBox(width: 8),
                                _tabBtn('Conversation', _mobileTab == 'chat', () {
                                  setState(() => _mobileTab = 'chat');
                                }),
                              ],
                            ),
                          ),

                          // content
                          Expanded(
                            child: _mobileTab == 'issues'
                                ? SingleChildScrollView(
                              padding: const EdgeInsets.all(12),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _questions.map((q) {
                                  return ActionChip(
                                    label: Text(q),
                                    onPressed: () => _sendChat(q),
                                    backgroundColor: const Color(0xFFEB58B5),
                                    labelStyle: const TextStyle(color: Colors.white),
                                  );
                                }).toList(),
                              ),
                            )
                                : _conversationArea(panelW: panelW, isWide: false),
                          ),
                        ],
                      ),
                    ),

                    // footer note (unchanged)
                    const Divider(height: 1),
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(8),
                      ),

                    ),


                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Conversation area (reuses your bubble look)
  Widget _conversationArea({required double panelW, required bool isWide}) {
    final initial = _chatMessages.isEmpty
        ? Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: const Text(
        "Hi! Pick an issue and I’ll guide you through safe, basic troubleshooting.\n"
            "Reminder: Do NOT open the system unit.",
        style: TextStyle(fontSize: 14),
      ),
    )
        : const SizedBox.shrink();

    return Container(
      color: Colors.grey.shade50,
      child: Column(
        children: [
          if (isWide)
            Container(
              height: 44,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
              ),
              child: const Text('Conversation', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          Expanded(
            child: ListView.builder(
              controller: _chatScroll,
              padding: const EdgeInsets.all(12),
              itemCount: _chatMessages.length + 1 + (_isReplying ? 1 : 0),
              itemBuilder: (_, i) {
                // show intro first
                if (i == 0) return initial;

                // typing indicator appended at end
                if (_isReplying && i == _chatMessages.length + 1) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('typing…'),
                    ),
                  );
                }

                final m = _chatMessages[i - 1];
                return Align(
                  alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: m.isUser ? const Color(0xFFEB58B5) : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    constraints: BoxConstraints(maxWidth: (isWide ? 720 : panelW) * 0.78),
                    child: Text(
                      m.text,
                      style: TextStyle(
                        color: m.isUser ? Colors.white : Colors.grey.shade900,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabBtn(String label, bool active, VoidCallback onTap) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: active ? Colors.black : Colors.grey.shade400),
        backgroundColor: active ? Colors.black : Colors.white,
        foregroundColor: active ? Colors.white : Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: const StadiumBorder(),
      ),
      onPressed: onTap,
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

// ----------------------------------------------------------------------
// Report Module
// ----------------------------------------------------------------------

class ReportModulePage extends StatefulWidget {
  const ReportModulePage({super.key});
  @override
  State<ReportModulePage> createState() => _ReportModulePageState();
}

class _ReportModulePageState extends State<ReportModulePage> {
  // Form controllers
  final _buildingCtrl = TextEditingController(); // kept for compatibility (unused with dropdown)
  final _floorCtrl = TextEditingController(); // text field again
  final _platformCtrl = TextEditingController(); // software only
  final _detailsCtrl = TextEditingController();

  // Service types (match web)
  static const String svcFM   = 'Facilities and Maintenance';
  static const String svcITSW = 'IT Support Services - Software';
  static const String svcITHW = 'IT Support Services - Hardware';
  static const List<String> _serviceTypes = [svcFM, svcITSW, svcITHW];

  String? _serviceType; // null = chooser screen (like web first page)

  // ----- Building dropdown options -----
  static const List<Map<String, String>> _kBuildings = [
    {'value': 'SD',  'label': 'SD - St. Dominic BLDG'},
    {'value': 'HR',  'label': 'HR - Holy Rosary BLDG'},
    {'value': 'OLP', 'label': 'OLP - Our Lady of Peace BLDG'},
    {'value': 'SLR', 'label': 'SLR - San Lorenzo BLDG'},
    {'value': 'OLF', 'label': 'OLF - Our Lady of Fatima BLDG'},
    {'value': 'SCS', 'label': 'SCS - St. Catherine of Siena BLDG'},
  ];
  String? _buildingValue; // selected building code (e.g., "SD")

  // Image
  final _picker = ImagePicker();
  XFile? _pickedImage;

  // UI
  bool _submitting = false;
  bool _showHelp = false;

  // Colors
  final Color _brand = const Color(0xFFEB58B5); // submit button uses this (same as before)
  final Color _pink  = const Color(0xFFEB58B5);

  @override
  void dispose() {
    _buildingCtrl.dispose();
    _floorCtrl.dispose();
    _platformCtrl.dispose();
    _detailsCtrl.dispose();
    super.dispose();
  }

  // ---------- Image pickers ----------
  Future<void> _chooseImage() async {
    if (_submitting) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Pick from gallery'),
            onTap: () async {
              Navigator.pop(context);
              final file = await _picker.pickImage(
                source: ImageSource.gallery, imageQuality: 85, maxWidth: 1600,
              );
              if (file != null && mounted) setState(() => _pickedImage = file);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera),
            title: const Text('Take a photo'),
            onTap: () async {
              Navigator.pop(context);
              final file = await _picker.pickImage(
                source: ImageSource.camera, imageQuality: 85, maxWidth: 1600,
              );
              if (file != null && mounted) setState(() => _pickedImage = file);
            },
          ),
          const SizedBox(height: 6),
        ]),
      ),
    );
  }

  void _removeImage() {
    if (_submitting) return;
    setState(() => _pickedImage = null);
  }

  void _previewImage() {
    if (_pickedImage == null) return;
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierColor: Colors.black87,
      builder: (_) => GestureDetector(
        onTap: () => Navigator.of(context, rootNavigator: true).pop(),
        child: Stack(children: [
          Center(child: InteractiveViewer(child: Image.file(File(_pickedImage!.path)))),
          Positioned(
            top: 24, right: 24,
            child: IconButton(
              style: IconButton.styleFrom(backgroundColor: Colors.black54),
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            ),
          ),
        ]),
      ),
    );
  }

  // ---------- Cloudinary ----------
  Future<String?> _uploadToCloudinary(XFile file) async {
    final uri = Uri.parse('https://api.cloudinary.com/v1_1/dsycysb0e/image/upload');
    final req = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = 'supportlink'
      ..files.add(http.MultipartFile.fromBytes('file', await file.readAsBytes(), filename: file.name));
    final streamResp = await req.send();
    final resp = await http.Response.fromStream(streamResp);
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return data['secure_url'] as String?;
    }
    return null;
  }

  // ---------- Submit ----------
  Future<void> _submit() async {
    final platform = _platformCtrl.text.trim();
    final floor = _floorCtrl.text.trim();
    final details = _detailsCtrl.text.trim();
    final service = _serviceType;
    final image = _pickedImage;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      await AppMsg.notSignedIn(context);
      return;
    }

    // Validation mirrors your web rules — show AppMsg dialogs
    if (service == null || image == null || details.isEmpty) {
      await AppMsg.incompleteForm(context, custom: 'Please complete all required fields and select an image.');
      return;
    }
    if (service == svcITSW) {
      if (platform.isEmpty) {
        await AppMsg.incompleteForm(context, custom: 'Please enter the Platform / System Name.');
        return;
      }
    } else {
      if (_buildingValue == null || floor.isEmpty) {
        await AppMsg.incompleteForm(context, custom: 'Please choose building and enter floor/room location.');
        return;
      }
    }

    setState(() => _submitting = true);
    try {
      final imageUrl = await _uploadToCloudinary(image);
      if (imageUrl == null) {
        await AppMsg.uploadFailed(context);
        return;
      }

      // Map selected building code to its label for storing
      String? buildingLabel;
      if (_buildingValue != null) {
        buildingLabel = _kBuildings.firstWhere(
              (e) => e['value'] == _buildingValue,
          orElse: () => const {'label': ''},
        )['label'];
      }

      final base = <String, dynamic>{
        'serverTimeStamp': FieldValue.serverTimestamp(),
        'serviceType': service,
        'additionalDetails': details,
        'imageUrl': imageUrl,
        'uid': uid,
        'status': 'Pending',
      };

      final payload = (service == svcITSW)
          ? {...base, 'platformName': platform}
          : {...base, 'buildingName': buildingLabel, 'floorLocation': floor};

      await FirebaseFirestore.instance.collection('userReport').add(payload);

      // reset
      _platformCtrl.clear();
      _floorCtrl.clear();
      _detailsCtrl.clear();
      setState(() {
        _pickedImage = null;
        _buildingValue = null;
      });

      await AppMsg.reportSubmitted(context);
      if (mounted) setState(() => _serviceType = null); // back to chooser
    } catch (e) {
      await AppMsg.reportSubmitFailed(context);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final edge = (size.width * 0.05).clamp(16.0, 24.0);
    final labelFS = (size.width * 0.04).clamp(14.0, 16.0);
    final imgH = (size.height * 0.22).clamp(140.0, 220.0);
    final btnVPad = (size.height * 0.02).clamp(12.0, 18.0);

    return Stack(children: [
      Scaffold(
        backgroundColor: Colors.white,
        body: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(edge, edge * 2.2, edge, edge),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ======= CHOOSER =======
                  if (_serviceType == null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () => setState(() => _showHelp = true),
                          icon: const Icon(Icons.info_outline, size: 18),
                          label: const Text('Know about service types'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.black87,
                            backgroundColor: Colors.white,
                            side: const BorderSide(color: Colors.black12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Choose a service type for your report:',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700], fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),

                    LayoutBuilder(builder: (c, bc) {
                      final isWide = bc.maxWidth >= 420;
                      return GridView.count(
                        shrinkWrap: true,
                        crossAxisCount: isWide ? 2 : 1,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _ServiceCard(
                            title: svcFM,
                            desc: 'Repairs, cleanliness, lighting, aircon, plumbing, room fixtures, etc.',
                            onTap: () => setState(() => _serviceType = svcFM),
                          ),
                          _ServiceCard(
                            title: svcITSW,
                            desc: 'Issues with school web apps/portals, DCT Schoology, logins, errors.',
                            onTap: () => setState(() => _serviceType = svcITSW),
                          ),
                          _ServiceCard(
                            title: svcITHW,
                            desc: 'PCs, printers, projectors, network ports, cables, peripherals.',
                            onTap: () => setState(() => _serviceType = svcITHW),
                          ),
                        ],
                      );
                    }),
                    const SizedBox(height: 24),
                  ],

                  // ======= FORM =======
                  if (_serviceType != null) ...[
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _serviceType = null),
                        icon: const Icon(Icons.chevron_left, size: 18),
                        label: const Text('Change service type'),
                      ),
                    ),

                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black12),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Selected service type', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          Text(_serviceType!, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (_serviceType == svcITSW) ...[
                      _label('PLATFORM / SYSTEM NAME', labelFS),
                      _textField(controller: _platformCtrl, hint: 'e.g., LMS (Moodle), Student Portal'),
                      const SizedBox(height: 20),
                    ] else ...[
                      _label('BUILDING NAME', labelFS),
                      _buildingDropdown(), // <<< dropdown here
                      const SizedBox(height: 20),

                      _label('FLOOR / ROOM LOCATION', labelFS),
                      _textField(controller: _floorCtrl, hint: 'e.g., 3/F Room 305'),
                      const SizedBox(height: 20),
                    ],

                    _label('UPLOAD IMAGE', labelFS),
                    _imagePicker(imgH),
                    const SizedBox(height: 20),

                    _label('OTHER DETAILS', labelFS),
                    _textField(controller: _detailsCtrl, maxLines: 4),
                    const SizedBox(height: 30),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _submitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _brand,
                          padding: EdgeInsets.symmetric(vertical: btnVPad),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _submitting
                            ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('SUBMIT', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),

      if (_showHelp)
        _HelpSheet(
          onClose: () => setState(() => _showHelp = false),
          brand: _brand,
        ),

      if (_submitting)
        Positioned.fill(child: IgnorePointer(child: Container(color: Colors.black.withOpacity(0.4)))),
    ]);
  }

  // ---- Small UI helpers ----
  Widget _label(String text, double fs) =>
      Padding(padding: const EdgeInsets.only(left: 8, bottom: 4), child: Text(text, style: TextStyle(fontSize: fs, color: Colors.black)));

  Widget _textField({required TextEditingController controller, int maxLines = 1, String? hint}) {
    final size = MediaQuery.of(context).size;
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: (size.height * 0.017).clamp(12.0, 16.0)),
      ),
    );
  }

  // Building dropdown widget
  Widget _buildingDropdown() {
    return DropdownButtonFormField<String>(
      value: _buildingValue,
      isExpanded: true,
      items: _kBuildings
          .map((e) => DropdownMenuItem<String>(
        value: e['value'],
        child: Text(e['label']!),
      ))
          .toList(),
      onChanged: (v) => setState(() => _buildingValue = v),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _imagePicker(double imgH) {
    return GestureDetector(
      onTap: _pickedImage == null ? _chooseImage : null,
      onLongPress: _pickedImage != null ? _previewImage : null,
      child: Container(
        height: imgH,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Stack(children: [
          Positioned.fill(
            child: _pickedImage == null
                ? Center(child: Text('Tap to upload image', style: TextStyle(color: Colors.grey[500])))
                : ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(File(_pickedImage!.path), fit: BoxFit.cover),
            ),
          ),
          if (_pickedImage != null)
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: _removeImage,
                style: IconButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.all(8)),
                icon: const Icon(Icons.delete, color: Colors.white, size: 20),
              ),
            ),
          if (_pickedImage != null)
            Positioned(
              bottom: 8,
              left: 8,
              child: ElevatedButton.icon(
                onPressed: _chooseImage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black.withOpacity(0.55),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.photo_library, size: 18),
                label: const Text('Change'),
              ),
            ),
        ]),
      ),
    );
  }
}



// ====== Service card (web-style) with background watermark logo ======
class _ServiceCard extends StatelessWidget {
  final String title;
  final String desc;
  final VoidCallback onTap;
  const _ServiceCard({required this.title, required this.desc, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black54),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(children: [
          // background watermark (assets/dctLogo.png)
          Positioned.fill(
            child: Opacity(
              opacity: 0.5,
              child: Image.asset('assets/dctLogo.png', fit: BoxFit.contain),
            ),
          ),
          // slight white overlay for readability
          Positioned.fill(child: Container(color: Colors.white.withOpacity(0.7))),
          // foreground text
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(desc, style: const TextStyle(fontSize: 12, color: Colors.black87)),
            ],
          ),
        ]),
      ),
    );
  }
}

// ====== Help sheet (like your web modal) ======
class _HelpSheet extends StatelessWidget {
  final VoidCallback onClose;
  final Color brand;
  const _HelpSheet({required this.onClose, required this.brand});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Service type guide', style: TextStyle(fontWeight: FontWeight.w700)),
                IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
              ]),
              const SizedBox(height: 8),
              _section('Facilities and Maintenance', const [
                'Building concerns: cleanliness, leaks, lights, air-conditioning, plumbing.',
                'Rooms/fixtures: doors, windows, chairs, whiteboards, signage.',
                'Provide building and floor/room location and a photo.',
              ]),
              _section('IT Support Services - Software', const [
                'School platforms/portals (LMS, SIS, registrar/grades, library site).',
                'Account logins, page errors, slow pages, submission failures.',
                'Provide the platform/system name, a screenshot, and steps to reproduce.',
              ]),
              _section('IT Support Services - Hardware', const [
                'Devices & peripherals: PCs, printers, projectors, keyboards, network ports.',
                'Cables, connectivity, “no display,” paper jams, power issues.',
                'Provide building and floor/room location and a photo.',
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  static Widget _section(String title, List<String> tips) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        ...tips.map((t) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('•  '), Expanded(child: Text(t, style: const TextStyle(color: Colors.black87))),
        ])),
      ]),
    );
  }
}

// ----------------------------------------------------------------------
// Report Logs (unchanged except using AppMsg for confirms)
// ----------------------------------------------------------------------




// If you use a custom message helper like on your existing codebase
// import 'package:your_package/app_msg.dart';  // <-- keep your original import

// lib/ui/app_msg.dart (or keep in the same file where AppMsg lives)


/// Drop-in replacement for your old AppMsg.
/// All methods return a modal dialog (not a SnackBar).
class AppMsg {
  // ----- Public API (same call sites as before) -----
  static Future<void> success(BuildContext c, String title, {String? m}) =>
      _dialog(
        c,
        title: title,
        message: m ?? title,
        variant: _Variant.success,
      );

  static Future<void> error(BuildContext c, String title, {String? m}) =>
      _dialog(
        c,
        title: title,
        message: m ?? title,
        variant: _Variant.error,
      );

  static Future<void> incompleteForm(BuildContext c, {String? custom}) =>
      _dialog(
        c,
        title: 'Incomplete Form',
        message: custom ?? 'Please complete all required fields.',
        variant: _Variant.warning,
      );

  static Future<void> uploadFailed(BuildContext c) =>
      _dialog(
        c,
        title: 'Upload Failed',
        message: 'Please try again.',
        variant: _Variant.error,
      );

  static Future<void> reportSubmitted(BuildContext c) =>
      _dialog(
        c,
        title: 'Success',
        message: 'Report submitted successfully.',
        variant: _Variant.success,
      );

  static Future<void> reportSubmitFailed(BuildContext c) =>
      _dialog(
        c,
        title: 'Failed',
        message: 'Failed to submit the report.',
        variant: _Variant.error,
      );

  static Future<void> notSignedIn(BuildContext c) =>
      _dialog(
        c,
        title: 'Not signed in',
        message: 'Please log in again.',
        variant: _Variant.error,
      );

  // ----- Core dialog builder -----
  static Future<void> _dialog(
      BuildContext context, {
        required String title,
        required String message,
        _Variant variant = _Variant.info,
      }) async {
    final colors = _palette(Theme.of(context).brightness, variant);

    // Using root navigator helps if you're calling from a bottom sheet.
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      useRootNavigator: true,
      builder: (c) => AlertDialog(
        backgroundColor: colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _IconBadge(variant: variant, colors: colors),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: colors.title,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: colors.body),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 96,
              child: FilledButton(
                style: ButtonStyle(
                  backgroundColor: WidgetStatePropertyAll(colors.ctaBg),
                  foregroundColor: WidgetStatePropertyAll(colors.ctaFg),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                onPressed: () => Navigator.of(c, rootNavigator: true).pop(),
                child: const Text('OK'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----- Color palette & icon mapping -----
  static _Colors _palette(Brightness b, _Variant v) {
    final isDark = b == Brightness.dark;

    Color card = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color title = isDark ? Colors.white : const Color(0xFF1F1F1F);
    Color body  = isDark ? Colors.white70 : const Color(0xFF505050);

    switch (v) {
      case _Variant.success:
        return _Colors(
          card: card,
          title: title,
          body: body,
          ring: const Color(0xFF4CAF50),
          iconBg: const Color(0xFFE8F5E9),
          icon: const Color(0xFF2E7D32),
          ctaBg: const Color(0xFF4CAF50),
          ctaFg: Colors.white,
          iconData: Icons.check_circle,
        );
      case _Variant.warning:
        return _Colors(
          card: card,
          title: title,
          body: body,
          ring: const Color(0xFFFFB300),
          iconBg: const Color(0xFFFFF3E0),
          icon: const Color(0xFFEF6C00),
          ctaBg: const Color(0xFF6750A4), // purple-ish like your screenshot
          ctaFg: Colors.white,
          iconData: Icons.error_outline,
        );
      case _Variant.error:
        return _Colors(
          card: card,
          title: title,
          body: body,
          ring: const Color(0xFFE53935),
          iconBg: const Color(0xFFFFEBEE),
          icon: const Color(0xFFC62828),
          ctaBg: const Color(0xFFE53935),
          ctaFg: Colors.white,
          iconData: Icons.highlight_off,
        );
      case _Variant.info:
      default:
        return _Colors(
          card: card,
          title: title,
          body: body,
          ring: const Color(0xFF1E88E5),
          iconBg: const Color(0xFFE3F2FD),
          icon: const Color(0xFF1565C0),
          ctaBg: const Color(0xFF1E88E5),
          ctaFg: Colors.white,
          iconData: Icons.info_outline,
        );
    }
  }
}

enum _Variant { success, warning, error, info }

class _Colors {
  final Color card, title, body, ring, iconBg, icon, ctaBg, ctaFg;
  final IconData iconData;
  _Colors({
    required this.card,
    required this.title,
    required this.body,
    required this.ring,
    required this.iconBg,
    required this.icon,
    required this.ctaBg,
    required this.ctaFg,
    required this.iconData,
  });
}

class _IconBadge extends StatelessWidget {
  final _Variant variant;
  final _Colors colors;
  const _IconBadge({super.key, required this.variant, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: colors.iconBg,
        shape: BoxShape.circle,
        border: Border.all(color: colors.ring, width: 3),
      ),
      child: Center(
        child: Icon(colors.iconData, color: colors.icon, size: 32),
      ),
    );
  }
}



class ReportLogsPage extends StatefulWidget {
  const ReportLogsPage({super.key});

  @override
  State<ReportLogsPage> createState() => _ReportLogsPageState();
}

class _ReportLogsPageState extends State<ReportLogsPage> {
  // Accent to match your nav
  static const Color kAccent = Color(0xFFE91E63);

  String? _expandedId; // composite key "collection:id"

  // ---------- Cloudinary (fill with your creds) ----------
  Future<String?> _uploadToCloudinary(XFile file) async {
    try {
      final url = Uri.parse("https://api.cloudinary.com/v1_1/<your_cloud_name>/image/upload");
      final request = http.MultipartRequest("POST", url)
        ..fields['upload_preset'] = "<your_unsigned_preset>"
        ..files.add(await http.MultipartFile.fromPath('file', file.path));
      final resp = await request.send();
      final res = await http.Response.fromStream(resp);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return data["secure_url"] as String?;
      }
      debugPrint("Cloudinary upload failed: ${res.body}");
      return null;
    } catch (e) {
      debugPrint("Upload error: $e");
      return null;
    }
  }

  bool _loading = true;
  String? _error;

  // status filter (All | Pending | On Process | Resolved)
  String _statusFilter = 'All';

  // merged list from all collections
  final List<_ReportItem> _reports = [];

  // per-user hidden resolved IDs
  final Set<String> _hiddenResolvedIds = <String>{};

  // image picker (used in edit sheet)
  final ImagePicker _picker = ImagePicker();

  // current user id
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // realtime subs
  final List<StreamSubscription> _subs = [];
  bool _bootstrapped = false; // first data arrived?

  // -------------------- PAGINATION --------------------
  static const int _pageSize = 6;
  int _page = 1;

  int get _totalPages =>
      (_filtered.isEmpty) ? 1 : ((_filtered.length + _pageSize - 1) ~/ _pageSize);

  List<_ReportItem> get _pageItems {
    final start = (_page - 1) * _pageSize;
    return _filtered.skip(start).take(_pageSize).toList();
  }

  void _goToPage(int p) {
    final clamped = p.clamp(1, _totalPages);
    if (clamped != _page) {
      setState(() {
        _page = clamped as int;
        _expandedId = null; // collapse when page changes
      });
    }
  }

  List<Widget> _buildPageButtons() {
    final widgets = <Widget>[];
    final total = _totalPages;

    int start = (_page - 3).clamp(1, total);
    int end = (start + 6).clamp(1, total);
    if ((end - start) < 6) start = (end - 6).clamp(1, total);

    Widget pill(int p) {
      final selected = p == _page;
      return InkWell(
        onTap: selected ? null : () => _goToPage(p),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? kAccent : Colors.transparent,
            border: Border.all(color: Colors.black87, width: 1),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$p',
            style: TextStyle(
              color: selected ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    if (start > 1) {
      widgets.add(pill(1));
      if (start > 2) widgets.add(const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('…')));
    }

    for (int p = start; p <= end; p++) {
      widgets.add(pill(p));
    }

    if (end < total) {
      if (end < total - 1) widgets.add(const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('…')));
      widgets.add(pill(total));
    }

    return widgets;
  }
  // ----------------------------------------------------

  @override
  void initState() {
    super.initState();
    _startRealtime();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    super.dispose();
  }

  // ---------- REALTIME WIRING ----------
  Future<void> _startRealtime() async {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();

    setState(() {
      _loading = true;
      _error = null;
      _reports.clear();
      _hiddenResolvedIds.clear();
      _bootstrapped = false;
      _page = 1; // reset on reload
    });

    final uid = _uid;
    if (uid == null) {
      setState(() {
        _loading = false;
        _error = 'Not signed in. Please login again.';
      });
      return;
    }

    try {
      // Per-user hides for resolved
      _subs.add(
        FirebaseFirestore.instance
            .collection('userResolvedHides')
            .where('uid', isEqualTo: uid)
            .snapshots()
            .listen((qs) {
          for (final c in qs.docChanges) {
            final rid = (c.doc.data()?['reportId'] as String?) ?? '';
            if (rid.isEmpty) continue;
            if (c.type == DocumentChangeType.removed) {
              _hiddenResolvedIds.remove(rid);
            } else {
              _hiddenResolvedIds.add(rid);
            }
          }
          if (mounted) setState(() => _page = 1);
        }, onError: (_) {
          if (mounted) setState(() => _error = 'Live hides failed.');
        }),
      );

      StreamSubscription _listenCollection({
        required String collection,
        required String fallbackStatus,
      }) {
        return FirebaseFirestore.instance
            .collection(collection)
            .where('uid', isEqualTo: uid)
            .snapshots()
            .listen((qs) {
          for (final change in qs.docChanges) {
            _applyDocChange(
              change: change,
              collectionName: collection,
              fallbackStatus: fallbackStatus,
            );
          }
          if (!_bootstrapped) {
            _bootstrapped = true;
            if (mounted) setState(() => _loading = false);
          } else {
            if (mounted) setState(() {});
          }
        }, onError: (_) {
          if (mounted) setState(() => _error = 'Live updates failed.');
        });
      }

      _subs.add(_listenCollection(collection: 'userReport',      fallbackStatus: 'Pending'));
      _subs.add(_listenCollection(collection: 'onProcess',       fallbackStatus: 'On Process'));
      _subs.add(_listenCollection(collection: 'resolvedReports', fallbackStatus: 'Resolved'));
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Failed to start live updates.';
        });
      }
    }
  }

  void _applyDocChange({
    required DocumentChange<Map<String, dynamic>> change,
    required String collectionName,
    required String fallbackStatus,
  }) {
    final doc = change.doc;
    final id = doc.id;

    int findIndex() => _reports.indexWhere((e) => e.id == id && e.collection == collectionName);

    if (change.type == DocumentChangeType.removed) {
      final idx = findIndex();
      if (idx != -1) _reports.removeAt(idx);
    } else {
      final item = _ReportItem.fromDoc(
        doc,
        collectionName: collectionName,
        fallbackStatus: fallbackStatus,
      );
      final idx = findIndex();
      if (idx == -1) {
        _reports.add(item);
      } else {
        _reports[idx] = item;
      }
    }

    // newest first
    _reports.sort((a, b) => b.sortMillis.compareTo(a.sortMillis));
    _page = 1; // keep bounds sane when list changes
  }

  // Visible list = hide resolved items current user has hidden
  List<_ReportItem> get _visibleReports {
    if (_hiddenResolvedIds.isEmpty) return List<_ReportItem>.from(_reports);
    return _reports.where((r) {
      if (r.status.toLowerCase() != 'resolved') return true;
      return !_hiddenResolvedIds.contains(r.id);
    }).toList();
  }

  ({int all, int pending, int onproc, int resolved}) _counts() {
    int p = 0, o = 0, r = 0;
    for (final e in _visibleReports) {
      final s = e.status.toLowerCase();
      if (s == 'pending') p++;
      else if (s == 'on process') o++;
      else if (s == 'resolved') r++;
    }
    return (all: _visibleReports.length, pending: p, onproc: o, resolved: r);
  }

  List<_ReportItem> get _filtered {
    final list = _visibleReports;
    if (_statusFilter == 'All') return list;
    final wanted = _statusFilter.toLowerCase();
    return list.where((e) => e.status.toLowerCase() == wanted).toList();
  }

  // ---------- ACTION HANDLERS ----------
  void _previewImage(String imageUrl) {
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierColor: Colors.black87,
      builder: (_) => GestureDetector(
        onTap: () => Navigator.of(context, rootNavigator: true).pop(),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  gaplessPlayback: true, // helps with SurfaceView buffer churn
                ),
              ),
            ),
            Positioned(
              top: 24,
              right: 24,
              child: IconButton(
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Simple confirm (kept as dialog; AppMsg handles success/error/info) ---
  Future<bool> _showConfirm({
    required String title,
    required String message,
    String confirmText = 'OK',
    String cancelText = 'Cancel',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c, rootNavigator: true).pop(false),
            child: Text(cancelText),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(c, rootNavigator: true).pop(true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // --- Remove from my log (Resolved only) ---
  Future<void> _removeFromMyLog(_ReportItem r) async {
    if (_uid == null) {
      await AppMsg.notSignedIn(context);
      return;
    }
    final ok = await _showConfirm(
      title: 'Remove from your log?',
      message: 'This will hide this resolved report from your Reported Issues.',
      confirmText: 'Remove',
    );
    if (!ok) return;

    try {
      final hideId = '${_uid}-${r.id}';
      await FirebaseFirestore.instance.collection('userResolvedHides').doc(hideId).set({
        'uid': _uid,
        'reportId': r.id,
        'createdAt': FieldValue.serverTimestamp(),
      });
      setState(() {
        _hiddenResolvedIds.add(r.id);
      });
      await AppMsg.success(context, 'Removed', m: 'The report is removed from your log.');
    } catch (e) {
      await AppMsg.error(context, 'Error', m: 'Failed to remove the report.');
    }
  }

  // --- Approve resolution (reporter only) ---
  Future<void> _approveResolution(_ReportItem r) async {
    if (_uid != r.uid) {
      await AppMsg.error(context, 'Not allowed', m: 'Only the original reporter can approve.');
      return;
    }
    if ((r.userApprovalStatus ?? 'pending').toLowerCase() == 'approved') {
      await AppMsg.success(context, 'Already approved', m: 'This resolution is already approved.');
      return;
    }
    final ok = await _showConfirm(
      title: 'Confirm Approval',
      message: 'Confirm that the issue is resolved.',
      confirmText: 'Approve',
    );
    if (!ok) return;

    try {
      await FirebaseFirestore.instance.collection('resolvedReports').doc(r.id).set({
        'userApprovalStatus': 'approved',
        'userApprovalAt': FieldValue.serverTimestamp(),
        'userApprovalByUid': _uid,
        'userApprovalNotes': null,
      }, SetOptions(merge: true));
      await AppMsg.success(context, 'Approved', m: 'Thanks for confirming the fix.');
    } catch (e) {
      await AppMsg.error(context, 'Error', m: 'Could not approve the resolution.');
    }
  }

  // --- Decline resolution (reporter only) ---
  Future<void> _declineResolution(_ReportItem r) async {
    if (_uid != r.uid) {
      await AppMsg.error(context, 'Not allowed', m: 'Only the original reporter can decline.');
      return;
    }
    if ((r.userApprovalStatus ?? 'pending').toLowerCase() == 'declined') {
      await AppMsg.success(context, 'Already declined', m: 'This resolution is already declined.');
      return;
    }

    final notes = await _promptText(
      title: 'Decline Resolution',
      inputLabel: 'Tell us what is still wrong',
      hint: 'Optional notes...',
      confirmText: 'Decline',
    );
    if (notes == null) return;

    try {
      await FirebaseFirestore.instance.collection('resolvedReports').doc(r.id).set({
        'userApprovalStatus': 'declined',
        'userApprovalAt': FieldValue.serverTimestamp(),
        'userApprovalByUid': _uid,
        'userApprovalNotes': notes.isEmpty ? null : notes,
      }, SetOptions(merge: true));
      await AppMsg.success(context, 'Noted', m: 'Marked as not resolved. A staff member will review.');
    } catch (e) {
      await AppMsg.error(context, 'Error', m: 'Could not decline the resolution.');
    }
  }

  // --- Prompt text helper (kept minimal) ---
  Future<String?> _promptText({
    required String title,
    String inputLabel = 'Notes',
    String hint = '',
    String confirmText = 'OK',
    String cancelText = 'Cancel',
    int maxLines = 3,
  }) async {
    final ctl = TextEditingController();
    final value = await showDialog<String?>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(alignment: Alignment.centerLeft, child: Text(inputLabel, style: Theme.of(c).textTheme.labelMedium)),
            const SizedBox(height: 8),
            TextField(
              controller: ctl,
              maxLines: maxLines,
              decoration: InputDecoration(
                hintText: hint,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(c, rootNavigator: true).pop(null), child: Text(cancelText)),
          ElevatedButton(onPressed: () => Navigator.of(c, rootNavigator: true).pop(ctl.text.trim()), child: Text(confirmText)),
        ],
      ),
    );
    return value;
  }

  // --- FULL EDIT SHEET (restored) ---
  void _openEditSheet(_ReportItem r) {
    // controllers
    final bCtrl = TextEditingController(text: r.buildingName ?? '');
    final fCtrl = TextEditingController(text: r.floorLocation ?? '');
    final pCtrl = TextEditingController(text: r.platformName ?? r.platform ?? r.systemName ?? '');
    final dCtrl = TextEditingController(text: r.additionalDetails ?? '');

    const svcTypes = <String>[
      'Facilities and Maintenance',
      'IT Support Services - Hardware',
      'IT Support Services - Software',
    ];

    String _canon(String s) => s
        .replaceAll(RegExp(r'[\u2012-\u2015\u2212]'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();

    String _snapToOption(String? raw) {
      final c = _canon(raw ?? '');
      for (final opt in svcTypes) {
        if (_canon(opt) == c) return opt;
      }
      return '';
    }

    String svcType = _snapToOption(r.serviceType);
    String? currentImageUrl = r.imageUrl;
    XFile? newImageFile;
    bool saving = false;
    bool dirty = false;

    Future<void> _pickFromGallery(StateSetter setSheet) async {
      if (saving) return;
      final x = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (x == null) return;
      setSheet(() {
        newImageFile = x;
        dirty = true;
      });
    }

    Future<void> _pickFromCamera(StateSetter setSheet) async {
      if (saving) return;
      final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
      if (x == null) return;
      setSheet(() {
        newImageFile = x;
        dirty = true;
      });
    }

    String? _validate() {
      if (svcType.isEmpty) return 'Please choose a service type.';
      final isSW = svcType == 'IT Support Services - Software';
      final hasImg = (newImageFile != null) || ((currentImageUrl ?? '').isNotEmpty);
      if (!hasImg) return 'Please attach an image.';
      if (isSW) {
        if (pCtrl.text.trim().isEmpty) return 'Please enter the Platform / System Name.';
      } else {
        if (bCtrl.text.trim().isEmpty) return 'Please enter the Building Name.';
        if (fCtrl.text.trim().isEmpty) return 'Please enter the Floor / Room Location.';
      }
      return null;
    }

    Future<void> _save(StateSetter setSheet) async {
      if (saving) return;

      final err = _validate();
      if (err != null) {
        await AppMsg.incompleteForm(context, custom: err);
        return;
      }

      setSheet(() => saving = true);
      try {
        String finalImageUrl = currentImageUrl ?? '';
        if (newImageFile != null) {
          final uploaded = await _uploadToCloudinary(newImageFile!);
          if (uploaded == null || uploaded.isEmpty) {
            await AppMsg.uploadFailed(context);
            setSheet(() => saving = false);
            return;
          }
          finalImageUrl = uploaded;
        }

        final isSW = svcType == 'IT Support Services - Software';
        final payload = <String, dynamic>{
          'uid': _uid,
          'serviceType': svcType,
          'additionalDetails': dCtrl.text.trim(),
          'imageUrl': finalImageUrl,
          'lastEditedAt': FieldValue.serverTimestamp(),
          'platformName': isSW ? pCtrl.text.trim() : null,
          'buildingName': isSW ? null : bCtrl.text.trim(),
          'floorLocation': isSW ? null : fCtrl.text.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        };

        // Editable only in userReport
        await FirebaseFirestore.instance.collection('userReport').doc(r.id).set(
          payload,
          SetOptions(merge: true),
        );

        await AppMsg.success(context, 'Updated', m: 'Your report has been updated.');

        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).pop(); // close sheet
      } catch (e) {
        await AppMsg.error(context, 'Update failed', m: 'Please try again.');
      } finally {
        if (mounted) setSheet(() => saving = false);
      }
    }

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;
            final preview = newImageFile != null
                ? Image.file(
              File(newImageFile!.path),
              width: 100,
              height: 70,
              fit: BoxFit.cover,
            )
                : (currentImageUrl?.isNotEmpty == true
                ? Image.network(currentImageUrl!, width: 100, height: 70, fit: BoxFit.cover, gaplessPlayback: true)
                : Container(width: 100, height: 70, color: const Color(0xFF0A1936)));

            return Padding(
              padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 16 + bottomInset),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text('Edit Report', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Service type
                    const Text('Service Type', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: svcTypes.map((t) {
                        final selected = svcType == t;
                        return InkWell(
                          onTap: () => setSheet(() {
                            svcType = t;
                            dirty = true;
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              border: Border.all(color: selected ? Colors.black : Colors.grey.shade400),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Radio<String>(
                                value: t,
                                groupValue: svcType,
                                onChanged: (v) => setSheet(() {
                                  svcType = v ?? '';
                                  dirty = true;
                                }),
                                activeColor: Colors.black,
                              ),
                              Text(t, style: const TextStyle(fontSize: 12)),
                            ]),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 12),

                    // Conditional fields
                    if (svcType == 'IT Support Services - Software') ...[
                      const Text('Platform / System Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: pCtrl,
                        onChanged: (_) => setSheet(() => dirty = true),
                        decoration: _inputDecoration('e.g., LMS, Library System'),
                      ),
                    ] else ...[
                      const Text('Building Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: bCtrl,
                        onChanged: (_) => setSheet(() => dirty = true),
                        decoration: _inputDecoration('Enter building name'),
                      ),
                      const SizedBox(height: 10),
                      const Text('Floor / Room Location', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: fCtrl,
                        onChanged: (_) => setSheet(() => dirty = true),
                        decoration: _inputDecoration('Enter floor/room'),
                      ),
                    ],

                    const SizedBox(height: 12),

                    // Image picker
                    const Text('Image', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF0A1936),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.all(6),
                          child: ClipRRect(borderRadius: BorderRadius.circular(6), child: preview),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ElevatedButton(
                              onPressed: () => _pickFromGallery(setSheet),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black87,
                                elevation: 0,
                                side: const BorderSide(color: Colors.black12),
                              ),
                              child: const Text('Upload Photo'),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: () => _pickFromCamera(setSheet),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black87,
                                elevation: 0,
                                side: const BorderSide(color: Colors.black12),
                              ),
                              child: const Text('Take Photo'),
                            ),
                            if (newImageFile != null) ...[
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: () => setSheet(() {
                                  newImageFile = null;
                                  dirty = true;
                                }),
                                child: const Text('Remove new image'),
                              )
                            ]
                          ],
                        )
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Other details
                    const Text('Other Details', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: dCtrl,
                      maxLines: 3,
                      onChanged: (_) => setSheet(() => dirty = true),
                      decoration: _inputDecoration('Describe the issue...'),
                    ),

                    const SizedBox(height: 16),

                    // Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: (!dirty || saving) ? null : () => _save(setSheet),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0A1936),
                            foregroundColor: Colors.white,
                          ),
                          child: Text(saving ? 'Saving...' : 'Save Changes'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------- BUILD ----------
  @override
  Widget build(BuildContext context) {
    final counts = _counts();
    final size = MediaQuery.of(context).size;
    final edge = (size.width * 0.05).clamp(16.0, 24.0);

    // keep page within bounds if list shrinks or filter changes
    if (_page > _totalPages) _page = _totalPages;
    if (_page < 1) _page = 1;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('REPORTED ISSUES', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
          : Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Filter + counts
              Padding(
                padding: EdgeInsets.all(edge),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text('Filter by status:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: DropdownButton<String>(
                              isExpanded: true,
                              underline: const SizedBox(),
                              value: _statusFilter,
                              items: const ['All', 'Pending', 'On Process', 'Resolved']
                                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                                  .toList(),
                              onChanged: (v) => setState(() {
                                _statusFilter = v ?? 'All';
                                _page = 1;
                                _expandedId = null;
                              }),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _countChip('All: ${counts.all}'),
                        _countChip('Pending: ${counts.pending}'),
                        _countChip('On Process: ${counts.onproc}'),
                        _countChip('Resolved: ${counts.resolved}'),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(thickness: 2),

              // List (paged)
              Expanded(
                child: _filtered.isEmpty
                    ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.assignment_outlined, size: 60, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('No reports found for this status.', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                      const SizedBox(height: 8),
                      Text('Reports will appear here when submitted', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
                    ],
                  ),
                )
                    : ListView.builder(
                  padding: EdgeInsets.all(edge),
                  itemCount: _pageItems.length,
                  itemBuilder: (_, i) {
                    final r = _pageItems[i];
                    final rowKey = '${r.collection}:${r.id}';
                    final canEdit = r.status.toLowerCase() == 'pending' && r.collection == 'userReport';
                    return KeyedSubtree(
                      key: ValueKey(rowKey), // stable
                      child: _ReportTile(
                        item: r,
                        currentUid: _uid,
                        open: _expandedId == rowKey,
                        onToggle: () => setState(() {
                          _expandedId = (_expandedId == rowKey) ? null : rowKey;
                        }),
                        onPreview: r.imageUrl != null ? () => _previewImage(r.imageUrl!) : null,
                        onPreviewResolved: (r.resolvedImageUrl != null && r.resolvedImageUrl!.isNotEmpty)
                            ? () => _previewImage(r.resolvedImageUrl!)
                            : null,
                        onRemoveFromMyLog: r.status.toLowerCase() == 'resolved' ? () => _removeFromMyLog(r) : null,
                        onEdit: canEdit ? () => _openEditSheet(r) : null,
                        onApprove: r.status.toLowerCase() == 'resolved' ? () => _approveResolution(r) : null,
                        onDecline: r.status.toLowerCase() == 'resolved' ? () => _declineResolution(r) : null,
                      ),
                    );
                  },
                ),
              ),

              // Pagination bar
              if (_filtered.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(bottom: edge, left: edge, right: edge, top: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: _page > 1 ? () => _goToPage(_page - 1) : null,
                        child: const Text('Previous'),
                      ),
                      const SizedBox(width: 8),
                      Wrap(spacing: 6, children: _buildPageButtons()),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _page < _totalPages ? () => _goToPage(_page + 1) : null,
                        child: const Text('Next'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _countChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }

  static InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: Colors.grey[100],
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  );
}

// ---------- Models & tiles (unchanged from your version) ----------

class _ReportItem {
  final String id;
  final String collection;

  // Status: Pending | On Process | Resolved
  final String status;

  // Common fields
  final String? buildingName;
  final String? floorLocation;
  final String? serviceType;
  final String? platformName; // platformName / systemName / platform (web parity)
  final String? systemName;
  final String? platform;
  final String? additionalDetails;
  final String? imageUrl;

  // Ownership
  final String? uid;

  // Timestamps
  final Timestamp? serverTimeStamp;
  final Timestamp? processedAt;
  final Timestamp? resolvedAt;

  // Resolution meta
  final String? resolvedByName;
  final String? resolvedByDept;
  final String? resolutionNotes;
  final String? resolvedImageUrl;
  final bool? hiddenForAdmin;

  // User approval
  final String? userApprovalStatus; // 'pending' | 'approved' | 'declined'
  final String? userApprovalNotes;
  final String? userApprovalByUid;

  _ReportItem({
    required this.id,
    required this.collection,
    required this.status,
    this.buildingName,
    this.floorLocation,
    this.serviceType,
    this.platformName,
    this.systemName,
    this.platform,
    this.additionalDetails,
    this.imageUrl,
    this.uid,
    this.serverTimeStamp,
    this.processedAt,
    this.resolvedAt,
    this.resolvedByName,
    this.resolvedByDept,
    this.resolutionNotes,
    this.resolvedImageUrl,
    this.hiddenForAdmin,
    this.userApprovalStatus,
    this.userApprovalNotes,
    this.userApprovalByUid,
  });

  int get sortMillis =>
      (resolvedAt?.millisecondsSinceEpoch ??
          processedAt?.millisecondsSinceEpoch ??
          serverTimeStamp?.millisecondsSinceEpoch ??
          0);

  factory _ReportItem.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> d, {
        required String collectionName,
        required String fallbackStatus,
      }) {
    final data = d.data() ?? {};
    String status = (data['status'] as String?)?.trim() ?? fallbackStatus;
    status = {
      'on process': 'On Process',
      'resolved': 'Resolved',
      'pending': 'Pending'
    }[status.toLowerCase()] ??
        status;

    return _ReportItem(
      id: d.id,
      collection: collectionName,
      status: status,
      buildingName: data['buildingName'] as String?,
      floorLocation: data['floorLocation'] as String?,
      serviceType: data['serviceType'] as String?,
      platformName: data['platformName'] as String?,
      systemName: data['systemName'] as String?,
      platform: data['platform'] as String?,
      additionalDetails: data['additionalDetails'] as String?,
      imageUrl: data['imageUrl'] as String?,
      uid: data['uid'] as String?,
      serverTimeStamp: data['serverTimeStamp'] as Timestamp?,
      processedAt: data['processedAt'] as Timestamp?,
      resolvedAt: data['resolvedAt'] as Timestamp?,
      resolvedByName: data['resolvedByName'] as String?,
      resolvedByDept: data['resolvedByDept'] as String?,
      resolutionNotes: data['resolutionNotes'] as String?,
      resolvedImageUrl: data['resolvedImageUrl'] as String?,
      hiddenForAdmin: data['hiddenForAdmin'] as bool?,
      userApprovalStatus: (data['userApprovalStatus'] as String?) ?? 'pending',
      userApprovalNotes: data['userApprovalNotes'] as String?,
      userApprovalByUid: data['userApprovalByUid'] as String?,
    );
  }
}

class _ReportTile extends StatefulWidget {
  final _ReportItem item;
  final String? currentUid;

  // controlled expansion
  final bool open;
  final VoidCallback onToggle;

  final VoidCallback? onPreview; // original image
  final VoidCallback? onPreviewResolved; // resolution image
  final VoidCallback? onRemoveFromMyLog; // only for Resolved
  final VoidCallback? onDelete; // optional (not used)
  final VoidCallback? onEdit; // edit pending item
  final VoidCallback? onApprove; // user approves resolution
  final VoidCallback? onDecline; // user declines resolution

  const _ReportTile({
    required this.item,
    required this.open,
    required this.onToggle,
    this.currentUid,
    this.onPreview,
    this.onPreviewResolved,
    this.onRemoveFromMyLog,
    this.onDelete,
    this.onEdit,
    this.onApprove,
    this.onDecline,
    super.key,
  });

  @override
  State<_ReportTile> createState() => _ReportTileState();
}

class _ReportTileState extends State<_ReportTile> {
  String _fmtDate(Timestamp? ts) {
    if (ts == null) return '—';
    final d = ts.toDate();
    return '${_mfull(d.month)} ${d.day}, ${d.year}  ${_two(d.hour)}:${_two(d.minute)}';
  }

  static String _mfull(int m) => const [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ][m - 1];
  static String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final r = widget.item;
    final isResolved = r.status.toLowerCase() == 'resolved';
    final canEdit = widget.onEdit != null;

    final size = MediaQuery.of(context).size;
    final headerH = (size.height * 0.055).clamp(42.0, 56.0);
    final thumbW = (size.width * 0.28).clamp(90.0, 120.0);
    final thumbH = (thumbW * 0.7).clamp(64.0, 90.0);

    final approval = (r.userApprovalStatus ?? 'pending').toLowerCase();
    final isOwner = (widget.currentUid != null && widget.currentUid == r.uid);

    final Widget preview = (r.imageUrl?.isNotEmpty ?? false)
        ? GestureDetector(
      onTap: widget.onPreview,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          r.imageUrl!,
          width: thumbW,
          height: thumbH,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      ),
    )
        : Container(
      width: thumbW,
      height: thumbH,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: const Text('No image', style: TextStyle(fontSize: 10, color: Colors.black54)),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.transparent, width: 0),
        boxShadow: const [
          BoxShadow(
            blurRadius: 8,
            offset: Offset(0, 20),
            color: Color(0x14000000),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header toggles via parent
          InkWell(
            onTap: widget.onToggle,
            child: Container(
              height: headerH,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _StatusChip(status: r.status, approval: approval),
                  Row(
                    children: [
                      Text(
                        widget.open ? 'Hide Details' : 'View Details',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        duration: const Duration(milliseconds: 200),
                        turns: widget.open ? 0.5 : 0.0,
                        child: const Icon(Icons.keyboard_arrow_down, color: Colors.black, size: 18),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),

          // Details
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: _details(context, r, isResolved, canEdit, isOwner, approval, size, preview, thumbW, thumbH),
            crossFadeState: widget.open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
          ),
        ],
      ),
    );
  }

  Widget _details(
      BuildContext context,
      _ReportItem r,
      bool isResolved,
      bool canEdit,
      bool isOwner,
      String approval,
      Size size,
      Widget preview,
      double thumbW,
      double thumbH,
      ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(11)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // meta + original thumb
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _kv('Building Name', r.buildingName),
                    _kv('Floor Location', r.floorLocation),
                    _kv('Service Type', r.serviceType),
                    _kv('Platform / System Name', r.platformName ?? r.systemName ?? r.platform),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                padding: const EdgeInsets.all(6),
                child: preview,
              ),
            ],
          ),

          const SizedBox(height: 12),
          const Text(
            'Report Details',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Other Details: ', style: TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: r.additionalDetails ?? '—'),
              ],
            ),
            style: const TextStyle(fontSize: 14, color: Colors.black),
          ),

          if (isResolved) ...[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 6),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    children: [
                      Text(
                        r.resolvedByName?.isNotEmpty == true ? r.resolvedByName! : '—',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                      const Text('•', style: TextStyle(color: Colors.grey)),
                      Text(r.resolvedByDept?.isNotEmpty == true ? r.resolvedByDept! : '—',
                          style: const TextStyle(fontSize: 12, color: Colors.black87)),
                      const Text('•', style: TextStyle(color: Colors.grey)),
                      Text(_fmtDate(r.resolvedAt), style: const TextStyle(fontSize: 12, color: Colors.black87)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  padding: const EdgeInsets.all(6),
                  child: (r.resolvedImageUrl?.isNotEmpty ?? false)
                      ? GestureDetector(
                    onTap: widget.onPreviewResolved,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        r.resolvedImageUrl!,
                        width: thumbW,
                        height: thumbH,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
                    ),
                  )
                      : Container(
                    width: thumbW,
                    height: thumbH,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: const Text('No image', style: TextStyle(fontSize: 10, color: Colors.black54)),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Resolution Summary: ', style: TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(text: r.resolutionNotes ?? '—'),
                ],
              ),
              style: const TextStyle(fontSize: 14, color: Colors.black),
            ),

            if (isOwner && approval == 'pending') ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: widget.onApprove,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Approve — Issue Resolved'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: widget.onDecline,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Decline — Not Resolved'),
                ),
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 12),
            ],

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: widget.onRemoveFromMyLog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: EdgeInsets.symmetric(vertical: (size.height * 0.015).clamp(10.0, 14.0)),
                ),
                child: const Text('Remove from My Log'),
              ),
            ),
          ],

          if (canEdit) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: widget.onEdit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black87,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Edit Report'),
              ),
            ),
          ],

          if (!isResolved && widget.onDelete != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: widget.onDelete,
                child: const Text('Delete (admin)'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _kv(String k, String? v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        '$k: ${v?.isNotEmpty == true ? v : '—'}',
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.black,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  final String approval; // 'pending' | 'approved' | 'declined'
  const _StatusChip({required this.status, this.approval = 'pending'});

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    String text = status;
    Color bg;

    if (s == 'resolved') {
      if (approval == 'approved') {
        text = 'Resolved (Approved)';
        bg = Colors.green;
      } else if (approval == 'declined') {
        text = 'Not Resolved';
        bg = Colors.red;
      } else {
        text = 'Resolved (Pending Your Approval)';
        bg = Colors.green;
      }
    } else if (s == 'on process') {
      bg = Colors.orange;
    } else if (s == 'pending') {
      bg = Colors.grey;
    } else {
      bg = Colors.blueGrey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
    );
  }
}



// ---------- Models & tiles ----------


class _LabeledField extends StatelessWidget {
  final String label;
  final Widget child;
  const _LabeledField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}



// ----------------------------------------------------------------------
// Profile
// ----------------------------------------------------------------------

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final Color pink = const Color(0xFFE91E63);

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Confirm Logout',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseAuth.instance.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('uid');
      await prefs.remove('role');
      if (!mounted) return;

      // Show auto-closing dialog for 2 seconds
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.check_circle, color: Colors.green, size: 48),
              SizedBox(height: 12),
              Text(
                'Logged out',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'You have been signed out successfully.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );

      // Wait 2 seconds then close dialog and go to login
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      Navigator.of(context).pop(); // close the dialog
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
    } catch (e) {
      if (!mounted) return;
      await AppMsg.error(context, 'Logout failed', m: e.toString());
    }
  }





  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    final size = MediaQuery.of(context).size;
    final h = size.height;
    final double avatarRadius = (h * 0.08).clamp(44.0, 56.0);
    final double gapNameToRole = (h * 0.005).clamp(4.0, 8.0);
    final double gapRoleToDept = (h * 0.02).clamp(12.0, 18.0);
    final double optionVPad = (h * 0.015).clamp(10.0, 14.0);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'PROFILE',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: uid == null
          ? const Center(child: Text('Not signed in'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
        builder: (context, snap) {
          final loading = snap.connectionState == ConnectionState.waiting;
          final data = snap.data?.data() ?? {};
          final name = (data['name'] as String?)?.trim() ?? '';
          final role = (data['role'] as String?)?.trim() ?? '';
          final department = (data['department'] as String?)?.trim() ?? '';
          final photoUrl = (data['photoUrl'] as String?)?.trim() ?? '';
          final initials = (name.isNotEmpty ? name[0] : 'U').toUpperCase();

          return Stack(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        // Header (same layout/colors)
                        CircleAvatar(
                          radius: avatarRadius,
                          backgroundColor: pink,
                          child: ClipOval(
                            child: photoUrl.isNotEmpty
                                ? Image.network(
                              photoUrl,
                              width: avatarRadius * 2,
                              height: avatarRadius * 2,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Center(
                                child: Text(
                                  initials,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 28,
                                  ),
                                ),
                              ),
                            )
                                : Center(
                              child: Text(
                                initials,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 28,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          name.isNotEmpty ? name : '—',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: gapNameToRole),
                        Text(
                          role.isNotEmpty ? role : '—',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),

                        SizedBox(height: gapRoleToDept),

                        Text(
                          department.isNotEmpty ? department : '—',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 24),

                        _buildProfileOption(
                          icon: Icons.edit,
                          title: 'Edit Profile',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const EditProfilePage(),
                              ),
                            );
                          },
                          vPad: optionVPad,
                        ),
                        const Divider(),
                        _buildProfileOption(
                          icon: Icons.vpn_key_rounded,
                          title: 'Change Password',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const ChangePasswordPage(),
                              ),
                            );
                          },
                          vPad: optionVPad,
                        ),
                        const Divider(),
                        _buildProfileOption(
                          icon: Icons.logout,
                          title: 'Logout',
                          onTap: _logout,
                          isLogout: true,
                          vPad: optionVPad,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              if (loading)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.05),
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProfileOption({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isLogout = false,
    double vPad = 12.0,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      visualDensity: const VisualDensity(horizontal: 0, vertical: -1),
      leading: Icon(
        icon,
        color: isLogout ? Colors.red : const Color(0xFFE91E63),
      ),
      title: Padding(
        padding: EdgeInsets.symmetric(vertical: vPad * 0.2),
        child: Text(
          title,
          style: TextStyle(
            color: isLogout ? Colors.red : Colors.black,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
