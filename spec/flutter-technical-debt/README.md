# Flutter technical debt remediation specs

This directory contains implementation-ready plans for reducing the Flutter technical debt identified in `review/` and `review2/`.

Start here:

1. `spec-architecture-flutter-technical-debt-roadmap.md` — overall sequence and dependencies.
2. `spec-architecture-voice-log-decomposition.md` — split `voice_log_screen.dart` and clarify its role.
3. `spec-design-food-search-editor-consolidation.md` — remove duplicated food search / ingredient editor UI.
4. `spec-architecture-nutrition-repository-split.md` — split `NutritionRepository` and typed models.
5. `spec-quality-flutter-cache-tests.md` — add missing cache/SWR/rollback tests.
6. `spec-design-flutter-accessibility-responsive.md` — accessibility, responsive, i18n, design-system cleanup.

All specs are read-only planning artifacts. Implementation should be done in small PR-sized batches and validated with `flutter analyze` and focused `flutter test` commands.
