import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delivery/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

void main() async{
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class DeliveryPersonnel{
  final String name;
  final String email;
  final String company;

  DeliveryPersonnel({required this.name, required this.email, required this.company});

  factory DeliveryPersonnel.fromMap(Map<String,dynamic> m) => DeliveryPersonnel(
    name: m['name'] ?? '',
    email: m['email'] ?? '',
    company: m['company'] ?? '',
  );
}

class Recipient{
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
      item: m['item'] ?? '',
      qty: (m['qty'] is int) ? m['qty'] : int.tryParse(m['qty'].toString()) ?? 0,
      tracking: m['tracking'] ?? '',
      date: formattedDate,
      time: formattedTime,
    );
  }
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Delivery Confirmation',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.white),
      ),
      home: const MyHomePage(title: 'Delivery Confirmation'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late Future<void> _loadData;
  DeliveryPersonnel? deliveryPersonnel;
  Recipient? recipient;
  List<DeliveryItem> deliveryItems = [];

  @override
  void initState() {
    super.initState();
    _loadData = _fetchFromFirestore();
  }

  Future<void> _fetchFromFirestore() async{
    try{
      final personnelDoc = await FirebaseFirestore.instance
          .collection('delivery_personnel')
          .doc('personnel')
          .get();

      final recipientDoc = await FirebaseFirestore.instance
          .collection('recipients')
          .doc('workshop1')
          .get();

      final itemsSnapshot = await FirebaseFirestore.instance
          .collection('deliveries')
          .doc('delivery123')
          .collection('items')
          .get();

      deliveryPersonnel = DeliveryPersonnel.fromMap(personnelDoc.data() ?? {});
      recipient = Recipient.fromMap(recipientDoc.data() ?? {});
      deliveryItems = itemsSnapshot.docs.map((d) => DeliveryItem.fromMap(d.data())).toList();
    } catch (e) {
      debugPrint("Error fetching Firestore data: $e");
    }
  }

  File? _imageFile;
  final ImagePicker _picker = ImagePicker();

  Future<void> _takePhoto() async{
    final XFile? pickedFile = await _picker.pickImage(source: ImageSource.camera);
    if (pickedFile != null){
      setState(() {
        _imageFile = File(pickedFile.path);
      });
    }
  }


  bool _isConfirmed = false;
  bool _isCancelled = false;

  void _handleCancel(){
    setState(() {
      _isCancelled = true;
      _isConfirmed = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Cancelled")),
    );
  }

  void _handleConfirm(){
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
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Delivery Confirmation',
          style: TextStyle(color: Color(0xFF1B6C07), fontWeight: FontWeight.bold),
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
      body: FutureBuilder(
          future: _loadData,
          builder: (context,snapshot){
            if(snapshot.connectionState != ConnectionState.done){
              return const Center(child: CircularProgressIndicator());
            }
            if(deliveryPersonnel == null || recipient == null){
              return const Center(child: Text('Failed to load data'));
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 5),
                  Text(
                    'Date: ${deliveryItems.isNotEmpty ? "${deliveryItems.first.date} - ${deliveryItems.first.time}" : "N/A"}',
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    "From: ${deliveryPersonnel!.name} | ${deliveryPersonnel!.company} | [${deliveryPersonnel!.email}]",
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    "To: ${recipient!.name} | ${recipient!.location} | ${recipient!.email}",
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  Table(
                    border: TableBorder.all(color: Colors.grey.shade300),
                    columnWidths: const{
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
                        children:[
                          Padding(padding: EdgeInsets.all(8), child: Text(item.item, style: const TextStyle(fontSize: 10.5))),
                          Padding(padding: EdgeInsets.all(8), child: Text(item.qty.toString(), style: const TextStyle(fontSize: 10.5))),
                          Padding(padding: EdgeInsets.all(8), child: Text(item.tracking, style: const TextStyle(fontSize: 10.5))),
                          Padding(padding: EdgeInsets.all(8), child: Text(item.date, style: const TextStyle(fontSize: 10.5))),
                          Padding(padding: EdgeInsets.all(8), child: Text(item.time, style: const TextStyle(fontSize: 10.5))),
                        ],
                      )),
                    ],
                  ),
                  const SizedBox(height: 20,)
                ],
              ),
            );
          }
      ),
    );
  }
}
