import 'package:cal_tracker_mobile/app/theme.dart';
import 'package:cal_tracker_mobile/domain/models/macro_distribution.dart';
import 'package:cal_tracker_mobile/ui/features/dashboard/views/macro_distribution_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macro percentage presets derive whole grams', () {
    final grams = gramsFromPercentages(
      2000,
      MacroPreset.highProtein.percentages,
    );

    expect(grams.proteinGrams, 175);
    expect(grams.carbsGrams, 175);
    expect(grams.fatGrams, 67);
    expect(macroCaloriesFromGrams(grams), 2003);
    expect(macroWarningLevel(3), MacroCalorieWarningLevel.none);
    expect(macroWarningLevel(50), MacroCalorieWarningLevel.soft);
    expect(macroWarningLevel(100), MacroCalorieWarningLevel.clear);
  });

  testWidgets('full macro sheet shows presets and personalized card',
      (tester) async {
    await tester.pumpWidget(_testApp(const MacroDistributionSheet(
      calories: 2000,
    )));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('macro_preset_balanced')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('macro_preset_high_protein')),
      findsOneWidget,
    );
    expect(
        find.byKey(const ValueKey('macro_preset_lower_carb')), findsOneWidget);
    expect(find.text('Personalized'), findsOneWidget);
    expect(_iconFor(tester, 'macro_preset_icon_balanced'),
        Icons.pie_chart_rounded);
    expect(_iconFor(tester, 'macro_preset_icon_high_protein'),
        Icons.fitness_center_rounded);
    expect(_iconFor(tester, 'macro_preset_icon_lower_carb'), Icons.eco_rounded);
    expect(_iconFor(tester, 'macro_personalized_icon'), Icons.tune_rounded);
  });

  testWidgets('preset-only picker returns selected preset config',
      (tester) async {
    MacroDistributionConfig? saved;
    await tester.pumpWidget(_testApp(
      Builder(
        builder: (context) => FilledButton(
          onPressed: () async {
            saved = await showModalBottomSheet<MacroDistributionConfig>(
              context: context,
              isScrollControlled: true,
              builder: (context) => const MacroDistributionSheet(
                calories: 2000,
                presetOnly: true,
              ),
            );
          },
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('macro_preset_balanced')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('macro_preset_high_protein')),
      findsOneWidget,
    );
    expect(
        find.byKey(const ValueKey('macro_preset_lower_carb')), findsOneWidget);
    expect(find.text('Personalized'), findsNothing);
    expect(find.byKey(const ValueKey('macro_mode_grams')), findsNothing);
    expect(find.byKey(const ValueKey('macro_grams_editor')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('macro_preset_high_protein')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('macro_distribution_save_button')));
    await tester.pumpAndSettle();

    expect(saved?.mode, MacroMode.percentage);
    expect(saved?.source, MacroSource.preset);
    expect(saved?.preset, MacroPreset.highProtein);
    final payload = saved!.toApiJson(calories: 2000);
    expect(payload, containsPair('proteinPct', 35));
    expect(payload.containsKey('proteinGrams'), false);
  });

  testWidgets('tapping personalized opens custom editor bottom sheet',
      (tester) async {
    await tester.pumpWidget(_testApp(const MacroDistributionSheet(
      calories: 2000,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Personalized'));
    await tester.pumpAndSettle();

    expect(find.text('Personalized macros'), findsOneWidget);
    expect(find.byKey(const ValueKey('macro_mode_percentage')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('macro_percentage_editor')), findsOneWidget);
  });

  testWidgets('percentage mismatch blocks save until a fix button resolves it',
      (tester) async {
    await tester.pumpWidget(_testApp(const MacroDistributionSheet(
      calories: 2000,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Personalized'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('macro_percentage_protein_field')),
      '40',
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('macro_percentage_total_warning')),
      findsOneWidget,
    );
    expect(_personalizedSaveButton(tester).onPressed, isNull);

    final adjustCarbs =
        find.byKey(const ValueKey('macro_percentage_adjust_carbs'));
    await tester.ensureVisible(adjustCarbs);
    await tester.pumpAndSettle();
    await tester.tap(adjustCarbs.hitTestable());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('macro_percentage_total_warning')),
      findsNothing,
    );
    expect(_personalizedSaveButton(tester).onPressed, isNotNull);
  });

  testWidgets('gram mismatch blocks save until a fix button resolves it',
      (tester) async {
    await tester.pumpWidget(_testApp(const MacroDistributionSheet(
      calories: 2000,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Personalized'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('macro_mode_grams')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('macro_grams_protein_field')),
      '300',
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('macro_calorie_mismatch_warning')),
      findsOneWidget,
    );
    expect(
        find.byKey(const ValueKey('macro_warning_keep_grams')), findsNothing);
    expect(_personalizedSaveButton(tester).onPressed, isNull);

    final adjustProtein =
        find.byKey(const ValueKey('macro_warning_adjust_protein'));
    await tester.ensureVisible(adjustProtein);
    await tester.pumpAndSettle();
    await tester.tap(adjustProtein.hitTestable());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('macro_calorie_mismatch_warning')),
      findsNothing,
    );
    expect(_personalizedSaveButton(tester).onPressed, isNotNull);
  });
}

Widget _testApp(Widget child) {
  return MaterialApp(
    theme: buildLightTheme(),
    home: Scaffold(body: child),
  );
}

IconData? _iconFor(WidgetTester tester, String key) {
  return tester.widget<Icon>(find.byKey(ValueKey(key))).icon;
}

FilledButton _personalizedSaveButton(WidgetTester tester) {
  return tester.widget<FilledButton>(
    find.byKey(const ValueKey('personalized_macro_save_button')),
  );
}
