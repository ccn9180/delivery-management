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
  final String? reason;
  final String? deliveryProof;

  Delivery({
    required this.code,
    required this.address,
    required this.date,
    required this.status,
    required this.items,
    this.reason,
    this.deliveryProof,
  });

  factory Delivery.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Delivery(
      code: doc.id,
      address: data['address'] ?? '',
      date: (data['deliveryDate'] as Timestamp).toDate().toLocal(),
      status: data['status'] ?? 'New Order',
      items: List<Map<String, dynamic>>.from(data['deliveryItems'] ?? []),
      reason: data['reason'],
      deliveryProof: data['deliveryProof'],
    );
  }
}

/// Cache for items to avoid re-reading the same doc
final Map<String, Map<String, dynamic>> _itemCache = {};

Future<String?> fetchEmployeeCode() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;

  final userDoc = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .get();

  return userDoc.data()?['employeeID'];
}

Stream<List<Delivery>> fetchEmployeeDeliveries() async* {
  final employeeCode = await fetchEmployeeCode();
  if (employeeCode == null) {
    yield [];
    return;
  }

  final now = DateTime.now();
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
      .map(
        (snapshot) =>
        snapshot.docs.map((doc) => Delivery.fromDoc(doc)).toList(),
  );
}

/// Preload all items in the cache
Future<void> preloadItems(List<Delivery> deliveries) async {
  final ids = deliveries
      .expand((d) => d.items.map((i) => i['itemID'] as String))
      .toSet();
  final missing = ids.where((id) => !_itemCache.containsKey(id)).toList();

  if (missing.isNotEmpty) {
    final snaps = await FirebaseFirestore.instance
        .collection('items')
        .where(
      FieldPath.documentId,
      whereIn: missing.take(10).toList(),
    ) // Firestore allows max 10 in whereIn
        .get();

    for (var doc in snaps.docs) {
      _itemCache[doc.id] = doc.data();
    }

    // If more than 10, fetch in batches
    if (missing.length > 10) {
      for (var i = 10; i < missing.length; i += 10) {
        final batch = missing.skip(i).take(10).toList();
        final extraSnaps = await FirebaseFirestore.instance
            .collection('items')
            .where(FieldPath.documentId, whereIn: batch)
            .get();
        for (var doc in extraSnaps.docs) {
          _itemCache[doc.id] = doc.data();
        }
      }
    }
  }
}

//-----------------------HOME PAGE--------------------------------
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
    _pages = [
      const DeliveryHistory(),
      const DeliveryListPage(),
      const ProfilePage(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
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

//---------------------------------DELIVERY LIST PAGE---------------------------------
class DeliveryListPage extends StatelessWidget {
  const DeliveryListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
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
                    final failed = deliveries.where((d) => d.status == 'Failed').length;

                    final deliveredProgress = total == 0 ? 0.0 : delivered / total;
                    final failedProgress = total == 0 ? 0.0 : failed / total;

                    return SizedBox(
                    width: 50,
                    height: 50,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Background circle (gray for remaining)
                        CircularProgressIndicator(
                          value: 1.0,
                          strokeWidth: 6,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.grey.shade200),
                        ),

                        // Failed portion
                        CircularProgressIndicator(
                          value: failedProgress,
                          strokeWidth: 6,
                          backgroundColor: Colors.transparent,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                        ),

                        // Delivered portion (on top of failed)
                        CircularProgressIndicator(
                          value: deliveredProgress,
                          strokeWidth: 6,
                          backgroundColor: Colors.transparent,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                        ),

                        // Center text
                        Text(
                          "$delivered/$total",
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
                  Tab(text:"Failed")
                ],
              ),

              const SizedBox(height: 10),

              // TabBarView
              Expanded(
                child: StreamBuilder<List<Delivery>>(
                  stream: fetchEmployeeDeliveries(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final deliveries = snapshot.data!;
                    preloadItems(deliveries);

                    final newOrder = deliveries
                        .where((d) => d.status == 'New Order')
                        .toList();
                    final ongoing = deliveries
                        .where((d) => d.status == 'On-Going')
                        .toList();
                    final finished = deliveries
                        .where((d) => d.status == 'Delivered')
                        .toList();
                    final failed = deliveries
                        .where((d) => d.status == 'Failed')
                        .toList();

                    final dateFormat = DateFormat('dd/MM/yyyy');
                    final timeFormat = DateFormat('hh:mm a');

                    return TabBarView(
                      children: [
                        DeliveryListTab(
                          deliveries: newOrder,
                          emptyMessages: "No new orders",
                        ),
                        DeliveryListTab(
                          deliveries: ongoing,
                          emptyMessages: "No ongoing deliveries",
                        ),
                        DeliveryListTab(
                          deliveries: finished,
                          emptyMessages: "No completed deliveries",
                        ),
                        DeliveryListTab(
                          deliveries: failed,
                          emptyMessages: "No failed deliveries",
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

//-------------------------------------TAB-----------------------------------------------
class DeliveryListTab extends StatefulWidget {
  final List<Delivery> deliveries;
  final String emptyMessages;

  const DeliveryListTab({
    super.key,
    required this.deliveries,
    required this.emptyMessages,
  });

  @override
  _DeliveryListTabState createState() => _DeliveryListTabState();
}

class _DeliveryListTabState extends State<DeliveryListTab> with AutomaticKeepAliveClientMixin {
  @override
  bool _itemsLoaded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    await preloadItems(widget.deliveries);
    if (mounted) {
      setState(() {
        _itemsLoaded = true;
      });
    }
  }

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

    if (!_itemsLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: widget.deliveries.length,
      itemBuilder: (context, index) {
        final delivery = widget.deliveries[index];

        // Format date and time
        final dateStr = DateFormat('dd/MM/yyyy').format(delivery.date);
        final timeStr = DateFormat('hh:mm a').format(delivery.date);

        return Padding(
          padding: const EdgeInsets.fromLTRB(7, 0, 7, 16),
          child: deliveryCard(
            context: context,
            delivery: delivery, // pass full object
            date: dateStr,
            time: timeStr,
          ),
        );
      },
    );
  }
}

//--------------------------------DELIVERY CARD------------------------------------------
Widget deliveryCard({
  required BuildContext context,
  required Delivery delivery,
  required String date,
  required String time,
}) {
  final code = delivery.code;
  final status = delivery.status;
  final address = delivery.address;
  final dateStr = DateFormat('dd/MM/yyyy').format(delivery.date);
  final timeStr = DateFormat('hh:mm a').format(delivery.date);

  return GestureDetector(
    onTap: () {
      showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: "Delivery Details",
        barrierColor: Colors.black.withOpacity(0.5),
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, anim1, anim2) {
          return Center(child: DeliveryDetailsPopUp(delivery: delivery));
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Item image
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade100, width: 1.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Builder(
                      builder: (_) {
                        if (delivery.items.isEmpty) {
                          return Image.asset(
                            'assets/images/noimage.png',
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                          );
                        }

                        final firstItemId = delivery.items.first['itemID'];
                        final cached = _itemCache[firstItemId];
                        final imageUrl = cached?['imageUrl'] ?? '';

                        return imageUrl.isNotEmpty
                            ? Image.network(
                          imageUrl,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Image.asset(
                            'assets/images/noimage.png',
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                          ),
                        )
                            : Image.asset(
                          'assets/images/noimage.png',
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
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                            ),
                          ),
                          const Spacer(),
                          if (status == 'On-Going' || status == 'Delivered'|| status == 'Failed')
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
                                      : status == 'Failed'
                                      ? Colors.red.shade100
                                      : Colors.blue.shade100,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  status,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: status == 'Delivered'
                                        ? Colors.green
                                        : status == 'Failed'
                                        ? Colors.red
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
                          Text(dateStr, style: const TextStyle(fontSize: 12)),
                          const SizedBox(width: 12),
                          const Icon(Icons.access_time, size: 16),
                          const SizedBox(width: 6),
                          Text(timeStr, style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
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

//--------------------------------DELIVERY DETAILS POP UP-------------------------------------
class DeliveryDetailsPopUp extends StatelessWidget {
  final Delivery delivery;

  const DeliveryDetailsPopUp({super.key, required this.delivery});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;

    final location =
    delivery.items.isNotEmpty && delivery.items.first['location'] != null
        ? LatLng(
      (delivery.items.first['location'] as GeoPoint).latitude,
      (delivery.items.first['location'] as GeoPoint).longitude,
    )
        : LatLng(5.40688, 100.30968);

    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: Container(
          width: width * 0.9,
          constraints: BoxConstraints(maxHeight: height * 0.8),
          padding: EdgeInsets.all(width * 0.05),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '# ${delivery.code}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: width * 0.045,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        height: height * 0.23,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: GoogleMap(
                          mapType: MapType.normal,
                          initialCameraPosition: CameraPosition(
                            target: location,
                            zoom: 15,
                          ),
                          markers: {
                            Marker(
                              markerId: MarkerId(delivery.code),
                              position: location,
                            ),
                          },
                          zoomControlsEnabled: false,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.location_pin),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              delivery.address,
                              style: TextStyle(fontSize: width * 0.035),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 17),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Goods Detail',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: width * 0.04,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${delivery.items.length} item${delivery.items.length > 1 ? 's' : ''}',
                              style: TextStyle(
                                fontSize: width * 0.03,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Horizontal items
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: delivery.items.map((item) {
                            final cached = _itemCache[item['itemID']];
                            final imageUrl = cached?['imageUrl'] ?? '';
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.grey.shade100,
                                    width: 1.5,
                                  ),
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
                                    'assets/images/noimage.png',
                                    width: 50,
                                    height: 50,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                      const SizedBox(height: 12),
                      Table(
                        columnWidths: const {
                          0: FlexColumnWidth(5),
                          1: FlexColumnWidth(2),
                          2: FlexColumnWidth(1),
                        },
                        children: delivery.items.map((item) {
                          final cached = _itemCache[item['itemID']];
                          final name = cached?['itemName'] ?? 'Unknown';
                          final price = (cached?['price'] ?? 0).toDouble();
                          final qty = item['quantity'] ?? 0;

                          return TableRow(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                ),
                                child: Text(
                                  name,
                                  style: TextStyle(
                                    fontSize: width * 0.035,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                ),
                                child: Text(
                                  'RM ${price.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: width * 0.035,
                                    color: Colors.grey,
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                ),
                                child: Text(
                                  'x $qty',
                                  style: TextStyle(
                                    fontSize: width * 0.035,
                                    color: Colors.grey,
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Buttons
              Builder(
                builder: (_) {
                  if (delivery.status == 'New Order') {
                    return Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey.shade200,
                            ),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              FirebaseFirestore.instance
                                  .collection('delivery')
                                  .doc(delivery.code)
                                  .update({'status': 'On-Going'});
                              Navigator.of(context).pop();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFF1B6C07),
                            ),
                            child: const Text(
                              'Accepted',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    );
                  } else if (delivery.status == 'On-Going') {
                    return Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey.shade200,
                            ),
                            child: const Text(
                              'Back',
                              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => GoogleMapPage(
                                  deliveryCode: delivery.code,
                                  deliveryAddress: delivery.address,
                                  deliveryLocation: location,
                                  deliveryStatus: delivery.status,
                                  deliveryItems: delivery.items,
                                ),
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFF1B6C07),
                            ),
                            child: const Text(
                              'Navigation',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    );
                  } else if (delivery.status == 'Failed') {
                    return Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey.shade200,
                            ),
                            child: const Text(
                              'Back',
                              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text(
                                    "Reason for Failure",
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                                  ),
                                  content: Text(delivery.reason ?? "No reason provided"),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(context).pop(),
                                      child: const Text("Close"),
                                    ),
                                  ],
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade400,
                            ),
                            child: const Text(
                              'View Reason',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    );
                  } else if (delivery.status == 'Delivered') {
                    return Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey.shade200,
                            ),
                            child: const Text(
                              'Back',
                              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (context) {
                                  return AlertDialog(
                                    title: const Text(
                                      "Delivery Confirmation",
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold, fontSize: 20),
                                    ),
                                    content: SingleChildScrollView(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text("Delivery Code: #${delivery.code}"),
                                          const SizedBox(height: 8),
                                          Text(
                                            "Delivered On: ${DateFormat('dd/MM/yyyy hh:mm a').format(delivery.date)}",
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            "Items Delivered:",
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold),
                                          ),
                                          const SizedBox(height: 6),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: delivery.items.map((item) {
                                              final cached = _itemCache[item['itemID']];
                                              final name = cached?['itemName'] ?? 'Unknown';
                                              final qty = item['quantity'] ?? 0;
                                              return Text("- $name x$qty");
                                            }).toList(),
                                          ),
                                          const SizedBox(height: 12),
                                          if (delivery.deliveryProof != null &&
                                              delivery.deliveryProof!.isNotEmpty) ...[
                                            const SizedBox(height: 12),
                                            Text(
                                              "Delivery Proof:",
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14),
                                            ),
                                            const SizedBox(height: 6),

                                            Image.network(
                                              delivery.deliveryProof!,
                                              width: double.infinity,
                                              height: 200,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => Container(
                                                width: double.infinity,
                                                height: 200,
                                                color: Colors.grey.shade200,
                                                child: const Center(
                                                  child: Text("Failed to load image"),
                                                ),
                                              ),
                                            ),
                                          ],
                                          if (delivery.reason != null)
                                            Text("Notes: ${delivery.reason}"),
                                        ],
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.of(context).pop(),
                                        child: const Text("Close"),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFF1B6C07),
                            ),
                            child: const Text(
                              'View Details',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    );
                  } else {
                    return ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF1B6C07),
                      ),
                      child: const Text(
                        'Back',
                        style: TextStyle(color: Colors.white),
                      ),
                    );
                  }
                },
              )
            ],
          ),
        ),
      ),
    );
  }
}
