import 'package:geolocator/geolocator.dart';

class Config {
  static const String googleMapsApiKey = "AIzaSyBwfTQ-3Qpia1X0zkpy8Dw6R6MV8HI016U";

  // Delivery destination
  static const double deliveryLatitude = 5.4164;
  static const double deliveryLongitude = 100.3327;

  // Location tracking settings
  static const double locationUpdateDistance = 5.0; // meters
  static const LocationAccuracy locationAccuracy = LocationAccuracy.high;
  static const double navigationUpdateDistance = 2.0; // meters during active nav

  // Behavior toggles
  static const bool autoStartNavigation = true; // start navigation when map loads

  // Auto re-route settings
  static const double offRouteThresholdMeters = 20.0; // reroute when >20m off the road polyline
  static const int periodicRerouteSeconds = 8; // refresh route every few seconds
  static const double headingDeviationDegrees = 60.0; // reroute if heading deviates a lot

  // Driver camera behavior
  static const double zoomSlow = 19.5;    // walking / traffic start
  static const double zoomMedium = 18.0;  // city driving
  static const double zoomFast = 16.5;    // highway
  static const double tiltSlow = 60.0;
  static const double tiltMedium = 52.0;
  static const double tiltFast = 45.0;

  // Navigation completion settings
  static const double arrivalThresholdMeters = 50.0; // Consider arrived when within this distance
}

