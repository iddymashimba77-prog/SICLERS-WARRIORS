import 'package:flutter/material.dart';

import '../../data/auth_repository.dart';
import '../../data/token_store.dart';

/// Forgot password page for password reset request (AUTH + PUBLIC HOME).
///
/// Allows users to request a password reset using their login identity (email
/// or phone). The backend responds uniformly (no account enumeration) and
/// sends the reset token only when the identifier matches a registered account.
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  static const String routeName = '/forgot-password';

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _identifierController = TextEditingController();
  bool _submitting = false;
  bool _requestSent = false;

  @override
  void dispose() {
    _identifierController.dispose();
    super.dispose();
  }

  String? _validateIdentifier(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email or phone number is required';
    }
    if (!value.contains('@')) {
      final digits = value.replaceAll(RegExp(r'[^\d]'), '');
      if (digits.length < 9 || digits.length > 15) {
        return 'Enter a valid phone number or email address';
      }
    }
    return null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);

    try {
      final repo = AuthRepository(tokenStore: EphemeralTokenStore());
      await repo.requestPasswordReset(
        identifier: _identifierController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _requestSent = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _showError('Unable to send reset request. Please try again.');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reset Password'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                Icon(
                  Icons.lock_reset_outlined,
                  size: 72,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  _requestSent ? 'Check Your Inbox' : 'Forgot Password?',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  _requestSent
                      ? 'If that identifier matches an account, reset instructions have been sent.'
                      : 'Enter your email or phone number and we\'ll send you instructions to reset your password.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                if (!_requestSent) ...[
                  TextFormField(
                    controller: _identifierController,
                    decoration: const InputDecoration(
                      labelText: 'Email or phone',
                      prefixIcon: Icon(Icons.alternate_email_outlined),
                      helperText:
                          'Use the email or phone you registered with',
                    ),
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    validator: _validateIdentifier,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Send Reset Link'),
                  ),
                ] else ...[
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => Navigator.pushReplacementNamed(
                      context,
                      '/login',
                    ),
                    child: const Text('Return to Login'),
                  ),
                ],
                const SizedBox(height: 16),
                if (!_requestSent)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Back to Login'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
