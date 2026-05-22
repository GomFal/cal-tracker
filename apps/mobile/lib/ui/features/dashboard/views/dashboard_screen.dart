import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/dark_mode_toggle.dart';
import '../../../../domain/models/macro_distribution.dart';
import '../../../../domain/models/nutrition_models.dart';
import '../../../../l10n/app_localizations_context.dart';
import '../../../../l10n/meal_label_localizations.dart';
import '../../../core/content_frame.dart';
import '../../../core/design_system.dart';
import '../../../shared/meal_item_editor_sheet.dart';
import '../../auth/view_models/auth_view_model.dart';
import '../../hydration/hydration_format.dart';
import '../../meal_history/view_models/meal_history_view_model.dart';
import '../../settings/view_models/settings_view_model.dart';
import '../dashboard_time_labels.dart';
import '../view_models/dashboard_view_model.dart';
import 'calorie_target_sheet.dart';
import 'macro_distribution_sheet.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<DashboardViewModel>().load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<DashboardViewModel>();
    final user = context.watch<AuthViewModel>().user;
    final l10n = context.l10n;
    final summary = viewModel.summary;
    final displayName = user?.displayName.trim().isNotEmpty == true
        ? user!.displayName
        : l10n.fallbackUserName;
    return ContentFrame(
      title: displayName,
      subtitle: dashboardGreeting(DateTime.now(), l10n),
      leading: const _Avatar(),
      actions: const [DarkModeToggle()],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (viewModel.isLoading) ...[
            const LinearProgressIndicator(minHeight: 3),
            const SizedBox(height: FreshSpacing.md),
          ],
          if (viewModel.error != null) ...[
            FreshStatusBanner(
              icon: Icons.error_outline_rounded,
              title: l10n.dashboardCouldNotLoadToday,
              message: viewModel.error!,
              color: FreshColors.coral,
              action: TextButton.icon(
                onPressed: () => viewModel.load(forceRefresh: true),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(l10n.commonTryAgain),
              ),
            ),
            const SizedBox(height: FreshSpacing.md),
          ],
          _DailyProgressCard(
            summary: summary,
            onSetup: () => _showCalorieTargetSheet(context, viewModel),
          ),
          const SizedBox(height: FreshSpacing.md),
          _MacroSummaryRow(summary: summary),
          const SizedBox(height: FreshSpacing.md),
          _WaterIntakeCard(
            summary: summary,
            enabled: !viewModel.isLoading,
            onUpdate: viewModel.updateDailyWater,
          ),
          const SizedBox(height: FreshSpacing.lg),
          _MealSection(
            summary: summary,
            onEditMeal: (meal) => _showMealItemEditor(context, viewModel, meal),
            onDeleteMeal: (meal) => _confirmDeleteMeal(context, viewModel, meal),
          ),
        ],
      ),
    );
  }

  Future<void> _showMealItemEditor(
    BuildContext context,
    DashboardViewModel viewModel,
    Meal meal,
  ) async {
    final items = await showModalBottomSheet<List<MealItem>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => MealItemEditorSheet(
        meal: meal,
        keyPrefix: 'dashboard',
      ),
    );
    if (!context.mounted || items == null) return;
    await viewModel.correctMealItems(meal, items);
  }

  Future<void> _confirmDeleteMeal(
    BuildContext context,
    DashboardViewModel viewModel,
    Meal meal,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.historyDeleteMealTitle),
        content: Text(meal.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.commonDelete),
          ),
        ],
      ),
    );
    if (!context.mounted || confirmed != true) return;

    final deleted = await viewModel.deleteMeal(meal);
    if (!context.mounted) return;
    if (!deleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.dashboardCouldNotDeleteMeal)),
      );
      return;
    }
    await context.read<MealHistoryViewModel>().load(forceRefresh: true);
  }

  Future<void> _showCalorieTargetSheet(
    BuildContext context,
    DashboardViewModel viewModel,
  ) async {
    final summary = viewModel.summary;
    final selection = await showModalBottomSheet<CalorieTargetSelection>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => CalorieTargetSheet(
        initialValue: summary?.target.calories ?? 2200,
        estimateCalories: viewModel.estimateCalories,
      ),
    );
    if (!context.mounted || selection == null) return;
    final saved = await viewModel.updateCalorieTarget(
      selection.calories,
      source: selection.source,
      macroConfig: selection.macroConfig,
    );
    if (!context.mounted) return;
    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.calorieCouldNotSaveCalories),
        ),
      );
      return;
    }
    if (!context.mounted) return;
    await Future.wait([
      context.read<MealHistoryViewModel>().load(),
      context.read<SettingsViewModel>().load(),
    ]);
    if (!context.mounted ||
        selection.source != 'manual' ||
        selection.macroConfig != null) {
      return;
    }
    final shouldConfigure = await showModalBottomSheet<bool>(
          context: context,
          useSafeArea: true,
          builder: (context) => PostCalorieSaveMacroPrompt(
            calories: selection.calories,
          ),
        ) ??
        false;
    if (!context.mounted || !shouldConfigure) return;
    final macroConfig = await showModalBottomSheet<MacroDistributionConfig>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => MacroDistributionSheet(
        calories: selection.calories,
      ),
    );
    if (!context.mounted || macroConfig == null) return;
    final macroSaved = await viewModel.updateCalorieTarget(
      selection.calories,
      source: selection.source,
      macroConfig: macroConfig,
    );
    if (!context.mounted) return;
    if (!macroSaved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.calorieCouldNotSaveMacros),
        ),
      );
      return;
    }
    await Future.wait([
      context.read<MealHistoryViewModel>().load(),
      context.read<SettingsViewModel>().load(),
    ]);
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar();

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: palette.limeWash,
        shape: BoxShape.circle,
        border: Border.all(color: palette.surface, width: 3),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/images/icons/protein_icon.png',
        fit: BoxFit.cover,
      ),
    );
  }
}

class _DailyProgressCard extends StatelessWidget {
  const _DailyProgressCard({
    required this.summary,
    required this.onSetup,
  });

  final DailySummary? summary;
  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = context.freshPalette;
    final l10n = context.l10n;
    final consumed = summary?.consumed.calories ?? 0;
    final target = summary?.target.calories ?? 2200;
    final hasConfiguredTarget = summary?.calorieTargetConfigured ?? true;
    if (!hasConfiguredTarget) {
      return _CalorieSetupProgressCard(onTap: onSetup);
    }
    final remaining = (summary?.remaining.calories ?? target - consumed)
        .clamp(0, target)
        .toInt();
    final progress =
        target <= 0 ? 0.0 : (consumed / target).clamp(0, 1).toDouble();
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < 380;
    final ringSize = compact ? 118.0 : 132.0;
    final cardHeight = compact ? 124.0 : 136.0;
    return FreshCard(
      key: const ValueKey('dashboard_progress_card'),
      color: palette.limeSoft,
      radius: FreshRadii.xl,
      padding: EdgeInsets.fromLTRB(
        compact ? 20 : 24,
        compact ? 22 : 26,
        compact ? 18 : 22,
        compact ? 22 : 26,
      ),
      child: SizedBox(
        height: cardHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.dashboardTodayCalories,
                    key: const ValueKey('dashboard_today_calories_label'),
                    style: textTheme.titleSmall?.copyWith(
                      color: palette.inkSoft,
                      fontSize: compact ? 19 : 21,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$consumed',
                          key: const ValueKey('dashboard_consumed_calories'),
                          style: textTheme.displayLarge?.copyWith(
                            fontSize: compact ? 56 : 64,
                            height: 0.92,
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 7),
                        Padding(
                          padding: EdgeInsets.only(bottom: compact ? 8 : 9),
                          child: Text(
                            l10n.commonKcal,
                            style: textTheme.titleMedium?.copyWith(
                              color: palette.inkSoft,
                              fontSize: compact ? 16 : 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: FreshSpacing.lg),
            FreshProgressRing(
              progress: progress,
              size: ringSize,
              trackColor: palette.surface,
              center: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$remaining',
                      key: const ValueKey('dashboard_remaining_calories'),
                      style: textTheme.headlineMedium?.copyWith(
                        fontSize: compact ? 23 : 27,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Text(
                    '${l10n.commonKcal} ${l10n.dashboardCaloriesLeft}',
                    key: const ValueKey('dashboard_remaining_label'),
                    textAlign: TextAlign.center,
                    style: textTheme.labelSmall?.copyWith(
                      color: palette.inkSoft,
                      fontSize: compact ? 10 : 11,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalorieSetupProgressCard extends StatelessWidget {
  const _CalorieSetupProgressCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cardHeight = (screenWidth * 0.48).clamp(184.0, 206.0);
    final titleStyle = textTheme.headlineSmall?.copyWith(
      color: palette.ink,
      fontSize: screenWidth < 380 ? 31 : 35,
      height: 1.12,
      fontWeight: FontWeight.w800,
      letterSpacing: 0,
    );
    final radius = BorderRadius.circular(30);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('dashboard_progress_card'),
        borderRadius: radius,
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: palette.limeSoft,
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.055),
                blurRadius: 32,
                offset: const Offset(0, 18),
              ),
              BoxShadow(
                color: palette.lime.withValues(alpha: 0.12),
                blurRadius: 26,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: SizedBox(
              height: cardHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    child: _SetupDatePill(
                      label: dashboardDayMonthLabel(DateTime.now(), l10n),
                    ),
                  ),
                  Positioned(
                    top: 78,
                    left: 0,
                    right: 0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            l10n.calorieSetupHeadlinePrefix,
                            style: titleStyle,
                          ),
                        ),
                        const SizedBox(height: 8),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                l10n.calorieSetupHeadlineMain,
                                style: titleStyle,
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      palette.limeWash.withValues(alpha: 0.86),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Text(
                                  l10n.calorieSetupHeadlineBadge,
                                  style: titleStyle?.copyWith(
                                    color: palette.leaf,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SetupDatePill extends StatelessWidget {
  const _SetupDatePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        height: 36,
        padding: const EdgeInsets.only(left: 0, right: 17),
        decoration: BoxDecoration(
          color: palette.surface.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: palette.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.bolt_rounded,
                color: palette.limeDeep,
                size: 21,
              ),
            ),
            const SizedBox(width: 13),
            Text(
              label,
              style: textTheme.titleMedium?.copyWith(
                color: palette.ink,
                fontSize: 17,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MacroSummaryRow extends StatelessWidget {
  const _MacroSummaryRow({required this.summary});

  final DailySummary? summary;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final consumedNutrition = summary?.consumed ?? _emptyNutrition;
    final targetNutrition = summary?.target ?? _emptyNutrition;
    final hasConfiguredMacros = summary?.macroMode != null;
    return Row(
      children: [
        Expanded(
          child: _MacroSummaryPill(
            assetPath: 'assets/images/icons/carbs_icon.png',
            iconKey: const ValueKey('dashboard_macro_carbs_icon'),
            label: l10n.commonCarbs,
            value: hasConfiguredMacros
                ? _macroRatio(
                    consumedNutrition.carbsGrams,
                    targetNutrition.carbsGrams,
                  )
                : '',
            color: FreshColors.orange,
          ),
        ),
        const SizedBox(width: FreshSpacing.sm),
        Expanded(
          child: _MacroSummaryPill(
            assetPath: 'assets/images/icons/protein_icon.png',
            iconKey: const ValueKey('dashboard_macro_protein_icon'),
            label: l10n.localeName.startsWith('es') ? 'Proteínas' : 'Proteins',
            value: hasConfiguredMacros
                ? _macroRatio(
                    consumedNutrition.proteinGrams,
                    targetNutrition.proteinGrams,
                  )
                : '',
            color: FreshColors.mint,
          ),
        ),
        const SizedBox(width: FreshSpacing.sm),
        Expanded(
          child: _MacroSummaryPill(
            assetPath: 'assets/images/icons/fats_icon.png',
            iconKey: const ValueKey('dashboard_macro_fats_icon'),
            label: l10n.localeName.startsWith('es') ? 'Grasas' : 'Fats',
            value: hasConfiguredMacros
                ? _macroRatio(
                    consumedNutrition.fatGrams,
                    targetNutrition.fatGrams,
                  )
                : '',
            color: FreshColors.yellow,
          ),
        ),
      ],
    );
  }
}

class _MacroSummaryPill extends StatelessWidget {
  const _MacroSummaryPill({
    required this.assetPath,
    required this.iconKey,
    required this.label,
    required this.value,
    required this.color,
  });

  final String assetPath;
  final Key iconKey;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = context.freshPalette;
    return FreshCard(
      color: palette.surface,
      radius: FreshRadii.lg,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 42),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              clipBehavior: Clip.antiAlias,
              child: ClipOval(
                child: Image.asset(
                  assetPath,
                  key: iconKey,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  excludeFromSemantics: true,
                ),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelSmall?.copyWith(
                      color: palette.inkSoft,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (value.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        maxLines: 1,
                        style: textTheme.labelLarge?.copyWith(
                          color: palette.ink,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaterIntakeCard extends StatelessWidget {
  const _WaterIntakeCard({
    required this.summary,
    required this.enabled,
    required this.onUpdate,
  });

  final DailySummary? summary;
  final bool enabled;
  final Future<bool> Function(double waterConsumedLiters) onUpdate;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final consumed = roundHydrationLiters(summary?.waterConsumedLiters ?? 0);
    final goal = roundHydrationLiters(summary?.hydrationGoalLiters ?? 0);
    final canDecrease = enabled && consumed > 0;
    final canIncrease = enabled && goal > 0 && consumed < goal;
    return Container(
      key: const ValueKey('dashboard_water_intake_card'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: palette.water.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: palette.water.withValues(alpha: 0.16),
            blurRadius: 18,
            spreadRadius: 1,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: palette.ink.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          FreshIconChip(
            icon: Icons.water_drop_rounded,
            color: palette.water,
            backgroundColor: palette.water.withValues(alpha: 0.14),
            size: 48,
          ),
          const SizedBox(width: FreshSpacing.md),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.dashboardWaterIntake,
                  style: textTheme.titleMedium?.copyWith(
                    color: palette.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.dashboardWaterProgress(
                    formatHydrationLiters(consumed),
                    formatHydrationLiters(goal),
                  ),
                  key: const ValueKey('dashboard_water_progress'),
                  style: textTheme.bodyMedium?.copyWith(
                    color: palette.inkSoft,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: FreshSpacing.sm),
          _WaterStepButton(
            key: const ValueKey('dashboard_water_decrease_button'),
            icon: Icons.remove_rounded,
            tooltip: l10n.dashboardWaterDecreaseTooltip,
            enabled: canDecrease,
            onPressed: () {
              _setWater(consumed - 0.25, goal);
            },
          ),
          const SizedBox(width: FreshSpacing.sm),
          _WaterStepButton(
            key: const ValueKey('dashboard_water_increase_button'),
            icon: Icons.add_rounded,
            tooltip: l10n.dashboardWaterIncreaseTooltip,
            enabled: canIncrease,
            onPressed: () {
              _setWater(consumed + 0.25, goal);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _setWater(double next, double goal) async {
    final clamped = next.clamp(0, goal).toDouble();
    await onUpdate(roundHydrationLiters(clamped));
  }
}

class _WaterStepButton extends StatelessWidget {
  const _WaterStepButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final actionBlue = Theme.of(context).brightness == Brightness.dark
        ? palette.water
        : const Color(0xff0078c8);
    return SizedBox.square(
      dimension: 42,
      child: IconButton(
        tooltip: tooltip,
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 26),
        style: IconButton.styleFrom(
          backgroundColor: palette.water.withValues(alpha: 0.18),
          foregroundColor: actionBlue,
          disabledBackgroundColor: palette.water.withValues(alpha: 0.14),
          disabledForegroundColor: actionBlue.withValues(alpha: 0.62),
          shape: const CircleBorder(),
        ),
      ),
    );
  }
}

const _emptyNutrition = NutritionSnapshot(
  calories: 0,
  proteinGrams: 0,
  carbsGrams: 0,
  fatGrams: 0,
);

String _macroRatio(double consumed, double target) {
  return '${_formatMacro(consumed)}/${_formatMacro(target)}';
}

String _formatMacro(double value) {
  return value.round().toString();
}

class _MealSection extends StatelessWidget {
  const _MealSection({
    required this.summary,
    required this.onEditMeal,
    required this.onDeleteMeal,
  });

  final DailySummary? summary;
  final ValueChanged<Meal> onEditMeal;
  final ValueChanged<Meal> onDeleteMeal;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final meals = summary?.meals ?? const <Meal>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (meals.isEmpty)
          _DashboardEmptyMealsCard(
            title: l10n.dashboardNoMealsLoggedToday,
            message: l10n.dashboardNoMealsMessage,
          )
        else
          for (final meal in meals)
            Padding(
              padding: const EdgeInsets.only(bottom: FreshSpacing.md),
              child: _MealRow(
                meal: meal,
                onEdit: () => onEditMeal(meal),
                onDelete: () => onDeleteMeal(meal),
              ),
            ),
      ],
    );
  }
}

class _DashboardEmptyMealsCard extends StatelessWidget {
  const _DashboardEmptyMealsCard({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    final cardWidth =
        (MediaQuery.sizeOf(context).width - 40).clamp(0.0, 720.0).toDouble();
    return Align(
      alignment: Alignment.center,
      child: Container(
        width: cardWidth,
        padding: const EdgeInsets.symmetric(
          horizontal: FreshSpacing.xl,
          vertical: FreshSpacing.xxl,
        ),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(FreshRadii.xl),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1f080907),
              blurRadius: 30,
              offset: Offset(0, 16),
            ),
            BoxShadow(
              color: Color(0x0f080907),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            const FreshIconChip(
              icon: Icons.restaurant_menu_rounded,
              color: FreshColors.limeDeep,
            ),
            const SizedBox(height: FreshSpacing.md),
            Text(
              title,
              style: textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: FreshSpacing.sm),
            Text(
              message,
              style: textTheme.bodyMedium?.copyWith(color: palette.inkMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _MealRow extends StatelessWidget {
  const _MealRow({
    required this.meal,
    required this.onEdit,
    required this.onDelete,
  });

  final Meal meal;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = context.freshPalette;
    final l10n = context.l10n;
    return FreshCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (meal.mealLabel != null) ...[
                  _MealLabelChip(label: meal.mealLabel!),
                  const SizedBox(height: FreshSpacing.xs),
                ],
                Text(meal.title, style: textTheme.titleMedium),
                Text(
                  l10n.caloriesValue(meal.nutrition.calories),
                  style:
                      textTheme.bodyMedium?.copyWith(color: palette.inkMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: FreshSpacing.sm),
          FreshIconButton(
            key: ValueKey('dashboard_delete_meal_${meal.id}'),
            icon: Icons.delete_outline_rounded,
            tooltip: l10n.dashboardDeleteMealTooltip,
            foregroundColor: palette.coral,
            size: 42,
            onPressed: onDelete,
          ),
          const SizedBox(width: FreshSpacing.xs),
          FreshIconButton(
            key: ValueKey('dashboard_edit_meal_${meal.id}'),
            icon: Icons.edit_rounded,
            tooltip: l10n.dashboardEditIngredientsTooltip,
            size: 42,
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}

class _MealLabelChip extends StatelessWidget {
  const _MealLabelChip({required this.label});

  final MealLabel label;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = context.freshPalette;
    return Container(
      key: ValueKey('dashboard_meal_label_${label.type}_${label.label}'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: palette.limeWash,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        localizedMealLabel(context.l10n, label),
        style: textTheme.labelMedium?.copyWith(
          color: palette.limeDeep,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
