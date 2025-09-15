import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'firebase_options.dart';

class ConfirmationPage extends StatefulWidget {
  final String? deliveryCode;
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
  final String location;

  Recipient({required this.name, required this.email, required this.location});

  factory Recipient.fromMap(Map<String, dynamic> m) => Recipient(
    name: m['name'] ?? '',
    email: m['email'] ?? '',
    location: m['location'] ?? '',
  );
}

class DeliveryItem {
  final String item;
  final int qty;
  final String tracking;
  final String date;
  final String time;

  DeliveryItem({
    required this.item,
    required this.qty,
    required this.tracking,
    required this.date,
    required this.time,
  });

  factory DeliveryItem.fromMap(Map<String, dynamic> m) {
    String formattedDate = '';
    String formattedTime = '';

    if (m['date'] != null) {
      if (m['date'] is Timestamp) {
        final dt = (m['date'] as Timestamp).toDate();
        formattedDate = DateFormat('yyyy-MM-dd').format(dt);
      } else {
        formattedDate = m['date'].toString();
      }
    }

    if (m['time'] != null) {
      if (m['time'] is Timestamp) {
        final dt = (m['time'] as Timestamp).toDate();
        formattedTime = DateFormat('HH:mm').format(dt);
      } else {
        formattedTime = m['time'].toString();
      }
    }

    return DeliveryItem(
      item: m['itemName'] ?? m['item'] ?? '',
      qty: (m['quantity'] is int) ? m['quantity'] : int.tryParse(m['quantity'].toString()) ?? 0,
      tracking: m['tracking'] ?? m['itemID'] ?? '',
      date: formattedDate,
      time: formattedTime,
    );
  }
}

class _ConfirmationPageState extends State<ConfirmationPage> {
  DeliveryPersonnel? deliveryPersonnel;
  Recipient? recipient;
  List<DeliveryItem> deliveryItems = [];
  String? deliveryDateFormatted;
  String? deliveryStatus;
  bool _isLoading = true;
  bool _hasError = false;
  bool _dataLoaded = false;

  @override
  void initState() {
    super.initState();

    // Create a fallback recipient using the delivery address
    recipient = Recipient(
      name: "Delivery Location",
      email: "",
      location: widget.deliveryAddress ?? "Unknown Address",
    );

    // Use fallback data immediately and try to load real data in background
    _setFallbackData();
    _loadDataInBackground();
  }

  Future<void> _loadDataInBackground() async {
    try {
      // Initialize Firebase if not already initialized
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      await _fetchFromFirestore();
    } catch (e) {
      debugPrint("Error loading data: $e");
      // Keep the fallback data if real data loading fails
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
        _dataLoaded = true;
      });
    }
  }

  Future<void> _fetchFromFirestore() async {
    if (widget.deliveryCode == null) {
      return; // Keep fallback data
    }

    try {
      // Fetch the main delivery document
      final deliveryDoc = await FirebaseFirestore.instance
          .collection('delivery')
          .doc(widget.deliveryCode)
          .get();

      if (deliveryDoc.exists) {
        final deliveryData = deliveryDoc.data()!;

        // Format delivery date
        if (deliveryData['deliveryDate'] != null && deliveryData['deliveryDate'] is Timestamp) {
          final date = (deliveryData['deliveryDate'] as Timestamp).toDate();
          deliveryDateFormatted = DateFormat('yyyy-MM-dd - HH:mm').format(date);
        }

        // Get delivery status
        deliveryStatus = deliveryData['status']?.toString() ?? 'Unknown Status';

        // Get employee ID from delivery data
        final String employeeID = deliveryData['employeeID']?.toString() ?? '25PG0001';

        // Fetch delivery personnel from users collection
        final personnelQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('employeeID', isEqualTo: employeeID)
            .get();

        DeliveryPersonnel? newPersonnel;
        if (personnelQuery.docs.isNotEmpty) {
          newPersonnel = DeliveryPersonnel.fromMap(personnelQuery.docs.first.data());
        }

        List<DeliveryItem> newDeliveryItems = [];
        // Process delivery items
        final List<Map<String, dynamic>> itemsData =
        List<Map<String, dynamic>>.from(deliveryData['deliveryItems'] ?? []);

        // Fetch detailed item information for each delivery item
        for (var itemData in itemsData) {
          final String itemID = itemData['itemID']?.toString() ?? '';
          if (itemID.isNotEmpty) {
            final itemDoc = await FirebaseFirestore.instance
                .collection('items')
                .doc(itemID)
                .get();

            if (itemDoc.exists) {
              final itemDetail = itemDoc.data()!;
              newDeliveryItems.add(DeliveryItem.fromMap({
                ...itemDetail,
                'quantity': itemData['quantity'],
                'itemID': itemID,
                'date': deliveryData['deliveryDate'],
              }));
            }
          }
        }

        if (mounted) {
          setState(() {
            if (newPersonnel != null) {
              deliveryPersonnel = newPersonnel;
            }
            if (newDeliveryItems.isNotEmpty) {
              deliveryItems = newDeliveryItems;
            }
            _hasError = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching Firestore data: $e");
      // Keep the existing fallback data
    }
  }

  void _setFallbackData() {
    deliveryPersonnel = DeliveryPersonnel(
      name: "Test Driver",
      email: "driver@example.com",
      employeeID: "25PG0001",
      phoneNumber: "012-3456789",
    );
    deliveryDateFormatted = "2025-09-16 - 14:30";
    deliveryStatus = "In Transit";

    // Add some fallback items
    deliveryItems = [
      DeliveryItem(
        item: "Shell Helix Ultra 5w40",
        qty: 2,
        tracking: "ITM00001",
        date: "2025-09-16",
        time: "14:30",
      ),
      DeliveryItem(
        item: "Engine Oil Filter",
        qty: 1,
        tracking: "ITM00002",
        date: "2025-09-16",
        time: "14:30",
      ),
    ];

    _hasError = true;
  }

  File? _imageFile;
  final ImagePicker _picker = ImagePicker();

  Future<void> _takePhoto() async {
    final XFile? pickedFile = await _picker.pickImage(source: ImageSource.camera);
    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
      });
    }
  }

  bool _isConfirmed = false;
  bool _isCancelled = false;

  void _handleCancel() {
    setState(() {
      _isCancelled = true;
      _isConfirmed = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Cancelled")),
    );
  }

  void _handleConfirm() {
    setState(() {
      _isConfirmed = true;
      _isCancelled = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Delivery Confirmed")),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Show loading only for a brief moment, then show data
    if (_isLoading && !_dataLoaded) {
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
        actions: [
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 4,
                      offset: Offset(2, 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(8.0),
                child: Icon(
                  Icons.person,
                  color: Color(0xFF1B6D07),
                  size: 30,
                ),
              ),
            ),
          )
        ],
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
            Text(
              "From: ${deliveryPersonnel?.name ?? "Unknown"} | ${deliveryPersonnel?.employeeID ?? "N/A"} | [${deliveryPersonnel?.email ?? "N/A"}]",
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 5),

            // Delivery Address
            Text(
              "To: ${widget.deliveryAddress ?? "Unknown Address"}",
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // Delivery Items Table
            if (deliveryItems.isNotEmpty)
              Table(
                border: TableBorder.all(color: Colors.grey.shade300),
                columnWidths: const {
                  0: FlexColumnWidth(2),
                  1: FlexColumnWidth(1),
                  2: FlexColumnWidth(2),
                  3: FlexColumnWidth(2),
                  4: FlexColumnWidth(1.5),
                },
                children: [
                  const TableRow(
                    children: [
                      Padding(padding: EdgeInsets.all(8), child: Text('Item(s) Delivered', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold))),
                      Padding(padding: EdgeInsets.all(8), child: Text('Quantity', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold))),
                      Padding(padding: EdgeInsets.all(8), child: Text('Tracking Number', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold))),
                      Padding(padding: EdgeInsets.all(8), child: Text('Delivery Date', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold))),
                      Padding(padding: EdgeInsets.all(8), child: Text('Delivery Time', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold))),
                    ],
                  ),
                  ...deliveryItems.map((item) => TableRow(
                    children: [
                      Padding(padding: const EdgeInsets.all(8), child: Text(item.item, style: const TextStyle(fontSize: 10.5))),
                      Padding(padding: const EdgeInsets.all(8), child: Text(item.qty.toString(), style: const TextStyle(fontSize: 10.5))),
                      Padding(padding: const EdgeInsets.all(8), child: Text(item.tracking, style: const TextStyle(fontSize: 10.5))),
                      Padding(padding: const EdgeInsets.all(8), child: Text(item.date, style: const TextStyle(fontSize: 10.5))),
                      Padding(padding: const EdgeInsets.all(8), child: Text(item.time, style: const TextStyle(fontSize: 10.5))),
                    ],
                  )),
                ],
              ),
            const SizedBox(height: 20,)
          ],
        ),
      ),
    );
  }
}