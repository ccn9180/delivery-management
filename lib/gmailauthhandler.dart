import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'changepassword.dart';

class GmailAuthHandler extends StatefulWidget {
  const GmailAuthHandler({super.key});

  @override
  State<GmailAuthHandler> createState() => _GmailAuthHandlerState();
}

class _GmailAuthHandlerState extends State<GmailAuthHandler> {
  @override
  void initState() {
    super.initState();
    // Start authentication immediately when the screen loads
    _startAuthentication();
  }

  Future<void> _startAuthentication() async {
    try {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) {
        Navigator.pop(context);
        return;
      }

      final GoogleSignIn googleSignIn = GoogleSignIn();
      await googleSignIn.signOut(); // Force account picker

      final GoogleSignInAccount? account = await googleSignIn.signIn();
      if (account == null) {
        Navigator.pop(context);
        return;
      }

      // Check email match
      if (account.email.toLowerCase() != user.email!.toLowerCase()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selected Google account does not match your signed-in email.')),
        );
        Navigator.pop(context);
        return;
      }

      // Reauthenticate with Firebase
      final GoogleSignInAuthentication auth = await account.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        idToken: auth.idToken,
        accessToken: auth.accessToken,
      );
      await user.reauthenticateWithCredential(credential);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const ChangePasswordPage()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Re-authentication failed: $e')),
      );
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
            const Text('Re-authenticating with Google...', style: TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}