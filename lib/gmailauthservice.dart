import 'dart:convert';
import 'package:flutter_appauth/flutter_appauth.dart';

class GmailAuthService {
  static const String clientId =
      '720193850695-s30ea16een9e1stdiiuf73n54f6ln1nr.apps.googleusercontent.com';

  static const String redirectUrl =
      'com.googleusercontent.apps.720193850695-s30ea16een9e1stdiiuf73n54f6ln1nr:/oauth2redirect';

  static const String issuer = 'https://accounts.google.com';

  final FlutterAppAuth _appAuth = FlutterAppAuth();

  // Launches Google OAuth and returns the authenticated email if successful.
  // Returns null if authentication fails or email cannot be determined.
  Future<String?> authenticateAndGetEmail() async {
    try {
      final AuthorizationTokenResponse? result =
      await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          clientId,
          redirectUrl,
          issuer: issuer,
          scopes: ['openid', 'email', 'profile'],
          promptValues: ['select_account'],
        ),
      );

      if (result == null || result.idToken == null) {
        return null;
      }

      // Decode ID token (JWT) to extract the email claim
      final parts = result.idToken!.split('.');
      if (parts.length != 3) return null;
      final payload = _base64UrlDecode(parts[1]);
      final Map<String, dynamic> claims = json.decode(payload) as Map<String, dynamic>;
      final String? email = claims['email'] as String?;
      return email;
    } catch (e) {
      print('Gmail authentication error: $e');
      return null;
    }
  }

  String _base64UrlDecode(String input) {
    String normalized = input.replaceAll('-', '+').replaceAll('_', '/');
    switch (normalized.length % 4) {
      case 2:
        normalized += '==';
        break;
      case 3:
        normalized += '=';
        break;
    }
    return utf8.decode(base64.decode(normalized));
  }
}
