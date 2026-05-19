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

  testWidgets('macro sheet defaults to percentages and flips preset text order',
      (tester) async {
    await tester.pumpWidget(_testApp(const MacroDistributionSheet(
      calories: 2000,
    )));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('macro_mode_percentage')), findsOneWidget);
    expect(find.text('30% protein · 40% carbs · 30% fat'), findsOneWidget);
    expect(find.text('150g protein · 200g carbs · 67g fat'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('macro_mode_grams')));
    await tester.pumpAndSettle();

    final balancedCard = find.byKey(const ValueKey('macro_preset_balanced'));
    expect(
      find.descendant(
        of: balancedCard,
        matching: find.text('150g protein · 200g carbs · 67g fat'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('custom percentages use carbs as the default balancer',
      (tester) async {
    await tester.pumpWidget(_testApp(const MacroDistributionSheet(
      calories: 2000,
    )));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('macro_percentage_protein_field')),
      '40',
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('macro_percentage_carbs_field')),
          )
          .controller
          ?.text,
      '30',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('macro_percentage_fat_field')),
          )
          .controller
          ?.text,
      '30',
    );
  });

  testWidgets('gram mode shows warnings only above the threshold',
      (tester) async {
    await tester.pumpWidget(_testApp(const MacroDistributionSheet(
      calories: 2000,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('macro_mode_grams')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('macro_calorie_mismatch_warning')),
      findsNothing,
    );

    await tester.enterText(
      find.byKey(const ValueKey('macro_grams_protein_field')),
      '300',
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('macro_calorie_mismatch_warning')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('macro_warning_adjust_carbs')),
        findsOneWidget);
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
}

Widget _testApp(Widget child) {
  return MaterialApp(
    theme: buildLightTheme(),
    home: Scaffold(body: child),
  );
}
