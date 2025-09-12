import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class Profile extends StatefulWidget {
  const Profile({super.key});
  @override
  State<Profile> createState() => _ProfileState();
}

class _ProfileState extends State<Profile> {
  File? _image;
  String? _profileImageUrl; // Base64 or Storage URL
  String? _displayName;
  String? _employeeID;
  String? _phoneNum;
  int? _deliveredCount;
  final user = FirebaseAuth.instance.currentUser;
  final bool useBase64ForTesting = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  /// Load profile data from Firestore
  Future<void> _loadProfile() async {
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _displayName = data['name'] as String?;
          _profileImageUrl =
          (data['profileImage'] as String?)?.isNotEmpty == true
              ? data['profileImage']
              : null;
          _employeeID=data['employeeID']??'Not set';
          _phoneNum=data['phoneNumber']??'Not set';
          _deliveredCount=data['deliveredCount']??'Not set';
        });
      }
    } catch (e) {
      print('Error loading profile: $e');
    }
  }

  ImageProvider? get profileImageProvider {
    if (_image != null) return FileImage(_image!);
    if (_profileImageUrl == null) return null;
    return useBase64ForTesting
        ? Image.memory(base64Decode(_profileImageUrl!)).image
        : NetworkImage(_profileImageUrl!);
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null && user != null) {
      setState(() => _image = File(pickedFile.path));

      String? imageToSave;

      try {
        if (useBase64ForTesting) {
          final bytes = await _image!.readAsBytes();
          imageToSave = base64Encode(bytes);
        } else {
          final storageRef = FirebaseStorage.instance
              .ref()
              .child("profile_images")
              .child("${user!.uid}.jpg");
          final uploadTask = await storageRef.putFile(_image!);

          if (uploadTask.state == TaskState.success) {
            imageToSave = await storageRef.getDownloadURL();
          } else {
            throw "Upload failed";
          }
        }

        // Save to Firestore
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user!.uid)
            .set({
          "profileImage": imageToSave,
          "name":_displayName ?? user!.displayName ?? "User Name",
          "employeeID":_employeeID
        }, SetOptions(merge: true));

        // Update state
        setState(() {
          _profileImageUrl = imageToSave;
        });

        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Profile image updated!")));
      } catch (e) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_displayName == null) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 80,
        leading: Padding(
          padding: EdgeInsets.all(12),
          child: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.arrow_back, color: Colors.black),
          ),
        ),
        title: Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text(
            "Profile",
            style: TextStyle(
                color: Color(0xFF1B6C07),
                fontWeight: FontWeight.bold,
                fontSize: 24
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 30),
            Center(
              child: GestureDetector(
                onTap: _pickAndUploadImage,
                child: Container(
                  padding: EdgeInsets.all(1.5),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    shape: BoxShape.circle,
                  ),
                  child: CircleAvatar(
                    radius: 80,
                    backgroundColor: Colors.white,
                    backgroundImage: profileImageProvider,
                    child: profileImageProvider == null
                        ? Icon(Icons.person,
                        size: 100, color: Color(0xFF1B6C07))
                        : null,
                  ),
                ),
              ),
            ),
            SizedBox(height: 60),
            Table(
              columnWidths: const {
                0: FixedColumnWidth(200), // Left column fits content
                1: FlexColumnWidth(),      // Right column takes remaining space
              },
              children: [
                TableRow(
                  children: [
                    Text(
                      'Name',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _displayName ?? 'User Name',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
                TableRow(
                  children: [
                    SizedBox(height:15),
                    SizedBox(height:15),
                  ]
                ),
                TableRow(
                  children: [
                    Text(
                      'EmployeeID',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _employeeID ?? 'Employee ID',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
                TableRow(
                    children: [
                      SizedBox(height:15),
                      SizedBox(height:15),
                    ]
                ),
                TableRow(
                  children: [
                    Text(
                      'Phone Number',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _phoneNum ?? 'Phone Number',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
                TableRow(
                    children: [
                      SizedBox(height:15),
                      SizedBox(height:15),
                    ]
                ),
                TableRow(
                  children: [
                    Text(
                      'Total Delivery Completed',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        (_deliveredCount?.toString() ?? 'Count'),
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
                TableRow(
                    children: [
                      SizedBox(height:15),
                      SizedBox(height:15),
                    ]
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
