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
class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  _DashboardState createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  int _selectedIndex = 0;
  final Color pinkColor = const Color(0xFFE91E63);
  final Color iconColor = Colors.white;
  final Color inactiveIconColor = Colors.white70;
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
    _subscribePresets(); // NEW
  }

  @override
  void dispose() {
    _presetSub?.cancel(); // NEW
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
    setState(() => _selectedIndex = index);
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

          // chat bubble (kept where you placed it)
          Positioned(
            right: 16,
            bottom: -50 + navH, // keep above bottom nav (unchanged as requested)
            child: FloatingActionButton.extended(
              onPressed: () => setState(() => _chatOpen = true),
              backgroundColor: pinkColor,
              icon: const Icon(Icons.support_agent, color: Colors.white),
              label: const Text('Help', style: TextStyle(color: Colors.white)),
            ),
          ),

          // chat overlay panel
          if (_chatOpen) _buildChatOverlay(context),
        ],
      ),
      bottomNavigationBar: CurvedNavigationBar(
        height: navH,
        backgroundColor: Colors.transparent,
        color: pinkColor,
        buttonBackgroundColor: pinkColor,
        animationDuration: const Duration(milliseconds: 300),
        items: <Widget>[
          Icon(Icons.assessment_outlined,
              size: iconSz,
              color: _selectedIndex == 0 ? iconColor : inactiveIconColor),
          Icon(Icons.history_outlined,
              size: iconSz,
              color: _selectedIndex == 1 ? iconColor : inactiveIconColor),
          Icon(Icons.account_circle_outlined,
              size: iconSz,
              color: _selectedIndex == 2 ? iconColor : inactiveIconColor),
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
                                        backgroundColor: Color(0xFFE91E63),
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
                                          backgroundColor: const Color(0xFFE91E63),
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
                                    backgroundColor: const Color(0xFFE91E63),
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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
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
                      color: m.isUser ? const Color(0xFFE91E63) : Colors.grey.shade200,
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

class _ChatMsg {
  final String text;
  final bool isUser;
  _ChatMsg({required this.text, required this.isUser});
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
    'IT Support Services',
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
      AppMsg.notSignedIn(context);
      return;
    }

    if (building.isEmpty || floor.isEmpty || service == null || image == null) {
      AppMsg.incompleteForm(context, custom: 'Please complete all required fields and select an image.');
      return;
    }

    setState(() => _submitting = true);
    try {
      // 1) Upload image first
      final imageUrl = await _uploadToCloudinary(image);
      if (imageUrl == null) {
        AppMsg.uploadFailed(context);
        return;
      }

      // 2) Create Firestore doc
      await FirebaseFirestore.instance.collection('userReport').add({
        'serverTimeStamp': FieldValue.serverTimestamp(),
        'buildingName': building,
        'floorLocation': floor,
        'serviceType': service,
        'additionalDetails': details,
        'imageUrl': imageUrl,
        'uid': uid,
        'status': 'Pending',
      });

      // 3) Reset
      _buildingCtrl.clear();
      _floorCtrl.clear();
      _detailsCtrl.clear();
      setState(() {
        _serviceType = null;
        _pickedImage = null;
      });

      AppMsg.reportSubmitted(context);
    } catch (e) {
      debugPrint('Error submitting report: $e');
      AppMsg.reportSubmitFailed(context);
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
            padding: EdgeInsets.all(edge),
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
                          backgroundColor: _pink,
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



class ReportLogsPage extends StatefulWidget {
  const ReportLogsPage({super.key});

  @override
  State<ReportLogsPage> createState() => _ReportLogsPageState();
}

class _ReportLogsPageState extends State<ReportLogsPage> {
  bool _loading = true;
  String? _error;

  // status filter (All | Pending | On Process | Resolved)
  String _statusFilter = 'All';

  // merged list from all collections
  final List<_ReportItem> _reports = [];

  // per-user hidden resolved IDs
  final Set<String> _hiddenResolvedIds = <String>{};

  // image picker (used by Edit sheet)
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
      _reports.clear();
      _hiddenResolvedIds.clear();
    });

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() {
        _loading = false;
        _error = 'Not signed in. Please login again.';
      });
      return;
    }

    try {
      await Future.wait([
        _loadHides(uid),
        _loadReports(uid),
      ]);
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load reports.';
      });
    }
  }

  Future<void> _loadHides(String uid) async {
    final snap = await FirebaseFirestore.instance
        .collection('userResolvedHides')
        .where('uid', isEqualTo: uid)
        .get();

    final ids = snap.docs
        .map((d) => (d.data()['reportId'] as String?) ?? '')
        .where((e) => e.isNotEmpty);
    _hiddenResolvedIds.addAll(ids);
  }

  Future<void> _loadReports(String uid) async {
    final fs = FirebaseFirestore.instance;

    final q1 = fs.collection('userReport').where('uid', isEqualTo: uid).get();
    final q2 = fs.collection('onProcess').where('uid', isEqualTo: uid).get();
    final q3 = fs.collection('resolvedReports').where('uid', isEqualTo: uid).get();

    final results = await Future.wait([q1, q2, q3]);

    for (final doc in results[0].docs) {
      _reports.add(_ReportItem.fromDoc(
        doc,
        collectionName: 'userReport',
        fallbackStatus: 'Pending',
      ));
    }
    for (final doc in results[1].docs) {
      _reports.add(_ReportItem.fromDoc(
        doc,
        collectionName: 'onProcess',
        fallbackStatus: 'On Process',
      ));
    }
    for (final doc in results[2].docs) {
      _reports.add(_ReportItem.fromDoc(
        doc,
        collectionName: 'resolvedReports',
        fallbackStatus: 'Resolved',
      ));
    }

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
      if (s == 'pending') {
        p++;
      } else if (s == 'on process') {
        o++;
      } else if (s == 'resolved') {
        r++;
      }
    }
    return (all: _visibleReports.length, pending: p, onproc: o, resolved: r);
  }

  List<_ReportItem> get _filtered {
    final list = _visibleReports;
    if (_statusFilter == 'All') return list;
    final wanted = _statusFilter.toLowerCase();
    return list.where((e) => e.status.toLowerCase() == wanted).toList();
  }

  // Fullscreen image preview
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

  // Remove from MY log (resolved only)
  Future<void> _removeFromMyLog(_ReportItem r) async {
    if (r.status.toLowerCase() != 'resolved') {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Not allowed'),
          content: const Text('You can only remove items that are already Resolved.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
          ],
        ),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove from your log?'),
        content: const Text('This action will remove this report from your Report Log.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    ) ??
        false;
    if (!ok) return;

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not signed in')));
        return;
      }

      // 1) write user hide marker
      final hideId = '${uid}_${r.id}';
      await FirebaseFirestore.instance.collection('userResolvedHides').doc(hideId).set({
        'uid': uid,
        'reportId': r.id,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 2) if admin already hid -> hard delete from resolvedReports
      if (r.hiddenForAdmin == true) {
        await FirebaseFirestore.instance.collection('resolvedReports').doc(r.id).delete();
      }

      // 3) update local UI immediately
      setState(() {
        _hiddenResolvedIds.add(r.id);
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.hiddenForAdmin == true ? 'Deleted.' : 'Removed from your log.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to remove report.')));
    }
  }

  // ---------- EDIT: open sheet ----------
  void _openEditSheet(_ReportItem r) {
    // Only allow edit for pending reports that are still in 'userReport'
    final isEditable = r.status.toLowerCase() == 'pending' && r.collection == 'userReport';
    if (!isEditable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only Pending reports can be edited.')),
      );
      return;
    }

    // local state for the bottom sheet
    const serviceTypes = <String>[
      'Facilities and Maintenance',
      'IT Support Services - Hardware',
      'IT Support Services - Software',
    ];
    String svcType = r.serviceType ?? '';
    String buildingName = r.buildingName ?? '';
    String floorLocation = r.floorLocation ?? '';
    String platformName =
        (r.platformName?.isNotEmpty == true ? r.platformName : (r.systemName?.isNotEmpty == true ? r.systemName : r.platform)) ??
            '';
    String details = r.additionalDetails ?? '';
    String currentImageUrl = r.imageUrl ?? '';
    XFile? newImage;
    bool saving = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> pickFrom(ImageSource src) async {
              final f = await _picker.pickImage(source: src, imageQuality: 85, maxWidth: 1600);
              if (f != null) setLocal(() => newImage = f);
            }

            Future<void> doSave() async {
              // validation
              final isSW = svcType == 'IT Support Services - Software';
              final hasImage = (newImage != null) || currentImageUrl.isNotEmpty;
              if (svcType.isEmpty) {
                _toast('Please choose a service type.');
                return;
              }
              if (!hasImage) {
                _toast('Please attach an image.');
                return;
              }
              if (isSW) {
                if (platformName.trim().isEmpty) {
                  _toast('Please enter the Platform / System Name.');
                  return;
                }
              } else {
                if (buildingName.trim().isEmpty) {
                  _toast('Please enter the Building Name.');
                  return;
                }
                if (floorLocation.trim().isEmpty) {
                  _toast('Please enter the Floor / Room Location.');
                  return;
                }
              }

              setLocal(() => saving = true);

              // upload new image if present
              String finalUrl = currentImageUrl;
              if (newImage != null) {
                final uploaded = await _uploadToCloudinary(newImage!);
                if (uploaded == null) {
                  setLocal(() => saving = false);
                  _toast('Image upload failed. Try again.');
                  return;
                }
                finalUrl = uploaded;
              }

              // build payload
              final payload = <String, dynamic>{
                'serviceType': svcType,
                'additionalDetails': details,
                'imageUrl': finalUrl,
                'lastEditedAt': FieldValue.serverTimestamp(),
                // normalize fields based on type
                'platformName': isSW ? platformName : null,
                'buildingName': isSW ? null : buildingName,
                'floorLocation': isSW ? null : floorLocation,
              };

              try {
                await FirebaseFirestore.instance.collection('userReport').doc(r.id).update(payload);

                // update local list
                final idx = _reports.indexWhere((e) => e.id == r.id && e.collection == r.collection);
                if (idx != -1) {
                  setState(() {
                    _reports[idx] = _reports[idx].copyWith(
                      serviceType: svcType,
                      additionalDetails: details,
                      imageUrl: finalUrl,
                      platformName: isSW ? platformName : null,
                      buildingName: isSW ? null : buildingName,
                      floorLocation: isSW ? null : floorLocation,
                    );
                  });
                }

                if (mounted) Navigator.pop(ctx);
                _toast('Report updated.');
              } catch (e) {
                _toast('Failed to update the report.');
              } finally {
                setLocal(() => saving = false);
              }
            }

            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        height: 5,
                        width: 44,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const Text('Edit Report',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 14),

                      // Service type radios
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Service Type',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: serviceTypes.map((t) {
                          final selected = svcType == t;
                          return ChoiceChip(
                            label: Text(t, style: const TextStyle(fontSize: 12)),
                            selected: selected,
                            onSelected: (_) => setLocal(() => svcType = t),
                            selectedColor: const Color(0xFF0A1936),
                            labelStyle: TextStyle(color: selected ? Colors.white : Colors.black),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 12),

                      // Conditional fields
                      if (svcType == 'IT Support Services - Software') ...[
                        _LabeledField(
                          label: 'Platform / System Name',
                          child: TextField(
                            decoration: _inputDecoration('e.g., LMS, Library System'),
                            onChanged: (v) => platformName = v,
                            controller: TextEditingController(text: platformName),
                          ),
                        ),
                      ] else ...[
                        _LabeledField(
                          label: 'Building Name',
                          child: TextField(
                            decoration: _inputDecoration('Enter building name'),
                            onChanged: (v) => buildingName = v,
                            controller: TextEditingController(text: buildingName),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _LabeledField(
                          label: 'Floor / Room Location',
                          child: TextField(
                            decoration: _inputDecoration('Enter floor/room'),
                            onChanged: (v) => floorLocation = v,
                            controller: TextEditingController(text: floorLocation),
                          ),
                        ),
                      ],

                      const SizedBox(height: 12),

                      // Image row
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Image',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF0A1936),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.all(6),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: SizedBox(
                                width: 110,
                                height: 76,
                                child: newImage != null
                                    ? Image.file(File(newImage!.path), fit: BoxFit.cover)
                                    : (currentImageUrl.isNotEmpty
                                    ? Image.network(currentImageUrl, fit: BoxFit.cover)
                                    : Container(color: Colors.black12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            children: [
                              ElevatedButton.icon(
                                onPressed: saving ? null : () => pickFrom(ImageSource.gallery),
                                icon: const Icon(Icons.photo_library, size: 18),
                                label: const Text('Upload'),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.black87, foregroundColor: Colors.white),
                              ),
                              const SizedBox(height: 6),
                              ElevatedButton.icon(
                                onPressed: saving ? null : () => pickFrom(ImageSource.camera),
                                icon: const Icon(Icons.photo_camera, size: 18),
                                label: const Text('Camera'),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.black87, foregroundColor: Colors.white),
                              ),
                              if (newImage != null)
                                TextButton(
                                  onPressed: saving ? null : () => setLocal(() => newImage = null),
                                  child: const Text('Remove new image'),
                                ),
                            ],
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      _LabeledField(
                        label: 'Other Details',
                        child: TextField(
                          maxLines: 3,
                          decoration: _inputDecoration('Describe the issue...'),
                          onChanged: (v) => details = v,
                          controller: TextEditingController(text: details),
                        ),
                      ),

                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: saving ? null : () => Navigator.pop(ctx),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: saving ? null : doSave,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0A1936),
                                foregroundColor: Colors.white,
                              ),
                              child: saving
                                  ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                                  : const Text('Save Changes'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Cloudinary upload
  Future<String?> _uploadToCloudinary(XFile file) async {
    try {
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
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final counts = _counts();
    final size = MediaQuery.of(context).size;
    final edge = (size.width * 0.05).clamp(16.0, 24.0);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'REPORT LOGS',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh, color: Colors.black),
          ),
        ],
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
                              items: const [
                                'All',
                                'Pending',
                                'On Process',
                                'Resolved',
                              ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
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
                    final canEdit = r.status.toLowerCase() == 'pending' && r.collection == 'userReport';
                    return _ReportTile(
                      item: r,
                      onPreview: r.imageUrl != null ? () => _previewImage(r.imageUrl!) : null,
                      onPreviewResolved: (r.resolvedImageUrl != null &&
                          r.resolvedImageUrl!.isNotEmpty)
                          ? () => _previewImage(r.resolvedImageUrl!)
                          : null,
                      onRemoveFromMyLog:
                      r.status.toLowerCase() == 'resolved' ? () => _removeFromMyLog(r) : null,
                      onEdit: canEdit ? () => _openEditSheet(r) : null,
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
    this.serverTimeStamp,
    this.processedAt,
    this.resolvedAt,
    this.resolvedByName,
    this.resolvedByDept,
    this.resolutionNotes,
    this.resolvedImageUrl,
    this.hiddenForAdmin,
  });

  int get sortMillis =>
      (resolvedAt?.millisecondsSinceEpoch ??
          processedAt?.millisecondsSinceEpoch ??
          serverTimeStamp?.millisecondsSinceEpoch ??
          0);

  _ReportItem copyWith({
    String? serviceType,
    String? buildingName,
    String? floorLocation,
    String? platformName,
    String? additionalDetails,
    String? imageUrl,
  }) {
    return _ReportItem(
      id: id,
      collection: collection,
      status: status,
      buildingName: buildingName ?? this.buildingName,
      floorLocation: floorLocation ?? this.floorLocation,
      serviceType: serviceType ?? this.serviceType,
      platformName: platformName ?? this.platformName,
      systemName: systemName,
      platform: platform,
      additionalDetails: additionalDetails ?? this.additionalDetails,
      imageUrl: imageUrl ?? this.imageUrl,
      serverTimeStamp: serverTimeStamp,
      processedAt: processedAt,
      resolvedAt: resolvedAt,
      resolvedByName: resolvedByName,
      resolvedByDept: resolvedByDept,
      resolutionNotes: resolutionNotes,
      resolvedImageUrl: resolvedImageUrl,
      hiddenForAdmin: hiddenForAdmin,
    );
  }

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
      serverTimeStamp: data['serverTimeStamp'] as Timestamp?,
      processedAt: data['processedAt'] as Timestamp?,
      resolvedAt: data['resolvedAt'] as Timestamp?,

      resolvedByName: data['resolvedByName'] as String?,
      resolvedByDept: data['resolvedByDept'] as String?,
      resolutionNotes: data['resolutionNotes'] as String?,
      resolvedImageUrl: data['resolvedImageUrl'] as String?,
      hiddenForAdmin: data['hiddenForAdmin'] as bool?,
    );
  }
}

class _ReportTile extends StatefulWidget {
  final _ReportItem item;

  final VoidCallback? onPreview; // original image
  final VoidCallback? onPreviewResolved; // resolution image
  final VoidCallback? onRemoveFromMyLog; // only for Resolved
  final VoidCallback? onDelete; // optional (not used)
  final VoidCallback? onEdit; // edit pending item

  const _ReportTile({
    required this.item,
    this.onPreview,
    this.onPreviewResolved,
    this.onRemoveFromMyLog,
    this.onDelete,
    this.onEdit,
  });

  @override
  State<_ReportTile> createState() => _ReportTileState();
}

class _ReportTileState extends State<_ReportTile> {
  bool _open = false;

  String _fmtDate(Timestamp? ts) {
    if (ts == null) return '—';
    final d = ts.toDate();
    return '${_mfull(d.month)} ${d.day}, ${d.year}  ${_two(d.hour)}:${_two(d.minute)}';
  }

  static String _mfull(int m) =>
      ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][m - 1];
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

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF0A1936)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Container(
              height: headerH,
              decoration: const BoxDecoration(
                color: Color(0xFF0A1936),
                borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _StatusChip(status: r.status),
                  Row(
                    children: [
                      Text(_open ? 'Hide Details' : 'View Details', style: const TextStyle(color: Colors.white)),
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        duration: const Duration(milliseconds: 200),
                        turns: _open ? 0.5 : 0.0,
                        child: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(11)),
                border: Border.all(color: Colors.transparent),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top meta fields + original thumbnail
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _kv('Building Name', r.buildingName),
                            _kv('Floor Location', r.floorLocation),
                            _kv('Service Type', r.serviceType),
                            _kv('Platform / System Name', platformLine),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // original thumbnail
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A1936),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.all(6),
                        child: (r.imageUrl?.isNotEmpty ?? false)
                            ? GestureDetector(
                          onTap: widget.onPreview,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              r.imageUrl!,
                              width: thumbW,
                              height: thumbH,
                              fit: BoxFit.cover,
                            ),
                          ),
                        )
                            : SizedBox(width: thumbW, height: thumbH),
                      ),
                    ],
                  ),

                  // Report details
                  const SizedBox(height: 12),
                  const Text('Report Details',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'Other Details: ', style: TextStyle(fontWeight: FontWeight.w600)),
                        TextSpan(text: r.additionalDetails ?? '—'),
                      ],
                    ),
                    style: const TextStyle(fontSize: 14),
                  ),

                  // Resolution section
                  if (isResolved) ...[
                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 6),

                    // resolution header + thumb
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            children: [
                              Text(r.resolvedByName?.isNotEmpty == true ? r.resolvedByName! : '—',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                              const Text('•', style: TextStyle(color: Colors.grey)),
                              Text(r.resolvedByDept?.isNotEmpty == true ? r.resolvedByDept! : '—',
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
                            color: const Color(0xFF0A1936),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.all(6),
                          child: (r.resolvedImageUrl?.isNotEmpty ?? false)
                              ? GestureDetector(
                            onTap: widget.onPreviewResolved,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
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
                              color: const Color(0xFF0A1936),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child:
                            const Text('No image', style: TextStyle(fontSize: 10, color: Colors.white70)),
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
                      style: const TextStyle(fontSize: 14),
                    ),

                    const SizedBox(height: 12),
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

                  // Edit (Pending only)
                  if (canEdit) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: widget.onEdit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0A1936),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Edit Report'),
                      ),
                    ),
                  ],

                  // Optional hard-delete button (not part of web UX)
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
            ),
            crossFadeState: _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String? v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        '$k: ${v?.isNotEmpty == true ? v : '—'}',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    Color bg = s == 'resolved'
        ? Colors.green
        : s == 'on process'
        ? Colors.orange
        : s == 'pending'
        ? Colors.grey
        : Colors.blueGrey;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(
        status,
        style: const TextStyle(color: Colors.white, fontSize: 12),
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
    try {
      await FirebaseAuth.instance.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('uid');
      await prefs.remove('role');
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error signing out')),
      );
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
