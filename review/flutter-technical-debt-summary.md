# Auditoría Flutter de deuda técnica

Fecha: 2026-06-18  
Scope: `apps/mobile`  
Método: 2 tandas paralelas de 5 subagentes read-only + métricas locales.

## Resumen ejecutivo

No se detectaron P0/blockers funcionales por inspección estática. La deuda principal está en mantenibilidad Flutter: pantallas monolíticas, repositorio central demasiado amplio, duplicación de componentes de búsqueda/edición de alimentos, huecos de cobertura alrededor de cache real/rollback/semantics, y accesibilidad/responsive en controles custom.

Métricas locales excluyendo generated/build:

- Dart total: 151 ficheros, 46.617 líneas.
- `lib`: 79 ficheros, 29.746 líneas.
- `test`: 47 ficheros, 14.475 líneas.
- Ratio líneas test/lib: 0,49.
- `TODO/FIXME/HACK`: 0.
- Ficheros `lib` >500 líneas: 20+.

## Hallazgos P1

### 1. Pantallas/god files demasiado grandes

Ficheros más críticos:

- `apps/mobile/lib/ui/features/voice_log/views/voice_log_screen.dart` — ~2590 LOC.
- `apps/mobile/lib/ui/features/dashboard/views/calorie_target_sheet.dart` — ~2295 LOC.
- `apps/mobile/lib/ui/features/agent_chat/views/agent_chat_screen.dart` — ~1254 LOC.
- `apps/mobile/lib/ui/features/dashboard/views/macro_distribution_sheet.dart` — ~1153 LOC.
- `apps/mobile/lib/ui/features/dashboard/views/dashboard_screen.dart` — ~1013 LOC.
- `apps/mobile/lib/ui/features/meal_templates/views/usual_food_scan_screen.dart` — ~983 LOC.

Impacto: cambios UI más lentos, tests más frágiles, más riesgo de regresión y duplicación.

Acción recomendada: refactor incremental, no reescritura. Extraer widgets privados estables manteniendo tests existentes como red de seguridad.

### 2. `NutritionRepository` es un hub excesivo

Ruta: `apps/mobile/lib/data/repositories/nutrition_repository.dart` — ~1093 LOC.

Responsabilidades mezcladas:

- API calls de summary, meals, templates, usual foods, agent/voice/chat.
- Parsing de outputs agent/chat.
- Cache stale-while-revalidate, dedupe, cooldown.
- Write-through updates y rollback/local consistency.
- Telemetry/cache failure handling.

Acción recomendada:

- Extraer parsers a `agent_result_parser.dart`/modelos typed.
- Mover `FoodSearchResult` fuera del repository a modelo de dominio/data neutral.
- Dividir facades por dominio: daily summary, meal templates/usual foods, agent/voice.
- Mantener un coordinador de cache explícito para invariantes compartidas.

### 3. Duplicación de búsqueda/edición de alimentos

Evidencia:

- Existe `apps/mobile/lib/ui/shared/food_search_panel.dart`.
- Existe `apps/mobile/lib/ui/shared/meal_item_editor_sheet.dart`.
- Pero `voice_log_screen.dart` reimplementa `_FoodSearchBox`, `_ProposalEditorSheet`, `_EditableIngredientRow` y búsqueda inline.
- `nutrition_edit_components.dart` y `voice_log_helpers.dart` tienen conflicto de `normalizedText`; `voice_log_screen.dart` importa con `hide normalizedText`.

Acción recomendada:

- Unificar búsqueda en `FoodSearchPanel` configurable.
- Extraer `EditableIngredientCard/Row` compartido.
- Crear helper único para normalización de texto.

### 4. Ownership de cache/estado todavía difuso

Hay buen patrón base cache-first, pero la lógica queda repartida entre repository, ViewModels y pantallas.

Riesgos:

- Invariantes de stale-while-revalidate difíciles de probar de extremo a extremo.
- Mutaciones optimistas pueden divergir si varios ViewModels actualizan summary/templates en paralelo.
- `SettingsViewModel.load` no deduplica cargas igual que otros ViewModels.

Acción recomendada:

- Documentar contrato de Repository/ViewModel: quién lee cache, quién refresca, quién hace rollback.
- Añadir tests del repository real para dedupe/cooldown/force/write-through.

## Hallazgos P2

### 5. Accesibilidad insuficiente en controles custom

Evidencia:

- `usual_food_scan_screen.dart`: selector OCR con `GestureDetector` + `CustomPaint` sin `Semantics`.
- `scan_viewfinder_overlay.dart`: textos pintados en canvas invisibles para lectores de pantalla.
- `calorie_target_sheet.dart`: ruler custom sin `Semantics`, acciones increment/decrement ni valores accesibles.
- `app_shell.dart`: navegación custom sin `Semantics(selected: ...)` claro.

Acción recomendada: añadir wrappers `Semantics`, acciones increment/decrement, labels localizados y tests con `SemanticsTester`.

### 6. Estados error/empty pueden mostrar datos por defecto como si fueran reales

Ejemplo: `dashboard_screen.dart` puede mostrar banner de error y a la vez tarjetas con defaults (`0`, target `2200`, agua `0/0`) cuando no hay `summary` visible.

Acción recomendada: si no hay cache/datos visibles, mostrar estado error/empty dedicado. Usar defaults solo para setup explícito.

### 7. Responsive/text scale frágil en superficies densas

Riesgos:

- `_DailyProgressCard` usa alturas fijas y ring/texto en fila.
- `_MealLabelSheet` no está suficientemente protegida frente a teclado + campo “Other”.
- Auth hero y OCR overlay usan dimensiones/textos fijos.

Acción recomendada: `LayoutBuilder`, scroll/constrained boxes y widget tests con viewport pequeño, español y textScale alto.

### 8. I18n/hardcoded strings puntuales

Evidencia:

- `dashboard_screen.dart` usa `l10n.localeName.startsWith('es') ? ...` para macros.
- Hay strings/status/errors visibles fuera de ARB en algunas zonas.

Acción recomendada: mover a ARB y regenerar l10n.

### 9. Design system drift

Evidencia: colores locales en `dashboard_screen.dart` para agua y superficies visuales; auditoría dark mode no cubre todos los `Color(0x...)`.

Acción recomendada: mover tokens semánticos a `FreshPalette`/design system y ampliar test estático con allowlist.

## Testing: estado y gaps

Fortalezas:

- Buena suite unit/widget sin backend real.
- `flutter_test_config.dart` hace fatales los hit-test warnings.
- Tests de cache-first/optimistic rollback en ViewModels.
- Cobertura amplia de `VoiceLogViewModel`.

Gaps prioritarios:

1. Tests del `NutritionRepository` real para cache/dedupe/cooldown/force/write-through.
2. Widget tests de Dashboard con datos cacheados visibles + refresh pendiente/fallido.
3. Coverage de usual foods en `NutritionCacheStore`.
4. Tests de `MobileUpdateViewModel`/dialog host con fakes para evitar flakiness.
5. Delete/rollback en meal history.
6. Semantics tests para controles custom/icon-only.
7. Goldens selectivos para dashboard, macro/calorie sheets y meal cards.

Comandos recomendados:

```bash
cd apps/mobile
flutter analyze
flutter test
flutter test test/nutrition_cache_store_test.dart test/nutrition_repository_test.dart test/data_view_model_cache_test.dart
flutter test test/dashboard_cleanup_widget_test.dart test/meal_history_widget_test.dart
flutter test test/features/meal_templates/usual_food_scan_view_model_test.dart test/features/meal_templates/usual_food_scan_screen_test.dart
```

## Roadmap recomendado

### Fase 1 — Bajo riesgo / alto retorno

1. Extraer componentes duplicados de búsqueda/edición de alimentos.
2. Mover `FoodSearchResult` y `MealCreateInitialItems` fuera de pantallas/repositorios hacia modelos compartidos.
3. Añadir tests de repository cache/dedupe/write-through.
4. Corregir i18n puntual de macros y strings hardcodeados.

### Fase 2 — Partición de god files

1. Partir `voice_log_screen.dart` en paneles/widgets por responsabilidad.
2. Partir `calorie_target_sheet.dart`: wizard, ruler, birthday picker, validaciones puras.
3. Partir `macro_distribution_sheet.dart` y `agent_chat_screen.dart` de forma incremental.

### Fase 3 — Arquitectura de datos/cache

1. Dividir `NutritionRepository` en facades por dominio.
2. Extraer parsers y contratos typed para agent outputs.
3. Formalizar contrato cache/optimistic updates entre repository y ViewModels.

### Fase 4 — UX robusta

1. Añadir semantics a controles custom.
2. Añadir tests text scale/viewport pequeño/ES.
3. Introducir goldens selectivos para superficies visuales críticas.
4. Consolidar tokens de color y dark mode audit.

