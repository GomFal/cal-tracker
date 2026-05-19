import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../domain/models/macro_distribution.dart';
import '../../../../domain/models/nutrition_models.dart';
import '../../../../l10n/app_localizations_context.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/design_system.dart';
import '../../../core/user_visible_error.dart';
import 'macro_distribution_sheet.dart';

class CalorieTargetSelection {
  const CalorieTargetSelection({
    required this.calories,
    required this.source,
    this.macroConfig,
  });

  final int calories;
  final String source;
  final MacroDistributionConfig? macroConfig;
}

class CalorieTargetSheet extends StatefulWidget {
  const CalorieTargetSheet({
    super.key,
    required this.initialValue,
    required this.estimateCalories,
  });

  final int initialValue;
  final Future<CalorieEstimate> Function({
    required int age,
    required String sex,
    required double heightCm,
    required double weightKg,
    required String activityLevel,
    required String goal,
    String? pace,
  }) estimateCalories;

  @override
  State<CalorieTargetSheet> createState() => _CalorieTargetSheetState();
}

class _CalorieTargetSheetState extends State<CalorieTargetSheet> {
  late final TextEditingController _controller;
  String _source = 'manual';
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
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.86;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottomInset + 20),
      child: SizedBox(
        height: maxHeight,
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
              l10n.calorieTargetSheetTitle,
              style: textTheme.titleLarge,
            ),
            const SizedBox(height: FreshSpacing.xs),
            Text(
              l10n.calorieTargetSheetSubtitle,
              style: textTheme.bodyMedium?.copyWith(color: palette.inkMuted),
            ),
            const SizedBox(height: FreshSpacing.lg),
            FreshCard(
              shadow: false,
              color: palette.surfaceSoft,
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  _StepButton(
                    key: const ValueKey('calorie_target_decrement'),
                    icon: Icons.remove_rounded,
                    onTap: () => _step(-50),
                  ),
                  const SizedBox(width: FreshSpacing.md),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('dashboard_calorie_target_field'),
                      controller: _controller,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      style: textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      decoration: InputDecoration(
                        suffixText: l10n.commonKcal,
                        errorText: _error,
                      ),
                      onChanged: (_) => setState(() {
                        _source = 'manual';
                        _error = null;
                      }),
                    ),
                  ),
                  const SizedBox(width: FreshSpacing.md),
                  _StepButton(
                    key: const ValueKey('calorie_target_increment'),
                    icon: Icons.add_rounded,
                    onTap: () => _step(50),
                  ),
                ],
              ),
            ),
            const SizedBox(height: FreshSpacing.md),
            TextButton(
              key: const ValueKey('calorie_calculator_link'),
              onPressed: _showCalculator,
              child: Text(l10n.calorieTargetCalculatorLink),
            ),
            const SizedBox(height: FreshSpacing.lg),
            FilledButton(
              key: const ValueKey('dashboard_save_calorie_target_button'),
              onPressed: _submit,
              child: Text(l10n.commonSave),
            ),
          ],
        ),
      ),
    );
  }

  void _step(int delta) {
    final current =
        int.tryParse(_controller.text.trim()) ?? widget.initialValue;
    final next = (current + delta).clamp(800, 10000).toInt();
    setState(() {
      _source = 'manual';
      _error = null;
      _controller.text = next.toString();
    });
  }

  Future<void> _showCalculator() async {
    final estimate = await showModalBottomSheet<CalorieEstimate>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (context) => CalorieCalculatorWizard(
        estimateCalories: widget.estimateCalories,
      ),
    );
    if (estimate == null || !mounted) return;
    final macroConfig = await showModalBottomSheet<MacroDistributionConfig>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (context) => _CalculatorMacroPrompt(
        calories: estimate.targetCalories,
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop(
      CalorieTargetSelection(
        calories: estimate.targetCalories,
        source: 'calculator',
        macroConfig: macroConfig,
      ),
    );
  }

  void _submit() {
    final value = int.tryParse(_controller.text.trim());
    if (value == null || value < 800 || value > 10000) {
      setState(() => _error = context.l10n.calorieTargetRangeValidationError(
            800,
            10000,
          ));
      return;
    }
    Navigator.of(context).pop(
      CalorieTargetSelection(calories: value, source: _source),
    );
  }
}

class _CalculatorMacroPrompt extends StatelessWidget {
  const _CalculatorMacroPrompt({required this.calories});

  final int calories;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;
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
                color: palette.rule,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: FreshSpacing.lg),
          Text(
            l10n.calorieMacroPromptTitle,
            style: textTheme.titleLarge?.copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: FreshSpacing.xs),
          Text(
            l10n.calorieMacroPromptMessage(calories),
            style: textTheme.bodyMedium?.copyWith(color: palette.inkMuted),
          ),
          const SizedBox(height: FreshSpacing.lg),
          FilledButton(
            key: const ValueKey('calculator_macro_configure_button'),
            onPressed: () async {
              final config =
                  await showModalBottomSheet<MacroDistributionConfig>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                useRootNavigator: true,
                builder: (context) => MacroDistributionSheet(
                  calories: calories,
                  presetOnly: true,
                  title: l10n.calorieCalculatorChooseYourMacrosTitle,
                ),
              );
              if (context.mounted && config != null) {
                Navigator.of(context).pop(config);
              }
            },
            child: Text(l10n.calorieMacroPromptConfigure),
          ),
          const SizedBox(height: FreshSpacing.sm),
          TextButton(
            key: const ValueKey('calculator_macro_skip_button'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.calorieMacroPromptSkip),
          ),
        ],
      ),
    );
  }
}

class PostCalorieSaveMacroPrompt extends StatelessWidget {
  const PostCalorieSaveMacroPrompt({super.key, required this.calories});

  final int calories;

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
            l10n.postCalorieSaveTitle,
            style: textTheme.titleLarge?.copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: FreshSpacing.xs),
          Text(
            l10n.postCalorieSaveTarget(calories),
            style: textTheme.bodyMedium?.copyWith(color: palette.inkSoft),
          ),
          const SizedBox(height: FreshSpacing.xs),
          Text(
            l10n.postCalorieSaveMacroQuestion,
            style: textTheme.bodyMedium?.copyWith(color: palette.inkMuted),
          ),
          const SizedBox(height: FreshSpacing.lg),
          FilledButton(
            key: const ValueKey('macro_prompt_set_distribution'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.postCalorieSaveSetMacroDistribution),
          ),
          const SizedBox(height: FreshSpacing.sm),
          TextButton(
            key: const ValueKey('macro_prompt_not_now'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.postCalorieSaveNotNow),
          ),
        ],
      ),
    );
  }
}

class CalorieCalculatorWizard extends StatefulWidget {
  const CalorieCalculatorWizard({
    super.key,
    required this.estimateCalories,
  });

  final Future<CalorieEstimate> Function({
    required int age,
    required String sex,
    required double heightCm,
    required double weightKg,
    required String activityLevel,
    required String goal,
    String? pace,
  }) estimateCalories;

  @override
  State<CalorieCalculatorWizard> createState() =>
      _CalorieCalculatorWizardState();
}

enum _WizardStep {
  sex,
  age,
  height,
  weight,
  goal,
  pace,
  activity,
  result,
}

class _CalorieCalculatorWizardState extends State<CalorieCalculatorWizard> {
  final _heightController = TextEditingController(text: '170');
  final _weightController = TextEditingController(text: '70');
  final _feetController = TextEditingController(text: '5');
  final _inchesController = TextEditingController(text: '7');
  final _poundsController = TextEditingController(text: '154');
  late DateTime _birthDate;
  late final FixedExtentScrollController _birthMonthController;
  late final FixedExtentScrollController _birthDayController;
  late final FixedExtentScrollController _birthYearController;
  int _stepIndex = 0;
  bool _heightMetric = true;
  bool _weightMetric = true;
  String _sex = 'male';
  String _activityLevel = 'moderately_active';
  String _goal = 'maintain';
  String _lossPace = 'moderate';
  String _gainPace = 'standard';
  bool _isLoading = false;
  String? _error;
  CalorieEstimate? _estimate;

  @override
  void initState() {
    super.initState();
    _birthDate = _defaultBirthDate();
    _birthMonthController =
        FixedExtentScrollController(initialItem: _birthDate.month - 1);
    _birthDayController =
        FixedExtentScrollController(initialItem: _birthDate.day - 1);
    _birthYearController = FixedExtentScrollController(
      initialItem: _birthDate.year - _oldestAllowedBirthDate().year,
    );
  }

  @override
  void dispose() {
    _heightController.dispose();
    _weightController.dispose();
    _feetController.dispose();
    _inchesController.dispose();
    _poundsController.dispose();
    _birthMonthController.dispose();
    _birthDayController.dispose();
    _birthYearController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final l10n = context.l10n;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.94;
    final activeStep = _activeStep;
    final totalSteps = _totalSteps;
    final currentStep = _isResultStep ? totalSteps : _stepIndex + 1;
    return Material(
      color: palette.screen,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.fromLTRB(24, 10, 24, bottomInset + 16),
        child: SizedBox(
          height: maxHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _WizardTopBar(
                currentStep: currentStep,
                totalSteps: totalSteps,
                progress: currentStep / totalSteps,
                canGoBack: _stepIndex > 0 && !_isResultStep,
                onClose: () => Navigator.of(context).maybePop(),
                onBack: _goBack,
              ),
              if (_error != null) ...[
                const SizedBox(height: FreshSpacing.md),
                FreshStatusBanner(
                  icon: Icons.error_outline_rounded,
                  title: l10n.calorieWizardCheckDetailsTitle,
                  message: _error!,
                  color: FreshColors.coral,
                ),
              ],
              const SizedBox(height: FreshSpacing.md),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: KeyedSubtree(
                    key: ValueKey(_isLoading ? 'loading' : activeStep.name),
                    child:
                        _isLoading ? const _LoadingPlanStep() : _bodyForStep(),
                  ),
                ),
              ),
              if (!_isLoading) ...[
                const SizedBox(height: FreshSpacing.lg),
                FilledButton(
                  key: ValueKey(_isResultStep
                      ? 'calorie_wizard_use_estimate_button'
                      : 'calorie_wizard_next_button'),
                  onPressed: _primaryAction,
                  child: Text(
                    _isResultStep
                        ? l10n.calorieWizardUseEstimate
                        : l10n.calorieWizardContinue,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<_WizardStep> get _questionSteps {
    final steps = <_WizardStep>[
      _WizardStep.sex,
      _WizardStep.age,
      _WizardStep.height,
      _WizardStep.weight,
      _WizardStep.goal,
    ];
    if (_goal == 'lose_fat' || _goal == 'gain_muscle') {
      steps.add(_WizardStep.pace);
    }
    steps.add(_WizardStep.activity);
    return steps;
  }

  int get _totalSteps => _questionSteps.length + 1;

  bool get _isResultStep => _stepIndex >= _questionSteps.length;

  _WizardStep get _activeStep {
    if (_isResultStep) return _WizardStep.result;
    return _questionSteps[_stepIndex];
  }

  Widget _bodyForStep() {
    switch (_activeStep) {
      case _WizardStep.sex:
        return _sexStep();
      case _WizardStep.age:
        return _ageStep();
      case _WizardStep.height:
        return _heightStep();
      case _WizardStep.weight:
        return _weightStep();
      case _WizardStep.goal:
        return _goalStep();
      case _WizardStep.pace:
        return _paceStep();
      case _WizardStep.activity:
        return _activityStep();
      case _WizardStep.result:
        return _resultStep();
    }
  }

  void _setControllerText(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  String _formatCompactNumber(double value) {
    if ((value - value.roundToDouble()).abs() < 0.01) {
      return value.round().toString();
    }
    return value.toStringAsFixed(1);
  }

  String _formatFeetAndInches(double value) {
    final totalInches = value.round();
    final feet = totalInches ~/ 12;
    final inches = totalInches % 12;
    return '$feet\'$inches"';
  }

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime _youngestAllowedBirthDate() {
    final today = _today();
    return DateTime(today.year - 18, today.month, today.day);
  }

  DateTime _oldestAllowedBirthDate() {
    final today = _today();
    return DateTime(today.year - 100, today.month, today.day);
  }

  DateTime _defaultBirthDate() {
    final today = _today();
    return DateTime(today.year - 30, today.month, today.day);
  }

  List<int> get _birthYearValues {
    final oldest = _oldestAllowedBirthDate().year;
    final youngest = _youngestAllowedBirthDate().year;
    return List<int>.generate(youngest - oldest + 1, (index) => oldest + index);
  }

  int _daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  DateTime _clampBirthDate(DateTime date) {
    final oldest = _oldestAllowedBirthDate();
    final youngest = _youngestAllowedBirthDate();
    if (date.isBefore(oldest)) return oldest;
    if (date.isAfter(youngest)) return youngest;
    return date;
  }

  DateTime _safeBirthDate({
    required int year,
    required int month,
    required int day,
  }) {
    final safeDay = day.clamp(1, _daysInMonth(year, month)).toInt();
    return _clampBirthDate(DateTime(year, month, safeDay));
  }

  int _ageFromBirthDate(DateTime birthDate) {
    final today = _today();
    var age = today.year - birthDate.year;
    final hadBirthdayThisYear = today.month > birthDate.month ||
        (today.month == birthDate.month && today.day >= birthDate.day);
    if (!hadBirthdayThisYear) age -= 1;
    return age;
  }

  void _syncBirthWheelControllers() {
    final yearIndex = _birthDate.year - _oldestAllowedBirthDate().year;
    if (_birthMonthController.hasClients) {
      _birthMonthController.jumpToItem(_birthDate.month - 1);
    }
    if (_birthDayController.hasClients) {
      _birthDayController.jumpToItem(_birthDate.day - 1);
    }
    if (_birthYearController.hasClients) {
      _birthYearController.jumpToItem(yearIndex);
    }
  }

  void _setBirthDate({int? month, int? day, int? year}) {
    final requestedYear = year ?? _birthDate.year;
    final requestedMonth = month ?? _birthDate.month;
    final requestedDay = day ?? _birthDate.day;
    final next = _safeBirthDate(
      year: requestedYear,
      month: requestedMonth,
      day: requestedDay,
    );
    final needsWheelSync = next.year != requestedYear ||
        next.month != requestedMonth ||
        next.day != requestedDay;
    setState(() {
      _birthDate = next;
      _error = null;
    });
    if (needsWheelSync) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncBirthWheelControllers();
      });
    }
  }

  void _setHeightFromRuler(double value) {
    setState(() {
      if (_heightMetric) {
        final heightCm = value.clamp(120, 230).toDouble();
        _setControllerText(_heightController, heightCm.round().toString());
      } else {
        final totalInches = value.round().clamp(48, 90);
        final feet = totalInches ~/ 12;
        final inches = totalInches % 12;
        _setControllerText(_feetController, feet.toString());
        _setControllerText(_inchesController, inches.toString());
      }
      _error = null;
    });
  }

  void _setWeightFromRuler(double value) {
    setState(() {
      if (_weightMetric) {
        final weightKg = value.clamp(35, 250).toDouble();
        _setControllerText(_weightController, _formatCompactNumber(weightKg));
      } else {
        final pounds = value.round().clamp(78, 551);
        _setControllerText(_poundsController, pounds.toString());
      }
      _error = null;
    });
  }

  void _setHeightUnit(bool metric) {
    setState(() {
      if (metric && !_heightMetric) {
        final heightCm = _heightInCm();
        if (heightCm != null) {
          _setControllerText(_heightController, heightCm.round().toString());
        }
      }
      if (!metric && _heightMetric) {
        final heightCm = double.tryParse(_heightController.text.trim());
        if (heightCm != null) {
          final totalInches = (heightCm / 2.54).round().clamp(48, 90);
          _setControllerText(_feetController, (totalInches ~/ 12).toString());
          _setControllerText(_inchesController, (totalInches % 12).toString());
        }
      }
      _heightMetric = metric;
      _error = null;
    });
  }

  void _setWeightUnit(bool metric) {
    setState(() {
      if (metric && !_weightMetric) {
        final weightKg = _weightInKg();
        if (weightKg != null) {
          _setControllerText(_weightController, _formatCompactNumber(weightKg));
        }
      }
      if (!metric && _weightMetric) {
        final weightKg = double.tryParse(_weightController.text.trim());
        if (weightKg != null) {
          final pounds = (weightKg / 0.45359237).round().clamp(78, 551);
          _setControllerText(_poundsController, pounds.toString());
        }
      }
      _weightMetric = metric;
      _error = null;
    });
  }

  Widget _sexStep() {
    final l10n = context.l10n;
    return _WizardQuestionPage(
      title: l10n.calorieWizardSexTitle,
      subtitle: l10n.calorieWizardSexSubtitle,
      children: [
        _WizardChoiceCard(
          key: const ValueKey('calorie_wizard_sex_male'),
          icon: Icons.male_rounded,
          title: l10n.calorieWizardSexMale,
          message: l10n.calorieWizardSexMaleMessage,
          selected: _sex == 'male',
          onTap: () => setState(() {
            _sex = 'male';
            _error = null;
          }),
        ),
        const SizedBox(height: FreshSpacing.md),
        _WizardChoiceCard(
          key: const ValueKey('calorie_wizard_sex_female'),
          icon: Icons.female_rounded,
          title: l10n.calorieWizardSexFemale,
          message: l10n.calorieWizardSexFemaleMessage,
          selected: _sex == 'female',
          onTap: () => setState(() {
            _sex = 'female';
            _error = null;
          }),
        ),
      ],
    );
  }

  Widget _ageStep() {
    return _WizardQuestionPage(
      title: context.l10n.calorieWizardBirthdayTitle,
      centerTitle: true,
      children: [
        _BirthdayWheelPicker(
          selectedDate: _birthDate,
          years: _birthYearValues,
          monthController: _birthMonthController,
          dayController: _birthDayController,
          yearController: _birthYearController,
          onMonthChanged: (month) => _setBirthDate(month: month),
          onDayChanged: (day) => _setBirthDate(day: day),
          onYearChanged: (year) => _setBirthDate(year: year),
        ),
      ],
    );
  }

  Widget _heightStep() {
    final l10n = context.l10n;
    final heightCm = _heightInCm() ?? 170;
    final value = _heightMetric
        ? (double.tryParse(_heightController.text.trim()) ?? heightCm)
        : (heightCm / 2.54).clamp(48, 90).toDouble();
    return _WizardQuestionPage(
      title: l10n.calorieWizardHeightTitle,
      centerTitle: true,
      children: [
        Center(
          child: _CompactUnitToggle(
            firstKey: const ValueKey('calorie_wizard_metric_units'),
            secondKey: const ValueKey('calorie_wizard_us_units'),
            firstLabel: 'cm',
            secondLabel: 'ft',
            firstSelected: _heightMetric,
            onFirstTap: () => _setHeightUnit(true),
            onSecondTap: () => _setHeightUnit(false),
          ),
        ),
        const SizedBox(height: 42),
        _MeasurementValueDisplay(
          value: _heightMetric
              ? value.toStringAsFixed(1)
              : _formatFeetAndInches(value),
          unit: _heightMetric ? 'cm' : 'ft',
        ),
        const SizedBox(height: FreshSpacing.xl),
        _SlidingRulerScale(
          key: const ValueKey('calorie_wizard_height_ruler'),
          value: value,
          min: _heightMetric ? 120 : 48,
          max: _heightMetric ? 230 : 90,
          valueStep: 1,
          tickStep: 1,
          visibleHalfRange: _heightMetric ? 15 : 6,
          majorEvery: _heightMetric ? 10 : 6,
          labelFormatter: _heightMetric
              ? (mark) => mark.round().toString()
              : (mark) => _formatFeetAndInches(mark),
          onChanged: _setHeightFromRuler,
        ),
      ],
    );
  }

  Widget _weightStep() {
    final l10n = context.l10n;
    final weightKg = _weightInKg() ?? 70;
    final value = _weightMetric
        ? (double.tryParse(_weightController.text.trim()) ?? weightKg)
        : (weightKg / 0.45359237).clamp(78, 551).toDouble();
    return _WizardQuestionPage(
      title: l10n.calorieWizardWeightTitle,
      centerTitle: true,
      children: [
        Center(
          child: _CompactUnitToggle(
            firstKey: const ValueKey('calorie_wizard_metric_units'),
            secondKey: const ValueKey('calorie_wizard_us_units'),
            firstLabel: 'kg',
            secondLabel: 'lb',
            firstSelected: _weightMetric,
            onFirstTap: () => _setWeightUnit(true),
            onSecondTap: () => _setWeightUnit(false),
          ),
        ),
        const SizedBox(height: 42),
        _MeasurementValueDisplay(
          value: _weightMetric
              ? value.toStringAsFixed(1)
              : value.round().toString(),
          unit: _weightMetric ? 'kg' : 'lb',
        ),
        const SizedBox(height: FreshSpacing.xl),
        _SlidingRulerScale(
          key: const ValueKey('calorie_wizard_weight_ruler'),
          value: value,
          min: _weightMetric ? 35 : 78,
          max: _weightMetric ? 250 : 551,
          valueStep: _weightMetric ? 0.5 : 1,
          tickStep: 1,
          visibleHalfRange: _weightMetric ? 15 : 30,
          majorEvery: _weightMetric ? 10 : 20,
          labelFormatter: (mark) => mark.round().toString(),
          onChanged: _setWeightFromRuler,
        ),
      ],
    );
  }

  Widget _goalStep() {
    final l10n = context.l10n;
    return _WizardQuestionPage(
      title: l10n.calorieWizardGoalTitle,
      subtitle: l10n.calorieWizardGoalSubtitle,
      children: [
        for (final option in _goalOptions(l10n))
          Padding(
            padding: const EdgeInsets.only(bottom: FreshSpacing.md),
            child: _WizardChoiceCard(
              key: ValueKey('calorie_wizard_goal_${option.value}'),
              icon: option.icon,
              title: option.label,
              message: option.message,
              selected: _goal == option.value,
              onTap: () => setState(() {
                _goal = option.value;
                _error = null;
              }),
            ),
          ),
      ],
    );
  }

  Widget _paceStep() {
    final l10n = context.l10n;
    final isLoss = _goal == 'lose_fat';
    final paceOptions =
        isLoss ? _lossPaceOptions(l10n) : _gainPaceOptions(l10n);
    return _WizardQuestionPage(
      title: isLoss
          ? l10n.calorieWizardLossPaceTitle
          : l10n.calorieWizardGainPaceTitle,
      subtitle: l10n.calorieWizardPaceSubtitle,
      children: [
        for (final option in paceOptions)
          Padding(
            padding: const EdgeInsets.only(bottom: FreshSpacing.md),
            child: _WizardChoiceCard(
              key: ValueKey('calorie_wizard_pace_${option.value}'),
              icon: option.icon,
              title: option.label,
              message: option.message,
              selected: _selectedPace == option.value,
              onTap: () => setState(() {
                if (isLoss) {
                  _lossPace = option.value;
                } else {
                  _gainPace = option.value;
                }
                _error = null;
              }),
            ),
          ),
      ],
    );
  }

  Widget _activityStep() {
    final l10n = context.l10n;
    return _WizardQuestionPage(
      title: l10n.calorieWizardActivityTitle,
      subtitle: l10n.calorieWizardActivitySubtitle,
      children: [
        for (final option in _activityOptions(l10n))
          Padding(
            padding: const EdgeInsets.only(bottom: FreshSpacing.md),
            child: _WizardChoiceCard(
              key: ValueKey('calorie_wizard_activity_${option.value}'),
              icon: option.icon,
              title: option.label,
              message: option.message,
              selected: _activityLevel == option.value,
              onTap: () => setState(() {
                _activityLevel = option.value;
                _error = null;
              }),
            ),
          ),
      ],
    );
  }

  Widget _resultStep() {
    final estimate = _estimate;
    if (estimate == null) return const _LoadingPlanStep();
    return _ResultPlanStep(estimate: estimate);
  }

  String? get _selectedPace {
    if (_goal == 'lose_fat') return _lossPace;
    if (_goal == 'gain_muscle') return _gainPace;
    return null;
  }

  Future<void> _primaryAction() async {
    if (_isResultStep) {
      if (_estimate != null) Navigator.of(context).pop(_estimate);
      return;
    }
    final step = _activeStep;
    if (!_validateCurrentStep(step)) return;
    if (step == _WizardStep.activity) {
      await _calculateEstimate();
      return;
    }
    setState(() {
      _error = null;
      _stepIndex += 1;
    });
  }

  void _goBack() {
    if (_isLoading) return;
    if (_isResultStep) {
      setState(() {
        _error = null;
        _estimate = null;
        _stepIndex = math.max(0, _questionSteps.length - 1);
      });
      return;
    }
    if (_stepIndex == 0) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _error = null;
      _stepIndex -= 1;
    });
  }

  bool _validateCurrentStep(_WizardStep step) {
    switch (step) {
      case _WizardStep.age:
        final age = _ageFromBirthDate(_birthDate);
        if (age < 18 || age > 100) {
          setState(
              () => _error = context.l10n.calorieWizardBirthdayValidationError);
          return false;
        }
        return true;
      case _WizardStep.height:
        final heightCm = _heightMetric
            ? double.tryParse(_heightController.text.trim())
            : _heightInCm();
        if (heightCm == null || heightCm < 120 || heightCm > 230) {
          setState(
              () => _error = context.l10n.calorieWizardHeightValidationError);
          return false;
        }
        return true;
      case _WizardStep.weight:
        final weightKg = _weightMetric
            ? double.tryParse(_weightController.text.trim())
            : _weightInKg();
        if (weightKg == null || weightKg < 35 || weightKg > 250) {
          setState(
              () => _error = context.l10n.calorieWizardWeightValidationError);
          return false;
        }
        return true;
      case _WizardStep.sex:
      case _WizardStep.goal:
      case _WizardStep.pace:
      case _WizardStep.activity:
      case _WizardStep.result:
        return true;
    }
  }

  Future<void> _calculateEstimate() async {
    final profile = _profileValues();
    if (profile == null) {
      setState(() => _error = context.l10n.calorieWizardProfileValidationError);
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final estimateFuture = widget.estimateCalories(
        age: profile.age,
        sex: _sex,
        heightCm: profile.heightCm,
        weightKg: profile.weightKg,
        activityLevel: _activityLevel,
        goal: _goal,
        pace: _selectedPace,
      );
      final estimate = await estimateFuture;
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      if (!mounted) return;
      setState(() {
        _estimate = estimate;
        _stepIndex = _questionSteps.length;
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = userVisibleErrorMessage(
          error,
          context: UserErrorContext.calorieEstimate,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  _ProfileValues? _profileValues() {
    final age = _ageFromBirthDate(_birthDate);
    final heightCm = _heightMetric
        ? double.tryParse(_heightController.text.trim())
        : _heightInCm();
    final weightKg = _weightMetric
        ? double.tryParse(_weightController.text.trim())
        : _weightInKg();
    if (age < 18 ||
        age > 100 ||
        heightCm == null ||
        heightCm < 120 ||
        heightCm > 230 ||
        weightKg == null ||
        weightKg < 35 ||
        weightKg > 250) {
      return null;
    }
    return _ProfileValues(age: age, heightCm: heightCm, weightKg: weightKg);
  }

  double? _heightInCm() {
    final feet = double.tryParse(_feetController.text.trim());
    final inches = double.tryParse(_inchesController.text.trim());
    if (feet == null || inches == null) return null;
    return (feet * 12 + inches) * 2.54;
  }

  double? _weightInKg() {
    final pounds = double.tryParse(_poundsController.text.trim());
    if (pounds == null) return null;
    return pounds * 0.45359237;
  }
}

class _ProfileValues {
  const _ProfileValues({
    required this.age,
    required this.heightCm,
    required this.weightKg,
  });

  final int age;
  final double heightCm;
  final double weightKg;
}

class _WizardOption {
  const _WizardOption({
    required this.value,
    required this.label,
    required this.message,
    required this.icon,
  });

  final String value;
  final String label;
  final String message;
  final IconData icon;
}

List<_WizardOption> _activityOptions(AppLocalizations l10n) => [
      _WizardOption(
        value: 'sedentary',
        label: l10n.calorieWizardActivitySedentary,
        message: l10n.calorieWizardActivitySedentaryMessage,
        icon: Icons.weekend_rounded,
      ),
      _WizardOption(
        value: 'lightly_active',
        label: l10n.calorieWizardActivityLightlyActive,
        message: l10n.calorieWizardActivityLightlyActiveMessage,
        icon: Icons.directions_walk_rounded,
      ),
      _WizardOption(
        value: 'moderately_active',
        label: l10n.calorieWizardActivityModeratelyActive,
        message: l10n.calorieWizardActivityModeratelyActiveMessage,
        icon: Icons.fitness_center_rounded,
      ),
      _WizardOption(
        value: 'very_active',
        label: l10n.calorieWizardActivityVeryActive,
        message: l10n.calorieWizardActivityVeryActiveMessage,
        icon: Icons.local_fire_department_rounded,
      ),
      _WizardOption(
        value: 'extra_active',
        label: l10n.calorieWizardActivitySuperActive,
        message: l10n.calorieWizardActivitySuperActiveMessage,
        icon: Icons.speed_rounded,
      ),
    ];

const _calorieWizardCardShadow = [
  BoxShadow(
    color: Color(0x08080907),
    blurRadius: 20,
    offset: Offset(0, 7),
  ),
];

List<_WizardOption> _goalOptions(AppLocalizations l10n) => [
      _WizardOption(
        value: 'lose_fat',
        label: l10n.calorieWizardGoalLoseWeight,
        message: l10n.calorieWizardGoalLoseWeightMessage,
        icon: Icons.flag_rounded,
      ),
      _WizardOption(
        value: 'gain_muscle',
        label: l10n.calorieWizardGoalGainMuscle,
        message: l10n.calorieWizardGoalGainMuscleMessage,
        icon: Icons.fitness_center_rounded,
      ),
      _WizardOption(
        value: 'maintain',
        label: l10n.calorieWizardGoalMaintainWeight,
        message: l10n.calorieWizardGoalMaintainWeightMessage,
        icon: Icons.balance_rounded,
      ),
    ];

List<_WizardOption> _lossPaceOptions(AppLocalizations l10n) => [
      _WizardOption(
        value: 'slow',
        label: l10n.calorieWizardPaceSlow,
        message: l10n.calorieWizardPaceSlowMessage,
        icon: Icons.eco_rounded,
      ),
      _WizardOption(
        value: 'moderate',
        label: l10n.calorieWizardPaceModerate,
        message: l10n.calorieWizardPaceModerateMessage,
        icon: Icons.check_circle_outline_rounded,
      ),
      _WizardOption(
        value: 'aggressive',
        label: l10n.calorieWizardPaceAggressive,
        message: l10n.calorieWizardLossPaceAggressiveMessage,
        icon: Icons.bolt_rounded,
      ),
    ];

List<_WizardOption> _gainPaceOptions(AppLocalizations l10n) => [
      _WizardOption(
        value: 'lean',
        label: l10n.calorieWizardPaceLean,
        message: l10n.calorieWizardPaceLeanMessage,
        icon: Icons.eco_rounded,
      ),
      _WizardOption(
        value: 'standard',
        label: l10n.calorieWizardPaceStandard,
        message: l10n.calorieWizardPaceStandardMessage,
        icon: Icons.check_circle_outline_rounded,
      ),
      _WizardOption(
        value: 'aggressive',
        label: l10n.calorieWizardPaceAggressive,
        message: l10n.calorieWizardGainPaceAggressiveMessage,
        icon: Icons.bolt_rounded,
      ),
    ];

class _StepButton extends StatelessWidget {
  const _StepButton({
    super.key,
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FreshIconButton(
      icon: icon,
      tooltip: icon == Icons.add_rounded
          ? l10n.calorieTargetIncreaseTooltip
          : l10n.calorieTargetDecreaseTooltip,
      onPressed: onTap,
      backgroundColor: context.freshPalette.surface,
    );
  }
}

class _WizardTopBar extends StatelessWidget {
  const _WizardTopBar({
    required this.currentStep,
    required this.totalSteps,
    required this.progress,
    required this.canGoBack,
    required this.onClose,
    required this.onBack,
  });

  final int currentStep;
  final int totalSteps;
  final double progress;
  final bool canGoBack;
  final VoidCallback onClose;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    final normalizedProgress = progress.clamp(0.0, 1.0).toDouble();
    return Row(
      children: [
        FreshIconButton(
          key: ValueKey(canGoBack
              ? 'calorie_wizard_back_button'
              : 'calorie_wizard_close_button'),
          icon: canGoBack ? Icons.arrow_back_rounded : Icons.close_rounded,
          tooltip: canGoBack
              ? context.l10n.calorieWizardBackTooltip
              : context.l10n.calorieWizardCloseTooltip,
          onPressed: canGoBack ? onBack : onClose,
          backgroundColor: palette.surface,
        ),
        const SizedBox(width: FreshSpacing.md),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: normalizedProgress,
              backgroundColor: palette.surfaceMuted,
              color: palette.lime,
            ),
          ),
        ),
        const SizedBox(width: FreshSpacing.md),
        Text(
          '$currentStep/$totalSteps',
          style: textTheme.labelLarge?.copyWith(
            color: palette.inkMuted,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _WizardQuestionPage extends StatelessWidget {
  const _WizardQuestionPage({
    required this.title,
    this.subtitle,
    this.centerTitle = false,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final bool centerTitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: FreshSpacing.md),
          Text(
            title,
            textAlign: centerTitle ? TextAlign.center : TextAlign.start,
            style: textTheme.headlineSmall?.copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w800,
              height: 1.05,
            ),
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: FreshSpacing.sm),
            Text(
              subtitle!,
              textAlign: centerTitle ? TextAlign.center : TextAlign.start,
              style: textTheme.bodyMedium?.copyWith(
                color: palette.inkMuted,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: FreshSpacing.xl),
          ...children,
          const SizedBox(height: FreshSpacing.lg),
        ],
      ),
    );
  }
}

class _WizardChoiceCard extends StatelessWidget {
  const _WizardChoiceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
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
            boxShadow: _calorieWizardCardShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: selected ? palette.limeWash : palette.surfaceSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: selected ? palette.limeDeep : palette.ink,
                  size: 22,
                ),
              ),
              const SizedBox(width: FreshSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleSmall?.copyWith(
                        color: palette.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      message,
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
                    ? Icon(
                        Icons.check_rounded,
                        color: palette.ink,
                        size: 18,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BirthdayWheelPicker extends StatelessWidget {
  const _BirthdayWheelPicker({
    required this.selectedDate,
    required this.years,
    required this.monthController,
    required this.dayController,
    required this.yearController,
    required this.onMonthChanged,
    required this.onDayChanged,
    required this.onYearChanged,
  });

  final DateTime selectedDate;
  final List<int> years;
  final FixedExtentScrollController monthController;
  final FixedExtentScrollController dayController;
  final FixedExtentScrollController yearController;
  final ValueChanged<int> onMonthChanged;
  final ValueChanged<int> onDayChanged;
  final ValueChanged<int> onYearChanged;

  int get _dayCount =>
      DateTime(selectedDate.year, selectedDate.month + 1, 0).day;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    return SizedBox(
      height: 340,
      child: Column(
        children: [
          Row(
            children: [
              _BirthdayWheelLabel(
                text: context.l10n.calorieWizardBirthdayMonth,
                color: palette.inkMuted,
              ),
              _BirthdayWheelLabel(
                text: context.l10n.calorieWizardBirthdayDay,
                color: palette.inkMuted,
              ),
              _BirthdayWheelLabel(
                text: context.l10n.calorieWizardBirthdayYear,
                color: palette.inkMuted,
              ),
            ],
          ),
          const SizedBox(height: FreshSpacing.sm),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  height: 52,
                  decoration: BoxDecoration(
                    border: Border.symmetric(
                      horizontal: BorderSide(color: palette.limeSoft),
                    ),
                  ),
                ),
                Row(
                  children: [
                    _BirthdayWheel(
                      key: const ValueKey('calorie_wizard_birth_month_wheel'),
                      controller: monthController,
                      values: List<int>.generate(12, (index) => index + 1),
                      selectedValue: selectedDate.month,
                      format: (value) => value.toString().padLeft(2, '0'),
                      onChanged: onMonthChanged,
                    ),
                    _BirthdayWheel(
                      key: const ValueKey('calorie_wizard_birth_day_wheel'),
                      controller: dayController,
                      values:
                          List<int>.generate(_dayCount, (index) => index + 1),
                      selectedValue: selectedDate.day,
                      format: (value) => value.toString().padLeft(2, '0'),
                      onChanged: onDayChanged,
                    ),
                    _BirthdayWheel(
                      key: const ValueKey('calorie_wizard_birth_year_wheel'),
                      controller: yearController,
                      values: years,
                      selectedValue: selectedDate.year,
                      format: (value) => value.toString(),
                      onChanged: onYearChanged,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BirthdayWheelLabel extends StatelessWidget {
  const _BirthdayWheelLabel({
    required this.text,
    required this.color,
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _BirthdayWheel extends StatelessWidget {
  const _BirthdayWheel({
    super.key,
    required this.controller,
    required this.values,
    required this.selectedValue,
    required this.format,
    required this.onChanged,
  });

  final FixedExtentScrollController controller;
  final List<int> values;
  final int selectedValue;
  final String Function(int value) format;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    return Expanded(
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        physics: const FixedExtentScrollPhysics(),
        itemExtent: 46,
        diameterRatio: 8,
        perspective: 0.001,
        overAndUnderCenterOpacity: 0.78,
        onSelectedItemChanged: (index) {
          if (index >= 0 && index < values.length) onChanged(values[index]);
        },
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: values.length,
          builder: (context, index) {
            final value = values[index];
            final selected = value == selectedValue;
            return Center(
              child: Text(
                format(value),
                style:
                    (selected ? textTheme.headlineSmall : textTheme.titleLarge)
                        ?.copyWith(
                  color: selected ? palette.lime : palette.inkMuted,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CompactUnitToggle extends StatelessWidget {
  const _CompactUnitToggle({
    required this.firstKey,
    required this.secondKey,
    required this.firstLabel,
    required this.secondLabel,
    required this.firstSelected,
    required this.onFirstTap,
    required this.onSecondTap,
  });

  final Key firstKey;
  final Key secondKey;
  final String firstLabel;
  final String secondLabel;
  final bool firstSelected;
  final VoidCallback onFirstTap;
  final VoidCallback onSecondTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CompactUnitSegment(
          key: firstKey,
          label: firstLabel,
          selected: firstSelected,
          onTap: onFirstTap,
        ),
        const SizedBox(width: FreshSpacing.sm),
        _CompactUnitSegment(
          key: secondKey,
          label: secondLabel,
          selected: !firstSelected,
          onTap: onSecondTap,
        ),
      ],
    );
  }
}

class _CompactUnitSegment extends StatelessWidget {
  const _CompactUnitSegment({
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
          curve: Curves.easeOutCubic,
          width: 54,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? palette.lime : palette.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? palette.lime : palette.ruleSoft,
            ),
            boxShadow: selected
                ? const []
                : const [
                    BoxShadow(
                      color: Color(0x14080907),
                      blurRadius: 16,
                      offset: Offset(0, 8),
                    ),
                  ],
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

class _MeasurementValueDisplay extends StatelessWidget {
  const _MeasurementValueDisplay({
    required this.value,
    required this.unit,
  });

  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          children: [
            TextSpan(
              text: value,
              style: textTheme.displayMedium?.copyWith(
                color: palette.ink,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            TextSpan(
              text: ' $unit',
              style: textTheme.titleMedium?.copyWith(
                color: palette.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlidingRulerScale extends StatefulWidget {
  const _SlidingRulerScale({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.valueStep,
    required this.tickStep,
    required this.visibleHalfRange,
    required this.majorEvery,
    required this.labelFormatter,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final double valueStep;
  final double tickStep;
  final double visibleHalfRange;
  final double majorEvery;
  final String Function(double value) labelFormatter;
  final ValueChanged<double> onChanged;

  @override
  State<_SlidingRulerScale> createState() => _SlidingRulerScaleState();
}

class _SlidingRulerScaleState extends State<_SlidingRulerScale> {
  double? _dragStartValue;
  double _dragOffset = 0;
  double? _visualValue;
  double? _lastCommittedValue;

  double _snap(double rawValue) {
    final snapped = widget.min +
        (((rawValue - widget.min) / widget.valueStep).round() *
            widget.valueStep);
    return snapped.clamp(widget.min, widget.max).toDouble();
  }

  double _clamp(double rawValue) {
    return rawValue.clamp(widget.min, widget.max).toDouble();
  }

  void _commitValue(double rawValue) {
    final snapped = _snap(rawValue);
    if (snapped == _lastCommittedValue || snapped == widget.value) return;
    _lastCommittedValue = snapped;
    widget.onChanged(snapped);
  }

  @override
  void didUpdateWidget(covariant _SlidingRulerScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_dragStartValue == null) {
      _visualValue = null;
      _lastCommittedValue = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final displayValue = _visualValue ?? widget.value;
    return SizedBox(
      height: 104,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = math.max(1.0, constraints.maxWidth);
          final unitsPerPixel = (widget.visibleHalfRange * 2) / width;

          void updateFromTap(double dx) {
            final center = width / 2;
            _commitValue(widget.value + ((dx - center) * unitsPerPixel));
          }

          void updateFromDrag(double dx) {
            _dragOffset += dx;
            final rawValue = _clamp((_dragStartValue ?? widget.value) -
                (_dragOffset * unitsPerPixel));
            setState(() => _visualValue = rawValue);
            _commitValue(rawValue);
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => updateFromTap(details.localPosition.dx),
            onHorizontalDragStart: (_) {
              _dragStartValue = widget.value;
              _dragOffset = 0;
              _visualValue = widget.value;
              _lastCommittedValue = widget.value;
            },
            onHorizontalDragUpdate: (details) =>
                updateFromDrag(details.delta.dx),
            onHorizontalDragEnd: (_) {
              final rawValue = _visualValue ?? widget.value;
              final snapped = _snap(rawValue);
              if (snapped != widget.value) widget.onChanged(snapped);
              setState(() {
                _dragStartValue = null;
                _dragOffset = 0;
                _visualValue = null;
                _lastCommittedValue = null;
              });
            },
            onHorizontalDragCancel: () {
              setState(() {
                _dragStartValue = null;
                _dragOffset = 0;
                _visualValue = null;
                _lastCommittedValue = null;
              });
            },
            child: CustomPaint(
              painter: _SlidingRulerPainter(
                value: displayValue,
                min: widget.min,
                max: widget.max,
                tickStep: widget.tickStep,
                visibleHalfRange: widget.visibleHalfRange,
                majorEvery: widget.majorEvery,
                labelFormatter: widget.labelFormatter,
                activeColor: palette.lime,
                tickColor: palette.rule,
                majorTickColor: palette.inkMuted.withValues(alpha: 0.48),
                labelColor: palette.inkMuted,
              ),
              child: const SizedBox.expand(),
            ),
          );
        },
      ),
    );
  }
}

class _SlidingRulerPainter extends CustomPainter {
  const _SlidingRulerPainter({
    required this.value,
    required this.min,
    required this.max,
    required this.tickStep,
    required this.visibleHalfRange,
    required this.majorEvery,
    required this.labelFormatter,
    required this.activeColor,
    required this.tickColor,
    required this.majorTickColor,
    required this.labelColor,
  });

  final double value;
  final double min;
  final double max;
  final double tickStep;
  final double visibleHalfRange;
  final double majorEvery;
  final String Function(double value) labelFormatter;
  final Color activeColor;
  final Color tickColor;
  final Color majorTickColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final visibleMin = math.max(min, value - visibleHalfRange);
    final visibleMax = math.min(max, value + visibleHalfRange);
    final unitsPerPixel = (visibleHalfRange * 2) / math.max(1.0, size.width);
    final startTick = (visibleMin / tickStep).floor() * tickStep;
    final endTick = (visibleMax / tickStep).ceil() * tickStep;

    final tickPaint = Paint()
      ..color = tickColor
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    final majorPaint = Paint()
      ..color = majorTickColor
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final activePaint = Paint()
      ..color = activeColor
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    const tickTop = 12.0;
    const labelTop = 66.0;
    for (var tick = startTick; tick <= endTick + 0.001; tick += tickStep) {
      if (tick < min || tick > max) continue;
      final x = centerX + ((tick - value) / unitsPerPixel);
      if (x < -16 || x > size.width + 16) continue;
      final roundedTick = tick.roundToDouble();
      final isMajor = (roundedTick % majorEvery).abs() < 0.001;
      final tickHeight = isMajor ? 42.0 : 28.0;
      canvas.drawLine(
        Offset(x, tickTop),
        Offset(x, tickTop + tickHeight),
        isMajor ? majorPaint : tickPaint,
      );
      if (isMajor) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: labelFormatter(roundedTick),
            style: TextStyle(
              color: labelColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(canvas, Offset(x - textPainter.width / 2, labelTop));
      }
    }

    canvas.drawLine(
      Offset(centerX, tickTop),
      Offset(centerX, tickTop + 64),
      activePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SlidingRulerPainter oldDelegate) {
    return value != oldDelegate.value ||
        min != oldDelegate.min ||
        max != oldDelegate.max ||
        activeColor != oldDelegate.activeColor ||
        tickColor != oldDelegate.tickColor ||
        majorTickColor != oldDelegate.majorTickColor ||
        labelColor != oldDelegate.labelColor;
  }
}

class _LoadingPlanStep extends StatelessWidget {
  const _LoadingPlanStep();

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              l10n.calorieWizardLoadingTitle,
              textAlign: TextAlign.center,
              style: textTheme.headlineSmall?.copyWith(
                color: palette.ink,
                fontWeight: FontWeight.w800,
                height: 1.08,
              ),
            ),
            const SizedBox(height: FreshSpacing.xxl),
            TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 850),
              curve: Curves.easeOutCubic,
              tween: Tween<double>(begin: 0, end: 1),
              builder: (context, value, child) {
                return _ProgressRing(
                  progress: value,
                  size: 220,
                  center: Text(
                    '${(value * 100).round()}%',
                    style: textTheme.displaySmall?.copyWith(
                      color: palette.ink,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: FreshSpacing.xxl),
            Text(
              l10n.calorieWizardLoadingMessage,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: palette.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultPlanStep extends StatelessWidget {
  const _ResultPlanStep({required this.estimate});

  final CalorieEstimate estimate;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: FreshSpacing.md),
          Text(
            l10n.calorieWizardResultTitle,
            textAlign: TextAlign.center,
            style: textTheme.headlineSmall?.copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w800,
              height: 1.08,
            ),
          ),
          const SizedBox(height: FreshSpacing.xxl),
          Center(
            child: _ProgressRing(
              progress: 1,
              size: 238,
              center: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${estimate.targetCalories}',
                    key: const ValueKey('calorie_wizard_target_value'),
                    style: textTheme.displaySmall?.copyWith(
                      color: palette.ink,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    l10n.commonKcal,
                    style: textTheme.titleMedium?.copyWith(
                      color: palette.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: FreshSpacing.xxl),
          DecoratedBox(
            key: const ValueKey('calorie_wizard_result_card'),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(FreshRadii.lg),
              boxShadow: _calorieWizardCardShadow,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _ResultLine(
                    label: l10n.calorieWizardResultBmr,
                    value: l10n.caloriesValue(estimate.bmr),
                  ),
                  _ResultLine(
                    label: l10n.calorieWizardResultMaintenance,
                    value: l10n.caloriesValue(estimate.maintenanceCalories),
                  ),
                  _ResultLine(
                    label: l10n.calorieWizardResultTargetRange,
                    value: l10n.calorieWizardTargetRangeValue(
                      estimate.recommendedRangeMin,
                      estimate.recommendedRangeMax,
                    ),
                  ),
                  _ResultLine(
                    label: l10n.calorieWizardResultAdjustment,
                    value: l10n.caloriesValue(estimate.adjustmentCalories),
                  ),
                ],
              ),
            ),
          ),
          if (estimate.warnings.isNotEmpty) ...[
            const SizedBox(height: FreshSpacing.md),
            for (final warning in estimate.warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: FreshSpacing.sm),
                child: FreshStatusBanner(
                  icon: Icons.info_outline_rounded,
                  title: l10n.calorieWizardEstimateNoteTitle,
                  message: warning,
                  color: FreshColors.orange,
                ),
              ),
          ],
          if (estimate.explanation.isNotEmpty) ...[
            const SizedBox(height: FreshSpacing.md),
            Text(
              estimate.explanation,
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: palette.inkMuted,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: FreshSpacing.lg),
        ],
      ),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({
    required this.progress,
    required this.size,
    required this.center,
  });

  final double progress;
  final double size;
  final Widget center;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _ProgressRingPainter(
              progress: progress,
              backgroundColor: Colors.white,
              foregroundColor: palette.lime,
              innerColor: palette.limeWash,
            ),
          ),
          center,
        ],
      ),
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  const _ProgressRingPainter({
    required this.progress,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.innerColor,
  });

  final double progress;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color innerColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    final strokeWidth = radius * 0.17;
    final ringRect = Rect.fromCircle(
      center: center,
      radius: radius - strokeWidth / 2,
    );
    final outerPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final activePaint = Paint()
      ..color = foregroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final innerPaint = Paint()
      ..color = innerColor
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius - strokeWidth - 4, innerPaint);
    canvas.drawArc(ringRect, 0, math.pi * 2, false, outerPaint);
    canvas.drawArc(
      ringRect,
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0.0, 1.0).toDouble(),
      false,
      activePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter oldDelegate) {
    return progress != oldDelegate.progress ||
        backgroundColor != oldDelegate.backgroundColor ||
        foregroundColor != oldDelegate.foregroundColor ||
        innerColor != oldDelegate.innerColor;
  }
}

class _ResultLine extends StatelessWidget {
  const _ResultLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    return Padding(
      padding: const EdgeInsets.only(bottom: FreshSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: palette.inkMuted),
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
