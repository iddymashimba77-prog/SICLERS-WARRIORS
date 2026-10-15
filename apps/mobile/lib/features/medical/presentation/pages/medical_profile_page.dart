import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../../profile/data/profile_repository.dart';
import '../../../profile/presentation/widgets/profile_view.dart';
import '../../../../shared/widgets/module_placeholder_page.dart';

class MedicalProfilePage extends StatelessWidget {
  const MedicalProfilePage({super.key, this.authController, this.repository});

  static const String routeName = '/medical';

  /// Optional auth injection; without it the page renders the PATIENT
  /// medical-identity form against the standalone (in-memory) wiring so
  /// widget tests and the shell can run without a full DI graph.
  final AuthController? authController;
  final ProfileRepository? repository;

  @override
  Widget build(BuildContext context) {
    final controller = authController ?? SessionScope.controllerOf(context);
    final isPatient = controller.isAuthenticated &&
        (controller.roles.contains('PATIENT') ||
            controller.roles.contains('CAREGIVER'));
    final token = controller.accessToken;

    if (!isPatient || token == null) {
      return ModulePlaceholderPage(
        title: AppStrings.medicalProfile,
        description: AppStrings.medicalIdentity,
        icon: Icons.medical_services_outlined,
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.medicalProfile)),
      body: SafeArea(
        child: ProfileView(
          repository: repository ?? ProfileRepository(tokenStore: EphemeralTokenStore()),
          accessToken: token,
          canEdit: controller.roles.contains('PATIENT'),
        ),
      ),
    );
  }
}