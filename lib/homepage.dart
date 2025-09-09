import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delivery/profile_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:delivery/profile_page.dart';

class Delivery {
  final String code;
  final String address;
  final DateTime date;
  final String status;
  final List<Map<String, dynamic>> items;

  Delivery({
    required this.code,
    required this.address,
    required this.date,
    required this.status,
    required this.items,
  });

  factory Delivery.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Delivery(
      code: doc.id,
      address: data['address'] ?? '',
      date: (data['deliveryDate'] as Timestamp).toDate().toLocal(),
      status: data['status'] ?? 'New Order',
      items: List<Map<String,dynamic>>.from(data['deliveryItems'] ?? []),
    );
  }
}

Future<String?> fetchEmployeeCode() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;

  final userDoc = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid) // Firebase UID must match user doc ID
      .get();

  return userDoc.data()?['employeeID'];
}

Stream<List<Delivery>> fetchEmployeeDeliveries() async* {
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


class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageStatus();
}

class _HomePageStatus extends State<HomePage> {
  int _selectedIndex = 1;
  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    FirebaseFirestore.instance.collection('delivery').get().then((snapshot) {
      print("Total docs: ${snapshot.docs.length}");
      for (var doc in snapshot.docs) {
        print(doc.data());
      }
    });
    _pages = [
      DeliveryHistory(),
      const DeliveryListPage(),
      const ProfilePage(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
        ),

        child: BottomNavigationBar(
          backgroundColor: Colors.white,
          currentIndex: _selectedIndex,
          selectedItemColor: Color(0xFF1B6C07),
          unselectedItemColor: Colors.grey,
          selectedIconTheme: IconThemeData(size: 37),
          unselectedIconTheme: IconThemeData(size: 24),
          showSelectedLabels: false,
          showUnselectedLabels: false,

          onTap: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          items: [
            BottomNavigationBarItem(
              icon: Icon(Icons.history),
              label: 'History',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.home),
              label: 'Deliveries List',
            ),
            BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}

class DeliveryListPage extends StatelessWidget {
  const DeliveryListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(25, 20, 18, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Delivery List",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1B6C07),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            spreadRadius: 1,
                            blurRadius: 2,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const CircleAvatar(
                        radius: 22,
                        backgroundColor: Colors.white,
                        child: Icon(
                          Icons.person,
                          color: Color(0xFF1B6C07),
                          size: 27,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Align(
                alignment: Alignment.center,
                child: const TabBar(
                  labelColor: Color(0xFF1B6C07),
                  unselectedLabelColor: Colors.grey,
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                  indicatorColor: Color(0xFF1B6C07),
                  dividerColor: Colors.transparent,
                  indicatorWeight: 2,
                  tabs: [
                    Tab(text: "New Order"),
                    Tab(text: "On-Going"),
                    Tab(text: "Delivered"),
                  ],
                ),
              ),
              const SizedBox(height: 13),

              // Tab Content
              Expanded(
                child: StreamBuilder<List<Delivery>>(
                  stream: fetchEmployeeDeliveries(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Center(child: Text("No deliveries assigned"));
                    }

                    final deliveries = snapshot.data!;
                    final newOrder = deliveries.where((d) => d.status == 'New Order').toList();
                    final ongoing = deliveries.where((d) => d.status == 'On-Going').toList();
                    final finished = deliveries.where((d) => d.status == 'Delivered').toList();
                    final dateFormat = DateFormat('dd/MM/yyyy');
                    final timeFormat = DateFormat('HH:mm');

                    List<Map<String,String>> mapList(List<Delivery> list) => list.map((d) => {
                      'code': d.code,
                      'address': d.address,
                      'date': dateFormat.format(d.date),
                      'time': timeFormat.format(d.date),
                      'status': d.status,
                      'image': d.items.isNotEmpty
                          ? (d.items.first['imageUrl']?.toString() ?? 'assets/images/EngineOils.jpg')
                          : 'assets/images/EngineOils.jpg',
                    }).toList();

                    return TabBarView(
                      children: [
                        DeliveryListTab(deliveries: mapList(newOrder)),
                        DeliveryListTab(deliveries: mapList(ongoing)),
                        DeliveryListTab(deliveries: mapList(finished)),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DeliveryListTab extends StatelessWidget {
  final List<Map<String, String>> deliveries;
  const DeliveryListTab({super.key, required this.deliveries});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: deliveries.length,
      itemBuilder: (context, index) {
        final d = deliveries[index];
        return Padding(
          padding: EdgeInsets.fromLTRB(7, 0, 7, 16),
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
  }
}

Widget deliveryCard({
  required BuildContext context,
  required String image,
  required String code,
  required String date,
  required String time,
  required String address,
  required String status,
}) {
  return GestureDetector(
    onTap: () {
      showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: "Delivery Details",
        barrierColor: Colors.black.withOpacity(0.5),
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, anim1, anim2) {
          return Center(
            child: DeliveryDetailsPopUp(
              code: code,
              address: address,
              image: image,
              status: status,
            ),
          );
        },
        transitionBuilder: (context, anim1, anim2, child) {
          return ScaleTransition(
            scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
            child: child,
          );
        },
      );
    },

    child: Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade100, width: 1.5),
      ),
      elevation: 3,
      shadowColor: Colors.grey.shade100,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 5),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade100, width: 1.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/EngineOils.jpg',
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),

                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Text(
                            '# $code',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                            ),
                          ),
                          const Spacer(),
                          if (status == 'On-Going' || status == 'Delivered')
                            Transform.translate(
                              offset: const Offset(0, -14.5),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: status == 'Delivered'
                                      ? Colors.green.shade100
                                      : Colors.blue.shade100,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  status,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: status == 'Delivered'
                                        ? Colors.green
                                        : Colors.blueGrey,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 16),
                          const SizedBox(width: 6),
                          Text(date, style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 12),
                          const Icon(Icons.access_time, size: 16),
                          const SizedBox(width: 6),
                          Text(time, style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Divider(color: Colors.grey.shade300, thickness: 1),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(address, style: const TextStyle(fontSize: 11.5)),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class DeliveryDetailsPopUp extends StatelessWidget {
  final String code;
  final String address;
  final String image;
  final String status;

  const DeliveryDetailsPopUp({
    super.key,
    required this.code,
    required this.address,
    required this.image,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        padding: const EdgeInsets.all(20),
        margin: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '# $code',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                    height:180,
                    width:double.infinity,
                    child:Container(
                      height: 180,
                      child: Image.asset('assets/images/map.jpeg',width: 100,),
                    )
                ),
              ),
              SizedBox(height:12),
              Row(
                children: [
                  const Icon(Icons.location_pin),
                  const SizedBox(width: 8),
                  Expanded(child: Text(address)),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Goods Detail',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Image.asset('assets/images/EngineOils.jpg', width: 50),
                  const SizedBox(width: 10),
                  Image.asset('assets/images/EngineOils.jpg', width: 50),
                  const SizedBox(width: 10),
                  Image.asset('assets/images/EngineOils.jpg', width: 50),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                '• Part No: BOSCH 0986UR3204 | RM 30.00/Unit',
                style: TextStyle(color: Colors.grey),
              ),
              const Text(
                '• Brake Pad BENDIX DB1242 GCT | RM 25.00',
                style: TextStyle(color: Colors.grey),
              ),
              const Text(
                '• Petronas Multi-Grade SAE 15W-50 API-SJ | RM 18.00',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.center,
                child: Builder(
                  builder: (_) {
                    if (status == 'New Order') {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(
                                vertical: 5,
                                horizontal: 38,
                              ),
                              backgroundColor: Colors.grey.shade200,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                color: Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(
                                vertical: 5,
                                horizontal: 30,
                              ),
                              backgroundColor: Color(0xFF1B6C07),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                            child: Text(
                              'Accepted',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      );
                    } else if (status == 'On-Going') {
                      return ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(
                            vertical: 5,
                            horizontal: 10,
                          ),
                          backgroundColor: Color(0xFF1B6C07),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(7),
                          ),
                        ),
                        child: Text(
                          'Start Navigation',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    } else {
                      return ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(
                            vertical: 5,
                            horizontal: 30,
                          ),
                          backgroundColor: Color(0xFF1B6C07),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(7),
                          ),
                        ),
                        child: Text(
                          'Back',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DeliveryHistory extends StatelessWidget {
  const DeliveryHistory({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Delivery>>(
      stream: fetchEmployeeDeliveries(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text("No delivery history"));
        }

        final delivered = snapshot.data!.where((d) => d.status == 'Delivered').toList();
        final mapList = delivered.map((d) => {
          'code': d.code,
          'address': d.address,
          'date': "${d.date.day}/${d.date.month}/${d.date.year}",
          'time': "${d.date.hour}:${d.date.minute.toString().padLeft(2,'0')}",
          'status': d.status,
          'image': d.items.isNotEmpty ? d.items.first['imageUrl'] ?? 'assets/images/EngineOils.jpg' : 'assets/images/EngineOils.jpg',
        }).toList();

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: mapList.length,
          itemBuilder: (context, index) {
            final d = mapList[index];
            return Padding(
              padding: const EdgeInsets.fromLTRB(7,0,7,16),
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
    );
  }
}

