import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../shared/widgets/app_logo.dart';
import '../../data/auth_repository.dart';
import '../../data/token_store.dart';
import '../controllers/auth_controller.dart';
import '../widgets/session_router.dart';
import '../widgets/session_scope.dart';
import 'continue_as_page.dart';

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
    super.dispose();
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
      // Backend-driven role routing (AUTH-2): the server-asserted session
      // decides which experience opens. A single unambiguous context is
      // entered directly; multi-role sessions stop at "Continue as" so no
      // role is silently dropped.
      final resolved = SessionRouter.resolve(
        roles: _controller.roles,
        doctorVerificationStatus: _controller.doctorVerificationStatus,
      );
      Navigator.pushReplacementNamed(
        context,
        resolved?.route ?? ContinueAsPage.routeName,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _controller.lastError?.message ?? AppStrings.loginFailed,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.tr('common.signIn'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
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
                const SizedBox(height: 32),
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
      ),
    );
  }
}