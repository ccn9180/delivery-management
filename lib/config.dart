import 'package:geolocator/geolocator.dart';

class Config {
  static const String googleMapsApiKey = "AIzaSyBwfTQ-3Qpia1X0zkpy8Dw6R6MV8HI016U";

  // Delivery destination
  static const double deliveryLatitude = 5.4164;
  static const double deliveryLongitude = 100.3327;

  // Location tracking settings
  static const double locationUpdateDistance = 5.0; // meters
  static const LocationAccuracy locationAccuracy = LocationAccuracy.high;
}
