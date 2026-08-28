import 'package:flutter/material.dart';

import '../api.dart';
import '../app_state.dart';
import '../theme.dart';

/// Sign in / register, plus the Aadhaar screen appfeature.md asks for.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _registering = false;
  bool _busy = false;
  String? _error;

  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    _run(() => _registering
        ? AppState.instance.register(_email.text, _password.text, _name.text)
        : AppState.instance.signIn(_email.text, _password.text));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    final c = context.sc;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.acc,
                        borderRadius: BorderRadius.circular(SanjeevaniRadius.sm),
                      ),
                      child: Text('S',
                          style: TextStyle(
                              color: c.accInk,
                              fontFamily: textTheme.displaySmall!.fontFamily,
                              fontSize: 24)),
                    ),
                    const SizedBox(height: SanjeevaniSpace.md),
                    Text(_registering ? 'Create your account' : 'Tell us what is wrong',
                        style: textTheme.displaySmall),
                    const SizedBox(height: SanjeevaniSpace.sm),
                    Text(
                      'In your own words, in your own language. We find the right doctor for you.',
                      style: textTheme.bodyLarge?.copyWith(color: c.ink2),
                    ),
                    const SizedBox(height: SanjeevaniSpace.xxl),

                    if (_registering) ...[
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(labelText: 'Full name'),
                        textCapitalization: TextCapitalization.words,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
                      ),
                      const SizedBox(height: SanjeevaniSpace.md),
                    ],

                    TextFormField(
                      controller: _email,
                      decoration: const InputDecoration(labelText: 'Email'),
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      validator: (v) =>
                          (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                    ),
                    const SizedBox(height: SanjeevaniSpace.md),
                    TextFormField(
                      controller: _password,
                      decoration: const InputDecoration(labelText: 'Password'),
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      validator: (v) => (v == null || v.length < 8)
                          ? 'At least 8 characters'
                          : null,
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: SanjeevaniSpace.md),
                      Text(_error!, style: TextStyle(color: c.dan)),
                    ],

                    const SizedBox(height: SanjeevaniSpace.xl),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Text(_busy
                          ? 'Please wait…'
                          : (_registering ? 'Create account' : 'Sign in')),
                    ),
                    const SizedBox(height: SanjeevaniSpace.sm),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _registering = !_registering;
                                _error = null;
                              }),
                      child: Text(_registering
                          ? 'I already have an account'
                          : 'New here? Create an account'),
                    ),

                    if (state.firebaseEnabled) ...[
                      const SizedBox(height: SanjeevaniSpace.sm),
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _run(AppState.instance.signInWithFirebase),
                        icon: const Icon(Icons.account_circle_outlined),
                        label: const Text('Continue with Google'),
                      ),
                    ],

                    // Only offered when Firebase is not handling sign-in. Both
                    // buttons at once would be two doors to the same account with
                    // different identifiers behind them.
                    if (!state.firebaseEnabled && state.googleEnabled) ...[
                      const SizedBox(height: SanjeevaniSpace.sm),
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _run(AppState.instance.signInWithGoogle),
                        icon: const Icon(Icons.account_circle_outlined),
                        label: const Text('Continue with Google'),
                      ),
                    ],

                    const SizedBox(height: SanjeevaniSpace.xl),
                    Text(
                      'Sanjeevani helps you reach the right doctor. It does not diagnose you. '
                      'Aadhaar linking is optional and can be done later from your profile.',
                      style: textTheme.bodySmall?.copyWith(color: c.ink3),
                      textAlign: TextAlign.center,
                    ),
                    if (!state.googleEnabled && !state.firebaseEnabled)
                      Padding(
                        padding: const EdgeInsets.only(top: SanjeevaniSpace.sm),
                        child: Text(
                          'Single sign-on is switched off on this server. Set '
                          'FIREBASE_PROJECT_ID here and the FIREBASE_* build '
                          'values in the app, or GOOGLE_CLIENT_IDS, to turn it on.',
                          style: textTheme.bodySmall?.copyWith(color: c.ink3),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: SanjeevaniSpace.sm),
                      child: Text(
                        'API: ${Api.baseUrl}',
                        style: textTheme.bodySmall?.copyWith(color: c.ink3),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
