import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as permission_handler_plugin;
import 'package:http/http.dart' as http;

class GoogleMapPage extends StatefulWidget {
  final String? deliveryCode;
  final String? deliveryAddress;
  final LatLng? deliveryLocation;
  final String? deliveryStatus;
  final List<Map<String, dynamic>>? deliveryItems;

  const GoogleMapPage({
    super.key,
    this.deliveryCode,
    this.deliveryAddress,
    this.deliveryLocation,
    this.deliveryStatus,
    this.deliveryItems,
  });

  @override
  State<GoogleMapPage> createState() => _GoogleMapPageState();
}

class _GoogleMapPageState extends State<GoogleMapPage> {
  GoogleMapController? _mapController;
  LatLng? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  bool _isLoading = true;
  String _errorMessage = '';
  bool _locationServiceEnabled = false;
  LocationPermission _locationPermission = LocationPermission.denied;

  // Navigation related variables
  bool _isNavigating = false;
  bool _isCalculatingRoute = false;
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  LatLng? _destination;
  // Remove PolylinePoints instance - we'll use direct decoding
  String _googleApiKey = "AIzaSyBwfTQ-3Qpia1X0zkpy8Dw6R6MV8HI016U"; // replace with your API key

  // Navigation direction variables
  String _currentDirection = "Head towards destination";
  double _currentBearing = 0.0;
  List<LatLng> _routePoints = [];
  int _currentRouteIndex = 0;

  // TARUMT Penang branch coordinates (origin)
  static const LatLng _tarumtPenang = LatLng(5.40688, 100.30968);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeLocationAndMap();
    });
  }

  Future<void> _initializeLocationAndMap() async {
    if (!mounted) return;

    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      _locationServiceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!_locationServiceEnabled) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Location services are disabled. Please enable them in your device settings.';
            _isLoading = false;
          });
        }
        return;
      }

      _locationPermission = await Geolocator.checkPermission();
      if (_locationPermission == LocationPermission.denied) {
        _locationPermission = await Geolocator.requestPermission();
        if (_locationPermission == LocationPermission.denied) {
          if (mounted) {
            setState(() {
              _errorMessage = 'Location permission denied. Please grant permission to use this feature.';
              _isLoading = false;
            });
          }
          return;
        }
      }

      if (_locationPermission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Location permission is permanently denied. Please enable it from the app settings.';
            _isLoading = false;
          });
        }
        return;
      }

      await _getCurrentLocation();
      // 🚀 Auto-start navigation after current location is found
      if (mounted && _currentPosition != null) {
        _startNavigation();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error initializing location: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
        _isLoading = false;
        _errorMessage = '';
      });

      _moveCameraToCurrentPosition();
      _startLocationTracking();
    } catch (e) {
      setState(() {
        _errorMessage = 'Error getting current location: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  void _moveCameraToCurrentPosition() {
    if (_mapController != null && _currentPosition != null) {
      // Set initial camera with delivery man's perspective
      CameraPosition cameraPosition = CameraPosition(
        target: _currentPosition!,
        zoom: 19, // High zoom for street-level view
        bearing: _currentBearing, // Rotate camera to show direction
        tilt: 45, // Slight tilt for better perspective
      );

      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(cameraPosition),
      );
    }
  }

  void _startLocationTracking() {
    if (_locationPermission != LocationPermission.whileInUse &&
        _locationPermission != LocationPermission.always) {
      return;
    }

    _positionStream?.cancel();
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high, // High accuracy for better precision
        distanceFilter: 5, // Reduced distance filter for more frequent updates
        timeLimit: Duration(seconds: 30), // Add timeout
      ),
    ).listen(
          (Position position) {
        if (mounted) {
          setState(() {
            _currentPosition = LatLng(position.latitude, position.longitude);
          });
          if (_isNavigating && _destination != null) {
            _updateNavigation(position);
          }
        }
      },
      onError: (error) {
        debugPrint('Location tracking error: $error');
        // Don't show error to user, just log it
      },
    );
  }

  void _updateNavigation(Position position) {
    if (mounted && _mapController != null && _currentPosition != null) {
      setState(() {
        _markers.removeWhere((marker) => marker.markerId.value == "origin");
        _markers.add(
          Marker(
            markerId: const MarkerId("origin"),
            position: _currentPosition!,
            infoWindow: const InfoWindow(title: "Current Location"),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          ),
        );
      });

      // Update navigation direction
      _updateNavigationDirection();

      // Follow delivery man's perspective with bearing
      _followDeliveryManPerspective();
    }
  }

  // Follow delivery man's perspective with proper camera angle
  void _followDeliveryManPerspective() {
    if (_mapController == null || _currentPosition == null) return;

    try {
      // Create camera position that follows the delivery man's direction
      CameraPosition cameraPosition = CameraPosition(
        target: _currentPosition!,
        zoom: 19, // High zoom for street-level view
        bearing: _currentBearing, // Rotate camera to show direction
        tilt: 45, // Slight tilt for better perspective
      );

      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(cameraPosition),
      );
    } catch (e) {
      debugPrint('Camera perspective error: $e');
    }
  }

  Future<void> _startNavigation() async {
    if (_currentPosition == null) return;

    // Use delivery location if available, otherwise use TARUMT as fallback
    LatLng destination = widget.deliveryLocation ?? _tarumtPenang;

    setState(() {
      _isNavigating = true;
      _isCalculatingRoute = false; // Don't calculate, just show direction
      _destination = destination;
    });

    // Show route direction without calculating
    _showRouteDirection(_currentPosition!, destination);
  }

  void _stopNavigation() {
    setState(() {
      _isNavigating = false;
      _polylines.clear();
      _markers.clear();
      _destination = null;
    });
  }

  // Show route direction with real road-based navigation
  void _showRouteDirection(LatLng origin, LatLng destination) async {
    setState(() {
      _isCalculatingRoute = true;
    });

    try {
      // Get real road-based route from Google Directions API
      List<LatLng> roadPoints = await _getRoadBasedRoute(origin, destination);

      if (roadPoints.isNotEmpty) {
        _routePoints = roadPoints;
        _currentRouteIndex = 0;

        // Create main route polyline following actual roads
        Polyline mainRoute = Polyline(
          polylineId: const PolylineId("main_route"),
          color: const Color(0xFF4285F4), // Google Maps blue color
          width: 8, // Thick solid line
          points: roadPoints,
        );

        // Create markers for origin and destination
        Set<Marker> directionMarkers = {
          Marker(
            markerId: const MarkerId("origin"),
            position: origin,
            infoWindow: const InfoWindow(title: "TAR UMT Penang", snippet: "Starting Point"),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          ),
          Marker(
            markerId: const MarkerId("destination"),
            position: destination,
            infoWindow: const InfoWindow(title: "Delivery Destination", snippet: "End Point"),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          ),
        };

        setState(() {
          _polylines = {mainRoute};
          _markers = directionMarkers;
          _isCalculatingRoute = false;
        });

        // Update navigation direction
        _updateNavigationDirection();

        // Fit camera to show the entire route
        _fitCameraToPoints(roadPoints);
      } else {
        // Fallback to straight line if API fails
        _createFallbackRoute(origin, destination);
      }
    } catch (e) {
      debugPrint('Error getting road-based route: $e');
      // Fallback to straight line if API fails
      _createFallbackRoute(origin, destination);
    }
  }

  // Get real road-based route from Google Directions API
  Future<List<LatLng>> _getRoadBasedRoute(LatLng origin, LatLng destination) async {
    try {
      String url = 'https://maps.googleapis.com/maps/api/directions/json?'
          'origin=${origin.latitude},${origin.longitude}&'
          'destination=${destination.latitude},${destination.longitude}&'
          'mode=driving&'
          'key=$_googleApiKey';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
          String encodedPolyline = data['routes'][0]['overview_polyline']['points'];
          return _decodePolyline(encodedPolyline);
        }
      }
    } catch (e) {
      debugPrint('Error getting directions: $e');
    }

    return [];
  }

  // Fallback route if API fails
  void _createFallbackRoute(LatLng origin, LatLng destination) {
    List<LatLng> fallbackPoints = _createDetailedRoute(origin, destination);
    _routePoints = fallbackPoints;
    _currentRouteIndex = 0;

    Polyline mainRoute = Polyline(
      polylineId: const PolylineId("main_route"),
      color: const Color(0xFF4285F4),
      width: 8,
      points: fallbackPoints,
    );

    Set<Marker> directionMarkers = {
      Marker(
        markerId: const MarkerId("origin"),
        position: origin,
        infoWindow: const InfoWindow(title: "TAR UMT Penang", snippet: "Starting Point"),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
      Marker(
        markerId: const MarkerId("destination"),
        position: destination,
        infoWindow: const InfoWindow(title: "Delivery Destination", snippet: "End Point"),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    };

    setState(() {
      _polylines = {mainRoute};
      _markers = directionMarkers;
      _isCalculatingRoute = false;
    });

    _updateNavigationDirection();
    _fitCameraToPoints(fallbackPoints);
  }

  // Create a more detailed route with intermediate points for Google Maps-like navigation
  List<LatLng> _createDetailedRoute(LatLng origin, LatLng destination) {
    List<LatLng> points = [origin];

    // Calculate intermediate points for a more realistic route
    double latDiff = destination.latitude - origin.latitude;
    double lngDiff = destination.longitude - origin.longitude;

    // Add more intermediate points for smoother route (12-15 points)
    for (int i = 1; i <= 12; i++) {
      double factor = i / 13.0;
      double lat = origin.latitude + (latDiff * factor);
      double lng = origin.longitude + (lngDiff * factor);

      // Add realistic curves and turns like Google Maps
      if (i >= 2 && i <= 4) {
        // First curve section
        double curveOffset = 0.003 * sin((i - 2) * pi / 2); // Smooth curve
        lng += curveOffset;
      } else if (i >= 6 && i <= 8) {
        // Second curve section
        double curveOffset = 0.002 * cos((i - 6) * pi / 2); // Another smooth curve
        lat += curveOffset;
      } else if (i >= 9 && i <= 11) {
        // Final approach curve
        double curveOffset = 0.0015 * sin((i - 9) * pi / 2); // Gentle final curve
        lng += curveOffset;
      }

      points.add(LatLng(lat, lng));
    }

    points.add(destination);
    return points;
  }

  // Update navigation direction based on current position and route
  void _updateNavigationDirection() {
    if (_currentPosition == null || _routePoints.length < 2) return;

    // Find the closest point on the route
    double minDistance = double.infinity;
    int closestIndex = 0;

    for (int i = 0; i < _routePoints.length; i++) {
      double distance = _calculateDistanceInKm(_currentPosition!, _routePoints[i]);
      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }

    _currentRouteIndex = closestIndex;

    // Calculate bearing to next point
    if (closestIndex < _routePoints.length - 1) {
      LatLng nextPoint = _routePoints[closestIndex + 1];
      _currentBearing = _calculateBearing(_currentPosition!, nextPoint);
      _currentDirection = _getDirectionText(_currentBearing);
    } else {
      _currentDirection = "You have arrived at your destination";
    }
  }

  // Calculate bearing between two points
  double _calculateBearing(LatLng from, LatLng to) {
    double lat1 = from.latitude * (pi / 180);
    double lat2 = to.latitude * (pi / 180);
    double deltaLng = (to.longitude - from.longitude) * (pi / 180);

    double y = sin(deltaLng) * cos(lat2);
    double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLng);

    double bearing = atan2(y, x) * (180 / pi);
    return (bearing + 360) % 360;
  }

  // Get direction text based on bearing with turn instructions
  String _getDirectionText(double bearing) {
    if (bearing >= 337.5 || bearing < 22.5) return "Continue straight";
    if (bearing >= 22.5 && bearing < 67.5) return "Turn right ahead";
    if (bearing >= 67.5 && bearing < 112.5) return "Turn right";
    if (bearing >= 112.5 && bearing < 157.5) return "Turn right";
    if (bearing >= 157.5 && bearing < 202.5) return "Turn around";
    if (bearing >= 202.5 && bearing < 247.5) return "Turn left";
    if (bearing >= 247.5 && bearing < 292.5) return "Turn left";
    if (bearing >= 292.5 && bearing < 337.5) return "Turn left ahead";
    return "Continue straight";
  }


  // Calculate estimated travel time
  String _calculateEstimatedTime(LatLng origin, LatLng destination) {
    double distance = _calculateDistanceInKm(origin, destination);
    int estimatedMinutes = (distance * 2.5).round(); // Rough estimate: 2.5 min per km
    return "$estimatedMinutes min";
  }

  // Calculate distance
  String _calculateDistance(LatLng origin, LatLng destination) {
    double distance = _calculateDistanceInKm(origin, destination);
    return "${distance.toStringAsFixed(1)} km";
  }

  // Calculate distance in kilometers using Haversine formula
  double _calculateDistanceInKm(LatLng origin, LatLng destination) {
    const double earthRadius = 6371; // Earth's radius in kilometers

    double lat1Rad = origin.latitude * (pi / 180);
    double lat2Rad = destination.latitude * (pi / 180);
    double deltaLatRad = (destination.latitude - origin.latitude) * (pi / 180);
    double deltaLngRad = (destination.longitude - origin.longitude) * (pi / 180);

    double a = sin(deltaLatRad / 2) * sin(deltaLatRad / 2) +
        cos(lat1Rad) * cos(lat2Rad) *
            sin(deltaLngRad / 2) * sin(deltaLngRad / 2);
    double c = 2 * asin(sqrt(a));

    return earthRadius * c;
  }

  // Get estimated delivery time based on distance and delivery items
  String _getEstimatedDeliveryTime() {
    if (_currentPosition == null || _destination == null) {
      return "Estimated Time: 20-30 minutes";
    }

    double distance = _calculateDistanceInKm(_currentPosition!, _destination!);
    int baseMinutes = (distance * 2.5).round(); // Base time: 2.5 min per km

    // Add extra time based on delivery items count
    int itemCount = widget.deliveryItems?.length ?? 1;
    int extraMinutes = (itemCount * 2).clamp(0, 15); // 2 min per item, max 15 min

    int totalMinutes = baseMinutes + extraMinutes;
    int minTime = (totalMinutes * 0.8).round(); // 80% of calculated time
    int maxTime = (totalMinutes * 1.2).round(); // 120% of calculated time

    return "Estimated Time: $minTime-$maxTime minutes";
  }

  Future<void> _calculateRoute(LatLng origin, LatLng destination) async {
    try {
      List<LatLng> polylineCoordinates = await _getRouteCoordinates(origin, destination);
      if (polylineCoordinates.isNotEmpty) {
        Polyline polyline = Polyline(
          polylineId: const PolylineId("route"),
          color: Colors.blue,
          width: 5,
          points: polylineCoordinates,
        );

        Set<Marker> markers = {
          Marker(
            markerId: const MarkerId("origin"),
            position: origin,
            infoWindow: const InfoWindow(title: "Current Location"),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          ),
          Marker(
            markerId: const MarkerId("destination"),
            position: destination,
            infoWindow: const InfoWindow(title: "Delivery Destination"),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          ),
        };

        setState(() {
          _polylines = {polyline};
          _markers = markers;
          _isCalculatingRoute = false;
        });

        _fitCameraToRoute(polylineCoordinates);
      }
    } catch (e) {
      setState(() {
        _isCalculatingRoute = false;
      });
    }
  }

  Future<List<LatLng>> _getRouteCoordinates(LatLng origin, LatLng destination) async {
    List<LatLng> polylineCoordinates = [];
    try {
      String url =
          'https://maps.googleapis.com/maps/api/directions/json?origin=${origin.latitude},${origin.longitude}&destination=${destination.latitude},${destination.longitude}&key=$_googleApiKey';

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          String encodedPolyline = data['routes'][0]['overview_polyline']['points'];
          polylineCoordinates = _decodePolyline(encodedPolyline);
        }
      }
    } catch (e) {
      debugPrint('Error getting route coordinates: $e');
    }
    return polylineCoordinates;
  }

  // Decode polyline string to list of LatLng points
  List<LatLng> _decodePolyline(String polyline) {
    List<LatLng> points = [];
    int index = 0;
    int len = polyline.length;
    int lat = 0;
    int lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = polyline.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = polyline.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }

  // Fit camera to show points (for direction display) - optimized for delivery navigation
  void _fitCameraToPoints(List<LatLng> points) {
    if (points.isEmpty || _mapController == null) return;

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (LatLng point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    // Add padding for better view
    double latPadding = (maxLat - minLat) * 0.1;
    double lngPadding = (maxLng - minLng) * 0.1;

    LatLngBounds bounds = LatLngBounds(
      southwest: LatLng(minLat - latPadding, minLng - lngPadding),
      northeast: LatLng(maxLat + latPadding, maxLng + lngPadding),
    );

    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50.0)); // Reduced padding for closer view
  }

  void _fitCameraToRoute(List<LatLng> coordinates) {
    if (coordinates.isEmpty || _mapController == null) return;

    double minLat = coordinates.first.latitude;
    double maxLat = coordinates.first.latitude;
    double minLng = coordinates.first.longitude;
    double maxLng = coordinates.first.longitude;

    for (LatLng c in coordinates) {
      if (c.latitude < minLat) minLat = c.latitude;
      if (c.latitude > maxLat) maxLat = c.latitude;
      if (c.longitude < minLng) minLng = c.longitude;
      if (c.longitude > maxLng) maxLng = c.longitude;
    }

    LatLngBounds bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100.0));
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(10),
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.7),
              ),
              child: const Icon(Icons.arrow_back, color: Colors.black),
            ),
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage.isNotEmpty) {
      return Center(child: Text(_errorMessage));
    }

    if (_currentPosition == null) {
      return const Center(child: Text("Waiting for location..."));
    }

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _currentPosition!,
            zoom: 19, // High zoom for delivery navigation
            bearing: _currentBearing, // Initial bearing
            tilt: 45, // Initial tilt
          ),
          myLocationEnabled: true,
          myLocationButtonEnabled: true,
          zoomControlsEnabled: true, // Enable zoom controls for delivery man
          mapToolbarEnabled: false, // Disable toolbar for cleaner view
          compassEnabled: true, // Enable compass for navigation
          markers: _isNavigating
              ? _markers
              : {
            Marker(
              markerId: const MarkerId("current_user"),
              position: _currentPosition!,
              infoWindow: const InfoWindow(title: "You are here"),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
            )
          },
          polylines: _polylines,
          onMapCreated: (GoogleMapController controller) {
            _mapController = controller;
            _moveCameraToCurrentPosition();
          },
        ),

        // Compass-like navigation indicator (top right)
        if (_isNavigating)
          Positioned(
            top: 120,
            right: 16,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Transform.rotate(
                  angle: _currentBearing * (pi / 180),
                  child: const Icon(
                    Icons.navigation,
                    color: Colors.blue,
                    size: 32,
                  ),
                ),
              ),
            ),
          ),
        // Navigation control buttons (bottom right)
        if (_isNavigating)
          Positioned(
            bottom: 200,
            right: 16,
            child: Column(
              children: [
                FloatingActionButton(
                  onPressed: _stopNavigation,
                  backgroundColor: Colors.red,
                  child: const Icon(Icons.stop, color: Colors.white),
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  onPressed: () {
                    if (_currentPosition != null && _destination != null) {
                      _showRouteDirection(_currentPosition!, _destination!);
                    }
                  },
                  backgroundColor: Colors.blue,
                  child: const Icon(Icons.refresh, color: Colors.white),
                ),
              ],
            ),
          ),

        // Route calculation loading indicator
        if (_isCalculatingRoute)
          const Positioned(
            top: 200,
            left: 0,
            right: 0,
            child: Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(width: 16),
                      Text('Calculating route...'),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // Large navigation direction overlay (Waze-like)
        if (_isNavigating && _destination != null && !_isCalculatingRoute)
          Positioned(
            top: 100,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Direction text
                  Text(
                    _currentDirection,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  // Distance and bearing
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.navigation, color: Colors.blue, size: 24),
                          const SizedBox(width: 8),
                          Text(
                            _calculateDistance(_currentPosition!, _destination!),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                      // Bearing arrow
                      Transform.rotate(
                        angle: _currentBearing * (pi / 180),
                        child: const Icon(
                          Icons.arrow_upward,
                          color: Colors.blue,
                          size: 32,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

        // Delivery info card at bottom
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF1B6C07),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.deliveryCode ?? "# MSN 10011",
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.deliveryAddress ?? "22 & 24, Jln Sultan Ahmad Shah, George Town, Pulau Pinang",
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.timer, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      _getEstimatedDeliveryTime(),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Navigation status indicator
                if (_isNavigating) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.navigation, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          "Navigation Active",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.green),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Delivery status updated')),
                    );
                  },
                  child: const Text("Update"),
                )
              ],
            ),
          ),
        ),
      ],
    );
  }
}