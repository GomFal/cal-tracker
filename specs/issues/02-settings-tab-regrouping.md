# Issue 02 — Settings: reagrupar opciones en grids

**Estado:** Recopilado. Listo para decidir approach de implementación.
**Rama actual:** `develop`
**Origen del report:** Usuario — reagrupación de opciones en la pestaña de Settings / Menú.

## Necesidad del usuario

Reorganizar visualmente la pestaña de Settings con esta estructura:

1. **Opciones de calorías** → **grid de 2 columnas** (en lugar de la columna única actual).
2. **Configuración de la app** → agrupar **lenguaje** y **apariencia/tema** en una nueva sección.
3. **Logout** → se queda donde está actualmente.
4. **Datos de usuario** → se queda donde está, **ocupando la columna entera**.

## Estructura actual de `SettingsScreen`

### Andamiaje

- `lib/ui/features/settings/views/settings_screen.dart` (511 líneas aprox).
- Root: `ContentFrame(title: l10n.settingsTitle, subtitle: l10n.settingsSubtitle, child: Column(...))`.
- `ContentFrame` (línea 1-24) delega en `FreshPage` con `maxWidth: 760` (en `design_system.dart:265`).
- `FreshPage` (líneas 262-293 de `design_system.dart`) usa `SafeArea` + `Center` + `ConstrainedBox(maxWidth: 760)` + `CustomScrollView` con `SliverToBoxAdapter` para el `Column`.
- Padding lateral: 20 dp. Ancho útil en móvil compacto: 320 dp; capeado a 720 dp en pantallas anchas.

### Orden actual de hijos del `Column` (de arriba a abajo)

| # | Bloque | Líneas | Tipo / widget | Ancho |
|---|---|---|---|---|
| 1 | **Cabecera de usuario** (avatar + nombre + email) | 54-99 | `FreshCard` `radius: FreshRadii.xl`, `color: palette.limeSoft` | full-width |
| 2 | `SizedBox(height: FreshSpacing.lg)` | 100 | separador | – |
| 3 | Loading banner | 101-104 | `LinearProgressIndicator(minHeight: 3)` | full-width |
| 4 | Error banner | 105-113 | `FreshStatusBanner` con `palette.coral` | full-width |
| 5 | **Opción: Hydration goal** | 114-123 | `_SettingsGoalRow` (icon + título + subtítulo + chevron) | full-width |
| 6 | `SizedBox(height: FreshSpacing.md)` | 124 | separador | – |
| 7 | **Opción: Calorie target** | 125-138 | `_SettingsGoalRow` | full-width |
| 8 | `SizedBox(height: FreshSpacing.md)` | 139 | separador | – |
| 9 | **Opción: Macro distribution** | 140-149 | `_SettingsGoalRow` | full-width |
| 10 | `SizedBox(height: FreshSpacing.md)` | 150 | separador | – |
| 11 | **Opción: Language** | 151-159 | `_SettingsGoalRow` | full-width |
| 12 | `SizedBox(height: FreshSpacing.md)` | 160 | separador | – |
| 13 | **Opción: Theme / Appearance** | 161-169 | `_SettingsGoalRow` | full-width |
| 14 | `SizedBox(height: FreshSpacing.md)` | 170 | separador | – |
| 15 | **Card: Data sources** | 171-176 | `_DataSourcesCard` (`FreshCard shadow: false`, padding 16) | full-width (informativa, no tappable) |
| 16 | `SizedBox(height: FreshSpacing.xl)` | 177 | separador | – |
| 17 | **Botón Logout** | 178-181 | `OutlinedButton.icon` con `Icons.logout_rounded` y `Text(l10n.settingsLogOut)` | full-width |

### `_SettingsGoalRow` (línea 609-651) — el "tile" usado 5 veces

Estructura: `FreshCard(padding: 16, onTap) → Row([FreshIconChip(size: 42), SizedBox(12), Expanded(Column[title, subtitle inkMuted]), Icon(chevron)])`. `radius: FreshRadii.lg` por defecto, `shadow: true` por defecto. No es un widget del design system; es privado al fichero.

### `ValueKey` expuestas (referencia para tests)

- `hydration_goal_row`
- `calorie_target_row`
- `macro_distribution_row`
- `language_settings_row`
- `theme_settings_row`
- (data sources y logout: sin key)

## Clasificación por la nueva agrupación del usuario

### 1. "Opciones de calorías" → grid 2 columnas

- `calorie_target_row` — `Icons.flag_rounded`, `palette.orange` → abre `CalorieTargetSheet` (compartido con Dashboard).
- `macro_distribution_row` — `Icons.pie_chart_rounded`, `palette.leaf` → abre `MacroDistributionSheet` (con gate `_MacroRequiresCaloriesSheet` si no hay calorías).
- **Hidratación NO entra en calorías** (es objetivo hídrico, `Icons.water_drop_rounded`, `palette.water`). Quedaría fuera del grid 2-col según la nueva agrupación.
  - *Nota:* el usuario no mencionó hidratación explícitamente. El agente debe confirmar si se mantiene como fila propia fuera del grid o si se incorpora a "calorías". **Pendiente de decisión.**

### 2. "Configuración de la app" → nueva sección

- `language_settings_row` — `Icons.translate_rounded`, `palette.mint` → abre sheet inline de `_showLanguageSheet` (no en fichero aparte).
- `theme_settings_row` — `Icons.contrast_rounded`, `palette.limeDeep` → abre sheet inline de `_showThemeSheet`.

### 3. "Datos de usuario" → se queda como está (full-width)

- `FreshCard` con `radius: FreshRadii.xl`, `color: palette.limeSoft`, contenido `Row` con avatar circular 58×58 (icono `Icons.person_rounded`, 30 px, `palette.limeDeep`) y `Expanded(Column[displayName, email])`. Líneas 54-99.

### 4. "Logout" → se queda como está (full-width)

- `OutlinedButton.icon(onPressed: auth.logout, icon: Icon(Icons.logout_rounded), label: Text(l10n.settingsLogOut))`. Líneas 178-181.

### 5. (Decisión pendiente) Card de "Data sources" y fila de "Hydration"

- Data sources: card informativa (`FreshCard shadow: false`, con `Icons.source_rounded`, `palette.orange`), sin acción. No la menciona el usuario → probablemente se queda donde está (entre Theme y Logout).
- Hydration goal: fila normal con `_SettingsGoalRow`. No la menciona el usuario → probablemente se queda donde está (entre User card y Calorie target).

## Ficheros directamente sospechosos (los que se tocarán)

| Fichero | Por qué |
|---|---|
| `apps/mobile/lib/ui/features/settings/views/settings_screen.dart` | Único fichero del `build` y de los sheets inline (idioma, tema, gate de macros). Toda la reorganización vive aquí. |
| `apps/mobile/lib/ui/core/design_system.dart` | Tiene los tokens (`FreshSpacing`, `FreshRadii`, `FreshCard`, `FreshIconChip`, `FreshSectionTitle`). `FreshSectionTitle` ya existe (línea 695) pero **no se usa** en `settings_screen.dart`. `FreshCard` y `FreshIconChip` son los bloques que se reusarán. |
| `apps/mobile/lib/ui/core/content_frame.dart` | Wrapper muy fino de `FreshPage`. No cambia. |
| `apps/mobile/lib/l10n/app_en.arb` y `app_es.arb` | Solo si se añaden cadenas de cabecera de sección (p. ej. `settingsSectionCalories`, `settingsSectionApp`). Las actuales ya cubren lo que existe. |
| `apps/mobile/lib/l10n/generated/app_localizations*.dart` | Regenerado al añadir ARB. |
| `apps/mobile/test/settings_language_widget_test.dart` | Tests que buscan las `ValueKey` actuales. Cualquier reagrupamiento debe conservarlas o migrarlas explícitamente. |

### Ficheros donde las opciones viven en otros sitios (referencia, no se tocan)

- `apps/mobile/lib/ui/features/dashboard/views/dashboard_screen.dart` — reutiliza `CalorieTargetSheet`, `MacroDistributionSheet`. No re-renderiza las opciones de Settings, solo dispara los sheets.
- `apps/mobile/lib/ui/features/dashboard/views/calorie_target_sheet.dart` — sheet "bueno" (handle fuera del scroll), compartido con Dashboard.
- `apps/mobile/lib/ui/features/dashboard/views/macro_distribution_sheet.dart` — sheet "bueno", compartido con Dashboard.
- `apps/mobile/lib/app/locale_view_model.dart` y `theme_mode_view_model.dart` — estado de idioma y tema.

## Patrones de grid disponibles en el proyecto

**No hay widgets de grid nativos (`GridView`, `SliverGrid`, `StaggeredGrid`) en ninguna parte del proyecto.** No hay paquetes de grid en `pubspec.yaml`. Cualquier grid hay que construirlo a mano.

### Patrones reutilizables para grid 2 columnas

| Patrón | Fichero | Descripción | Cuándo encaja |
|---|---|---|---|
| `_MacroGrid` (Wrap + SizedBox(width), 2 ó 4 cols) | `lib/ui/features/meal_templates/views/usual_food_editor_screen.dart:630-649` | `LayoutBuilder` + cálculo de `itemWidth = (maxWidth - gap*(cols-1)) / cols` + `Wrap`. Breakpoint `>=560` ⇒ 4 cols. | **El más cercano a un "grid 2×N" verdadero.** Soporta N columnas, envuelve automáticamente, celdas iguales. |
| `_TwoColumnFields` (1 col si estrecho, 2 si ancho) | `lib/ui/features/meal_templates/views/usual_food_editor_screen.dart:603-622` | `LayoutBuilder` + `Row(crossAxisAlignment: start, children: [Expanded × N])`. Breakpoint `<560` colapsa. | Una sola fila de N celdas; no es grid 2×N. |
| `Row` + 2× `Expanded` (estilo `_MacroSummaryRow`) | `lib/ui/features/dashboard/views/dashboard_screen.dart:523-585` | 3 columnas con `Row` + `Expanded` + `SizedBox` (8 dp). | Una sola fila fija, sin envoltura. |
| `Wrap` con `width` fija (mutators del local toolkit) | `lib/local_toolkit/ui/local_toolkit_overlay.dart:400-490` | `LayoutBuilder` + `width = (constraints.maxWidth - 8) / 2` a `>=430`. | Variante de `_MacroGrid` con botones outlined. |

### `_SettingsGoalRow` y `_SettingsOption` (privados de `settings_screen.dart`)

- `_SettingsGoalRow` (línea 609-651): `FreshCard(padding: 16, onTap) + Row([FreshIconChip(42), gap 12, Expanded(Column[title, subtitle inkMuted]), chevron])`. Radio `FreshRadii.lg` (24) por defecto, `shadow: true` por defecto. No hay `FreshSettingTile` en el design system.
- `_SettingsOption` (línea 523-547): `FreshCard(padding: 16, onTap, shadow: false) + Row(Expanded(Text) + check)`. Usado en los sheets de language y theme.
- `_DataSourcesCard` (línea 466-510): `FreshCard(padding: 16, shadow: false) + FreshIconChip(Icons.source_rounded) + Column(Text título, Text subtítulo, Text OFF, Text USDA)`.

### Primitivas del design system relevantes

- `FreshCard` (`design_system.dart:353`): `child` (req), `padding = EdgeInsets.all(20)`, `color`, `radius = FreshRadii.lg`, `onTap`, `shadow = true`. Tiene `InkWell` automático si `onTap != null`. **Suficiente para celdas de grid.**
- `FreshIconChip` (`design_system.dart:439`): `icon`, `color` (req), `size = 42`. Cuadrado `size×size` con `color.withValues(alpha: 0.14)` de fondo. Reusable dentro de cada celda.
- `FreshSectionTitle` (`design_system.dart:695-712`): `Row([Expanded(Text), trailing?])` con `textTheme.titleLarge`. **Ya existe y serviría para cabeceras de sección.** No se usa en Settings actualmente.
- `FreshMetricCard` (`design_system.dart:472`): `title`, `value`, `unit`, `icon`, `color` (todos req), `sparkline` (opt). Card con icono + título + valor + unidad. Radio `FreshRadii.lg`, padding `16`. **Pensada para dashboards / métricas.** Posible candidato a celda de grid.
- `FreshSpacing` (`design_system.dart:165-172`): `xs=4, sm=8, md=12, lg=16, xl=24, xxl=32`.
- `FreshRadii` (`design_system.dart:174-180`): `sm=10, md=18, lg=24, xl=32`.

### Sombras disponibles

- `_lightSoftShadow` y `_darkSoftShadow` (`design_system.dart:240-260`). Se aplican dentro de `FreshCard.build` solo si `shadow: true`. **Para celdas de grid, probablemente `shadow: false`** para evitar ruido visual (igual que `_SettingsOption` y `_DataSourcesCard` actuales).

## Responsividad y consideraciones de layout

### Ancho disponible

- Móvil compacto (360 dp): área = 320 dp → 2 columnas con `FreshSpacing.md` (12) = ~154 dp por celda.
- Móvil estándar (411 dp): área = 371 dp → ~179 dp por celda.
- Tablet portrait (600 dp): área = 560 dp → justo en el breakpoint del `_MacroGrid`.
- Pantallas anchas: capeado a 720 dp.

### Implicación para el grid

- 154 dp por celda en móvil compacto es **estrecho** para `_SettingsGoalRow` actual (icon 42 + gap 12 + Expanded texto + chevron). El texto quedaría con menos de 100 dp de ancho. **Hay que decidir si:**
  - (a) Se simplifica la celda (sin subtítulo, o subtítulo muy corto).
  - (b) Se apila verticalmente (icon arriba, texto abajo) tipo `_MacroSummaryPill` o `_NutritionChip`.
  - (c) Se mantiene el grid solo en pantallas anchas y se vuelve a columna en móvil compacto (`LayoutBuilder` con breakpoint).

### Breakpoints existentes (referencia)

| Componente | Fichero:línea | Breakpoint |
|---|---|---|
| `AppShell` (BottomNav ↔ SideNav) | `app_shell.dart:48` | `>=720` |
| `Local toolkit quick mutators` | `local_toolkit_overlay.dart:405` | `>=430` |
| `_MacroGrid` | `usual_food_editor_screen.dart:639` | `>=560` |
| `_TwoColumnFields` | `usual_food_editor_screen.dart:610` | `<560` colapsa |
| `BottomSaveBar` | `meal_template_editor_screen.dart:703` | `<420` colapsa |
| `MealItemEditorSheet` | `meal_item_editor_sheet.dart:264,366` | `<260` colapsa |

## Localizaciones ARB relacionadas

### Cabecera / errores / logout

| Clave | EN | ES | Línea EN | Línea ES |
|---|---|---|---|---|
| `settingsTitle` | "Menu" | "Menú" | `app_en.arb:116` | `app_es.arb:71` |
| `settingsSubtitle` | "Account and preferences" | "Cuenta y preferencias" | `app_en.arb:117` | `app_es.arb:72` |
| `settingsCouldNotUpdateGoals` | "Could not update goals" | "No se pudieron actualizar los objetivos" | `app_en.arb:118` | `app_es.arb:73` |
| `settingsLogOut` | "Log out" | "Cerrar sesión" | `app_en.arb:196` | `app_es.arb:95` |
| `settingsNotSet` | "Not set" | "Sin configurar" | `app_en.arb:208` | `app_es.arb:97` |
| `fallbackUserName` | "Cal Tracker" | "Cal Tracker" | `app_en.arb:4` | `app_es.arb:4` |

### Hidratación (fila + sheet + info card)

| Clave | EN | ES | Línea EN | Línea ES |
|---|---|---|---|---|
| `settingsHydrationGoal` | "Hydration goal" | "Objetivo de hidratación" | `app_en.arb:119` | `app_es.arb:74` |
| `settingsHydrationGoalSubtitle` | "{liters} L per day" | "{liters} L al día" | `app_en.arb:120` | `app_es.arb:75` |
| `hydrationSheetTitle` | "Set your daily water goal" | "Define tu objetivo diario de agua" | `app_en.arb:185` | `app_es.arb:84` |
| (resto de hidratación) | ... | ... | `app_en.arb:183-195` | `app_es.arb:82-94` |

### Calorías (fila + sheet "bueno" compartido)

| Clave | EN | ES | Línea EN | Línea ES |
|---|---|---|---|---|
| `settingsCalorieTarget` | "Calorie target" | "Objetivo de calorías" | `app_en.arb:128` | `app_es.arb:76` |
| `settingsCalorieTargetSubtitle` | "{calories} Kcal daily target" | "{calories} Kcal de objetivo diario" | `app_en.arb:129` | `app_es.arb:77` |
| `calorieTargetSheetTitle` | "Set your daily calories" | "Configura tus calorías diarias" | `app_en.arb:229` | `app_es.arb:118` |
| (resto de calorie target) | ... | ... | `app_en.arb:229-249, 262-272` | `app_es.arb:118-128, 134-137` |

### Macros (fila + sheet "bueno" compartido + presets)

| Clave | EN | ES | Línea EN | Línea ES |
|---|---|---|---|---|
| `settingsMacroDistributionTitle` | "Macro distribution" | "Distribución de macros" | `app_en.arb:137` | `app_es.arb:78` |
| `settingsMacroPresetSubtitle` | "{preset}: ..." | "{preset}: ..." | `app_en.arb:138` | `app_es.arb:79` |
| `settingsMacroPercentSubtitle` | "{protein}% protein, ..." | "{protein} % proteína, ..." | `app_en.arb:155` | `app_es.arb:80` |
| `settingsMacroGramsSubtitle` | "{protein}g protein, ..." | "{protein} g proteína, ..." | `app_en.arb:169` | `app_es.arb:81` |
| `settingsMacroRequiresCaloriesTitle` | "Set calories first" | "Configura primero tus calorías" | `app_en.arb:225` | `app_es.arb:114` |
| (presets: `macroPresetBalanced`, `macroPresetHighProtein`, `macroPresetLowerCarb`) | ... | ... | `app_en.arb:362-364` | `app_es.arb:210-212` |

### Idioma y tema (filas + sheets inline)

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

### Data sources (card informativa)

| Clave | EN | ES | Línea EN | Línea ES |
|---|---|---|---|---|
| `settingsDataSourcesTitle` | "Data sources" | "Fuentes de datos" | `app_en.arb:217` | `app_es.arb:106` |
| `settingsDataSourcesSubtitle` | "Food matches can include public reference data." | "Las coincidencias de alimentos pueden incluir datos públicos de referencia." | `app_en.arb:218` | `app_es.arb:107` |
| `settingsDataSourcesOpenFoodFacts` | "Contains information from Open Food Facts…" | "Contiene información de Open Food Facts…" | `app_en.arb:219` | `app_es.arb:108` |
| `settingsDataSourcesUsda` | "USDA FoodData Central data is public domain under CC0 1.0." | "Los datos de USDA FoodData Central son de dominio público bajo CC0 1.0." | `app_en.arb:220` | `app_es.arb:109` |

> **No existe** `commonLogout`, `commonSignOut`, `signOut`, ni `logout` en los ARB. La única cadena de cierre de sesión es `settingsLogOut`.

## Tests existentes

### `apps/mobile/test/settings_language_widget_test.dart` (636 líneas)

Único test dedicado a `SettingsScreen`. Cubre:

- **Idioma**: pulsa `language_settings_row`, abre sheet con N `language_option_<tag>`, cambiar a `es` refleja "Idioma", "Distribución de macros" y "Fuentes de datos" en pantalla, y persiste en `AppPreferencesRepository.savedLocaleCode`.
- **Tema**: pulsa `theme_settings_row`, verifica sheet con `theme_option_system|light|dark`, persiste `ThemeMode`.
- **Hidratación**: pulsa `hydration_goal_row`, valida conmutación litros↔onzas, incrementa y guarda con `save_goal_button`. **Test de dismiss por drag:** `await tester.drag(find.byType(BottomSheet), const Offset(0, 500))` confirma que el drag cierra el sheet.
- **Calorie target**: pulsa `calorie_target_row`, escribe "1900" en `dashboard_calorie_target_field`, guarda con `dashboard_save_calorie_target_button`. Verifica snackbar "Calories saved", `macro_prompt_not_now` visible, subtítulo "1900 Kcal daily target".
- **Macros**: `macro_distribution_row` con/sin calorías, gate `_MacroRequiresCaloriesSheet`, abrir `MacroDistributionSheet`.

**Cobertura real:**

- ✅ `ValueKey`s estables: `language_settings_row`, `theme_settings_row`, `hydration_goal_row`, `calorie_target_row`, `macro_distribution_row`, `theme_option_system|light|dark`, `language_option_<tag>`, `save_goal_button`, `hydration_goal_value`, `hydration_unit_liters`, `hydration_unit_ounces`, `hydration_goal_increase_button`, `hydration_goal_decrease_button`, `dashboard_calorie_target_field`, `dashboard_save_calorie_target_button`, `macro_prompt_not_now`, `macro_distribution_save_button`, `macro_requires_calories_set_now`, `macro_requires_calories_skip`.
- ✅ Cambio de idioma en vivo y persistencia.
- ✅ Cambio de tema en vivo y persistencia.
- ✅ Hidratación litros/onzas + dismiss con drag.
- ✅ Calorie target + prompt de macros + rollback.
- ✅ Gate "Set calories first" + skip.
- ❌ No hay test para el row de **Data sources** (es estático).
- ❌ No hay test para el **botón Logout**.
- ❌ No hay test para el path de error (`settings.error` banner).
- ❌ No hay test para el **header de usuario**.
- ❌ No hay test para la **cabecera** (`settingsTitle`, `settingsSubtitle`).

### `apps/mobile/patrol_test/goals_settings_test.dart` (12.4 KB, 3 patrolTests)

- "sets first calorie target from the Home setup prompt" — desde dashboard.
- "uses calorie calculator estimate before saving Home target" — wizard desde dashboard.
- "edits goals from Menu and updates Home immediately" — **sí toca Settings**: pulsa `nav_menu_button`, espera `calorie_target_row`, edita calorías, comprueba "2300 Kcal daily target", luego abre `hydration_goal_row` y sube 10 veces el stepper.

### `apps/mobile/patrol_test/language_settings_test.dart` (3.7 KB, 1 patrolTest)

- "switches language from Menu and persists after app restart" — pulsa `nav_menu_button`, abre `language_settings_row`, cambia a `es` y luego a `en`, reinicia y verifica persistencia.

### Otros tests relevantes

- `apps/mobile/test/locale_view_model_test.dart` — VM de idioma.
- `apps/mobile/test/theme_mode_view_model_test.dart` — VM de tema.
- `apps/mobile/test/calorie_target_validation_test.dart` — validador del sheet de calorías.
- `apps/mobile/test/macro_distribution_test.dart` — modelo de distribución.
- `apps/mobile/test/dashboard_cleanup_widget_test.dart` — Dashboard, no Settings.

## ViewModel de Settings

`lib/ui/features/settings/view_models/settings_view_model.dart` (155 líneas). Métodos públicos:

- `Future<void> load({bool forceRefresh = false})` (línea 41-79) — cache-first + refresh en background.
- `Future<DailyGoals?> updateGoals({int? calories, double? hydrationGoalLiters, String? calorieTargetSource, MacroDistributionConfig? macroConfig, int? macroCalorieTarget})` (línea 81-125) — optimistic + rollback.
- `Future<AuthUser?> setTrustedMode(bool enabled)` (línea 127-141).
- `void reset()` (línea 143-149) — invocado por `app.dart:311` durante logout.

**No necesita cambios para el reagrupamiento visual** — su contrato se mantiene. La UI consume los getters públicos (`goals`, `isLoading`, `isSaving`, `error`) y los handlers `onTap` del `build`.

## Resumen de símbolos clave (para cuando se implemente)

| Símbolo | Fichero | Línea |
|---|---|---|
| `SettingsScreen` (root) | `lib/ui/features/settings/views/settings_screen.dart` | 18-25 |
| `_SettingsScreenState.build` (todo el `Column`) | `lib/ui/features/settings/views/settings_screen.dart` | 38-183 |
| `User card` (FreshCard limeSoft) | `lib/ui/features/settings/views/settings_screen.dart` | 54-99 |
| Hydration goal row | `lib/ui/features/settings/views/settings_screen.dart` | 114-123 |
| Calorie target row | `lib/ui/features/settings/views/settings_screen.dart` | 125-138 |
| Macro distribution row | `lib/ui/features/settings/views/settings_screen.dart` | 140-149 |
| Language row | `lib/ui/features/settings/views/settings_screen.dart` | 151-159 |
| Theme row | `lib/ui/features/settings/views/settings_screen.dart` | 161-169 |
| Data sources card | `lib/ui/features/settings/views/settings_screen.dart` | 171-176 + 466-510 |
| Logout button | `lib/ui/features/settings/views/settings_screen.dart` | 178-181 |
| `_SettingsGoalRow` (tile) | `lib/ui/features/settings/views/settings_screen.dart` | 609-651 |
| `_SettingsOption` (sheet option) | `lib/ui/features/settings/views/settings_screen.dart` | 523-547 |
| `_DataSourcesCard` | `lib/ui/features/settings/views/settings_screen.dart` | 466-510 |
| `_MacroRequiresCaloriesSheet` | `lib/ui/features/settings/views/settings_screen.dart` | 549-606 |
| `_SettingsScreenState._showLanguageSheet` | `lib/ui/features/settings/views/settings_screen.dart` | 412-458 |
| `_SettingsScreenState._showThemeSheet` | `lib/ui/features/settings/views/settings_screen.dart` | 337-410 |
| `FreshCard` (design system) | `lib/ui/core/design_system.dart` | 353- |
| `FreshIconChip` (design system) | `lib/ui/core/design_system.dart` | 439- |
| `FreshSectionTitle` (design system) | `lib/ui/core/design_system.dart` | 695-712 |
| `FreshMetricCard` (design system) | `lib/ui/core/design_system.dart` | 472- |
| `_MacroGrid` (patrón reusable) | `lib/ui/features/meal_templates/views/usual_food_editor_screen.dart` | 630-649 |
| `_TwoColumnFields` (patrón reusable) | `lib/ui/features/meal_templates/views/usual_food_editor_screen.dart` | 603-622 |
| `SettingsViewModel` | `lib/ui/features/settings/view_models/settings_view_model.dart` | – |
| `HydrationGoalSheet` | `lib/ui/features/settings/views/hydration_goal_sheet.dart` | – |

## Decisiones pendientes

- **¿Grid 2 columnas en móvil compacto o solo en pantallas anchas?** En 320 dp de área, 2 columnas con `FreshSpacing.md` quedan a ~154 dp por celda, lo que es estrecho para el `_SettingsGoalRow` actual (icon + texto + chevron). Posibles enfoques: (a) grid 2 cols siempre con celda simplificada; (b) grid 2 cols en `>=560` dp, columna única en `>=560`; (c) grid 2 cols siempre con celda tipo `_NutritionChip` (icon + label + value apilados).
- **¿Se añade una cabecera de sección "Calorías" / "App"?** `FreshSectionTitle` ya existe (línea 695 de `design_system.dart`) y no se usa en Settings. Añadir cabeceras ayuda a la lectura pero requiere nuevas claves ARB (`settingsSectionCalories`, `settingsSectionApp`).
- **¿La fila de hidratación entra en el grid 2-col de calorías o se queda aparte?** El usuario no la menciona. Hidratación no es calorías estrictamente. Decisión por defecto: se queda como fila propia (fuera del grid) para no asumir.
- **¿Data sources se reagrupa con "App" o se queda como card informativa aparte?** El usuario no la menciona. Decisión por defecto: se queda como está.
- **¿El grid 2-col se aplica solo a calorías o también a "App" (idioma + apariencia)?** El usuario menciona grid solo para calorías, y luego pide "otra sección" (no grid explícito) para App. Decisión por defecto: grid 2-col solo para calorías; App como una sección nueva con dos filas o dos tarjetas, según se decida.

## Informes completos en este directorio

- `02-investigation-settings-screen.md` — mapeo exhaustivo de la pantalla actual, ViewModel, sheets, tests, ARB.
- `02-investigation-grid-patterns.md` — inventario de widgets de grid, primitivas de tarjeta, patrones reutilizables, responsividad.
