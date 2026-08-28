import 'package:firebase_core/firebase_core.dart';

/// Firebase client configuration, supplied at build time rather than by a
/// generated `firebase_options.dart`:
///
///   flutter run --dart-define=FIREBASE_API_KEY=... --dart-define=FIREBASE_APP_ID=...
///
/// These values identify the project to Firebase; they are not secrets and ship
/// inside every client build regardless. Keeping them out of the tree means one
/// checkout can point at a staging or production project without an edit, and
/// nobody has to run the FlutterFire CLI to build.
///
/// Access is still controlled where it actually matters: the backend verifies
/// every ID token against FIREBASE_PROJECT_ID, and roles come from our own users
/// table, never from the token.
class FirebaseConfig {
  const FirebaseConfig._();

  static const String apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const String appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const String projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const String messagingSenderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const String authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');

  /// Everything Firebase needs before `initializeApp` will succeed. A partial
  /// config is worse than none: it throws at startup rather than at sign-in.
  static bool get configured =>
      apiKey.isNotEmpty && appId.isNotEmpty && projectId.isNotEmpty && messagingSenderId.isNotEmpty;

  static FirebaseOptions get options => FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        projectId: projectId,
        messagingSenderId: messagingSenderId,
        // Defaulted rather than required: it is only `<project>.firebaseapp.com`,
        // and getting it wrong breaks the web popup in a way that is hard to read.
        authDomain: authDomain.isNotEmpty ? authDomain : '$projectId.firebaseapp.com',
      );
}
