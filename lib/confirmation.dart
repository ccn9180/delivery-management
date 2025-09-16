import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'firebase_options.dart';

class ConfirmationPage extends StatefulWidget {
  final String? deliveryCode; // This matches what's passed from GoogleMapPage
  final String? deliveryAddress;
  final dynamic deliveryLocation;
  final String? deliveryStatus;
  final List<Map<String, dynamic>>? deliveryItems;

  const ConfirmationPage({
    super.key,
    this.deliveryCode,
    this.deliveryAddress,
    this.deliveryLocation,
    this.deliveryStatus,
    this.deliveryItems,
  });

  @override
  State<ConfirmationPage> createState() => _ConfirmationPageState();
}

class DeliveryPersonnel {
  final String name;
  final String email;
  final String employeeID;
  final String phoneNumber;

  DeliveryPersonnel({
    required this.name,
    required this.email,
    required this.employeeID,
    required this.phoneNumber,
  });

  factory DeliveryPersonnel.fromMap(Map<String, dynamic> m) => DeliveryPersonnel(
    name: m['name'] ?? '',
    email: m['email'] ?? '',
    employeeID: m['employeeID'] ?? '',
    phoneNumber: m['phoneNumber'] ?? '',
  );
}

class Recipient {
  final String name;
  final String email;
  final String address;

  Recipient({required this.name, required this.email, required this.address});

  factory Recipient.fromMap(Map<String, dynamic> m) => Recipient(
    name: m['recipientName'] ?? 'Customer',
    email: m['recipientEmail'] ?? '',
    address: m['address'] ?? 'Unknown Address',
  );
}

class DeliveryItem {
  final String itemID;
  final int quantity;

  DeliveryItem({
    required this.itemID,
    required this.quantity,
  });

  factory DeliveryItem.fromMap(Map<String, dynamic> m) => DeliveryItem(
    itemID: m['itemID'] ?? 'N/A',
    quantity: (m['quantity'] is int) ? m['quantity'] : int.tryParse(m['quantity'].toString()) ?? 0,
  );
}

class _ConfirmationPageState extends State<ConfirmationPage> {
  DeliveryPersonnel? deliveryPersonnel;
  Recipient? recipient;
  List<DeliveryItem> deliveryItems = [];
  String? deliveryDateFormatted;
  String? deliveryStatus;
  bool _isLoading = true;
  Map<String, dynamic>? deliveryData;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      // Initialize Firebase
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      // Debug print to check what delivery code we're looking for
      debugPrint("Looking for delivery with code: ${widget.deliveryCode}");

      if (widget.deliveryCode == null || widget.deliveryCode!.isEmpty) {
        if (mounted) {
          setState(() {
            errorMessage = 'Delivery code is missing';
            _isLoading = false;
          });
        }
        return;
      }

      // FIRST: Try to get the document directly using the deliveryCode as the document ID
      DocumentSnapshot deliveryDoc = await FirebaseFirestore.instance
          .collection('delivery')
          .doc(widget.deliveryCode) // Use the deliveryCode directly as document ID
          .get();

      // SECOND: If not found by ID, try to query by the 'code' field
      if (!deliveryDoc.exists) {
        debugPrint("Document not found by ID, trying query by 'code' field...");

        QuerySnapshot querySnapshot = await FirebaseFirestore.instance
            .collection('delivery')
            .where('code', isEqualTo: widget.deliveryCode)
            .limit(1)
            .get();

        if (querySnapshot.docs.isNotEmpty) {
          deliveryDoc = querySnapshot.docs.first;
          debugPrint("Found document via query with ID: ${deliveryDoc.id}");
        }
      } else {
        debugPrint("Found document directly with ID: ${deliveryDoc.id}");
      }

      if (deliveryDoc.exists) {
        deliveryData = deliveryDoc.data() as Map<String, dynamic>;

        // Debug print to see the actual data structure
        debugPrint("Document data keys: ${deliveryData!.keys.toList()}");
        debugPrint("Document data: $deliveryData");

        // Extract recipient info from delivery document
        recipient = Recipient.fromMap(deliveryData!);

        // Format delivery date
        if (deliveryData!['deliveryDate'] != null) {
          // Handle different date formats
          if (deliveryData!['deliveryDate'] is Timestamp) {
            final date = (deliveryData!['deliveryDate'] as Timestamp).toDate();
            deliveryDateFormatted = DateFormat('yyyy-MM-dd - HH:mm').format(date);
          } else if (deliveryData!['deliveryDate'] is String) {
            // Parse the string format "16 September 2025 at 00:10:10 UTC+8"
            try {
              final dateString = deliveryData!['deliveryDate'].replaceAll(' at ', ' ');
              final date = DateFormat('d MMMM yyyy HH:mm:ss').parse(dateString);
              deliveryDateFormatted = DateFormat('yyyy-MM-dd - HH:mm').format(date);
            } catch (e) {
              deliveryDateFormatted = deliveryData!['deliveryDate'];
            }
          }
        }

        // Get delivery status
        deliveryStatus = deliveryData!['status']?.toString() ?? 'Unknown Status';

        // Get employee ID and fetch personnel
        final String employeeID = deliveryData!['employedID']?.toString() ?? '';
        debugPrint("Looking for employee with ID: $employeeID");

        if (employeeID.isNotEmpty) {
          final personnelQuery = await FirebaseFirestore.instance
              .collection('users')
              .where('employeeID', isEqualTo: employeeID)
              .get();

          if (personnelQuery.docs.isNotEmpty) {
            deliveryPersonnel = DeliveryPersonnel.fromMap(personnelQuery.docs.first.data());
            debugPrint("Found delivery personnel: ${deliveryPersonnel!.name}");
          } else {
            debugPrint("No personnel found with employeeID: $employeeID");
          }
        }

        // Process delivery items - using the exact field names from your data
        final List<dynamic> itemsData = deliveryData!['deliveryItems'] ?? [];
        List<DeliveryItem> newDeliveryItems = [];
        debugPrint("Found ${itemsData.length} delivery items");

        for (var itemData in itemsData) {
          if (itemData is Map<String, dynamic>) {
            newDeliveryItems.add(DeliveryItem.fromMap(itemData));
          }
        }

        if (mounted) {
          setState(() {
            deliveryItems = newDeliveryItems;
            _isLoading = false;
          });
        }
      } else {
        // Document doesn't exist
        if (mounted) {
          setState(() {
            errorMessage = 'Delivery with code ${widget.deliveryCode} not found';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Firestore error: $e");
      if (mounted) {
        setState(() {
          errorMessage = 'Error loading delivery data: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'Delivery Confirmation',
            style: TextStyle(color: Color(0xFF1B6C07), fontWeight: FontWeight.bold),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'Delivery Confirmation',
            style: TextStyle(color: Color(0xFF1B6C07), fontWeight: FontWeight.bold),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 20),
                Text(
                  errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _loadData,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (deliveryData == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
        ),
        body: const Center(
          child: Text('Delivery data is null'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Delivery Confirmation',
          style: TextStyle(color: Color(0xFF1B6C07), fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Delivery Code
            if (widget.deliveryCode != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Delivery Code: ${widget.deliveryCode}',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green),
                  ),
                  const SizedBox(height: 10),
                ],
              ),

            // Delivery Status
            Text(
              'Status: $deliveryStatus',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue),
            ),
            const SizedBox(height: 5),

            // Delivery Date
            Text(
              'Date: ${deliveryDateFormatted ?? "N/A"}',
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 5),

            // Delivery Personnel
            if (deliveryPersonnel != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Driver: ${deliveryPersonnel!.name} | ${deliveryPersonnel!.employeeID}",
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                ],
              ),

            // Recipient Information
            if (recipient != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Recipient: ${recipient!.name}",
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    "Email: ${recipient!.email}",
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    "Address: ${recipient!.address}",
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                ],
              ),

            // Delivery Items Table
            if (deliveryItems.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Delivery Items:',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Table(
                    border: TableBorder.all(color: Colors.grey.shade300),
                    columnWidths: const {
                      0: FlexColumnWidth(2),
                      1: FlexColumnWidth(1),
                    },
                    children: [
                      const TableRow(
                        children: [
                          Padding(padding: EdgeInsets.all(8), child: Text('Item ID', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold))),
                          Padding(padding: EdgeInsets.all(8), child: Text('Quantity', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold))),
                        ],
                      ),
                      ...deliveryItems.map((item) => TableRow(
                        children: [
                          Padding(padding: const EdgeInsets.all(8), child: Text(item.itemID, style: const TextStyle(fontSize: 10.5))),
                          Padding(padding: const EdgeInsets.all(8), child: Text(item.quantity.toString(), style: const TextStyle(fontSize: 10.5))),
                        ],
                      )),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),

            // Location Information
            if (deliveryData!['location'] != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Location:',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    deliveryData!['location'].toString(),
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
          ],
        ),
      ),
    );
  }
}