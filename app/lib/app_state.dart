import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'api.dart';

/// Single source of truth for "who is signed in and what screen should show".
/// A plain ChangeNotifier — no state-management dependency, the app is small.
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState instance = AppState._();

  /// Web client id from Google Cloud Console, used as the backend audience:
  ///   flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=...
  static const String googleServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  Map<String, dynamic>? user;
  Map<String, dynamic>? patient;
  bool googleEnabled = false;
  bool booting = true;
  bool unlocked = false;
  String? error;

  bool get signedIn => user != null;
  bool get isPatient => user?['role'] == 'patient';
  bool get profileComplete => patient?['profile_complete'] == true;
  bool get appLockSet => patient?['app_lock_set'] == true;
  bool get needsUnlock => appLockSet && !unlocked;
  String get language => (patient?['language'] as String?) ?? 'en';

  Future<void> boot() async {
    await Api.instance.loadToken();
    googleEnabled = await Api.instance.googleEnabled();
    if (Api.instance.token != null) {
      try {
        await refresh();
      } catch (_) {
        await Api.instance.setToken(null);
      }
    }
    if (googleEnabled && googleServerClientId.isNotEmpty) {
      try {
        await GoogleSignIn.instance.initialize(serverClientId: googleServerClientId);
      } catch (e) {
        // Missing platform config should not stop the email/password path.
        debugPrint('google sign-in unavailable: $e');
        googleEnabled = false;
      }
    } else {
      googleEnabled = false;
    }
    booting = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    final me = await Api.instance.me();
    user = me['user'] as Map<String, dynamic>?;
    patient = me['patient'] as Map<String, dynamic>?;
    notifyListeners();
  }

  Future<void> _adopt(Map<String, dynamic> authResponse) async {
    await Api.instance.setToken(authResponse['token'] as String);
    unlocked = true; // just authenticated, no need to also punch in the PIN
    await refresh();
  }

  Future<void> signIn(String email, String password) async {
    final out = await Api.instance.login(email.trim(), password);
    if ((out['user'] as Map)['role'] != 'patient') {
      throw ApiException(403, 'This app is for patients. Staff use the web console.');
    }
    await _adopt(out);
  }

  Future<void> register(String email, String password, String fullName) async =>
      _adopt(await Api.instance.register(email.trim(), password, fullName.trim()));

  /// Google flow: the plugin gets an ID token, the backend verifies it and mints
  /// our own JWT. Nothing Google-issued is trusted past that point.
  Future<void> signInWithGoogle() async {
    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw ApiException(400, 'Google sign-in is not available on this platform build.');
    }
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw ApiException(400, 'Google did not return an ID token.');
    }
    await _adopt(await Api.instance.loginWithGoogle(idToken));
  }

  Future<void> signOut() async {
    try {
      if (googleEnabled) await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Signing out of Google is best-effort; our own session still ends.
    }
    await Api.instance.setToken(null);
    user = null;
    patient = null;
    unlocked = false;
    notifyListeners();
  }

  void unlock() {
    unlocked = true;
    notifyListeners();
  }

  Future<void> setLanguage(String code) async {
    patient = await Api.instance.saveProfile({'language': code});
    notifyListeners();
  }
}
