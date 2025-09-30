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
import 'report_status_watcher.dart';
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
                      child: Text(
                        "Note: For complex issues, please contact:\n"
                            "- CSD (for plumbing)\n"
                            "- Maintenance (for electrical/AC)\n"
                            "- Facilities (for furniture/doors)",
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
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

  // Form state
  final _buildingCtrl = TextEditingController();
  final _floorCtrl = TextEditingController();
  final _detailsCtrl = TextEditingController();

  String? _serviceType; // 'Facilities and Maintenance' | 'IT Support Services'
  final _serviceTypes = const [
    'Facilities and Maintenance',
    'IT Support Services - Software',
    'IT Support Services - Hardware',
  ];
  // Image state
  final _picker = ImagePicker();
  XFile? _pickedImage;

  // UI state
  bool _submitting = false;

  // Colors (kept consistent with your theme)
  final Color _pink = const Color(0xFFE91E63);

  @override
  void dispose() {
    _buildingCtrl.dispose();
    _floorCtrl.dispose();
    _detailsCtrl.dispose();
    super.dispose();
  }

  // ---- Image pickers
  Future<void> _chooseImage() async {
    if (_submitting) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Pick from gallery'),
                onTap: () async {
                  Navigator.pop(context);
                  final file = await _picker.pickImage(
                    source: ImageSource.gallery,
                    imageQuality: 85,
                    maxWidth: 1600,
                  );
                  if (file != null && mounted) {
                    setState(() => _pickedImage = file);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Take a photo'),
                onTap: () async {
                  Navigator.pop(context);
                  final file = await _picker.pickImage(
                    source: ImageSource.camera,
                    imageQuality: 85,
                    maxWidth: 1600,
                  );
                  if (file != null && mounted) {
                    setState(() => _pickedImage = file);
                  }
                },
              ),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
  }

  void _removeImage() {
    if (_submitting) return;
    setState(() => _pickedImage = null);
  }

  // Hold-to-preview
  void _previewImage() {
    if (_pickedImage == null) return;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.file(File(_pickedImage!.path)),
              ),
            ),
            Positioned(
              top: 24,
              right: 24,
              child: IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                ),
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Cloudinary upload (same as your web app)
  Future<String?> _uploadToCloudinary(XFile file) async {
    final uri = Uri.parse('https://api.cloudinary.com/v1_1/dsycysb0e/image/upload');
    final req = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = 'supportlink'
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          await file.readAsBytes(),
          filename: file.name,
        ),
      );

    final streamResp = await req.send();
    final resp = await http.Response.fromStream(streamResp);
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return data['secure_url'] as String?;
    } else {
      debugPrint('Cloudinary upload failed: ${resp.statusCode} ${resp.body}');
      return null;
    }
  }

  // ---- Submit
  Future<void> _submit() async {
    final building = _buildingCtrl.text.trim();
    final floor = _floorCtrl.text.trim();
    final details = _detailsCtrl.text.trim();
    final service = _serviceType;
    final image = _pickedImage;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      await AppMsg.notSignedIn(context);
      return;
    }

    if (building.isEmpty || floor.isEmpty || service == null || image == null) {
      // Auto-closing error dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.error, color: Colors.red, size: 48),
              SizedBox(height: 12),
              Text(
                'Incomplete Form',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Please complete all required fields and select an image.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.of(context).pop(); // close dialog
      return;
    }

    setState(() => _submitting = true);
    try {
      // 1) Upload image first
      final imageUrl = await _uploadToCloudinary(image);
      if (imageUrl == null) {
        await AppMsg.uploadFailed(context);
        return;
      }

      // 2) Create Firestore doc
      await FirebaseFirestore.instance.collection('userReport').add({
        'uid': uid,
        'serverTimeStamp': FieldValue.serverTimestamp(),
        'buildingName': building,
        'floorLocation': floor,
        'serviceType': service,
        'additionalDetails': details,
        'imageUrl': imageUrl,
        'status': 'Pending',
      });

      // 3) Reset fields
      _buildingCtrl.clear();
      _floorCtrl.clear();
      _detailsCtrl.clear();
      setState(() {
        _serviceType = null;
        _pickedImage = null;
      });

      // ✅ Success modal (auto-close after 2s)
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
                'Submitted',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Your report has been submitted successfully.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );

      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.of(context).pop(); // close success dialog
    } catch (e) {
      debugPrint('Error submitting report: $e');
      await AppMsg.reportSubmitFailed(context);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final edge = (size.width * 0.05).clamp(16.0, 24.0);
    final labelFS = (size.width * 0.04).clamp(14.0, 16.0);
    final imgH = (size.height * 0.22).clamp(140.0, 220.0);
    final btnVPad = (size.height * 0.02).clamp(12.0, 18.0);

    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.white,
          body: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(edge, edge * 3, edge, edge),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // BUILDING NAME
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0, bottom: 4.0),
                      child: Text('BUILDING NAME',
                          style: TextStyle(color: Colors.black, fontSize: labelFS)),
                    ),
                    _buildTextField(controller: _buildingCtrl),
                    const SizedBox(height: 20),

                    // FLOOR LOCATION
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0, bottom: 4.0),
                      child: Text('FLOOR LOCATION',
                          style: TextStyle(color: Colors.black, fontSize: labelFS)),
                    ),
                    _buildTextField(controller: _floorCtrl),
                    const SizedBox(height: 20),

                    // SERVICE TYPE
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0, bottom: 4.0),
                      child: Text('SERVICE TYPE',
                          style: TextStyle(color: Colors.black, fontSize: labelFS)),
                    ),
                    _buildServiceTypeDropdown(),
                    const SizedBox(height: 20),

                    // UPLOAD IMAGE
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0, bottom: 4.0),
                      child: Text('UPLOAD IMAGE',
                          style: TextStyle(color: Colors.black, fontSize: labelFS)),
                    ),
                    _buildImagePicker(imgH: imgH),
                    const SizedBox(height: 20),

                    // OTHER DETAILS
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0, bottom: 4.0),
                      child: Text('OTHER DETAILS',
                          style: TextStyle(color: Colors.black, fontSize: labelFS)),
                    ),
                    _buildTextField(controller: _detailsCtrl, maxLines: 4),
                    const SizedBox(height: 30),

                    // SUBMIT
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _submitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:  const Color(0xFFEB58B5),
                          padding: EdgeInsets.symmetric(vertical: btnVPad),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _submitting
                            ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                            : const Text(
                          'SUBMIT',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Loading overlay
        if (_submitting)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: Colors.black.withOpacity(0.4),
              ),
            ),
          ),
      ],
    );
  }

  // ---- UI helpers
  Widget _buildTextField({required TextEditingController controller, int maxLines = 1}) {
    final size = MediaQuery.of(context).size;
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: (size.height * 0.017).clamp(12.0, 16.0),
        ),
      ),
    );
  }

  Widget _buildServiceTypeDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonFormField<String>(
        value: _serviceType,
        decoration: InputDecoration(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          filled: true,
          fillColor: Colors.transparent,
        ),
        hint: const Text('Select service type'),
        items: _serviceTypes.map((s) => DropdownMenuItem<String>(value: s, child: Text(s))).toList(),
        onChanged: (v) => setState(() => _serviceType = v),
      ),
    );
  }

  Widget _buildImagePicker({required double imgH}) {
    return GestureDetector(
      onTap: _pickedImage == null ? _chooseImage : null,
      onLongPress: _pickedImage != null ? _previewImage : null, // hold-to-preview
      child: Container(
        height: imgH,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Stack(
          children: [
            // Placeholder or image
            Positioned.fill(
              child: _pickedImage == null
                  ? Center(
                child: Text(
                  'Tap to upload image',
                  style: TextStyle(color: Colors.grey[500]),
                ),
              )
                  : ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(_pickedImage!.path),
                  fit: BoxFit.cover,
                ),
              ),
            ),

            // Remove button
            if (_pickedImage != null)
              Positioned(
                top: 8,
                right: 8,
                child: Row(
                  children: [
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: _removeImage,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        padding: const EdgeInsets.all(8),
                      ),
                      icon: const Icon(Icons.delete, color: Colors.white, size: 20),
                    ),
                  ],
                ),
              ),

            // Pick button (if image exists)
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.photo_library, size: 18),
                  label: const Text('Change'),
                ),
              ),
          ],
        ),
      ),
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
  String? _expandedId; // only one open at a time

  // ---------- Cloudinary uploader (called on SAVE only when a new photo was picked) ----------
  Future<String?> _uploadToCloudinary(XFile file) async {
    try {
      // TODO: replace <your_cloud_name> and <your_unsigned_preset> if needed
      final url = Uri.parse("https://api.cloudinary.com/v1_1/<your_cloud_name>/image/upload");
      final request = http.MultipartRequest("POST", url)
        ..fields['upload_preset'] = "<your_unsigned_preset>"
        ..files.add(await http.MultipartFile.fromPath('file', file.path));

      final response = await request.send();
      final res = await http.Response.fromStream(response);

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return data["secure_url"] as String?;
      } else {
        debugPrint("Cloudinary upload failed: ${res.body}");
        return null;
      }
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

  // image picker
  final ImagePicker _picker = ImagePicker();

  // current user id
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // realtime subs
  final List<StreamSubscription> _subs = [];
  bool _bootstrapped = false; // first data arrived?

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
          if (mounted) setState(() {});
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

      _subs.add(_listenCollection(collection: 'userReport', fallbackStatus: 'Pending'));
      _subs.add(_listenCollection(collection: 'onProcess', fallbackStatus: 'On Process'));
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
      barrierColor: Colors.black87,
      builder: (_) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.network(imageUrl, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 24,
              right: 24,
              child: IconButton(
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Dialog helpers (place inside your State class) ---
  Future<void> _showInfo(BuildContext context, String title, String message) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<bool> _showConfirm(
      BuildContext context, {
        required String title,
        required String message,
        String confirmText = 'OK',
        String cancelText = 'Cancel',
      }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: Text(cancelText)),
          ElevatedButton(onPressed: () => Navigator.of(c).pop(true), child: Text(confirmText)),
        ],
      ),
    );
    return result ?? false;
  }

  Future<String?> _promptText(
      BuildContext context, {
        required String title,
        String inputLabel = 'Notes',
        String hint = '',
        String confirmText = 'OK',
        String cancelText = 'Cancel',
        int maxLines = 3,
      }) async {
    final ctl = TextEditingController();
    return showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(inputLabel, style: Theme.of(c).textTheme.labelMedium),
            ),
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
          TextButton(onPressed: () => Navigator.of(c).pop(null), child: Text(cancelText)),
          ElevatedButton(onPressed: () => Navigator.of(c).pop(ctl.text.trim()), child: Text(confirmText)),
        ],
      ),
    );
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

// --- Your fixed methods ---
  Future<void> _removeFromMyLog(_ReportItem r) async {
    if (_uid == null) return;

    // 1) Confirm first
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove from your log?'),
        content: const Text(
          'This will remove this report from your Reported Issues on your device. '
              'You can still find it in Records if needed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      // 2) Persist the hide
      await FirebaseFirestore.instance
          .collection('userResolvedHides')
          .doc('$_uid-${r.id}')
          .set({
        'uid': _uid,
        'reportId': r.id,
        'at': FieldValue.serverTimestamp(),
      });

      // 3) Immediate local hide
      if (mounted) {
        setState(() {
          _hiddenResolvedIds.add(r.id);
        });
      }

      if (!mounted) return;

      // 4) Success modal (auto-close after 2s)
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
                'Removed',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'The report is no longer in your Reported Issues.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.of(context).pop(); // close success dialog
    } catch (e) {
      if (!mounted) return;

      // Error modal (auto-close after 2s)
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.error, color: Colors.red, size: 48),
              SizedBox(height: 12),
              Text(
                'Failed',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Could not remove the report. Please try again.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.of(context).pop(); // close error dialog
    }
  }


  Future<void> _approveResolution(_ReportItem r) async {
    if (_uid != r.uid) {
      await _showInfo(context, 'Not allowed', 'Only the original reporter can approve.');
      return;
    }
    if ((r.userApprovalStatus ?? 'pending').toLowerCase() == 'approved') {
      await _showInfo(context, 'Already approved', 'This resolution is already approved.');
      return;
    }

    final ok = await _showConfirm(
      context,
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

      if (!mounted) return;

      // Success modal (auto-closes after 2s)
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
              Text('Approved', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Thanks for confirming the fix.', textAlign: TextAlign.center),
            ],
          ),
        ),
      );

      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      Navigator.of(context).pop(); // close success dialog
    } catch (e) {
      if (!mounted) return;
      await AppMsg.error(context, 'Error', m: 'Could not approve the resolution.');
    }
  }

  Future<void> _declineResolution(_ReportItem r) async {
    if (_uid != r.uid) {
      await _showInfo(context, 'Not allowed', 'Only the original reporter can decline.');
      return;
    }
    if ((r.userApprovalStatus ?? 'pending').toLowerCase() == 'declined') {
      await _showInfo(context, 'Already declined', 'This resolution is already declined.');
      return;
    }

    final notes = await _promptText(
      context,
      title: 'Decline Resolution',
      inputLabel: 'Tell us what is still wrong',
      hint: 'Optional notes...',
      confirmText: 'Decline',
      maxLines: 3,
    );
    if (notes == null) return; // cancelled

    try {
      await FirebaseFirestore.instance.collection('resolvedReports').doc(r.id).set({
        'userApprovalStatus': 'declined',
        'userApprovalAt': FieldValue.serverTimestamp(),
        'userApprovalByUid': _uid,
        'userApprovalNotes': notes.isEmpty ? null : notes,
      }, SetOptions(merge: true));

      if (!mounted) return;

      // Success modal (auto-closes after 2s)
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
              Text('Declined', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('We noted your feedback. A staff member will review.', textAlign: TextAlign.center),
            ],
          ),
        ),
      );

      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      Navigator.of(context).pop(); // close success dialog
    } catch (e) {
      if (!mounted) return;
      await AppMsg.error(context, 'Error', m: 'Could not decline the resolution.');
    }
  }



  // ---------- EDIT SHEET (mirrors your web UX) ----------
  // ---------- EDIT SHEET (mirrors your web UX) ----------
  void _openEditSheet(_ReportItem r) {
    // controllers
    final bCtrl = TextEditingController(text: r.buildingName ?? '');
    final fCtrl = TextEditingController(text: r.floorLocation ?? '');
    final pCtrl = TextEditingController(text: r.platformName ?? r.platform ?? r.systemName ?? '');
    final dCtrl = TextEditingController(text: r.additionalDetails ?? '');

    // service types (same as web)
    // service types (same as web)
    const svcTypes = <String>[
      'Facilities and Maintenance',
      'IT Support Services - Hardware',
      'IT Support Services - Software',
    ];

// Canonicalize: lower-case, normalize dashes/whitespace
    String _canon(String s) {
      return s
          .replaceAll(RegExp(r'[\u2012-\u2015\u2212]'), '-') // any unicode dash -> '-'
          .replaceAll(RegExp(r'\s+'), ' ')                   // collapse spaces
          .trim()
          .toLowerCase();
    }

// Snap an arbitrary incoming string to a known option (or '' if no match)
    String _snapToOption(String? raw) {
      final c = _canon(raw ?? '');
      for (final opt in svcTypes) {
        if (_canon(opt) == c) return opt; // return the exact label from svcTypes
      }
      return ''; // none matched
    }

// Use snapped option as the initial group value
    String svcType = _snapToOption(r.serviceType);





    String? currentImageUrl = r.imageUrl; // existing image in DB
    XFile? newImageFile; // newly chosen; upload on SAVE
    bool saving = false;

    // NEW: track if anything changed
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
        // Upload ONLY if a new file was chosen; otherwise keep currentImageUrl
        String finalImageUrl = currentImageUrl ?? '';
        if (newImageFile != null) {
          final uploaded = await _uploadToCloudinary(newImageFile!);
          if (uploaded == null || uploaded.isEmpty) {
            await AppMsg.error(context, 'Upload failed', m: 'Could not upload the image. Try again.');
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
          // normalize fields like web
          'platformName': isSW ? pCtrl.text.trim() : null,
          'buildingName': isSW ? null : bCtrl.text.trim(),
          'floorLocation': isSW ? null : fCtrl.text.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        };

        // Only editable if still in userReport (same rule as web)
        await FirebaseFirestore.instance.collection('userReport').doc(r.id).set(
          payload,
          SetOptions(merge: true),
        );

        if (!mounted) return;

        // Auto-closing success dialog (2s)
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
                  'Updated',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'Your report has been updated.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );

        // Wait 2 seconds → close dialog → close sheet
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        Navigator.of(context).pop(); // close success dialog
        Navigator.pop(context);      // close bottom sheet
      } catch (e) {
        if (!mounted) return;
        await AppMsg.error(context, 'Update failed', m: e.toString());
      } finally {
        if (mounted) setSheet(() => saving = false);
      }
    }

    showModalBottomSheet(
      context: context,
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
                ? Image.network(currentImageUrl!, width: 100, height: 70, fit: BoxFit.cover)
                : Container(
              width: 100,
              height: 70,
              color: const Color(0xFF0A1936),
            ));

            // Hook up change listeners once (to set dirty when user types)
            void _attachDirtyListeners() {
              bCtrl.removeListener(() {});
              fCtrl.removeListener(() {});
              pCtrl.removeListener(() {});
              dCtrl.removeListener(() {});
            }

            // Instead of listeners, use onChanged on TextFields below (simpler/clearer)

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
                          child: Text('Edit Report',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                        IconButton(
                          onPressed: saving ? null : () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Service type (radio like web, 3 options)
                    const Text('Service Type', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: svcTypes.map((t) {
                        final selected = svcType == t; // exact, because we snapped svcType
                        return InkWell(
                          onTap: saving ? null : () => setSheet(() => svcType = t),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              border: Border.all(color: selected ? Colors.black : Colors.grey.shade400),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Radio<String>(
                                value: t,
                                groupValue: svcType, // exact match now
                                onChanged: saving ? null : (v) => setSheet(() => svcType = v ?? ''),
                                activeColor: Colors.black,
                              ),
                              Text(t, style: const TextStyle(fontSize: 12)),
                            ]),
                          ),
                        );
                      }).toList(),
                    ),


                    const SizedBox(height: 12),

                    // Conditional fields (like web)
                    if (svcType == 'IT Support Services - Software') ...[
                      const Text('Platform / System Name',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: pCtrl,
                        onChanged: (_) => setSheet(() => dirty = true),
                        decoration: _inputDecoration('e.g., LMS, Library System'),
                      ),
                    ] else ...[
                      const Text('Building Name',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: bCtrl,
                        onChanged: (_) => setSheet(() => dirty = true),
                        decoration: _inputDecoration('Enter building name'),
                      ),
                      const SizedBox(height: 10),
                      const Text('Floor / Room Location',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: fCtrl,
                        onChanged: (_) => setSheet(() => dirty = true),
                        decoration: _inputDecoration('Enter floor/room'),
                      ),
                    ],

                    const SizedBox(height: 12),

                    // Image picker (Upload Photo / Take Photo) + preview like web
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
                              onPressed: saving ? null : () => _pickFromGallery(setSheet),
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
                              onPressed: saving ? null : () => _pickFromCamera(setSheet),
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
                                onPressed: saving
                                    ? null
                                    : () => setSheet(() {
                                  newImageFile = null;
                                  dirty = true; // mark change
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

                    // Actions (align right like web)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: saving ? null : () => Navigator.pop(context),
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

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'REPORTED ISSUES',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        // actions: [   <--- remove this block
        //   IconButton(
        //     tooltip: 'Reconnect live',
        //     onPressed: _startRealtime,
        //     icon: const Icon(Icons.wifi, color: Colors.black),
        //   ),
        // ],
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
                        const Text(
                          'Filter by status:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: DropdownButton<String>(
                              isExpanded: true,
                              underline: const SizedBox(),
                              value: _statusFilter,
                              items: const ['All', 'Pending', 'On Process', 'Resolved']
                                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                                  .toList(),
                              onChanged: (v) => setState(() => _statusFilter = v ?? 'All'),
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

              // List
              Expanded(
                child: _filtered.isEmpty
                    ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.assignment_outlined, size: 60, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('No reports found for this status.',
                          style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                      const SizedBox(height: 8),
                      Text('Reports will appear here when submitted',
                          style: TextStyle(color: Colors.grey[500], fontSize: 14)),
                    ],
                  ),
                )
                    : ListView.builder(
                  padding: EdgeInsets.all(edge),
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) {
                    final r = _filtered[i];
                    final canEdit =
                        r.status.toLowerCase() == 'pending' && r.collection == 'userReport';
                    return _ReportTile(
                      item: r,
                      currentUid: _uid,
                      open: _expandedId == r.id,                             // NEW
                      onToggle: () => setState(() {                         // NEW
                        _expandedId = (_expandedId == r.id) ? null : r.id;  // toggle; ensure only one open
                      }),

                      onPreview: r.imageUrl != null ? () => _previewImage(r.imageUrl!) : null,
                      onPreviewResolved: (r.resolvedImageUrl != null && r.resolvedImageUrl!.isNotEmpty)
                          ? () => _previewImage(r.resolvedImageUrl!)
                          : null,
                      onRemoveFromMyLog: r.status.toLowerCase() == 'resolved'
                          ? () => _removeFromMyLog(r)
                          : null,
                      onEdit: (r.status.toLowerCase() == 'pending' && r.collection == 'userReport')
                          ? () => _openEditSheet(r)
                          : null,
                      onApprove: r.status.toLowerCase() == 'resolved' ? () => _approveResolution(r) : null,
                      onDecline: r.status.toLowerCase() == 'resolved' ? () => _declineResolution(r) : null,
                    );

                  },
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

// ---------- Models & tiles ----------

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

  // NEW: controlled expansion
  final bool open;
  final VoidCallback onToggle;

  final VoidCallback? onPreview;           // original image
  final VoidCallback? onPreviewResolved;   // resolution image
  final VoidCallback? onRemoveFromMyLog;   // only for Resolved
  final VoidCallback? onDelete;            // optional (not used)
  final VoidCallback? onEdit;              // edit pending item
  final VoidCallback? onApprove;           // user approves resolution
  final VoidCallback? onDecline;           // user declines resolution

  const _ReportTile({
    required this.item,
    required this.open,         // NEW (required)
    required this.onToggle,     // NEW (required)
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
    'January','February','March','April','May','June',
    'July','August','September','October','November','December'
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

    final platformLine = r.platformName?.isNotEmpty == true
        ? r.platformName
        : (r.systemName?.isNotEmpty == true
        ? r.systemName
        : (r.platform?.isNotEmpty == true ? r.platform : null));

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
      child: const Text('No image',
          style: TextStyle(fontSize: 10, color: Colors.black54)),
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
            onTap: widget.onToggle, // NEW
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
                        child: const Icon(Icons.keyboard_arrow_down,
                            color: Colors.black, size: 18),
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
            crossFadeState: widget.open
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
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
                const TextSpan(
                    text: 'Other Details: ',
                    style: TextStyle(fontWeight: FontWeight.w600)),
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
                      Text(
                          r.resolvedByDept?.isNotEmpty == true ? r.resolvedByDept! : '—',
                          style: const TextStyle(fontSize: 12, color: Colors.black87)),
                      const Text('•', style: TextStyle(color: Colors.grey)),
                      Text(_fmtDate(r.resolvedAt),
                          style: const TextStyle(fontSize: 12, color: Colors.black87)),
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
                    child: const Text('No image',
                        style: TextStyle(fontSize: 10, color: Colors.black54)),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                      text: 'Resolution Summary: ',
                      style: TextStyle(fontWeight: FontWeight.w600)),
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: EdgeInsets.symmetric(
                    vertical: (size.height * 0.015).clamp(10.0, 14.0),
                  ),
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
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
