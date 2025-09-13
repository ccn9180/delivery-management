import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

class Profile extends StatefulWidget {
  final void Function(String)? onImageChanged; // callback

  const Profile({super.key, this.onImageChanged});
  @override
  State<Profile> createState() => _ProfileState();
}

class _ProfileState extends State<Profile> {
  File? _image;
  String? _profileImageUrl; // Base64
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
          _employeeID = data['employeeID'] ?? 'Not set';
          _phoneNum = data['phoneNumber'] ?? 'Not set';
          _deliveredCount = data['deliveredCount'] ?? 0;
        });
      }
    } catch (e) {
      print('Error loading profile: $e');
    }
  }

  /// Get ImageProvider for CircleAvatar
  ImageProvider? get profileImageProvider {
    if (_image != null) return FileImage(_image!);
    if (_profileImageUrl == null) return null;
    return useBase64ForTesting
        ? Image.memory(base64Decode(_profileImageUrl!)).image
        : null;
  }

  /// Pick image, compress, convert to Base64, and update Firestore
  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null && user != null) {
      setState(() => _image = File(pickedFile.path));

      try {
        // Read image bytes
        final bytes = await _image!.readAsBytes();

        // Decode and compress
        final imageDecoded = img.decodeImage(bytes);
        if (imageDecoded == null) throw "Failed to decode image";

        final resized = img.copyResize(imageDecoded, width: 500); // Resize
        final compressedBytes = img.encodeJpg(resized, quality: 60); // Compress

        // Encode to Base64
        final imageToSave = base64Encode(compressedBytes);

        // Save to Firestore
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user!.uid)
            .set({
          "profileImage": imageToSave,
          "name": _displayName ?? user!.displayName ?? "User Name",
          "employeeID": _employeeID
        }, SetOptions(merge: true));

        // Update UI
        setState(() {
          _profileImageUrl = imageToSave;
        });

        if (widget.onImageChanged != null && imageToSave != null) {
          widget.onImageChanged!(imageToSave);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Profile image updated!")),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error updating profile image: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_displayName == null) {
      return const Scaffold(
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
          padding: const EdgeInsets.all(12),
          child: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.black),
          ),
        ),
        title: const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text(
            "Profile",
            style: TextStyle(
                color: Color(0xFF1B6C07),
                fontWeight: FontWeight.bold,
                fontSize: 24),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 30),
            Center(
              child: GestureDetector(
                onTap: _pickAndUploadImage,
                child: Container(
                  padding: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    shape: BoxShape.circle,
                  ),
                  child: CircleAvatar(
                    radius: 80,
                    backgroundColor: Colors.white,
                    backgroundImage: profileImageProvider,
                    child: profileImageProvider == null
                        ? const Icon(Icons.person,
                        size: 100, color: Color(0xFF1B6C07))
                        : null,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 60),
            Table(
              columnWidths: const {
                0: FixedColumnWidth(200),
                1: FlexColumnWidth(),
              },
              children: [
                _buildTableRow('Name', _displayName ?? 'User Name'),
                _buildSpacerRow(),
                _buildTableRow('EmployeeID', _employeeID ?? 'Employee ID'),
                _buildSpacerRow(),
                _buildTableRow('Phone Number', _phoneNum ?? 'Phone Number'),
                _buildSpacerRow(),
                _buildTableRow('Total Delivery Completed',
                    (_deliveredCount?.toString() ?? '0')),
                _buildSpacerRow(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  TableRow _buildTableRow(String title, String value) {
    return TableRow(children: [
      Text(title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      Align(
          alignment: Alignment.centerLeft,
          child: Text(value, style: const TextStyle(fontSize: 16))),
    ]);
  }

  TableRow _buildSpacerRow() {
    return const TableRow(children: [
      SizedBox(height: 15),
      SizedBox(height: 15),
    ]);
  }
}
