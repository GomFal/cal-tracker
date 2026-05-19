import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../domain/models/macro_distribution.dart';
import '../../../../domain/models/nutrition_models.dart';
import '../../../core/design_system.dart';

class MacroDistributionSheet extends StatefulWidget {
  const MacroDistributionSheet({
    super.key,
    required this.calories,
    this.initialGoals,
    this.presetOnly = false,
    this.title = 'Set your macros',
  });

  final int calories;
  final DailyGoals? initialGoals;
  final bool presetOnly;
  final String title;

  @override
  State<MacroDistributionSheet> createState() => _MacroDistributionSheetState();
}

class _MacroDistributionSheetState extends State<MacroDistributionSheet> {
  late MacroMode _mode;
  late MacroPreset? _preset;
  late int _proteinPct;
  late int _carbsPct;
  late int _fatPct;
  late final TextEditingController _proteinPctController;
  late final TextEditingController _carbsPctController;
  late final TextEditingController _fatPctController;
  late final TextEditingController _proteinGramsController;
  late final TextEditingController _carbsGramsController;
  late final TextEditingController _fatGramsController;
  bool _acceptedGramMismatch = false;

  @override
  void initState() {
    super.initState();
    final goals = widget.initialGoals;
    _mode = widget.presetOnly
        ? MacroMode.percentage
        : goals?.macroMode ?? MacroMode.percentage;
    _preset = widget.presetOnly ? MacroPreset.balanced : goals?.macroPreset;
    final presetPercentages =
        _preset?.percentages ?? MacroPreset.balanced.percentages;
    _proteinPct = goals?.proteinPct ?? presetPercentages.proteinPct;
    _carbsPct = goals?.carbsPct ?? presetPercentages.carbsPct;
    _fatPct = goals?.fatPct ?? presetPercentages.fatPct;
    final initialGrams = goals == null
        ? gramsFromPercentages(widget.calories, _percentages)
        : MacroGrams(
            proteinGrams: goals.target.proteinGrams,
            carbsGrams: goals.target.carbsGrams,
            fatGrams: goals.target.fatGrams,
          );
    _proteinPctController = TextEditingController(text: '$_proteinPct');
    _carbsPctController = TextEditingController(text: '$_carbsPct');
    _fatPctController = TextEditingController(text: '$_fatPct');
    _proteinGramsController = TextEditingController(
        text: _formatGramValue(initialGrams.proteinGrams));
    _carbsGramsController =
        TextEditingController(text: _formatGramValue(initialGrams.carbsGrams));
    _fatGramsController =
        TextEditingController(text: _formatGramValue(initialGrams.fatGrams));
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

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
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
                widget.title,
                style: textTheme.titleLarge?.copyWith(
                  color: palette.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: FreshSpacing.xs),
              Text(
                'Daily target: ${widget.calories} Kcal',
                style: textTheme.bodyMedium?.copyWith(
                  color: palette.inkMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: FreshSpacing.lg),
              if (!widget.presetOnly) ...[
                _MacroModeToggle(
                  mode: _mode,
                  onChanged: (mode) => setState(() {
                    _mode = mode;
                    _acceptedGramMismatch = false;
                    if (mode == MacroMode.grams) {
                      _syncGramControllers(
                        gramsFromPercentages(widget.calories, _percentages),
                      );
                    }
                  }),
                ),
                const SizedBox(height: FreshSpacing.lg),
              ],
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
                            mode: _mode,
                            selected: _preset == preset,
                            onTap: () => _selectPreset(preset),
                          ),
                        ),
                      if (!widget.presetOnly) ...[
                        const SizedBox(height: FreshSpacing.sm),
                        if (_mode == MacroMode.percentage)
                          _percentageEditor()
                        else
                          _gramsEditor(),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: FreshSpacing.md),
              FilledButton(
                key: const ValueKey('macro_distribution_save_button'),
                onPressed: _save,
                child: const Text('Save macros'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _percentageEditor() {
    return FreshCard(
      key: const ValueKey('macro_percentage_editor'),
      color: context.freshPalette.surface,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _MacroNumberField(
            fieldKey: const ValueKey('macro_percentage_protein_field'),
            label: 'Protein',
            unit: '%',
            controller: _proteinPctController,
            onChanged: (value) => _setPercentage('protein', value),
          ),
          const SizedBox(height: FreshSpacing.md),
          _MacroNumberField(
            fieldKey: const ValueKey('macro_percentage_carbs_field'),
            label: 'Carbs',
            unit: '%',
            controller: _carbsPctController,
            onChanged: (value) => _setPercentage('carbs', value),
          ),
          const SizedBox(height: FreshSpacing.md),
          _MacroNumberField(
            fieldKey: const ValueKey('macro_percentage_fat_field'),
            label: 'Fat',
            unit: '%',
            controller: _fatPctController,
            onChanged: (value) => _setPercentage('fat', value),
          ),
        ],
      ),
    );
  }

  Widget _gramsEditor() {
    final delta = calorieDeltaKcal(widget.calories, _grams);
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
                label: 'Protein',
                unit: 'g',
                controller: _proteinGramsController,
                onChanged: (_) => _gramsChanged(),
              ),
              const SizedBox(height: FreshSpacing.md),
              _MacroNumberField(
                fieldKey: const ValueKey('macro_grams_carbs_field'),
                label: 'Carbs',
                unit: 'g',
                controller: _carbsGramsController,
                onChanged: (_) => _gramsChanged(),
              ),
              const SizedBox(height: FreshSpacing.md),
              _MacroNumberField(
                fieldKey: const ValueKey('macro_grams_fat_field'),
                label: 'Fat',
                unit: 'g',
                controller: _fatGramsController,
                onChanged: (_) => _gramsChanged(),
              ),
            ],
          ),
        ),
        if (warning != MacroCalorieWarningLevel.none &&
            !_acceptedGramMismatch) ...[
          const SizedBox(height: FreshSpacing.md),
          FreshStatusBanner(
            key: const ValueKey('macro_calorie_mismatch_warning'),
            icon: warning == MacroCalorieWarningLevel.soft
                ? Icons.info_outline_rounded
                : Icons.error_outline_rounded,
            title: warning == MacroCalorieWarningLevel.soft
                ? 'Small calorie mismatch'
                : 'Macros do not match calories',
            message:
                'These grams add up to ${macroCaloriesFromGrams(_grams)} Kcal, ${delta.abs()} Kcal ${delta > 0 ? 'over' : 'under'} your target.',
            color: warning == MacroCalorieWarningLevel.soft
                ? FreshColors.orange
                : FreshColors.coral,
          ),
          const SizedBox(height: FreshSpacing.sm),
          Wrap(
            spacing: FreshSpacing.sm,
            runSpacing: FreshSpacing.sm,
            children: [
              OutlinedButton(
                key: const ValueKey('macro_warning_keep_grams'),
                onPressed: () => setState(() => _acceptedGramMismatch = true),
                child: const Text('Keep grams'),
              ),
              OutlinedButton(
                key: const ValueKey('macro_warning_adjust_carbs'),
                onPressed: _adjustCarbsToCalories,
                child: const Text('Adjust carbs'),
              ),
              OutlinedButton(
                key: const ValueKey('macro_warning_adjust_fats'),
                onPressed: _adjustFatsToCalories,
                child: const Text('Adjust fats'),
              ),
              OutlinedButton(
                key: const ValueKey('macro_warning_recalculate_percentages'),
                onPressed: _recalculatePercentages,
                child: const Text('Use percentages'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  void _selectPreset(MacroPreset preset) {
    setState(() {
      _preset = preset;
      _proteinPct = preset.proteinPct;
      _carbsPct = preset.carbsPct;
      _fatPct = preset.fatPct;
      _syncPercentageControllers();
      _syncGramControllers(gramsFromPercentages(widget.calories, _percentages));
      _acceptedGramMismatch = false;
    });
  }

  void _setPercentage(String macro, int value) {
    final next = value.clamp(0, 100).toInt();
    setState(() {
      _preset = null;
      if (macro == 'protein') {
        _proteinPct = next;
        _carbsPct = 100 - _proteinPct - _fatPct;
        if (_carbsPct < 0) {
          _fatPct = (100 - _proteinPct).clamp(0, 100).toInt();
          _carbsPct = 0;
        }
      } else if (macro == 'fat') {
        _fatPct = next;
        _carbsPct = 100 - _proteinPct - _fatPct;
        if (_carbsPct < 0) {
          _proteinPct = (100 - _fatPct).clamp(0, 100).toInt();
          _carbsPct = 0;
        }
      } else {
        _carbsPct = next;
        _fatPct = 100 - _proteinPct - _carbsPct;
        if (_fatPct < 0) {
          _proteinPct = (100 - _carbsPct).clamp(0, 100).toInt();
          _fatPct = 0;
        }
      }
      _syncPercentageControllers();
    });
  }

  void _gramsChanged() {
    setState(() {
      _preset = null;
      _acceptedGramMismatch = false;
    });
  }

  void _adjustCarbsToCalories() {
    final grams = _grams;
    final remainingCalories = widget.calories -
        (grams.proteinGrams * proteinKcalPerGram) -
        (grams.fatGrams * fatKcalPerGram);
    _setControllerText(
      _carbsGramsController,
      _formatGramValue((remainingCalories / carbsKcalPerGram).clamp(0, 2000)),
    );
    _gramsChanged();
  }

  void _adjustFatsToCalories() {
    final grams = _grams;
    final remainingCalories = widget.calories -
        (grams.proteinGrams * proteinKcalPerGram) -
        (grams.carbsGrams * carbsKcalPerGram);
    _setControllerText(
      _fatGramsController,
      _formatGramValue((remainingCalories / fatKcalPerGram).clamp(0, 2000)),
    );
    _gramsChanged();
  }

  void _recalculatePercentages() {
    final percentages = percentagesFromGrams(widget.calories, _grams);
    setState(() {
      _mode = MacroMode.percentage;
      _preset = null;
      _proteinPct = percentages.proteinPct;
      _carbsPct = percentages.carbsPct;
      _fatPct = percentages.fatPct;
      _syncPercentageControllers();
      _acceptedGramMismatch = false;
    });
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
    final config = _mode == MacroMode.percentage
        ? (_preset == null
            ? MacroDistributionConfig.percentage(
                proteinPct: _proteinPct,
                carbsPct: _carbsPct,
                fatPct: _fatPct,
              )
            : MacroDistributionConfig.preset(_preset!))
        : MacroDistributionConfig.grams(
            proteinGrams: _grams.proteinGrams,
            carbsGrams: _grams.carbsGrams,
            fatGrams: _grams.fatGrams,
          );
    Navigator.of(context).pop(config);
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
    final grams = gramsFromPercentages(calories, preset.percentages);
    final gramLine =
        '${grams.proteinGrams.round()}g protein · ${grams.carbsGrams.round()}g carbs · ${grams.fatGrams.round()}g fat';
    final percentLine =
        '${preset.proteinPct}% protein · ${preset.carbsPct}% carbs · ${preset.fatPct}% fat';
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
            boxShadow: const [
              BoxShadow(
                color: Color(0x17080907),
                blurRadius: 28,
                offset: Offset(0, 14),
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
                  Icons.pie_chart_rounded,
                  color: selected ? palette.limeDeep : palette.ink,
                ),
              ),
              const SizedBox(width: FreshSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preset.label,
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
              label: 'Percentages',
              selected: mode == MacroMode.percentage,
              onTap: () => onChanged(MacroMode.percentage),
            ),
          ),
          Expanded(
            child: _MacroModeSegment(
              key: const ValueKey('macro_mode_grams'),
              label: 'Grams',
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
  if ((value - value.round()).abs() < 0.01) return value.round().toString();
  return value.toStringAsFixed(1);
}
