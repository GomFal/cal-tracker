## Review

- Correct:
  - La suite `apps/mobile/test` cubre bastantes capas sin backend real: repositorio/API parsing (`test/nutrition_repository_test.dart:19`, `:73`, `:198`, `:343`, `:425`), cache store (`test/nutrition_cache_store_test.dart:8-58`), ViewModels cache-first (`test/data_view_model_cache_test.dart:31-228`), UI de Dashboard/History/Templates/Voice, y flujos de escaneo con fakes (`test/features/meal_templates/usual_food_scan_view_model_test.dart:97-278`).
  - Buena configuración anti-fragilidad para taps: `test/flutter_test_config.dart:6` hace fatales los hit-test warnings.
  - No ejecuté `flutter analyze` ni `flutter test`: en esta sesión solo tengo herramientas read-only de inspección, no shell.

- Fixed:
  - Ninguno. La tarea era read-only y no modifiqué ficheros. Tampoco escribí `progress.md` ni `review/flutter-tests-validation.md` por conflicto con “No modifiques ficheros” y falta de herramienta de escritura.

- Blocker:
  - Ningún blocker confirmado por inspección estática.

- Note:
  - **P1 — Falta cobertura directa de la capa real de cache en `NutritionRepository`.** El repositorio contiene deduplicación/cooldown/cache (`lib/data/repositories/nutrition_repository.dart:193-240`, `:246-336`) y write-through helpers (`:882-976`). Los tests actuales cubren el store (`test/nutrition_cache_store_test.dart:8-58`) y ViewModels con fake repository (`test/data_view_model_cache_test.dart:31-228`), pero `test/nutrition_repository_test.dart` se centra en parsing/macros/hydration, no en cache. Añadir tests de `refreshDailySummary`, in-flight dedup, cooldown, `force`, y actualizaciones write-through.
  - **P1 — Gaps widget-level para stale-while-revalidate.** `DashboardScreen` solo muestra loader si `viewModel.isLoading` (`lib/ui/features/dashboard/views/dashboard_screen.dart:53-54`) y el ViewModel hidrata cache antes del refresh (`test/data_view_model_cache_test.dart:31-48`), pero los widget tests de Dashboard usan un fake que solo overridea `getDailySummary` (`test/dashboard_cleanup_widget_test.dart:831-832`). Sí hay checks contra loader durante optimistic water (`:339-370`), pero no “cached data visible + refresh pending”. Añadir widget tests con cache presente y refresh retardado.
  - **P2 — Mobile update VM/dialog casi sin unit/widget coverage.** `MobileUpdateViewModel` tiene estados/error/dispose (`lib/app/mobile_update_view_model.dart:26-73`) y `MobileUpdateDialogHost` agenda diálogo y ejecuta `openUpdate` (`lib/ui/core/mobile_update_dialog_host.dart:46-93`). Solo vi service tests (`test/mobile_update_service_test.dart:24-60`) y una integration test (`integration_test/mobile_update_test.dart:16-61`). Añadir unit tests del VM y widget test del host con fake VM/service.
  - **P2 — History delete/rollback sin cobertura clara.** La UI de History permite delete (`lib/ui/features/meal_history/views/meal_history_screen.dart:124-185`) y el VM tiene rollback si falla/no borra (`lib/ui/features/meal_history/view_models/meal_history_view_model.dart:134-159`). `test/meal_history_widget_test.dart` solo declara tests de edición/controles (`:18`, `:106`). Añadir tests de confirmación, cancelación y rollback/error.
  - **P2 — Semantics/golden coverage escasa.** Las guías piden goldens selectivos y semantics para controles importantes (`AGENTS.md:96-97`). No encontré goldens. Hay Semantics importantes en el botón global (`lib/ui/core/app_shell.dart:518-522`, `:598-600`), pero el test lo toca por key aunque el comentario dice semantics (`test/bottom_mic_bubble_widget_test.dart:214-216`). Añadir `SemanticsTester`/`bySemanticsLabel` para icon-only controls críticos y considerar goldens para tarjetas/forms visualmente complejos.
  - **P3 — Fragilidad por esperas temporales.** `test/voice_log_view_model_test.dart` usa `Future.delayed` (`:232`, `:283`, `:446`, `:472`, `:585`), y varios widget tests grandes usan mucho `pumpAndSettle` (p.ej. `test/voice_log_screen_test.dart:146-1574`, `test/dashboard_cleanup_widget_test.dart:55-779`). Preferir `Completer`, clocks controlados y pumps acotados.
  - **P3 — No correr integration/Patrol para validación sin backend.** `integration_test/app_test.dart` apunta a `http://10.0.2.2:3000` (`:7`, `:14`) y `CalTrackerBootstrap` agenda updates por defecto (`lib/app/app.dart:52`, `:126-128`) con servicios reales si no se inyectan fakes (`:221-262`). Patrol también postea al backend (`patrol_test/patrol_smoke_test.dart:260-316`). Para esta revisión, limitarse a `flutter test` unit/widget.

Comandos recomendados:

```bash
cd apps/mobile
flutter analyze
flutter test
flutter test test/nutrition_repository_test.dart test/nutrition_cache_store_test.dart test/data_view_model_cache_test.dart
flutter test test/dashboard_cleanup_widget_test.dart test/meal_history_widget_test.dart
flutter test test/features/meal_templates/usual_food_scan_view_model_test.dart test/features/meal_templates/usual_food_scan_screen_test.dart
```