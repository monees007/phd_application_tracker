import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _registering = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
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
      // On success the auth stream swaps this screen out; no navigation here.
    } catch (e) {
      if (mounted) setState(() => _error = AuthService.describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final t = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.school_outlined,
                        size: 52, color: t.colorScheme.primary),
                    const SizedBox(height: 14),
                    Text('PhD Application Tracker',
                        textAlign: TextAlign.center,
                        style: t.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                      'Deadlines, statuses and reminders in one place.',
                      textAlign: TextAlign.center,
                      style: t.textTheme.bodyMedium
                          ?.copyWith(color: t.colorScheme.outline),
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                      validator: (v) => (v == null || !v.contains('@'))
                          ? 'Enter a valid email'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      validator: (v) => (v == null || v.length < 6)
                          ? 'At least 6 characters'
                          : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: TextStyle(color: t.colorScheme.error)),
                    ],
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () {
                              if (!_formKey.currentState!.validate()) return;
                              _run(() => _registering
                                  ? auth.register(_email.text, _password.text)
                                  : auth.signIn(_email.text, _password.text));
                            },
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : Text(_registering ? 'Create account' : 'Sign in'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () =>
                              setState(() => _registering = !_registering),
                      child: Text(_registering
                          ? 'I already have an account'
                          : 'Create a new account'),
                    ),
                    if (!_registering)
                      TextButton(
                        onPressed: _busy || !_email.text.contains('@')
                            ? null
                            : () => _run(() async {
                                  await auth.sendPasswordReset(_email.text);
                                  if (mounted) {
                                    setState(() =>
                                        _error = 'Reset email sent.');
                                  }
                                }),
                        child: const Text('Forgot password'),
                      ),
                    const SizedBox(height: 12),
                    const Row(children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('or'),
                      ),
                      Expanded(child: Divider()),
                    ]),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed:
                          _busy ? null : () => _run(auth.signInAnonymously),
                      icon: const Icon(Icons.person_outline),
                      label: const Text('Continue as guest'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Guest data is tied to this install. You can attach an '
                      'email later from Settings without losing anything.',
                      textAlign: TextAlign.center,
                      style: t.textTheme.bodySmall
                          ?.copyWith(color: t.colorScheme.outline),
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
