import 'package:delivery/welcome.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'firebase_options.dart';
import 'homepage.dart';
import 'login_page.dart';
import 'google_map.dart';
import 'dart:io'; //for platform
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
  // This is the correct place to set it, before Firebase.initializeApp and runApp
  if (Platform.isAndroid) {
    // Choose one of these lines based on your testing:
    // AndroidGoogleMapsFlutter.useAndroidViewSurface = true; // Try this first (newer SurfaceView based Hybrid Composition)
    AndroidGoogleMapsFlutter.useAndroidViewSurface = false; // Or try this (older Virtual Display) if the above has issues

    // You might also need to initialize the Android-specific part of the maps plugin
    // if you are using a recent version and want to explicitly set the renderer.
    // However, just setting useAndroidViewSurface might be enough for what you're trying.
    // final GoogleMapsFlutterAndroid mapsImplementation = GoogleMapsFlutterAndroid();
    // mapsImplementation.initializeWithRenderer(AndroidMapRenderer.latest);
  }
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SWPS',
      theme: ThemeData(
        primarySwatch: Colors.green,
      ),

      home: const Wrapper(),
    );
  }
}