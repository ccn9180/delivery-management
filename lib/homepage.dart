import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delivery/profile_page.dart';
import 'package:delivery/widget/header.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
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
  final DateTime? deliveredAt;
  final GeoPoint? location;

  Delivery({
    required this.code,
    required this.address,
    required this.date,
    required this.status,
    required this.items,
    this.reason,
    this.deliveryProof,
    this.deliveredAt,
    this.location,
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
      deliveredAt: data['deliveredAt'] != null
          ? (data['deliveredAt'] as Timestamp).toDate().toLocal()
          : null,
      location: data['location'],
    );
  }
}

// Cache for items, avoid re-reading the same doc
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

// Preload all items in the cache
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
       DeliveryHistory(),
       DeliveryListPage(),
       ProfilePage(),
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
                    final delivered = deliveries
                        .where((d) => d.status == 'Delivered')
                        .length;
                    final failed = deliveries
                        .where((d) => d.status == 'Failed')
                        .length;

                    // Percentages
                    final deliveredPercent = total == 0
                        ? 0.0
                        : delivered / total;
                    final failedPercent = total == 0 ? 0.0 : failed / total;
                    final remainingPercent =
                        1.0 - deliveredPercent - failedPercent;

                    return SizedBox(
                      width: 50,
                      height: 50,
                      child: CircularPercentIndicator(
                        radius: 20,
                        lineWidth: 6,
                        percent: 1.0,
                        backgroundColor: Colors.grey.shade200,
                        progressColor: Colors.transparent,
                        circularStrokeCap: CircularStrokeCap.butt,
                        center: Stack(
                          alignment: Alignment.center,
                          children: [
                            // grey for remaining
                            CircularPercentIndicator(
                              radius: 20,
                              lineWidth: 6,
                              percent: remainingPercent,
                              backgroundColor: Colors.transparent,
                              progressColor: Colors.grey.shade200,
                              circularStrokeCap: CircularStrokeCap.butt,
                              startAngle: 0,
                            ),
                            // red for failed
                            CircularPercentIndicator(
                              radius: 20,
                              lineWidth: 6,
                              percent: failedPercent,
                              backgroundColor: Colors.transparent,
                              progressColor: Colors.red,
                              circularStrokeCap: CircularStrokeCap.butt,
                              startAngle: 360 * remainingPercent,
                            ),
                            // green for delivered
                            CircularPercentIndicator(
                              radius: 20,
                              lineWidth: 6,
                              percent: deliveredPercent,
                              backgroundColor: Colors.transparent,
                              progressColor: Colors.green,
                              circularStrokeCap: CircularStrokeCap.butt,
                              startAngle:
                                  360 * (remainingPercent + failedPercent),
                            ),
                            // Center text
                            Text(
                              "$delivered/$total",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // TabBar
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.only(left: 8),
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  padding: EdgeInsets.zero,
                  labelPadding: EdgeInsets.symmetric(horizontal: 8),
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
                    Tab(
                      child: Text("New Order", overflow: TextOverflow.visible),
                    ),
                    Tab(
                      child: Text("On-Going", overflow: TextOverflow.visible),
                    ),
                    Tab(
                      child: Text("Delivered", overflow: TextOverflow.visible),
                    ),
                    Tab(child: Text("Failed", overflow: TextOverflow.visible)),
                  ],
                ),
              ),

              SizedBox(height: 10),

              // TabBarView
              Expanded(
                child: StreamBuilder<List<Delivery>>(
                  stream: fetchEmployeeDeliveries(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(child: CircularProgressIndicator());
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

class _DeliveryListTabState extends State<DeliveryListTab>
    with AutomaticKeepAliveClientMixin {
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
      return Center(child: CircularProgressIndicator());
    }

    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: widget.deliveries.length,
      itemBuilder: (context, index) {
        final delivery = widget.deliveries[index];

        // Format date and time
        final dateStr = DateFormat('dd/MM/yyyy').format(delivery.date);
        final timeStr = DateFormat('hh:mm a').format(delivery.date);

        return Padding(
          padding: EdgeInsets.fromLTRB(7, 0, 7, 16),
          child: deliveryCard(
            context: context,
            delivery: delivery,
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
  final location = delivery.location;
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
        transitionDuration: Duration(milliseconds: 300),
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
        padding: EdgeInsets.all(16),
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
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 14),
                      Row(
                        children: [
                          Text(
                            '# $code',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                            ),
                          ),
                          Spacer(),
                          if (status == 'On-Going' ||
                              status == 'Delivered' ||
                              status == 'Failed')
                            Transform.translate(
                              offset: Offset(0, -14.5),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Container(
                                  padding: EdgeInsets.symmetric(
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
                            ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.calendar_today, size: 16),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              dateStr,
                              style: TextStyle(fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(Icons.access_time, size: 16),
                          SizedBox(width: 6),
                          Text(timeStr, style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Divider(color: Colors.grey.shade300, thickness: 1),
            SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.location_on, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(address, style: TextStyle(fontSize: 11.5)),
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

    final location = delivery.location != null
        ? LatLng(delivery.location!.latitude, delivery.location!.longitude)
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
                      SizedBox(height: 12),
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
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.location_pin),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              delivery.address,
                              style: TextStyle(fontSize: width * 0.035),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 17),
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
                            padding: EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
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
                      SizedBox(height: 8),

                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: delivery.items.map((item) {
                            final cached = _itemCache[item['itemID']];
                            final imageUrl = cached?['imageUrl'] ?? '';
                            return Padding(
                              padding: EdgeInsets.symmetric(horizontal: 6),
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

                      SizedBox(height: 12),
                      Table(
                        columnWidths: {
                          0: FlexColumnWidth(7),
                          1: FlexColumnWidth(2),
                        },
                        children: delivery.items.map((item) {
                          final cached = _itemCache[item['itemID']];
                          final name = cached?['itemName'] ?? 'Unknown';
                          final qty = item['quantity'] ?? 0;

                          return TableRow(
                            children: [
                              Padding(
                                padding: EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  name,
                                  style: TextStyle(
                                    fontSize: width * 0.035,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(vertical: 4),
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
              SizedBox(height: 12),
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
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
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
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              FirebaseFirestore.instance
                                  .collection('delivery')
                                  .doc(delivery.code)
                                  .update({'status': 'On-Going'});

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '#${delivery.code} has been accepted and is now On-Going',
                                  ),
                                  duration: Duration(seconds: 2),
                                  backgroundColor: Colors.green,
                                ),
                              );

                              Navigator.of(context).pop();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFF1B6C07),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
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
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              'Back',
                              style: TextStyle(
                                color: Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => GoogleMapPage(
                                  deliveryCode: delivery.code,
                                  deliveryAddress: delivery.address,
                                  deliveryLocation: delivery.location != null
                                      ? LatLng(
                                          delivery.location!.latitude,
                                          delivery.location!.longitude,
                                        )
                                      : LatLng(5.40688, 100.30968),
                                  deliveryStatus: delivery.status,
                                  deliveryItems: delivery.items,
                                ),
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFF1B6C07),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              'Navigation',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
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
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              'Back',
                              style: TextStyle(
                                color: Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: Text(
                                    "Reason for Failure",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                    ),
                                  ),
                                  content: Text(
                                    delivery.reason ?? "No reason provided",
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      child: Text("Close"),
                                    ),
                                  ],
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade400,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              'View Reason',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
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
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              'Back',
                              style: TextStyle(
                                color: Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (context) {
                                  return AlertDialog(
                                    title: Text(
                                      "Delivery Confirmation",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 20,
                                      ),
                                    ),
                                    content: SingleChildScrollView(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "# ${delivery.code}",
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: Colors.black,
                                            ),
                                          ),
                                          SizedBox(height: 12),
                                          Text(
                                            "Delivered At: ${DateFormat('dd/MM/yyyy hh:mm a').format(delivery.deliveredAt!)}",
                                          ),
                                          SizedBox(height: 12),
                                          if (delivery.deliveryProof != null &&
                                              delivery
                                                  .deliveryProof!
                                                  .isNotEmpty) ...[
                                            SizedBox(height: 12),
                                            Text(
                                              "Delivery Proof Image:",
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                            SizedBox(height: 6),

                                            Builder(
                                              builder: (_) {
                                                try {
                                                  Uint8List bytes =
                                                      base64Decode(
                                                        delivery.deliveryProof!,
                                                      );
                                                  return ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                    child: Image.memory(
                                                      bytes,
                                                      width: double.infinity,
                                                      height: 200,
                                                      fit: BoxFit.cover,
                                                    ),
                                                  );
                                                } catch (e) {
                                                  return Container(
                                                    width: double.infinity,
                                                    height: 200,
                                                    color: Colors.grey.shade200,
                                                    child: Center(
                                                      child: Text(
                                                        "Invalid image data",
                                                      ),
                                                    ),
                                                  );
                                                }
                                              },
                                            ),
                                          ],
                                          if (delivery.reason != null)
                                            Text("Notes: ${delivery.reason}"),
                                        ],
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(),
                                        child: Text("Close"),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFF1B6C07),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              'View Details',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        'Back',
                        style: TextStyle(color: Colors.white),
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
