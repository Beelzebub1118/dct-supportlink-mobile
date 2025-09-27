import 'package:flutter/material.dart';

/// Drop-in SweetAlert-style message/confirm/prompt utilities for mobile,
/// mirroring your web prompts and wording.
///
/// Usage examples:
///   await AppMsg.success(context, 'Submitted', m: 'Your report has been submitted.');
///   final ok = await AppMsg.confirm(context, title: 'Confirm Approval', message: 'Confirm that the issue is resolved.', confirmText: 'Approve');
///   final notes = await AppMsg.promptText(context, title: 'Decline Resolution', inputLabel: 'Tell us what is still wrong', hint: 'Optional notes...', confirmText: 'Decline');
///
enum AppDialogType { success, error, warning, info }

class AppMsg {
  // Brand-ish colors (warning = orange, 'OK' button ~ your web purple)
  static const _okBtnColor = Color(0xFF6C63FF);
  static const _dark = Color(0xFF0A1936);

  static Color _typeColor(AppDialogType t) {
    switch (t) {
      case AppDialogType.success:
        return Colors.green;
      case AppDialogType.error:
        return Colors.red;
      case AppDialogType.warning:
        return Colors.orange;
      case AppDialogType.info:
        return Colors.blue;
    }
  }

  static IconData _typeIcon(AppDialogType t) {
    switch (t) {
      case AppDialogType.success:
        return Icons.check_rounded;
      case AppDialogType.error:
        return Icons.close_rounded;
      case AppDialogType.warning:
        return Icons.priority_high_rounded;
      case AppDialogType.info:
        return Icons.info_rounded;
    }
  }

  // ---------- Simple alert helpers (match your web semantics) ----------
  static Future<void> success(BuildContext c, String t, {String? m, bool autoClose = true}) =>
      _alert(c, type: AppDialogType.success, title: t, message: m, autoClose: autoClose);

  static Future<void> error(BuildContext c, String t, {String? m}) =>
      _alert(c, type: AppDialogType.error, title: t, message: m);

  static Future<void> info(BuildContext c, String t, {String? m}) =>
      _alert(c, type: AppDialogType.info, title: t, message: m);

  static Future<void> warning(BuildContext c, String t, {String? m}) =>
      _alert(c, type: AppDialogType.warning, title: t, message: m);

  static Future<void> incompleteForm(BuildContext c, {String? custom}) =>
      _alert(c,
          type: AppDialogType.warning,
          title: 'Incomplete Form',
          message: custom ?? 'Please fill in all required fields.');

  static Future<void> reportSubmitted(BuildContext c) =>
      _alert(c, type: AppDialogType.success, title: 'Submitted', message: 'Your report has been submitted.', autoClose: true);

  static Future<void> uploadFailed(BuildContext c) =>
      _alert(c, type: AppDialogType.error, title: 'Upload failed', message: 'Could not upload the image. Try again.');

  static Future<void> reportSubmitFailed(BuildContext c) =>
      _alert(c, type: AppDialogType.error, title: 'Submit failed', message: 'Failed to submit your report.');

  static Future<void> notSignedIn(BuildContext c) =>
      _alert(c, type: AppDialogType.info, title: 'Not signed in', message: 'Please login again.');

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
      _alert(c, type: AppDialogType.success, title: 'Password updated!', autoClose: true);
  static Future<void> changePasswordFailed(BuildContext c) =>
      _alert(c, type: AppDialogType.error, title: 'Failed to change password');
  static Future<void> attemptOverload(BuildContext c) =>
      _alert(c, type: AppDialogType.warning, title: 'Too many attempts', message: 'Try again later.');
  static Future<void> loginRequires(BuildContext c) =>
      _alert(c, type: AppDialogType.info, title: 'Re-login required', message: 'Please re-login to change your password.');

  // ---------- Web-like Confirm / Delete Confirm ----------
  /// Generic confirm (two buttons). Returns true if confirmed.
  static Future<bool> confirm(
      BuildContext c, {
        required String title,
        String? message,
        String confirmText = 'OK',
        String cancelText = 'Cancel',
        AppDialogType type = AppDialogType.warning,
      }) =>
      _confirm(c,
          type: type,
          title: title,
          message: message,
          confirmText: confirmText,
          cancelText: cancelText);

  /// SweetAlert-style delete confirmation used on web.
  static Future<bool> confirmDeleteReport(BuildContext c) async {
    return _confirm(
      c,
      type: AppDialogType.warning,
      title: 'Are you sure?',
      message: "You won't be able to revert this!",
      confirmText: 'Yes',
      cancelText: 'Cancel',
    );
  }

  static Future<void> deleted(BuildContext c) =>
      _alert(c, type: AppDialogType.success, title: 'Deleted!', message: 'Your report has been deleted.', autoClose: true);

  static Future<void> deleteFailed(BuildContext c) =>
      _alert(c, type: AppDialogType.error, title: 'Delete failed', message: 'Please try again.');

  // ---------- Web-like Prompt (textarea) ----------
  /// Text prompt like SweetAlert `input: 'textarea'`.
  /// Returns the entered text, or null if cancelled.
  static Future<String?> promptText(
      BuildContext c, {
        required String title,
        String? inputLabel,
        String? hint,
        String confirmText = 'Submit',
        String cancelText = 'Cancel',
        int maxLines = 3,
      }) async {
    final controller = TextEditingController();
    final res = await showDialog<String?>(
      context: c,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(.55),
      builder: (ctx) => _PromptShell(
        title: title,
        inputLabel: inputLabel,
        hint: hint,
        controller: controller,
        maxLines: maxLines,
        cancelText: cancelText,
        confirmText: confirmText,
      ),
    );
    return res;
  }

  // --------------------------------------------------------------------

  // Core alert
  static Future<void> _alert(
      BuildContext ctx, {
        required AppDialogType type,
        required String title,
        String? message,
        String okText = 'OK',
        bool autoClose = false,
        Duration duration = const Duration(seconds: 2),
      }) async {
    final color = _typeColor(type);

    showDialog<void>(
      context: ctx,
      barrierDismissible: !autoClose,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (c) => _DialogShell(
        color: color,
        icon: _typeIcon(type),
        title: title,
        message: message,
        actions: autoClose
            ? const []
            : [
          _DialogButton(
            text: okText,
            bg: _okBtnColor,
            onTap: () => Navigator.of(c).pop(),
          ),
        ],
      ),
    );

    if (autoClose) {
      await Future.delayed(duration);
      if (ctx.mounted) {
        Navigator.of(ctx, rootNavigator: true).pop();
      }
    }
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
              if (message != null && message!.isNotEmpty) ...[
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
              if (actions.isNotEmpty)
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

class _PromptShell extends StatelessWidget {
  final String title;
  final String? inputLabel;
  final String? hint;
  final TextEditingController controller;
  final int maxLines;
  final String cancelText;
  final String confirmText;

  const _PromptShell({
    required this.title,
    required this.controller,
    required this.maxLines,
    required this.cancelText,
    required this.confirmText,
    this.inputLabel,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final maxW = (size.width * 0.9).clamp(280.0, 500.0);

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
              _RingIcon(color: Colors.orange, icon: Icons.edit_note_rounded),
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
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: maxLines,
                decoration: InputDecoration(
                  labelText: inputLabel,
                  hintText: hint,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _DialogButton(
                    text: cancelText,
                    bg: Colors.grey.shade300,
                    fg: Colors.black87,
                    onTap: () => Navigator.of(context).pop(null),
                  ),
                  const SizedBox(width: 12),
                  _DialogButton(
                    text: confirmText,
                    bg: AppMsg._okBtnColor,
                    onTap: () => Navigator.of(context).pop(controller.text.trim()),
                  ),
                ],
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
