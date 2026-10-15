import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/domain/auth_types.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/pages/login_page.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({
    super.key,
    required this.accessToken,
    this.controller,
    this.repository,
  });

  static const String routeName = '/change-password';

  final String accessToken;
  final AuthController? controller;
  final AuthRepository? repository;

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;

  AuthRepository get _repository => widget.repository ??
      AuthRepository(tokenStore: EphemeralTokenStore());

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    try {
      await _repository.changePassword(
        access: widget.accessToken,
        currentPassword: _currentController.text,
        newPassword: _newController.text,
      );
      if (!mounted) return;
      setState(() => _submitting = false);
      // The backend revokes *every* session on password change — end the local
      // session and route back through the sign-in screen.
      await widget.controller?.logout();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(AppStrings.changePassword),
          content: Text(AppStrings.passwordChanged),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(AppStrings.close),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        LoginPage.routeName,
        (route) => false,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message.isNotEmpty
              ? e.message
              : AppStrings.passwordChangeFailed),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.passwordChangeFailed)),
      );
    }
  }

  String? _validateCurrent(String? value) {
    if (value == null || value.isEmpty) {
      return AppStrings.currentPassword;
    }
    return null;
  }

  String? _validateNew(String? value) {
    if (value == null || value.isEmpty) {
      return AppStrings.newPassword;
    }
    if (!isPasswordLongEnough(value)) {
      return AppStrings.newPasswordHint;
    }
    return null;
  }

  String? _validateConfirm(String? value) {
    if (value != _newController.text) {
      return AppStrings.passwordsDoNotMatch;
    }
    if (value == null || value.isEmpty) {
      return AppStrings.confirmNewPassword;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.changePassword)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 48,
                  color: AppColors.primary,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Changing your password signs out every session, including '
                  'this device.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.xl),
                TextFormField(
                  controller: _currentController,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: AppStrings.currentPassword,
                    prefixIcon: Icon(Icons.password_outlined),
                  ),
                  validator: _validateCurrent,
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _newController,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: AppStrings.newPassword,
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  validator: _validateNew,
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _confirmController,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: AppStrings.confirmNewPassword,
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  validator: _validateConfirm,
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    child: Text(_obscure ? 'Show passwords' : 'Hide passwords'),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(AppStrings.updatePassword),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}