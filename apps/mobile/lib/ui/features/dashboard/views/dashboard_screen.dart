import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../domain/models/macro_distribution.dart';
import '../../../../domain/models/nutrition_models.dart';
import '../../../../l10n/app_localizations_context.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/meal_label_localizations.dart';
import '../../../core/content_frame.dart';
import '../../../core/design_system.dart';
import '../../../core/motion.dart';
import '../../../shared/meal_item_editor_sheet.dart';
import '../../auth/view_models/auth_view_model.dart';
import '../../hydration/hydration_format.dart';
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
    final palette = context.freshPalette;
    final summary = viewModel.summary;
    final showNoDataError =
        summary == null && viewModel.error != null && !viewModel.isLoading;
    final displayName = user?.displayName.trim().isNotEmpty == true
        ? user!.displayName
        : l10n.fallbackUserName;
    return ContentFrame(
      title: displayName,
      subtitle: l10n.dashboardGreeting,
      leading: const _Avatar(),
      actions: [
        _DashboardDatePill(label: dashboardDayMonthLabel(DateTime.now(), l10n)),
      ],
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
              color: palette.coral,
              action: TextButton.icon(
                onPressed: () => viewModel.load(forceRefresh: true),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(l10n.commonTryAgain),
              ),
            ),
            const SizedBox(height: FreshSpacing.md),
          ],
          if (!showNoDataError) ...[
            _HeroCalorieSection(
              summary: summary,
              onSetup: () => _showCalorieTargetSheet(context, viewModel),
            ),
            const SizedBox(height: FreshSpacing.lg),
            _MacroSection(summary: summary),
            const SizedBox(height: FreshSpacing.lg),
            _WaterSection(
              summary: summary,
              enabled: !viewModel.isLoading,
              onUpdate: viewModel.updateDailyWater,
            ),
            const SizedBox(height: FreshSpacing.lg),
            _MealSection(
              summary: summary,
              onEditMeal: (meal) =>
                  _showMealItemEditor(context, viewModel, meal),
            ),
            const SizedBox(height: FreshSpacing.lg),
          ],
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
      sheetAnimationStyle: freshSheetAnimationStyle(context),
      builder: (context) => MealItemEditorSheet(
        meal: meal,
        keyPrefix: 'dashboard',
        searchFoods: viewModel.searchFoods,
        onDeleteMeal: () => _confirmDeleteMeal(context, viewModel, meal),
      ),
    );
    if (!context.mounted || items == null) return;
    await viewModel.correctMealItems(meal, items);
  }

  Future<bool> _confirmDeleteMeal(
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
    if (!context.mounted || confirmed != true) return false;

    final deleted = await viewModel.deleteMeal(meal);
    if (!context.mounted) return false;
    if (!deleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.dashboardCouldNotDeleteMeal)),
      );
      return false;
    }
    return true;
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
      sheetAnimationStyle: freshSheetAnimationStyle(context),
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
        SnackBar(content: Text(context.l10n.calorieCouldNotSaveCalories)),
      );
      return;
    }
    if (!context.mounted ||
        selection.source != 'manual' ||
        selection.macroConfig != null) {
      return;
    }
    final shouldConfigure = await showModalBottomSheet<bool>(
          context: context,
          useSafeArea: true,
          sheetAnimationStyle: freshSheetAnimationStyle(context),
          builder: (context) =>
              PostCalorieSaveMacroPrompt(calories: selection.calories),
        ) ??
        false;
    if (!context.mounted || !shouldConfigure) return;
    final macroConfig = await showModalBottomSheet<MacroDistributionConfig>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      sheetAnimationStyle: freshSheetAnimationStyle(context),
      builder: (context) =>
          MacroDistributionSheet(calories: selection.calories),
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
        SnackBar(content: Text(context.l10n.calorieCouldNotSaveMacros)),
      );
      return;
    }
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar();

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: palette.surfaceSoft,
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.person_rounded, color: palette.lime, size: 20),
    );
  }
}

class _DashboardDatePill extends StatelessWidget {
  const _DashboardDatePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.calendar_today_outlined, color: palette.inkMuted, size: 16),
        const SizedBox(width: 6),
        Text(
          label,
          style: textTheme.bodyMedium?.copyWith(
            color: palette.inkSoft,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _HeroCalorieSection extends StatelessWidget {
  const _HeroCalorieSection({required this.summary, required this.onSetup});

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
      return _CalorieSetupHero(onTap: onSetup);
    }
    final remaining = (summary?.remaining.calories ?? target - consumed)
        .clamp(0, target)
        .toInt();
    final progress =
        target <= 0 ? 0.0 : (consumed / target).clamp(0, 1).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      key: const ValueKey('dashboard_progress_card'),
      children: [
        Text(
          l10n.commonCalories.toUpperCase(),
          style: textTheme.labelMedium?.copyWith(
            color: palette.inkMuted,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: FreshSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$remaining',
                    key: const ValueKey('dashboard_remaining_calories'),
                    style: textTheme.displayLarge?.copyWith(
                      fontSize: 42,
                      height: 0.95,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: palette.lime,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${l10n.commonKcal} ${l10n.dashboardCaloriesLeft}',
                    style: textTheme.bodyLarge?.copyWith(
                      color: palette.ink,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _consumedTargetMeta(l10n, consumed, target),
                    style: textTheme.bodyMedium?.copyWith(
                      color: palette.inkMuted,
                      fontWeight: FontWeight.w400,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: FreshSpacing.md),
            FreshProgressRing(
              progress: progress,
              size: 116,
              strokeWidth: 11.5,
              trackColor: palette.rule,
              color: palette.lime,
              center: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${(progress * 100).round()}%',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: palette.ink,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    l10n.dashboardOfGoal,
                    style: textTheme.bodySmall?.copyWith(
                      color: palette.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _consumedTargetMeta(AppLocalizations l10n, int consumed, int target) {
    return '${l10n.commonConsumed} $consumed · ${l10n.settingsCalorieTarget} $target';
  }
}

class _CalorieSetupHero extends StatelessWidget {
  const _CalorieSetupHero({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FreshRadii.lg),
        key: const ValueKey('dashboard_progress_card'),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: FreshSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.calorieSetupHeadlinePrefix,
                style: textTheme.headlineMedium?.copyWith(
                  color: palette.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: FreshSpacing.xs),
              Text(
                l10n.calorieSetupHeadlineMain,
                style: textTheme.headlineMedium?.copyWith(
                  color: palette.lime,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: FreshSpacing.sm),
              Text(
                l10n.calorieSetupHeadlineBadge,
                style: textTheme.bodyLarge?.copyWith(
                  color: palette.inkMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MacroSection extends StatelessWidget {
  const _MacroSection({required this.summary});

  final DailySummary? summary;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final consumed = summary?.consumed ?? _emptyNutrition;
    final target = summary?.target ?? _emptyNutrition;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.usualFoodsMacrosSectionTitle.toUpperCase(),
              style: textTheme.labelMedium?.copyWith(
                color: palette.inkMuted,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(width: FreshSpacing.sm),
            Expanded(
              child: Divider(color: palette.rule, height: 1, thickness: 1),
            ),
          ],
        ),
        const SizedBox(height: FreshSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _MacroProgressRow(
                assetPath: 'assets/images/icons/svg/carbs_icon.svg',
                iconKey: const ValueKey('dashboard_macro_carbs_icon'),
                label: l10n.commonCarbs,
                consumedGrams: consumed.carbsGrams,
                targetGrams: target.carbsGrams,
                iconSize: 36,
              ),
            ),
            _VerticalRule(color: palette.rule),
            Expanded(
              child: _MacroProgressRow(
                assetPath: 'assets/images/icons/svg/protein_icon.svg',
                iconKey: const ValueKey('dashboard_macro_protein_icon'),
                label: l10n.commonProtein,
                consumedGrams: consumed.proteinGrams,
                targetGrams: target.proteinGrams,
                iconSize: 34,
              ),
            ),
            _VerticalRule(color: palette.rule),
            Expanded(
              child: _MacroProgressRow(
                assetPath: 'assets/images/icons/svg/fats_icon.svg',
                iconKey: const ValueKey('dashboard_macro_fats_icon'),
                label: l10n.commonFat,
                consumedGrams: consumed.fatGrams,
                targetGrams: target.fatGrams,
                iconSize: 40,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _VerticalRule extends StatelessWidget {
  const _VerticalRule({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 88,
      margin: const EdgeInsets.symmetric(horizontal: FreshSpacing.sm),
      color: color,
    );
  }
}

class _MacroProgressRow extends StatelessWidget {
  const _MacroProgressRow({
    required this.assetPath,
    required this.iconKey,
    required this.label,
    required this.consumedGrams,
    required this.targetGrams,
    required this.iconSize,
  });

  final String assetPath;
  final Key iconKey;
  final String label;
  final double consumedGrams;
  final double targetGrams;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = context.freshPalette;
    final progress = targetGrams <= 0
        ? 0.0
        : (consumedGrams / targetGrams).clamp(0, 1).toDouble();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FreshSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SvgPicture.asset(
            assetPath,
            key: iconKey,
            width: iconSize,
            height: iconSize,
            colorFilter: ColorFilter.mode(palette.lime, BlendMode.srcIn),
          ),
          const SizedBox(height: FreshSpacing.sm),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyMedium?.copyWith(
              color: palette.inkSoft,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: FreshSpacing.xs),
          RichText(
            text: TextSpan(
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              children: [
                TextSpan(
                  text: _formatMacro(consumedGrams),
                  style: TextStyle(color: palette.lime),
                ),
                TextSpan(
                  text: ' / ${_formatMacro(targetGrams)} g',
                  style: TextStyle(color: palette.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(height: FreshSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: palette.rule,
              valueColor: AlwaysStoppedAnimation(palette.lime),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: FreshSpacing.xs),
          Text(
            '${(progress * 100).round()}%',
            style: textTheme.bodySmall?.copyWith(
              color: palette.inkMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _WaterSection extends StatelessWidget {
  const _WaterSection({
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

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.dashboardWaterIntake.toUpperCase(),
              style: textTheme.labelMedium?.copyWith(
                color: palette.inkMuted,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(width: FreshSpacing.sm),
            Expanded(
              child: Divider(color: palette.rule, height: 1, thickness: 1),
            ),
          ],
        ),
        const SizedBox(height: FreshSpacing.md),
        Row(
          children: [
            Icon(Icons.water_drop_outlined, color: palette.lime, size: 22),
            const SizedBox(width: FreshSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.commonWater,
                    style: textTheme.bodyMedium?.copyWith(
                      color: palette.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    l10n.dashboardWaterProgress(
                      formatHydrationLiters(consumed),
                      formatHydrationLiters(goal),
                    ),
                    key: const ValueKey('dashboard_water_progress'),
                    style: textTheme.bodyLarge?.copyWith(
                      color: palette.lime,
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
      ],
    );

    if (Theme.of(context).brightness == Brightness.dark) {
      return content;
    }

    return KeyedSubtree(
      key: const ValueKey('dashboard_water_intake_card'),
      child: content,
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
    return SizedBox.square(
      dimension: 34,
      child: IconButton(
        tooltip: tooltip,
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 18),
        style: IconButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: enabled ? palette.lime : palette.inkMuted,
          disabledBackgroundColor: Colors.transparent,
          disabledForegroundColor: palette.inkMuted,
          shape: const CircleBorder(),
          side: BorderSide(
            color: enabled ? palette.rule : palette.ruleSoft,
            width: 1.5,
          ),
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

String _formatMacro(double value) {
  return value.round().toString();
}

class _MealSection extends StatelessWidget {
  const _MealSection({required this.summary, required this.onEditMeal});

  final DailySummary? summary;
  final ValueChanged<Meal> onEditMeal;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = context.freshPalette;
    final l10n = context.l10n;
    final meals = summary?.meals ?? const <Meal>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.commonMeals.toUpperCase(),
              style: textTheme.labelMedium?.copyWith(
                color: palette.inkMuted,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(width: FreshSpacing.sm),
            Expanded(
              child: Divider(color: palette.rule, height: 1, thickness: 1),
            ),
          ],
        ),
        const SizedBox(height: FreshSpacing.md),
        if (meals.isEmpty)
          const _DashboardEmptyMealsCard()
        else
          for (final meal in meals)
            Padding(
              padding: const EdgeInsets.only(bottom: FreshSpacing.md),
              child: _MealRow(meal: meal, onEdit: () => onEditMeal(meal)),
            ),
      ],
    );
  }
}

class _DashboardEmptyMealsCard extends StatelessWidget {
  const _DashboardEmptyMealsCard();

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.room_service_outlined, size: 48, color: palette.inkMuted),
          const SizedBox(height: FreshSpacing.md),
          Text(
            l10n.dashboardNoMealsLoggedToday,
            textAlign: TextAlign.center,
            style: textTheme.titleMedium?.copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: FreshSpacing.xs),
          Text(
            l10n.dashboardNoMealsMessage,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: palette.inkMuted),
          ),
          const SizedBox(height: FreshSpacing.md),
          TextButton.icon(
            onPressed: () {
              try {
                context.push('/meal/create');
              } catch (_) {}
            },
            icon: Icon(Icons.add_rounded, size: 18, color: palette.lime),
            label: Text('${l10n.foodSearchAddAction} ${l10n.commonMeal}'),
            style: TextButton.styleFrom(
              foregroundColor: palette.lime,
              textStyle: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MealRow extends StatelessWidget {
  const _MealRow({required this.meal, required this.onEdit});

  final Meal meal;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = context.freshPalette;
    final l10n = context.l10n;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('dashboard_meal_row_${meal.id}'),
        onTap: onEdit,
        borderRadius: BorderRadius.circular(FreshRadii.sm),
        child: Ink(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: palette.rule, width: 1)),
          ),
          padding: const EdgeInsets.symmetric(vertical: FreshSpacing.md),
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
                    Text(
                      meal.title,
                      style: textTheme.bodyLarge?.copyWith(
                        color: palette.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: FreshSpacing.sm),
              Text(
                l10n.caloriesValue(meal.nutrition.calories),
                style: textTheme.bodyMedium?.copyWith(
                  color: palette.ink,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: FreshSpacing.sm),
              Icon(
                Icons.chevron_right_rounded,
                color: palette.inkMuted,
                size: 22,
              ),
            ],
          ),
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: palette.surfaceSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        localizedMealLabel(context.l10n, label),
        style: textTheme.labelSmall?.copyWith(
          color: palette.lime,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
