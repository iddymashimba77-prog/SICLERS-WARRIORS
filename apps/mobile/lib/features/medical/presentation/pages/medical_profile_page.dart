import 'package:flutter/material.dart';

import '../../../../shared/widgets/module_placeholder_page.dart';

class MedicalProfilePage extends StatelessWidget {
  const MedicalProfilePage({super.key});

  static const String routeName = '/medical';

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholderPage(
      title: 'Medical Profile',
      description:
          'Manage your sickle cell health records, genotype, '
          'crisis history and care team information.',
      icon: Icons.medical_services_outlined,
    );
  }
}
