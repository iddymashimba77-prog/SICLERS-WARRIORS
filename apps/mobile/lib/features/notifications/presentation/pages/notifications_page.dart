import 'package:flutter/material.dart';

import '../../../../shared/widgets/module_placeholder_page.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  static const String routeName = '/notifications';

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholderPage(
      title: 'Notifications',
      description:
          'Medication reminders, donation requests, appointment '
          'alerts and community updates.',
      icon: Icons.notifications_outlined,
    );
  }
}
