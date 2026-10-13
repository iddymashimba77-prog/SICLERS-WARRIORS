import 'package:flutter/material.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../shared/widgets/app_logo.dart';
import '../../data/auth_repository.dart';
import '../../data/token_store.dart';

/// Reset password page for completing password reset (AUTH + PUBLIC HOME).
///
/// The backend issues a single-use `PASSWORD_RESET` code (30 min) and hands it
/// to the user through an in-app SYSTEM notification — there is no email link —
/// so this screen accepts the code two ways:
///
///  * pre-filled via the `token` route argument (a caller can hand the code
///    straight over), or
///  * typed into the code field rendered whenever no token was supplied.
///
/// Without the field the route was a dead end: `token == null` short-circuited
/// every submit to "Invalid reset link" and nothing could complete a reset.
class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key, this.token, this.repository});

  static const String routeName = '/reset-password';

  final String? token;

  /// Repository override (widget tests inject a mock HTTP client).
  final AuthRepository? repository;

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _submitting = false;

  /// True when the page must ask for the code itself.
  bool get _needsCode => widget.token == null || widget.token!.isEmpty;

  @override
  void dispose() {
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _validateCode(String? value) {
    if (!_needsCode) return null;
    if (value == null || value.trim().isEmpty) {
      return l10n(context).tr('auth.resetCodeRequired');
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final s = l10n(context);
    if (value == null || value.isEmpty) {
      return s.tr('auth.passwordRequired');
    }
    if (value.length < 8) {
      return s.tr('auth.passwordMin');
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    final s = l10n(context);
    if (value == null || value.isEmpty) {
      return s.tr('auth.confirmAgain');
    }
    if (value != _passwordController.text) {
      return s.tr('auth.passwordMismatch');
    }
    return null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final token = _needsCode ? _codeController.text.trim() : widget.token!;
    if (token.isEmpty) {
      _showError(l10n(context).tr('auth.resetInvalidLink'));
      return;
    }

    setState(() => _submitting = true);

    try {
      final repo = widget.repository ??
          AuthRepository(tokenStore: EphemeralTokenStore());
      await repo.confirmPasswordReset(
        token: token,
        password: _passwordController.text,
      );
      if (!mounted) return;
      setState(() => _submitting = false);
      _showSuccessDialog();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _showError(l10n(context).tr('auth.resetFailed'));
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showSuccessDialog() {
    final s = l10n(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(s.tr('auth.resetSuccess')),
        content: Text(s.tr('auth.resetSuccessBody')),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.pushReplacementNamed(context, '/login');
            },
            child: Text(s.tr('auth.goToLogin')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = l10n(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.tr('auth.resetPasswordTitle')),
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
                const AppLogo(height: 72),
                const SizedBox(height: 16),
                Text(
                  s.tr('auth.setNewPassword'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  _needsCode
                      ? s.tr('auth.resetCodeThenPassword')
                      : s.tr('auth.enterNewPassword'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                if (_needsCode) ...[
                  TextFormField(
                    controller: _codeController,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: s.tr('auth.resetCode'),
                      prefixIcon: const Icon(Icons.pin_outlined),
                      helperText: s.tr('auth.resetCodeHint'),
                    ),
                    validator: _validateCode,
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: s.tr('auth.newPassword'),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                    helperText: s.tr('auth.minChars'),
                  ),
                  validator: _validatePassword,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  decoration: InputDecoration(
                    labelText: s.tr('auth.confirmNewPassword'),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                    ),
                  ),
                  validator: _validateConfirmPassword,
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
                      : Text(s.tr('auth.resetPasswordTitle')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
