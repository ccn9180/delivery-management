import 'dart:async' show Timer;
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delivery/profile.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'firebase_options.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'google_map.dart';
import 'dart:convert';

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

  DateTime _currentTime = DateTime.now();
  DateTime? _confirmedAt;
  Timer? _timer;

  String get currentDateFormatted {
    final date = _confirmedAt ?? _currentTime;
    return DateFormat('MMM d, yyyy').format(date);
  }

  String get currentTimeFormatted {
    final date = _confirmedAt ?? _currentTime;
    return DateFormat('h:mma').format(date).toLowerCase();
  }

  @override
  void initState() {
    super.initState();
    _loadData();

    // Start timer to update time every second
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
      } else {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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

        if (deliveryData!['deliveredAt'] != null) {
          final dyn = deliveryData!['deliveredAt'];
          if (dyn is Timestamp) {
            _confirmedAt = dyn.toDate().toLocal();
          } else if (dyn is DateTime) {
            _confirmedAt = dyn.toLocal();
          }
        }

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

  Future<void> _takePhoto() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
          source: ImageSource.camera, imageQuality: 80);
      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      debugPrint("Error taking photo: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to take photo: $e"), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final XFile? pickedFile =
      await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      debugPrint("Error picking from gallery: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to pick image: $e"), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowCompression: true,
      );
      if (result != null && result.files.single.path != null) {
        setState(() {
          _imageFile = File(result.files.single.path!);
        });
      }
    } catch (e) {
      debugPrint("Error picking file: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to pick file: $e"), backgroundColor: Colors.red),
      );
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
                  _takePhoto();
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

  void _showImageRequiredError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please upload proof of delivery before confirming'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _handleConfirmation() async {
    if (_imageFile == null || !_imageFile!.existsSync()) {
      debugPrint('❌ No image file selected or file does not exist.');
      _showImageRequiredError();
      return;
    }

    final docIdToUpdate = _deliveryDocId ?? widget.deliveryCode;
    if (docIdToUpdate == null || docIdToUpdate.isEmpty) {
      debugPrint('❌ Invalid delivery reference: $docIdToUpdate');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid delivery reference'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Uploading proof of delivery...'),
            ],
          ),
        ),
      );

      // Convert image file to Base64
      final bytes = await _imageFile!.readAsBytes();
      final proofBase64 = base64Encode(bytes);
      debugPrint('✅ Image converted to Base64, length: ${proofBase64.length}');

      if (Navigator.of(context).canPop()) Navigator.of(context).pop(); // close loading dialog

      // Update Firestore directly with Base64
      final now = DateTime.now();
      setState(() => _confirmedAt = now);
      _timer?.cancel();

      await FirebaseFirestore.instance
          .collection('delivery')
          .doc(docIdToUpdate)
          .update({
        'status': 'Delivered',
        'deliveredAt': Timestamp.fromDate(now),
        'deliveryProof': proofBase64, // store image as Base64 string
      });

      final String employeeID = deliveryData?['employeeID'] ?? '';
      if (employeeID.isNotEmpty) {
        final userQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('employeeID', isEqualTo: employeeID)
            .limit(1)
            .get();


        if (userQuery.docs.isNotEmpty) {
          final userDocId = userQuery.docs.first.id;

          await FirebaseFirestore.instance
              .collection('users')
              .doc(userDocId)
              .update({
            'deliveredCount': FieldValue.increment(1),
          });
          debugPrint("✅ Delivery count updated for employeeID: $employeeID");
        } else {
          debugPrint("⚠️ No user found with employeeID: $employeeID");
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Delivery confirmed!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );

      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.pop(context);

    } catch (e) {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop(); // close loading dialog
      debugPrint('❌ Firestore error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
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

    // Get current phone local date and time
    final now = DateTime.now();
    final currentDate = DateFormat('MMM d, yyyy').format(now);
    final currentTime = DateFormat('h:mma').format(now).toLowerCase();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 110,
        centerTitle: true,
        title: const Text(
          'Delivery Confirmation',
          style: TextStyle(
            color: Color(0xFF1B6C07),
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => GoogleMapPage(
                  deliveryCode: widget.deliveryCode,
                  deliveryAddress: widget.deliveryAddress,
                  deliveryLocation: widget.deliveryLocation,
                  deliveryStatus: deliveryStatus,
                  deliveryItems: widget.deliveryItems,
                ),
              ),
            );
          },
        ),
        actions: [
          Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 16.0, top: 30.0), // small top padding
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const Profile()),
                    );
                  },
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
                    child: const Icon(
                      Icons.person,
                      color: Color(0xFF1B6D07),
                      size: 30,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Date: $currentDate',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'From: ${deliveryPersonnel?.name ?? "N/A"} | Greenstem Business Software | [${deliveryPersonnel?.email ?? "N/A"}]',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'To: ${recipient?.name ?? "N/A"} | ${recipient?.email ?? "N/A"} | ${recipient?.address ?? "N/A"}',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 50),

            Table(
              border: TableBorder.symmetric(
                inside: BorderSide(color: Colors.grey.shade300),
              ),
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(1.5),
                2: FlexColumnWidth(2),
                3: FlexColumnWidth(2),
                4: FlexColumnWidth(1.5),
              },
              children: [
                TableRow(
                  children: [
                    for (var header in [
                      'Item(s) Delivered',
                      'Quantity',
                      'Tracking Number',
                      'Delivery Date',
                      'Delivery Time'
                    ])
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Center(
                          child: Text(
                            header,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),

                ...deliveryItems.map((item) {
                  return TableRow(
                    children: [
                      Padding(
                          padding: const EdgeInsets.all(8),
                          child: Center(
                            child: Text(item.itemID,
                                style: const TextStyle(fontSize: 10)),
                          )),
                      Padding(
                          padding: const EdgeInsets.all(8),
                          child: Center(
                            child: Text(item.quantity.toString(),
                                style: const TextStyle(fontSize: 10)),
                          )),
                      Padding(
                          padding: const EdgeInsets.all(8),
                          child: Center(
                            child: Text(widget.deliveryCode ?? 'N/A',
                                style: const TextStyle(fontSize: 10)),
                          )),
                      Padding(
                          padding: const EdgeInsets.all(8),
                          child: Center(
                            child: Text(currentDate,
                                style: const TextStyle(fontSize: 10)),
                          )),
                      Padding(
                          padding: const EdgeInsets.all(8),
                          child: Center(
                            child: Text(currentTime,
                                style: const TextStyle(fontSize: 10)),
                          )),
                    ],
                  );
                }),
              ],
            ),

            const SizedBox(height: 50),

            const Text(
              'Confirmation Summary',
              style: TextStyle(
                fontSize: 10,
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
                    style: TextStyle(fontSize: 10),
                  ),
                  TextSpan(
                    text: currentDateFormatted,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                  const TextSpan(
                    text: ', at ',
                    style: TextStyle(fontSize: 10),
                  ),
                  TextSpan(
                    text: currentTimeFormatted,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                  const TextSpan(
                    text: '. Please check the items and contact us if there are any issues.',
                    style: TextStyle(fontSize: 10),
                  ),
                ],
              ),
              style: const TextStyle(height: 1.5),
            ),

            const SizedBox(height: 10),

            // Image upload section
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                const SizedBox(height: 5),
                GestureDetector(
                  onTap: _showImageSourceActionSheet,
                  child: Container(
                    height: 140,
                    width: 160,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          offset: const Offset(4, 6),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: _imageFile == null
                        ? const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt_outlined,
                            size: 40, color: Colors.black54),
                        SizedBox(height: 8),
                      ],
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

            Text.rich(
              const TextSpan(
                text: 'Thank you for choosing our services, Please do not hesitate to reach out if you have any concerns regarding this delivery.',
                style: TextStyle(fontSize: 10),
              ),
            ),

            const SizedBox(height: 100),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // Cancel button
                ElevatedButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => GoogleMapPage(
                          deliveryCode: widget.deliveryCode,
                          deliveryAddress: widget.deliveryAddress,
                          deliveryLocation: widget.deliveryLocation,
                          deliveryStatus: deliveryStatus,
                          deliveryItems: widget.deliveryItems,
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD7D7D7),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 37, vertical: 10),
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

  // Loading & Error Screens
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
              errorMessage ?? 'An error occurred',
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