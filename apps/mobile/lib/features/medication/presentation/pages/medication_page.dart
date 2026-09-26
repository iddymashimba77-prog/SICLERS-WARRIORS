import 'package:flutter/material.dart';

import '../../../../shared/widgets/module_placeholder_page.dart';

class MedicationPage extends StatelessWidget {
  const MedicationPage({super.key});

  static const String routeName = '/medication';

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholderPage(
      title: 'Medication Reminders',
      description:
          'Track your medication schedule, set reminders '
          '(Hydroxyurea, Folic Acid) and get adherence notifications.',
      icon: Icons.medication_outlined,
    );
  }
}
