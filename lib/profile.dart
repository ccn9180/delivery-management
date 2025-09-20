import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

class Profile extends StatefulWidget {
  // callback for updated image
  final void Function(String)? onImageChanged;

  const Profile({super.key, this.onImageChanged});

  @override
  State<Profile> createState() => _ProfileState();
}

class _ProfileState extends State<Profile> {
  File? _image;
  String? _profileImageUrl;
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

  // Load profile data from Firestore
  Future<void> _loadProfile() async {
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        String employeeID = data['employeeID'] ?? '';

        int deliveredCount = 0;
        if (employeeID.isNotEmpty) {
          final querySnapshot = await FirebaseFirestore.instance
              .collection('delivery')
              .where('employeeID', isEqualTo: employeeID)
              .where('status', isEqualTo: 'Delivered')
              .get();
          deliveredCount = querySnapshot.docs.length;
        }

        setState(() {
          _displayName = data['name'] as String?;
          _profileImageUrl =
              (data['profileImage'] as String?)?.isNotEmpty == true
              ? data['profileImage']
              : null;
          _employeeID = data['employeeID'] ?? 'Not set';
          _phoneNum = data['phoneNumber'] ?? 'Not set';
          _deliveredCount = deliveredCount;
        });
      }
    } catch (e) {
      print('Error loading profile: $e');
    }
  }

  // Image provider for CircleAvatar
  ImageProvider? get profileImageProvider {
    if (_image != null) return FileImage(_image!);
    if (_profileImageUrl == null) return null;
    return useBase64ForTesting
        ? Image.memory(base64Decode(_profileImageUrl!)).image
        : null;
  }

  // upload image
  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null && user != null) {
      setState(() => _image = File(pickedFile.path));

      try {
        final bytes = await _image!.readAsBytes();
        final imageDecoded = img.decodeImage(bytes);
        if (imageDecoded == null) throw "Failed to decode image";

        final resized = img.copyResize(imageDecoded, width: 500);
        final compressedBytes = img.encodeJpg(resized, quality: 60);
        final imageToSave = base64Encode(compressedBytes);

        await FirebaseFirestore.instance
            .collection('users')
            .doc(user!.uid)
            .set({
              "profileImage": imageToSave,
              "name": _displayName ?? user!.displayName ?? "User Name",
              "employeeID": _employeeID,
            }, SetOptions(merge: true));

        setState(() => _profileImageUrl = imageToSave);
        widget.onImageChanged?.call(imageToSave);

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Profile image updated!")));
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
      return Scaffold(body: Center(child: CircularProgressIndicator()));
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
        title: Text(
          "Profile",
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
        ),
      ),
      body: SafeArea(
        child: Container(
          color: Colors.white,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 10, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: GestureDetector(
                    onTap: _pickAndUploadImage,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        double avatarSize =
                            MediaQuery.of(context).size.width * 0.4;
                        return Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            Container(
                              width: avatarSize,
                              height: avatarSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.grey.shade300,
                                  width: 2,
                                ),
                              ),
                              child: ClipOval(
                                child: profileImageProvider != null
                                    ? Image(
                                        image: profileImageProvider!,
                                        fit: BoxFit.cover,
                                        width: avatarSize,
                                        height: avatarSize,
                                      )
                                    : Container(
                                        color: Colors.white,
                                        alignment: Alignment.center,
                                        child: Icon(
                                          Icons.person,
                                          size: avatarSize * 0.6,
                                          color: Color(0xFF1B6C07),
                                        ),
                                      ),
                              ),
                            ),
                            // Edit icon
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                    width: 2,
                                  ),
                                ),
                                child: Icon(
                                  Icons.edit,
                                  size: 20,
                                  color: Colors.green,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                SizedBox(height: MediaQuery.of(context).size.height * 0.03),

                // Info cards
                _buildInfoCard(
                  Icons.person,
                  "Name",
                  _displayName ?? "User Name",
                ),
                _buildInfoCard(
                  Icons.badge,
                  "Employee ID",
                  _employeeID ?? "Not set",
                ),
                _buildInfoCard(
                  Icons.phone,
                  "Phone Number",
                  _phoneNum ?? "Not set",
                ),
                _buildInfoCard(
                  Icons.local_shipping,
                  "Total Deliveries",
                  _deliveredCount ?? 0,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Generic info card
  Widget _buildInfoCard(IconData icon, String title, dynamic value) {
    return Card(
      margin: EdgeInsets.symmetric(
        vertical: MediaQuery.of(context).size.height * 0.01,
        horizontal: 0,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: Colors.green),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(value?.toString() ?? "Not set"),
      ),
    );
  }
}
