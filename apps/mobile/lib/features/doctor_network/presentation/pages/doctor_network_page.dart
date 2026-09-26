import 'package:flutter/material.dart';

import '../../../../shared/widgets/module_placeholder_page.dart';

class DoctorNetworkPage extends StatelessWidget {
  const DoctorNetworkPage({super.key});

  static const String routeName = '/doctors';

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholderPage(
      title: 'Doctor Network',
      description:
          'Find and chat with verified sickle cell specialists, '
          'book appointments and access your care team.',
      icon: Icons.local_hospital_outlined,
    );
  }
}
