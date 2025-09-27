import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ui_messages.dart';
import 'notification_service.dart'; // ⬅️ import added

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final Color pinkColor = const Color(0xFFE91E63);
  final Color fieldColor = Colors.grey[200]!;

  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      await AppMsg.incompleteForm(
        context,
        custom: 'Please enter both email and password.',
      );
      return;
    }
    if (_loading) return;

    setState(() => _loading = true);
    try {
      // 1) Sign in
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = cred.user!.uid;

      // 2) Blocked check
      final blockedSnap = await FirebaseFirestore.instance
          .collection('blockedUsers')
          .doc(uid)
          .get();

      if (blockedSnap.exists) {
        await FirebaseAuth.instance.signOut();
        await _clearPrefs();
        await AppMsg.error(
          context,
          'Blocked',
          m: 'Your account has been blocked from DCT SupportLink. Please contact or visit the MIS Office of DCT.',
        );
        return;
      }

      // 3) User document
      final userSnap =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();

      if (!userSnap.exists) {
        await FirebaseAuth.instance.signOut();
        await _clearPrefs();
        await AppMsg.error(
          context,
          'Login failed',
          m: 'No user profile found. Please contact support.',
        );
        return;
      }

      final data = userSnap.data()!;
      final disabled = (data['disabled'] == true);
      final role = (data['role'] ?? '').toString();

      if (disabled) {
        await FirebaseAuth.instance.signOut();
        await _clearPrefs();
        await AppMsg.error(
          context,
          'Blocked',
          m: 'Your account has been disabled by admin.',
        );
        return;
      }

      // 4) Persist uid + role
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('uid', uid);
      await prefs.setString('role', role);

      // 4.1) ⬅️ Save this device's FCM token immediately
      await NotificationService.saveTokenToFirestore(context);

      // 5) Success modal → navigate
      await AppMsg.success(context, 'Login successful');
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/dashboard', (r) => false);
    } on FirebaseAuthException catch (e) {
      await _handleAuthError(e);
    } catch (e) {
      await AppMsg.error(
        context,
        'Login error',
        m: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleAuthError(FirebaseAuthException e) async {
    String msg;
    switch (e.code) {
      case 'invalid-email':
        msg = 'The email address is malformed.';
        break;
      case 'user-disabled':
        msg = 'This user account has been disabled.';
        break;
      case 'user-not-found':
        msg = 'No user found with this email.';
        break;
      case 'wrong-password':
        msg = 'Incorrect password.';
        break;
      case 'too-many-requests':
        msg = 'Too many attempts. Try again later.';
        break;
      case 'network-request-failed':
        msg = 'Network error. Check your connection.';
        break;
      default:
        msg = 'Authentication failed: ${e.code}';
    }
    await AppMsg.error(context, 'Login failed', m: msg);
  }

  Future<void> _clearPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('uid');
    await prefs.remove('role');
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenHeight < 700;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Top decoration
          Positioned(
            top: -65,
            left: 0,
            right: 0,
            child: Image.asset(
              'assets/UpDes.png',
              fit: BoxFit.fitWidth,
              errorBuilder: (context, error, stack) => Container(
                height: 100,
                color: const Color(0xFFE91E63).withOpacity(0.2),
                child: const Center(child: Text('Missing UpDes.png')),
              ),
            ),
          ),
          // Bottom decoration
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Image.asset(
              'assets/LowDes.png',
              fit: BoxFit.fitWidth,
              errorBuilder: (context, error, stack) => Container(
                height: 100,
                color: const Color(0xFFE91E63).withOpacity(0.2),
                child: const Center(child: Text('Missing LowDes.png')),
              ),
            ),
          ),

          // Main content
          Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: isSmallScreen ? 20.0 : 40.0,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 400,
                  minHeight: screenHeight * 0.7,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo
                    Padding(
                      padding: EdgeInsets.only(
                        top: isSmallScreen
                            ? screenHeight * 0.02
                            : screenHeight * 0.005,
                        bottom: isSmallScreen ? 20.0 : 100.0,
                      ),
                      child: Image.asset(
                        'assets/DCTSupportLinkLogo.png',
                        height: isSmallScreen ? screenHeight * 0.15 : 140,
                        errorBuilder: (context, error, stack) =>
                            _buildMissingImagePlaceholder(
                              'Logo',
                              height:
                              isSmallScreen ? screenHeight * 0.15 : 200,
                            ),
                      ),
                    ),

                    // Email
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      enabled: !_loading,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        filled: true,
                        fillColor: fieldColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                      onSubmitted: (_) => _handleLogin(),
                    ),
                    SizedBox(height: isSmallScreen ? 15.0 : 20.0),

                    // Password
                    TextField(
                      controller: _passwordController,
                      enabled: !_loading,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        filled: true,
                        fillColor: fieldColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                        ),
                      ),
                      onSubmitted: (_) => _handleLogin(),
                    ),
                    SizedBox(height: isSmallScreen ? 20.0 : 30.0),

                    // Login button
                    Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: isSmallScreen ? 24.0 : 48.0),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: pinkColor,
                          padding: EdgeInsets.symmetric(
                            vertical: isSmallScreen ? 14.0 : 16.0,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.0),
                          ),
                        ),
                        onPressed: _loading ? null : _handleLogin,
                        child: _loading
                            ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                            : const Text(
                          'LOGIN',
                          style: TextStyle(
                            fontSize: 16,
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
        ],
      ),
    );
  }

  Widget _buildMissingImagePlaceholder(String imageName, {double? height}) {
    return Container(
      height: height,
      color: Colors.grey[200],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(height: 8),
            Text('Missing: $imageName'),
          ],
        ),
      ),
    );
  }
}
