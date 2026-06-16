import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../domain/models/macro_distribution.dart';
import '../../../../domain/models/nutrition_models.dart';
import '../../../../l10n/app_localizations_context.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/design_system.dart';

class MacroDistributionSheet extends StatefulWidget {
  const MacroDistributionSheet({
    super.key,
    required this.calories,
    this.initialGoals,
    this.presetOnly = false,
    this.title,
  });

  final int calories;
  final DailyGoals? initialGoals;
  final bool presetOnly;
  final String? title;

  @override
  State<MacroDistributionSheet> createState() => _MacroDistributionSheetState();
}

class _MacroDistributionSheetState extends State<MacroDistributionSheet> {
  late MacroPreset? _selectedPreset;
  MacroDistributionConfig? _personalizedConfig;

  @override
  void initState() {
    super.initState();
    final goals = widget.initialGoals;
    if (widget.presetOnly) {
      _selectedPreset = MacroPreset.balanced;
      return;
    }
    _selectedPreset = goals?.macroPreset ?? MacroPreset.balanced;
    if (goals?.macroMode == MacroMode.grams ||
        (goals?.macroSource == MacroSource.custom &&
            goals?.macroPreset == null)) {
      _selectedPreset = null;
      _personalizedConfig = _configFromGoals(goals!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Material(
      color: palette.screen,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, bottomInset + 20),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.9,
          child: Column(
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
                widget.title ?? l10n.macroSheetTitle,
                style: textTheme.titleLarge?.copyWith(
                  color: palette.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: FreshSpacing.xs),
              Text(
                l10n.macroDailyTarget(widget.calories),
                style: textTheme.bodyMedium?.copyWith(
                  color: palette.inkMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: FreshSpacing.lg),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final preset in MacroPreset.values)
                        Padding(
                          padding:
                              const EdgeInsets.only(bottom: FreshSpacing.md),
                          child: MacroPresetCard(
                            key: ValueKey('macro_preset_${preset.apiValue}'),
                            preset: preset,
                            calories: widget.calories,
                            mode: MacroMode.percentage,
                            selected: _selectedPreset == preset,
                            onTap: () => _selectPreset(preset),
                          ),
                        ),
                      if (!widget.presetOnly) ...[
                        Padding(
                          padding:
                              const EdgeInsets.only(bottom: FreshSpacing.md),
                          child: _PersonalizedMacroCard(
                            selected: _selectedPreset == null,
                            config: _personalizedConfig,
                            calories: widget.calories,
                            onTap: _openPersonalizedSheet,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: FreshSpacing.md),
              FilledButton(
                key: const ValueKey('macro_distribution_save_button'),
                onPressed: _save,
                child: Text(l10n.macroSaveMacros),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _selectPreset(MacroPreset preset) {
    setState(() {
      _selectedPreset = preset;
    });
  }

  Future<void> _openPersonalizedSheet() async {
    final config = await showModalBottomSheet<MacroDistributionConfig>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (context) => _PersonalizedMacroSheet(
        calories: widget.calories,
        initialConfig: _personalizedInitialConfig(),
      ),
    );
    if (!mounted || config == null) return;
    Navigator.of(context).pop(config);
  }

  MacroDistributionConfig _personalizedInitialConfig() {
    final personalizedConfig = _personalizedConfig;
    if (personalizedConfig != null) return personalizedConfig;
    final goals = widget.initialGoals;
    if (goals != null &&
        (goals.macroMode == MacroMode.grams ||
            goals.macroSource == MacroSource.custom)) {
      return _configFromGoals(goals);
    }
    final preset =
        _selectedPreset ?? goals?.macroPreset ?? MacroPreset.balanced;
    return MacroDistributionConfig.percentage(
      proteinPct: preset.proteinPct,
      carbsPct: preset.carbsPct,
      fatPct: preset.fatPct,
    );
  }

  MacroDistributionConfig _configFromGoals(DailyGoals goals) {
    if (goals.macroMode == MacroMode.grams) {
      return MacroDistributionConfig.grams(
        proteinGrams: goals.target.proteinGrams,
        carbsGrams: goals.target.carbsGrams,
        fatGrams: goals.target.fatGrams,
      );
    }
    final presetPercentages =
        goals.macroPreset?.percentages ?? MacroPreset.balanced.percentages;
    return MacroDistributionConfig.percentage(
      proteinPct: goals.proteinPct ?? presetPercentages.proteinPct,
      carbsPct: goals.carbsPct ?? presetPercentages.carbsPct,
      fatPct: goals.fatPct ?? presetPercentages.fatPct,
    );
  }

  void _save() {
    final selectedPreset = _selectedPreset;
    final config = selectedPreset != null
        ? MacroDistributionConfig.preset(selectedPreset)
        : _personalizedConfig;
    if (config == null ||
        !isValidMacroConfig(config, calories: widget.calories)) {
      return;
    }
    Navigator.of(context).pop(config);
  }
}

class _PersonalizedMacroSheet extends StatefulWidget {
  const _PersonalizedMacroSheet({
    required this.calories,
    required this.initialConfig,
  });

  final int calories;
  final MacroDistributionConfig initialConfig;

  @override
  State<_PersonalizedMacroSheet> createState() =>
      _PersonalizedMacroSheetState();
}

class _PersonalizedMacroSheetState extends State<_PersonalizedMacroSheet> {
  late MacroMode _mode;
  late int _proteinPct;
  late int _carbsPct;
  late int _fatPct;
  late final TextEditingController _proteinPctController;
  late final TextEditingController _carbsPctController;
  late final TextEditingController _fatPctController;
  late final TextEditingController _proteinGramsController;
  late final TextEditingController _carbsGramsController;
  late final TextEditingController _fatGramsController;

  @override
  void initState() {
    super.initState();
    final config = widget.initialConfig;
    _mode = config.mode;
    final percentages = config.percentages ?? MacroPreset.balanced.percentages;
    _proteinPct = percentages.proteinPct;
    _carbsPct = percentages.carbsPct;
    _fatPct = percentages.fatPct;
    final grams =
        config.grams ?? gramsFromPercentages(widget.calories, percentages);
    _proteinPctController = TextEditingController(text: '$_proteinPct');
    _carbsPctController = TextEditingController(text: '$_carbsPct');
    _fatPctController = TextEditingController(text: '$_fatPct');
    _proteinGramsController = TextEditingController(
      text: _formatGramValue(grams.proteinGrams),
    );
    _carbsGramsController = TextEditingController(
      text: _formatGramValue(grams.carbsGrams),
    );
    _fatGramsController = TextEditingController(
      text: _formatGramValue(grams.fatGrams),
    );
  }

  @override
  void dispose() {
    _proteinPctController.dispose();
    _carbsPctController.dispose();
    _fatPctController.dispose();
    _proteinGramsController.dispose();
    _carbsGramsController.dispose();
    _fatGramsController.dispose();
    super.dispose();
  }

  MacroPercentages get _percentages => MacroPercentages(
        proteinPct: _proteinPct,
        carbsPct: _carbsPct,
        fatPct: _fatPct,
      );

  MacroGrams get _grams => MacroGrams(
        proteinGrams: double.tryParse(_proteinGramsController.text.trim()) ?? 0,
        carbsGrams: double.tryParse(_carbsGramsController.text.trim()) ?? 0,
        fatGrams: double.tryParse(_fatGramsController.text.trim()) ?? 0,
      );

  bool get _canSave => isValidMacroConfig(_config, calories: widget.calories);

  MacroDistributionConfig get _config => _mode == MacroMode.percentage
      ? MacroDistributionConfig.percentage(
          proteinPct: _proteinPct,
          carbsPct: _carbsPct,
          fatPct: _fatPct,
        )
      : MacroDistributionConfig.grams(
          proteinGrams: _grams.proteinGrams,
          carbsGrams: _grams.carbsGrams,
          fatGrams: _grams.fatGrams,
        );

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Material(
      color: palette.screen,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, bottomInset + 20),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.9,
          child: Column(
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
                l10n.macroPersonalizedTitle,
                style: textTheme.titleLarge?.copyWith(
                  color: palette.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: FreshSpacing.xs),
              Text(
                l10n.macroDailyTarget(widget.calories),
                style: textTheme.bodyMedium?.copyWith(
                  color: palette.inkMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: FreshSpacing.lg),
              _MacroModeToggle(
                mode: _mode,
                onChanged: (mode) => setState(() {
                  _mode = mode;
                  if (mode == MacroMode.grams) {
                    _syncGramControllers(
                      gramsFromPercentages(widget.calories, _percentages),
                    );
                  }
                }),
              ),
              const SizedBox(height: FreshSpacing.lg),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: _mode == MacroMode.percentage
                      ? _percentageEditor()
                      : _gramsEditor(),
                ),
              ),
              const SizedBox(height: FreshSpacing.md),
              FilledButton(
                key: const ValueKey('personalized_macro_save_button'),
                onPressed: _canSave ? _save : null,
                child: Text(l10n.macroSavePersonalized),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _percentageEditor() {
    final l10n = context.l10n;
    final palette = context.freshPalette;
    final total = _percentages.total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FreshCard(
          key: const ValueKey('macro_percentage_editor'),
          color: context.freshPalette.surface,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _MacroNumberField(
                fieldKey: const ValueKey('macro_percentage_protein_field'),
                label: l10n.commonProtein,
                unit: '%',
                controller: _proteinPctController,
                onChanged: (value) => _setPercentage('protein', value),
              ),
              const SizedBox(height: FreshSpacing.md),
              _MacroNumberField(
                fieldKey: const ValueKey('macro_percentage_carbs_field'),
                label: l10n.commonCarbs,
                unit: '%',
                controller: _carbsPctController,
                onChanged: (value) => _setPercentage('carbs', value),
              ),
              const SizedBox(height: FreshSpacing.md),
              _MacroNumberField(
                fieldKey: const ValueKey('macro_percentage_fat_field'),
                label: l10n.commonFat,
                unit: '%',
                controller: _fatPctController,
                onChanged: (value) => _setPercentage('fat', value),
              ),
            ],
          ),
        ),
        if (total != 100) ...[
          const SizedBox(height: FreshSpacing.md),
          FreshStatusBanner(
            key: const ValueKey('macro_percentage_total_warning'),
            icon: Icons.error_outline_rounded,
            title: l10n.macroPercentagesMustTotal,
            message: l10n.macroPercentagesTotalMessage(total),
            color: palette.coral,
          ),
          const SizedBox(height: FreshSpacing.sm),
          Wrap(
            spacing: FreshSpacing.sm,
            runSpacing: FreshSpacing.sm,
            children: [
              OutlinedButton(
                key: const ValueKey('macro_percentage_adjust_protein'),
                onPressed: _canAdjustPercentage('protein')
                    ? () => _adjustPercentage('protein')
                    : null,
                child: Text(l10n.macroAdjustProtein),
              ),
              OutlinedButton(
                key: const ValueKey('macro_percentage_adjust_carbs'),
                onPressed: _canAdjustPercentage('carbs')
                    ? () => _adjustPercentage('carbs')
                    : null,
                child: Text(l10n.macroAdjustCarbs),
              ),
              OutlinedButton(
                key: const ValueKey('macro_percentage_adjust_fat'),
                onPressed: _canAdjustPercentage('fat')
                    ? () => _adjustPercentage('fat')
                    : null,
                child: Text(l10n.macroAdjustFat),
              ),
              OutlinedButton(
                key: const ValueKey('macro_percentage_reset_balanced'),
                onPressed: _resetBalancedPercentages,
                child: Text(l10n.macroResetBalanced),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _gramsEditor() {
    final l10n = context.l10n;
    final palette = context.freshPalette;
    final grams = _grams;
    final gramsWithinLimits = areMacroGramsWithinLimits(grams);
    final delta = calorieDeltaKcal(widget.calories, grams);
    final warning = macroWarningLevel(delta);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FreshCard(
          key: const ValueKey('macro_grams_editor'),
          color: context.freshPalette.surface,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _MacroNumberField(
                fieldKey: const ValueKey('macro_grams_protein_field'),
                label: l10n.commonProtein,
                unit: 'g',
                controller: _proteinGramsController,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: FreshSpacing.md),
              _MacroNumberField(
                fieldKey: const ValueKey('macro_grams_carbs_field'),
                label: l10n.commonCarbs,
                unit: 'g',
                controller: _carbsGramsController,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: FreshSpacing.md),
              _MacroNumberField(
                fieldKey: const ValueKey('macro_grams_fat_field'),
                label: l10n.commonFat,
                unit: 'g',
                controller: _fatGramsController,
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
        if (!gramsWithinLimits) ...[
          const SizedBox(height: FreshSpacing.md),
          FreshStatusBanner(
            key: const ValueKey('macro_grams_limit_warning'),
            icon: Icons.error_outline_rounded,
            title: l10n.macroGramsTooHigh,
            message: l10n.macroGramsTooHighMessage,
            color: palette.coral,
          ),
        ] else if (warning != MacroCalorieWarningLevel.none) ...[
          const SizedBox(height: FreshSpacing.md),
          FreshStatusBanner(
            key: const ValueKey('macro_calorie_mismatch_warning'),
            icon: warning == MacroCalorieWarningLevel.soft
                ? Icons.info_outline_rounded
                : Icons.error_outline_rounded,
            title: warning == MacroCalorieWarningLevel.soft
                ? l10n.macroSmallCalorieMismatch
                : l10n.macroCaloriesDoNotMatch,
            message: delta > 0
                ? l10n.macroGramMismatchOverMessage(
                    macroCaloriesFromGrams(grams),
                    delta.abs(),
                  )
                : l10n.macroGramMismatchUnderMessage(
                    macroCaloriesFromGrams(grams),
                    delta.abs(),
                  ),
            color: warning == MacroCalorieWarningLevel.soft
                ? palette.orange
                : palette.coral,
          ),
          const SizedBox(height: FreshSpacing.sm),
          Wrap(
            spacing: FreshSpacing.sm,
            runSpacing: FreshSpacing.sm,
            children: [
              OutlinedButton(
                key: const ValueKey('macro_warning_adjust_protein'),
                onPressed: _canAdjustGrams('protein')
                    ? () => _adjustGramsToCalories('protein')
                    : null,
                child: Text(l10n.macroAdjustProtein),
              ),
              OutlinedButton(
                key: const ValueKey('macro_warning_adjust_carbs'),
                onPressed: _canAdjustGrams('carbs')
                    ? () => _adjustGramsToCalories('carbs')
                    : null,
                child: Text(l10n.macroAdjustCarbs),
              ),
              OutlinedButton(
                key: const ValueKey('macro_warning_adjust_fat'),
                onPressed: _canAdjustGrams('fat')
                    ? () => _adjustGramsToCalories('fat')
                    : null,
                child: Text(l10n.macroAdjustFat),
              ),
              OutlinedButton(
                key: const ValueKey('macro_warning_recalculate_percentages'),
                onPressed: _usePercentages,
                child: Text(l10n.macroUsePercentages),
              ),
            ],
          ),
        ],
      ],
    );
  }

  void _setPercentage(String macro, int value) {
    setState(() {
      if (macro == 'protein') {
        _proteinPct = value;
      } else if (macro == 'carbs') {
        _carbsPct = value;
      } else {
        _fatPct = value;
      }
    });
  }

  bool _canAdjustPercentage(String macro) {
    final delta = 100 - _percentages.total;
    if (delta >= 0) return true;
    return _percentageValue(macro) >= -delta;
  }

  int _percentageValue(String macro) {
    if (macro == 'protein') return _proteinPct;
    if (macro == 'carbs') return _carbsPct;
    return _fatPct;
  }

  void _adjustPercentage(String macro) {
    if (!_canAdjustPercentage(macro)) return;
    final delta = 100 - _percentages.total;
    setState(() {
      if (macro == 'protein') {
        _proteinPct += delta;
      } else if (macro == 'carbs') {
        _carbsPct += delta;
      } else {
        _fatPct += delta;
      }
      _syncPercentageControllers();
    });
  }

  void _resetBalancedPercentages() {
    final percentages = MacroPreset.balanced.percentages;
    setState(() {
      _proteinPct = percentages.proteinPct;
      _carbsPct = percentages.carbsPct;
      _fatPct = percentages.fatPct;
      _syncPercentageControllers();
    });
  }

  bool _canAdjustGrams(String macro) {
    final remainingCalories = _remainingCaloriesForMacro(macro);
    if (remainingCalories < 0) return false;
    return remainingCalories / _kcalPerGram(macro) <= maxMacroGramTarget;
  }

  void _adjustGramsToCalories(String macro) {
    if (!_canAdjustGrams(macro)) return;
    final nextGrams = _remainingCaloriesForMacro(macro) / _kcalPerGram(macro);
    setState(() {
      _setControllerText(
          _controllerForMacro(macro), _formatGramValue(nextGrams));
    });
  }

  double _remainingCaloriesForMacro(String macro) {
    final grams = _grams;
    var usedCalories = 0.0;
    if (macro != 'protein') {
      usedCalories += grams.proteinGrams * proteinKcalPerGram;
    }
    if (macro != 'carbs') {
      usedCalories += grams.carbsGrams * carbsKcalPerGram;
    }
    if (macro != 'fat') {
      usedCalories += grams.fatGrams * fatKcalPerGram;
    }
    return widget.calories - usedCalories;
  }

  int _kcalPerGram(String macro) {
    if (macro == 'fat') return fatKcalPerGram;
    return macro == 'protein' ? proteinKcalPerGram : carbsKcalPerGram;
  }

  TextEditingController _controllerForMacro(String macro) {
    if (macro == 'protein') return _proteinGramsController;
    if (macro == 'carbs') return _carbsGramsController;
    return _fatGramsController;
  }

  void _usePercentages() {
    final percentages = _normalizedPercentagesFromGrams(_grams);
    setState(() {
      _mode = MacroMode.percentage;
      _proteinPct = percentages.proteinPct;
      _carbsPct = percentages.carbsPct;
      _fatPct = percentages.fatPct;
      _syncPercentageControllers();
    });
  }

  MacroPercentages _normalizedPercentagesFromGrams(MacroGrams grams) {
    final macroCalories = macroCaloriesFromGrams(grams);
    if (macroCalories <= 0) return MacroPreset.balanced.percentages;
    final proteinPct =
        (grams.proteinGrams * proteinKcalPerGram / macroCalories * 100).round();
    final carbsPct =
        (grams.carbsGrams * carbsKcalPerGram / macroCalories * 100).round();
    final fatPct = (100 - proteinPct - carbsPct).clamp(0, 100).toInt();
    return MacroPercentages(
      proteinPct: proteinPct.clamp(0, 100).toInt(),
      carbsPct: carbsPct.clamp(0, 100).toInt(),
      fatPct: fatPct,
    );
  }

  void _syncPercentageControllers() {
    _setControllerText(_proteinPctController, '$_proteinPct');
    _setControllerText(_carbsPctController, '$_carbsPct');
    _setControllerText(_fatPctController, '$_fatPct');
  }

  void _syncGramControllers(MacroGrams grams) {
    _setControllerText(
      _proteinGramsController,
      _formatGramValue(grams.proteinGrams),
    );
    _setControllerText(
      _carbsGramsController,
      _formatGramValue(grams.carbsGrams),
    );
    _setControllerText(_fatGramsController, _formatGramValue(grams.fatGrams));
  }

  void _setControllerText(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _save() {
    if (!_canSave) return;
    Navigator.of(context).pop(_config);
  }
}

class _PersonalizedMacroCard extends StatelessWidget {
  const _PersonalizedMacroCard({
    required this.selected,
    required this.config,
    required this.calories,
    required this.onTap,
  });

  final bool selected;
  final MacroDistributionConfig? config;
  final int calories;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final config = this.config;
    final primary = config == null
        ? l10n.macroCreateOwnSplit
        : _primarySummary(config, calories, l10n);
    final secondary = config == null
        ? l10n.macroPercentagesOrGrams
        : config.mode == MacroMode.percentage
            ? l10n.macroPersonalizedPercentages
            : l10n.macroPersonalizedGrams;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(FreshRadii.lg),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(FreshRadii.lg),
            border: Border.all(
              color: selected ? palette.lime : palette.ruleSoft,
              width: selected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: context.freshShadowColor(
                  lightAlpha: 0.09,
                  darkAlpha: 0.42,
                ),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: selected ? palette.limeWash : palette.surfaceSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.tune_rounded,
                  key: const ValueKey('macro_personalized_icon'),
                  color: selected ? palette.limeDeep : palette.ink,
                ),
              ),
              const SizedBox(width: FreshSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.macroPersonalized,
                      style: textTheme.titleSmall?.copyWith(
                        color: palette.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      primary,
                      style: textTheme.bodySmall?.copyWith(
                        color: palette.inkSoft,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      secondary,
                      style: textTheme.bodySmall?.copyWith(
                        color: palette.inkMuted,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: FreshSpacing.md),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: selected ? palette.lime : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? palette.lime : palette.rule,
                  ),
                ),
                child: selected
                    ? Icon(Icons.check_rounded, color: palette.ink, size: 18)
                    : const Icon(Icons.chevron_right_rounded, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _primarySummary(
    MacroDistributionConfig config,
    int calories,
    AppLocalizations l10n,
  ) {
    if (config.mode == MacroMode.grams && config.grams != null) {
      final grams = config.grams!;
      return _macroGramLine(l10n, grams);
    }
    final percentages = config.percentages ?? MacroPreset.balanced.percentages;
    final grams = gramsFromPercentages(calories, percentages);
    return l10n.macroPercentagesWithGramsSummary(
      _macroPercentLine(l10n, percentages),
      l10n.macroGramTriplet(
        _formatGramValue(grams.proteinGrams),
        _formatGramValue(grams.carbsGrams),
        _formatGramValue(grams.fatGrams),
      ),
    );
  }
}

class MacroPresetCard extends StatelessWidget {
  const MacroPresetCard({
    super.key,
    required this.preset,
    required this.calories,
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final MacroPreset preset;
  final int calories;
  final MacroMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final grams = gramsFromPercentages(calories, preset.percentages);
    final gramLine = _macroGramLine(l10n, grams);
    final percentLine = _macroPercentLine(l10n, preset.percentages);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(FreshRadii.lg),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(FreshRadii.lg),
            border: Border.all(
              color: selected ? palette.lime : palette.ruleSoft,
              width: selected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: context.freshShadowColor(
                  lightAlpha: 0.09,
                  darkAlpha: 0.42,
                ),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: selected ? palette.limeWash : palette.surfaceSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _iconForPreset(preset),
                  key: ValueKey('macro_preset_icon_${preset.apiValue}'),
                  color: selected ? palette.limeDeep : palette.ink,
                ),
              ),
              const SizedBox(width: FreshSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _localizedPresetLabel(l10n, preset),
                      style: textTheme.titleSmall?.copyWith(
                        color: palette.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      mode == MacroMode.grams ? gramLine : percentLine,
                      style: textTheme.bodySmall?.copyWith(
                        color: palette.inkSoft,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      mode == MacroMode.grams ? percentLine : gramLine,
                      style: textTheme.bodySmall?.copyWith(
                        color: palette.inkMuted,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: FreshSpacing.md),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: selected ? palette.lime : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? palette.lime : palette.rule,
                  ),
                ),
                child: selected
                    ? Icon(Icons.check_rounded, color: palette.ink, size: 18)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForPreset(MacroPreset preset) {
    switch (preset) {
      case MacroPreset.balanced:
        return Icons.pie_chart_rounded;
      case MacroPreset.highProtein:
        return Icons.fitness_center_rounded;
      case MacroPreset.lowerCarb:
        return Icons.eco_rounded;
    }
  }
}

class _MacroModeToggle extends StatelessWidget {
  const _MacroModeToggle({
    required this.mode,
    required this.onChanged,
  });

  final MacroMode mode;
  final ValueChanged<MacroMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.surfaceSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Expanded(
            child: _MacroModeSegment(
              key: const ValueKey('macro_mode_percentage'),
              label: l10n.macroPercentagesTab,
              selected: mode == MacroMode.percentage,
              onTap: () => onChanged(MacroMode.percentage),
            ),
          ),
          Expanded(
            child: _MacroModeSegment(
              key: const ValueKey('macro_mode_grams'),
              label: l10n.macroGramsTab,
              selected: mode == MacroMode.grams,
              onTap: () => onChanged(MacroMode.grams),
            ),
          ),
        ],
      ),
    );
  }
}

class _MacroModeSegment extends StatelessWidget {
  const _MacroModeSegment({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? palette.lime : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: palette.ink,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
      ),
    );
  }
}

class _MacroNumberField extends StatelessWidget {
  const _MacroNumberField({
    required this.fieldKey,
    required this.label,
    required this.unit,
    required this.controller,
    required this.onChanged,
  });

  final Key fieldKey;
  final String label;
  final String unit;
  final TextEditingController controller;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: palette.ink,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        SizedBox(
          width: 112,
          child: TextField(
            key: fieldKey,
            controller: controller,
            textAlign: TextAlign.end,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(suffixText: unit),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            onChanged: (value) => onChanged(int.tryParse(value) ?? 0),
          ),
        ),
      ],
    );
  }
}

String _formatGramValue(num value) {
  return value.round().toString();
}

String _macroGramLine(AppLocalizations l10n, MacroGrams grams) {
  return [
    l10n.macroProteinGramsSummary(_formatGramValue(grams.proteinGrams)),
    l10n.macroCarbsGramsSummary(_formatGramValue(grams.carbsGrams)),
    l10n.macroFatGramsSummary(_formatGramValue(grams.fatGrams)),
  ].join(' · ');
}

String _macroPercentLine(
  AppLocalizations l10n,
  MacroPercentages percentages,
) {
  return [
    l10n.macroProteinPercentSummary(percentages.proteinPct),
    l10n.macroCarbsPercentSummary(percentages.carbsPct),
    l10n.macroFatPercentSummary(percentages.fatPct),
  ].join(' · ');
}

String _localizedPresetLabel(AppLocalizations l10n, MacroPreset preset) {
  switch (preset) {
    case MacroPreset.balanced:
      return l10n.macroPresetBalanced;
    case MacroPreset.highProtein:
      return l10n.macroPresetHighProtein;
    case MacroPreset.lowerCarb:
      return l10n.macroPresetLowerCarb;
  }
}
