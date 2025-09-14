import 'package:flutter_appauth/flutter_appauth.dart';

class GmailAuthService {
  // Use your actual client ID
  static const String clientId = '928078978776-9mlo8kboqb6a24telufjb74pb694h8sm.apps.googleusercontent.com';
  static const String redirectUrl = 'my.edu.tarumt.delivery:/oauth2redirect';
  static const String issuer = 'https://accounts.google.com';

  final FlutterAppAuth _appAuth = FlutterAppAuth();

  Future<bool> authenticateWithGmail() async {
    try {
      // This will open the native Google authentication UI
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

      // Return true if authentication was successful
      return result != null && result.accessToken != null;
    } catch (e) {
      print('Gmail authentication error: $e');
      return false;
    }
  }
}