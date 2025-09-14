# Real-Time Navigation Setup Guide

## Overview
Your Google Map now includes real-time navigation functionality that allows you to:
- Start navigation to the delivery destination
- See the route displayed on the map
- Track your location in real-time during navigation
- Update the route as you move

## Setup Instructions

### 1. Google Maps API Key Setup
1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one
3. Enable the following APIs:
   - Maps SDK for Android
   - Maps SDK for iOS
   - Directions API
   - Places API (optional)
4. Create credentials (API Key)
5. Restrict the API key to your app (recommended for security)

### 2. Update Configuration
1. Open `lib/config.dart`
2. Replace `"AIzaSyBwfTQ-3Qpia1X0zkpy8Dw6R6MV8HI016U"` with your actual API key:
   ```dart
   static const String googleMapsApiKey = "AIzaSyBwfTQ-3Qpia1X0zkpy8Dw6R6MV8HI016U";
   ```

### 3. Android Setup
1. Open `android/app/src/main/AndroidManifest.xml`
2. Add your API key in the `<application>` tag:
   ```xml
   <meta-data
       android:name="com.google.android.geo.API_KEY"
       android:value="AIzaSyBwfTQ-3Qpia1X0zkpy8Dw6R6MV8HI016U"/>
   ```

### 4. iOS Setup
1. Open `ios/Runner/AppDelegate.swift`
2. Add your API key in the `application` method:
   ```swift
   GMSServices.provideAPIKey("AIzaSyBwfTQ-3Qpia1X0zkpy8Dw6R6MV8HI016U")
   ```

## Features

### Navigation Controls
- **Start Navigation**: Green button to begin navigation to delivery destination
- **Stop Navigation**: Red button to stop navigation and clear route
- **Refresh Route**: Blue button to recalculate route from current position

### Real-Time Updates
- Location tracking updates every 5 meters
- Camera follows your position during navigation
- Route markers update as you move
- Smooth camera animations

### Map Features
- Blue polyline shows the route
- Green marker: Your current location
- Red marker: Delivery destination
- Real-time location updates
- Automatic camera fitting to show entire route

## Usage

1. **Open the Map**: Navigate to the Google Map page
2. **Grant Permissions**: Allow location access when prompted
3. **Start Navigation**: Tap the green "Start Navigation" button
4. **Follow Route**: The map will show your route and track your movement
5. **Stop Navigation**: Tap the red "Stop Navigation" button when done

## Troubleshooting

### Common Issues
1. **No route displayed**: Check your Google Maps API key and ensure Directions API is enabled
2. **Location not updating**: Check location permissions in device settings
3. **Map not loading**: Verify your API key is correctly set in Android/iOS configuration

### Debug Information
- Check console logs for location updates and route calculation
- Verify API key is working by testing in a browser with the Directions API URL

## Customization

### Change Destination
Update the coordinates in `lib/config.dart`:
```dart
static const double deliveryLatitude = 5.4164;
static const double deliveryLongitude = 100.3327;
```

### Adjust Location Updates
Modify the update frequency in `lib/config.dart`:
```dart
static const double locationUpdateDistance = 5.0; // meters
```

### Styling
- Modify colors in the `_calculateRoute` method
- Update button styles in the bottom container
- Customize marker icons and info windows
