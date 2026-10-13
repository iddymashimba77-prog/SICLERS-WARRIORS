import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../shared/widgets/app_logo.dart';
import '../controllers/auth_controller.dart';
import '../widgets/session_router.dart';
import '../widgets/session_scope.dart';
import 'continue_as_page.dart';

/// First-run PIN setup (AUTH-2): shown right after the first email+password
/// sign-in or a fresh registration. The user chooses a 4-digit PIN that later
/// signs them in on this device without retyping the password.
class SetPinPage extends StatefulWidget {
  const SetPinPage({super.key, this.controller});

  static const String routeName = '/set-pin';

  final AuthController? controller;

  @override
  State<SetPinPage> createState() => _SetPinPageState();
}

class _SetPinPageState extends State<SetPinPage> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _submitting = false;

  AuthController get _controller =>
      widget.controller ?? SessionScope.controllerOf(context);

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool _isFourDigits(String value) => RegExp(r'^\d{4}$').hasMatch(value);

  Future<void> _save() async {
    final s = l10n(context);
    final pin = _pinController.text;
    if (!_isFourDigits(pin)) {
      _showError(s.tr('auth.pinLength'));
      return;
    }
    if (pin != _confirmController.text) {
      _showError(s.tr('auth.pinMismatch'));
      return;
    }
    setState(() => _submitting = true);
    await _controller.setLoginPin(pin: pin);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (_controller.hasLoginPin) {
      final resolved = SessionRouter.resolve(
        roles: _controller.roles,
        doctorVerificationStatus: _controller.doctorVerificationStatus,
      );
      Navigator.pushNamedAndRemoveUntil(
        context,
        resolved?.route ?? ContinueAsPage.routeName,
        (route) => false,
      );
    } else {
      _showError(_controller.lastError?.message ?? s.tr('err.generic'));
    }
  }

  void _skip() {
    final resolved = SessionRouter.resolve(
      roles: _controller.roles,
      doctorVerificationStatus: _controller.doctorVerificationStatus,
    );
    Navigator.pushNamedAndRemoveUntil(
      context,
      resolved?.route ?? ContinueAsPage.routeName,
      (route) => false,
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _pinField({
    required TextEditingController controller,
    required String label,
    required AppLocalizations s,
    bool enabled = true,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: 4,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.pin_outlined),
        counterText: '',
        helperText: s.tr('auth.pinHint'),
      ),
      onSubmitted: (_) => _save(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = l10n(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.tr('auth.setPinTitle'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              const AppLogo(height: 72),
              const SizedBox(height: 16),
              Text(
                s.tr('auth.setPinTitle'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                s.tr('auth.setPinBody'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              _pinField(controller: _pinController, label: s.tr('auth.pin'), s: s),
              const SizedBox(height: 16),
              _pinField(
                controller: _confirmController,
                label: s.tr('auth.confirmPin'),
                s: s,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _submitting ? null : _save,
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(s.tr('auth.savePin')),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _submitting ? null : _skip,
                child: Text(s.tr('auth.usePasswordInstead')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
