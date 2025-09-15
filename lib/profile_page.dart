import 'package:delivery/gmailauthhandler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'dart:convert';
import 'profile.dart';
import 'changepassword.dart';
import 'login_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String? _profileImageUrl; // Can be URL or Base64
  String? _displayName;
  final user = FirebaseAuth.instance.currentUser;

  /// Toggle for free-tier testing (Base64) vs production (Storage URL)
  final bool useBase64ForTesting = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  // Callback function to update the image
  void _updateProfileImage(String newImage) {
    setState(() {
      _profileImageUrl = newImage;
    });
  }

  // Helper getter for CircleAvatar image
  ImageProvider? get profileImageProvider {
    if (_profileImageUrl == null) return null;
    return useBase64ForTesting
        ? Image.memory(base64Decode(_profileImageUrl!)).image
        : NetworkImage(_profileImageUrl!);
  }

  // Helper method for showing SnackBars
  void showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _loadUserProfile() async {
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection("users")
          .doc(user!.uid)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _profileImageUrl = (data["profileImage"] as String?)?.isNotEmpty == true
              ? data["profileImage"]
              : null;
          _displayName = data["name"] as String?;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print("Error loading profile: $e");
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B6C07),
      body: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Column(
              children: [
                const SizedBox(height: 70),
                CircleAvatar(
                  radius: 63,
                  backgroundColor: Colors.white,
                  backgroundImage: profileImageProvider,
                  child: profileImageProvider == null
                      ? const Icon(
                    Icons.person,
                    size: 87,
                    color: Color(0xFF1B6C07),
                  )
                      : null,
                ),
                const SizedBox(height: 15),
                Text(
                  _displayName ?? 'User Name',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  user?.email ?? 'email',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),

          // White section
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(30),
                  topRight: Radius.circular(30),
                ),
              ),
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 30,
                ),
                children: [
                  ListTile(
                    leading: const Icon(
                      Icons.person_outline,
                      color: Color(0xFF1B6C07),
                    ),
                    title: const Text('Profile'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => Profile(
                            onImageChanged: _updateProfileImage, // pass callback
                          ),
                        ),
                      );
                    },
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(
                      Icons.vpn_key_outlined,
                      color: Color(0xFF1B6C07),
                    ),
                    title: const Text('Change Password'),
                    onTap: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const GmailAuthHandler()),
                      );
                    },
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.logout, color: Color(0xFF1B6C07)),
                    title: const Text('Log Out'),
                    onTap: () async {
                      await FirebaseAuth.instance.signOut();
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const LoginPage(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
