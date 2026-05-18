import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../domain/models/nutrition_models.dart';
import '../../../../l10n/app_localizations_context.dart';
import '../../../core/design_system.dart';

class CalorieTargetSelection {
  const CalorieTargetSelection({
    required this.calories,
    required this.source,
  });

  final int calories;
  final String source;
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
              'Set your daily calories',
              style: textTheme.titleLarge,
            ),
            const SizedBox(height: FreshSpacing.xs),
            Text(
              'Choose the target you want to track each day.',
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
                        suffixText: context.l10n.commonKcal,
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
              child: const Text("Don't know how many calories you need?"),
            ),
            const SizedBox(height: FreshSpacing.lg),
            FilledButton(
              key: const ValueKey('dashboard_save_calorie_target_button'),
              onPressed: _submit,
              child: Text(context.l10n.commonSave),
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
    Navigator.of(context).pop(
      CalorieTargetSelection(
        calories: estimate.targetCalories,
        source: 'calculator',
      ),
    );
  }

  void _submit() {
    final value = int.tryParse(_controller.text.trim());
    if (value == null || value < 800 || value > 10000) {
      setState(() => _error = 'Enter a target from 800 to 10000 Kcal.');
      return;
    }
    Navigator.of(context).pop(
      CalorieTargetSelection(calories: value, source: _source),
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
        padding: EdgeInsets.fromLTRB(20, 10, 20, bottomInset + 16),
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
                  title: 'Check your details',
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
                    _isResultStep ? 'Use this estimate' : 'Continue',
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
    return _WizardQuestionPage(
      title: 'What is your biological sex?',
      subtitle: 'This keeps the calorie estimate aligned with the formula.',
      children: [
        _WizardChoiceCard(
          key: const ValueKey('calorie_wizard_sex_male'),
          icon: Icons.male_rounded,
          title: 'Male',
          message: 'Use the male BMR coefficient.',
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
          title: 'Female',
          message: 'Use the female BMR coefficient.',
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
      title: "When's your birthday?",
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
    final heightCm = _heightInCm() ?? 170;
    final value = _heightMetric
        ? (double.tryParse(_heightController.text.trim()) ?? heightCm)
        : (heightCm / 2.54).clamp(48, 90).toDouble();
    return _WizardQuestionPage(
      title: 'How tall are you?',
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
    final weightKg = _weightInKg() ?? 70;
    final value = _weightMetric
        ? (double.tryParse(_weightController.text.trim()) ?? weightKg)
        : (weightKg / 0.45359237).clamp(78, 551).toDouble();
    return _WizardQuestionPage(
      title: "What's your current weight?",
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
    return _WizardQuestionPage(
      title: 'What is your main goal?',
      subtitle: 'Choose the outcome you want your target to support.',
      children: [
        for (final option in _goalOptions)
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
    final isLoss = _goal == 'lose_fat';
    final paceOptions = isLoss ? _lossPaceOptions : _gainPaceOptions;
    return _WizardQuestionPage(
      title: isLoss
          ? 'How fast do you want to lose weight?'
          : 'How fast do you want to gain weight?',
      subtitle: 'A steadier pace is easier to sustain.',
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
    return _WizardQuestionPage(
      title: 'What is your activity level?',
      subtitle: 'Pick the option that best matches a normal week.',
      children: [
        for (final option in _activityOptions)
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
          setState(() => _error = 'Choose a birthday for ages 18 to 100.');
          return false;
        }
        return true;
      case _WizardStep.height:
        final heightCm = _heightMetric
            ? double.tryParse(_heightController.text.trim())
            : _heightInCm();
        if (heightCm == null || heightCm < 120 || heightCm > 230) {
          setState(() => _error = 'Enter a height from 120 to 230 cm.');
          return false;
        }
        return true;
      case _WizardStep.weight:
        final weightKg = _weightMetric
            ? double.tryParse(_weightController.text.trim())
            : _weightInKg();
        if (weightKg == null || weightKg < 35 || weightKg > 250) {
          setState(() => _error = 'Enter a weight from 35 to 250 kg.');
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
      setState(() =>
          _error = 'Enter age, height, and weight in the expected ranges.');
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
      setState(() => _error = error.toString());
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

const _activityOptions = [
  _WizardOption(
    value: 'sedentary',
    label: 'Sedentary',
    message:
        'Mostly seated, low daily movement, and 0-1 light workouts weekly.',
    icon: Icons.weekend_rounded,
  ),
  _WizardOption(
    value: 'lightly_active',
    label: 'Lightly Active',
    message: 'Regular walks or light exercise 1-3 days per week.',
    icon: Icons.directions_walk_rounded,
  ),
  _WizardOption(
    value: 'moderately_active',
    label: 'Moderately Active',
    message: 'Training 3-5 days per week or a meaningfully active routine.',
    icon: Icons.fitness_center_rounded,
  ),
  _WizardOption(
    value: 'very_active',
    label: 'Very Active',
    message: 'Hard exercise most days or active work plus regular training.',
    icon: Icons.local_fire_department_rounded,
  ),
  _WizardOption(
    value: 'extra_active',
    label: 'Super Active',
    message: 'Athlete-level workload, two-a-days, or demanding physical work.',
    icon: Icons.speed_rounded,
  ),
];

const _goalOptions = [
  _WizardOption(
    value: 'lose_fat',
    label: 'Lose Weight',
    message: 'Estimate a deficit from maintenance.',
    icon: Icons.flag_rounded,
  ),
  _WizardOption(
    value: 'gain_muscle',
    label: 'Gain Muscle',
    message: 'Estimate a controlled calorie surplus.',
    icon: Icons.fitness_center_rounded,
  ),
  _WizardOption(
    value: 'maintain',
    label: 'Maintain Weight',
    message: 'Track around your estimated maintenance.',
    icon: Icons.balance_rounded,
  ),
  _WizardOption(
    value: 'recomposition',
    label: 'Improve Nutrition',
    message: 'Start near maintenance while you train consistently.',
    icon: Icons.auto_graph_rounded,
  ),
];

const _lossPaceOptions = [
  _WizardOption(
    value: 'slow',
    label: 'Slow',
    message: 'Easier to maintain and better for performance.',
    icon: Icons.eco_rounded,
  ),
  _WizardOption(
    value: 'moderate',
    label: 'Moderate',
    message: 'Recommended default for most users.',
    icon: Icons.check_circle_outline_rounded,
  ),
  _WizardOption(
    value: 'aggressive',
    label: 'Aggressive',
    message: 'Larger deficit. Use only if you can recover well.',
    icon: Icons.bolt_rounded,
  ),
];

const _gainPaceOptions = [
  _WizardOption(
    value: 'lean',
    label: 'Lean',
    message: 'Small surplus for minimal fat gain.',
    icon: Icons.eco_rounded,
  ),
  _WizardOption(
    value: 'standard',
    label: 'Standard',
    message: 'Recommended default for most users gaining muscle.',
    icon: Icons.check_circle_outline_rounded,
  ),
  _WizardOption(
    value: 'aggressive',
    label: 'Aggressive',
    message: 'Larger surplus with higher fat-gain risk.',
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
    return FreshIconButton(
      icon: icon,
      tooltip: icon == Icons.add_rounded ? 'Increase' : 'Decrease',
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
          tooltip: canGoBack ? 'Back' : 'Close',
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
              _BirthdayWheelLabel(text: 'Month', color: palette.inkMuted),
              _BirthdayWheelLabel(text: 'Day', color: palette.inkMuted),
              _BirthdayWheelLabel(text: 'Year', color: palette.inkMuted),
            ],
          ),
          const SizedBox(height: FreshSpacing.sm),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  height: 70,
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

class _SlidingRulerScale extends StatelessWidget {
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

  double _snap(double rawValue) {
    final snapped = min + (((rawValue - min) / valueStep).round() * valueStep);
    return snapped.clamp(min, max).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    return SizedBox(
      height: 104,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = math.max(1.0, constraints.maxWidth);
          final unitsPerPixel = (visibleHalfRange * 2) / width;

          void updateFromTap(double dx) {
            final center = width / 2;
            onChanged(_snap(value + ((dx - center) * unitsPerPixel)));
          }

          void updateFromDrag(double dx) {
            onChanged(_snap(value - (dx * unitsPerPixel)));
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => updateFromTap(details.localPosition.dx),
            onHorizontalDragUpdate: (details) =>
                updateFromDrag(details.delta.dx),
            child: CustomPaint(
              painter: _SlidingRulerPainter(
                value: value,
                min: min,
                max: max,
                tickStep: tickStep,
                visibleHalfRange: visibleHalfRange,
                majorEvery: majorEvery,
                labelFormatter: labelFormatter,
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
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Personalizing your calorie plan...',
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
              'Building a target from your profile and activity.',
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
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: FreshSpacing.md),
          Text(
            'Your personalized calorie plan is ready!',
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
                    'Kcal',
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
          FreshCard(
            key: const ValueKey('calorie_wizard_result_card'),
            color: palette.surface,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _ResultLine(
                  label: 'BMR estimate',
                  value: '${estimate.bmr} Kcal',
                ),
                _ResultLine(
                  label: 'Maintenance',
                  value: '${estimate.maintenanceCalories} Kcal',
                ),
                _ResultLine(
                  label: 'Target range',
                  value:
                      '${estimate.recommendedRangeMin}-${estimate.recommendedRangeMax} Kcal',
                ),
                _ResultLine(
                  label: 'Adjustment',
                  value: '${estimate.adjustmentCalories} Kcal',
                ),
              ],
            ),
          ),
          if (estimate.warnings.isNotEmpty) ...[
            const SizedBox(height: FreshSpacing.md),
            for (final warning in estimate.warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: FreshSpacing.sm),
                child: FreshStatusBanner(
                  icon: Icons.info_outline_rounded,
                  title: 'Estimate note',
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
