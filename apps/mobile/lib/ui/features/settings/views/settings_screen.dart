import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/locale_view_model.dart';
import '../../../../domain/models/macro_distribution.dart';
import '../../../../domain/models/nutrition_models.dart';
import '../../../../l10n/app_localizations_context.dart';
import '../../../core/content_frame.dart';
import '../../../core/design_system.dart';
import '../../auth/view_models/auth_view_model.dart';
import '../../dashboard/view_models/dashboard_view_model.dart';
import '../../dashboard/views/macro_distribution_sheet.dart';
import '../../meal_history/view_models/meal_history_view_model.dart';
import '../view_models/settings_view_model.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<SettingsViewModel>().load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthViewModel>();
    final settings = context.watch<SettingsViewModel>();
    final locale = context.watch<LocaleViewModel>();
    final l10n = context.l10n;
    final user = auth.user;
    final goals = settings.goals;
    final limeCardTextColor = FreshPalette.dark.limeWash;
    return ContentFrame(
      title: l10n.settingsTitle,
      subtitle: l10n.settingsSubtitle,
      actions: [
        FreshIconButton(
          icon: Icons.more_horiz_rounded,
          tooltip: l10n.settingsMoreTooltip,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FreshCard(
            radius: FreshRadii.xl,
            color: FreshColors.limeSoft,
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: const BoxDecoration(
                    color: FreshColors.surface,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: FreshColors.limeDeep,
                    size: 30,
                  ),
                ),
                const SizedBox(width: FreshSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.displayName ?? l10n.fallbackUserName,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(color: limeCardTextColor),
                      ),
                      if (user != null)
                        Text(
                          user.email,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: limeCardTextColor),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: FreshSpacing.lg),
          if (settings.isLoading) ...[
            const LinearProgressIndicator(minHeight: 3),
            const SizedBox(height: FreshSpacing.md),
          ],
          if (settings.error != null) ...[
            FreshStatusBanner(
              icon: Icons.error_outline_rounded,
              title: l10n.settingsCouldNotUpdateGoals,
              message: settings.error!,
              color: FreshColors.coral,
            ),
            const SizedBox(height: FreshSpacing.md),
          ],
          _SettingsGoalRow(
            key: const ValueKey('hydration_goal_row'),
            icon: Icons.water_drop_rounded,
            color: FreshColors.water,
            title: l10n.settingsHydrationGoal,
            subtitle: l10n.settingsHydrationGoalSubtitle(
              goals?.hydrationGoalGlasses ?? 12,
            ),
            onTap: settings.isLoading
                ? null
                : () => _editGoal(
                      context,
                      title: l10n.settingsHydrationGoal,
                      fieldKey: const ValueKey('hydration_goal_field'),
                      initialValue: goals?.hydrationGoalGlasses ?? 12,
                      unit: l10n.settingsGlassesUnit,
                      minValue: 1,
                      maxValue: 40,
                      onSave: (value) => context
                          .read<SettingsViewModel>()
                          .updateGoals(hydrationGoalGlasses: value),
                    ),
          ),
          const SizedBox(height: FreshSpacing.md),
          _SettingsGoalRow(
            key: const ValueKey('calorie_target_row'),
            icon: Icons.flag_rounded,
            color: FreshColors.orange,
            title: l10n.settingsCalorieTarget,
            subtitle: l10n.settingsCalorieTargetSubtitle(
              goals?.target.calories ?? 2200,
            ),
            onTap: settings.isLoading
                ? null
                : () => _editGoal(
                      context,
                      title: l10n.settingsCalorieTarget,
                      fieldKey: const ValueKey('calorie_target_field'),
                      initialValue: goals?.target.calories ?? 2200,
                      unit: l10n.commonKcal,
                      minValue: 800,
                      maxValue: 10000,
                      onSave: (value) => context
                          .read<SettingsViewModel>()
                          .updateGoals(calories: value),
                    ),
          ),
          const SizedBox(height: FreshSpacing.md),
          _SettingsGoalRow(
            key: const ValueKey('macro_distribution_row'),
            icon: Icons.pie_chart_rounded,
            color: FreshColors.leaf,
            title: 'Macro distribution',
            subtitle: _macroDistributionSubtitle(goals),
            onTap: settings.isLoading
                ? null
                : () => _showMacroDistributionSheet(context, goals),
          ),
          const SizedBox(height: FreshSpacing.md),
          _SettingsGoalRow(
            key: const ValueKey('language_settings_row'),
            icon: Icons.translate_rounded,
            color: FreshColors.mint,
            title: l10n.settingsLanguageTitle,
            subtitle: locale.localeCode == 'es'
                ? l10n.settingsLanguageSubtitleSpanish
                : l10n.settingsLanguageSubtitleEnglish,
            onTap: () => _showLanguageSheet(context),
          ),
          const SizedBox(height: FreshSpacing.xl),
          OutlinedButton.icon(
            onPressed: auth.logout,
            icon: const Icon(Icons.logout_rounded),
            label: Text(l10n.settingsLogOut),
          ),
        ],
      ),
    );
  }

  Future<void> _editGoal(
    BuildContext context, {
    required String title,
    required ValueKey<String> fieldKey,
    required int initialValue,
    required String unit,
    required int minValue,
    required int maxValue,
    required Future<Object?> Function(int value) onSave,
  }) async {
    final value = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _GoalEditSheet(
        title: title,
        fieldKey: fieldKey,
        initialValue: initialValue,
        unit: unit,
        minValue: minValue,
        maxValue: maxValue,
      ),
    );
    if (!context.mounted || value == null) return;
    final updated = await onSave(value);
    if (!context.mounted || updated == null) return;
    await Future.wait([
      context.read<DashboardViewModel>().load(),
      context.read<MealHistoryViewModel>().load(),
    ]);
  }

  Future<void> _showMacroDistributionSheet(
    BuildContext context,
    DailyGoals? goals,
  ) async {
    final calories = goals?.target.calories ?? 2200;
    final macroConfig = await showModalBottomSheet<MacroDistributionConfig>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => MacroDistributionSheet(
        calories: calories,
        initialGoals: goals,
      ),
    );
    if (!context.mounted || macroConfig == null) return;
    final updated = await context.read<SettingsViewModel>().updateGoals(
          macroConfig: macroConfig,
          macroCalorieTarget: calories,
        );
    if (!context.mounted || updated == null) return;
    await Future.wait([
      context.read<DashboardViewModel>().load(forceRefresh: true),
      context.read<SettingsViewModel>().load(),
      context.read<MealHistoryViewModel>().load(),
    ]);
  }

  String _macroDistributionSubtitle(DailyGoals? goals) {
    if (goals?.macroMode == null) return 'Not set';
    final preset = goals!.macroPreset;
    if (preset != null) {
      return '${preset.label}: ${preset.proteinPct}% protein, ${preset.carbsPct}% carbs, ${preset.fatPct}% fat';
    }
    if (goals.macroMode == MacroMode.percentage &&
        goals.proteinPct != null &&
        goals.carbsPct != null &&
        goals.fatPct != null) {
      return '${goals.proteinPct}% protein, ${goals.carbsPct}% carbs, ${goals.fatPct}% fat';
    }
    return '${goals.target.proteinGrams.round()}g protein, ${goals.target.carbsGrams.round()}g carbs, ${goals.target.fatGrams.round()}g fat';
  }

  Future<void> _showLanguageSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) {
        final l10n = sheetContext.l10n;
        final localeViewModel = sheetContext.watch<LocaleViewModel>();
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: sheetContext.freshPalette.rule,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: FreshSpacing.lg),
              Text(
                l10n.settingsLanguageSheetTitle,
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: FreshSpacing.md),
              _LanguageOption(
                key: const ValueKey('language_option_en'),
                title: l10n.settingsLanguageEnglish,
                selected: localeViewModel.localeCode == 'en',
                onTap: () async {
                  await localeViewModel.setLocaleCode('en');
                  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                },
              ),
              const SizedBox(height: FreshSpacing.sm),
              _LanguageOption(
                key: const ValueKey('language_option_es'),
                title: l10n.settingsLanguageSpanish,
                selected: localeViewModel.localeCode == 'es',
                onTap: () async {
                  await localeViewModel.setLocaleCode('es');
                  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FreshCard(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      shadow: false,
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          if (selected)
            Icon(Icons.check_rounded, color: context.freshPalette.limeDeep),
        ],
      ),
    );
  }
}

class _SettingsGoalRow extends StatelessWidget {
  const _SettingsGoalRow({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FreshCard(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Row(
        children: [
          FreshIconChip(
            icon: icon,
            color: color,
          ),
          const SizedBox(width: FreshSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                Text(
                  subtitle,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: FreshColors.inkMuted),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

class _GoalEditSheet extends StatefulWidget {
  const _GoalEditSheet({
    required this.title,
    required this.fieldKey,
    required this.initialValue,
    required this.unit,
    required this.minValue,
    required this.maxValue,
  });

  final String title;
  final ValueKey<String> fieldKey;
  final int initialValue;
  final String unit;
  final int minValue;
  final int maxValue;

  @override
  State<_GoalEditSheet> createState() => _GoalEditSheetState();
}

class _GoalEditSheetState extends State<_GoalEditSheet> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottomInset + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: context.freshPalette.rule,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: FreshSpacing.lg),
          Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: FreshSpacing.md),
          TextField(
            key: widget.fieldKey,
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: widget.unit,
              errorText: _error,
            ),
          ),
          const SizedBox(height: FreshSpacing.lg),
          FilledButton(
            key: const ValueKey('save_goal_button'),
            onPressed: _submit,
            child: Text(context.l10n.commonSave),
          ),
        ],
      ),
    );
  }

  void _submit() {
    final value = int.tryParse(_controller.text.trim());
    if (value == null || value < widget.minValue || value > widget.maxValue) {
      setState(() {
        _error = context.l10n.settingsGoalRangeError(
          widget.minValue,
          widget.maxValue,
        );
      });
      return;
    }
    Navigator.of(context).pop(value);
  }
}
