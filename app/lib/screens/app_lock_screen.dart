import 'package:flutter/material.dart';

import '../api.dart';
import '../app_state.dart';
import '../theme.dart';

/// The app lock from appfeature.md 1.2 — a PIN on top of the session, so a shared
/// or unlocked phone does not expose someone's medical history.
class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  String _pin = '';
  bool _busy = false;
  String? _error;

  Future<void> _verify() async {
    if (_pin.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (await Api.instance.verifyAppLock(_pin)) {
        AppState.instance.unlock();
      } else {
        setState(() {
          _error = 'That PIN did not match.';
          _pin = '';
        });
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _press(String key) {
    if (_busy) return;
    if (key == '⌫') {
      if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
      return;
    }
    if (key.isEmpty || _pin.length >= 12) return;
    setState(() {
      _error = null;
      _pin += key;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    final textTheme = Theme.of(context).textTheme;
    final dotCount = _pin.length.clamp(4, 12);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 66,
                    height: 66,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: c.surface2, shape: BoxShape.circle),
                    child: Icon(Icons.lock_outline, color: c.ink2, size: 26),
                  ),
                  const SizedBox(height: SanjeevaniSpace.md),
                  Text('Welcome back', style: textTheme.headlineMedium),
                  const SizedBox(height: SanjeevaniSpace.sm),
                  Text('Enter your app PIN',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyLarge?.copyWith(color: c.ink2)),
                  const SizedBox(height: SanjeevaniSpace.xl),
                  Wrap(
                    spacing: SanjeevaniSpace.md,
                    children: List.generate(dotCount, (i) {
                      final filled = i < _pin.length;
                      return Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: filled ? c.acc : Colors.transparent,
                          border: Border.all(color: filled ? c.acc : c.ink3, width: 2),
                        ),
                      );
                    }),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: SanjeevaniSpace.md),
                      child: Text(_error!, style: TextStyle(color: c.dan)),
                    ),
                  const SizedBox(height: SanjeevaniSpace.xl),
                  GridView.count(
                    shrinkWrap: true,
                    crossAxisCount: 3,
                    mainAxisSpacing: SanjeevaniSpace.md,
                    crossAxisSpacing: SanjeevaniSpace.md,
                    childAspectRatio: 1.3,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      for (final key in const [
                        '1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '⌫'
                      ])
                        key.isEmpty
                            ? const SizedBox.shrink()
                            : OutlinedButton(
                                onPressed: () => _press(key),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(68),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(SanjeevaniRadius.lg),
                                  ),
                                ),
                                child: Text(
                                  key,
                                  style: textTheme.headlineSmall?.copyWith(
                                    fontSize: 26,
                                    color: key == '⌫' ? c.ink2 : c.ink,
                                  ),
                                ),
                              ),
                    ],
                  ),
                  const SizedBox(height: SanjeevaniSpace.lg),
                  FilledButton(
                    onPressed: _busy ? null : _verify,
                    child: Text(_busy ? 'Checking…' : 'Unlock'),
                  ),
                  TextButton(
                    onPressed: AppState.instance.signOut,
                    child: const Text('Sign out instead'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
