import 'package:cal_tracker_mobile/app/theme.dart';
import 'package:cal_tracker_mobile/domain/models/nutrition_models.dart';
import 'package:cal_tracker_mobile/l10n/generated/app_localizations.dart';
import 'package:cal_tracker_mobile/ui/features/dashboard/views/calorie_target_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('calorie wizard shows birthday wheels and measurement rulers', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(_wizard()));
    await tester.pumpAndSettle();

    await _tapNext(tester);

    expect(find.text("When's your birthday?"), findsOneWidget);
    expect(
      find.byKey(const ValueKey('calorie_wizard_birth_month_wheel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('calorie_wizard_birth_day_wheel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('calorie_wizard_birth_year_wheel')),
      findsOneWidget,
    );

    await _tapNext(tester);

    expect(find.text('How tall are you?'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('calorie_wizard_height_ruler')),
      findsOneWidget,
    );
    expect(find.text('cm'), findsOneWidget);
    expect(find.text('ft'), findsOneWidget);

    await _tapNext(tester);

    expect(find.text("What's your current weight?"), findsOneWidget);
    expect(
      find.byKey(const ValueKey('calorie_wizard_weight_ruler')),
      findsOneWidget,
    );
    expect(find.text('kg'), findsOneWidget);
    expect(find.text('lb'), findsOneWidget);
  });

  testWidgets('measurement rulers expose slider semantics actions', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();

    await tester.pumpWidget(_testApp(_wizard()));
    await tester.pumpAndSettle();
    await _tapNext(tester); // Sex.
    await _tapNext(tester); // Birthday.

    expect(find.text('How tall are you?'), findsOneWidget);
    final rulerData = tester
        .getSemantics(
          find.byKey(const ValueKey('calorie_wizard_height_ruler_semantics')),
        )
        .getSemanticsData();
    expect(rulerData.label, 'How tall are you?');
    expect(rulerData.value, '170.0 cm');
    expect(rulerData.flagsCollection.isSlider, isTrue);
    expect(rulerData.hasAction(SemanticsAction.increase), isTrue);
    expect(rulerData.hasAction(SemanticsAction.decrease), isTrue);
    semanticsHandle.dispose();
  });

  testWidgets(
    'calorie wizard derives age and reaches 100 percent while loading',
    (tester) async {
      _EstimateInput? estimateInput;

      await tester.pumpWidget(
        _testApp(
          _wizard(
            estimateCalories: ({
              required int age,
              required String sex,
              required double heightCm,
              required double weightKg,
              required String activityLevel,
              required String goal,
              String? pace,
            }) async {
              estimateInput = _EstimateInput(
                age: age,
                heightCm: heightCm,
                weightKg: weightKg,
              );
              return _estimate;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _tapNext(tester); // Sex.
      await _tapNext(tester); // Birthday.
      await _tapNext(tester); // Height.
      await _tapNext(tester); // Weight.
      await _tapNext(tester); // Goal.

      await tester.tap(
        find.byKey(const ValueKey('calorie_wizard_activity_lightly_active')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('calorie_wizard_next_button')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));

      expect(find.text('100%'), findsOneWidget);
      expect(estimateInput?.age, 30);
      expect(estimateInput?.heightCm, 170);
      expect(estimateInput?.weightKg, 70);

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('calorie_wizard_target_value')),
        findsOneWidget,
      );
      expect(find.text('1620'), findsOneWidget);
    },
  );

  testWidgets('calorie wizard no longer shows improve nutrition goal', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(_wizard()));
    await tester.pumpAndSettle();

    await _tapNext(tester); // Sex.
    await _tapNext(tester); // Birthday.
    await _tapNext(tester); // Height.
    await _tapNext(tester); // Weight.

    expect(find.text('Lose Weight'), findsOneWidget);
    expect(find.text('Maintain Weight'), findsOneWidget);
    expect(find.text('Gain Muscle'), findsOneWidget);
    expect(find.text('Improve Nutrition'), findsNothing);
    expect(
      find.byKey(const ValueKey('calorie_wizard_goal_recomposition')),
      findsNothing,
    );
  });

  testWidgets('calorie target setup and wizard render Spanish strings', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        CalorieTargetSheet(
          initialValue: 2200,
          estimateCalories: ({
            required int age,
            required String sex,
            required double heightCm,
            required double weightKg,
            required String activityLevel,
            required String goal,
            String? pace,
          }) async =>
              _estimate,
        ),
        locale: const Locale('es'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Configura tus calorías diarias'), findsOneWidget);
    expect(find.text('¿No sabes cuántas calorías necesitas?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('calorie_calculator_link')));
    await tester.pumpAndSettle();

    expect(find.text('¿Cuál es tu sexo biológico?'), findsOneWidget);
    expect(find.text('Continuar'), findsOneWidget);

    await _tapNext(tester); // Sex.
    expect(find.text('¿Cuándo es tu cumpleaños?'), findsOneWidget);
    await _tapNext(tester); // Birthday.
    await _tapNext(tester); // Height.
    await _tapNext(tester); // Weight.
    await _tapNext(tester); // Goal.

    expect(find.text('¿Cuál es tu nivel de actividad?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('calorie_wizard_next_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();

    expect(find.text('Usar esta estimación'), findsOneWidget);
  });
}

Widget _wizard({
  Future<CalorieEstimate> Function({
    required int age,
    required String sex,
    required double heightCm,
    required double weightKg,
    required String activityLevel,
    required String goal,
    String? pace,
  })? estimateCalories,
}) {
  return CalorieCalculatorWizard(
    estimateCalories: estimateCalories ??
        ({
          required int age,
          required String sex,
          required double heightCm,
          required double weightKg,
          required String activityLevel,
          required String goal,
          String? pace,
        }) async =>
            _estimate,
  );
}

Widget _testApp(Widget child, {Locale? locale}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildLightTheme(),
    home: Scaffold(body: child),
  );
}

Future<void> _tapNext(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('calorie_wizard_next_button')));
  await tester.pumpAndSettle();
}

class _EstimateInput {
  const _EstimateInput({
    required this.age,
    required this.heightCm,
    required this.weightKg,
  });

  final int age;
  final double heightCm;
  final double weightKg;
}

const _estimate = CalorieEstimate(
  bmr: 1620,
  maintenanceCalories: 1920,
  targetCalories: 1620,
  recommendedRangeMin: 1500,
  recommendedRangeMax: 1800,
  activityFactor: 1.2,
  warnings: [],
  explanation: 'Test estimate.',
  adjustmentCalories: 300,
);
