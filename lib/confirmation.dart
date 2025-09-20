import 'dart:async' show Timer;
import 'dart:typed_data';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'firebase_options.dart';
import 'package:image/image.dart' as img;
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
  String? itemName;

  DeliveryItem({
    required this.itemID,
    required this.quantity,
    this.itemName,
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
  bool _isUploading = false;

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

  Future<void> _loadItemNames(List<DeliveryItem> items) async {
    if (items.isEmpty) return;

    try {
      // Collect all itemIDs
      final itemIDs = items.map((i) => i.itemID.trim()).toList();

      // Batch get all documents in one call
      final querySnapshot = await FirebaseFirestore.instance
          .collection('items')
          .where(FieldPath.documentId, whereIn: itemIDs)
          .get();

      // Map from docID -> name
      final Map<String, String> idToName = {
        for (var doc in querySnapshot.docs) doc.id: doc.data()['itemName'] ?? 'Unknown Item'
      };

      // Assign names to delivery items
      for (var item in items) {
        item.itemName = idToName[item.itemID.trim()] ?? 'Unknown Item';
        if (item.itemName == 'Unknown Item') {
          debugPrint("⚠️ No name found for itemID: ${item.itemID}");
        } else {
          debugPrint("✅ Found name '${item.itemName}' for itemID: ${item.itemID}");
        }
      }
    } catch (e) {
      debugPrint("❌ Error loading item names: $e");
      for (var item in items) {
        item.itemName = 'Unknown Item';
      }
    }
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

        // Resolve delivery personnel: prefer employeeID on delivery doc, fallback to current user
        final String employeeID = (deliveryData!['employeeID'] ?? deliveryData!['employedID'] ?? '')
            .toString()
            .trim();

        Future<DeliveryPersonnel?> _mapUserDocToPersonnel(DocumentSnapshot doc) async {
          final data = doc.data() as Map<String, dynamic>?;
          if (data == null) return null;
          return DeliveryPersonnel.fromMap(data);
        }

        DeliveryPersonnel? resolvedPersonnel;

        // 1) Try by employeeID from delivery doc
        if (employeeID.isNotEmpty) {
          final byEmployeeId = await FirebaseFirestore.instance
              .collection('users')
              .where('employeeID', isEqualTo: employeeID)
              .limit(1)
              .get();
          if (byEmployeeId.docs.isNotEmpty) {
            resolvedPersonnel = await _mapUserDocToPersonnel(byEmployeeId.docs.first);
          }
        }

        // 2) Fallback to current logged-in user (by uid)
        if (resolvedPersonnel == null) {
          final currentUser = FirebaseAuth.instance.currentUser;
          if (currentUser != null) {
            final byUid = await FirebaseFirestore.instance
                .collection('users')
                .doc(currentUser.uid)
                .get();
            if (byUid.exists) {
              resolvedPersonnel = await _mapUserDocToPersonnel(byUid);
            }
          }
        }

        // 3) Fallback to current logged-in user's email lookup
        if (resolvedPersonnel == null) {
          final currentUser = FirebaseAuth.instance.currentUser;
          final email = currentUser?.email;
          if (email != null && email.isNotEmpty) {
            final byEmail = await FirebaseFirestore.instance
                .collection('users')
                .where('email', isEqualTo: email)
                .limit(1)
                .get();
            if (byEmail.docs.isNotEmpty) {
              resolvedPersonnel = await _mapUserDocToPersonnel(byEmail.docs.first);
            }
          }
        }

        if (resolvedPersonnel != null) {
          deliveryPersonnel = resolvedPersonnel;
        }

        final List<dynamic> itemsData = deliveryData!['deliveryItems'] ?? [];
        List<DeliveryItem> newDeliveryItems = [];
        for (var itemData in itemsData) {
          if (itemData is Map<String, dynamic>) {
            newDeliveryItems.add(DeliveryItem.fromMap(itemData));
          }
        }

        await _loadItemNames(newDeliveryItems);

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
      debugPrint('No image file selected or file does not exist.');
      _showImageRequiredError();
      return;
    }

    final docIdToUpdate = _deliveryDocId ?? widget.deliveryCode;
    if (docIdToUpdate == null || docIdToUpdate.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid delivery reference'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      final now = DateTime.now();

      // Compress and resize image
      final String proofBase64 = await _compressAndEncodeImage(_imageFile!);

      // Update delivery record
      await _updateDeliveryRecord(docIdToUpdate, proofBase64, now);

      setState(() => _confirmedAt = now);
      _timer?.cancel();

      //scaffold message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Delivery confirmed!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        Navigator.popUntil(context, (route) => route.isFirst);
      }
    } catch (e) {
      debugPrint('Confirmation error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isUploading = false);
    }
  }

  /// Compress image and encode as Base64
  Future<String> _compressAndEncodeImage(File imageFile) async {
    final Uint8List bytes = await imageFile.readAsBytes();
    img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) throw Exception('Unable to decode selected image');

    // Resize to max 1024px
    const int maxSide = 1024;
    if (decoded.width > maxSide || decoded.height > maxSide) {
      decoded = img.copyResize(
        decoded,
        width: decoded.width >= decoded.height ? maxSide : null,
        height: decoded.height > decoded.width ? maxSide : null,
      );
    }

    // Compress to fit ~900KB
    int quality = 60;
    late Uint8List jpegBytes;
    for (;;) {
      final List<int> encoded = img.encodeJpg(decoded, quality: quality);
      jpegBytes = Uint8List.fromList(encoded);
      if (jpegBytes.lengthInBytes <= 900 * 1024 || quality <= 30) break;
      quality -= 10;
    }

    return base64Encode(jpegBytes);
  }

  /// Update delivery document in Firestore
  Future<void> _updateDeliveryRecord(String docId, String proofBase64, DateTime now) async {
    await FirebaseFirestore.instance.collection('delivery').doc(docId).update({
      'status': 'Delivered',
      'deliveredAt': Timestamp.fromDate(now),
      'deliveryProof': proofBase64,
    });
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
        centerTitle: true,
        toolbarHeight: 80,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Delivery Confirmation',
          style: TextStyle(
            color: Color(0xFF1B6C07),
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Delivery details card
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 2,
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date
                    Text(
                      "Delivered At: $currentDate  $currentTime",
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),

                    // From section
                    Text("From", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.person, size: 14, color: Color(0xFF1B6C07)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            "${deliveryPersonnel?.name ?? "N/A"}",
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Icon(Icons.email, size: 14, color: Color(0xFF1B6C07)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            "${deliveryPersonnel?.email ?? "N/A"}",
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.location_on, size: 14, color: Color(0xFF1B6C07)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            "SPMS",
                            style: const TextStyle(fontSize: 12),
                            softWrap: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // To section
                    Text("To", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.person, size: 14, color: Color(0xFF1B6C07)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            "${recipient?.name ?? "N/A"}",
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Icon(Icons.email, size: 14, color: Color(0xFF1B6C07)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text("${recipient?.email ?? "N/A"}", style: const TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.location_on, size: 14, color: Color(0xFF1B6C07)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            "${recipient?.address ?? "N/A"}",
                            style: const TextStyle(fontSize: 12),
                            softWrap: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 20),

            // Items table
            Text("Items for #${widget.deliveryCode ?? 'N/A'}",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)
            ),
            SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 330,
                child: Table(
                  border: TableBorder.symmetric(
                    inside: BorderSide(color: Colors.grey.shade300),
                  ),
                  columnWidths: const {
                    0: FlexColumnWidth(2), // Item Name
                    1: FlexColumnWidth(2), // Item(s) Delivered
                    2: FlexColumnWidth(1), // Quantity
                  },
                  children: [
                    // Header row
                    TableRow(
                      decoration: BoxDecoration(color: Colors.grey.shade200),
                      children: const [
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Center(
                            child: Text(
                              'Item Name',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Center(
                            child: Text(
                              'Item(s) Delivered',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Center(
                            child: Text(
                              'Quantity',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Data rows
                    ...deliveryItems.map((item) {
                      return TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Center(
                              child: Text(
                                item.itemName ?? 'N/A',
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Center(
                              child: Text(
                                item.itemID,
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Center(
                              child: Text(
                                item.quantity.toString(),
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ),
            SizedBox(height: 30),
            // Proof of Delivery
            Text(
              'Confirmation Summary',
              style: TextStyle(
                fontSize: 14,
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
            SizedBox(height: 8),
            GestureDetector(
              onTap: _showImageSourceActionSheet,
              child: Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _imageFile == null
                    ? const Center(child: Icon(Icons.camera_alt_outlined, size: 40, color: Colors.black54))
                    : ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(_imageFile!, fit: BoxFit.cover, width: double.infinity),
                ),
              ),
            ),
          ],
        ),
      ),

      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _isUploading ? null : _handleConfirmation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B6C07),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: _isUploading
                    ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
                    : const Text(
                  'Confirm',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Loading & Error Screens
  Widget _loadingScreen() => Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      toolbarHeight: 80,
      title: const Text(
        'Delivery Confirmation',
        style: TextStyle(
            color:  Color(0xFF1B6C07),
            fontWeight: FontWeight.bold
        ),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.black),
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: const Center(child: CircularProgressIndicator()),
  );

  Widget _errorScreen() => Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      toolbarHeight: 80,
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