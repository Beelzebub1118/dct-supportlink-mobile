import 'package:flutter/material.dart';

enum AppDialogType { success, error, warning, info }

class AppMsg {
  // Brand-ish colors (warning = orange, ok button ~ purple like your web)
  static const _okBtnColor = Color(0xFF6C63FF);
  static const _dark       = Color(0xFF0A1936);

  static Color _typeColor(AppDialogType t) {
    switch (t) {
      case AppDialogType.success: return Colors.green;
      case AppDialogType.error:   return Colors.red;
      case AppDialogType.warning: return Colors.orange;
      case AppDialogType.info:    return Colors.blue;
    }
  }

  static IconData _typeIcon(AppDialogType t) {
    switch (t) {
      case AppDialogType.success: return Icons.check_rounded;
      case AppDialogType.error:   return Icons.close_rounded;
      case AppDialogType.warning: return Icons.priority_high_rounded;
      case AppDialogType.info:    return Icons.info_rounded;
    }
  }

  // ---------- Public helpers (names match your web semantics) ----------
  static Future<void> success(BuildContext c, String t, {String? m}) =>
      _alert(c, type: AppDialogType.success, title: t, message: m);

  static Future<void> error(BuildContext c, String t, {String? m}) =>
      _alert(c, type: AppDialogType.error, title: t, message: m);

  static Future<void> info(BuildContext c, String t, {String? m}) =>
      _alert(c, type: AppDialogType.info, title: t, message: m);

  static Future<void> incompleteForm(BuildContext c, {String? custom}) =>
      _alert(c,
          type: AppDialogType.warning,
          title: 'Incomplete Form',
          message: custom ?? 'Please fill in all required fields.');

  static Future<void> reportSubmitted(BuildContext c) =>
      _alert(c, type: AppDialogType.success, title: 'Success', message: 'Report submitted!');

  static Future<void> uploadFailed(BuildContext c) =>
      _alert(c, type: AppDialogType.error, title: 'Upload failed', message: 'Please try again.');

  static Future<void> reportSubmitFailed(BuildContext c) =>
      _alert(c, type: AppDialogType.error, title: 'Failed to submit report', message: 'Please try again.');

  static Future<void> notSignedIn(BuildContext c) =>
      _alert(c, type: AppDialogType.info, title: 'Not signed in', message: 'Please re-login.');

  // Change password messages
  static Future<void> passwordMismatch(BuildContext c) =>
      _alert(c, type: AppDialogType.error, title: 'Password mismatch', message: 'Passwords do not match.');
  static Future<void> passwordIncorrect(BuildContext c) =>
      _alert(c, type: AppDialogType.error, title: 'Incorrect password', message: 'Current password is incorrect.');
  static Future<void> passwordLength(BuildContext c) =>
      _alert(c, type: AppDialogType.warning, title: 'Weak password', message: 'Password must be at least 6 characters.');
  static Future<void> uniquePassword(BuildContext c) =>
      _alert(c, type: AppDialogType.warning, title: 'Use a new password', message: 'New password must be different from current.');
  static Future<void> passwordUpdated(BuildContext c) =>
      _alert(c, type: AppDialogType.success, title: 'Password updated!');
  static Future<void> changePasswordFailed(BuildContext c) =>
      _alert(c, type: AppDialogType.error, title: 'Failed to change password');
  static Future<void> attemptOverload(BuildContext c) =>
      _alert(c, type: AppDialogType.warning, title: 'Too many attempts', message: 'Try again later.');
  static Future<void> loginRequires(BuildContext c) =>
      _alert(c, type: AppDialogType.info, title: 'Re-login required', message: 'Please re-login to change your password.');

  // Delete confirmations in SweetAlert style
  static Future<bool> confirmDeleteReport(BuildContext c) async {
    return _confirm(
      c,
      type: AppDialogType.warning,
      title: 'Are you sure?',
      message: "You won't be able to revert this!",
      confirmText: 'Yes, delete it!',
      cancelText: 'Cancel',
    );
  }

  static Future<void> deleted(BuildContext c) =>
      _alert(c, type: AppDialogType.success, title: 'Deleted!', message: 'Your report has been deleted.');
  static Future<void> deleteFailed(BuildContext c) =>
      _alert(c, type: AppDialogType.error, title: 'Delete failed', message: 'Please try again.');
  // --------------------------------------------------------------------

  // Core alert
  static Future<void> _alert(
      BuildContext ctx, {
        required AppDialogType type,
        required String title,
        String? message,
        String okText = 'OK',
      }) async {
    final color = _typeColor(type);
    await showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (c) => _DialogShell(
        color: color,
        icon: _typeIcon(type),
        title: title,
        message: message,
        actions: [
          _DialogButton(
            text: okText,
            bg: _okBtnColor,
            onTap: () => Navigator.of(c).pop(),
          ),
        ],
      ),
    );
  }

  // Confirm dialog (two buttons)
  static Future<bool> _confirm(
      BuildContext ctx, {
        required AppDialogType type,
        required String title,
        String? message,
        String confirmText = 'OK',
        String cancelText = 'Cancel',
      }) async {
    final color = _typeColor(type);
    final result = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (c) => _DialogShell(
        color: color,
        icon: _typeIcon(type),
        title: title,
        message: message,
        actions: [
          _DialogButton(
            text: cancelText,
            bg: Colors.grey.shade300,
            fg: Colors.black87,
            onTap: () => Navigator.of(c).pop(false),
          ),
          _DialogButton(
            text: confirmText,
            bg: _okBtnColor,
            onTap: () => Navigator.of(c).pop(true),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

// ------- Visual building blocks for the SweetAlert-like dialog -------

class _DialogShell extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String? message;
  final List<Widget> actions;

  const _DialogShell({
    required this.color,
    required this.icon,
    required this.title,
    required this.actions,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final maxW = (size.width * 0.9).clamp(280.0, 420.0);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RingIcon(color: color, icon: icon),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 10),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: actions
                    .map((w) => Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: w))
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingIcon extends StatelessWidget {
  final Color color;
  final IconData icon;
  const _RingIcon({required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: color.withOpacity(.25), width: 6),
      ),
      child: Center(
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: color, width: 3),
          ),
          child: Icon(icon, color: color, size: 36),
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;

  const _DialogButton({
    required this.text,
    required this.bg,
    required this.onTap,
    this.fg = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}
