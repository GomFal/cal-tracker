# Dashboard/history meal edit repair

## Changes made
- Repaired `apps/mobile/lib/ui/shared/meal_item_editor_sheet.dart` analyzer issues from the partial implementation:
  - removed unused import/dead inline search helper;
  - added the missing compact macro summary helper;
  - kept compact-by-default ingredient rows with one-expanded-row behavior;
  - kept secondary actions behind the overflow menu;
  - tightened overflow-menu text and compact-row trailing text to avoid RenderFlex overflows.
- Updated targeted widget tests to match the intentional compact interaction:
  - assert compact rows initially;
  - tap an ingredient row before editing quantities/details;
  - open replace/details through the overflow menu.
- L10n partial additions for compact search/replace labels remain in EN/ES and generated files.

## Validation
- `dart format apps/mobile/lib/ui/shared/meal_item_editor_sheet.dart apps/mobile/lib/l10n/app_en.arb apps/mobile/lib/l10n/app_es.arb apps/mobile/lib/l10n/generated/app_localizations.dart apps/mobile/lib/l10n/generated/app_localizations_en.dart apps/mobile/lib/l10n/generated/app_localizations_es.dart`
  - Exit 65 because `dart format` cannot parse `.arb` JSON files as Dart.
  - The Dart files in that list were formatted successfully; ARB files were not changed by formatter.
- `flutter analyze`: PASS, no issues.
- `flutter test test/dashboard_cleanup_widget_test.dart test/meal_history_widget_test.dart`: PASS, 15 tests.
- `flutter test`: PASS, full mobile suite.

## Risks / notes
- Existing worktree has many unrelated pre-existing modified files; I only intentionally edited meal editor repair files plus the two targeted tests authorized by supervisor override.
- No visual/emulator inspection was performed; validation is analyzer + widget/unit tests.
