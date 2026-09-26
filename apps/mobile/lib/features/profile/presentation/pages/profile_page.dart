import 'package:flutter/material.dart';

import '../../../../shared/widgets/module_placeholder_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  static const String routeName = '/profile';

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholderPage(
      title: 'Profile',
      description:
          'Your personal account information, emergency contacts, '
          'blood type, genotype and notification preferences.',
      icon: Icons.person_outline,
    );
  }
}
