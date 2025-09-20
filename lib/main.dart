import 'package:delivery/welcome.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'homepage.dart';
import 'login_page.dart';


class Wrapper extends StatelessWidget {
  const Wrapper({super.key});

  Future<bool> _isFirstRun() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenWelcome = prefs.getBool('hasSeenWelcome') ?? false;
    return !hasSeenWelcome;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isFirstRun(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: Colors.green)),
          );
        }

        final firstRun = snapshot.data!;
        if (firstRun) {
          return WelcomePage(
            onFinished: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('hasSeenWelcome', true);

              // After onboarding, go to LoginPage
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginPage()),
              );
            },
          );
        }

        // Not first run → use auth state
        return StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator(color: Colors.green)),
              );
            }

            if (snapshot.hasData) {
              return const HomePage(); // logged in
            } else {
              return const LoginPage(); // logged out
            }
          },
        );
      },
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Firebase.apps.isEmpty
          ? Firebase.initializeApp(
              options: DefaultFirebaseOptions.currentPlatform,
            )
          : Future.value(Firebase.app()),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'SPMS',
            theme: ThemeData(primarySwatch: Colors.green),
            home: const Wrapper(),
          );
        }

        if (snapshot.hasError) {
          return MaterialApp(
            home: Scaffold(
              body: Center(
                child: Text('Firebase initialization error: ${snapshot.error}'),
              ),
            ),
          );
        }

        return const MaterialApp(
          home: Scaffold(body: Center(child: CircularProgressIndicator())),
        );
      },
    );
  }
}
