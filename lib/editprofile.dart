import 'dart:convert';
import 'dart:io';
import 'package:dct_supportlink/ui_messages.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _nameCtl = TextEditingController();
  final _roleCtl = TextEditingController();
  final _deptCtl = TextEditingController();

  final _nameKey = GlobalKey();
  final _roleKey = GlobalKey();
  final _deptKey = GlobalKey();

  final _nameFocus = FocusNode();
  final _roleFocus = FocusNode();
  final _deptFocus = FocusNode();

  final _scrollCtrl = ScrollController();

  final Color _pink = const Color(0xFFE91E63);

  String _photoUrl = '';
  File? _newImageFile;
  bool _saving = false;
  bool _seeded = false;

  OverlayEntry? _tipEntry; // active tooltip
  static const String _cloudName = 'dsycysb0e';
  static const String _uploadPreset = 'supportlink';

  @override
  void dispose() {
    _nameCtl.dispose();
    _roleCtl.dispose();
    _deptCtl.dispose();
    _nameFocus.dispose();
    _roleFocus.dispose();
    _deptFocus.dispose();
    _scrollCtrl.dispose();
    _removeTip();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (file != null) {
      setState(() => _newImageFile = File(file.path));
    }
  }

  Future<String?> _uploadToCloudinary(File file) async {
    final uri = Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/image/upload');
    final req = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = _uploadPreset
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final res = await req.send();
    final body = await res.stream.bytesToString();
    if (res.statusCode == 200 || res.statusCode == 201) {
      final jsonMap = json.decode(body) as Map<String, dynamic>;
      return (jsonMap['secure_url'] as String?) ?? (jsonMap['url'] as String?);
    }
    debugPrint('Cloudinary upload failed: ${res.statusCode} $body');
    return null;
  }

  // ---------- Tooltip helpers ----------
  void _removeTip() {
    _tipEntry?..remove();
    _tipEntry = null;
  }

  Future<void> _showFieldTip(GlobalKey key, String message) async {
    _removeTip();

    // Ensure the field is visible first
    final ctx = key.currentContext;
    if (ctx != null) {
      await Scrollable.ensureVisible(
        ctx,
        alignment: 0.2,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }

    final overlay = Overlay.of(context);
    if (overlay == null || key.currentContext == null) return;

    final box = key.currentContext!.findRenderObject() as RenderBox?;
    if (box == null) return;

    final fieldSize = box.size;
    final fieldPos = box.localToGlobal(Offset.zero);

    // Position: centered under the text field, slightly overlapping the top border
    final left = fieldPos.dx + (fieldSize.width / 2) - 120; // 240 = tooltip width
    final top = fieldPos.dy - 46; // above the field

    _tipEntry = OverlayEntry(
      builder: (_) => Positioned(
        left: left.clamp(12, MediaQuery.of(context).size.width - 252),
        top: top,
        width: 240,
        child: _FieldPopover(message: message),
      ),
    );

    overlay.insert(_tipEntry!);
    await Future.delayed(const Duration(seconds: 2));
    _removeTip();
  }

  // ---------- Save ----------
  Future<void> _save() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      await AppMsg.notSignedIn(context);
      return;
    }

    final name = _nameCtl.text.trim();
    final role = _roleCtl.text.trim();
    final dept = _deptCtl.text.trim();

    // keep whatever field-level popovers/validation you already have
    if (name.isEmpty || role.isEmpty || dept.isEmpty) {
      await AppMsg.incompleteForm(
        context,
        custom: 'Please complete Name, Role, and Department.',
      );
      return;
    }

    try {
      setState(() => _saving = true);

      String photoUrl = _photoUrl;
      if (_newImageFile != null) {
        final uploaded = await _uploadToCloudinary(_newImageFile!);
        if (uploaded == null) {
          await AppMsg.uploadFailed(context);
          return;
        }
        photoUrl = uploaded;
      }

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'name': name,
        'role': role,
        'department': dept,
        'photoUrl': photoUrl,
      }, SetOptions(merge: true));

      if (!mounted) return;

      // ✅ Show centered modal like your web:
      await AppMsg.success(
        context,
        'Profile Updated',
        m: 'Your profile is successfully updated!',
      );

      Navigator.pop(context);
    } catch (e) {
      await AppMsg.error(
        context,
        'Failed to save profile',
        m: 'Please try again.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final h = MediaQuery.of(context).size.height;
    final double radius = (h * 0.08).clamp(44.0, 56.0);
    final double topPad = (h * 0.01).clamp(6.0, 12.0);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'EDIT PROFILE',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: uid == null
          ? const Center(child: Text('Not signed in'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
        builder: (context, snap) {
          final data = snap.data?.data() ?? {};
          if (!_seeded && data.isNotEmpty) {
            _nameCtl.text = (data['name'] as String?)?.trim() ?? '';
            _roleCtl.text = (data['role'] as String?)?.trim() ?? '';
            _deptCtl.text = (data['department'] as String?)?.trim() ?? '';
            _photoUrl = (data['photoUrl'] as String?)?.trim() ?? '';
            _seeded = true;
          }

          return Stack(
            children: [
              SingleChildScrollView(
                controller: _scrollCtrl,
                padding: EdgeInsets.fromLTRB(20, topPad, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Avatar
                    Center(
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: radius,
                            backgroundColor: _pink,
                            child: ClipOval(
                              child: _newImageFile != null
                                  ? Image.file(
                                _newImageFile!,
                                width: radius * 2,
                                height: radius * 2,
                                fit: BoxFit.cover,
                              )
                                  : (_photoUrl.isNotEmpty
                                  ? Image.network(
                                _photoUrl,
                                width: radius * 2,
                                height: radius * 2,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.person,
                                  size: 50,
                                  color: Colors.white,
                                ),
                              )
                                  : const Icon(
                                Icons.person,
                                size: 50,
                                color: Colors.white,
                              )),
                            ),
                          ),
                          Material(
                            color: Colors.white,
                            shape: const CircleBorder(),
                            child: IconButton(
                              icon: const Icon(Icons.edit, size: 18),
                              onPressed: _pickImage,
                              tooltip: 'Change photo',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Name
                    const Padding(
                      padding: EdgeInsets.only(left: 8.0, bottom: 4.0),
                      child: Text('Name',
                          style: TextStyle(color: Colors.black, fontSize: 16)),
                    ),
                    Container(
                      key: _nameKey,
                      child: _buildTextField(
                        controller: _nameCtl,
                        focusNode: _nameFocus,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Role
                    const Padding(
                      padding: EdgeInsets.only(left: 8.0, bottom: 4.0),
                      child: Text('Role',
                          style: TextStyle(color: Colors.black, fontSize: 16)),
                    ),
                    Container(
                      key: _roleKey,
                      child: _buildTextField(
                        controller: _roleCtl,
                        focusNode: _roleFocus,
                        hintText: 'e.g., Admin or User',
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Department
                    const Padding(
                      padding: EdgeInsets.only(left: 8.0, bottom: 4.0),
                      child: Text('Department',
                          style: TextStyle(color: Colors.black, fontSize: 16)),
                    ),
                    Container(
                      key: _deptKey,
                      child: _buildTextField(
                        controller: _deptCtl,
                        focusNode: _deptFocus,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Save
                    ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _pink,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _saving ? 'SAVING…' : 'SAVE',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (_saving)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.1),
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

  Widget _buildTextField({
    required TextEditingController controller,
    FocusNode? focusNode,
    String? hintText,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintText: hintText,
      ),
    );
  }
}

/// Small SweetAlert-like tooltip used for field validation.
class _FieldPopover extends StatelessWidget {
  const _FieldPopover({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // bubble
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
              border: Border.all(color: Colors.black12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.priority_high_rounded, color: Colors.orange, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    message,
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                ),
              ],
            ),
          ),
          // little pointer
          Transform.translate(
            offset: const Offset(0, -1),
            child: CustomPaint(
              size: const Size(14, 8),
              painter: _TrianglePainter(color: Colors.white, stroke: Colors.black12),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final Color color;
  final Color stroke;
  _TrianglePainter({required this.color, required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();

    final fill = Paint()..color = color;
    final outline = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke;

    canvas.drawPath(p, fill);
    canvas.drawPath(p, outline);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
