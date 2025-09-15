import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  // Stream of notifications that are visible now
  Stream<QuerySnapshot> _notificationStream() async* {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      yield* const Stream.empty();
      return;
    }

    final userDoc = await FirebaseFirestore.instance
        .collection("users")
        .doc(user.uid)
        .get();

    if (!userDoc.exists) {
      yield* const Stream.empty();
      return;
    }

    final employeeId = userDoc.data()?["employeeID"];
    if (employeeId == null) {
      yield* const Stream.empty();
      return;
    }

    // Fetch notifications that should be visible now
    yield* FirebaseFirestore.instance
        .collection("notifications")
        .where("employeeID", isEqualTo: employeeId)
        .where("showAt", isLessThanOrEqualTo: Timestamp.now())
        .orderBy("showAt", descending: true)
        .snapshots();
  }

  // Mark notification as read
  Future<void> _markAsRead(String docId) async {
    await FirebaseFirestore.instance
        .collection("notifications")
        .doc(docId)
        .update({"isRead": true});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B6C07),
        leading: const BackButton(color: Colors.white),
        title: const Text(
          "Notifications",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _notificationStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No notifications yet."));
          }

          final notifications = snapshot.data!.docs;

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: notifications.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, index) {
              final doc = notifications[index];
              final data = doc.data() as Map<String, dynamic>;
              final title = data["title"] ?? "No Title";
              final body = data["body"] ?? "No Content";
              final isRead = data["isRead"] ?? false;
              final showAt = (data["showAt"] as Timestamp?)?.toDate();

              return ListTile(
                leading: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.notifications_none,
                      color: Colors.grey,
                      size: 28,
                    ),
                    if (!isRead)
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
                ),
                title: Text(
                  title,
                  style: TextStyle(
                    fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: showAt != null
                    ? Text(
                  "${showAt.hour}:${showAt.minute.toString().padLeft(2, '0')}",
                  style: const TextStyle(color: Colors.grey),
                )
                    : null,
                onTap: () async {
                  if (!isRead) {
                    await _markAsRead(doc.id);
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}
