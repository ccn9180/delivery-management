import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delivery/widget/header.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'homepage.dart';

class DeliveryHistory extends StatefulWidget {
  const DeliveryHistory({super.key});

  @override
  State<DeliveryHistory> createState() => _DeliveryHistoryState();
}

class _DeliveryHistoryState extends State<DeliveryHistory> {
  String _searchQuery = "";
  DateTime? _pickedDate;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Stream<List<Delivery>> _fetchDeliveries() async* {
    final employeeCode = await fetchEmployeeCode();
    if (employeeCode == null) {
      yield [];
      return;
    }

    var query = FirebaseFirestore.instance
        .collection('delivery')
        .where('employeeID', isEqualTo: employeeCode)
        .where('status', isEqualTo: 'Delivered')
        .orderBy('deliveryDate', descending: true);

    if (_pickedDate != null) {
      final startOfDay = DateTime(_pickedDate!.year, _pickedDate!.month, _pickedDate!.day).toUtc();
      final endOfDay = DateTime(_pickedDate!.year, _pickedDate!.month, _pickedDate!.day, 23, 59, 59).toUtc();
      query = query
          .where('deliveryDate', isGreaterThanOrEqualTo: startOfDay)
          .where('deliveryDate', isLessThanOrEqualTo: endOfDay);
    }

    yield* query.snapshots().map(
            (snapshot) => snapshot.docs.map((doc) => Delivery.fromDoc(doc)).toList());
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

            // Search & date picker
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: "Search by Delivery ID or Date",
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.calendar_today, color: Colors.grey),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setState(() {
                          _pickedDate = picked;
                          _searchQuery = "";
                          _searchCtrl.text = DateFormat('dd/MM/yyyy').format(picked);
                        });
                      }
                    },
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.trim().toLowerCase();
                    _pickedDate = null; // reset date filter if typing
                  });
                },
              ),
            ),

            const SizedBox(height: 12),

            // Delivery list
            Expanded(
              child: StreamBuilder<List<Delivery>>(
                stream: _fetchDeliveries(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final deliveries = snapshot.data ?? [];

                  // Apply search filter
                  final filtered = _searchQuery.isNotEmpty
                      ? deliveries.where((d) =>
                  d.code.toLowerCase().contains(_searchQuery) ||
                      DateFormat('dd/MM/yyyy')
                          .format(d.date)
                          .toLowerCase()
                          .contains(_searchQuery))
                      .toList()
                      : deliveries;

                  if (filtered.isEmpty) {
                    return _emptyState();
                  }

                  // ✅ Wait for item preload before building UI
                  return FutureBuilder<void>(
                    future: preloadItems(filtered), // your preload method
                    builder: (context, preloadSnap) {
                      if (preloadSnap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final isWide = width > 600;
                      return isWide
                          ? GridView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: 3.5,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final d = filtered[index];
                          return deliveryCard(
                            context: context,
                            delivery: d,
                            date: DateFormat('dd/MM/yyyy').format(d.date),
                            time: DateFormat('hh:mm a').format(d.date),
                          );
                        },
                      )
                          : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final d = filtered[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: deliveryCard(
                              context: context,
                              delivery: d,
                              date: DateFormat('dd/MM/yyyy').format(d.date),
                              time: DateFormat('hh:mm a').format(d.date),
                            ),
                          );
                        },
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
