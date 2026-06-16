# Issue 02 — Settings tab: investigation map

**Estado:** Investigación. No propone fix ni plan. Sólo mapea el estado actual.
**Rama actual:** `develop`
**Origen del report:** Usuario — reagrupación de opciones en la pestaña de Settings / Ajustes.
**Fecha:** 2026-06-15

---

## 1. Resumen ejecutivo

`SettingsScreen` es la pestaña `menu` del shell (`navMenu`, `keyName: 'menu'`, ruta `/settings`).
Se compone de un `ContentFrame` (que internamente usa `FreshPage` → `CustomScrollView` con `SliverToBoxAdapter`) y un único `Column` vertical. **No existe** ningún grid (`GridView`/`SliverGrid`/`Wrap`) en `lib/` — la app no usa grids en ningún sitio.

Las opciones se renderizan como un único `Column` de tarjetas full-width (`FreshCard` 16 px padding), separadas por `SizedBox(height: FreshSpacing.md)`. La cabecera (usuario) y el botón de logout están fuera de cualquier "sección" — son hijos sueltos del mismo `Column`.

No hay cabeceras de sección (`FreshSectionTitle` existe en `design_system.dart` línea 695 pero **no se usa** en `settings_screen.dart`). La palabra "sección" en este informe se refiere a los bloques visuales del `Column` que el usuario percibe.

---

## 2. Estructura actual de `SettingsScreen`

### 2.1 Andamiaje del widget

- `lib/ui/features/settings/views/settings_screen.dart`
- Root: `ContentFrame(title: l10n.settingsTitle, subtitle: l10n.settingsSubtitle, child: Column(...))` (línea 53–183).
- `ContentFrame` (línea 1–24) sólo delega en `FreshPage` con `maxWidth: 760` (en `design_system.dart:265`).
- `FreshPage` (línea 262–293 de `design_system.dart`) usa `SafeArea` + `Center` + `ConstrainedBox(maxWidth: 760)` + `CustomScrollView`. El contenido va dentro de un `SliverPadding(padding: EdgeInsets.fromLTRB(20, 10, 20, 24))` y un `SliverToBoxAdapter`.
- La cabecera de la página (`FreshHeader`) la construye `FreshPage` con `title = l10n.settingsTitle` ("Menu" / "Menú") y `subtitle = l10n.settingsSubtitle` ("Account and preferences" / "Cuenta y preferencias").
- `SettingsScreen` es `StatefulWidget` con `initState` que llama a `SettingsViewModel.load()` (línea 30–35).
- En `build` (línea 38–183) se hace `context.watch<...>` de: `AuthViewModel`, `SettingsViewModel`, `LocaleViewModel`, `ThemeModeViewModel`. **No hay `context.read` de `SettingsViewModel` dentro del `build`** — sólo en handlers `onTap` y al refrescar.

### 2.2 Orden de hijos del `Column` (de arriba a abajo, tal como se renderizan)

| # | Bloque | Líneas | Tipo / widget | Ancho | Notas |
|---|---|---|---|---|---|
| 1 | **Cabecera de usuario** (avatar + nombre + email) | 54–99 | `FreshCard` radius `FreshRadii.xl`, `color: palette.limeSoft` | `Column(stretch)` → full-width | Único sitio donde se renderiza `Icons.person_rounded` y el email. Muestra `user?.displayName ?? l10n.fallbackUserName` (línea 79). |
| 2 | `SizedBox(height: FreshSpacing.lg)` (16) | 100 | separador | – | |
| 3 | Loading banner | 101–104 | `LinearProgressIndicator(minHeight: 3)` + spacer | – | Sólo cuando `settings.isLoading == true` |
| 4 | Error banner | 105–113 | `FreshStatusBanner` con `palette.coral` y `l10n.settingsCouldNotUpdateGoals` | full-width | Sólo cuando `settings.error != null` |
| 5 | **Opción: Hydration goal** | 114–123 | `_SettingsGoalRow` (icono + título + subtítulo + chevron) | full-width | Abre `HydrationGoalSheet` |
| 6 | `SizedBox(height: FreshSpacing.md)` (12) | 124 | separador | – | |
| 7 | **Opción: Calorie target** | 125–138 | `_SettingsGoalRow` | full-width | Abre `CalorieTargetSheet` (compartido con Dashboard) |
| 8 | `SizedBox(height: FreshSpacing.md)` | 139 | separador | – | |
| 9 | **Opción: Macro distribution** | 140–149 | `_SettingsGoalRow` | full-width | Abre `MacroDistributionSheet` o `_MacroRequiresCaloriesSheet` (gate) |
| 10 | `SizedBox(height: FreshSpacing.md)` | 150 | separador | – | |
| 11 | **Opción: Language** | 151–159 | `_SettingsGoalRow` | full-width | Abre el sheet inline de `_showLanguageSheet` (no en fichero aparte) |
| 12 | `SizedBox(height: FreshSpacing.md)` | 160 | separador | – | |
| 13 | **Opción: Theme / Appearance** | 161–169 | `_SettingsGoalRow` | full-width | Abre el sheet inline de `_showThemeSheet` (no en fichero aparte) |
| 14 | `SizedBox(height: FreshSpacing.md)` | 170 | separador | – | |
| 15 | **Card: Data sources** | 171–176 | `_DataSourcesCard` (FreshCard `shadow: false`, padding 16) | full-width | Card informativa con texto estático (Open Food Facts + USDA). **No es tappable.** |
| 16 | `SizedBox(height: FreshSpacing.xl)` (24) | 177 | separador | – | |
| 17 | **Botón Logout** | 178–181 | `OutlinedButton.icon` con `Icons.logout_rounded` y `Text(l10n.settingsLogOut)` | full-width (stretch del Column) | `onPressed: auth.logout` |

**Importante:** ninguno de los hijos usa `Wrap`, `GridView`, `Row` con `Expanded`s múltiples, ni anchura fija. Todos son `Column` stretch → full-width.

### 2.3 Tabla detallada de cada opción (`_SettingsGoalRow` y cards)

Para todas las `_SettingsGoalRow` (filas 5, 7, 9, 11, 13 del `Column`):

- `icon` es un `Icons.*` Material, color de icono variable.
- `color` del `FreshIconChip` viene de `palette.{water|orange|leaf|mint|limeDeep}`.
- `title`: clave ARB `settings*Title` o `settings*`.
- `subtitle`: clave ARB `settings*Subtitle(...)` o `settingsNotSet` o `settingsTheme*` / `settingsLanguageNativeName`.
- `onTap`: **deshabilitado** (`null`) si `settings.isLoading || settings.isSaving`; en caso contrario, llama a la función `_show*` correspondiente.
- Trailing: `Icon(Icons.chevron_right_rounded)` (literal, no `key`).
- Render: `FreshCard(padding: EdgeInsets.all(16), onTap: ...) → Row([FreshIconChip, SizedBox(12), Expanded(Column[Text(title), Text(subtitle, inkMuted)]), Icon(chevron)])` — `settings_screen.dart:609-643`.

| Bloque | `ValueKey` (row) | Icon | Color | `title` (ARB) | `subtitle` (ARB) | onTap → | Sub-sheet / destino |
|---|---|---|---|---|---|---|---|
| Hydration goal | `hydration_goal_row` | `Icons.water_drop_rounded` | `palette.water` | `settingsHydrationGoal` | `settingsHydrationGoalSubtitle(liters)` o `settingsNotSet` | `_showHydrationGoalSheet(context, goals)` | `HydrationGoalSheet` (fichero aparte, devuelve `double?`) |
| Calorie target | `calorie_target_row` | `Icons.flag_rounded` | `palette.orange` | `settingsCalorieTarget` | `settingsCalorieTargetSubtitle(calories)` o `settingsNotSet` | `_showCalorieTargetSheet(context, goals)` | `CalorieTargetSheet` (compartido con dashboard) |
| Macro distribution | `macro_distribution_row` | `Icons.pie_chart_rounded` | `palette.leaf` | `settingsMacroDistributionTitle` | `settingsMacroPresetSubtitle` / `settingsMacroPercentSubtitle` / `settingsMacroGramsSubtitle` / `settingsNotSet` (computado en `_macroDistributionSubtitle`, líneas 301–328) | `_showMacroDistributionEntry(context, goals)` | `MacroDistributionSheet` (con gate `_MacroRequiresCaloriesSheet` si no hay calorías) |
| Language | `language_settings_row` | `Icons.translate_rounded` | `palette.mint` | `settingsLanguageTitle` | `lookupAppLocalizations(locale).settingsLanguageNativeName` (línea 459) | `_showLanguageSheet(context)` | `showModalBottomSheet` inline (líneas 412–458) |
| Theme / Appearance | `theme_settings_row` | `Icons.contrast_rounded` | `palette.limeDeep` | `settingsThemeTitle` | `settingsThemeSystem` / `settingsThemeLight` / `settingsThemeDark` (computado en `_themeModeSubtitle`, líneas 330–335) | `_showThemeSheet(context)` | `showModalBottomSheet` inline (líneas 337–410) |
| Data sources | _(no key)_ | `Icons.source_rounded` (dentro del card) | `palette.orange` | `settingsDataSourcesTitle` | `settingsDataSourcesSubtitle` + `settingsDataSourcesOpenFoodFacts` + `settingsDataSourcesUsda` | _(no tap; widget estático)_ | – |
| Logout | _(no key)_ | `Icons.logout_rounded` (dentro del `OutlinedButton.icon`) | – | `settingsLogOut` | _(sin subtítulo)_ | `auth.logout` (callback directo, no async-await) | – |

### 2.4 Clasificación por el criterio del usuario

**1. "Opciones de calorías"** (en la pantalla actual):

- `calorie_target_row` (Calorie target) — `_SettingsGoalRow` con `Icons.flag_rounded`, `palette.orange`.
- `macro_distribution_row` (Macro distribution) — `_SettingsGoalRow` con `Icons.pie_chart_rounded`, `palette.leaf`.
- Hidratación **no** es calorías: es un objetivo hídrico con icono `Icons.water_drop_rounded` y `palette.water`. En el sheet se ofrece unidad en litros/oz (`HydrationGoalUnit` enum). En el plan del usuario, hidratación **no entra** en el grupo de "opciones de calorías".

**2. "Configuración de la app"** (lenguaje + apariencia):

- `language_settings_row` — `Icons.translate_rounded`, `palette.mint`.
- `theme_settings_row` — `Icons.contrast_rounded`, `palette.limeDeep`.
- No hay otras (notificaciones, unidades, etc. no existen como opciones de Settings).

**3. "Datos de usuario"** (la cabecera):

- `FreshCard` con `radius: FreshRadii.xl`, `color: palette.limeSoft`, contenido `Row` con avatar circular 58×58 (icono `Icons.person_rounded`, 30 px, `palette.limeDeep`) y `Expanded(Column[Text(displayName), Text(email)])` (líneas 54–99).

**4. "Logout"** (botón al final):

- `OutlinedButton.icon(onPressed: auth.logout, icon: Icon(Icons.logout_rounded), label: Text(l10n.settingsLogOut))` (líneas 178–181).
- `auth.logout` viene de `AuthViewModel.logout()` (fichero `lib/ui/features/auth/view_models/auth_view_model.dart:117`).

---

## 3. Ficheros directamente sospechosos (los que se tocarán al reagrupar)

| Fichero | Por qué |
|---|---|
| `apps/mobile/lib/ui/features/settings/views/settings_screen.dart` | Único fichero del `build` y de los sheets inline (idioma, tema, gate de macros). Toda la reorganización vive aquí. |
| `apps/mobile/lib/ui/features/settings/views/hydration_goal_sheet.dart` | Sub-sheet que se dispara desde el row de hidratación (no cambia su contenido; sí puede cambiar la fila que lo dispara). |
| `apps/mobile/lib/ui/features/settings/view_models/settings_view_model.dart` | Estado y mutaciones que consumen los handlers del `build`. No necesita cambios para reagrupar visualmente, pero su contrato se mantiene. |
| `apps/mobile/lib/ui/core/design_system.dart` | Tiene los tokens (`FreshSpacing`, `FreshRadii`, `FreshCard`, `FreshIconChip`, `FreshSectionTitle`). `FreshSectionTitle` ya existe (línea 695) pero **no se usa** en `settings_screen.dart`; `FreshCard` y `FreshIconChip` son los bloques que se reusarán. |
| `apps/mobile/lib/ui/core/content_frame.dart` | Wrapper muy fino (`title + subtitle + child`); no cambia. |
| `apps/mobile/lib/l10n/app_en.arb` y `app_es.arb` | Sólo si se añaden cadenas de cabecera de sección o réplicas. Las actuales (ver §6) ya cubren lo que existe. |
| `apps/mobile/lib/l10n/generated/app_localizations*.dart` | Regenerado al añadir ARB; los getters `String get settings*` se generan automáticamente. |

Ficheros donde las opciones viven en **otros** sitios (no son `SettingsScreen` pero reutilizan las mismas claves ARB y los mismos sheets):

| Fichero | Relación |
|---|---|
| `apps/mobile/lib/ui/features/dashboard/views/dashboard_screen.dart` | Reutiliza `CalorieTargetSheet`, `MacroDistributionSheet` y `PostCalorieSaveMacroPrompt`. También refresca `SettingsViewModel` tras guardar (líneas 179, 216). El dashboard **no** re-renderiza las opciones de Settings, sólo dispara los sheets. |
| `apps/mobile/lib/ui/features/dashboard/views/calorie_target_sheet.dart` | Sheet "bueno" según `specs/issues/02-investigation-drag-handle-patterns.md` (handle no dentro de scroll). Lo abre Settings y Dashboard. |
| `apps/mobile/lib/ui/features/dashboard/views/macro_distribution_sheet.dart` | Idem, "bueno". |
| `apps/mobile/lib/app/locale_view_model.dart` | Estado del idioma; lo consume `SettingsScreen` y `AppShell`. |
| `apps/mobile/lib/app/theme_mode_view_model.dart` | Estado del tema; lo consume `SettingsScreen` y `AppShell`. |
| `apps/mobile/lib/app/router.dart` (línea 188) | Único `GoRoute` que mapea a `SettingsScreen` (rama `StatefulShellBranch` con path `/settings`). |

---

## 4. ViewModel de Settings

`lib/ui/features/settings/view_models/settings_view_model.dart` (155 líneas).

### 4.1 Dependencias del constructor

- `AuthRepository _authRepository`
- `NutritionRepository _nutritionRepository`
- `DateTime Function()? now` (clock inyectable para tests; default `DateTime.now`)

### 4.2 Estado privado

| Campo | Tipo | Notas |
|---|---|---|
| `_goals` | `DailyGoals?` | Cacheado en memoria + persistido en `NutritionRepository.cachedDailySummary`. |
| `_isLoading` | `bool` | `true` sólo cuando **no** hay `_goals` visibles. |
| `_isRefreshing` | `bool` | `true` cuando hay datos visibles y se está re-pidiendo. |
| `_isSaving` | `bool` | `true` durante `updateGoals` o `setTrustedMode`. |
| `_error` | `String?` | Mensaje user-visible (no se muestra si ya había datos). |

### 4.3 Getters públicos

| Getter | Semántica |
|---|---|
| `goals` | `DailyGoals?` actual. |
| `hasVisibleData` | `_goals != null`. |
| `isLoading` | `_isLoading && !hasVisibleData` (sin datos + cargando). |
| `isRefreshing` | `_isRefreshing` (con datos + refrescando). |
| `isSaving` | `_isSaving`. |
| `error` | `String?` user-visible. |

### 4.4 Métodos públicos

- `Future<void> load({bool forceRefresh = false})` (línea 41–79)
  - Si no es `forceRefresh`, primero lee del cache (`_nutritionRepository.cachedDailySummary`) y notifica.
  - Después pide `_nutritionRepository.refreshDailySummary(date, force: forceRefresh)`.
  - En éxito: `_goals = goalsFromSummary(summary)`, `_error = null`.
  - En fallo con datos visibles: silencioso (no sobreescribe `_error` para no romper UX stale-while-revalidate). En fallo sin datos: setea `_error` con `userVisibleErrorMessage(..., context: UserErrorContext.settingsLoad)`.
- `Future<DailyGoals?> updateGoals({int? calories, double? hydrationGoalLiters, String? calorieTargetSource, MacroDistributionConfig? macroConfig, int? macroCalorieTarget})` (línea 81–125)
  - Aplica override optimista con `goalsWithOverrides` y persiste en el cache.
  - Llama a `_nutritionRepository.updateDailyGoals(...)`.
  - En éxito: persiste en cache, devuelve el `DailyGoals`.
  - En fallo: **rollback** a `_previous` (revierte cache y memoria) y devuelve `null`.
- `Future<AuthUser?> setTrustedMode(bool enabled)` (línea 127–141)
  - Pasa por `AuthRepository.updateTrustedMode(enabled)`. **No se usa en `SettingsScreen` actualmente** (sólo en backend / otros lugares). Está aquí por completitud.
- `void reset()` (línea 143–149)
  - Limpia todo el estado. Lo invoca `app.dart:311` durante logout.

### 4.5 Flujos asíncronos observables en UI

- `LinearProgressIndicator` sólo cuando `settings.isLoading` (es decir, primer load sin cache).
- Filas `_SettingsGoalRow` se **deshabilitan** (`onTap: null`) durante `isLoading || isSaving`. `isRefreshing` **no** deshabilita (stale-while-revalidate).
- `FreshStatusBanner` se muestra si `settings.error != null` (sólo se setea si no había datos visibles o durante `updateGoals`).
- Tras `updateGoals`, `SettingsScreen` invoca `_refreshGoalConsumers` (líneas 290–298) que en paralelo recarga `DashboardViewModel`, `SettingsViewModel` y `MealHistoryViewModel` con `forceRefresh: true`.

---

## 5. Sub-sheet `hydration_goal_sheet.dart`

`lib/ui/features/settings/views/hydration_goal_sheet.dart` (393 líneas).

### 5.1 Estructura

- `StatefulWidget` con un único `required this.initialLiters`.
- Estado interno:
  - `double _liters` (redondeado a 0.25 L).
  - `HydrationGoalUnit _unit` (litros u onzas; `enum` declarado en la línea 6).
- Constantes de clase: `_stepLiters = 0.25`, `_maxLiters = 10.0`, `_ouncesPerLiter = 33.8140227`.

### 5.2 Layout del `build` (líneas 39–148)

- `Padding(EdgeInsets.fromLTRB(20, 12, 20, bottomInset + 20))` — respeta teclado.
- `SizedBox(height: maxHeight)` con `maxHeight = MediaQuery.sizeOf(context).height * 0.86` (línea 41) — altura fija al 86 % de la pantalla.
- `LayoutBuilder` que activa `compact = constraints.maxHeight < 560` (línea 47).
- `Column(crossAxisAlignment: CrossAxisAlignment.stretch)` con:
  1. **Drag handle** (líneas 52–61): `Center(child: Container(width: 44, height: 4, decoration: BoxDecoration(color: palette.rule, borderRadius: BorderRadius.circular(999))))`.
  2. `SizedBox(height: FreshSpacing.lg)` (16).
  3. Título: `Text(l10n.hydrationSheetTitle, style: titleLarge.copyWith(color: palette.ink, fontWeight: w800))`.
  4. Subtítulo: `Text(l10n.hydrationSheetSubtitle, bodyMedium.copyWith(color: palette.inkMuted))`.
  5. `SizedBox(height: compact ? md : lg)`.
  6. Bloque "Unidad" (`l10n.hydrationUnitTitle`) + `_UnitSegmentedControl` (litros vs onzas).
  7. `SizedBox(height: compact ? md : lg)`.
  8. Bloque "Objetivo diario" (`l10n.hydrationDailyGoal`) + `_HydrationStepper` (botón −, valor grande, botón +).
  9. `Row` con `l10n.hydrationRecommendedRange` + `Icons.info_outline_rounded` (icono decorativo, no tooltip).
  10. `SizedBox(height: compact ? md : lg)`.
  11. `_HydrationInfoCard` (card lima con `Icons.water_drop_rounded` y mensaje `l10n.hydrationInfoMessage`).
  12. `SizedBox(height: FreshSpacing.lg)`.
  13. Botón `FilledButton(key: ValueKey('save_goal_button'), onPressed: () => Navigator.of(context).pop(_liters), child: Text(l10n.commonSave))`.

### 5.3 Comparación con los patrones de drag-to-dismiss (per `02-investigation-drag-handle-patterns.md`)

| Criterio | `HydrationGoalSheet` | `CalorieTargetSheet` (referencia "buena") | `MealItemEditorSheet` (referencia "mala") |
|---|---|---|---|
| `showModalBottomSheet` config (línea 188 de `settings_screen.dart`) | `isScrollControlled: true`, `useSafeArea: true` | igual | igual |
| Drag handle como primer hijo | **Sí** (línea 52–61) | Sí (línea 80–89) | Sí (línea 67–76) |
| Handle dentro de `SingleChildScrollView` | **No** | No | **Sí** (lo mete dentro del scroll → bug) |
| Altura | `SizedBox(height: 0.86·screen)` (fija) | `SizedBox(height: 0.86·screen)` | `mainAxisSize: min` dentro de scroll |
| Body container | `Padding → SizedBox → Column` (no scroll) | igual | `Padding → SingleChildScrollView → Column` |
| Cancel button | **No** (test `settings_language_widget_test.dart:137` verifica `findsNothing` para `hydration_goal_cancel_button`) | sí | sí |

**Conclusión:** `HydrationGoalSheet` sigue el patrón "bueno" del `CalorieTargetSheet` — handle fuera del scroll, altura fija al 86 % de la pantalla, sin cancel button explícito (descartable por drag). El test E2E en `patrol_test/goals_settings_test.dart` y el widget test verifican explícitamente que el dismiss funciona con `await tester.drag(find.byType(BottomSheet), const Offset(0, 500))`.

### 5.4 Claves `ValueKey` expuestas (para tests)

- `hydration_goal_value` (línea 245 — valor numérico).
- `hydration_goal_decrease_button` (línea 213).
- `hydration_goal_increase_button` (línea 270).
- `hydration_unit_liters` / `hydration_unit_ounces` (líneas 110, 122).
- `save_goal_button` (línea 142).
- `hydration_goal_row` (en `settings_screen.dart:115`) — key del row que lo dispara.
- `hydration_goal_cancel_button` **no existe** (verificado en `settings_language_widget_test.dart:137` con `findsNothing`).

---

## 6. Localizaciones ARB (clave | EN | ES | línea)

Sólo claves que el `SettingsScreen` o los sheets que dispara consumen directamente. Las claves de los sheets ya abiertos (calorie target, macro distribution) también se incluyen porque su copia vive en `calorieTarget*` y `macro*` (no en `settings*`) — ver `l10n/app_en.arb:229-308` y `l10n/app_es.arb:118-167`.

### 6.1 Cabecera / errores / logout

| Clave | EN | ES | Línea EN | Línea ES |
|---|---|---|---|---|
| `settingsTitle` | "Menu" | "Menú" | `app_en.arb:116` | `app_es.arb:71` |
| `settingsSubtitle` | "Account and preferences" | "Cuenta y preferencias" | `app_en.arb:117` | `app_es.arb:72` |
| `settingsCouldNotUpdateGoals` | "Could not update goals" | "No se pudieron actualizar los objetivos" | `app_en.arb:118` | `app_es.arb:73` |
| `settingsLogOut` | "Log out" | "Cerrar sesión" | `app_en.arb:196` | `app_es.arb:95` |
| `settingsNotSet` | "Not set" | "Sin configurar" | `app_en.arb:208` | `app_es.arb:97` |
| `fallbackUserName` | "Cal Tracker" | "Cal Tracker" | `app_en.arb:4` | `app_es.arb:4` |

### 6.2 Hidratación (fila + sheet + info card)

| Clave | EN | ES | Línea EN | Línea ES |
|---|---|---|---|---|
| `settingsHydrationGoal` | "Hydration goal" | "Objetivo de hidratación" | `app_en.arb:119` | `app_es.arb:74` |
| `settingsHydrationGoalSubtitle` | "{liters} L per day" | "{liters} L al día" | `app_en.arb:120` | `app_es.arb:75` |
| `settingsLitersUnit` | "liters" | "litros" | `app_en.arb:183` | `app_es.arb:82` |
| `settingsOuncesUnit` | "ounces" | "onzas" | `app_en.arb:184` | `app_es.arb:83` |
| `hydrationSheetTitle` | "Set your daily water goal" | "Define tu objetivo diario de agua" | `app_en.arb:185` | `app_es.arb:84` |
| `hydrationSheetSubtitle` | "Choose how much water you want to drink each day." | "Elige cuánta agua quieres beber cada día." | `app_en.arb:186` | `app_es.arb:85` |
| `hydrationUnitTitle` | "Unit" | "Unidad" | `app_en.arb:187` | `app_es.arb:86` |
| `hydrationUnitLiters` | "Liters (L)" | "Litros (L)" | `app_en.arb:188` | `app_es.arb:87` |
| `hydrationUnitOunces` | "Onzas (fl oz)" | "Onzas (fl oz)" | `app_en.arb:189` | `app_es.arb:88` |
| `hydrationDailyGoal` | "Daily goal" | "Objetivo diario" | `app_en.arb:190` | `app_es.arb:89` |
| `hydrationRecommendedRange` | "Recommended: 2.0 - 3.0 L" | "Recomendado: 2.0 - 3.0 L" | `app_en.arb:191` | `app_es.arb:90` |
| `hydrationInfoTitle` | "Stay hydrated" | "Mantente hidratado" | `app_en.arb:192` | `app_es.arb:91` |
| `hydrationInfoMessage` | "Drinking enough water…" | "Beber suficiente agua…" | `app_en.arb:193` | `app_es.arb:92` |
| `hydrationDecreaseGoalTooltip` | "Decrease water goal" | "Reducir objetivo de agua" | `app_en.arb:194` | `app_es.arb:93` |
| `hydrationIncreaseGoalTooltip` | "Increase water goal" | "Aumentar objetivo de agua" | `app_en.arb:195` | `app_es.arb:94` |

### 6.3 Calorías (fila + sheet "bueno" compartido)

| Clave | EN | ES | Línea EN | Línea ES |
|---|---|---|---|---|
| `settingsCalorieTarget` | "Calorie target" | "Objetivo de calorías" | `app_en.arb:128` | `app_es.arb:76` |
| `settingsCalorieTargetSubtitle` | "{calories} Kcal daily target" | "{calories} Kcal de objetivo diario" | `app_en.arb:129` | `app_es.arb:77` |
| `calorieTargetSheetTitle` | "Set your daily calories" | "Configura tus calorías diarias" | `app_en.arb:229` | `app_es.arb:118` |
| `calorieTargetSheetSubtitle` | "Choose the target you want to track each day." | "Elige el objetivo que quieres controlar cada día." | `app_en.arb:230` | `app_es.arb:119` |
| `calorieTargetCalculatorLink` | "Don't know how many calories you need?" | "¿No sabes cuántas calorías necesitas?" | `app_en.arb:231` | `app_es.arb:120` |
| `calorieTargetRangeValidationError` | "Enter a target from {min} to {max} Kcal." | "Introduce un objetivo de {min} a {max} Kcal." | `app_en.arb:232` | `app_es.arb:121` |
| `calorieTargetIncreaseTooltip` | "Increase" | "Aumentar" | `app_en.arb:243` | `app_es.arb:122` |
| `calorieTargetDecreaseTooltip` | "Decrease" | "Disminuir" | `app_en.arb:244` | `app_es.arb:123` |
| `calorieSetupHeadlinePrefix` | "Set up your" | "Configura tus" | `app_en.arb:245` | `app_es.arb:124` |
| `calorieSetupHeadlineMain` | "daily calories" | "calorías diarias" | `app_en.arb:246` | `app_es.arb:125` |
| `calorieSetupHeadlineBadge` | "Here." | "Aquí." | `app_en.arb:247` | `app_es.arb:126` |
| `calorieCouldNotSaveCalories` | "Couldn't save your calories. Please try again." | "No se pudieron guardar tus calorías. Inténtalo de nuevo." | `app_en.arb:248` | `app_es.arb:127` |
| `calorieCouldNotSaveMacros` | "Couldn't save your macros. Please try again." | "No se pudieron guardar tus macros. Inténtalo de nuevo." | `app_en.arb:249` | `app_es.arb:128` |
| `calorieMacroPromptTitle` | "Add macros?" | "¿Añadir macros?" | `app_en.arb:262` | `app_es.arb:134` |
| `calorieMacroPromptMessage` | "Choose a simple protein, carb and fat split for {calories} Kcal." | "Elige un reparto simple de proteína, carbohidratos y grasa para {calories} Kcal." | `app_en.arb:263` | `app_es.arb:135` |
| `calorieMacroPromptConfigure` | "Configure" | "Configurar" | `app_en.arb:271` | `app_es.arb:136` |
| `calorieMacroPromptSkip` | "Skip for now" | "Omitir por ahora" | `app_en.arb:272` | `app_es.arb:137` |
| `settingsGoalRangeError` | "Enter {min}-{max}." | "Introduce {min}-{max}." | `app_en.arb:197` | `app_es.arb:96` |

### 6.4 Macros (fila + sheet "bueno" compartido + presets)

| Clave | EN | ES | Línea EN | Línea ES |
|---|---|---|---|---|
| `settingsMacroDistributionTitle` | "Macro distribution" | "Distribución de macros" | `app_en.arb:137` | `app_es.arb:78` |
| `settingsMacroPresetSubtitle` | "{preset}: {protein}% protein, {carbs}% carbs, {fat}% fat" | "{preset}: {protein} % proteína, {carbs} % carbohidratos, {fat} % grasa" | `app_en.arb:138` | `app_es.arb:79` |
| `settingsMacroPercentSubtitle` | "{protein}% protein, {carbs}% carbs, {fat}% fat" | "{protein} % proteína, {carbs} % carbohidratos, {fat} % grasa" | `app_en.arb:155` | `app_es.arb:80` |
| `settingsMacroGramsSubtitle` | "{protein}g protein, {carbs}g carbs, {fat}g fat" | "{protein} g proteína, {carbs} g carbohidratos, {fat} g grasa" | `app_en.arb:169` | `app_es.arb:81` |
| `settingsMacroRequiresCaloriesTitle` | "Set calories first" | "Configura primero tus calorías" | `app_en.arb:225` | `app_es.arb:114` |
| `settingsMacroRequiresCaloriesMessage` | "Configure your daily calories before setting a macro distribution." | "Configura tus calorías diarias antes de definir una distribución de macros." | `app_en.arb:226` | `app_es.arb:115` |
| `settingsMacroRequiresCaloriesSetNow` | "Set your calories now" | "Configurar calorías ahora" | `app_en.arb:227` | `app_es.arb:116` |
| `settingsMacroRequiresCaloriesSkip` | "Skip for now" | "Omitir por ahora" | `app_en.arb:228` | `app_es.arb:117` |
| `macroPresetBalanced` | "Balanced" | "Equilibrado" | `app_en.arb:362` | `app_es.arb:210` |
| `macroPresetHighProtein` | "High protein" | "Alta proteína" | `app_en.arb:363` | `app_es.arb:211` |
| `macroPresetLowerCarb` | "Lower carb" | "Bajo en carbohidratos" | `app_en.arb:364` | `app_es.arb:212` |

### 6.5 Idioma y tema (filas + sheets inline)

| Clave | EN | ES | Línea EN | Línea ES |
|---|---|---|---|---|
| `settingsLanguageTitle` | "Language" | "Idioma" | `app_en.arb:209` | `app_es.arb:98` |
| `settingsLanguageNativeName` | "English" | "Español" | `app_en.arb:210` | `app_es.arb:99` |
| `settingsLanguageSheetTitle` | "Choose language" | "Elige idioma" | `app_en.arb:211` | `app_es.arb:100` |
| `settingsThemeTitle` | "Appearance" | "Apariencia" | `app_en.arb:212` | `app_es.arb:101` |
| `settingsThemeSheetTitle` | "Choose appearance" | "Elige apariencia" | `app_en.arb:213` | `app_es.arb:102` |
| `settingsThemeSystem` | "Device default" | "Por defecto del dispositivo" | `app_en.arb:214` | `app_es.arb:103` |
| `settingsThemeLight` | "Light" | "Claro" | `app_en.arb:215` | `app_es.arb:104` |
| `settingsThemeDark` | "Dark" | "Oscuro" | `app_en.arb:216` | `app_es.arb:105` |

### 6.6 Data sources (card informativa)

| Clave | EN | ES | Línea EN | Línea ES |
|---|---|---|---|---|
| `settingsDataSourcesTitle` | "Data sources" | "Fuentes de datos" | `app_en.arb:217` | `app_es.arb:106` |
| `settingsDataSourcesSubtitle` | "Food matches can include public reference data." | "Las coincidencias de alimentos pueden incluir datos públicos de referencia." | `app_en.arb:218` | `app_es.arb:107` |
| `settingsDataSourcesOpenFoodFacts` | "Contains information from Open Food Facts…" | "Contiene información de Open Food Facts…" | `app_en.arb:219` | `app_es.arb:108` |
| `settingsDataSourcesUsda` | "USDA FoodData Central data is public domain under CC0 1.0." | "Los datos de USDA FoodData Central son de dominio público bajo CC0 1.0." | `app_en.arb:220` | `app_es.arb:109` |

### 6.7 Claves comunes reutilizadas (no son `settings*`)

| Clave | EN | ES | Línea EN | Línea ES |
|---|---|---|---|---|
| `commonSave` | "Save" | "Guardar" | `app_en.arb:8` | `app_es.arb:8` |
| `commonCancel` | "Cancel" | "Cancelar" | `app_en.arb:6` | `app_es.arb:6` |
| `commonKcal` | "Kcal" | "Kcal" | `app_en.arb:27` | `app_es.arb:27` |

> **No existe** clave `commonLogout`, `commonSignOut`, `signOut`, ni `logout` en los ARB. La única cadena de cierre de sesión es `settingsLogOut`.

---

## 7. Tests existentes para Settings

### 7.1 `apps/mobile/test/settings_language_widget_test.dart` (636 líneas)

Es el único test dedicado a `SettingsScreen`. Cubre:

- **Idioma**: pulsa `language_settings_row`, abre sheet con N `language_option_*` (uno por `AppLocalizations.supportedLocales`), cambiar a `es` refleja "Idioma", "Distribución de macros" y "Fuentes de datos" en pantalla, y persiste en `AppPreferencesRepository.savedLocaleCode`.
- **Tema**: pulsa `theme_settings_row`, verifica sheet con `theme_option_system|light|dark`, persiste `ThemeMode` en preferencias.
- **Hidratación**: pulsa `hydration_goal_row`, verifica título/subtítulo, comprueba `findsNothing` para `hydration_goal_cancel_button`, valida la conmutación litros↔onzas (`hydration_unit_ounces` → muestra "84.5"), incrementa y guarda con `save_goal_button`. Repite con `es` y verifica la copia localizada. Test de dismiss: `tester.drag(find.byType(BottomSheet), const Offset(0, 500))` confirma que el drag cierra el sheet.
- **Calorie target**: pulsa `calorie_target_row`, abre `CalorieTargetSheet` compartido, escribe "1900" en `dashboard_calorie_target_field`, guarda con `dashboard_save_calorie_target_button`. Verifica `nutritionRepository.updatedCalories == 1900`, snackbar "Calories saved", `macro_prompt_not_now` visible, y al volver a Settings el subtítulo es "1900 Kcal daily target".
- **Previews antes de setup**: `Not set` aparece 2 veces (calorías y macros) si no hay resumen configurado.
- **Gate de macros**: pulsa `macro_distribution_row` sin calorías, abre `_MacroRequiresCaloriesSheet` ("Set calories first"); `macro_requires_calories_set_now` lleva a `CalorieTargetSheet`; `macro_requires_calories_skip` no llama a `updateDailyGoals` y vuelve al menú.
- **Macros con calorías**: `macro_distribution_row` con calorías configuradas abre `MacroDistributionSheet` (verifica `macro_distribution_save_button`).
- **Setup del pump**: `_pumpSettings` (línea 312) monta `MultiProvider` con `AuthViewModel`, `LocaleViewModel`, `ThemeModeViewModel`, `DashboardViewModel`, `MealHistoryViewModel` y `SettingsViewModel` (todos fakeados). Home: `Scaffold(body: SettingsScreen())`.

**Cobertura real:**

- ✅ `ValueKey`s estables: `language_settings_row`, `theme_settings_row`, `hydration_goal_row`, `calorie_target_row`, `macro_distribution_row`, `theme_option_system|light|dark`, `language_option_<tag>`, `save_goal_button`, `hydration_goal_value`, `hydration_unit_liters`, `hydration_unit_ounces`, `hydration_goal_increase_button`, `hydration_goal_decrease_button`, `dashboard_calorie_target_field`, `dashboard_save_calorie_target_button`, `macro_prompt_not_now`, `macro_distribution_save_button`, `macro_requires_calories_set_now`, `macro_requires_calories_skip`.
- ✅ Cambio de idioma en vivo y persistencia.
- ✅ Cambio de tema en vivo y persistencia.
- ✅ Hidratación litros/onzas + dismiss con drag.
- ✅ Calorie target + prompt de macros + rollback.
- ✅ Gate "Set calories first" + skip.
- ❌ **No** hay test para el row de **Data sources** (es estático).
- ❌ **No** hay test para el **botón Logout** (sólo cobertura indirecta en `app.dart:311`).
- ❌ **No** hay test para el path de error (`settings.error` banner).
- ❌ **No** hay test para el **header de usuario** (avatar + email).
- ❌ **No** hay test para la **cabecera** (`settingsTitle`, `settingsSubtitle`).

### 7.2 `apps/mobile/patrol_test/goals_settings_test.dart` (12.4 KB, 3 patrolTests)

- "sets first calorie target from the Home setup prompt" — flujo desde dashboard, no desde Settings.
- "uses calorie calculator estimate before saving Home target" — wizard completo desde dashboard.
- "edits goals from Menu and updates Home immediately" — **sí toca Settings**: pulsa `nav_menu_button`, espera `calorie_target_row`, edita calorías, comprueba "2300 Kcal daily target", luego abre `hydration_goal_row` y sube 10 veces el stepper.

### 7.3 `apps/mobile/patrol_test/language_settings_test.dart` (3.7 KB, 1 patrolTest)

- "switches language from Menu and persists after app restart" — pulsa `nav_menu_button`, abre `language_settings_row`, cambia a `es` y luego a `en`. Reinicia la app y verifica que el idioma persiste.

### 7.4 Otros tests relevantes (no específicos de Settings)

- `apps/mobile/test/locale_view_model_test.dart` — VM de idioma.
- `apps/mobile/test/theme_mode_view_model_test.dart` — VM de tema.
- `apps/mobile/test/calorie_target_validation_test.dart` — validador del sheet de calorías.
- `apps/mobile/test/macro_distribution_test.dart` — modelo de distribución.
- `apps/mobile/test/dashboard_cleanup_widget_test.dart` — Dashboard, no Settings.

**No** existen `*settings_screen*_test.dart` ni `*settings_view_model*_test.dart` con coverage específico del VM. La lógica de `SettingsViewModel` se valida indirectamente a través de los widget tests y patrol tests.

---

## 8. Otros lugares donde se renderiza el contenido de Settings

`SettingsScreen` se monta únicamente en una ruta: `apps/mobile/lib/app/router.dart:188` (rama `StatefulShellBranch` con `path: '/settings'`). **No hay duplicación** en el shell, en el perfil, en el dashboard, ni en el voice log. Las opciones (calorie target, macro distribution, language, theme) sólo aparecen en esta pantalla.

Lo que sí se reusa en otros sitios:

| Vista | Reutiliza |
|---|---|
| `dashboard_screen.dart:154, 186, 194` | `CalorieTargetSheet`, `PostCalorieSaveMacroPrompt`, `MacroDistributionSheet` (los abre desde el `_DailyProgressCard` / `_CalorieSetupProgressCard`). |
| `app_shell.dart:698` | `l10n.navMenu` ("Menu" / "Menú") para el tab de navegación. |
| `app_shell.dart:680+` (nav 0 = home, 1 = stats, 2 = usual, 3 = menu) | `ValueKey('main_nav_menu')` para el botón del bottom/side nav que abre Settings. |
| `app.dart:180, 311, 330` | Instancia el `SettingsViewModel`, llama `reset()` en logout, llama `load()` durante el preload. |
| `main_local.dart:241, 268` | El entrypoint `lib/main_local.dart` también carga `SettingsViewModel` (toolkit local). |

No hay un "profile screen" ni un "settings page" alternativo; la pestaña `menu` del shell **es** el único sitio.

---

## 9. Observaciones sobre el layout actual

### 9.1 Anchura, padding y scroll

- `FreshPage.maxWidth = 760` (default en `design_system.dart:265`). En pantallas anchas (`>= 720 px`, el shell pasa a `_FreshSideNav` lateral — `app_shell.dart:60`), el contenido de Settings se centra con `Center(ConstrainedBox(maxWidth: 760))` y queda con el mismo padding lateral de 20 px. En tablet / landscape hay mucho espacio vacío a izquierda y derecha.
- Padding horizontal: `EdgeInsets.fromLTRB(20, 18, 20, 8)` para la cabecera de la página, `EdgeInsets.fromLTRB(20, 10, 20, 24)` para el body — `design_system.dart:280-289`.
- Scroll: `CustomScrollView` + `SliverToBoxAdapter(child: Column(...))` (`design_system.dart:268-292`). El `Column` no es lazy; renderiza los 7 hijos completos (cabecera + loading + error + 5 goal rows + data sources card + spacer + logout button) en una sola pasada.
- **No** hay `RefreshIndicator`, no hay `Scrollbar`, no hay `BouncingScrollPhysics` explícito.

### 9.2 Filas y cards

- Todas las `_SettingsGoalRow` son `FreshCard(padding: EdgeInsets.all(16), onTap: ..., child: Row([icon chip, gap 12, Expanded(Column[title, subtitle]), chevron]))`. Altura intrínseca según el texto del subtítulo. Radio = `FreshRadii.lg` (24) por defecto.
- El avatar de la cabecera es 58×58 dentro de un `FreshCard` con `radius: FreshRadii.xl` (32) y `palette.limeSoft` de fondo.
- La card de **Data sources** no es tappable y usa `shadow: false` (línea 504–520) — visualmente más plana que las goal rows.
- El botón **Logout** es `OutlinedButton.icon` Material (no `FreshCard`); hereda la altura mínima Material por defecto y los estilos del theme.

### 9.3 Iconos y colores por fila (paleta)

| Fila | `Icons.*` | Color (palette) |
|---|---|---|
| Hydration goal | `water_drop_rounded` | `water` |
| Calorie target | `flag_rounded` | `orange` |
| Macro distribution | `pie_chart_rounded` | `leaf` |
| Language | `translate_rounded` | `mint` |
| Theme / Appearance | `contrast_rounded` | `limeDeep` |
| Data sources | `source_rounded` | `orange` |
| Logout | `logout_rounded` | _(heredado del theme)_ |

### 9.4 Estado condicional

- `LinearProgressIndicator` sólo aparece si `settings.isLoading` (sin datos cacheados) — `settings_screen.dart:101–104`.
- `FreshStatusBanner` sólo si `settings.error != null` — `settings_screen.dart:105–113`.
- Las `_SettingsGoalRow` se deshabilitan (chevron sigue visible, `onTap: null`) si `settings.isLoading || settings.isSaving` — afecta a las filas de calorías, macros e hidratación. Language y theme **no** se deshabilitan.

### 9.5 Tokens de diseño relevantes (para futuros grids 2-col)

- `FreshSpacing`: `xs=4, sm=8, md=12, lg=16, xl=24, xxl=32` (`design_system.dart:165-172`).
- `FreshRadii`: `sm=10, md=18, lg=24, xl=32` (`design_system.dart:174-180`).
- `FreshCard` ya soporta `padding`, `color`, `radius`, `onTap`, `shadow` — sirve como bloque para celdas de un grid.
- `FreshIconChip` (línea 411–443): cuadrado 42×42 con tinte 14 % sobre el color. Se reusaría dentro de cada celda.
- `FreshSectionTitle` (línea 695–712): `Row([Expanded(Text), trailing?])` con `textTheme.titleLarge` — **ya existe** y serviría para cabeceras de sección.
- **No hay widget `FreshGrid` ni `FreshTwoColumn`**: el patrón de 2 columnas en la app hoy es manual (`Row(Expanded, gap, Expanded)` en `dashboard_screen.dart:523-583` para macros y en `dashboard_screen.dart:301-376` para el header de progreso).
- **Cero uso** de `GridView`, `SliverGrid`, `Wrap` con `runSpacing` para distribuir items iguales — el `Wrap` que existe en `macro_distribution_sheet.dart:420, 532` sólo se usa para distribuir botones con tamaño variable (no para grid de tarjetas).

### 9.6 `ValueKey`s expuestas en el `build` (referencia rápida para tests)

```
'hydration_goal_row'
'calorie_target_row'
'macro_distribution_row'
'language_settings_row'
'theme_settings_row'
// data sources: no key
// logout: no key
```

### 9.7 Drag handle / sheet patrón

`SettingsScreen` invoca 5 `showModalBottomSheet` distintos (ver §2.3). Todos usan `isScrollControlled: true` excepto los dos "prompts" (post-save macro prompt y "set calories first"). El `HydrationGoalSheet` es el único en fichero aparte; los de theme y language son inline `showModalBottomSheet` definidos en `settings_screen.dart:337-410` y `412-458`.

---

## 10. Resumen para el reagrupamiento (sin proponer fix)

- **"Opciones de calorías"** (filas a reagrupar en grid 2-col): `calorie_target_row` + `macro_distribution_row`. Hidratación **no** es calorías.
- **"Configuración de la app"** (nueva sección agrupando): `language_settings_row` + `theme_settings_row`.
- **"Datos de usuario"**: el `FreshCard` actual con `palette.limeSoft` (líneas 54–99) sigue donde está, full-width.
- **"Logout"**: el `OutlinedButton.icon` actual (líneas 178–181) sigue donde está, full-width.
- **Lo único intermedio que "se mueve"** es la fila de hidratación — el usuario no la menciona, así que **fuera del scope** según su petición. Mantener donde está (entre la cabecera y la fila de calorie target).
- **Card de "Data sources"**: informativa, sin acción. El usuario no la menciona, así que se quedaría donde está (entre theme y logout) salvo que se decida reagruparla con "App" o dejarla aparte.
- **Tokens de grid**: hoy no existen — habría que decidir entre `Row(Expanded, Expanded)` con gap (como el patrón del dashboard) o introducir un widget nuevo en `design_system.dart` (e.g. `FreshTwoColumn`).
- **Cabeceras de sección**: `FreshSectionTitle` ya existe en `design_system.dart:695-712` pero no se usa. Si se quiere añadir cabeceras de "Calorías", "App", etc., se reusaría.
- **Tests a actualizar** (sin entrar en cambios concretos): `settings_language_widget_test.dart` ejercita las `ValueKey`s; cualquier reagrupamiento debe conservarlas (o migrarlas explícitamente). El test de hidratación por drag (`tester.drag(find.byType(BottomSheet), Offset(0, 500))`) y los Patrol tests (`goals_settings_test.dart`, `language_settings_test.dart`) son el contrato de regresión.
