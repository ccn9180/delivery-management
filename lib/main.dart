import 'package:delivery/welcome.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'firebase_options.dart';
import 'homepage.dart';
import 'login_page.dart';
import 'dart:io';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';

class Wrapper extends StatelessWidget {
  const Wrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          return const HomePage(); // user logged in
        }
        return const WelcomePage(); // user not logged in
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
