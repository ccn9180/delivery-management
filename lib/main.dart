import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

final List<Map<String, String>> deliveries = [
  {
    'image': 'https://via.placeholder.com/60x60.png?text=Oil',
    'status': 'On-Going',
    'code': 'MSN 10001',
    'date': '27 July, 2025',
    'time': '3:00 PM',
    'address':
    '29, Jalan P. Ramlee, Taman P. Ramlee, 10460 George Town, Pulau Pinang',
  },
  {
    'image': 'https://via.placeholder.com/60x60.png?text=Parts',
    'status': 'On-Going',
    'code': 'MSN 10002',
    'date': '28 July, 2025',
    'time': '11:00 AM',
    'address':
    '88, Jalan Burma, George Town, 10050 George Town, Pulau Pinang',
  },
  {
    'image': 'https://via.placeholder.com/60x60.png?text=Oil',
    'status': 'Delivered',
    'code': 'MSN 10003',
    'date': '25 July, 2025',
    'time': '4:45 PM',
    'address':
    '21, Lebuh Acheh, George Town, 10300 George Town, Pulau Pinang',
  },
  {
    'image': 'https://via.placeholder.com/60x60.png?text=Oil',
    'status': 'New Order',
    'code': 'MSN 10011',
    'date': '27 July, 2025',
    'time': '3:00 PM',
    'address':
    '30, Jalan P. Ramlee, Taman P. Ramlee, 10460 George Town, Pulau Pinang',
  },
];

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: const MainPage());
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});
  @override
  State<MainPage> createState() => _MainPageStatus();
}

class _MainPageStatus extends State<MainPage> {
  int _selectedIndex = 1;
  late List<Map<String, String>> finished;
  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    finished = deliveries.where((d) => d['status'] == 'Delivered').toList();
    _pages = [
      DeliveryHistory(deliveries: finished),
      const DeliveryListPage(),
      const Center(child: Text("ProfilePage")),
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
    final newOrder = deliveries.where((d) => d['status'] == 'New Order').toList();
    final ongoing = deliveries.where((d) => d['status'] == 'On-Going').toList();
    final finished = deliveries.where((d) => d['status'] == 'Delivered').toList();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(25, 20, 18, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "try1",
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
                alignment: Alignment.centerLeft,
                child: TabBar(
                  labelPadding: EdgeInsets.only(right: 30),
                  isScrollable: true,
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
                child: TabBarView(
                  children: [
                    DeliveryListTab(deliveries: newOrder),
                    DeliveryListTab(deliveries: ongoing),
                    DeliveryListTab(deliveries: finished),
                  ],
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
                  child:GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(5.4194, 100.3327),
                      zoom:15,
                    ),
                    markers: {
                      Marker(
                        markerId: MarkerId('delivery'),
                        position: LatLng(5.4194, 100.3327),
                      ),
                    },
                    zoomControlsEnabled: false,
                    myLocationEnabled: false,
                    liteModeEnabled: true,
                    onMapCreated: (controller){},
                  ),
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
  final List<Map<String, String>> deliveries;
  const DeliveryHistory({super.key,required this.deliveries});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(25, 20, 18, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Delivery History',
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
                      child: CircleAvatar(
                        radius: 22,
                        backgroundColor: Colors.white,
                        child: Icon(Icons.person,color: Color(0xFF1B6C07),size:27,
                        ),
                      ),
                    )
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
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
                ),
              ),
            ],
          )
      ),
    );
  }
}

