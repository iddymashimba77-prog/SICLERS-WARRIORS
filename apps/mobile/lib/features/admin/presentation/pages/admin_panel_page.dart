import 'package:flutter/material.dart';

import '../../../../shared/widgets/module_placeholder_page.dart';

class AdminPanelPage extends StatelessWidget {
  const AdminPanelPage({super.key});

  static const String routeName = '/admin';

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholderPage(
      title: 'Admin Panel',
      description:
          'Restricted area for administrators — user management, '
          'doctor verification, content moderation and system analytics.',
      icon: Icons.admin_panel_settings_outlined,
    );
  }
}
