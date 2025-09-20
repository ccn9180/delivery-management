import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // FocusNodes
  final _oldFocus = FocusNode();
  final _newFocus = FocusNode();
  final _confirmFocus = FocusNode();

  bool _loading = false;

  // Visibility toggles
  bool _oldVisible = false;
  bool _newVisible = false;
  bool _confirmVisible = false;

  void _showSnack(String message, {Color color = Colors.red}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) {
        _showSnack("No user logged in.");
        return;
      }

      // Reauthenticate
      final cred = EmailAuthProvider.credential(
        email: user.email!,
        password: _oldPasswordController.text.trim(),
      );
      await user.reauthenticateWithCredential(cred);

      // Update password
      await user.updatePassword(_newPasswordController.text.trim());

      _showSnack("Password updated successfully!", color: Colors.green);
      Navigator.pop(context, true);
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case "wrong-password":
        case "invalid-credential":
        case "invalid-login-credentials":
          _showSnack("Old password is incorrect.");
          break;

        case "weak-password":
          _showSnack("New password is too weak (min 6 characters).");
          break;

        case "requires-recent-login":
          _showSnack("Please log in again before changing your password.");
          break;

        default:
          _showSnack("Error: ${e.message}");
      }
    } catch (e) {
      _showSnack("Unexpected error: $e");
    } finally {
      setState(() => _loading = false);
    }
  }

  // Reusable password field with visibility toggle + focus control
  Widget _buildPasswordField({
    required String label,
    required TextEditingController controller,
    required bool isVisible,
    required VoidCallback toggleVisibility,
    required String? Function(String?) validator,
    required FocusNode focusNode,
    FocusNode? nextFocus,
    bool isLast = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 6, top: 10),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
        ),
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          obscureText: !isVisible,
          validator: validator,
          textInputAction: isLast ? TextInputAction.done : TextInputAction.next,
          onFieldSubmitted: (_) {
            if (!isLast && nextFocus != null) {
              FocusScope.of(context).requestFocus(nextFocus);
            } else {
              FocusScope.of(context).unfocus();
              _resetPassword();
            }
          },
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Color(0xFF1B6C07), width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.red, width: 2),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.red, width: 2),
            ),
            contentPadding:
            EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            suffixIcon: IconButton(
              icon: Icon(
                isVisible ? Icons.visibility : Icons.visibility_off,
                color: Colors.grey,
              ),
              onPressed: toggleVisibility,
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();

    _oldFocus.dispose();
    _newFocus.dispose();
    _confirmFocus.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 80,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Change Password",
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(30,10,30,10),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               Text(
                "Choose a New Password",
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
               SizedBox(height: 4),
               Text(
                "Enter and confirm your new password to regain access",
                style: TextStyle(
                  color: Colors.black54,
                  fontSize: 12.5,
                ),
              ),
               SizedBox(height: 25),

              // Old Password
              _buildPasswordField(
                label: "Old Password",
                controller: _oldPasswordController,
                isVisible: _oldVisible,
                toggleVisibility: () =>
                    setState(() => _oldVisible = !_oldVisible),
                validator: (value) =>
                value!.isEmpty ? "Enter your old password" : null,
                focusNode: _oldFocus,
                nextFocus: _newFocus,
              ),

              // New Password
              _buildPasswordField(
                label: "New Password",
                controller: _newPasswordController,
                isVisible: _newVisible,
                toggleVisibility: () =>
                    setState(() => _newVisible = !_newVisible),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return "Enter a new password";
                  }
                  if (value.length < 6) {
                    return "Password must be at least 6 characters";
                  }
                  return null;
                },
                focusNode: _newFocus,
                nextFocus: _confirmFocus,
              ),

              // Confirm Password
              _buildPasswordField(
                label: "Confirm New Password",
                controller: _confirmPasswordController,
                isVisible: _confirmVisible,
                toggleVisibility: () =>
                    setState(() => _confirmVisible = !_confirmVisible),
                validator: (value) {
                  if (value != _newPasswordController.text) {
                    return "Passwords do not match";
                  }
                  return null;
                },
                focusNode: _confirmFocus,
                isLast: true,
              ),
               SizedBox(height: 30),
            ],
          ),
        ),
      ),

      // reset button
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(30, 16, 30, 30),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _loading ? null : _resetPassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF1B6C07),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: _loading
                  ? CircularProgressIndicator(color: Colors.white)
                  : Text(
                "Reset Password",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}