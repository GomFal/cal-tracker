import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/locale_view_model.dart';
import '../../../../app/performance_overlay_view_model.dart';
import '../../../../app/theme_mode_view_model.dart';
import '../../../../domain/models/macro_distribution.dart';
import '../../../../domain/models/nutrition_models.dart';
import '../../../../l10n/app_localizations_context.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/content_frame.dart';
import '../../../core/design_system.dart';
import '../../hydration/hydration_format.dart';
import '../../auth/view_models/auth_view_model.dart';
import '../../dashboard/view_models/dashboard_view_model.dart';
import '../../dashboard/views/calorie_target_sheet.dart';
import '../../dashboard/views/macro_distribution_sheet.dart';
import '../../meal_history/view_models/meal_history_view_model.dart';
import '../view_models/settings_view_model.dart';
import 'hydration_goal_sheet.dart';

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
    final themeMode = context.watch<ThemeModeViewModel>().themeMode;
    final performanceOverlay = context.watch<PerformanceOverlayViewModel>();
    final l10n = context.l10n;
    final palette = context.freshPalette;
    final user = auth.user;
    final goals = settings.goals;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final limeCardTextColor = isDark ? palette.ink : FreshPalette.dark.limeWash;
    return ContentFrame(
      title: l10n.settingsTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FreshCard(
            radius: FreshRadii.xl,
            color: palette.limeSoft,
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: palette.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.person_rounded,
                    color: palette.limeDeep,
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
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: limeCardTextColor,
                            ),
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
              color: palette.coral,
            ),
            const SizedBox(height: FreshSpacing.md),
          ],
          _SettingsGoalRow(
            key: const ValueKey('hydration_goal_row'),
            icon: Icons.water_drop_rounded,
            color: palette.water,
            title: l10n.settingsHydrationGoal,
            subtitle: l10n.settingsHydrationGoalSubtitle(
              formatHydrationLiters(goals?.hydrationGoalLiters ?? 0),
            ),
            onTap: settings.isLoading || settings.isSaving
                ? null
                : () => _showHydrationGoalSheet(context, goals: goals),
          ),
          const SizedBox(height: FreshSpacing.md),
          _SettingsGoalRow(
            key: const ValueKey('calorie_target_row'),
            icon: Icons.flag_rounded,
            color: palette.orange,
            title: l10n.settingsCalorieTarget,
            subtitle: goals?.calorieTargetConfigured == true
                ? l10n.settingsCalorieTargetSubtitle(
                    goals?.target.calories ?? 2200,
                  )
                : l10n.settingsNotSet,
            onTap: settings.isLoading || settings.isSaving
                ? null
                : () => _showCalorieTargetSheet(context, goals),
          ),
          const SizedBox(height: FreshSpacing.md),
          _SettingsGoalRow(
            key: const ValueKey('macro_distribution_row'),
            icon: Icons.pie_chart_rounded,
            color: palette.leaf,
            title: l10n.settingsMacroDistributionTitle,
            subtitle: _macroDistributionSubtitle(l10n, goals),
            onTap: settings.isLoading || settings.isSaving
                ? null
                : () => _showMacroDistributionEntry(context, goals),
          ),
          const SizedBox(height: FreshSpacing.md),
          _SettingsGoalRow(
            key: const ValueKey('language_settings_row'),
            icon: Icons.translate_rounded,
            color: palette.mint,
            title: l10n.settingsLanguageTitle,
            subtitle: _languageDisplayName(locale.locale),
            onTap: () => _showLanguageSheet(context),
          ),
          const SizedBox(height: FreshSpacing.md),
          _SettingsGoalRow(
            key: const ValueKey('theme_settings_row'),
            icon: Icons.contrast_rounded,
            color: palette.limeDeep,
            title: l10n.settingsThemeTitle,
            subtitle: _themeModeSubtitle(l10n, themeMode),
            onTap: () => _showThemeSheet(context),
          ),
          if (!kReleaseMode) ...[
            const SizedBox(height: FreshSpacing.md),
            _DeveloperSettingsCard(
              title: l10n.settingsDeveloperMenuTitle,
              performanceOverlayTitle: l10n.settingsPerformanceOverlayTitle,
              performanceOverlaySubtitle:
                  l10n.settingsPerformanceOverlaySubtitle,
              performanceOverlayStatus: performanceOverlay.visible
                  ? l10n.settingsPerformanceOverlayOn
                  : l10n.settingsPerformanceOverlayOff,
              performanceOverlayEnabled: performanceOverlay.visible,
              onPerformanceOverlayChanged: performanceOverlay.setVisible,
            ),
          ],
          const SizedBox(height: FreshSpacing.md),
          _DataSourcesCard(
            title: l10n.settingsDataSourcesTitle,
            subtitle: l10n.settingsDataSourcesSubtitle,
            openFoodFacts: l10n.settingsDataSourcesOpenFoodFacts,
            usda: l10n.settingsDataSourcesUsda,
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

  Future<void> _showHydrationGoalSheet(
    BuildContext context, {
    required DailyGoals? goals,
  }) async {
    final value = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) =>
          HydrationGoalSheet(initialLiters: goals?.hydrationGoalLiters ?? 0),
    );
    if (!context.mounted || value == null) return;
    final updated = await context.read<SettingsViewModel>().updateGoals(
          hydrationGoalLiters: value,
        );
    if (!context.mounted || updated == null) return;
    await _refreshGoalConsumers(context, forceDashboardRefresh: true);
  }

  Future<void> _showCalorieTargetSheet(
    BuildContext context,
    DailyGoals? goals,
  ) async {
    final selection = await showModalBottomSheet<CalorieTargetSelection>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => CalorieTargetSheet(
        initialValue: goals?.target.calories ?? 2200,
        estimateCalories: context.read<DashboardViewModel>().estimateCalories,
      ),
    );
    if (!context.mounted || selection == null) return;
    final updated = await context.read<SettingsViewModel>().updateGoals(
          calories: selection.calories,
          calorieTargetSource: selection.source,
          macroConfig: selection.macroConfig,
          macroCalorieTarget: selection.calories,
        );
    if (!context.mounted || updated == null) return;
    await _refreshGoalConsumers(context, forceDashboardRefresh: true);
    if (!context.mounted ||
        selection.source != 'manual' ||
        selection.macroConfig != null) {
      return;
    }
    final shouldConfigure = await showModalBottomSheet<bool>(
          context: context,
          useSafeArea: true,
          builder: (context) =>
              PostCalorieSaveMacroPrompt(calories: selection.calories),
        ) ??
        false;
    if (!context.mounted || !shouldConfigure) return;
    await _showMacroDistributionSheet(
      context,
      updated,
      caloriesOverride: selection.calories,
    );
  }

  Future<void> _showMacroDistributionEntry(
    BuildContext context,
    DailyGoals? goals,
  ) async {
    if (goals?.calorieTargetConfigured == true) {
      await _showMacroDistributionSheet(context, goals);
      return;
    }
    final shouldSetCalories = await showModalBottomSheet<bool>(
          context: context,
          useSafeArea: true,
          builder: (context) => const _MacroRequiresCaloriesSheet(),
        ) ??
        false;
    if (!context.mounted || !shouldSetCalories) return;
    await _showCalorieTargetSheet(context, goals);
  }

  Future<void> _showMacroDistributionSheet(
    BuildContext context,
    DailyGoals? goals, {
    int? caloriesOverride,
  }) async {
    final calories = caloriesOverride ?? goals?.target.calories ?? 2200;
    final macroConfig = await showModalBottomSheet<MacroDistributionConfig>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) =>
          MacroDistributionSheet(calories: calories, initialGoals: goals),
    );
    if (!context.mounted || macroConfig == null) return;
    final updated = await context.read<SettingsViewModel>().updateGoals(
          macroConfig: macroConfig,
          macroCalorieTarget: calories,
        );
    if (!context.mounted || updated == null) return;
    await _refreshGoalConsumers(context, forceDashboardRefresh: true);
  }

  Future<void> _refreshGoalConsumers(
    BuildContext context, {
    bool forceDashboardRefresh = false,
  }) {
    return Future.wait([
      context.read<DashboardViewModel>().load(
            forceRefresh: forceDashboardRefresh,
          ),
      context.read<SettingsViewModel>().load(),
      context.read<MealHistoryViewModel>().load(),
    ]);
  }

  String _macroDistributionSubtitle(AppLocalizations l10n, DailyGoals? goals) {
    if (goals?.calorieTargetConfigured != true || goals?.macroMode == null) {
      return l10n.settingsNotSet;
    }
    final preset = goals!.macroPreset;
    if (preset != null) {
      return l10n.settingsMacroPresetSubtitle(
        _macroPresetLabel(l10n, preset),
        preset.proteinPct,
        preset.carbsPct,
        preset.fatPct,
      );
    }
    if (goals.macroMode == MacroMode.percentage &&
        goals.proteinPct != null &&
        goals.carbsPct != null &&
        goals.fatPct != null) {
      return l10n.settingsMacroPercentSubtitle(
        goals.proteinPct!,
        goals.carbsPct!,
        goals.fatPct!,
      );
    }
    return l10n.settingsMacroGramsSubtitle(
      goals.target.proteinGrams.round(),
      goals.target.carbsGrams.round(),
      goals.target.fatGrams.round(),
    );
  }

  String _macroPresetLabel(AppLocalizations l10n, MacroPreset preset) {
    return switch (preset) {
      MacroPreset.balanced => l10n.macroPresetBalanced,
      MacroPreset.highProtein => l10n.macroPresetHighProtein,
      MacroPreset.lowerCarb => l10n.macroPresetLowerCarb,
    };
  }

  String _themeModeSubtitle(AppLocalizations l10n, ThemeMode themeMode) {
    return switch (themeMode) {
      ThemeMode.system => l10n.settingsThemeSystem,
      ThemeMode.light => l10n.settingsThemeLight,
      ThemeMode.dark => l10n.settingsThemeDark,
    };
  }

  Future<void> _showThemeSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) {
        final l10n = sheetContext.l10n;
        final themeModeViewModel = sheetContext.watch<ThemeModeViewModel>();
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
                l10n.settingsThemeSheetTitle,
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: FreshSpacing.md),
              _SettingsOption(
                key: const ValueKey('theme_option_system'),
                title: l10n.settingsThemeSystem,
                selected: themeModeViewModel.themeMode == ThemeMode.system,
                onTap: () async {
                  await themeModeViewModel.setThemeMode(ThemeMode.system);
                  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                },
              ),
              const SizedBox(height: FreshSpacing.sm),
              _SettingsOption(
                key: const ValueKey('theme_option_light'),
                title: l10n.settingsThemeLight,
                selected: themeModeViewModel.themeMode == ThemeMode.light,
                onTap: () async {
                  await themeModeViewModel.setThemeMode(ThemeMode.light);
                  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                },
              ),
              const SizedBox(height: FreshSpacing.sm),
              _SettingsOption(
                key: const ValueKey('theme_option_dark'),
                title: l10n.settingsThemeDark,
                selected: themeModeViewModel.themeMode == ThemeMode.dark,
                onTap: () async {
                  await themeModeViewModel.setThemeMode(ThemeMode.dark);
                  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                },
              ),
            ],
          ),
        );
      },
    );
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
              for (final locale in AppLocalizations.supportedLocales) ...[
                _SettingsOption(
                  key: ValueKey('language_option_${locale.toLanguageTag()}'),
                  title: _languageDisplayName(locale),
                  selected: localeViewModel.locale == locale,
                  onTap: () async {
                    await localeViewModel.setLocaleTag(locale.toLanguageTag());
                    if (sheetContext.mounted) {
                      Navigator.of(sheetContext).pop();
                    }
                  },
                ),
                if (locale != AppLocalizations.supportedLocales.last)
                  const SizedBox(height: FreshSpacing.sm),
              ],
            ],
          ),
        );
      },
    );
  }

  String _languageDisplayName(Locale locale) {
    return lookupAppLocalizations(locale).settingsLanguageNativeName;
  }
}

class _DeveloperSettingsCard extends StatelessWidget {
  const _DeveloperSettingsCard({
    required this.title,
    required this.performanceOverlayTitle,
    required this.performanceOverlaySubtitle,
    required this.performanceOverlayStatus,
    required this.performanceOverlayEnabled,
    required this.onPerformanceOverlayChanged,
  });

  final String title;
  final String performanceOverlayTitle;
  final String performanceOverlaySubtitle;
  final String performanceOverlayStatus;
  final bool performanceOverlayEnabled;
  final ValueChanged<bool> onPerformanceOverlayChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    return FreshCard(
      padding: const EdgeInsets.all(16),
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              FreshIconChip(
                icon: Icons.developer_mode_rounded,
                color: palette.mint,
              ),
              const SizedBox(width: FreshSpacing.md),
              Expanded(child: Text(title, style: textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: FreshSpacing.sm),
          SwitchListTile.adaptive(
            key: const ValueKey('settings_performance_overlay_switch'),
            contentPadding: EdgeInsets.zero,
            title: Text(performanceOverlayTitle),
            subtitle: Text(
              '$performanceOverlaySubtitle\n$performanceOverlayStatus',
            ),
            value: performanceOverlayEnabled,
            onChanged: onPerformanceOverlayChanged,
          ),
        ],
      ),
    );
  }
}

class _DataSourcesCard extends StatelessWidget {
  const _DataSourcesCard({
    required this.title,
    required this.subtitle,
    required this.openFoodFacts,
    required this.usda,
  });

  final String title;
  final String subtitle;
  final String openFoodFacts;
  final String usda;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    return FreshCard(
      padding: const EdgeInsets.all(16),
      shadow: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FreshIconChip(icon: Icons.source_rounded, color: palette.orange),
          const SizedBox(width: FreshSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: textTheme.bodyMedium?.copyWith(
                    color: palette.inkMuted,
                  ),
                ),
                const SizedBox(height: FreshSpacing.sm),
                Text(
                  openFoodFacts,
                  style: textTheme.bodySmall?.copyWith(color: palette.inkMuted),
                ),
                const SizedBox(height: 4),
                Text(
                  usda,
                  style: textTheme.bodySmall?.copyWith(color: palette.inkMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsOption extends StatelessWidget {
  const _SettingsOption({
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

class _MacroRequiresCaloriesSheet extends StatelessWidget {
  const _MacroRequiresCaloriesSheet();

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;
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
                color: palette.rule,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: FreshSpacing.lg),
          Text(
            l10n.settingsMacroRequiresCaloriesTitle,
            style: textTheme.titleLarge?.copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: FreshSpacing.xs),
          Text(
            l10n.settingsMacroRequiresCaloriesMessage,
            style: textTheme.bodyMedium?.copyWith(color: palette.inkMuted),
          ),
          const SizedBox(height: FreshSpacing.lg),
          FilledButton(
            key: const ValueKey('macro_requires_calories_set_now'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.settingsMacroRequiresCaloriesSetNow),
          ),
          const SizedBox(height: FreshSpacing.sm),
          TextButton(
            key: const ValueKey('macro_requires_calories_skip'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.settingsMacroRequiresCaloriesSkip),
          ),
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
    final palette = context.freshPalette;
    return FreshCard(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Row(
        children: [
          FreshIconChip(icon: icon, color: color),
          const SizedBox(width: FreshSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                Text(
                  subtitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: palette.inkMuted),
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
