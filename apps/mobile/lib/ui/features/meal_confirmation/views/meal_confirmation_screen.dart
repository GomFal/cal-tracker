import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations_context.dart';
import '../../../core/design_system.dart';

class MealConfirmationScreen extends StatelessWidget {
  const MealConfirmationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    return Scaffold(
      backgroundColor: palette.screen,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: FreshCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FreshIconChip(
                    icon: Icons.check_rounded,
                    color: palette.limeDeep,
                  ),
                  const SizedBox(height: FreshSpacing.md),
                  Text(context.l10n.mealConfirmationEmbedded),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
