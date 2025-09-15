import 'package:delivery/gmailauthservice.dart';
import 'package:flutter/material.dart';
import 'changepassword.dart'; // Adjust path based on your folder structure

class GmailAuthHandler extends StatefulWidget {
  const GmailAuthHandler({super.key});

  @override
  State<GmailAuthHandler> createState() => _GmailAuthHandlerState();
}

class _GmailAuthHandlerState extends State<GmailAuthHandler> {
  final GmailAuthService _authService = GmailAuthService();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Start authentication immediately when the screen loads
    _startAuthentication();
  }

  Future<void> _startAuthentication() async {
    final bool isAuthenticated = await _authService.authenticateWithGmail();

    if (isAuthenticated) {
      // Authentication successful, navigate to change password page
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const ChangePasswordPage()),
      );
    } else {
      // Authentication failed, go back to previous screen
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              _isLoading ? 'Redirecting to Gmail...' : 'Authentication completed',
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}