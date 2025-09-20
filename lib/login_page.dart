import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'homepage.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _passwordVisible = false;
  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Welcome back, ${userCredential.user!.email}!")),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomePage()),
      );
    } on FirebaseAuthException catch (e) {
      setState(() {
        if (e.code == 'user-not-found') {
          _errorMessage = 'No user found for that email.';
        } else if (e.code == 'wrong-password') {
          _errorMessage = 'Wrong password provided.';
        } else if (e.code == 'invalid-email') {
          _errorMessage = 'The email address is badly formatted.';
        } else if (e.code == 'invalid-credential') {
          _errorMessage = 'Invalid email or password. Please try again.';
        } else {
          _errorMessage = 'Login failed. Please try again later.';
        }
      });
    } catch (_) {
      setState(() {
        _errorMessage = "Something went wrong. Try again later.";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _forgotPassword() async {
    if (_emailController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter your email first")),
      );
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: _emailController.text.trim(),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Password reset email sent! Check your inbox."),
        ),
      );
    } on FirebaseAuthException catch (e) {
      String message = 'Something went wrong. Try again.';
      if (e.code == 'invalid-email') {
        message = 'Invalid email. Please try again!';
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Color(0xFFEFFAEF)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.08,
                  vertical: 12,
                ),

                // scroll moves up when keyboard opens
                reverse: true,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      // Push content up when keyboard appears
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).viewInsets.bottom,
                      ),
                      child: Column(
                        children: [
                          SizedBox(height: screenHeight * 0.15),
                          // Logo
                          Image.asset(
                            'assets/images/SWPS.png',
                            height: screenHeight * 0.18,
                          ),
                          SizedBox(height: screenHeight * 0.03),

                          // Title
                          Text(
                            "Login to SPMS",
                            style: TextStyle(
                              fontSize: screenHeight * 0.035,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1B6C07),
                            ),
                          ),
                          SizedBox(height: screenHeight * 0.04),

                          // Form
                          Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                // Email
                                TextFormField(
                                  controller: _emailController,
                                  focusNode: _emailFocus,
                                  textInputAction: TextInputAction.next,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: _inputDecoration(
                                    "Email",
                                    screenHeight,
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Email is required';
                                    }
                                    if (!RegExp(
                                      r'^[^@]+@[^@]+\.[^@]+',
                                    ).hasMatch(value)) {
                                      return 'Enter a valid email';
                                    }
                                    return null;
                                  },
                                  onFieldSubmitted: (_) {
                                    FocusScope.of(
                                      context,
                                    ).requestFocus(_passwordFocus);
                                  },
                                ),
                                SizedBox(height: screenHeight * 0.02),

                                // Password
                                TextFormField(
                                  controller: _passwordController,
                                  focusNode: _passwordFocus,
                                  obscureText: !_passwordVisible,
                                  decoration:
                                      _inputDecoration(
                                        "Password",
                                        screenHeight,
                                      ).copyWith(
                                        suffixIcon: IconButton(
                                          icon: Icon(
                                            _passwordVisible
                                                ? Icons.visibility
                                                : Icons.visibility_off,
                                            color: Colors.black54,
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              _passwordVisible =
                                                  !_passwordVisible;
                                            });
                                          },
                                        ),
                                      ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Password is required';
                                    }
                                    return null;
                                  },
                                  onFieldSubmitted: (_) => _login(),
                                ),

                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: _forgotPassword,
                                    child: Text(
                                      'Forgot Password?',
                                      style: TextStyle(
                                        color: Color(0xFF1B6C07),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(height: screenHeight * 0.04),

                                // Login button
                                ElevatedButton(
                                  onPressed: _isLoading ? null : _login,
                                  style: ElevatedButton.styleFrom(
                                    elevation: 6,
                                    backgroundColor: const Color(0xFF1B6C07),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: screenWidth * 0.15,
                                      vertical: screenHeight * 0.02,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(25),
                                    ),
                                  ),
                                  child: _isLoading
                                      ? SizedBox(
                                          width: screenWidth * 0.06,
                                          height: screenWidth * 0.06,
                                          child:
                                              const CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2,
                                              ),
                                        )
                                      : Text(
                                          'LOGIN',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: screenHeight * 0.025,
                                          ),
                                        ),
                                ),

                                SizedBox(height: screenHeight * 0.02),

                                if (_errorMessage.isNotEmpty)
                                  Text(
                                    _errorMessage,
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontSize: screenHeight * 0.018,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, double screenHeight) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        fontSize: screenHeight * 0.02,
        color: Colors.black54,
      ),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18.0),
        borderSide: BorderSide.none,
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: 20.0,
        vertical: screenHeight * 0.02,
      ),
    );
  }
}
