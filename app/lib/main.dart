import 'package:flutter/material.dart';

import 'app_state.dart';
import 'screens/app_lock_screen.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'screens/profile_setup_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppState.instance.boot();
  runApp(const SanjeevaniApp());
}

class SanjeevaniApp extends StatelessWidget {
  const SanjeevaniApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sanjeevani',
      debugShowCheckedModeBanner: false,
      theme: sanjeevaniLightTheme,
      darkTheme: sanjeevaniDarkTheme,
      themeMode: ThemeMode.system,
      home: const _Gate(),
    );
  }
}

/// Decides the first screen: sign in, unlock, finish the profile, or the app.
class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final state = AppState.instance;
        if (state.booting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (!state.signedIn) return const LoginScreen();
        if (state.needsUnlock) return const AppLockScreen();
        if (!state.profileComplete) return const ProfileSetupScreen();
        return const HomeShell();
      },
    );
  }
}
