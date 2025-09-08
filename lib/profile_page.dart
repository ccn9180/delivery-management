import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


import 'dart:io';
import 'login_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  File? _image;
  String? _profileImageUrl;
  String? _displayName;
  final user =FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    if (user==null) return;

    final doc = await FirebaseFirestore.instance.collection("users").doc(user!.uid).get();
    if (doc.exists && doc.data()!["profileImage"] != null) {
      final data = doc.data()!;
      setState(() {
        _profileImageUrl = data["profileImage"];
        _displayName = data["name"];
      });
    }
  }


  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
      });
      await _uploadImageToFirestore();
    }
  }

  Future<void> _uploadImageToFirestore() async {
    if (_image == null || user == null) return;

    try {
      final storageRef = FirebaseStorage.instance
          .ref()
          .child("profile_images")
          .child("${user!.uid}.jpg");

      await storageRef.putFile(_image!);

      final downloadUrl = await storageRef.getDownloadURL();

      await FirebaseFirestore.instance.collection("users").doc(user!.uid).set({
        "email": user!.email,
        "profileImage": downloadUrl,
        "name": user!.displayName ?? "name",
      }, SetOptions(merge: true));

      setState(() {
        _profileImageUrl = downloadUrl;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Profile image updated!")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B6C07), // Green background
      body: Column(
        children: <Widget>[
          // Green header with profile info
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 30.0),
            child: Column(
              children: [
                const SizedBox(height: 70),
                GestureDetector(
                  onTap: _pickImage,
                  child: CircleAvatar(
                    radius: 63,
                    backgroundColor: Colors.white,
                    backgroundImage: _image != null
                        ? FileImage(_image!)
                        : (_profileImageUrl != null ? NetworkImage(_profileImageUrl!) as ImageProvider : null),
                    child: (_image == null && _profileImageUrl == null)
                        ? const Icon(Icons.person, size: 87, color: Color(0xFF1B6C07))
                        : null,
                  ),
                ),
                const SizedBox(height: 15),
                Text(
                  _displayName ?? user?.displayName ?? 'User Name',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  user?.email ?? 'email',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),

          // White rounded section
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
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 30.0),
                children: <Widget>[
                  ListTile(
                    leading: const Icon(Icons.person_outline, color: Color(0xFF1B6C07)),
                    title: const Text('Profile'),
                    onTap: () {},
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.vpn_key_outlined, color: Color(0xFF1B6C07)),
                    title: const Text('Change Password'),
                    onTap: () {},
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.logout, color: Color(0xFF1B6C07)),
                    title: const Text('Log Out'),
                    onTap: () async {
                      await FirebaseAuth.instance.signOut();
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (context) => const LoginPage()),
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
