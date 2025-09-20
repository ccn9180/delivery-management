import 'package:delivery/gmailauthhandler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'profile.dart';
import 'login_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String? _profileImageUrl;
  String? _displayName;
  final user = FirebaseAuth.instance.currentUser;
  final bool useBase64ForTesting = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  //for update image
  void _updateProfileImage(String newImage) {
    setState(() => _profileImageUrl = newImage);
  }

  ImageProvider? get profileImageProvider {
    if (_profileImageUrl == null) return null;
    return useBase64ForTesting
        ? Image.memory(base64Decode(_profileImageUrl!)).image
        : NetworkImage(_profileImageUrl!);
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
          _profileImageUrl =
              (data["profileImage"] as String?)?.isNotEmpty == true
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
    if (_isLoading) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator(color: Colors.green)),
      );
    }

    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Color(0xFF1B6C07),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: EdgeInsets.symmetric(vertical: screenHeight * 0.03),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: screenWidth * 0.16,
                    backgroundColor: Colors.white,
                    backgroundImage: profileImageProvider,
                    child: profileImageProvider == null
                        ? Icon(
                            Icons.person,
                            size: screenWidth * 0.22,
                            color: Color(0xFF1B6C07),
                          )
                        : null,
                  ),
                  SizedBox(height: screenHeight * 0.015),
                  Text(
                    _displayName ?? 'User Name',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: screenHeight * 0.028,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.005),
                  Text(
                    user?.email ?? 'email',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: screenHeight * 0.018,
                    ),
                  ),
                ],
              ),
            ),

            //for below container
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(30),
                    topRight: Radius.circular(30),
                  ),
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: screenWidth * 0.05,
                    vertical: screenHeight * 0.03,
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(
                          Icons.person_outline,
                          color: Color(0xFF1B6C07),
                          size: screenWidth * 0.07,
                        ),
                        title: Text(
                          'Profile',
                          style: TextStyle(fontSize: screenHeight * 0.022),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  Profile(onImageChanged: _updateProfileImage),
                            ),
                          );
                        },
                      ),
                      Divider(height: screenHeight * 0.01, thickness: 1),
                      ListTile(
                        leading: Icon(
                          Icons.vpn_key_outlined,
                          color: Color(0xFF1B6C07),
                          size: screenWidth * 0.07,
                        ),
                        title: Text(
                          'Change Password',
                          style: TextStyle(fontSize: screenHeight * 0.022),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => GmailAuthHandler(),
                            ),
                          );
                        },
                      ),
                      Divider(height: screenHeight * 0.01, thickness: 1),
                      ListTile(
                        leading: Icon(
                          Icons.logout,
                          color: Color(0xFF1B6C07),
                          size: screenWidth * 0.07,
                        ),
                        title: Text(
                          'Log Out',
                          style: TextStyle(fontSize: screenHeight * 0.022),
                        ),
                        onTap: () async {
                          await FirebaseAuth.instance.signOut();
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (context) => LoginPage(),
                            ),
                            (route) => false, // remove all previous routes
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
