# Investigation — Patrones de grid 2 columnas para la pestaña de Settings

Scope: `/home/antonio/code/cal-tracker/apps/mobile/lib` y `apps/mobile/test`.
Fecha: 2026-06-15.
Flutter toolchain: 3.41.9 / Dart 3.11.5 (`flutter --version`).
Pantalla objetivo: `lib/ui/features/settings/views/settings_screen.dart` (objetivo: reagrupar opciones en grid 2 columnas + sección "Configuración de la app").

> Este documento **solo documenta hallazgos**. No propone ni evalúa fixes.

---

## TL;DR

- El proyecto **no usa** widgets nativos `GridView` / `SliverGrid` / `StaggeredGrid` / `flutter_staggered_grid_view` en **ninguna** parte del código. Tampoco hay paquetes relacionados en `pubspec.yaml`.
- Las opciones que se renderizan "en paralelo" (filas de N columnas de cards del mismo tamaño) están implementadas **siempre** con `LayoutBuilder` + `Row`/`Wrap` + `Expanded`/`SizedBox(width: …)`.
- No existe un widget de design system dedicado para "settings row" o "settings tile"; las opciones de Settings están hechas a mano con `_SettingsGoalRow` y `_SettingsOption` (clases privadas dentro de `settings_screen.dart`).
- `FreshCard` es la primitiva base de tarjeta. Tiene `padding`, `color`, `radius`, `onTap`, `shadow`. No tiene `header/icon/label/subtitle` "integrados" — se combinan manualmente con `FreshIconChip` + `Text` + `Column`/`Row`.
- La responsividad "wide" (tablet / split) ya está parcialmente contemplada: `AppShell` rompe a `>=720` (lateral nav), `FreshPage` cape el contenido a `maxWidth: 760`, y dos widgets usan `LayoutBuilder` con sus propios breakpoints (430 y 560).
- Los tests de Settings actuales **no** prueban grids 2 columnas; presuponen un único `Column` con `ValueKey('…settings_row')` apilados.

---

## 1. Inventario de widgets de grid

Búsquedas exhaustivas (`grep -rn`) sobre `apps/mobile/lib`:

| Widget | Hits | Comentario |
| --- | --- | --- |
| `GridView(` (cualquier constructor) | 0 | No se usa en el proyecto. |
| `SliverGrid(` | 0 | No se usa. |
| `SliverGridDelegate` | 0 | No se usa. |
| `StaggeredGridView` / `flutter_staggered_grid_view` | 0 | No se usa. |
| `MasonryGrid` / `WaterfallFlow` / `GridLayout` | 0 | No se usan. |
| `Wrap(` | 17 (10 archivos) | Usado extensivamente para chips, presets, options. |
| `LayoutBuilder(` | 13 (8 archivos) | Patrón clave para "grid responsivo" / multi-columna. |
| `Row(` + 2× `Expanded` | sí | Patrón multi-columna más simple (ver §3). |
| `crossAxisCount:` / `columnCount:` | 0 | No existe el concepto de "columnas" en ningún delegate. |

### 1.1 Paquete `pubspec.yaml`

`/home/antonio/code/cal-tracker/apps/mobile/pubspec.yaml` (líneas 11-32) lista únicamente:

- `flutter`, `flutter_localizations`, `camera`, `flutter_secure_storage`, `go_router`, `google_mlkit_text_recognition`, `google_sign_in`, `http`, `http_parser`, `intl`, `package_info_plus`, `path_provider`, `permission_handler`, `provider`, `record`, `marionette_flutter`, `shared_preferences`, `url_launcher`.

**No hay paquetes de grid**. Cualquier grid 2 columnas tiene que construirse a mano.

### 1.2 Usos de `LayoutBuilder` (los relevantes para grids)

| Fichero | Línea | Propósito | Breakpoint |
| --- | --- | --- | --- |
| `lib/ui/core/app_shell.dart` | 48 | Cambia `BottomNav` ↔ `SideNav` (wide). | `>=720` |
| `lib/ui/features/meal_templates/views/usual_food_editor_screen.dart` | 610 | `_TwoColumnFields`: 1 columna si estrecho, fila con `Expanded` si ancho. | `<560` colapsa |
| `lib/ui/features/meal_templates/views/usual_food_editor_screen.dart` | 637 | `_MacroGrid`: 2 o 4 columnas via `Wrap` + `SizedBox(width: …)`. | `>=560` ⇒ 4 cols; si no 2 |
| `lib/ui/features/meal_templates/views/meal_template_editor_screen.dart` | 703 | `_BottomSaveBar`: `Column` o `Row` según ancho. | `<420` colapsa |
| `lib/ui/features/dashboard/views/calorie_target_sheet.dart` | 1817 | Reorganiza controles del sheet de calorías. | — |
| `lib/ui/features/dashboard/views/dashboard_screen.dart` | — (no LayoutBuilder, pero equivalente) | `_MacroSummaryRow` siempre 3 columnas fijas (`Row` + 3× `Expanded`). | fijo |
| `lib/ui/shared/meal_item_editor_sheet.dart` | 264, 366 | Inline row/column swap por ancho. | `<260` colapsa |
| `lib/local_toolkit/ui/local_toolkit_overlay.dart` | 405 | Toolkit quick-mutators: 2 columnas a `>=430`. | `>=430` |

> Importante para la decisión: los **únicos** patrones que producen un grid 2 columnas visualmente idéntico a lo que el usuario describe son `_MacroGrid` (`Wrap` + `SizedBox(width)`) y `_TwoColumnFields` (`Row` + `Expanded`).

---

## 2. Inventario de widgets de tarjeta / tile del design system

Fichero único: `lib/ui/core/design_system.dart` (21.0K, 826 líneas).

No hay un widget `FreshSettingTile` ni `FreshSettingRow` en el design system. Las opciones de Settings están implementadas como **clases privadas** dentro de `settings_screen.dart` (ver §6).

### 2.1 Tarjetas del design system

| Widget | Línea | Props principales | Notas |
| --- | --- | --- | --- |
| `FreshCard` | 353 | `child` (req), `padding = EdgeInsets.all(20)`, `color`, `radius = FreshRadii.lg`, `onTap`, `shadow = true` | Primitiva. Sin `icon/title/subtitle` propios. Soporta `InkWell` automático si `onTap != null`. |
| `FreshMetricCard` | 472 | `title`, `value`, `unit`, `icon`, `color` (todos req), `sparkline` (opt) | Card con icono + título + valor + unidad. `radius = FreshRadii.lg`, padding `16`. Pensada para dashboards / métricas. |
| `FreshStatusBanner` | 540 | `icon`, `title` (req), `message?`, `color = FreshColors.lime`, `action?` | Card coloreada (alpha 0.16) sin shadow. Usada para errores y avisos. |
| `FreshEmptyState` | 758 | `icon`, `title`, `message` | Card centrada, padding interno, ícono circular. |
| `FreshPage` | 248 | `title`, `child` (req), `actions = []`, `subtitle?`, `maxWidth = 760`, `leading?` | El "page wrapper" — centra + cape a `760` + CustomScrollView. |
| `FreshHeader` | 297 | `title`, `subtitle?`, `actions = []`, `leading?` | Subheader. `actions` se renderiza con `Wrap(spacing: FreshSpacing.sm)`. |
| `FreshSectionTitle` | 800 | `title` (req), `trailing?` | `Row(Expanded(Text) + trailing)`. Usado para títulos de sección en otros sitios (meal_history, voice_log, meal_template_editor). |
| `FreshIconButton` | 399 | `icon` (req), `onPressed?`, `tooltip?`, `backgroundColor?`, `foregroundColor?`, `size = 48` | Botón circular. |
| `FreshIconChip` | 439 | `icon`, `color` (req), `backgroundColor?`, `size = 42` | Círculo `size×size` con `color.withValues(alpha: 0.14)` de fondo y `Icon` (color del icono = `size * 0.5`). |
| `FreshProgressRing` | 590 | `progress`, `center` (req), `size = 90`, `color = FreshColors.lime`, `trackColor?` | Anillo de progreso. |
| `FreshMiniBars` | 673 | `values` (req), `color = FreshColors.mint`, `height = 46` | Barras de mini chart. |
| `FreshFoodStack` | 717 | `assets = const[…]`, `size = 38` | Stack de imágenes circulares. |
| `FreshSpacing` | 202 | `xs=4, sm=8, md=12, lg=16, xl=24, xxl=32` | Tokens de espacio (estáticos). |
| `FreshRadii` | 213 | `sm=10, md=18, lg=24, xl=32` | Tokens de radio. |
| `FreshPalette` (ThemeExtension) | 30 | `appBg, screen, surface, surfaceSoft, surfaceMuted, ink, inkSoft, inkMuted, rule, ruleSoft, lime, limeDeep, limeSoft, limeWash, leaf, water, orange, mint, coral, yellow` | ThemeExtension con 2 paletas (`FreshPalette.light` y `FreshPalette.dark`). Acceso via extensión `context.freshPalette`. |
| `FreshColors` | 5 | Constantes `Color(0x…)` | Equivalentes a `FreshPalette.light` pero como `static const`. |

### 2.2 Sombras / elevaciones de las tarjetas

`lib/ui/core/design_system.dart:240-260`:

```dart
const _lightSoftShadow = [
  BoxShadow(
    color: Color(0x1f080907),
    blurRadius: 30,
    offset: Offset(0, 16),
  ),
  BoxShadow(
    color: Color(0x0f080907),
    blurRadius: 10,
    offset: Offset(0, 4),
  ),
];

const _darkSoftShadow = [
  BoxShadow(
    color: Color(0x66080b07),
    blurRadius: 24,
    offset: Offset(0, 14),
  ),
  BoxShadow(
    color: Color(0x3310140d),
    blurRadius: 8,
    offset: Offset(0, 3),
  ),
];
```

Se aplican dentro de `FreshCard.build` (`design_system.dart:374-384`) **solo** si `shadow: true`. Si se quiere evitar el shadow dentro de un grid denso, se puede pasar `shadow: false`.

### 2.3 Colores frecuentemente usados en tarjetas

(`FreshPalette`, `design_system.dart:30-130`.)

- `palette.surface` (default color de `FreshCard`).
- `palette.surfaceSoft` / `palette.surfaceMuted` (alternativas suaves).
- `palette.limeSoft` / `palette.limeWash` (acentos del user card y CTA).
- Acentos semánticos: `palette.water` (azul), `palette.orange`, `palette.leaf` (verde), `palette.mint`, `palette.coral`, `palette.yellow`, `palette.limeDeep`.

---

## 3. Patrones buenos para grid 2 columnas (con código concreto)

### 3.1 Patrón A — `Row` + `Expanded` × 2 (estilo `_MacroSummaryRow` del dashboard)

**Fichero:** `lib/ui/features/dashboard/views/dashboard_screen.dart:523-585`

Resumen del patrón (3 columnas en este caso; para 2 columnas es directamente extrapolable):

```dart
class _MacroSummaryRow extends StatelessWidget {
  const _MacroSummaryRow({required this.summary});
  final DailySummary? summary;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final l10n = context.l10n;
    // ...
    return Row(
      children: [
        Expanded(
          child: _MacroSummaryPill(
            assetPath: 'assets/images/icons/carbs_icon.png',
            iconKey: const ValueKey('dashboard_macro_carbs_icon'),
            label: l10n.commonCarbs,
            value: hasConfiguredMacros ? _macroRatio(...) : '',
            color: palette.orange,
          ),
        ),
        const SizedBox(width: FreshSpacing.sm),
        Expanded(
          child: _MacroSummaryPill( /* proteína */ ),
        ),
        const SizedBox(width: FreshSpacing.sm),
        Expanded(
          child: _MacroSummaryPill( /* grasas */ ),
        ),
      ],
    );
  }
}
```

Cada `_MacroSummaryPill` es un `FreshCard` (radius `FreshRadii.lg`, padding `(8, 8)`, color `palette.surface`) con su propio `minHeight: 42` (línea 610).

**Pros:** automático (Expanded reparte), alturas iguales si `mainAxisSize`/`intrinsicHeight` están bien.
**Contras:** no envuelve; si los items no caben en una fila a ancho estrecho, se desbordan (no es un grid 2×N verdadero).

### 3.2 Patrón B — `_TwoColumnFields` (1 col si estrecho, 2 si ancho)

**Fichero:** `lib/ui/features/meal_templates/views/usual_food_editor_screen.dart:603-622`

```dart
class _TwoColumnFields extends StatelessWidget {
  const _TwoColumnFields({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(children: children);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              Expanded(child: children[index]),
              if (index != children.length - 1)
                const SizedBox(width: FreshSpacing.md),
            ],
          ],
        );
      },
    );
  }
}
```

**Pros:** envuelve automáticamente (vuelve a columna si no cabe).
**Contras:** todas las celdas en una misma fila, no es 2×N.

### 3.3 Patrón C — `_MacroGrid` (Wrap + SizedBox(width), 2 ó 4 columnas)

**Fichero:** `lib/ui/features/meal_templates/views/usual_food_editor_screen.dart:630-649`

```dart
class _MacroGrid extends StatelessWidget {
  const _MacroGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 4 : 2;
        final itemWidth =
            (constraints.maxWidth - FreshSpacing.md * (columns - 1)) / columns;
        return Wrap(
          spacing: FreshSpacing.md,
          runSpacing: FreshSpacing.sm,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}
```

**Pros:** **el patrón más cercano a un "grid 2×N" verdadero**. Soporta N columnas, envuelve automáticamente, celdas iguales. Es el patrón que mejor encajaría con "reagrupar 3 opciones de calorías en grid 2 columnas".
**Contras:** requiere `LayoutBuilder` y cálculo manual de `itemWidth` con resta de gaps.

### 3.4 Patrón D — `Wrap` con `width` fija (mutators del local toolkit)

**Fichero:** `lib/local_toolkit/ui/local_toolkit_overlay.dart:400-490`

```dart
LayoutBuilder(
  builder: (context, constraints) {
    final twoColumn = constraints.maxWidth >= 430;
    final width = twoColumn
        ? (constraints.maxWidth - 8) / 2
        : constraints.maxWidth;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _MutatorButton(key: …, width: width, …),
        _MutatorButton(key: …, width: width, …),
        _MutatorButton(key: …, width: width, …),
        // …
      ],
    );
  },
)
```

Cada `_MutatorButton` (`local_toolkit_overlay.dart:524-580`) es un `SizedBox(width: width, child: OutlinedButton.icon(…))`. Es decir: variantes de C con botón outlined en lugar de `FreshCard`.

**Pros:** idéntico a C, pero los items son botones en vez de cards.
**Contras:** no es del design system central, es código del local toolkit (que no llega a producción en flavors normales).

### 3.5 Patrón E — Inline (settings sheet dropdowns)

`lib/ui/features/settings/views/settings_screen.dart:441-462` muestra cómo se renderiza cada idioma en el sheet de idioma — un `Column` con `_SettingsOption` apilados, sin grid:

```dart
for (final locale in AppLocalizations.supportedLocales) ...[
  _SettingsOption(
    key: ValueKey('language_option_${locale.toLanguageTag()}'),
    title: _languageDisplayName(locale),
    selected: localeViewModel.locale == locale,
    onTap: () async { … },
  ),
  if (locale != AppLocalizations.supportedLocales.last)
    const SizedBox(height: FreshSpacing.sm),
],
```

`_SettingsOption` está definido en `settings_screen.dart:523-547` (un `FreshCard` con `shadow: false` y un `Icon(Icons.check_rounded)` si `selected`).

---

## 4. Patrón actual de la pantalla de Settings

**Fichero:** `lib/ui/features/settings/views/settings_screen.dart` (689 líneas, layout completo en una `Column` vertical).

### 4.1 `ContentFrame` (línea 50) — wrappea todo

`lib/ui/core/content_frame.dart:1-30` es un wrapper trivial de `FreshPage`:

```dart
return FreshPage(
  title: title,
  subtitle: subtitle,
  actions: actions ?? const [],
  leading: leading,
  child: child,
);
```

`FreshPage` (`design_system.dart:248-295`) aplica:

```dart
return SafeArea(
  child: Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),  // maxWidth = 760
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: FreshHeader(…),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            sliver: SliverToBoxAdapter(child: child),
          ),
        ],
      ),
    ),
  ),
);
```

Es decir, **el área de contenido disponible** en `SettingsScreen` (en el peor caso: pantalla de 360dp) es `360 - 2*20 = 320dp`; en pantallas grandes se capa a `760 - 2*20 = 720dp`.

### 4.2 Contenido actual (`settings_screen.dart:53-175`)

Todo está en una `Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: […])` con `const SizedBox(height: FreshSpacing.md)` entre cada `_SettingsGoalRow`. Estructura:

1. **User card** (línea 55-101): `FreshCard` con `radius: FreshRadii.xl`, color `palette.limeSoft`. Avatar circular de 58×58 + nombre + email.
2. **`LinearProgressIndicator`** si `settings.isLoading` (línea 104-106).
3. **`FreshStatusBanner`** si `settings.error != null` (línea 108-115).
4. **`_SettingsGoalRow('hydration_goal_row')`** — icono `water_drop`, color `palette.water`, "Hydration goal" (línea 117-122).
5. **`_SettingsGoalRow('calorie_target_row')`** — icono `flag`, color `palette.orange`, "Calorie target" (línea 125-138).
6. **`_SettingsGoalRow('macro_distribution_row')`** — icono `pie_chart`, color `palette.leaf`, "Macro distribution" (línea 141-149).
7. **`_SettingsGoalRow('language_settings_row')`** — icono `translate`, color `palette.mint`, "Language" (línea 151-159).
8. **`_SettingsGoalRow('theme_settings_row')`** — icono `contrast`, color `palette.limeDeep`, "Appearance" (línea 160-169).
9. **`_DataSourcesCard`** — `FreshCard` con `padding: EdgeInsets.all(16)`, `shadow: false`, `FreshIconChip(Icons.source_rounded, palette.orange)` + 4 textos (líneas 171-176 + 466-510).
10. **`SizedBox(height: FreshSpacing.xl)`** + `OutlinedButton.icon` "Log out" (línea 178-181).

> **Conclusión:** las opciones de calorías (3) son los items 4-6; los items 7-8 son "configuración de la app"; el resto se mantiene.

### 4.3 `_SettingsGoalRow` (línea 609-651)

Es el "tile" usado 5 veces. Estructura:

```dart
class _SettingsGoalRow extends StatelessWidget {
  const _SettingsGoalRow({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    return FreshCard(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Row(
        children: [
          FreshIconChip(icon: icon, color: color),
          const SizedBox(width: FreshSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: palette.inkMuted,
                      ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}
```

Es decir: **`FreshCard` (radius default `FreshRadii.lg`, padding `16`, color default `palette.surface`, shadow default) + `FreshIconChip` + título + subtítulo + chevron**. Sin `ValueKey` propio — el `Key` se le pasa desde fuera (cada `_SettingsGoalRow` recibe `key: ValueKey('hydration_goal_row')` etc.).

### 4.4 Otros widgets privados del fichero

- `_SettingsOption` (línea 523-547): `FreshCard(padding: 16, onTap, shadow: false) + Row(Expanded(Text) + check icon)`. Usado en los bottom sheets de language y theme.
- `_DataSourcesCard` (línea 466-510): `FreshCard(padding: 16, shadow: false) + FreshIconChip(Icons.source_rounded) + Column(Text título, Text subtítulo, Text OFF, Text USDA)`.
- `_MacroRequiresCaloriesSheet` (línea 549-606): `Padding` + `Column` con "handle" (Container 44×4) + textos + botones.

---

## 5. Patrones relacionados en otros features

### 5.1 `meal_history_screen.dart` (518 líneas)

- `lib/ui/features/meal_history/views/meal_history_screen.dart:218-280` define `_CaloriesChartCard` con un `Row` de 7 `_ChartBar` (uno por día de la semana) — cada `_ChartBar` es `Expanded` dentro del `Row`. Es un **gráfico de barras**, no un grid de tarjetas, pero el patrón Row+Expanded es idéntico.
- `_HistoryMealCard` (líneas 382-419): `FreshCard(padding: 16, onTap)` con `FreshIconChip` + título + fecha + kcal. Estructura similar a `_SettingsGoalRow` (sin chevron).
- `_SheetAction` (líneas 421-444): `FreshCard(padding: 16, onTap, shadow: false) + FreshIconChip + Text` — usado en `showModalBottomSheet` para "Edit ingredients" / "Delete".
- **`Wrap`** se usa en `meal_history_screen.dart:234` con `crossAxisAlignment: WrapCrossAlignment.end` para alinear número + "Kcal" + subtítulo (no es grid).

### 5.2 `dashboard_screen.dart` (32.8K)

- `_MacroSummaryRow` (línea 523-585): ya descrito en §3.1.
- `_DailyProgressCard` (línea 277-380): un único `FreshCard` enorme con `Row(Expanded(Column) + FreshProgressRing)`. **No** es grid; es una card con dos sub-zonas.
- `_WaterIntakeCard` (línea 729-870): `Container` con `padding: 14`, `BoxDecoration` propio (no usa `FreshCard` — usa un gradient blue custom) + `Row(FreshIconChip + Expanded(Column) + 2 step buttons)`.
- `_MealRow` (línea 946-989): `FreshCard(padding: 16) + Row(Expanded(Column) + IconButton(delete) + IconButton(edit))`.

### 5.3 `voice_log_screen.dart` (2613 líneas)

- **No hay grid 2 columnas.** Todos los `Wrap` se usan para chips, presets (50g, 100g, 150g, 200g), ChoiceChips, ActionChips, y para alinear inline texto + badges. Ejemplos:
  - `voice_log_screen.dart:560`: `Wrap(spacing: xs, runSpacing: xs, children: [ActionChip(50g), ActionChip(100g), …])`.
  - `voice_log_screen.dart:733`: `Wrap(spacing: 8, runSpacing: 8, children: [_PortionChoiceChip(…) × N])`.
  - `voice_log_screen.dart:1827`: `Wrap(spacing: sm, runSpacing: sm, children: [ChoiceChip(label)] × N)`.
  - `voice_log_screen.dart:2286`: idéntico a 560, para presets en `_ProposalItemCard`.
  - `voice_log_screen.dart:2520`: `Wrap(crossAxisAlignment: end, spacing: 4, children: [Text, Padding(Text)])` — alineación tipográfica.

### 5.4 `meal_templates_screen.dart` y `usual_food_editor_screen.dart`

- `_TemplateCard` y `_UsualFoodCard` (en `meal_templates_screen.dart:244-350` y `:262-340` aprox.): `FreshCard(padding: 16) + Column(Row(FreshIconChip + Expanded(Column) + 2 IconButtons) + SizedBox + Wrap(_NutritionChip × 4))`.
- `_NutritionChip` (`meal_templates_screen.dart:444-475`): `Container(padding: (12, 10)) + BoxDecoration(color.withAlpha(0.13), radius FreshRadii.md) + Column(label, value)`. **Esto es un candidato natural a celda de grid** (es un chip 2×N con label + valor).
- **`_TwoColumnFields` y `_MacroGrid`** (en `usual_food_editor_screen.dart:603-622` y `:630-649`): ya descritos en §3.

### 5.5 `dashboard/views/calorie_target_sheet.dart` (69.5K)

- No contiene grid 2 columnas. Es un sheet de scroll vertical con un wizard, presets, sliders, etc. Algunos `LayoutBuilder` aislados (línea 1817).
- `MacroPresetCard` (`macro_distribution_sheet.dart:858-953`): card "grande" con `Container + InkWell + AnimatedContainer` propio (no usa `FreshCard`). Tres `MacroPresetCard` se renderizan apilados en `Column` (línea 95-105), **no** en grid.

### 5.6 `meal_item_editor_sheet.dart` (líneas 264, 366)

`LayoutBuilder` que cambia `Column` ↔ `Row` cuando `maxWidth < 260`. Mismo patrón que §3.2 pero para 2 sub-zonas inline dentro de una card, no como grid.

---

## 6. Ficheros del design system relevantes (resumen ejecutivo)

| Fichero | Líneas | Qué aporta |
| --- | --- | --- |
| `lib/ui/core/design_system.dart` | 826 | `FreshColors`, `FreshPalette`, `FreshSpacing`, `FreshRadii`, `FreshPage`, `FreshHeader`, `FreshCard`, `FreshIconButton`, `FreshIconChip`, `FreshMetricCard`, `FreshStatusBanner`, `FreshProgressRing`, `FreshMiniBars`, `FreshFoodStack`, `FreshEmptyState`, `FreshSectionTitle`, sombras `_lightSoftShadow`/`_darkSoftShadow`. |
| `lib/ui/core/content_frame.dart` | 19 | Wrapper trivial de `FreshPage` con `title`/`subtitle`/`actions`/`leading`. |
| `lib/ui/core/app_shell.dart` | 726 | `AppShell` con breakpoint `>=720` (línea 51): cambia `BottomNav` ↔ `SideNav`. `_FreshSideNav` ocupa `width: 112` (línea 230-260). |
| `lib/app/theme.dart` | — | Tema Material, `buildLightTheme`/`buildDarkTheme`. **No** contiene el `FreshPalette` (eso es un `ThemeExtension` en `design_system.dart`). |

**No existe** ningún `lib/ui/core/grid.dart`, `lib/ui/core/settings_tile.dart`, o equivalente. La única "plantilla" de settings row está dentro de `settings_screen.dart` (clase privada `_SettingsGoalRow`).

---

## 7. Consideraciones de responsividad

### 7.1 Breakpoints existentes

| Componente | Fichero:línea | Breakpoint | Efecto |
| --- | --- | --- | --- |
| `AppShell` | `app_shell.dart:51` | `>=720` | Cambia `BottomNav` → `SideNav` de 112dp. |
| `FreshPage` | `design_system.dart:255,271` | `maxWidth = 760` (constante) | Cape del área de contenido. |
| `Local toolkit quick mutators` | `local_toolkit_overlay.dart:405` | `>=430` | 1 col → 2 cols. |
| `MacroGrid` | `usual_food_editor_screen.dart:639` | `>=560` | 2 cols → 4 cols. |
| `TwoColumnFields` | `usual_food_editor_screen.dart:610` | `<560` | Fila → Columna. |
| `BottomSaveBar` | `meal_template_editor_screen.dart:703` | `<420` | Fila → Columna. |
| `MealItemEditorSheet` | `meal_item_editor_sheet.dart:264,366` | `<260` | Fila → Columna. |
| Dashboard progress card | `dashboard_screen.dart:266,387` | `<380` | Tamaño compacto (no afecta a grid). |
| `DashboardEmptyMealsCard` | `dashboard_screen.dart:907` | — | `(width - 40).clamp(0, 720)` — centra y cape a 720. |

### 7.2 Ancho disponible para el grid de Settings

`ContentFrame` envuelve con `FreshPage(maxWidth: 760)`, padding lateral 20+20 = 40.

- Pantalla 360dp (móvil compacto): `360 - 40 = 320dp` para el grid.
- Pantalla 411dp (móvil estándar): `411 - 40 = 371dp`.
- Pantalla 600dp (tablet portrait): `600 - 40 = 560dp` — justo en el breakpoint del `_MacroGrid`.
- Pantalla 720dp+: capeado a `720dp` de área.

En el peor caso (320dp), 2 columnas con `FreshSpacing.md` (12) entre medias = `(320 - 12) / 2 = 154dp` por celda. Cada `_SettingsGoalRow` actual tiene `FreshIconChip(size: 42) + spacing md + Expanded(Column(title + subtitle)) + chevron` — a 154dp el texto queda **muy estrecho** (probablemente menos de 100dp para el `Expanded`).

> **Implicación:** un grid 2 columnas en móvil compacto es viable solo si el contenido de la card se simplifica (p. ej. quitar el subtítulo, o usar una variante vertical como `_MacroSummaryPill`).

### 7.3 Patrones "wide" en el resto del proyecto

- `_FreshSideNav` (`app_shell.dart:230-260`) ocupa 112dp en pantallas `>=720`, dejando 600dp+ de contenido.
- No hay ningún `LayoutBuilder` dentro de `SettingsScreen` o `MealHistoryScreen` para adaptar filas a ancho grande. El cape a 760 hace que el layout sea muy parecido entre tablet portrait y móvil ancho.

---

## 8. Tests existentes con grids

Búsqueda exhaustiva en `apps/mobile/test/`:

| Patrón | Hits | Comentario |
| --- | --- | --- |
| `GridView` / `StaggeredGrid` / `SliverGrid` / `crossAxisCount` | 0 | No hay tests de grids. |
| `Wrap` | 1 (en `meal_history_widget_test.dart:172,182`) | Solo referencia al `Wrap` del `_CaloriesChartCard` para verificar la posición de un pill. No es test de grid. |
| `findsNWidgets(2)` buscando un par de cards | no en settings | Los tests de settings asumen orden lineal con `ValueKey` distintos. |

### 8.1 `settings_language_widget_test.dart` (20.4K, ~600 líneas) — el test existente de Settings

`apps/mobile/test/settings_language_widget_test.dart`:

- Hace `pumpWidget` con `SettingsScreen` envuelto en `MaterialApp` + `MultiProvider` (líneas 312-378).
- Asume **layout vertical de filas**. Tests relevantes:
  - `expect(find.text('Language'), findsOneWidget)` (línea 41).
  - `await tester.tap(find.byKey(const ValueKey('language_settings_row')))` (línea 45) — busca una sola fila con ese key.
  - `await tester.tap(find.byKey(const ValueKey('theme_settings_row')))` (líneas 87, 109).
  - `await tester.tap(find.byKey(const ValueKey('hydration_goal_row')))` (línea 122) y luego `await tester.tap(find.byKey(const ValueKey('calorie_target_row')))` (línea 172).
- **No hay tests que verifiquen geometría, número de filas en paralelo, o que un grid tenga 2 columnas**. Cualquier cambio que mueva una opción de "fila propia con key `xxx_settings_row`" a "celda de grid" **romperá estos tests** hasta que se actualicen los finders.
- Existe además `theme_mode_view_model_test.dart` (3.1K) y `locale_view_model_test.dart` (2.9K) que no tocan widgets.

### 8.2 Otros tests relevantes

- `meal_history_widget_test.dart:172-182`: usa `find.byKey(presetWrapFinder)` + `tester.getRect(...)` para verificar posición de elementos, no grid.
- `dashboard_cleanup_widget_test.dart` (39.5K): cubre `_MacroSummaryRow` y demás, pero con asunciones de layout de **fila horizontal de 3**.
- `voice_log_screen_test.dart` (52.3K): no toca grids.

---

## 9. Resumen de hallazgos accionables (sin proponer implementación)

1. **No hay infraestructura de grid en el proyecto.** Cualquier grid 2×N hay que construirlo a mano con `LayoutBuilder` + `Wrap` + `SizedBox(width)` o `Row` + `Expanded`.
2. **El patrón más cercano y reusable es `_MacroGrid` (`usual_food_editor_screen.dart:630-649`)**, con su `_TwoColumnFields` y la versión del local toolkit (`local_toolkit_overlay.dart:400-410`) como variantes.
3. **No existe un widget de design system para settings row.** Hoy se usa una clase privada `_SettingsGoalRow` (línea 609) en `settings_screen.dart`. Cualquier refactor de la pantalla de Settings requerirá decidir si esa fila se reifica en el design system o se queda como widget local.
4. **`FreshCard` ya cubre todo lo necesario** (radius, color, padding, onTap, shadow) — no hace falta un widget nuevo de tarjeta. La combinación `FreshCard` + `FreshIconChip` + `Text` + `chevron` ya produce visualmente el mismo resultado que el tile actual.
5. **Breakpoint a vigilar:** 560dp cambia 2 cols ↔ 4 cols en `_MacroGrid`. 430dp cambia 1 ↔ 2 cols en el local toolkit. El área de contenido de Settings cape a 720dp (FreshPage) con 40dp de padding lateral — en móvil compacto el área es 320dp, donde 2 columnas con `FreshSpacing.md` quedan en ~154dp por celda.
6. **Tests de regresión:** `settings_language_widget_test.dart` busca explícitamente `find.byKey(ValueKey('xxx_settings_row'))` para `hydration`, `calorie_target`, `language`, `theme`, `macro_distribution`. Cualquier cambio a grid 2 columnas debe decidir si mantiene esos `ValueKey` (p. ej. poniéndolos en cada celda) o si reescribe los finders.
7. **Paleta y elevaciones:** ya documentadas (§2.2-2.3). Las tarjetas pequeñas en grid deberían probablemente pasar `shadow: false` para evitar ruido visual (igual que `_SettingsOption` y `_DataSourcesCard` actuales).
8. **El user card (`settings_screen.dart:55-101`) y la sección de logout (`settings_screen.dart:178-181`)** están separados del flujo "opciones de calorías" / "configuración de la app" — el usuario quiere mantenerlos como están.

---

## 10. Ficheros a abrir primero por el siguiente agente

1. `lib/ui/features/settings/views/settings_screen.dart` — pantalla objetivo (689 líneas).
2. `lib/ui/core/design_system.dart` — para primitivas (`FreshCard`, `FreshIconChip`, `FreshSectionTitle`, `FreshSpacing`).
3. `lib/ui/features/meal_templates/views/usual_food_editor_screen.dart:603-649` — patrones `_TwoColumnFields` y `_MacroGrid` (los más reutilizables).
4. `lib/ui/features/dashboard/views/dashboard_screen.dart:523-585` — `_MacroSummaryRow` como referencia de "fila horizontal de cards" (no grid).
5. `lib/ui/core/app_shell.dart:48-77` — entender el breakpoint 720 y el área disponible en wide.
6. `apps/mobile/test/settings_language_widget_test.dart` — tests a actualizar/preservar.
