import 'package:flutter/material.dart';

import '../../../../shared/widgets/module_placeholder_page.dart';

class DonationsPage extends StatelessWidget {
  const DonationsPage({super.key});

  static const String routeName = '/donations';

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholderPage(
      title: 'Financial Donations',
      description:
          'Support the mission — one-time or recurring donations '
          'that fund treatment, blood drives and community support.',
      icon: Icons.favorite_outline,
    );
  }
}
