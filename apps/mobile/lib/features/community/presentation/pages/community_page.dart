import 'package:flutter/material.dart';

import '../../../../shared/widgets/module_placeholder_page.dart';

class CommunityPage extends StatelessWidget {
  const CommunityPage({super.key});

  static const String routeName = '/community';

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholderPage(
      title: 'Community',
      description:
          'Connect with fellow warriors — support groups, '
          'stories, events and peer-to-peer encouragement.',
      icon: Icons.groups,
    );
  }
}
