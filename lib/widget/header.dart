import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PageHeader extends StatelessWidget {
  final String title;
  final Widget? extraWidget;

  const PageHeader({super.key, required this.title,this.extraWidget});

  Stream<String?> _profileImageStream(String uid) {
    return FirebaseFirestore.instance
        .collection("users")
        .doc(uid)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      final data = doc.data()!;
      final url = (data["profileImage"] as String?)?.isNotEmpty == true
          ? data["profileImage"]
          : null;
      return url;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return _buildHeader(context, null, isLoading: false);
    }

    return StreamBuilder<String?>(
      stream: _profileImageStream(user.uid),
      builder: (context, snapshot) {
        final url = snapshot.data;
        final isLoading = snapshot.connectionState == ConnectionState.waiting;

        ImageProvider? provider;
        if (url != null && url.isNotEmpty) {
          provider = url.startsWith("http")
              ? NetworkImage(url)
              : MemoryImage(base64Decode(url));
        }

        return _buildHeader(context, provider, isLoading: isLoading);
      },
    );
  }

  Widget _buildHeader(BuildContext context, ImageProvider? provider,
      {bool isLoading = false}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(25, 22, 18, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1B6C07),
            ),
          ),
          Row(
            children: [
              if (extraWidget != null) ...[
                extraWidget!,
                const SizedBox(width: 12),
              ],
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      spreadRadius: 1,
                      blurRadius: 2,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.white,
                  backgroundImage: provider,
                  child: isLoading
                      ? const CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF1B6C07))
                      : (provider == null
                      ? const Icon(Icons.person,
                      color: Color(0xFF1B6C07), size: 27)
                      : null),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}