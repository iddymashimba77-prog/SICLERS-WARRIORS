import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/settings_sheet.dart';
import '../../../auth/domain/auth_types.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/pages/change_password_page.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../../medical/presentation/pages/medical_profile_page.dart';
import '../../../notifications/presentation/pages/notifications_page.dart';
import '../../../public/presentation/pages/public_home_page.dart';
import '../../data/profile_repository.dart';
import '../widgets/profile_view.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, this.authController, this.repository});

  static const String routeName = '/profile';

  final AuthController? authController;
  final ProfileRepository? repository;

  @override
  Widget build(BuildContext context) {
    // Shared app session when rendered inside the shell; explicit controller
    // (widget tests / standalone) wins when provided.
    final controller =
        authController ?? SessionScope.controllerOf(context);
    final email = controller.email ?? AppStrings.appName;
    final roles = controller.roles;
    final token = controller.accessToken;
    final repository =
        this.repository ?? ProfileRepository(tokenStore: EphemeralTokenStore());
    final s = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(s.tr('profile.title'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ProfilePhotoHeader(
              email: email,
              roles: roles,
              accessToken: token,
              repository: repository,
              controller: controller,
            ),
            const Divider(height: 32),
            if (token == null)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: Text(AppStrings.profileLoadFailed)),
              )
            else
              ProfileView(
                repository: repository,
                accessToken: token,
                canEdit: roles.contains('PATIENT'),
              ),
            const Divider(height: 32),
            Text(
              s.tr('profile.preferences').toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            _SettingTile(
              icon: Icons.palette_outlined,
              title: s.tr('profile.appearanceLanguage'),
              subtitle: s.tr('profile.adaptExperience'),
              onTap: () => showSettingsSheet(context),
            ),
            const Divider(height: 32),
            Text(
              s.tr('profile.securityPrivacy').toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            _SettingTile(
              icon: Icons.medical_services_outlined,
              title: s.tr('profile.medicalProfile'),
              subtitle: s.tr('profile.medicalIdentity'),
              onTap: () =>
                  Navigator.pushNamed(context, MedicalProfilePage.routeName),
            ),
            _SettingTile(
              icon: Icons.notifications_outlined,
              title: s.tr('profile.notificationPreferences'),
              subtitle: s.tr('profile.emergencyAlwaysOn'),
              onTap: () =>
                  Navigator.pushNamed(context, NotificationsPage.routeName),
            ),
            _SettingTile(
              icon: Icons.lock_outline,
              title: s.tr('profile.changePassword'),
              subtitle: s.tr('profile.sessionOnDevice'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChangePasswordPage(
                      accessToken: token!,
                      controller: controller,
                    ),
                  ),
                );
              },
            ),
            _SettingTile(
              icon: Icons.shield_outlined,
              title: s.tr('profile.consentPrivacy'),
              subtitle: s.tr('profile.consentBody'),
              onTap: () => showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(s.tr('profile.consentPrivacy')),
                  content: Text(s.tr('profile.consentBody')),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text(s.tr('common.close')),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 32),
            OutlinedButton.icon(
              onPressed: () => _confirmSignOut(context),
              icon: const Icon(Icons.logout),
              label: Text(s.tr('common.signOut')),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final s = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.tr('common.signOut')),
        content: Text(AppStrings.signOutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.tr('common.signOut')),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      final controller =
          authController ?? SessionScope.controllerOf(context);
      await controller.logout();
      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          PublicHomePage.routeName,
          (route) => false,
        );
      }
    }
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(title),
        subtitle: Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// Editable avatar header: shows the current profile picture (person icon
/// before any upload) and opens a picker sheet on tap — camera or gallery —
/// then uploads the chosen image to `/api/auth/me/photo/` and swaps in the
/// server-returned URL.
class _ProfilePhotoHeader extends StatefulWidget {
  const _ProfilePhotoHeader({
    required this.email,
    required this.roles,
    this.accessToken,
    this.repository,
    this.controller,
  });

  final String email;
  final List<String> roles;
  final String? accessToken;
  final ProfileRepository? repository;

  /// Source of server-truth photo URL: ProfilePage rebuilds on every session
  /// notify, so the header stays in sync with login / /auth/me restores.
  final AuthController? controller;

  @override
  State<_ProfilePhotoHeader> createState() => _ProfilePhotoHeaderState();
}

class _ProfilePhotoHeaderState extends State<_ProfilePhotoHeader> {
  final ImagePicker _picker = ImagePicker();
  String? _photoUrl;
  bool _uploading = false;

  Future<void> _pick(ImageSource source) async {
    final access = widget.accessToken;
    final repository = widget.repository;
    if (access == null || repository == null) return;
    if (_uploading) return;
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1000,
        imageQuality: 82,
      );
      if (file == null) return;
      if (!mounted) return;
      setState(() => _uploading = true);
      final bytes = await file.readAsBytes();
      final url = await repository.uploadProfilePhoto(
        access: access,
        bytes: bytes,
        filename: file.name,
        mimeType: _mimeTypeForName(file.name),
      );
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _photoUrl = url;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n(context).tr('profile.photoUpdated'))),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_photoErrorMessage(context, error))),
      );
    }
  }

  /// Prefer the repository's specific message (wrong type, too large, server
  /// validation) over a blanket "could not upload" — the user needs to know
  /// which image to pick instead.
  String _photoErrorMessage(BuildContext context, Object error) {
    if (error is AuthException) {
      switch (error.code) {
        case 'UNSUPPORTED_PHOTO_TYPE':
          return l10n(context).tr('profile.photoNotSupported');
        case 'PHOTO_TOO_LARGE':
          return l10n(context).tr('profile.photoTooLarge');
        case 'EMPTY_PHOTO':
          return l10n(context).tr('profile.photoEmpty');
        default:
          final message = error.message.trim();
          if (message.isNotEmpty && !message.contains('Exception')) {
            return message;
          }
      }
    }
    return l10n(context).tr('profile.photoUploadFailed');
  }

  /// Best-effort extension hint; the repository verifies against magic bytes.
  String? _mimeTypeForName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return null;
  }

  void _showSourceSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              subtitle: const Text('Use the camera to capture a new picture'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pick(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              subtitle: const Text('Pick an existing image from your device'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pick(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Prefer the in-session upload result; otherwise fall back to the URL the
    // server asserted on login/me so a restart shows the same picture.
    final photoUrl = _photoUrl ?? widget.controller?.photoUrl;
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
    return Row(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            InkWell(
              key: const Key('profile-photo'),
              customBorder: const CircleBorder(),
              onTap: _uploading ? null : _showSourceSheet,
              child: _uploading
                  ? const CircleAvatar(
                      radius: 28,
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    )
                  : hasPhoto
                      ? CircleAvatar(
                          radius: 28,
                          backgroundColor: AppColors.surface,
                          backgroundImage: NetworkImage(photoUrl),
                        )
                      : const CircleAvatar(
                          radius: 28,
                          child: Icon(Icons.person_outline, size: 32),
                        ),
            ),
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: AppColors.blue,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(
                  Icons.photo_camera_outlined,
                  size: 12,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.email,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final role in widget.roles)
                    Chip(
                      label: Text(role),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: AppColors.surface,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}