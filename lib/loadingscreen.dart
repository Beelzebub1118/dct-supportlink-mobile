import 'package:flutter/material.dart';
import 'dart:async';
import 'login.dart'; // LoginScreen yung class dito

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  @override
  void initState() {
    super.initState();
    // Simulate loading (3 seconds) bago lumipat
    Timer(const Duration(seconds: 3), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const LoginScreen(), // ✅ tama na pangalan
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SizedBox.expand(
        child: Image.asset(
          "assets/loadingscreen.png", // iyong buong picture
          fit: BoxFit.cover,          // buong screen
        ),
      ),
    );
  }
}
