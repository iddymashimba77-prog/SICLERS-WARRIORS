import 'package:flutter/material.dart';

import '../../../../shared/widgets/module_placeholder_page.dart';

class BloodDonationPage extends StatelessWidget {
  const BloodDonationPage({super.key});

  static const String routeName = '/blood-donation';

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholderPage(
      title: 'Blood Donation',
      description:
          'Blood donation request/response system — find or '
          'become a donor within the warrior network.',
      icon: Icons.bloodtype_outlined,
    );
  }
}
