# Issue 01 — Edit Ingredients: drag handle no cierra el sheet

**Estado:** Recopilado. Listo para implementar cuando se decida.
**Rama actual:** `develop`
**Origen del report:** Usuario — flujo "Edit Ingredients" desde el Home.
**Reportado en:** Home (Dashboard). El mismo bug también afecta al editor de ingredientes abierto desde Meal History y al sub-sheet `NutritionEditSheet` y al proposal editor del voice log (estructura idéntica).

## Síntoma

> "Cuando estamos en el Home y queremos modificar una comida, arriba sale un icono, la típica rayita que te permite bajar hacia abajo el modal cuando sale. Pues esto está mal implementado y no se cierra esta pestaña, es decir, no se vuelve. Yo arrastro hacia abajo, sin embargo no se vuelve a la pestaña anterior."

- Al pulsar el icono de edición (lápiz) en una fila de comida del Dashboard se abre el sheet `MealItemEditorSheet` con la barrita gris arriba.
- Al **arrastrar esa barrita hacia abajo**, el sheet **no se cierra**. Se queda fijo, no se "vuelve" al Dashboard.
- El sheet sí se cierra correctamente pulsando el botón **Save edits** o haciendo tap en la barrera exterior — pero el drag-to-dismiss del handle no funciona.

## Causa raíz (observada, no prescrita)

El drag handle es un `Container(width: 44, height: 4, ...)` puramente decorativo que vive **dentro** del `SingleChildScrollView` que envuelve todo el contenido del sheet. El scrollable reclama el `VerticalDragGestureRecognizer` en la zona del handle, de modo que el `ModalBottomSheetRoute` subyacente de Flutter nunca llega a reconocer un drag-to-dismiss.

Los sheets que **sí** se cierran al arrastrar el handle (`CalorieTargetSheet`, `MacroDistributionSheet`) lo hacen porque el handle está como **primer hijo de un `Column` raíz, fuera del scrollable** (cuando hay scrollable, está en un `Expanded` por debajo del handle). En ese caso el drag vertical fuera del scrollable llega al `ModalBottomSheetRoute` y dispara el dismiss.

`MealItemEditorSheet` no usa `DraggableScrollableSheet`, ni `NotificationListener`, ni un `GestureDetector` sobre el handle. La responsabilidad del drag-to-dismiss es 100% del framework, y el framework solo lo entrega si la zona del handle no está atrapada dentro de un scrollable.

## Ficheros directamente sospechosos (sospechosos de causar el bug)

### Sheet principal reportado por el usuario
- `apps/mobile/lib/ui/shared/meal_item_editor_sheet.dart`
  - `MealItemEditorSheet` `StatefulWidget` (línea 12).
  - `build` (líneas 50-176): `DecoratedBox → Padding → SingleChildScrollView → Column`. El handle (Container 44x4) está en las líneas 65-77, dentro del scrollable.
  - `_save` (líneas 192-203): cierre vía `Navigator.of(context).pop(edited)`.
  - Llamada anidada a `showModalBottomSheet<NutritionEdit>` en líneas 503-521.

### Otros sheets con el mismo bug estructural (mismo patrón defectuoso)
- `apps/mobile/lib/ui/shared/nutrition_edit_sheet.dart`
  - `NutritionEditSheet` (línea 22). Handle (líneas 134-145) dentro de un `SingleChildScrollView` (línea 130).
- `apps/mobile/lib/ui/features/voice_log/views/voice_log_screen.dart`
  - `_ProposalEditorSheet` (líneas 2023-2076). Handle (líneas 2034-2043) dentro de un `SingleChildScrollView` (línea 2030).

### Entradas al flujo "Edit Ingredients"
- `apps/mobile/lib/ui/features/dashboard/views/dashboard_screen.dart`
  - `_showMealItemEditor` (líneas 99-110): `showModalBottomSheet<List<MealItem>>(...)` con `isScrollControlled: true`, `useSafeArea: true`, **sin** `useRootNavigator`.
  - `_MealRow` (línea 680). Botón `dashboard_edit_meal_<meal.id>` (línea 736) que dispara `_showMealItemEditor`.
- `apps/mobile/lib/ui/features/meal_history/views/meal_history_screen.dart`
  - `_showMealItemEditor` (líneas 148-160): mismo patrón, mismo `MealItemEditorSheet`.
- `apps/mobile/lib/ui/features/voice_log/views/voice_log_screen.dart`
  - `_showProposalEditor` (línea 188) → `_ProposalEditorSheet`.
  - Aperturas de `NutritionEditSheet` en líneas 409-433 y 2125-2149.

## Ficheros de referencia con el patrón bueno (drag-to-dismiss sí funciona)

- `apps/mobile/lib/ui/features/dashboard/views/calorie_target_sheet.dart`
  - Handle (líneas 80-89) como primer hijo del `Column` raíz, **fuera** del scrollable.
  - Body: `Padding → SizedBox(height: 0.86·screen) → Column` (sin `SingleChildScrollView` global).
  - Aperturas con `useRootNavigator: true` en líneas 179, 188, 268.
- `apps/mobile/lib/ui/features/dashboard/views/macro_distribution_sheet.dart`
  - Handle (líneas 63-71) como primer hijo del `Column` raíz, **fuera** del scrollable.
  - Body: `Material → Padding → SizedBox(height: 0.9·screen) → Column`. El `SingleChildScrollView` vive en un `Expanded` **por debajo** del handle.
  - `useRootNavigator: true` en línea 150.

## Contexto de navegación (no causa del bug, pero referenciado)

- `apps/mobile/lib/app/router.dart`
  - `StatefulShellRoute` con cuatro ramas (dashboard, history, templates, settings). Cada rama tiene su propio `Navigator`.
  - `SlidingBranchContainer` (líneas 67-199) con `userScrollEnabled: !modalLockController.isLocked`.
  - El sheet del editor se empuja al **Navigator de la rama dashboard** (porque `_showMealItemEditor` no pasa `useRootNavigator`). Eso no es la causa del bug, pero es la ruta de inserción.
- `apps/mobile/lib/ui/core/app_shell.dart`
  - `AppShell` (líneas 30-65), `_FreshBottomNav` (líneas 67-108), `_FreshSideNav` (líneas 110-146).
- `apps/mobile/lib/ui/core/shell_modal_lock.dart`
  - `ShellModalLockController` (líneas 3-40) y `ShellModalLockObserver` (líneas 42-73).
  - Solo alterna la `physics` del `PageView` cuando hay un `PopupRoute` abierto. **No bloquea pops**, no es responsable del bug.

## Tema de los sheets

- `apps/mobile/lib/app/theme.dart:235-244` — `BottomSheetThemeData` con `BorderRadius.vertical(top: Radius.circular(28))`. No activa `showDragHandle` nativo.

## Localizaciones ARB (referencia de cadenas, sin cambios necesarios)

- `apps/mobile/lib/l10n/app_en.arb`
  - Línea 29: `"commonEditIngredients": "Edit ingredients"`
  - Línea 30: `"commonSaveEdits": "Save edits"`
  - Línea 518: `"dashboardEditIngredientsTooltip": "Edit ingredients"`
- `apps/mobile/lib/l10n/app_es.arb`
  - Línea 29: `"commonEditIngredients": "Editar ingredientes"`
  - Línea 30: `"commonSaveEdits": "Guardar cambios"`
  - Línea 254: `"dashboardEditIngredientsTooltip": "Editar ingredientes"`

## Tests existentes (ninguno cubre el dismiss por drag)

- `apps/mobile/test/dashboard_cleanup_widget_test.dart`
  - Cubre apertura del editor desde el Dashboard y guardado vía botón Save, en `'dashboard meal cards edit explicit ingredients'` (línea 281), `'dashboard meal editor adds an ingredient from food search'` (línea 348), `'dashboard meal editor replaces an ingredient from food search'` (línea 421).
  - Cierra el sheet solo pulsando `save_dashboard_item_edits_button`. **No cubre drag-to-dismiss.**
- `apps/mobile/test/meal_history_widget_test.dart`
  - `'edits history meals with explicit ingredients'` (línea 18) y `'measurement controls adjust quantities and wrap presets'` (línea 105). Cierre solo por Save.
- `apps/mobile/test/sliding_branch_container_test.dart`
  - Cubre `ShellModalLockController` y el observer, no el drag del sheet.
- `apps/mobile/test/macro_distribution_test.dart`
  - Útil como referencia de patrón de testing de `showModalBottomSheet` con `tester.pumpWidget` + `showModalBottomSheet` directo.
- `apps/mobile/test/flutter_test_config.dart`
  - `WidgetController.hitTestWarningShouldBeFatal = true` (línea 1-7). Cualquier `tester.drag` que falle por hit-test hará fallar el test.
- `apps/mobile/patrol_test/patrol_smoke_test.dart`
  - Cubre apertura del editor desde voice log, no dismiss por drag.

## Hipótesis verificadas y descartadas

- **No hay `WillPopScope` / `PopScope`** en el editor ni en los sub-sheets que bloquee el pop. Verificado.
- **`ShellModalLockController` no bloquea pops** — solo cambia la `physics` del `PageView`. Verificado.
- **El `Save edits` sí cierra el sheet correctamente** — los tests pasan por esa vía.
- **`useRootNavigator` por defecto es `false`**, no es la causa. Los sheets de referencia (calorie target, macro distribution) usan `useRootNavigator: true` para sus sub-sheets anidados, pero ese no es el patrón que arregla el drag — el patrón que arregla el drag es la posición del handle relativa al scrollable.

## Resumen de símbolos clave (para cuando se implemente)

| Símbolo | Fichero | Línea |
|---|---|---|
| `_DashboardScreenState._showMealItemEditor` | `lib/ui/features/dashboard/views/dashboard_screen.dart` | 99 |
| `_MealRow` (icono edit) | `lib/ui/features/dashboard/views/dashboard_screen.dart` | 680 |
| `MealItemEditorSheet` | `lib/ui/shared/meal_item_editor_sheet.dart` | 12 |
| `_MealItemEditorSheetState.build` | `lib/ui/shared/meal_item_editor_sheet.dart` | 50 |
| Drag handle (MealItemEditorSheet) | `lib/ui/shared/meal_item_editor_sheet.dart` | 65-77 |
| `NutritionEditSheet` | `lib/ui/shared/nutrition_edit_sheet.dart` | 22 |
| Drag handle (NutritionEditSheet) | `lib/ui/shared/nutrition_edit_sheet.dart` | 134-145 |
| `_ProposalEditorSheet` | `lib/ui/features/voice_log/views/voice_log_screen.dart` | ~2023 |
| Drag handle (_ProposalEditorSheet) | `lib/ui/features/voice_log/views/voice_log_screen.dart` | 2034-2043 |
| `CalorieTargetSheet` (referencia buena) | `lib/ui/features/dashboard/views/calorie_target_sheet.dart` | 30 |
| Drag handle (CalorieTargetSheet) | `lib/ui/features/dashboard/views/calorie_target_sheet.dart` | 80-89 |
| `MacroDistributionSheet` (referencia buena) | `lib/ui/features/dashboard/views/macro_distribution_sheet.dart` | 14 |
| Drag handle (MacroDistributionSheet) | `lib/ui/features/dashboard/views/macro_distribution_sheet.dart` | 63-71 |

## Informes completos (en este mismo directorio)

- `01-investigation-edit-ingredients-home-entry.md` — mapeo de ficheros, símbolos y cadenas ARB.
- `02-investigation-drag-handle-patterns.md` — inventario completo de bottom sheets, patrón bueno vs. sospechoso.
- `03-investigation-navigation-stack.md` — router, shell, navigator, modal lock, call sites.
