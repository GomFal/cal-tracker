## Review

- **Correct:** `plan.md` no existe en `/home/antonio/code/cal-tracker/plan.md`; revisé `progress.md` solo en lectura. No modifiqué ni escribí `progress.md` ni `review/flutter-size-complexity.md` porque la tarea dice READ-ONLY / “No modifiques ningún fichero”.
- **Correct:** No encontré `TODO`, `FIXME`, `HACK` ni `XXX` en `apps/mobile/lib`.
- **Correct:** Hay cobertura existente para varios módulos grandes: `voice_log_screen_test.dart`, `voice_log_view_model_test.dart`, `agent_chat_test.dart`, `macro_distribution_test.dart`, `calorie_calculator_wizard_test.dart`, `meal_template_editor_widget_test.dart`.

## Top archivos grandes / complejos

1. `apps/mobile/lib/ui/features/voice_log/views/voice_log_screen.dart` — ~2,587 líneas. Mezcla pantalla, búsqueda manual, clarificación, editor de propuesta, filas editables y tarjetas de resultado (`_FoodSearchBoxState` 892-1089, `_ProposalEditorSheetState` 1995-2165, `_EditableIngredientRow` 2167-2335).
2. `apps/mobile/lib/ui/features/dashboard/views/calorie_target_sheet.dart` — ~2,295 líneas. Combina sheet, wizard, pickers, ruler custom painter y resultado (`_CalorieCalculatorWizardState` 390-1078, `_SlidingRulerScaleState` 1785-1893, painters 1895-1991 y 2203-2257).
3. `apps/mobile/lib/local_toolkit/data/local_fixture_store.dart` — ~1,378 líneas. Store, fixtures, escenarios, cálculo nutricional y helpers en un único fichero (`LocalFixtureStore` 27-813).
4. `apps/mobile/lib/ui/features/agent_chat/views/agent_chat_screen.dart` — ~1,254 líneas. UI de chat, timeline, widgets de resultados, drafts y listas (`_UsualFoodDraftReview` 600-690, `_UsualMealDraftReview` 692-783).
5. `apps/mobile/lib/ui/features/dashboard/views/macro_distribution_sheet.dart` — ~1,153 líneas. Estado de edición, lógica de porcentajes/gramos y UI juntos (`_PersonalizedMacroSheetState` 223-716, build 298-569).
6. `apps/mobile/lib/data/repositories/nutrition_repository.dart` — ~1,093 líneas. API, cache, health, parsers, telemetría y mutaciones juntos (`NutritionRepository` 142-1055; `_parseAgentRunResult` 491-560).
7. `apps/mobile/lib/ui/features/meal_templates/views/meal_template_editor_screen.dart` — ~1,040 líneas. Editor, controller de items, candidate groups, save bar y helpers en un archivo (`_TemplateMealItemController` 788-990).
8. `apps/mobile/lib/ui/features/dashboard/views/dashboard_screen.dart` — ~1,013 líneas. Dashboard, water, meal rows, modales y prompts juntos (`_DashboardScreenState` 28-219; widgets hasta 1013).
9. `apps/mobile/lib/ui/features/meal_templates/views/usual_food_scan_screen.dart` — ~979 líneas. Cámara/OCR/crop/UI/painters/helpers juntos (`_UsualFoodScanScreenState` 43-391; OCR helpers 863-979).
10. `apps/mobile/lib/ui/features/voice_log/view_models/voice_log_view_model.dart` — ~940 líneas. Grabación, transcripción, propuestas, candidatos, telemetría y timers juntos (`VoiceLogViewModel` 178-940).

## Deuda técnica priorizada

- **Blocker:** Ningún blocker funcional verificado en esta revisión de tamaño/complejidad.

- **Note:** Refactor prioritario: partir `voice_log_screen.dart`.
  - Evidencia: el fichero concentra búsqueda manual (`305-462`), clarificación (`687-812`), búsqueda debounced (`871-1089`), editor de propuesta (`1982-2165`) y filas editables (`2167-2335`).
  - Refactor concreto: extraer `manual_food_search_panel.dart`, `resolver_clarification_card.dart`, `food_search_box.dart`, `proposal_editor_sheet.dart`, `editable_ingredient_row.dart` y `result_cards.dart`.

- **Note:** Refactor prioritario: separar wizard/calculadora de `calorie_target_sheet.dart`.
  - Evidencia: `_CalorieCalculatorWizardState` ocupa `390-1078`; además contiene ruler/painters en `1757-1991` y resultado en `2048-2295`.
  - Refactor concreto: mover wizard a `calorie_calculator_wizard.dart`, ruler a `widgets/sliding_ruler_scale.dart`, birthday picker a `widgets/birthday_wheel_picker.dart`, y cálculos/validaciones a lógica pura testeable.

- **Note:** `NutritionRepository` tiene demasiadas responsabilidades.
  - Evidencia: cache SWR `193-336`, agent/voice/chat `338-408`, food search + telemetría `410-459`, parsers `461-560`, mutaciones y templates `562-880`, cache result handling `882+`.
  - Refactor concreto: extraer parsers (`agent_result_parser.dart`), API facades por dominio (`daily_summary_repository`, `meal_template_repository`, `agent_repository`) y un coordinador de cache.

- **Note:** `VoiceLogViewModel` debería dividirse por responsabilidades.
  - Evidencia: grabación `319-440`, transcripción `441-508`, submit text `515-565`, aplicación de resultados `566-655`, edición de propuesta `656-776`, selección de candidatos `777-853`, telemetría `907-929`.
  - Refactor concreto: separar `VoiceRecordingController`, `VoiceProposalController`, `CandidateResolutionController` y dejar el ViewModel como orquestador de UI state.

- **Note:** Duplicación de búsqueda/edición de alimentos.
  - Evidencia: existe `ui/shared/food_search_panel.dart` completo (`11-189`), pero `voice_log_screen.dart` implementa `_FoodSearchBoxState` (`892-1089`) y búsqueda inline (`2372-2432`); `meal_item_editor_sheet.dart` tiene `_InlineReplacementFoodSearch` (`546-600`).
  - Refactor concreto: unificar en componente reusable configurable para búsqueda, selección, estados empty/error/debounce.

- **Note:** Duplicación de filas/editors de ingredientes.
  - Evidencia: `meal_item_editor_sheet.dart` `_IngredientEditorCard` (`292-544`) y `voice_log_screen.dart` `_EditableIngredientRow` (`2167-2335`) implementan UI similar sobre `EditableMealItemController`.
  - Refactor concreto: extraer `EditableIngredientCard/Row` compartido.

- **Note:** Hardcoding de idioma en Dashboard.
  - Evidencia: `dashboard_screen.dart:556` usa `l10n.localeName.startsWith('es') ? 'Proteínas' : 'Proteins'`; `dashboard_screen.dart:571` igual para grasas.
  - Refactor concreto: usar `l10n.commonProtein` y `l10n.commonFat`, ya usados en otros módulos.

- **Note:** Acoplamiento UI/ViewModel a `dart:io`.
  - Evidencia: `agent_chat_view_model.dart:2`, `meal_templates_view_model.dart:2`, `voice_log_view_model.dart:2`.
  - Refactor concreto: introducir abstracciones de audio/archivo o DTOs de grabación para reducir dependencia de plataforma en ViewModels.

- **Note:** Tests vs lib: encontré aproximadamente 78 ficheros Dart relevantes en `lib` excluyendo generated/l10n generado, y ~46-47 tests Dart. La cobertura existe en flujos grandes, pero los refactors anteriores deberían hacerse con tests de caracterización antes de partir archivos.