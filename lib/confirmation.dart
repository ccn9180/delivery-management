import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
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
  final String address;

  Recipient({required this.name, required this.email, required this.address});

  factory Recipient.fromMap(Map<String, dynamic> m) => Recipient(
    name: m['recipientName'] ?? '',
    email: m['recipientEmail'] ?? '',
    address: m['address'] ?? '',
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
    itemID: m['itemID'] ?? '',
    quantity: (m['quantity'] is int)
        ? m['quantity']
        : int.tryParse(m['quantity'].toString()) ?? 0,
  );
}

class _ConfirmationPageState extends State<ConfirmationPage> {
  DeliveryPersonnel? deliveryPersonnel;
  Recipient? recipient;
  List<DeliveryItem> deliveryItems = [];

  DateTime? deliveryDateTime;
  String? deliveryDateFormatted;
  String? deliveryTimeFormatted;

  String? deliveryStatus;
  bool _isLoading = true;
  Map<String, dynamic>? deliveryData;
  String? errorMessage;

  String? _deliveryDocId;

  File? _imageFile;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      if (widget.deliveryCode == null || widget.deliveryCode!.isEmpty) {
        if (mounted) {
          setState(() {
            errorMessage = 'Delivery code is missing';
            _isLoading = false;
          });
        }
        return;
      }

      DocumentSnapshot deliveryDoc = await FirebaseFirestore.instance
          .collection('delivery')
          .doc(widget.deliveryCode)
          .get();

      if (!deliveryDoc.exists) {
        QuerySnapshot querySnapshot = await FirebaseFirestore.instance
            .collection('delivery')
            .where('code', isEqualTo: widget.deliveryCode)
            .limit(1)
            .get();

        if (querySnapshot.docs.isNotEmpty) {
          deliveryDoc = querySnapshot.docs.first;
        }
      }

      if (deliveryDoc.exists) {
        _deliveryDocId = deliveryDoc.id;

        deliveryData = deliveryDoc.data() as Map<String, dynamic>;
        recipient = Recipient.fromMap(deliveryData!);

        if (deliveryData!['deliveryDate'] != null) {
          final dyn = deliveryData!['deliveryDate'];

          if (dyn is Timestamp) {
            deliveryDateTime = (dyn as Timestamp).toDate().toLocal();
          } else if (dyn is String) {
            DateTime? parsed;
            try {
              parsed = DateTime.tryParse(dyn);
              if (parsed != null) parsed = parsed.toLocal();
            } catch (_) {
              parsed = null;
            }
            if (parsed == null) {
              try {
                String cleaned = dyn.replaceAll(' at ', ' ');
                cleaned = cleaned.replaceAll(RegExp(r'UTC.*$'), '').trim();
                parsed = DateFormat('d MMMM yyyy HH:mm:ss').parse(cleaned);
              } catch (e) {
                debugPrint('string parse failed: $e');
                parsed = null;
              }
            }
            if (parsed != null) {
              deliveryDateTime = parsed.toLocal();
            }
          }

          if (deliveryDateTime != null) {
            deliveryDateFormatted =
                DateFormat('MMM d, yyyy').format(deliveryDateTime!);
            deliveryTimeFormatted =
                DateFormat('h:mma').format(deliveryDateTime!).toLowerCase();
          }
        }

        deliveryStatus = deliveryData!['status']?.toString() ?? 'Unknown Status';

        final String employeeID = deliveryData!['employedID']?.toString() ?? '';
        if (employeeID.isNotEmpty) {
          final personnelQuery = await FirebaseFirestore.instance
              .collection('users')
              .where('employeeID', isEqualTo: employeeID)
              .get();

          if (personnelQuery.docs.isNotEmpty) {
            deliveryPersonnel =
                DeliveryPersonnel.fromMap(personnelQuery.docs.first.data());
          }
        }

        final List<dynamic> itemsData = deliveryData!['deliveryItems'] ?? [];
        List<DeliveryItem> newDeliveryItems = [];
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
        if (mounted) {
          setState(() {
            errorMessage =
            'Delivery with code ${widget.deliveryCode} not found';
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

  // ✅ Camera choice (front/rear)
  Future<void> _chooseCamera() async {
    final choice = await showDialog<CameraDevice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Select Camera"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, CameraDevice.rear),
            child: const Text("Rear Camera"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, CameraDevice.front),
            child: const Text("Front Camera"),
          ),
        ],
      ),
    );

    if (choice != null) {
      _takePhoto(choice);
    }
  }

  // ✅ Take photo
  Future<void> _takePhoto(CameraDevice camera) async {
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: camera,
    );
    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
      });
    }
  }

  // ✅ Gallery
  Future<void> _pickFromGallery() async {
    final XFile? pickedFile =
    await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
      });
    }
  }

  // ✅ File picker
  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      setState(() {
        _imageFile = File(result.files.single.path!);
      });
    }
  }

  void _showImageSourceActionSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text("Take Photo"),
                onTap: () {
                  Navigator.pop(context);
                  _chooseCamera();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text("Choose from Gallery"),
                onTap: () {
                  Navigator.pop(context);
                  _pickFromGallery();
                },
              ),
              ListTile(
                leading: const Icon(Icons.upload_file),
                title: const Text("Upload File"),
                onTap: () {
                  Navigator.pop(context);
                  _pickFile();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ✅ Show error message if no image is uploaded
  void _showImageRequiredError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please upload proof of delivery before confirming'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ),
    );
  }

  // ✅ Handle confirmation with image validation
  Future<void> _handleConfirmation() async {
    if (_imageFile == null) {
      _showImageRequiredError();
      return;
    }

    final docIdToUpdate = _deliveryDocId ?? widget.deliveryCode;
    if (docIdToUpdate != null && docIdToUpdate.isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('delivery')
          .doc(docIdToUpdate)
          .update({
        'status': 'Delivered',
        'deliveredAt': FieldValue.serverTimestamp(),
      });
    }

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _loadingScreen();
    }

    if (errorMessage != null) {
      return _errorScreen();
    }

    if (deliveryData == null) {
      return Scaffold(
        appBar: AppBar(backgroundColor: Colors.white, elevation: 0),
        body: const Center(child: Text('Delivery data is null')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Delivery Confirmation',
          style: TextStyle(
            color: Color(0xFF1B6C07),
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        centerTitle: true,
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
            const SizedBox(height: 15),
            Text(
              'Date: ${deliveryDateFormatted ?? "N/A"}',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'From: ${deliveryPersonnel?.name ?? "N/A"} | Greenstem Business Software | [${deliveryPersonnel?.email ?? "N/A"}]',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 15),
            Text(
              'To: ${recipient?.name ?? "N/A"} | ${recipient?.email ?? "N/A"} | ${recipient?.address ?? "N/A"}',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 30),

            /// Items Table
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
                    Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('Item(s) Delivered',
                            style: TextStyle(
                                fontSize: 10.5, fontWeight: FontWeight.bold))),
                    Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('Quantity',
                            style: TextStyle(
                                fontSize: 10.5, fontWeight: FontWeight.bold))),
                    Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('Tracking Number',
                            style: TextStyle(
                                fontSize: 10.5, fontWeight: FontWeight.bold))),
                    Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('Delivery Date',
                            style: TextStyle(
                                fontSize: 10.5, fontWeight: FontWeight.bold))),
                    Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('Delivery Time',
                            style: TextStyle(
                                fontSize: 10.5, fontWeight: FontWeight.bold))),
                  ],
                ),
                ...deliveryItems.map((item) => TableRow(
                  children: [
                    Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(item.itemID,
                            style: const TextStyle(fontSize: 10.5))),
                    Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(item.quantity.toString(),
                            style: const TextStyle(fontSize: 10.5))),
                    Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(widget.deliveryCode ?? 'N/A',
                            style: const TextStyle(fontSize: 10.5))),
                    Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(deliveryDateFormatted ?? 'N/A',
                            style: const TextStyle(fontSize: 10.5))),
                    Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(deliveryTimeFormatted ?? 'N/A',
                            style: const TextStyle(fontSize: 10.5))),
                  ],
                )),
              ],
            ),

            const SizedBox(height: 30),

            /// Confirmation Summary
            const Text(
              'Confirmation Summary',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'Your items were delivered on ',
                    style: TextStyle(fontSize: 14),
                  ),
                  TextSpan(
                    text: deliveryDateFormatted ?? 'N/A',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const TextSpan(
                    text: ', at ',
                    style: TextStyle(fontSize: 14),
                  ),
                  TextSpan(
                    text: deliveryTimeFormatted ?? 'N/A',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const TextSpan(
                    text:
                    '. Please check the items and contact us if there are any issues.',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
              style: const TextStyle(height: 1.5),
            ),

            const SizedBox(height: 20),

            // Image upload section with clear instructions
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: _showImageSourceActionSheet,
                  child: Container(
                    height: 140,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _imageFile == null
                        ? const Center(
                      child: Icon(Icons.camera_alt_outlined,
                          size: 40, color: Colors.black54),
                    )
                        : ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        _imageFile!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            /// Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD7D7D7),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 37,
                      vertical: 10,
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      color: Color(0xFF8E8989),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                ElevatedButton(
                  onPressed: _handleConfirmation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B6C07),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 35, vertical: 10),
                  ),
                  child: const Text(
                    'Confirm',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Loading & Error Screens
  Widget _loadingScreen() => Scaffold(
    appBar: AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      title: const Text(
        'Delivery Confirmation',
        style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.black),
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: const Center(child: CircularProgressIndicator()),
  );

  Widget _errorScreen() => Scaffold(
    appBar: AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      title: const Text(
        'Delivery Confirmation',
        style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
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