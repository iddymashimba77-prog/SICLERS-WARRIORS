import 'package:flutter/material.dart';

import '../../../../shared/widgets/module_placeholder_page.dart';

class AiAssistantPage extends StatelessWidget {
  const AiAssistantPage({super.key});

  static const String routeName = '/ai-assistant';

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholderPage(
      title: 'AI Assistant',
      description:
          'Smart symptom guidance and personalised sickle cell '
          'insights powered by the intelligence layer.',
      icon: Icons.smart_toy_outlined,
    );
  }
}
