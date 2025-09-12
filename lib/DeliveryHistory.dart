import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delivery/widget/header.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'homepage.dart'; // for deliveryCard widget

class DeliveryHistory extends StatelessWidget {
  const DeliveryHistory({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PageHeader(title: "Delivery History"),
            const SizedBox(height: 10),

            Expanded(
              child: StreamBuilder<List<Delivery>>(
                stream: fetchEmployeeDeliveries(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inbox, size: 60, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(
                            "No delivered deliveries yet",
                            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    );
                  }

                  // Filter only Delivered deliveries
                  final delivered = snapshot.data!
                      .where((d) => d.status == 'Delivered')
                      .toList();

                  if (delivered.isEmpty) {
                    return Center(
                      child: Text(
                        "No delivered deliveries yet",
                        style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                      ),
                    );
                  }

                  final dateFormat = DateFormat('dd/MM/yyyy');
                  final timeFormat = DateFormat('HH:mm');

                  List<Map<String, String>> mapList(List<Delivery> list) => list.map(
                        (d) => {
                      'code': d.code,
                      'address': d.address,
                      'date': dateFormat.format(d.date),
                      'time': timeFormat.format(d.date),
                      'status': d.status,
                      'image': d.items.isNotEmpty
                          ? (d.items.first['imageUrl']?.toString() ??
                          'assets/images/EngineOils.jpg')
                          : 'assets/images/EngineOils.jpg',
                    },
                  ).toList();

                  final mappedDeliveries = mapList(delivered);

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: mappedDeliveries.length,
                    itemBuilder: (context, index) {
                      final d = mappedDeliveries[index];
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(7, 0, 7, 16),
                        child: deliveryCard(
                          context: context,
                          image: d['image']!,
                          status: d['status']!,
                          code: d['code']!,
                          date: d['date']!,
                          time: d['time']!,
                          address: d['address']!,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
