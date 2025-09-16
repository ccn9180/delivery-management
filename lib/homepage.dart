import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delivery/profile_page.dart';
import 'package:delivery/widget/header.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'DeliveryHistory.dart';
import 'google_map.dart';

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
      items: List<Map<String, dynamic>>.from(data['deliveryItems'] ?? []),
    );
  }
}

//match the employee
Future<String?> fetchEmployeeCode() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;

  final userDoc = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid) // Firebase UID must match user doc ID
      .get();

  return userDoc.data()?['employeeID'];
}

//only fetch sysdate delivery
Stream<List<Delivery>> fetchEmployeeDeliveries() async* {
  final employeeCode = await fetchEmployeeCode();
  if (employeeCode == null) {
    yield [];
    return;
  }

  final now = DateTime.now(); // use local time
  final startOfDayLocal = DateTime(now.year, now.month, now.day, 0, 0, 0);
  final endOfDayLocal = DateTime(now.year, now.month, now.day, 23, 59, 59);

  final startOfDay = startOfDayLocal.toUtc();
  final endOfDay = endOfDayLocal.toUtc();

  yield* FirebaseFirestore.instance
      .collection('delivery')
      .where('employeeID', isEqualTo: employeeCode)
      .where('deliveryDate', isGreaterThanOrEqualTo: startOfDay)
      .where('deliveryDate', isLessThanOrEqualTo: endOfDay)
      .snapshots()
      .map((snapshot) =>
      snapshot.docs.map((doc) => Delivery.fromDoc(doc)).toList()
  );

}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageStatus();
}

class _HomePageStatus extends State<HomePage> {
  int _selectedIndex = 1;
  late final List<Widget> _pages;

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
      const DeliveryHistory(),
      const DeliveryListPage(),
      const ProfilePage()
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body:IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
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
            BottomNavigationBarItem(
                icon: Icon(Icons.person),
                label: 'Profile'
            ),
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
            children: [
              // Header
              PageHeader(
                title: "Delivery List",
                extraWidget: StreamBuilder<List<Delivery>>(
                  stream: fetchEmployeeDeliveries(),
                  builder: (context, snapshot) {
                    final deliveries = snapshot.data ?? [];
                    final total = deliveries.length;
                    final delivered = deliveries.where((d) => d.status == 'Delivered').length;
                    final progress = total == 0 ? 0.0 : delivered / total;

                    return SizedBox(
                      width: 50,
                      height: 50,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 46,
                            height: 46,
                            child: CircularProgressIndicator(
                              value: progress,
                              strokeWidth: 6,
                              backgroundColor: Colors.grey.shade200,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                delivered == total && total != 0 ? Colors.green : Colors.orange,
                              ),
                            ),
                          ),
                          Text(
                            "$delivered/$total", // <-- fraction instead of percentage
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // TabBar
              const TabBar(
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

              const SizedBox(height: 10),

              // TabBarView
              Expanded(
                child: StreamBuilder<List<Delivery>>(
                  stream: fetchEmployeeDeliveries(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }

                    final deliveries = snapshot.data ?? [];

                    final newOrder = deliveries
                        .where((d) => d.status == 'New Order')
                        .toList();
                    final ongoing = deliveries
                        .where((d) => d.status == 'On-Going')
                        .toList();
                    final finished = deliveries
                        .where((d) => d.status == 'Delivered')
                        .toList();

                    final dateFormat = DateFormat('dd/MM/yyyy');
                    final timeFormat = DateFormat('hh:mm a');

                    List<Map<String, String>> mapList(List<Delivery> list) =>
                        list
                            .map(
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

                    return TabBarView(
                      children: [
                        DeliveryListTab(
                          deliveries: mapList(newOrder),
                          emptyMessages: "No new orders assigned today",
                        ),
                        DeliveryListTab(
                          deliveries: mapList(ongoing),
                          emptyMessages: "No on-going deliveries at the moment",
                        ),
                        DeliveryListTab(
                          deliveries: mapList(finished),
                          emptyMessages: "No deliveries have been completed yet",
                        ),
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


class DeliveryListTab extends StatefulWidget {
  final List<Map<String, String>> deliveries;
  final String emptyMessages;

  const DeliveryListTab({
    super.key,
    required this.deliveries,
    required this.emptyMessages,
  });

  @override
  _DeliveryListTabState createState() => _DeliveryListTabState();
}

class _DeliveryListTabState extends State<DeliveryListTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.deliveries.isEmpty) {
      return Center(
        child: Text(
          widget.emptyMessages,
          style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: widget.deliveries.length,
      itemBuilder: (context, index) {
        final d = widget.deliveries[index];
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
    onTap: () async {
      final doc = await FirebaseFirestore.instance
          .collection('delivery')
          .doc(code)
          .get();

      if (!doc.exists) return;

      final data = doc.data() as Map<String, dynamic>;
      final List<Map<String, dynamic>> deliveryItems =
      List<Map<String, dynamic>>.from(data['deliveryItems'] ?? []);

      showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: "Delivery Details",
        barrierColor: Colors.black.withOpacity(0.5),
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, anim1, anim2) {
          final loc = data['location'] != null
              ? LatLng(
            (data['location'] as GeoPoint).latitude,
            (data['location'] as GeoPoint).longitude,
          )
              : LatLng(5.40688, 100.30968);
          print('Delivery $code location: ${data['location']}');

          return Center(
            child: DeliveryDetailsPopUp(
              code: code,
              address: address,
              status: status,
              items: deliveryItems,
              location: loc,
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
                    child: FutureBuilder<DocumentSnapshot?>(
                      future: FirebaseFirestore.instance
                          .collection('delivery')
                          .doc(code)
                          .get()
                          .then((doc) async {
                        if (!doc.exists) return null;

                        final data = doc.data() as Map<String, dynamic>;
                        final items = List<Map<String, dynamic>>.from(
                          data['deliveryItems'] ?? [],
                        );

                        if (items.isEmpty) return null;

                        final firstItemId = items.first['itemID'];
                        return FirebaseFirestore.instance
                            .collection('items')
                            .doc(firstItemId)
                            .get();
                      }),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const SizedBox(
                            width: 60,
                            height: 60,
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        }

                        // Handle null or non-existing doc
                        if (!snapshot.hasData ||
                            snapshot.data == null ||
                            !snapshot.data!.exists) {
                          return Image.asset(
                            'assets/images/EngineOils.jpg',
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                          );
                        }

                        final data =
                        snapshot.data!.data() as Map<String, dynamic>;
                        final imageUrl = data['imageUrl'] ?? '';

                        return imageUrl.isNotEmpty
                            ? Image.network(
                          imageUrl,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Image.asset(
                            'assets/images/EngineOils.jpg',
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                          ),
                        )
                            : Image.asset(
                          'assets/images/EngineOils.jpg',
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                        );
                      },
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
  final String status;
  final List<Map<String, dynamic>> items;
  final LatLng? location;

  const DeliveryDetailsPopUp({
    super.key,
    required this.code,
    required this.address,
    required this.status,
    required this.items,
    this.location,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;

    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: Container(
          width: width * 0.9,
          constraints: BoxConstraints(
            maxHeight: height * 0.8,
          ),
          padding: EdgeInsets.all(width * 0.05),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              // Scrollable content
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Delivery code
                      Text(
                        '# $code',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: width * 0.045, // scaled
                        ),
                      ),
                      SizedBox(height: height * 0.015),

                      // Map
                      Container(
                        height: height * 0.25, // scaled height
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: GoogleMap(
                          mapType: MapType.normal,
                          initialCameraPosition: CameraPosition(
                            target: location ?? LatLng(5.40688, 100.30968),
                            zoom: 15,
                          ),
                          markers: {
                            Marker(
                              markerId: MarkerId(code),
                              position: location ?? LatLng(5.40688, 100.30968),
                              infoWindow: InfoWindow(title: 'Delivery Location'),
                            ),
                          },
                          myLocationEnabled: false,
                          zoomControlsEnabled: false,
                        ),
                      ),
                      SizedBox(height: height * 0.015),

                      // Address
                      Row(
                        children: [
                          const Icon(Icons.location_pin),
                          SizedBox(width: width * 0.02),
                          Expanded(child: Text(address)),
                        ],
                      ),
                      SizedBox(height: height * 0.02),

                      // Goods Detail
                      Text(
                        'Goods Detail',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: width * 0.04,
                        ),
                      ),
                      SizedBox(height: height * 0.01),

                      // Items horizontally
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: items.map((item) {
                            return FutureBuilder<DocumentSnapshot>(
                              future: FirebaseFirestore.instance
                                  .collection('items')
                                  .doc(item['itemID'])
                                  .get(),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) return const SizedBox();
                                final data = snapshot.data!.data() as Map<String, dynamic>?;
                                final imageUrl = data?['imageUrl'] ?? '';
                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.grey.shade100, width: 1.5),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: imageUrl.isNotEmpty
                                          ? Image.network(
                                        imageUrl,
                                        width: 50,
                                        height: 50,
                                        fit: BoxFit.cover,
                                      )
                                          : Image.asset(
                                        'assets/images/EngineOils.jpg',
                                        width: 50,
                                        height: 50,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          }).toList(),
                        ),
                      ),
                      SizedBox(height: height * 0.02),

                      // Items vertical detail
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: items.map((item) {
                          return FutureBuilder<DocumentSnapshot>(
                            future: FirebaseFirestore.instance
                                .collection('items')
                                .doc(item['itemID'])
                                .get(),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) return const SizedBox();
                              final data = snapshot.data!.data() as Map<String, dynamic>?;
                              final name = data?['itemName'] ?? 'Unknown';
                              final price = (data?['price'] ?? 0).toDouble();
                              final qty = item['quantity'] ?? 0;
                              return Text(
                                '• $name | RM ${price.toStringAsFixed(2)} x $qty',
                                style: const TextStyle(color: Colors.grey),
                              );
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),

              SizedBox(height: height * 0.02),

              // Fixed button
              Builder(
                builder: (_) {
                  if (status == 'New Order') {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              vertical: 5,
                              horizontal: 38,
                            ),
                            backgroundColor: Colors.grey.shade200,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(7),
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              color: Colors.grey,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            FirebaseFirestore.instance
                                .collection('delivery')
                                .doc(code)
                                .update({'status': 'On-Going'});
                            Navigator.of(context).pop();
                          },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              vertical: 5,
                              horizontal: 30,
                            ),
                            backgroundColor: const Color(0xFF1B6C07),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(7),
                            ),
                          ),
                          child: const Text(
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
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => GoogleMapPage(
                              deliveryCode: code,
                              deliveryAddress: address,
                              deliveryLocation: location,
                              deliveryStatus: status,
                              deliveryItems: items,
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          vertical: 5,
                          horizontal: 10,
                        ),
                        backgroundColor: const Color(0xFF1B6C07),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                      child: const Text(
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
                        padding: const EdgeInsets.symmetric(
                          vertical: 5,
                          horizontal: 30,
                        ),
                        backgroundColor: const Color(0xFF1B6C07),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                      child: const Text(
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
            ],
          ),
        ),
      ),
    );
  }
}
