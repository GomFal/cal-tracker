# Investigation: "Edit Ingredients" drag handle from Home / Dashboard

**Branch:** `develop`
**Scope:** Mobile Flutter app (`/home/antonio/code/cal-tracker/apps/mobile/lib`)
**Goal:** Mapear exhaustivamente los ficheros y símbolos relevantes para entender cómo se abre el editor de ingredientes desde el Home, qué tipo de modal/sheet se muestra, y por qué el drag handle no cierra el sheet.

---

## TL;DR (lectura rápida)

- La entrada desde el Dashboard está en `lib/ui/features/dashboard/views/dashboard_screen.dart`, método `_showMealItemEditor` (líneas 99-110), que usa `showModalBottomSheet<List<MealItem>>(...)` con `isScrollControlled: true` y `useSafeArea: true`.
- El widget mostrado es `MealItemEditorSheet` (`lib/ui/shared/meal_item_editor_sheet.dart`), llamado sin ningún `enableDrag` ni `barrierDismissible` personalizado (por lo tanto ambos toman el default `true`).
- El "drag handle" (la barrita gris) **está DENTRO del `SingleChildScrollView`** (líneas 60-174), no fuera. Esto es estructuralmente distinto del patrón de `calorie_target_sheet.dart` y `macro_distribution_sheet.dart`, donde el handle está **FUERA** del scrollable como primer hijo de un `Column` directo.
- El `SingleChildScrollView` interno consume el gesto vertical de drag antes de que el `BottomSheet`底层 de Flutter pueda reconocer el drag-to-dismiss. El handle visualmente "sugiere" que se puede arrastrar, pero el scrollable se traga el gesto.
- El sheet SÍ se cierra por: (a) el botón "Save edits" (`Navigator.of(context).pop(edited)`), (b) tap en la barrera (barrier), o (c) `Navigator.pop` programático. El drag-to-dismiss NO funciona como el usuario espera.
- Hay tests que cubren la entrada/salida del sheet (`dashboard_cleanup_widget_test.dart` y `meal_history_widget_test.dart`), pero **ningún test cubre el dismiss por drag**.

---

## Ficheros directamente sospechosos (probablemente el sheet problemático)

### 1. `lib/ui/shared/meal_item_editor_sheet.dart` (21.6 KB)

- **Ruta absoluta:** `/home/antonio/code/cal-tracker/apps/mobile/lib/ui/shared/meal_item_editor_sheet.dart`
- **Widget público:** `MealItemEditorSheet` (línea 12, `StatefulWidget`)
- **Tipo de sheet:** contenido pasado a `showModalBottomSheet` externo. NO usa `DraggableScrollableSheet` ni `showBottomSheet`. Es el `builder:` que retorna el contenido de un `showModalBottomSheet<List<MealItem>>` (ver dashboard_screen.dart:100-109).
- **Estructura del `build` (líneas 50-176):**
  ```dart
  return DecoratedBox(
    decoration: BoxDecoration(color: palette.surfaceSoft),
    child: Padding(
      padding: EdgeInsets.fromLTRB(18, 12, 18, bottomInset + 18),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // <-- DRAG HANDLE AQUÍ, DENTRO DEL SCROLLABLE -->
            Center(
              child: Container(
                width: 44, height: 4,
                decoration: BoxDecoration(
                  color: context.freshPalette.rule,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: FreshSpacing.lg),
            Text(l10n.commonEditIngredients, style: textTheme.titleLarge),
            // ... resto del contenido ...
          ],
        ),
      ),
    ),
  );
  ```
- **Drag handle:** líneas 65-77. `Container` de 44x4, color `palette.rule`, dentro de un `Center` que es hijo directo de la `Column` que vive DENTRO del `SingleChildScrollView`. **No es un widget independiente que pueda capturar el gesto; es solo un elemento visual dentro del área scrollable.**
- **Cómo se cierra el sheet:**
  - El sheet se cierra únicamente con `Navigator.of(context).pop(edited)` (línea 192) desde el botón "Save edits" (`FilledButton.icon` con key `save_${widget.keyPrefix}_item_edits_button`, líneas 188-191).
  - El sheet también se puede descartar por tap en la barrera (comportamiento por defecto de `showModalBottomSheet`, `barrierDismissible: true` por defecto, no se sobrescribe).
  - El drag-to-dismiss del handle **no funciona** porque el `SingleChildScrollView` se traga el drag vertical antes de que el `BottomSheet` interno de Flutter pueda reclamarlo.
- **Conexión a pantalla anterior:** es un sheet modal independiente; cuando se cierra correctamente, el `await showModalBottomSheet<List<MealItem>>(...)` en `_DashboardScreenState._showMealItemEditor` recibe el resultado `items` y llama a `viewModel.correctMealItems(meal, items)`. **No hay "parent screen" al que "volver"; el sheet es la ruta top del Navigator** (vía `showModalBottomSheet` con `useRootNavigator` no especificado, así que usa el Navigator más cercano). El usuario espera que al arrastrar el handle hacia abajo el sheet se cierre (pop) como en otras pantallas de la app.

### 2. `lib/ui/shared/nutrition_edit_sheet.dart` (12.0 KB)

- **Ruta absoluta:** `/home/antonio/code/cal-tracker/apps/mobile/lib/ui/shared/nutrition_edit_sheet.dart`
- **Widget público:** `NutritionEditSheet` (línea 22, `StatefulWidget`)
- **Tipo de sheet:** contenido de `showModalBottomSheet<NutritionEdit>` (ver meal_item_editor_sheet.dart:503-520 para el call site desde "Edit details").
- **Misma estructura problemática:** el handle está DENTRO del `SingleChildScrollView` (líneas 134-145, dentro del `Column` hijo del `SingleChildScrollView`).
- **Cierre:** `Navigator.of(context).pop(nutrition)` desde el botón Save (línea 304).
- **Observación:** este sheet es un sub-sheet anidado dentro del meal editor; el bug del drag-to-dismiss también le afecta, pero la queja del usuario es sobre el editor de ingredientes en sí (primer sheet que aparece), no sobre la sub-pantalla de detalles nutricionales.

### 3. `lib/ui/shared/editable_meal_item_controller.dart` (6.5 KB)

- **Ruta absoluta:** `/home/antonio/code/cal-tracker/apps/mobile/lib/ui/shared/editable_meal_item_controller.dart`
- **Tipo:** clase de controlador (no widget). Usada por `_MealItemEditorSheetState` para gestionar los `TextEditingController` de cada ingrediente (`nameController`, `quantityController`, `unitController`) y el override de nutrición.
- **Relevante para el bug:** ninguno directamente. Es solo el modelo de datos detrás del sheet.

### 4. `lib/ui/shared/nutrition_edit_components.dart` (7.4 KB)

- **Ruta absoluta:** `/home/antonio/code/cal-tracker/apps/mobile/lib/ui/shared/nutrition_edit_components.dart`
- **Tipo:** utilidades de UI compartidas (`NutritionMacroSummaryText`, `NutritionMacroWarningBanner`, `NutritionCalorieSuggestionSuffix`, `macroInputDecoration`, `macroSpan`, `macroFieldStyle`, `formatMacro`, `formatQuantity`, `normalizedText`).
- **Relevante para el bug:** ninguno. Solo son componentes auxiliares.

### 5. `lib/ui/core/shell_modal_lock.dart` (1.7 KB)

- **Ruta absoluta:** `/home/antonio/code/cal-tracker/apps/mobile/lib/ui/core/shell_modal_lock.dart`
- **Tipo:** controlador (`ShellModalLockController` + `ShellModalLockObserver`) que rastrea `PopupRoute`s abiertas para bloquear gestos del shell global.
- **Relevante para el bug:** observar si esta clase se inyecta en el Navigator que abre el `showModalBottomSheet` del editor. **El observer NO se instancia ni se monta en `app.dart` ni en `main.dart` (grep no encuentra uso de `ShellModalLockController`/`ShellModalLockObserver` fuera de este fichero), por lo que en principio no debería interferir con el drag del bottom sheet.** Aun así, conviene verificar en la fase de fix.

---

## Ficheros de comparación que sí funcionan (patrón bueno)

### 6. `lib/ui/features/dashboard/views/calorie_target_sheet.dart` (69.5 KB)

- **Ruta absoluta:** `/home/antonio/code/cal-tracker/apps/mobile/lib/ui/features/dashboard/views/calorie_target_sheet.dart`
- **Tipo de sheet:** contenido de `showModalBottomSheet<CalorieTargetSelection>` (call sites en dashboard_screen.dart:154, calorie_target_sheet.dart:175/185/264, settings_screen.dart:209).
- **Estructura del `build` (líneas 73-156):**
  ```dart
  return Padding(
    padding: EdgeInsets.fromLTRB(20, 12, 20, bottomInset + 20),
    child: SizedBox(
      height: maxHeight,                                // 0.86 * screen height
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // <-- DRAG HANDLE AQUÍ, COMO PRIMER HIJO DEL Column, FUERA DEL SCROLLABLE -->
          Center(
            child: Container(
              width: 44, height: 4,
              decoration: BoxDecoration(
                color: palette.rule,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: FreshSpacing.lg),
          Text(l10n.calorieTargetSheetTitle, style: textTheme.titleLarge),
          // ... resto del contenido (sin SingleChildScrollView envolviendo el handle) ...
        ],
      ),
    ),
  );
  ```
- **Drag handle:** líneas 80-89. `Container` de 44x4, color `palette.rule`. **Está como hijo directo de la `Column` raíz, NO dentro de un scrollable.** Como toda la `Column` no es scrollable, los gestos verticales de drag llegan al `BottomSheet`底层 de Flutter y el drag-to-dismiss funciona.
- **Cierre:** `Navigator.of(context).pop(CalorieTargetSelection(...))` desde el botón Save (línea 209) o desde `_showCalculator` (línea 200).

### 7. `lib/ui/features/dashboard/views/macro_distribution_sheet.dart` (37.8 KB)

- **Ruta absoluta:** `/home/antonio/code/cal-tracker/apps/mobile/lib/ui/features/dashboard/views/macro_distribution_sheet.dart`
- **Tipo de sheet:** contenido de `showModalBottomSheet<MacroDistributionConfig>` (call sites en dashboard_screen.dart:194, calorie_target_sheet.dart:185/264, macro_distribution_sheet.dart:146, settings_screen.dart:271).
- **Estructura del `build` (líneas 45-160):**
  ```dart
  return Material(
    color: palette.screen,
    child: Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottomInset + 20),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.9,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // <-- DRAG HANDLE AQUÍ, FUERA DEL SCROLLABLE -->
            Center(
              child: Container(width: 44, height: 4, ...),
            ),
            const SizedBox(height: FreshSpacing.lg),
            Text(widget.title ?? l10n.macroSheetTitle, ...),
            const SizedBox(height: FreshSpacing.lg),
            Expanded(
              child: SingleChildScrollView(             // <-- scrollable ANIDADO en Expanded, NO envuelve el handle
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final preset in MacroPreset.values) ...,
                    // ... resto del contenido scrollable ...
                  ],
                ),
              ),
            ),
            const SizedBox(height: FreshSpacing.md),
            FilledButton(key: const ValueKey('macro_distribution_save_button'), ...),
          ],
        ),
      ),
    ),
  );
  ```
- **Drag handle:** líneas 63-71. Mismo `Container` 44x4. **Está como primer hijo del `Column` raíz, NO dentro del `SingleChildScrollView` (que vive dentro de un `Expanded` más abajo).** El drag vertical fuera del área scrollable llega al `BottomSheet`底层 y el dismiss funciona.
- **Cierre:** `Navigator.of(context).pop(config)` desde el botón Save (línea 211).

### Patrón ganador (resumen)

| Aspecto | `calorie_target_sheet` / `macro_distribution_sheet` ✅ | `meal_item_editor_sheet` / `nutrition_edit_sheet` ❌ |
|---|---|---|
| Wrap externo | `Padding > SizedBox(height: ...) > Column` | `DecoratedBox > Padding > SingleChildScrollView > Column` |
| Posición del handle | Primer hijo del `Column` raíz, **fuera** de cualquier scrollable | Primer hijo del `Column`, pero ese `Column` vive **dentro** de un `SingleChildScrollView` |
| Scrollable del contenido | Si existe, está anidado en un `Expanded` o `Flexible` después del handle | El `SingleChildScrollView` envuelve **todo**, incluido el handle |
| Resultado del drag | El `BottomSheet`底层 reconoce el drag y dispara pop | El `SingleChildScrollView` reclama el gesto y el drag solo scrollea contenido (o no hace nada si el contenido cabe) |

---

## Ficheros de entrada al flujo desde el Home

### 8. `lib/ui/features/dashboard/views/dashboard_screen.dart` (32.8 KB)

- **Ruta absoluta:** `/home/antonio/code/cal-tracker/apps/mobile/lib/ui/features/dashboard/views/dashboard_screen.dart`
- **Entry point del bug:** método privado `_showMealItemEditor` (líneas 99-110):
  ```dart
  Future<void> _showMealItemEditor(
    BuildContext context,
    DashboardViewModel viewModel,
    Meal meal,
  ) async {
    final items = await showModalBottomSheet<List<MealItem>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => MealItemEditorSheet(
        meal: meal,
        keyPrefix: 'dashboard',
        searchFoods: viewModel.searchFoods,
      ),
    );
    if (!context.mounted || items == null) return;
    await viewModel.correctMealItems(meal, items);
  }
  ```
- **Configuración relevante del sheet:**
  - `isScrollControlled: true` → el sheet puede ocupar toda la altura de la pantalla.
  - `useSafeArea: true` → respeta las safe areas.
  - **No** se especifican `enableDrag` ni `barrierDismissible`, así que ambos son `true` (defaults de Flutter).
- **Cómo se invoca desde la UI:** el `_MealSection` (línea 91) itera `summary.meals` y renderiza `_MealRow` (línea 680). Cada `_MealRow` tiene un `FreshIconButton` con `key: ValueKey('dashboard_edit_meal_${meal.id}')` (línea 736) y `tooltip: l10n.dashboardEditIngredientsTooltip`, con `icon: Icons.edit_rounded` (líneas 732-737). Al pulsarlo, llama a `onEdit(meal)` que llega hasta `_showMealItemEditor` (línea 96, `onEditMeal: (meal) => _showMealItemEditor(context, viewModel, meal)`).
- **Comportamiento esperado por el usuario:** pulsar el icono de edición (lápiz) en la fila de una comida del Dashboard debería abrir el sheet; al arrastrar la barrita gris hacia abajo el sheet debería cerrarse y volver al Dashboard. **El sheet se abre, pero el drag-to-dismiss no funciona** porque, como se documenta arriba, el handle está dentro del `SingleChildScrollView` del `MealItemEditorSheet`.

### 9. `lib/ui/features/meal_history/views/meal_history_screen.dart` (parte del mismo flujo)

- **Ruta absoluta:** `/home/antonio/code/cal-tracker/apps/mobile/lib/ui/features/meal_history/views/meal_history_screen.dart`
- **Entry point alternativo:** método `_showMealItemEditor` (líneas 148-160) con la **misma** estructura (mismo `showModalBottomSheet<List<MealItem>>(...)` envolviendo `MealItemEditorSheet`). El usuario llega aquí desde el tab de historial y desde el action sheet `_showMealActions` (líneas 86-126) que muestra la opción "Edit ingredients".
- **Misma estructura problemática** — el bug es transversal al sheet, no a la entrada. Confirmado en el código.

### 10. `lib/main.dart` (482 B)

- **Ruta absoluta:** `/home/antonio/code/cal-tracker/apps/mobile/lib/main.dart`
- **Contenido:** bootstrap de la app. `runApp(const CalTrackerBootstrap())`. No interviene en el flujo del sheet, pero es el punto de entrada del proceso.

### 11. `lib/app/app.dart` (11.8 KB)

- **Ruta absoluta:** `/home/antonio/code/cal-tracker/apps/mobile/lib/app/app.dart`
- **Relevancia:** monta `CalTrackerBootstrap` (línea 37) y configura el `MaterialApp.router` con `MobileUpdateDialogHost` envolviendo el `child`. **No se instancia `ShellModalLockController`/`ShellModalLockObserver` aquí**, así que ese lock no está activo y no es responsable del bug. Verificado por grep — la única definición está en `lib/ui/core/shell_modal_lock.dart` y no se referencia desde `app.dart`, `main.dart` ni `router.dart`.

### 12. `lib/app/router.dart` (7.9 KB)

- **Ruta absoluta:** `/home/antonio/code/cal-tracker/apps/mobile/lib/app/router.dart`
- **Relevancia:** solo se comprobó que no hay una integración de `ShellModalLockController` con el `Navigator`. No es responsable del bug.

### 13. `lib/ui/core/app_shell.dart` (19.0 KB)

- **Ruta absoluta:** `/home/antonio/code/cal-tracker/apps/mobile/lib/ui/core/app_shell.dart`
- **Tipo:** shell con bottom nav (`_FreshBottomNav`) y side nav (`_FreshSideNav`). Aloja `_CenterVoiceButton` (línea 380) con `_BubbleTip` (línea 580) que se muestra sobre rutas de creación de plantillas.
- **Relevancia para el bug:** el shell está montado en `AppShell.build` (línea 50) que envuelve `navigationShell` (el `StatefulNavigationShell` de go_router). **No se referencia `ShellModalLockController` aquí**, así que el lock no está activo. La navegación de tabs tampoco captura gestos verticales globales (es `BottomNavigationBar` + `PageView` interno en `SlidingBranchContainer`). No es responsable del bug.

---

## Localizaciones ARB relacionadas

### 14. `lib/l10n/app_en.arb`

- **Ruta absoluta:** `/home/antonio/code/cal-tracker/apps/mobile/lib/l10n/app_en.arb`
- **Cadenas clave:**
  - línea 29: `"commonEditIngredients": "Edit ingredients"`
  - línea 30: `"commonSaveEdits": "Save edits"`
  - línea 32: `"commonAddIngredient": "Add ingredient"`
  - línea 33: `"commonDeleteIngredient": "Delete ingredient"`
  - línea 34: `"commonCheckIngredientDetails": "Check ingredient details"`
  - línea 35: `"commonIngredientDetailsError": "Each ingredient needs a name, amount, unit, calories, and non-negative macros."`
  - línea 36: `"commonAddAtLeastOneIngredient": "Add at least one ingredient."`
  - línea 39: `"mealEditorIngredientsSection": "Ingredients"`
  - línea 40: `"mealEditorEditDetails": "Edit details"`
  - línea 41: `"mealEditorNutritionDetails": "Nutrition details"`
  - línea 42: `"mealEditorApplySuggestion": "Apply suggestion"`
  - línea 518: `"dashboardEditIngredientsTooltip": "Edit ingredients"`
  - línea 519: `"dashboardDeleteMealTooltip": "Delete meal"`
  - línea 520: `"dashboardCouldNotDeleteMeal": "Could not delete meal."`

### 15. `lib/l10n/app_es.arb`

- **Ruta absoluta:** `/home/antonio/code/cal-tracker/apps/mobile/lib/l10n/app_es.arb`
- **Cadenas clave (mismas keys que en `app_en.arb`):**
  - línea 29: `"commonEditIngredients": "Editar ingredientes"`
  - línea 30: `"commonSaveEdits": "Guardar cambios"`
  - línea 32: `"commonAddIngredient": "Añadir ingrediente"`
  - línea 33: `"commonDeleteIngredient": "Eliminar ingrediente"`
  - línea 39: `"mealEditorIngredientsSection": "Ingredientes"`
  - línea 40: `"mealEditorEditDetails": "Editar detalles"`
  - línea 41: `"mealEditorNutritionDetails": "Detalles nutricionales"`
  - línea 254: `"dashboardEditIngredientsTooltip": "Editar ingredientes"`
  - línea 255: `"dashboardDeleteMealTooltip": "Eliminar comida"`
  - línea 256: `"dashboardCouldNotDeleteMeal": "No se pudo eliminar la comida."`
- **Observación:** las traducciones están sincronizadas (1:1 con `app_en.arb`).

---

## Tests existentes

### 16. `apps/mobile/test/dashboard_cleanup_widget_test.dart`

- **Ruta absoluta:** `/home/antonio/code/cal-tracker/apps/mobile/test/dashboard_cleanup_widget_test.dart`
- **Tests relevantes para el sheet:**
  - `'dashboard meal cards edit explicit ingredients'` (línea 281): abre el sheet del editor desde el Dashboard (`dashboard_edit_meal_meal-1`), valida la edición de ingredientes con el flow de "Edit details" → `NutritionEditSheet`, y verifica `correctMealItems`.
  - `'dashboard meal editor adds an ingredient from food search'` (línea 348).
  - `'dashboard meal editor replaces an ingredient from food search'` (línea 421).
- **Cobertura del dismiss por drag:** **ninguna**. Todos los tests cierran el sheet pulsando `save_dashboard_item_edits_button`. No se valida `tester.drag`, `tester.fling`, ni `Navigator.canPop` tras un drag.

### 17. `apps/mobile/test/meal_history_widget_test.dart`

- **Ruta absoluta:** `/home/antonio/code/cal-tracker/apps/mobile/test/meal_history_widget_test.dart`
- **Tests relevantes:**
  - `'edits history meals with explicit ingredients'` (línea 18): flujo desde el historial, abre el action sheet, toca "Edit ingredients" (`find.text('Edit ingredients')`), entra al editor, edita y guarda.
  - `'measurement controls adjust quantities and wrap presets'` (línea 105): cubre la UI de los steppers y presets.
- **Cobertura del dismiss por drag:** **ninguna**. Cierre siempre vía Save.

### 18. `apps/mobile/test/macro_distribution_test.dart`

- **Ruta absoluta:** `/home/antonio/code/cal-tracker/apps/mobile/test/macro_distribution_test.dart`
- **Relevancia:** demuestra el patrón de testing de `showModalBottomSheet<MacroDistributionConfig>` con `tester.pumpWidget` + `showModalBottomSheet` directo. Útil como referencia para añadir un test del dismiss por drag del `MealItemEditorSheet`.

### 19. `apps/mobile/patrol_test/patrol_smoke_test.dart`

- **Ruta absoluta:** `/home/antonio/code/cal-tracker/apps/mobile/patrol_test/patrol_smoke_test.dart`
- **Tests relevantes:** `preserves Spanish meat and rice quantities and opens editor` (línea 134), que abre el editor de ingredientes desde la propuesta de voz. Confirma `find.text('Edit ingredients')` pero no cubre dismiss por drag.
- **Cobertura del dismiss por drag:** **ninguna**.

### Resumen de cobertura

| Test | Cubre abrir editor desde Home? | Cubre dismiss por drag? |
|---|---|---|
| `dashboard_cleanup_widget_test.dart` | Sí (varios) | **No** |
| `meal_history_widget_test.dart` | Sí (varios) | **No** |
| `macro_distribution_test.dart` | No (es otro sheet) | No |
| `patrol_smoke_test.dart` | Sí (vía voice log) | **No** |

---

## Observaciones sobre el patrón drag handle

1. **Inconsistencia entre sheets.** Todos los sheets del proyecto dibujan el mismo handle visual (`Container` 44x4, `palette.rule`, `borderRadius.circular(999)`) — verificado en `meal_item_editor_sheet.dart:67`, `nutrition_edit_sheet.dart:139`, `calorie_target_sheet.dart:82, 238, 311`, `macro_distribution_sheet.dart:66, 313`, `voice_log_screen.dart:1808, 2037`, `meal_history_screen.dart:112`, `hydration_goal_sheet.dart:54`, `settings_screen.dart:361, 426, 570`. **El handle es solo decorativo en todos los casos; ningún `GestureDetector` está atado al handle.** El dismiss por drag depende 100% del `BottomSheet`底层 de Flutter, que reconoce el drag en la zona "scrim" o en la zona del sheet por encima del contenido scrollable.

2. **El handle solo "funciona" como drag-to-dismiss si NO está dentro de un scrollable.** En `calorie_target_sheet.dart` y `macro_distribution_sheet.dart` el handle está en un `Column` raíz, fuera de cualquier `SingleChildScrollView`/`ListView`, y el `SizedBox(height: 0.86/0.9 * screen height)` acota la altura. El usuario arrastra el handle → el `BottomSheet`底层 recibe el drag → dismiss. **Esto es lo que el usuario espera también en el editor de ingredientes.**

3. **El editor de ingredientes (y el sub-sheet de nutrition details) envuelven TODO el contenido, incluido el handle, en un `SingleChildScrollView` (meal_item_editor_sheet.dart:60, nutrition_edit_sheet.dart:133).** El `SingleChildScrollView` reclama el `VerticalDragGestureRecognizer` en el área del handle. Cuando el usuario arrastra la barrita hacia abajo:
   - Si el contenido cabe sin scrollear: el drag se queda en el scrollable (que está al inicio, así que intenta scrollear hacia abajo y rebota, sin hacer nada visible).
   - Si el contenido excede: el drag scrollea el contenido, **nunca** llega al `BottomSheet`底层.
   - En ambos casos, el sheet no se cierra. **Esto explica exactamente el bug reportado.**

4. **El sheet usa `isScrollControlled: true`** (dashboard_screen.dart:102). Esto es necesario para que el sheet pueda expandirse a pantalla casi completa (el `MealItemEditorSheet` contiene listas largas de ingredientes + food search + detalles). No es la causa del bug, pero el contenido extenso hace que el `SingleChildScrollView` sea obligatorio para evitar overflow.

5. **No hay un `DraggableScrollableSheet` ni un mecanismo custom de drag-to-dismiss** en ningún sitio del proyecto. El drag-to-dismiss depende del comportamiento por defecto de `showModalBottomSheet`, que solo funciona fuera de un scrollable interno o cuando el scrollable está en su límite superior y "cede" el gesto (lo cual no ocurre consistentemente con `SingleChildScrollView` no restringido).

6. **El `shell_modal_lock.dart` no está activo.** El `ShellModalLockController`/`ShellModalLockObserver` están definidos pero **no se montan en el `Navigator` ni en `app.dart`/`main.dart`/`router.dart`**. No es responsable del bug, pero es un punto a tener en cuenta si en el fix se introduce un observer del Navigator (debería respetar la lista de `PopupRoute` que ya rastrea).

7. **El sheet sí tiene otras formas válidas de cerrarse** confirmadas en código: (a) el botón "Save edits" (`FilledButton.icon` con `key: ValueKey('save_${keyPrefix}_item_edits_button')`, `meal_item_editor_sheet.dart:188-191`) llama a `Navigator.of(context).pop(edited)` en `_save` (línea 192); (b) tap en la barrera exterior (default `barrierDismissible: true`); (c) `Navigator.pop` programático. El drag-to-dismiss del handle es la única vía que el usuario intenta y que falla.

---

## Resumen de símbolos relevantes (tabla rápida)

| Símbolo | Tipo | Fichero | Línea |
|---|---|---|---|
| `DashboardScreen` | `StatefulWidget` (root del Home) | `lib/ui/features/dashboard/views/dashboard_screen.dart` | 27 |
| `_DashboardScreenState._showMealItemEditor` | método (entry point del bug) | `lib/ui/features/dashboard/views/dashboard_screen.dart` | 99 |
| `_MealRow` (icono edit en cada comida) | `StatelessWidget` | `lib/ui/features/dashboard/views/dashboard_screen.dart` | 680 |
| `MealItemEditorSheet` | `StatefulWidget` (sheet problemático) | `lib/ui/shared/meal_item_editor_sheet.dart` | 12 |
| `_MealItemEditorSheetState.build` | método (render) | `lib/ui/shared/meal_item_editor_sheet.dart` | 50 |
| Drag handle (Container 44x4) | `Container` | `lib/ui/shared/meal_item_editor_sheet.dart` | 65-77 |
| Botón Save (Navigator.pop) | `FilledButton.icon` | `lib/ui/shared/meal_item_editor_sheet.dart` | 188-191 |
| `_save` (pop con datos) | método | `lib/ui/shared/meal_item_editor_sheet.dart` | 192-203 |
| `NutritionEditSheet` | `StatefulWidget` (sub-sheet con mismo bug) | `lib/ui/shared/nutrition_edit_sheet.dart` | 22 |
| Drag handle (NutritionEditSheet) | `Container` | `lib/ui/shared/nutrition_edit_sheet.dart` | 134-145 |
| `EditableMealItemController` | clase de controlador (no afecta el bug) | `lib/ui/shared/editable_meal_item_controller.dart` | 14 |
| `CalorieTargetSheet` | `StatefulWidget` (patrón bueno) | `lib/ui/features/dashboard/views/calorie_target_sheet.dart` | 30 |
| Drag handle (CalorieTargetSheet) | `Container` (fuera del scrollable) | `lib/ui/features/dashboard/views/calorie_target_sheet.dart` | 80-89 |
| `MacroDistributionSheet` | `StatefulWidget` (patrón bueno) | `lib/ui/features/dashboard/views/macro_distribution_sheet.dart` | 14 |
| Drag handle (MacroDistributionSheet) | `Container` (fuera del scrollable) | `lib/ui/features/dashboard/views/macro_distribution_sheet.dart` | 63-71 |
| `ShellModalLockController` | `ChangeNotifier` (no activo) | `lib/ui/core/shell_modal_lock.dart` | 3 |
| `AppShell` | `StatelessWidget` (shell) | `lib/ui/core/app_shell.dart` | 45 |
| `CalTrackerBootstrap` | `StatefulWidget` (root) | `lib/app/app.dart` | 37 |
| `MealHistoryScreen._showMealItemEditor` | método (mismo bug desde historial) | `lib/ui/features/meal_history/views/meal_history_screen.dart` | 148-160 |
| `commonEditIngredients` | key ARB | `lib/l10n/app_en.arb:29` / `lib/l10n/app_es.arb:29` | — |
| `dashboardEditIngredientsTooltip` | key ARB | `lib/l10n/app_en.arb:518` / `lib/l10n/app_es.arb:254` | — |

---

## Conclusión de la investigación (sin propuesta de fix)

El drag handle del `MealItemEditorSheet` (y por extensión el del sub-sheet `NutritionEditSheet`) **no cierra el sheet** porque el handle es un simple `Container` decorativo que vive **dentro** del `SingleChildScrollView` que envuelve todo el contenido. El scrollable reclama el gesto vertical de drag, de modo que el `BottomSheet`底层 de Flutter nunca llega a reconocer un drag-to-dismiss.

El patrón de sheets que SÍ funcionan (`CalorieTargetSheet`, `MacroDistributionSheet`) mantiene el handle como primer hijo de un `Column` raíz, fuera del scrollable. En esos casos el drag vertical en la zona del handle se propaga al `BottomSheet`底层 y dispara el dismiss correctamente.

Ninguna de las dos formas usa `DraggableScrollableSheet`, `enableDrag: true` explícito, ni un `GestureDetector` propio sobre el handle. Toda la responsabilidad del drag-to-dismiss es del framework, y solo funciona si el handle no queda atrapado dentro de un scrollable.

No hay tests que cubran el dismiss por drag del editor de ingredientes desde el Home, así que el bug pasó inadvertido en la suite actual.
