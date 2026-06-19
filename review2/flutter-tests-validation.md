## Review

No escribí `progress.md` ni `review2/flutter-tests-validation.md` porque la tarea también dice **READ-ONLY / No modifiques ficheros**; apliqué la restricción de no edición.

- Correct:
  - Buena cobertura cache-first/optimistic rollback en ViewModels: `test/data_view_model_cache_test.dart:31-88`, `:107-229`.
  - `flutter_test_config.dart:5-7` convierte hit-test warnings en fallos, reduciendo taps frágiles.
  - `NutritionCacheStore` cubre scoping por usuario, expiración y limpieza: `test/nutrition_cache_store_test.dart:8-58`.
  - `VoiceLogViewModel` tiene cobertura amplia de grabación, propuestas, correcciones activas, clarificaciones y errores: `test/voice_log_view_model_test.dart:239-383`, `:531-666`, `:741-1017`.
  - No vi tests marcados como `skip` en `test/` ni `integration_test/`.

- Fixed:
  - Ninguno; revisión read-only.

- Blocker:
  - Varios widget/integration tests pueden disparar HTTP real de update-check al montar `CalTrackerBootstrap` sin desactivar updates ni inyectar fake. Evidencia:
    - `CalTrackerBootstrap` agenda `viewModel.checkForUpdate()` si `checkForUpdates` es true: `lib/app/app.dart:121-128`.
    - Si no se inyecta servicio, crea `MobileUpdateService(apiConfig: widget.apiConfig)`: `lib/app/app.dart:261-262`.
    - `MobileUpdateService` usa `http.Client()` real y hace `GET /apk/latest.json`: `lib/data/services/mobile_update_service.dart:31-48`.
    - Tests afectados: `test/widget_test.dart:93-99`, `test/startup_auth_widget_test.dart:30-35`, `:74-79`, `:109-114`, `integration_test/app_test.dart:13-15`.
  - Recomendación: en tests de bootstrap/auth pasar `checkForUpdates: false` o un `MobileUpdateService` fake/mock. Esto evita llamadas reales, timeouts de 4s y flakiness.

- Note:
  - `plan.md` no existe en la ruta indicada; `progress.md` solo contiene esqueleto de estado (`progress.md:1-10`).
  - Gap de cobertura repository: `NutritionRepository` tiene muchos métodos reales de templates/usual foods/cache write-through (`lib/data/repositories/nutrition_repository.dart:755-873`, `:930-976`), pero los tests de repositorio visibles se concentran en parsing/search/goals/hydration (`test/nutrition_repository_test.dart:19-464`). Los widget tests usan repos fake para esos métodos (`test/meal_templates_widget_test.dart:365-412`, `test/meal_template_editor_widget_test.dart:460-508`), así que no validan payload/API/cache real.
  - Gap menor en cache store: hay API para usual foods (`lib/data/services/nutrition_cache_store.dart:78-86`), pero `nutrition_cache_store_test.dart:8-58` cubre daily/templates/clear, no read/write de usual foods.
  - No hay golden tests (`matchesGoldenFile`/golden no aparece; `pubspec.yaml:34-43` no lista dependencia golden extra). Para superficies visuales densas como dashboard/macro sheets/meal cards, añadir goldens selectivos ayudaría.
  - Semantics coverage es baja: hay `Semantics` importantes en `lib/ui/core/app_shell.dart:518-523` y `:598-600`, pero los tests no usan `bySemanticsLabel`/`ensureSemantics`; `test/bottom_mic_bubble_widget_test.dart:214-216` comenta semantics pero toca por key.

Comandos recomendados, sin backend real:

```bash
cd apps/mobile
flutter analyze
flutter test
flutter test test/widget_test.dart test/startup_auth_widget_test.dart test/app_bootstrap_lifecycle_test.dart
flutter test test/nutrition_cache_store_test.dart test/nutrition_repository_test.dart test/data_view_model_cache_test.dart
```

No ejecuté `flutter analyze/test` en esta sesión porque solo tuve herramientas de inspección y la revisión debía evitar llamadas reales al backend.