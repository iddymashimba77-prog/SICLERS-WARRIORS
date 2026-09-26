import 'package:flutter/material.dart';

import '../../../../shared/widgets/module_placeholder_page.dart';

class ClinicPage extends StatelessWidget {
  const ClinicPage({super.key});

  static const String routeName = '/clinic';

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholderPage(
      title: 'Clinic Calendar',
      description:
          'Book and manage clinic appointments — upcoming visits, '
          'vaccinations and follow-ups.',
      icon: Icons.event_available_outlined,
    );
  }
}
