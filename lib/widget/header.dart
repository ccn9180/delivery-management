import 'dart:async';
import 'package:delivery/notication.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PageHeader extends StatefulWidget {
  final String title;
  final Widget? extraWidget;

  const PageHeader({super.key, required this.title, this.extraWidget});

  @override
  State<PageHeader> createState() => _PageHeaderState();
}

class _PageHeaderState extends State<PageHeader> {
  String? employeeId;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fetchEmployeeId();
    // Refresh every 30 seconds to catch showAt changes
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchEmployeeId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = await FirebaseFirestore.instance
        .collection("users")
        .doc(user.uid)
        .get();

    setState(() {
      employeeId = userDoc.data()?["employeeID"];
    });
  }

  void _onNotificationTap() {
    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const NotificationsPage()),
      );
    }
  }

  // Returns the number of unread notifications whose showAt <= now
  int _countUnread(List<QueryDocumentSnapshot> docs) {
    final now = DateTime.now();
    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final isRead = data['isRead'] ?? false;
      final showAt = (data['showAt'] as Timestamp?)?.toDate();
      return !isRead && (showAt == null || !showAt.isAfter(now));
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(25, 22, 18, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            widget.title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1B6C07),
            ),
          ),
          Row(
            children: [
              if (widget.extraWidget != null) ...[
                widget.extraWidget!,
                const SizedBox(width: 12),
              ],
              if (employeeId == null)
                IconButton(
                  icon: const Icon(
                    Icons.notifications,
                    color: Color(0xFF1B6C07),
                    size: 28,
                  ),
                  onPressed: _onNotificationTap,
                )
              else
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection("notifications")
                      .where("employeeID", isEqualTo: employeeId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    final unreadCount = snapshot.hasData
                        ? _countUnread(snapshot.data!.docs)
                        : 0;

                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                spreadRadius: 1,
                                blurRadius: 2,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: IconButton(
                            icon: const Icon(
                              Icons.notifications,
                              color: Color(0xFF1B6C07),
                              size: 28,
                            ),
                            onPressed: _onNotificationTap,
                          ),
                        ),
                        if (unreadCount > 0)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}
