import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';

class EmergencyPage extends StatelessWidget {
  const EmergencyPage({super.key});

  static const String routeName = '/emergency';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.emergency,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.sos, size: 96, color: Colors.white),
              const SizedBox(height: 24),
              Text(
                AppStrings.emergencySupport,
                style: Theme.of(
                  context,
                ).textTheme.headlineSmall?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 48),
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.emergency,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48,
                    vertical: 16,
                  ),
                ),
                onPressed: () {},
                child: const Text('Trigger SOS Alert'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
