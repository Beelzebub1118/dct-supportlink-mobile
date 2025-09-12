import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'ui_messages.dart'; // where AppMsg lives
class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _currentCtl = TextEditingController();
  final _newCtl = TextEditingController();
  final _confirmCtl = TextEditingController();

  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;
  bool _saving = false;

  final _pink = const Color(0xFFE91E63);

  @override
  void dispose() {
    _currentCtl.dispose();
    _newCtl.dispose();
    _confirmCtl.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final current = _currentCtl.text.trim();
    final next = _newCtl.text.trim();
    final confirm = _confirmCtl.text.trim();

    // validations → SweetAlert-style dialogs
    if (current.isEmpty || next.isEmpty || confirm.isEmpty) {
      await AppMsg.incompleteForm(context, custom: 'Please complete all fields.');
      return;
    }
    if (next != confirm) {
      await AppMsg.passwordMismatch(context);
      return;
    }
    if (next == current) {
      await AppMsg.uniquePassword(context);
      return;
    }
    if (next.length < 6) {
      await AppMsg.passwordLength(context);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      await AppMsg.error(context, 'No authenticated user', m: 'Please re-login.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    try {
      // IMPORTANT: named params fix the “too many positional args” error
      final cred = EmailAuthProvider.credential(
        email: user.email!,
        password: current,
      );
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(next);

      await AppMsg.passwordUpdated(context);   // success modal
      if (!mounted) return;
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'wrong-password':         await AppMsg.passwordIncorrect(context); break;
        case 'too-many-requests':      await AppMsg.attemptOverload(context);   break;
        case 'requires-recent-login':  await AppMsg.loginRequires(context);     break;
        case 'weak-password':          await AppMsg.passwordLength(context);     break;
        default:                       await AppMsg.changePasswordFailed(context);
      }
    } catch (_) {
      await AppMsg.changePasswordFailed(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    // simple responsiveness: scale vertical gaps a bit to screen height
    final h = MediaQuery.of(context).size.height;
    final gap = (h * 0.02).clamp(14.0, 24.0); // 14..24
    final fieldGap = (h * 0.015).clamp(12.0, 20.0); // 12..20

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'CHANGE PASSWORD',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: _saving ? null : () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Current Password
                const Padding(
                  padding: EdgeInsets.only(left: 8.0, bottom: 4.0),
                  child: Text('Current Password',
                      style: TextStyle(color: Colors.black, fontSize: 16)),
                ),
                _buildPasswordField(
                  hintText: 'Enter current password',
                  controller: _currentCtl,
                  obscure: !_showCurrent,
                  onToggle: () => setState(() => _showCurrent = !_showCurrent),
                  enabled: !_saving,
                ),
                SizedBox(height: fieldGap),

                // New Password
                const Padding(
                  padding: EdgeInsets.only(left: 8.0, bottom: 4.0),
                  child: Text('New Password',
                      style: TextStyle(color: Colors.black, fontSize: 16)),
                ),
                _buildPasswordField(
                  hintText: 'Enter new password',
                  controller: _newCtl,
                  obscure: !_showNew,
                  onToggle: () => setState(() => _showNew = !_showNew),
                  enabled: !_saving,
                ),
                SizedBox(height: fieldGap),

                // Confirm Password
                const Padding(
                  padding: EdgeInsets.only(left: 8.0, bottom: 4.0),
                  child: Text('Confirm Password',
                      style: TextStyle(color: Colors.black, fontSize: 16)),
                ),
                _buildPasswordField(
                  hintText: 'Confirm new password',
                  controller: _confirmCtl,
                  obscure: !_showConfirm,
                  onToggle: () => setState(() => _showConfirm = !_showConfirm),
                  enabled: !_saving,
                ),
                SizedBox(height: gap),

                // Save Button (keeps your design)
                ElevatedButton(
                  onPressed: _saving ? null : _handleSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _pink,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _saving ? 'SAVING...' : 'SAVE',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),

          // Saving overlay
          if (_saving)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.08),
                child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Keeps your grey/rounded look; adds a trailing eye toggle (no design change otherwise)
  Widget _buildPasswordField({
    required String hintText,
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggle,
    bool enabled = true,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      enabled: enabled,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintText: hintText,
        suffixIcon: IconButton(
          onPressed: enabled ? onToggle : null,
          icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
        ),
      ),
    );
  }
}
