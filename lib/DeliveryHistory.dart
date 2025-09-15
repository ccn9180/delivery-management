import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delivery/widget/header.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'homepage.dart'; // deliveryCard widget

Stream<List<Delivery>> fetchAllDeliveries() async* {
  final employeeCode = await fetchEmployeeCode();
  if (employeeCode == null) {
    yield [];
    return;
  }

  yield* FirebaseFirestore.instance
      .collection('delivery')
      .where('employeeID', isEqualTo: employeeCode)
      .snapshots()
      .map((snapshot) =>
      snapshot.docs.map((doc) => Delivery.fromDoc(doc)).toList());
}

class DeliveryHistory extends StatefulWidget {
  const DeliveryHistory({super.key});

  @override
  State<DeliveryHistory> createState() => _DeliveryHistoryState();
}

class _DeliveryHistoryState extends State<DeliveryHistory> {
  String _searchQuery = "";
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PageHeader(title: "Delivery History"),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Column(
                  children: [
                    // Search bar
                    SizedBox(
                      width: width,
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: "Search by Delivery ID or Date",
                          prefixIcon: const Icon(Icons.search, color: Colors.grey),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.calendar_today, color: Colors.grey),
                            onPressed: () async {
                              final pickedDate = await showDatePicker(
                                context: context,
                                initialDate: DateTime.now(),
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (pickedDate != null) {
                                final formattedDate =
                                DateFormat('dd/MM/yyyy').format(pickedDate);
                                setState(() {
                                  _searchQuery = formattedDate.toLowerCase();
                                  _searchCtrl.text = formattedDate;
                                });
                              }
                            },
                          ),
                          filled: true,
                          fillColor: Colors.grey[100],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value.trim().toLowerCase();
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 12),

                    // List of deliveries
                    Expanded(
                      child: StreamBuilder<List<Delivery>>(
                        stream: fetchAllDeliveries(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }

                          if (!snapshot.hasData || snapshot.data!.isEmpty) {
                            return _emptyState();
                          }

                          final delivered = snapshot.data!
                              .where((d) => d.status == 'Delivered')
                              .toList();

                          if (delivered.isEmpty) return _emptyState();

                          final dateFormat = DateFormat('dd/MM/yyyy');
                          final timeFormat = DateFormat('hh:mm a');

                          List<Map<String, String>> mappedDeliveries = delivered.map(
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

                          if (_searchQuery.isNotEmpty) {
                            mappedDeliveries = mappedDeliveries.where((d) {
                              return d['code']!.toLowerCase().contains(_searchQuery) ||
                                  d['date']!.toLowerCase().contains(_searchQuery);
                            }).toList();
                          }

                          if (mappedDeliveries.isEmpty) {
                            return Center(
                              child: Text(
                                "No matching deliveries found",
                                style: TextStyle(
                                    fontSize: 16, color: Colors.grey.shade600),
                              ),
                            );
                          }

                          // Use GridView on wide screens
                          final isWide = width > 600;

                          return isWide
                              ? GridView.builder(
                            gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 16,
                              crossAxisSpacing: 16,
                              childAspectRatio: 3.5,
                            ),
                            itemCount: mappedDeliveries.length,
                            itemBuilder: (context, index) {
                              final d = mappedDeliveries[index];
                              return deliveryCard(
                                context: context,
                                image: d['image']!,
                                status: d['status']!,
                                code: d['code']!,
                                date: d['date']!,
                                time: d['time']!,
                                address: d['address']!,
                              );
                            },
                          )
                              : ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: mappedDeliveries.length,
                            itemBuilder: (context, index) {
                              final d = mappedDeliveries[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 16),
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
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
}
