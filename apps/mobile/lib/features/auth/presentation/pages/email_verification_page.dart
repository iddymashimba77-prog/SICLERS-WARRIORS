import 'package:flutter/material.dart';

import '../controllers/auth_controller.dart';
import '../widgets/session_scope.dart';
import 'login_page.dart';

/// AUTH-2 / AUTH-005 — email verification.
///
/// Reached right after signup: the account was created PENDING_VERIFICATION
/// and a one-time code was sent. Entering the code completes verification;
/// the screen offers a rate-limited resend and surfaces invalid/expired
/// errors inline. No verification token is ever rendered or logged client-side.
class EmailVerificationPage extends StatefulWidget {
  const EmailVerificationPage({super.key, required this.email, this.controller});

  static const String routeName = '/verify-email';

  final String email;
  final AuthController? controller;

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  final TextEditingController _codeController = TextEditingController();
  String? _error;

  AuthController get _controller =>
      widget.controller ?? SessionScope.controllerOf(context);

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter the verification code from your email.');
      return;
    }
    setState(() => _error = null);
    try {
      await _controller.verifyEmail(token: code);
      if (!mounted) return;
      _showSuccess();
    } on Exception {
      if (!mounted) return;
      setState(() {
        _error = _controller.lastError?.message ??
            'That verification code is invalid or has expired.';
      });
    }
  }

  Future<void> _resend() async {
    setState(() => _error = null);
    try {
      await _controller.resendEmailVerification(email: widget.email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A new verification code was sent.'),
        ),
      );
    } on Exception {
      if (!mounted) return;
      setState(() {
        _error = _controller.lastError?.message ??
            'Unable to send a new code right now. Try again shortly.';
      });
    }
  }

  void _showSuccess() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Email verified'),
        content: const Text(
          'Your email is verified. You can now sign in.',
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pushNamedAndRemoveUntil(
                LoginPage.routeName,
                (route) => false,
              );
            },
            child: const Text('Go to Login'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _controller.sessionBusy;

    return Scaffold(
      appBar: AppBar(title: const Text('Verify your email')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Icon(Icons.mark_email_read_outlined,
                  size: 72, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                'Check your inbox',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'We sent a one-time verification code to ${widget.email}. '
                    'Enter it below to activate your account.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _codeController,
                enabled: !busy,
                autocorrect: false,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Verification code',
                  prefixIcon: const Icon(Icons.verified_outlined),
                  errorText: _error,
                  helperText: 'Sent by email; expires after a short time.',
                ),
                onSubmitted: (_) => _verify(),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: busy ? null : _verify,
                child: busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Verify Email'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: busy ? null : _resend,
                child: const Text('Resend verification code'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil(
                  LoginPage.routeName,
                  (route) => false,
                ),
                child: const Text('I\'ll verify later — go to login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}