import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/storage_keys.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isSendingReset = false;
  bool _obscure = true;
  bool _autoLoginAttempted = false;

  bool _isSixDigitPin(String value) => RegExp(r'^\d{6}$').hasMatch(value);

  @override
  void initState() {
    super.initState();
    _restoreLoginState();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _restoreLoginState() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }
    final savedEmail = prefs.getString(StorageKeys.loginLastEmail) ?? '';
    final savedPin = prefs.getString(StorageKeys.loginSavedPin) ?? '';
    final manualLogout =
        prefs.getBool(StorageKeys.manualLogoutRequested) ?? false;
    _emailController.text = savedEmail;
    if (_autoLoginAttempted ||
        manualLogout ||
        savedEmail.isEmpty ||
        savedPin.isEmpty) {
      return;
    }
    _autoLoginAttempted = true;
    await _submit(
      emailOverride: savedEmail,
      passwordOverride: savedPin,
      isAutoLogin: true,
    );
  }

  Future<void> _saveLoginCredentials({
    required String email,
    required String pin,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageKeys.loginLastEmail, email);
    await prefs.setString(StorageKeys.loginSavedPin, pin);
    await prefs.remove(StorageKeys.manualLogoutRequested);
  }

  Future<void> _saveLastEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageKeys.loginLastEmail, email);
  }

  Future<void> _clearSavedPin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(StorageKeys.loginSavedPin);
  }

  Future<void> _submit({
    String? emailOverride,
    String? passwordOverride,
    bool isAutoLogin = false,
  }) async {
    final email = (emailOverride ?? _emailController.text).trim();
    final password = passwordOverride ?? _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      if (!isAutoLogin) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email and password are required')),
        );
      }
      return;
    }
    if (!_isSixDigitPin(password)) {
      if (!isAutoLogin) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Enter a 6-digit PIN')));
      }
      return;
    }
    await _saveLastEmail(email);
    setState(() {
      _isLoading = true;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _saveLoginCredentials(email: email, pin: password);
    } on FirebaseAuthException catch (e) {
      if (isAutoLogin &&
          (e.code == 'user-not-found' ||
              e.code == 'wrong-password' ||
              e.code == 'invalid-credential')) {
        await _clearSavedPin();
      }
      if (!mounted) {
        return;
      }
      final fallbackMessage = switch (e.code) {
        'user-not-found' => 'Account not found. Contact admin.',
        'wrong-password' => 'Invalid credentials',
        _ => 'Authentication failed',
      };
      if (!isAutoLogin) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message ?? fallbackMessage)));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email to reset password')),
      );
      return;
    }
    setState(() {
      _isSendingReset = true;
    });
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset email sent')),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Unable to send reset email')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSendingReset = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = _isLoading || _isSendingReset;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'QRTags Login',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscure,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'PIN',
                      border: const OutlineInputBorder(),
                      counterText: '',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscure = !_obscure;
                          });
                        },
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: isBusy ? null : _sendPasswordReset,
                        child: Text(
                          _isSendingReset ? 'Sending...' : 'Forgot password?',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: isBusy ? null : () => _submit(),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Sign In'),
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
