## Review

- Correct:
  - `plan.md` no existe en `/home/antonio/code/cal-tracker`; `progress.md` existe pero solo contiene plantilla/status sin hallazgos previos.
  - No modifiqué ficheros: la tarea pedía READ-ONLY y “No modifiques ningún fichero”, lo que entra en conflicto con escribir `progress.md` y `review2/flutter-size-complexity.md`. Dejo el contenido aquí.
  - Tests existentes cubren varios puntos calientes:
    - `voice_log_screen_test.dart` y `voice_log_view_model_test.dart` tienen cobertura extensa.
    - `calorie_calculator_wizard_test.dart`, `macro_distribution_test.dart`, `nutrition_repository_test.dart`, `data_view_model_cache_test.dart` cubren módulos grandes relevantes.
  - `TODO/FIXME/HACK/XXX`: sin coincidencias en `apps/mobile/**/*.dart`.
  - Métrica rápida por listado:
    - `apps/mobile/lib`: 82 Dart incluyendo generated; ~78 excluyendo `generated/api` y `l10n/generated`.
    - `apps/mobile/test`: 39 Dart.
    - Generated excluido correctamente; por ejemplo `l10n/generated/app_localizations.dart` llega al menos a línea 3271 y no lo cuento como deuda manual.

- Fixed:
  - Nada aplicado; revisión solo lectura.

- Blocker:
  - Ningún blocker funcional identificado. El principal riesgo es mantenibilidad/tamaño, no fallo inmediato.

- Note:

### Top archivos grandes / complejos

| Prioridad | Archivo | Tamaño observado | Evidencia | Riesgo/refactor recomendado |
|---|---:|---:|---|---|
| P0 | `apps/mobile/lib/ui/features/voice_log/views/voice_log_screen.dart` | ≥2547 líneas | `MealCreateScreen` línea 19, manual search panel línea 305, `_FoodSearchBox` línea 871, proposal editor línea 1982, inline replacement search línea 2372, `_MealLine` línea 2535 | Partir en `manual_food_search_panel.dart`, `candidate_resolution_section.dart`, `proposal_card.dart`, `proposal_editor_sheet.dart`, `meal_label_sheet.dart`. El archivo mezcla pantalla, editor, búsqueda, resolución de candidatos, banners, helpers y widgets privados. |
| P0 | `apps/mobile/lib/ui/features/dashboard/views/calorie_target_sheet.dart` | ≥2269 líneas | Wizard state línea 390, step builders líneas 700/733/752/799/844/869/903/928, ruler painter línea 1895, result step línea 2048 | Extraer wizard a subcarpeta: `calorie_wizard_state/controller`, `steps/*`, `ruler/*`, `result_step.dart`. El estado del wizard mantiene controladores, validación, navegación, cálculo remoto y UI en una sola clase. |
| P1 | `apps/mobile/lib/local_toolkit/data/local_fixture_store.dart` | ≥1346 líneas | Store línea 27, presets líneas 223/245/249/292/320, CRUD línea 413+, seed catalog línea 837, seed scenarios línea 1011, `_summaryFor` línea 1183, `_macroFields` línea 1305 | Local-only, pero conviene separar `fixture_seed_data.dart`, `fixture_presets.dart`, `fixture_mutations.dart`, `local_agent_scenarios.dart`. Hoy combina estado mutable, seed data, escenarios, cálculos y CRUD fake. |
| P1 | `apps/mobile/lib/ui/features/agent_chat/views/agent_chat_screen.dart` | ≥1155 líneas | Main screen línea 18, result widget línea 549, usual food draft review línea 600, usual meal draft review línea 692, input bar línea 1141 | Separar timeline bubbles, draft review widgets, result renderers e input bar. |
| P1 | `apps/mobile/lib/ui/features/dashboard/views/macro_distribution_sheet.dart` | ≥1086 líneas | Parent sheet línea 10, personalized state línea 223, editors líneas 372/458, save logic línea 712, cards línea 718/859 | Extraer personalized macro editor/controller y componentes de campos. |
| P1 | `apps/mobile/lib/data/repositories/nutrition_repository.dart` | ≥1013 líneas | DTO/result classes líneas 12-135, repository línea 142, API/cache methods línea 172+, parsers líneas 461/491, cache merge línea 882+, telemetry línea 1013 | Separar parsing (`agent_result_parser.dart`), cache sync (`nutrition_cache_coordinator.dart`) y food-search telemetry. Repository hace API, parsing, cache, telemetry y health recording. |
| P2 | `apps/mobile/lib/ui/features/dashboard/views/dashboard_screen.dart` | ≥988 líneas | Screen línea 21, progress card línea 244, water card línea 671, meal section línea 839, meal row línea 927 | Partir cards y meal list en widgets por archivo. |
| P2 | `apps/mobile/lib/ui/features/meal_templates/views/usual_food_scan_screen.dart` | ≥953 líneas | Camera lifecycle/control líneas 126-250, build línea 283, crop preview línea 393, OCR formatting lines/functions líneas 863/891 | Ya existe ViewModel separado, pero el screen aún mezcla camera plugin orchestration, crop UI y OCR text formatting. Extraer OCR formatting a pure service/helper y crop widgets a archivo propio. |
| P2 | `apps/mobile/lib/domain/models/nutrition_models.dart` | ≥897 líneas | Muchos modelos en un archivo: `MealItem` línea 318, `Meal` línea 669, `DailySummary` línea 714, `MealTemplate` línea 807, `UsualMealDraft` línea 857 | Separar por bounded context: `meal_models.dart`, `food_search_models.dart`, `goals_models.dart`, `templates_models.dart`. |
| P3 | `apps/mobile/lib/ui/core/design_system.dart` | ≥845 líneas | Palette línea 30, spacing/radii líneas 232/243, reusable widgets líneas 268-834 | No urgente porque es cohesionadamente “design system”, pero puede dividirse en `tokens.dart`, `cards.dart`, `indicators.dart`, `empty_state.dart`. |

### Deuda técnica priorizada

1. **Duplicación de búsqueda de alimentos**
   - `FoodSearchPanel` ya existe como widget compartido en `ui/shared/food_search_panel.dart:11`.
   - `meal_item_editor_sheet.dart` lo usa en línea 586.
   - `voice_log_screen.dart` mantiene un `_FoodSearchBox` privado en línea 871 y otro `_InlineReplacementFoodSearch` en línea 2372.
   - Refactor: migrar `voice_log_screen.dart` a `FoodSearchPanel` y eliminar `_FoodSearchBox` privado.

2. **Duplicación/helper conflict `normalizedText`**
   - `voice_log_helpers.dart:4` define `normalizedText`.
   - `nutrition_edit_components.dart:249` también define `normalizedText`.
   - `voice_log_screen.dart:16` importa `nutrition_edit_components.dart hide normalizedText`, señal clara de colisión.
   - Refactor: mover normalización común a un helper compartido o renombrar el helper UI-local.

3. **Acoplamientos de imports entre capas/features**
   - `ui/shared/food_search_panel.dart:3` importa `data/repositories/nutrition_repository.dart` solo para `FoodSearchResult`/callback (`food_search_panel.dart:8`), acoplando UI shared a data.
   - `FoodSearchResult` vive dentro del repository en `nutrition_repository.dart:135`.
   - `meal_templates_screen.dart:9` importa `voice_log_screen.dart` para usar `MealCreateInitialItems`, definido en `voice_log_screen.dart:214`; router depende de ese type en `app/router.dart:66`.
   - Refactor: mover `FoodSearchResult` a `domain/models/food_search_models.dart`; mover `MealCreateInitialItems` a un modelo de navegación o dominio compartido.

4. **ViewModel con demasiadas responsabilidades**
   - `VoiceLogViewModel` contiene audio lifecycle (`_startRecording` línea 319, `_stopRecording` línea 393, `_transcribe` línea 441), submit text línea 515, result mapping línea 566, proposal commit/edit líneas 656/688/725, candidate selection línea 777, telemetry línea 907.
   - Está bien testeado, pero crecerá difícil.
   - Refactor: extraer coordinadores internos: `VoiceRecordingController`, `VoiceAgentResultReducer`, `ProposalEditingCoordinator`.

5. **Archivos de UI “screen + todos sus widgets”**
   - Patrón repetido en `voice_log_screen.dart`, `calorie_target_sheet.dart`, `agent_chat_screen.dart`, `macro_distribution_sheet.dart`.
   - Refactor incremental recomendado: no reescribir; crear subcarpetas por feature y mover solo widgets privados estables con tests existentes como red de seguridad.