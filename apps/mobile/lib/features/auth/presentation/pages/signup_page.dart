import 'package:flutter/material.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_shapes.dart';
import '../../../../shared/widgets/app_logo.dart';
import '../../data/auth_repository.dart';
import '../../data/token_store.dart';
import '../controllers/auth_controller.dart';
import '../widgets/session_scope.dart';
import 'set_pin_page.dart';
import 'verification_submission_page.dart';

/// Sign up page for new user registration (AUTH-2 / AUTH-005).
///
/// Every non-admin role is self-registerable here (Patient/Sickler, Caregiver,
/// Blood Donor, Doctor, Psychologist, Social Support, Hospital, Clinic,
/// Organization). Professional and facility roles mark the account
/// "requires verification": the server gates them behind government-verified
/// documents (C5 pipeline), and this page routes them straight to
/// [VerificationSubmissionPage] after registration. Emails are always confirmed
/// with a one-time code so the account can move out of PENDING_VERIFICATION.
class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  static const String routeName = '/signup';

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _submitting = false;
  String _roleCode = 'PATIENT';

  AuthController get _controller =>
      SessionScope.maybeOf(context) ??
      AuthController(
        repository: AuthRepository(tokenStore: EphemeralTokenStore()),
      );

  /// Every registerable role (no administrator roles). The `verified` flag is
  /// a copy of the server's `verification_required` contract: those codes are
  /// gated behind the government-verified document pipeline (C5).
  static const List<(String, String, IconData, bool)> _roleOptions = [
    ('PATIENT', 'auth.rolePatient', Icons.favorite_outline, false),
    ('CAREGIVER', 'auth.roleCaregiver', Icons.family_restroom_outlined, false),
    ('BLOOD_DONOR', 'auth.roleDonor', Icons.bloodtype_outlined, false),
    ('DOCTOR', 'auth.roleDoctor', Icons.medical_services_outlined, true),
    ('PSYCHOLOGIST', 'auth.rolePsychologist', Icons.psychology_outlined, true),
    ('SOCIAL_SUPPORT', 'auth.roleSocialWorker', Icons.support_agent_outlined, true),
    ('HOSPITAL', 'auth.roleHospital', Icons.local_hospital_outlined, true),
    ('CLINIC', 'auth.roleClinic', Icons.healing_outlined, true),
    ('ORGANIZATION', 'auth.roleOrganization', Icons.account_balance_outlined, true),
  ];

  static bool _needsVerification(String roleCode) =>
      _roleOptions.firstWhere((o) => o.$1 == roleCode).$4;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final s = l10n(context);
    if (value == null || value.isEmpty) {
      return s.tr('auth.emailRequired');
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) {
      return s.tr('auth.emailInvalid');
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
    setState(() => _submitting = true);

    await _controller.register(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      firstName: _firstNameController.text.trim().isEmpty
          ? null
          : _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim().isEmpty
          ? null
          : _lastNameController.text.trim(),
      roleCode: _roleCode,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    final s = l10n(context);
    if (_controller.lastError != null) {
      final err = _controller.lastError!;
      _showError(
        err.code == 'NETWORK_ERROR' ? s.tr('err.network') : err.message,
      );
      return;
    }

    // Registration succeeded — always confirm it explicitly so the user is not
    // met with an ambiguous spinner/route swap.
    if (_needsVerification(_roleCode)) {
      // IAS-331/C5: professional & facility roles must attach government
      // documents next. The server already holds a usable session.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.tr('auth.registrationSuccess'))),
      );
      Navigator.pushNamedAndRemoveUntil(
        context,
        VerificationSubmissionPage.routeName,
        (route) => false,
        arguments: {'roleCode': _roleCode},
      );
      return;
    }
    if (_controller.isAuthenticated) {
      // Non-professional account: the server issued a usable session at
      // registration. Create the 4-digit login PIN, then enter the app.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.tr('auth.registrationSuccess'))),
      );
      Navigator.pushNamedAndRemoveUntil(
        context,
        SetPinPage.routeName,
        (route) => false,
      );
      return;
    }
    // No usable session was returned — send the new account to sign in.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.tr('auth.registrationSuccess'))),
    );
    Navigator.pushReplacementNamed(context, '/login');
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
        title: Text(s.tr('auth.signUpCta')),
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
                  s.tr('auth.signUpTitle'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  s.tr('auth.joinCommunity'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  s.tr('auth.accountFor'),
                  textAlign: TextAlign.start,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    // 2 columns on very narrow devices so role chips never
                    // truncate; 3 everywhere else.
                    final columns = constraints.maxWidth < 340 ? 2 : 3;
                    return GridView.count(
                      crossAxisCount: columns,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: columns == 2 ? 1.45 : 1.15,
                      children: [
                        for (final (code, labelKey, icon, verified) in _roleOptions)
                          _PurposeOption(
                            icon: icon,
                            label: s.tr(labelKey),
                            verified: verified,
                            selected: _roleCode == code,
                            onTap: () => setState(() => _roleCode = code),
                          ),
                      ],
                    );
                  },
                ),
                if (_needsVerification(_roleCode)) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: AppShapes.tile,
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.6),
                      border: Border.all(color: theme.colorScheme.outlineVariant),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.badge_outlined,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            s.tr('auth.verificationRequired'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: s.tr('auth.email'),
                    prefixIcon: const Icon(Icons.email_outlined),
                    helperText: s.tr('auth.emailLoginIdentity'),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  validator: _validateEmail,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _firstNameController,
                        decoration: InputDecoration(
                          labelText: s.tr('auth.firstName'),
                          prefixIcon: const Icon(Icons.person_outline),
                        ),
                        textCapitalization: TextCapitalization.words,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _lastNameController,
                        decoration: InputDecoration(
                          labelText: s.tr('auth.lastName'),
                          prefixIcon: const Icon(Icons.person_outline),
                        ),
                        textCapitalization: TextCapitalization.words,
                      ),
                    ),
                  ],
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
                    helperText: s.tr('auth.minChars'),
                  ),
                  validator: _validatePassword,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  decoration: InputDecoration(
                    labelText: s.tr('auth.confirmPassword'),
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
                      : Text(s.tr('auth.signUpCta')),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        '${s.tr('auth.haveAccount')} ',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pushReplacementNamed(
                        context,
                        '/login',
                      ),
                      child: Text(s.tr('auth.signIn')),
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

class _PurposeOption extends StatelessWidget {
  const _PurposeOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.verified = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Server contract: this role is gated behind the government-verified
  /// document pipeline (C5).
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: AppShapes.tile,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: AppShapes.tile,
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : null,
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 22, color: color),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10.5,
                      height: 1.1,
                      color: color,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (verified)
              Positioned(
                top: 2,
                right: 2,
                child: Icon(
                  Icons.verified,
                  size: 13,
                  color: theme.colorScheme.primary
                      .withValues(alpha: selected ? 1 : 0.7),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
