import 'package:flutter/material.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../shared/widgets/app_logo.dart';
import '../../data/auth_repository.dart';
import '../../data/token_store.dart';
import 'reset_password_page.dart';

/// Forgot password page for password reset request (AUTH + PUBLIC HOME).
///
/// Allows users to request a password reset using their login identity (email
/// or phone). The backend responds uniformly (no account enumeration) and
/// sends the reset token only when the identifier matches a registered account.
///
/// The code is delivered as an in-app SYSTEM notification (no email link), so
/// the confirmation state offers the "Enter reset code" step that carries the
/// user into [ResetPasswordPage] — without it the flow dead-ended here.
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key, this.repository});

  static const String routeName = '/forgot-password';

  /// Repository override (widget tests inject a mock HTTP client).
  final AuthRepository? repository;

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
    final s = l10n(context);
    if (value == null || value.trim().isEmpty) {
      return s.tr('auth.identifierRequired');
    }
    if (!value.contains('@')) {
      final digits = value.replaceAll(RegExp(r'[^\d]'), '');
      if (digits.length < 9 || digits.length > 15) {
        return s.tr('auth.identifierInvalid');
      }
    }
    return null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);

    try {
      final repo = widget.repository ??
          AuthRepository(tokenStore: EphemeralTokenStore());
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
      _showError(l10n(context).tr('auth.resetRequestFailed'));
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
    final s = l10n(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.tr('auth.resetPasswordTitle')),
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
                const AppLogo(height: 88),
                const SizedBox(height: 16),
                Text(
                  _requestSent
                      ? s.tr('auth.checkNotifications')
                      : s.tr('auth.forgotTitle'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  _requestSent
                      ? s.tr('auth.resetNotice')
                      : s.tr('auth.resetIntro'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                if (!_requestSent) ...[
                  TextFormField(
                    controller: _identifierController,
                    decoration: InputDecoration(
                      labelText: s.tr('auth.emailOrPhone'),
                      prefixIcon:
                          const Icon(Icons.alternate_email_outlined),
                      helperText: s.tr('auth.identifierHint'),
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
                        : Text(s.tr('auth.sendResetCode')),
                  ),
                ] else ...[
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => Navigator.pushNamed(
                      context,
                      ResetPasswordPage.routeName,
                    ),
                    child: Text(s.tr('auth.enterResetCode')),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.pushReplacementNamed(
                      context,
                      '/login',
                    ),
                    child: Text(s.tr('auth.returnToLogin')),
                  ),
                ],
                const SizedBox(height: 16),
                if (!_requestSent)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(s.tr('auth.backToLogin')),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
