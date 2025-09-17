import 'package:flutter_appauth/flutter_appauth.dart';

class GmailAuthService {
  static const String clientId =
      '720193850695-s30ea16een9e1stdiiuf73n54f6ln1nr.apps.googleusercontent.com';

  static const String redirectUrl =
      'com.googleusercontent.apps.720193850695-s30ea16een9e1stdiiuf73n54f6ln1nr:/oauth2redirect';

  static const String issuer = 'https://accounts.google.com';

  final FlutterAppAuth _appAuth = FlutterAppAuth();

  Future<bool> authenticateWithGmail() async {
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

      return result != null && result.accessToken != null;
    } catch (e) {
      print('Gmail authentication error: $e');
      return false;
    }
  }
}
