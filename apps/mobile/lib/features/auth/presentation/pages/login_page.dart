import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../shared/widgets/app_logo.dart';
import '../../data/auth_repository.dart';
import '../../data/token_store.dart';
import '../controllers/auth_controller.dart';
import '../widgets/session_router.dart';
import '../widgets/session_scope.dart';
import 'continue_as_page.dart';
import 'set_pin_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.controller});

  static const String routeName = '/login';

  final AuthController? controller;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  bool _obscurePassword = true;
  bool _submitting = false;

  AuthController get _controller =>
      widget.controller ??
      // Real app: reuse the single app-level session so the tokens we just
      // logged in with survive the switch into the shell.
      SessionScope.maybeOf(context) ??
      // Standalone fallback (widget tests): in-memory store, no network.
      AuthController(
        repository: AuthRepository(tokenStore: EphemeralTokenStore()),
      );

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  /// Whether to present the PIN pad: a remembered identity that configured a
  /// PIN on this device. Falls back to email+password otherwise.
  bool get _usePin => _controller.rememberedIdentity != null;

  void _afterAuthenticated() {
    if (!_controller.hasLoginPin) {
      // First sign-in on this account: create the 4-digit login PIN first.
      Navigator.pushReplacementNamed(context, SetPinPage.routeName);
      return;
    }
    // Backend-driven role routing (AUTH-2): the server-asserted session
    // decides which experience opens. A single unambiguous context is entered
    // directly; multi-role sessions stop at "Continue as" so no role is
    // silently dropped.
    final resolved = SessionRouter.resolve(
      roles: _controller.roles,
      doctorVerificationStatus: _controller.doctorVerificationStatus,
    );
    Navigator.pushReplacementNamed(
      context,
      resolved?.route ?? ContinueAsPage.routeName,
    );
  }

  void _showFailure() {
    final err = _controller.lastError;
    final message = err?.code == 'NETWORK_ERROR'
        ? l10n(context).tr('err.network')
        : (err?.message ?? AppStrings.loginFailed);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    await _controller.login(
      identifier: _emailController.text.trim(),
      password: _passwordController.text,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (_controller.isAuthenticated) {
      _afterAuthenticated();
    } else {
      _showFailure();
    }
  }

  Future<void> _submitPin() async {
    final pin = _pinController.text.trim();
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n(context).tr('auth.pinLength'))),
      );
      return;
    }
    setState(() => _submitting = true);
    await _controller.loginWithPin(pin: pin);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (_controller.isAuthenticated) {
      _afterAuthenticated();
    } else {
      _showFailure();
    }
  }

  Future<void> _usePasswordInstead() async {
    await _controller.forgetRememberedIdentity();
    if (!mounted) return;
    setState(() => _pinController.clear());
  }

  Widget _pinSignIn(AppLocalizations s) {
    final identity = _controller.rememberedIdentity ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        TextField(
          controller: _pinController,
          enabled: !_submitting,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textInputAction: TextInputAction.done,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                letterSpacing: 12,
              ),
          decoration: InputDecoration(
            labelText: s.tr('auth.pin'),
            counterText: '',
            prefixIcon: const Icon(Icons.pin_outlined),
            helperText: s.tr('auth.pinHint'),
          ),
          onSubmitted: (_) => _submitPin(),
        ),
        const SizedBox(height: 8),
        Text(
          s.tr('auth.enterPinFor', args: {'account': identity}),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _submitting ? null : _submitPin,
          child: _submitting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(s.tr('auth.signInWithPin')),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _submitting ? null : _usePasswordInstead,
          child: Text(s.tr('auth.usePasswordInstead')),
        ),
      ],
    );
  }

  Widget _passwordSignIn(AppLocalizations s) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _emailController,
            decoration: InputDecoration(
              labelText: s.tr('auth.emailOrPhone'),
              prefixIcon: const Icon(Icons.email_outlined),
            ),
            keyboardType: TextInputType.emailAddress,
            validator: (String? value) {
              if (value == null || value.isEmpty) {
                return s.tr('auth.requiredEmail');
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: s.tr('auth.password'),
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
            ),
            validator: (String? value) {
              if (value == null || value.isEmpty) {
                return s.tr('auth.requiredPassword');
              }
              return null;
            },
            onFieldSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.pushNamed(context, '/forgot-password'),
              child: Text(s.tr('auth.forgotPassword')),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(s.tr('common.signIn')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final pinMode = _usePin;
    return Scaffold(
      appBar: AppBar(
        title: Text(pinMode ? s.tr('auth.signInWithPin') : s.tr('common.signIn')),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              const AppLogo(height: 44),
              const SizedBox(height: 8),
              Text(
                AppStrings.appName,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              if (pinMode) _pinSignIn(s) else _passwordSignIn(s),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      '${s.tr('auth.noAccount')} ',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pushReplacementNamed(
                      context,
                      '/signup',
                    ),
                    child: Text(s.tr('common.signUp')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
