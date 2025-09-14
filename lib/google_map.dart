import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';

class GoogleMapPage extends StatefulWidget {
  const GoogleMapPage({super.key});

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
  LocationPermission? _locationPermission;

  @override
  void initState() {
    super.initState();
    _initializeLocation();
  }

  Future<void> _initializeLocation() async {
    _locationServiceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!_locationServiceEnabled) {
      setState(() {
        _errorMessage = 'Location services are disabled. Please enable them.';
        _isLoading = false;
      });
      return;
    }

    _locationPermission = await Geolocator.checkPermission();
    if (_locationPermission == LocationPermission.denied) {
      _locationPermission = await Geolocator.requestPermission();
      if (_locationPermission == LocationPermission.denied) {
        setState(() {
          _errorMessage = 'Location permissions are denied';
          _isLoading = false;
        });
        return;
      }
    }

    if (_locationPermission == LocationPermission.deniedForever) {
      setState(() {
        _errorMessage =
        'Location permissions are permanently denied. Please enable them in app settings.';
        _isLoading = false;
      });
      return;
    }

    _getCurrentLocation();
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

      // ✅ Move camera once we get location
      if (_mapController != null && _currentPosition != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(_currentPosition!, 16),
        );
      }

      _startLocationTracking();
    } catch (e) {
      setState(() {
        _errorMessage = 'Error getting location: $e';
        _isLoading = false;
      });
    }
  }

  void _startLocationTracking() {
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          _currentPosition = LatLng(position.latitude, position.longitude);
        });

        if (_mapController != null) {
          _mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(_currentPosition!, 16),
          );
        }
      }
    }, onError: (error) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Location tracking error: $error';
        });
      }
    });
  }

  Future<void> _openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  Future<void> _openAppSettings() async {
    await openAppSettings();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: Padding(
          padding: const EdgeInsets.all(10),
          child: GestureDetector(
            onTap: ()=>Navigator.pop(context),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.7),
              ),
              child: Icon(Icons.arrow_back, color: Colors.black),
            ),
          )
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
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_off, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 20),
              if (!_locationServiceEnabled)
                ElevatedButton(
                  onPressed: _openLocationSettings,
                  child: const Text('Enable Location Services'),
                ),
              if (_locationPermission == LocationPermission.deniedForever)
                ElevatedButton(
                  onPressed: _openAppSettings,
                  child: const Text('Open App Settings'),
                ),
              if (_locationPermission == LocationPermission.denied ||
                  _errorMessage.contains('Error getting location'))
                ElevatedButton(
                  onPressed: _initializeLocation,
                  child: const Text('Try Again'),
                ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _currentPosition ?? const LatLng(5.4164, 100.3327),
            zoom: 16,
          ),
          myLocationEnabled: true,
          myLocationButtonEnabled: true,
          zoomControlsEnabled: true,
          markers: _currentPosition != null
              ? {
            Marker(
              markerId: const MarkerId("current"),
              position: _currentPosition!,
              infoWindow: const InfoWindow(title: "You are here"),
            )
          }
              : {},
          onMapCreated: (GoogleMapController controller) {
            _mapController = controller;

            // ✅ If position already available, move camera immediately
            if (_currentPosition != null) {
              _mapController!.animateCamera(
                CameraUpdate.newLatLngZoom(_currentPosition!, 16),
              );
            }
          },
        ),
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
                const Text(
                  "# MSN 10011",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: const [
                    Icon(Icons.location_on, color: Colors.white),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "22 & 24, Jln Sultan Ahmad Shah, George Town, Pulau Pinang",
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: const [
                    Icon(Icons.timer, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      "Estimated Time: 20-30 minutes",
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.green),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Delivery status updated')),
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
