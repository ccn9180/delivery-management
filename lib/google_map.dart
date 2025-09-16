import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:delivery/changepassword.dart';
import 'package:delivery/confirmation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show ByteData;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as permission_handler_plugin;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'config.dart';

// Simple container for Directions steps (used for showing road/instruction names)
class _NavStep {
  final List<LatLng> points;
  final String instruction;
  const _NavStep({required this.points, required this.instruction});
}

// High-contrast navigation map style to make roads/labels clearer (similar to Google Maps nav)
const String _navigationMapStyle = '''
[
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"visibility":"on"},{"saturation":20},{"lightness":10}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#1f2937"}]},
  {"featureType":"road","elementType":"labels.text.stroke","stylers":[{"color":"#ffffff"},{"weight":2}]},
  {"featureType":"water","stylers":[{"color":"#d6eefc"}]},
  {"featureType":"landscape","stylers":[{"color":"#eef5ea"}]}
]
''';

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
  String _googleApiKey = Config.googleMapsApiKey;
  // Driver view/follow state
  bool _isFollowMode = true; // camera follows heading like turn-by-turn
  bool _userInteracting = false;
  BitmapDescriptor? _navArrowIcon;
  
  // Enhanced navigation state management
  bool _hasReachedDestination = false;
  bool _isExternalNavigationActive = false;
  bool _showDeliveryInfoCard = true;
  double _arrivalThreshold = Config.arrivalThresholdMeters; // meters - consider arrived when within this distance
  _AppLifecycleObserver? _lifecycleObserver;

  // Navigation direction variables
  String _currentDirection = "Head towards destination";
  double _currentBearing = 0.0;
  List<LatLng> _routePoints = [];
  int _currentRouteIndex = 0;
  DateTime? _lastRerouteAt;
  // Navigation steps from Directions API (for road names/instructions)
  List<_NavStep> _navSteps = [];

  // Default delivery destination from configuration (used if widget doesn't pass one)
  static final LatLng _defaultDestination =
  LatLng(Config.deliveryLatitude, Config.deliveryLongitude);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeLocationAndMap();
    });
    
    // Listen for app lifecycle changes to detect return from external navigation
    _lifecycleObserver = _AppLifecycleObserver(
      onResume: () {
        if (_isExternalNavigationActive) {
          // User returned from external Google Maps, show option to continue
          _showReturnFromExternalNavigationDialog();
        }
      },
    );
    WidgetsBinding.instance.addObserver(_lifecycleObserver!);
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
        await Geolocator.openLocationSettings();
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
        await Geolocator.openAppSettings();
        _locationPermission = await Geolocator.checkPermission();
        if (_locationPermission == LocationPermission.deniedForever) {
          if (mounted) {
            setState(() {
              _errorMessage = 'Location permission is permanently denied. Please enable it from the app settings.';
              _isLoading = false;
            });
          }
          return;
        }
      }

      await _getCurrentLocation();
      // 🚀 Auto-start navigation after current location is found (toggleable via Config)
      if (mounted && _currentPosition != null && Config.autoStartNavigation) {
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
      // 1) Try last known quickly to place camera fast
      Position? lastKnown = await Geolocator.getLastKnownPosition();
      if (mounted && lastKnown != null) {
        setState(() {
          _currentPosition = LatLng(lastKnown.latitude, lastKnown.longitude);
        });
      }

      // 2) Request a fresh high-accuracy fix
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: Config.locationAccuracy,
        timeLimit: const Duration(seconds: 12),
      );

      if (!mounted) return;
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
        _isLoading = false;
        _errorMessage = '';
      });

      _moveCameraToCurrentPosition();
      _startLocationTracking();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error getting current location: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  void _moveCameraToCurrentPosition() {
    if (_mapController != null && _currentPosition != null) {
      // Set initial camera with delivery man's perspective
      // Driver-forward perspective (aim slightly ahead of the car)
      CameraPosition cameraPosition = CameraPosition(
        target: _pointAheadOf(_currentPosition!, 35),
        zoom: 19.5,
        bearing: _currentBearing,
        tilt: 60,
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
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: (_isNavigating ? Config.navigationUpdateDistance : Config.locationUpdateDistance).toInt(),
      ),
    ).listen(
          (Position position) {
        if (mounted) {
          setState(() {
            _currentPosition = LatLng(position.latitude, position.longitude);
          });
          if (_isNavigating && _destination != null) {
            _updateNavigation(position);
            // If we already have a route, keep it; otherwise draw now
            if (_polylines.isEmpty) {
              _showRouteDirection(_currentPosition!, _destination!);
            } else {
              _maybeReroute();
            }
          }
        }
      },
      onError: (error) {
        debugPrint('Location tracking error: $error');
        // Don't show error to user, just log it
      },
    );
  }

  // Open native Google Maps (or web) for full turn-by-turn with road names
  Future<void> _openExternalGoogleMaps() async {
    if (_destination == null) return;
    final LatLng dest = _destination!;
    final LatLng origin = _currentPosition ?? dest;
    
    // Create deep link URL for Google Maps navigation
    final Uri uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&origin=${origin.latitude},${origin.longitude}&destination=${dest.latitude},${dest.longitude}&travelmode=driving&dir_action=navigate');
    
    if (await canLaunchUrl(uri)) {
      setState(() {
        _isExternalNavigationActive = true;
        _showDeliveryInfoCard = false; // Hide delivery info when external navigation is active
      });
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // Check if off-route or time-based refresh required, then reroute
  void _maybeReroute() {
    if (_currentPosition == null || _destination == null || _routePoints.isEmpty) return;

    final DateTime now = DateTime.now();
    // time-based refresh
    if (_lastRerouteAt == null || now.difference(_lastRerouteAt!).inSeconds >= Config.periodicRerouteSeconds) {
      _lastRerouteAt = now;
      _showRouteDirection(_currentPosition!, _destination!);
      return;
    }

    // off-route detection: distance from nearest route point
    double minMeters = double.infinity;
    for (final p in _routePoints) {
      final double d = _distanceMeters(_currentPosition!, p);
      if (d < minMeters) minMeters = d;
      if (minMeters <= Config.offRouteThresholdMeters) break;
    }
    if (minMeters > Config.offRouteThresholdMeters) {
      _showRouteDirection(_currentPosition!, _destination!);
      _lastRerouteAt = now;
    }
  }

  void _updateNavigation(Position position) {
    if (mounted && _mapController != null && _currentPosition != null) {
      // Check if driver has reached destination
      _checkDestinationArrival();
      
      setState(() {
        _markers.removeWhere((marker) => marker.markerId.value == "origin");
        _markers.add(
          Marker(
            markerId: const MarkerId("origin"),
            position: _currentPosition!,
            infoWindow: const InfoWindow(title: "Current Location"),
            icon: _isNavigating
                ? (_navArrowIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure))
                : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
            flat: _isNavigating,
            rotation: _isNavigating ? _currentBearing : 0,
            anchor: _isNavigating ? const Offset(0.5, 0.5) : const Offset(0.5, 1.0),
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
      if (!_isFollowMode) return; // don't override when user explores
      // Adaptive camera based on approximate speed from last route segment
      final double zoom = _selectZoomForSpeed();
      final double tilt = _selectTiltForSpeed();
      CameraPosition cameraPosition = CameraPosition(
        target: _pointAheadOf(_currentPosition!, 35),
        zoom: zoom,
        bearing: _currentBearing,
        tilt: tilt,
      );

      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(cameraPosition),
      );
    } catch (e) {
      debugPrint('Camera perspective error: $e');
    }
  }

  double _selectZoomForSpeed() {
    // If we have at least 2 points, estimate speed from route spacing
    if (_routePoints.length >= 2 && _currentRouteIndex < _routePoints.length - 1) {
      final LatLng a = _routePoints[_currentRouteIndex];
      final LatLng b = _routePoints[_currentRouteIndex + 1];
      final double meters = _distanceMeters(a, b);
      if (meters > 40) return Config.zoomFast;      // likely faster road
      if (meters > 15) return Config.zoomMedium;    // city driving
      return Config.zoomSlow;                        // slow/turning
    }
    return Config.zoomMedium;
  }

  double _selectTiltForSpeed() {
    if (_routePoints.length >= 2 && _currentRouteIndex < _routePoints.length - 1) {
      final LatLng a = _routePoints[_currentRouteIndex];
      final LatLng b = _routePoints[_currentRouteIndex + 1];
      final double meters = _distanceMeters(a, b);
      if (meters > 40) return Config.tiltFast;
      if (meters > 15) return Config.tiltMedium;
      return Config.tiltSlow;
    }
    return Config.tiltMedium;
  }

  Future<void> _startNavigation() async {
    if (_currentPosition == null) return;

    // Use delivery location if available, otherwise use configured default
    LatLng destination = widget.deliveryLocation ?? _defaultDestination;

    await _prepareNavArrowIcon();

    setState(() {
      _isNavigating = true;
      _isCalculatingRoute = false; // Don't calculate, just show direction
      _destination = destination;
    });

    // Show route direction using Google Directions API
    _showRouteDirection(_currentPosition!, destination);
  }

  Future<void> _prepareNavArrowIcon() async {
    if (_navArrowIcon != null) return;
    try {
      const double size = 96;
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);

      final Paint fill = Paint()..color = const Color(0xFF1A73E8);
      final Paint stroke = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6;

      final Path path = Path();
      path.moveTo(size * 0.5, 6);
      path.lineTo(size * 0.82, size * 0.86);
      path.lineTo(size * 0.5, size * 0.7);
      path.lineTo(size * 0.18, size * 0.86);
      path.close();

      canvas.drawPath(path, fill);
      canvas.drawPath(path, stroke);

      final ui.Image img = await recorder.endRecording().toImage(size.toInt(), size.toInt());
      final ByteData? bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      if (bytes != null) {
        _navArrowIcon = BitmapDescriptor.fromBytes(bytes.buffer.asUint8List());
      }
    } catch (_) {}
  }

  void _stopNavigation() {
    setState(() {
      _isNavigating = false;
      _polylines.clear();
      _markers.clear();
      _destination = null;
      _hasReachedDestination = false;
      _isExternalNavigationActive = false;
      _showDeliveryInfoCard = true;
    });
  }

  // Check if driver has reached the destination
  void _checkDestinationArrival() {
    if (_currentPosition == null || _destination == null || _hasReachedDestination) return;
    
    double distanceToDestination = _distanceMeters(_currentPosition!, _destination!);
    
    if (distanceToDestination <= _arrivalThreshold) {
      setState(() {
        _hasReachedDestination = true;
        _isNavigating = false;
        _showDeliveryInfoCard = false; // Hide delivery info card when arrived
      });
      
      // Show arrival confirmation
      _showArrivalConfirmation();
    }
  }

  // Show arrival confirmation dialog
  void _showArrivalConfirmation() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.location_on, color: Colors.green),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Destination Reached!',
                  style: TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
          content: const Text(
            'You have arrived at the delivery destination. Please use the Update button below to proceed with the delivery.',
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Keep navigation active for re-routing
                setState(() {
                  _hasReachedDestination = false;
                  _isNavigating = true;
                  _showDeliveryInfoCard = true;
                });
              },
              child: const Text('Continue Navigation'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Just close the dialog, user can use Update button
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  // Return to internal navigation from external Google Maps
  void _returnToInternalNavigation() {
    setState(() {
      _isExternalNavigationActive = false;
      _showDeliveryInfoCard = true;
      _isNavigating = true;
    });
  }

  // Show dialog when user returns from external navigation
  void _showReturnFromExternalNavigationDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(
                  'assets/images/SWPS.png',
                  width: 22,
                  height: 22,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Navigation Status',
                  style: TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
          content: const Text(
            'You have returned from Google Maps. Would you like to continue with internal navigation?',
            textAlign: TextAlign.left,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Stop navigation and hide route
                setState(() {
                  _isExternalNavigationActive = false;
                  _isNavigating = false;
                  _polylines.clear();
                  _showDeliveryInfoCard = true;
                });
              },
              child: const Text('Stop Navigation'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Continue with external Google Maps navigation
                _openExternalGoogleMaps();
              },
              child: const Text('Continue Navigation'),
            ),
          ],
        );
      },
    );
  }

  // Show route direction with real road-based navigation
  void _showRouteDirection(LatLng origin, LatLng destination) async {
    debugPrint('Starting route calculation from ${origin.latitude},${origin.longitude} to ${destination.latitude},${destination.longitude}');
    setState(() {
      _isCalculatingRoute = true;
    });

    try {
      // Get real road-based route from Google Directions API
      List<LatLng> roadPoints = await _getRoadBasedRoute(origin, destination);
      debugPrint('Route points received: ${roadPoints.length}');

      if (roadPoints.isNotEmpty) {
        _routePoints = roadPoints;
        _currentRouteIndex = 0;

        // Create navigation-style polylines (underlay + main route + inner glow)
        final Polyline underlay = Polyline(
          polylineId: const PolylineId("route_underlay"),
          color: Colors.white,
          width: 14,
          points: roadPoints,
          zIndex: 0,
          geodesic: true,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        );

        final Polyline mainRoute = Polyline(
          polylineId: const PolylineId("main_route"),
          color: const Color(0xFF1A73E8),
          width: 10,
          points: roadPoints,
          zIndex: 1,
          geodesic: true,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        );

        final Polyline innerGlow = Polyline(
          polylineId: const PolylineId("route_inner"),
          color: const Color(0xFF7BB1FF),
          width: 4,
          points: roadPoints,
          zIndex: 2,
          geodesic: true,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        );

        // Create markers for origin and destination
        Set<Marker> directionMarkers = {
          Marker(
            markerId: const MarkerId("origin"),
            position: origin,
            infoWindow: const InfoWindow(title: "Current Location", snippet: "Starting Point"),
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
          _polylines = {underlay, mainRoute, innerGlow};
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

  // Get real road-based route from Google Directions API (use detailed legs/steps)
  Future<List<LatLng>> _getRoadBasedRoute(LatLng origin, LatLng destination) async {
    try {
      String url = 'https://maps.googleapis.com/maps/api/directions/json?'
          'origin=${origin.latitude},${origin.longitude}&'
          'destination=${destination.latitude},${destination.longitude}&'
          'mode=driving&'
          'key=$_googleApiKey';

      debugPrint('Making API call to: $url');
      final response = await http.get(Uri.parse(url));
      debugPrint('API response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
          debugPrint('API call successful, processing route data');
          // Prefer detailed steps to avoid straight-line artifacts and capture road names
          _navSteps = [];
          final List<LatLng> points = [];
          final routes = data['routes'] as List;
          final legs = routes[0]['legs'] as List;
          for (final leg in legs) {
            final steps = leg['steps'] as List;
            for (final step in steps) {
              final poly = step['polyline']?['points'];
              final rawInstr = step['html_instructions'] as String?;
              final instruction = rawInstr == null ? '' : _stripHtml(rawInstr);
              if (poly is String && poly.isNotEmpty) {
                final decoded = _decodePolyline(poly);
                if (decoded.isNotEmpty) {
                  _navSteps.add(_NavStep(points: decoded, instruction: instruction));
                }
                if (points.isNotEmpty && decoded.isNotEmpty && points.last == decoded.first) {
                  points.addAll(decoded.skip(1));
                } else {
                  points.addAll(decoded);
                }
              }
            }
          }
          if (points.isNotEmpty) return points;
          // fallback to overview if steps missing
          String encodedPolyline = data['routes'][0]['overview_polyline']['points'];
          return _decodePolyline(encodedPolyline);
        } else {
          debugPrint('Directions API error: ${data['status']} - ${data['error_message'] ?? 'Unknown error'}');
        }
      } else {
        debugPrint('HTTP error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error getting directions: $e');
    }

    // Try a no-billing fallback using OSRM demo server
    debugPrint('Trying OSRM fallback for road-based route');
    final List<LatLng> osrm = await _getOsrmRoutePoints(origin, destination);
    if (osrm.isNotEmpty) return osrm;

    debugPrint('Returning empty route points, will use fallback');
    return [];
  }

  // Fallback route if steps fetch fails: try overview polyline from Directions
  Future<void> _createFallbackRoute(LatLng origin, LatLng destination) async {
    // Try to fetch overview-based route (still follows roads)
    List<LatLng> overview = await _getRouteCoordinates(origin, destination);
    // If Google overview not available (e.g., billing disabled), try OSRM
    if (overview.isEmpty) {
      overview = await _getOsrmRoutePoints(origin, destination);
    }
    if (overview.isEmpty) {
      debugPrint('No road-based overview available; skipping straight-line fallback');
      if (mounted) {
        setState(() {
          _isCalculatingRoute = false;
        });
      }
      return;
    }

    _routePoints = overview;
    _currentRouteIndex = 0;

    final Polyline underlay = Polyline(
      polylineId: const PolylineId("route_underlay"),
      color: Colors.white,
      width: 14,
      points: overview,
      zIndex: 0,
      geodesic: true,
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
      jointType: JointType.round,
    );

    final Polyline mainRoute = Polyline(
      polylineId: const PolylineId("main_route"),
      color: const Color(0xFF1A73E8),
      width: 10,
      points: overview,
      zIndex: 1,
      geodesic: true,
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
      jointType: JointType.round,
    );

    final Polyline innerGlow = Polyline(
      polylineId: const PolylineId("route_inner"),
      color: const Color(0xFF7BB1FF),
      width: 4,
      points: overview,
      zIndex: 2,
      geodesic: true,
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
      jointType: JointType.round,
    );

    final Set<Marker> directionMarkers = {
      Marker(
        markerId: const MarkerId("origin"),
        position: origin,
        infoWindow: const InfoWindow(title: "Current Location", snippet: "Starting Point"),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
      Marker(
        markerId: const MarkerId("destination"),
        position: destination,
        infoWindow: const InfoWindow(title: "Delivery Destination", snippet: "End Point"),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    };

    if (mounted) {
      setState(() {
        _polylines = {underlay, mainRoute, innerGlow};
        _markers = directionMarkers;
        _isCalculatingRoute = false;
      });
    }

    _updateNavigationDirection();
    _fitCameraToPoints(overview);
  }

  // No-billing routing via OSRM public demo. Returns road-following points.
  Future<List<LatLng>> _getOsrmRoutePoints(LatLng origin, LatLng destination) async {
    try {
      final String url = 'https://router.project-osrm.org/route/v1/driving/'
          '${origin.longitude},${origin.latitude};'
          '${destination.longitude},${destination.latitude}'
          '?overview=full&geometries=polyline&alternatives=false&steps=false';
      debugPrint('OSRM request: $url');
      final response = await http.get(Uri.parse(url));
      debugPrint('OSRM response status: ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 'Ok' && (data['routes'] as List).isNotEmpty) {
          final String encoded = data['routes'][0]['geometry'];
          return _decodePolyline(encoded);
        } else {
          debugPrint('OSRM error: ${data['code']}');
        }
      }
    } catch (e) {
      debugPrint('Error fetching OSRM route: $e');
    }
    return [];
  }

  // Removed artificial straight-line fallback to ensure route always follows real roads

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
      // If heading deviates a lot from route, trigger reroute
      final double userToRouteBearing = _calculateBearing(_currentPosition!, nextPoint);
      final double diff = (_currentBearing - userToRouteBearing).abs();
      if (diff > Config.headingDeviationDegrees) {
        _maybeReroute();
      }
      // Update road/step name by finding the nearest step
      if (_navSteps.isNotEmpty) {
        String? stepName;
        double minStepDist = double.infinity;
        for (final s in _navSteps) {
          for (final p in s.points) {
            final d = _distanceMeters(_currentPosition!, p);
            if (d < minStepDist) {
              minStepDist = d;
              stepName = s.instruction;
            }
          }
        }
        if (stepName != null && stepName!.isNotEmpty) {
          _currentDirection = stepName!; // show real instruction with road name
        }
      }
    } else {
      _currentDirection = "You have arrived at your destination";
    }
  }

  // Remove simple HTML tags/entities from Directions instructions
  String _stripHtml(String html) {
    final String noTags = html.replaceAll(RegExp(r'<[^>]*>'), '');
    return noTags
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
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

  // Quick meters distance for off-route check
  double _distanceMeters(LatLng a, LatLng b) {
    const double earthRadius = 6371000.0; // meters
    final double dLat = (b.latitude - a.latitude) * (pi / 180);
    final double dLng = (b.longitude - a.longitude) * (pi / 180);
    final double lat1 = a.latitude * (pi / 180);
    final double lat2 = b.latitude * (pi / 180);
    final double sinDLat = sin(dLat / 2);
    final double sinDLng = sin(dLng / 2);
    final double aVal = sinDLat * sinDLat + sinDLng * sinDLng * cos(lat1) * cos(lat2);
    final double c = 2 * atan2(sqrt(aVal), sqrt(1 - aVal));
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

  // Compute a point slightly ahead of current location in heading direction (meters)
  LatLng _pointAheadOf(LatLng origin, double metersAhead) {
    // simple equirectangular approximation for short distances
    final double bearingRad = _currentBearing * (pi / 180);
    const double earthRadius = 6378137.0; // meters
    final double delta = metersAhead / earthRadius;
    final double lat1 = origin.latitude * (pi / 180);
    final double lng1 = origin.longitude * (pi / 180);

    final double lat2 = asin(sin(lat1) * cos(delta) + cos(lat1) * sin(delta) * cos(bearingRad));
    final double lng2 = lng1 + atan2(
      sin(bearingRad) * sin(delta) * cos(lat1),
      cos(delta) - sin(lat1) * sin(lat2),
    );

    return LatLng(lat2 * (180 / pi), ((lng2 * (180 / pi) + 540) % 360) - 180);
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
    if (_lifecycleObserver != null) {
      WidgetsBinding.instance.removeObserver(_lifecycleObserver!);
    }
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Text(
            _errorMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    if (_currentPosition == null) {
      return const Center(child: Text("Waiting for location..."));
    }

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _pointAheadOf(_currentPosition!, 35),
            zoom: 25,
            bearing: _currentBearing,
            tilt: 80,
          ),
          myLocationEnabled: true,
          myLocationButtonEnabled: true,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          compassEnabled: true,
          trafficEnabled: true,
          buildingsEnabled: true,
          indoorViewEnabled: true,
          tiltGesturesEnabled: true,
          rotateGesturesEnabled: true,
          padding: const EdgeInsets.only(
              top: 80, bottom: 170, left: 6, right: 6),
          onCameraMoveStarted: () {
            _userInteracting = true;
            if (_isFollowMode) {
              setState(() => _isFollowMode = false);
            }
          },
          onCameraIdle: () {
            _userInteracting = false;
          },
          markers: _isNavigating
              ? _markers
              : {
            Marker(
              markerId: const MarkerId("current_user"),
              position: _currentPosition!,
              infoWindow: const InfoWindow(title: "You are here"),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueAzure),
            )
          },
          polylines: _polylines,
          onMapCreated: (GoogleMapController controller) {
            _mapController = controller;
            // Apply high-contrast navigation style to emphasize roads/labels
            try {
              _mapController!.setMapStyle(_navigationMapStyle);
            } catch (_) {}
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
        // Re-center button to re-enter follow mode
        if (!_isFollowMode)
          Positioned(
            bottom: 200,
            left: 16,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                elevation: 3,
              ),
              onPressed: () {
                setState(() => _isFollowMode = true);
                _followDeliveryManPerspective();
              },
              icon: const Icon(Icons.my_location),
              label: const Text('Re-center'),
            ),
          ),
        // Navigation control buttons (bottom right)
        if (_isNavigating && !_hasReachedDestination)
          Positioned(
            bottom: 200,
            right: 16,
            child: Column(
              children: [
                FloatingActionButton(
                  tooltip: 'Open in Google Maps',
                  onPressed: _openExternalGoogleMaps,
                  backgroundColor: Colors.white,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset(
                      'assets/images/SWPS.png',
                      width: 28,
                      height: 28,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Return to internal navigation button (when external navigation is active)
        if (_isExternalNavigationActive)
          Positioned(
            bottom: 200,
            left: 16,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                elevation: 3,
              ),
              onPressed: _returnToInternalNavigation,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Return to App'),
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

        // Compact guidance banner
        if (_isNavigating && _destination != null && !_isCalculatingRoute)
          Positioned(
            top: 60,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Transform.rotate(
                    angle: _currentBearing * (pi / 180),
                    child: const Icon(
                        Icons.turn_slight_right, color: Colors.blue, size: 26),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _currentDirection,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _calculateDistance(_currentPosition!, _destination!),
                    style: const TextStyle(fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue),
                  ),
                ],
              ),
            ),
          ),

        // Draggable delivery info
        if (_showDeliveryInfoCard)
          DraggableScrollableSheet(
            initialChildSize: 0.18,
            // collapsed height
            minChildSize: 0.12,
            maxChildSize: 0.4,
            snap: true,
            snapSizes: const [0.18, 0.4],
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF1B6C07),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: SingleChildScrollView(
                  controller: scrollController,
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Grip
                      Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      Text(
                        '#${widget.deliveryCode ?? "Default code"}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.location_on, color: Colors.white),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              widget.deliveryAddress ?? "Address Invalid",
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13),
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
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_isNavigating && !_hasReachedDestination) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12,
                              vertical: 10),
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
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (_hasReachedDestination) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12,
                              vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.location_on, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                "Destination Reached!",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (_isExternalNavigationActive) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12,
                              vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.map, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                "External Navigation Active",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(36),
                            foregroundColor: Colors.green),
                        onPressed: () {
                          // Replace Google Map with Confirmation page so back goes to delivery list
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const ConfirmationPage()),
                          );
                        },
                        child: const Text("Update", style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                      )
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

// App lifecycle observer to detect when user returns from external navigation
class _AppLifecycleObserver extends WidgetsBindingObserver {
  final VoidCallback onResume;

  _AppLifecycleObserver({required this.onResume});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResume();
    }
  }
}