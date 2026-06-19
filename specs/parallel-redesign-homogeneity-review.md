# Revisión de homogeneidad: ramas AMOLED paralelas

## Alcance

Revisión manual desde el hilo padre tras fallar el reviewer asíncrono por falta de herramientas/aceptación. Se compararon las tres ramas de implementación contra `design/amoled-redesign` (`32a3a97`):

- `design/amoled-settings-history` en `.worktrees/amoled-settings-history`, commit `9b33294`.
- `design/amoled-meal-create-agent` en `.worktrees/amoled-meal-create-agent`, commit `edc89b2`.
- `design/amoled-saved-editors` en `.worktrees/amoled-saved-editors`, commit `2305d62`.

La revisión se centra en consistencia visual AMOLED, alcance, validación y riesgos antes de mergear.

## Estado de ramas

| Rama | Commit | Estado | Reporte |
|---|---:|---|---|
| `design/amoled-settings-history` | `9b33294` | Commit creado; worktree solo conserva `subagent-output/` sin trackear | `specs/settings-history-implementation-report.md` |
| `design/amoled-meal-create-agent` | `edc89b2` | Commit creado y worktree limpio | `specs/meal-create-agent-implementation-report.md` |
| `design/amoled-saved-editors` | `2305d62` | Commit creado y worktree limpio | `specs/saved-editors-implementation-report.md` |

## Resumen de diffs

### Settings + History

Archivos cambiados:

- `apps/mobile/lib/ui/features/settings/views/settings_screen.dart`
- `apps/mobile/lib/ui/features/meal_history/views/meal_history_screen.dart`
- `specs/settings-history-implementation-report.md`

Resultado visual esperado: Settings pasa de tarjetas apiladas a header textual, filas full-width, divisores y secciones; History convierte chart y comidas en secciones/filas abiertas.

### Meal Create + Voice + Agent

Archivos cambiados:

- `apps/mobile/lib/ui/features/voice_log/views/voice_log_screen.dart`
- `apps/mobile/lib/ui/features/agent_chat/views/agent_chat_screen.dart`
- `apps/mobile/test/voice_log_screen_test.dart`
- `specs/meal-create-agent-implementation-report.md`
- `subagent-output/meal-create-agent-lean.md`

Resultado visual esperado: reduce `FreshCard`/paneles en creación de comida, propuestas, clarificaciones y chat; pasa a secciones abiertas, métricas tipográficas y filas con reglas.

### Saved Editors + Scanner

Archivos cambiados:

- `apps/mobile/lib/ui/features/meal_templates/views/usual_food_editor_screen.dart`
- `apps/mobile/lib/ui/features/meal_templates/views/meal_template_editor_screen.dart`
- `apps/mobile/lib/ui/features/meal_templates/views/usual_food_scan_screen.dart`
- `apps/mobile/test/features/meal_templates/usual_food_scan_screen_test.dart`
- `apps/mobile/test/meal_template_editor_widget_test.dart`
- `apps/mobile/test/meal_templates_widget_test.dart`
- `specs/saved-editors-implementation-report.md`
- `subagent-output/saved-editors-lean.md`

Resultado visual esperado: editores como formularios abiertos con títulos/divisores; scanner con HUD oscuro/translúcido en vez de `Card` Material blanca/roja.

## Hallazgos

| Severidad | Rama / archivo | Hallazgo | Recomendación |
|---|---|---|---|
| Media | `design/amoled-meal-create-agent`, `design/amoled-saved-editors` | Los commits incluyen archivos en `subagent-output/`. Son artefactos de ejecución, no producto ni spec revisable de larga vida. | Antes de mergear, quitar esos archivos del commit o aceptar explícitamente que se versionen. Preferencia: removerlos y dejar solo `specs/*-implementation-report.md`. |
| Media | Todas | Ninguna rama tuvo validación visual con emulator/Marionette. Los tests pasan, pero el cambio es principalmente visual. | Antes del merge final a `design/amoled-redesign`, ejecutar local toolkit y revisar pantallas principales con hot reload/screenshot. |
| Baja-media | Todas | `flutter analyze --no-pub` sigue reportando el info preexistente `lib/app/theme.dart:244:23 prefer_const_constructors`. | No bloquear estas ramas por ello. Corregir en commit separado si se quiere dejar analyze verde. |
| Baja | `design/amoled-settings-history` | Worktree conserva `subagent-output/` sin trackear. No afecta commit, pero ensucia estado local. | Borrar o ignorar ese directorio antes de seguir usando el worktree. |
| Baja | `design/amoled-saved-editors` | `graphify update .` fue intentado y rechazó sobrescribir por menos nodos. | No bloquear; ejecutar `graphify update .` desde la rama final integrada y revisar salida. |

## Homogeneidad visual

La dirección general es coherente entre ramas:

- Las tres migran de tarjetas/cajas a **secciones abiertas**.
- El patrón de **filas full-width + divisores sutiles** aparece en Settings, History, meal create y editores.
- Se reduce el uso de icon chips decorativos y contenedores coloreados.
- Los estados especiales conservan contraste, pero con menos superficie sólida.

Puntos a vigilar en revisión visual:

- **Densidad vertical**: las tres ramas pueden haber resuelto spacing de forma local. Al integrarlas, comprobar que Settings, History, Meal Create y Editors tienen ritmos similares (`FreshSpacing.lg` entre secciones; filas con padding comparable).
- **Acciones secundarias**: History y My foods usan `⋯`/acciones discretas; Meal Create/Agent puede seguir teniendo controles más densos por naturaleza. Verificar que no parezca otra app.
- **Scanner**: el HUD oscuro es conceptualmente correcto, pero debe comprobarse sobre fondos claros/oscuros de cámara.

## Validación reportada

- Settings/History:
  - `flutter pub get`: passed.
  - `dart format`: passed.
  - `flutter analyze --no-pub`: solo info preexistente de `theme.dart`.
  - `flutter test --no-pub test/settings_language_widget_test.dart test/dashboard_cleanup_widget_test.dart`: passed, 23 tests.
  - `git diff --check`: passed.
- Meal Create/Agent:
  - `flutter pub get`: passed.
  - `flutter analyze --no-pub`: solo info preexistente de `theme.dart`.
  - `flutter test --no-pub test/voice_log_screen_test.dart test/agent_chat_test.dart`: passed, `+19 ~5`.
  - `git diff --check`: passed.
  - `graphify update .`: completed without graph changes.
- Saved Editors/Scanner:
  - `flutter pub get`: passed.
  - focused analyze on changed files: passed.
  - focused widget tests: passed, 31 tests.
  - `git diff --check`: passed.
  - full analyze only blocked by preexisting `theme.dart` info.

## Merge recommendation

Recommended order:

1. `design/amoled-settings-history` — smallest surface, foundational list/section style.
2. `design/amoled-saved-editors` — aligns editor patterns with Settings/My foods; has good focused test coverage.
3. `design/amoled-meal-create-agent` — broadest and most sensitive flow; merge after visual pass because it changes many interaction surfaces.

Before merging each branch:

1. Remove committed `subagent-output/*` from `design/amoled-meal-create-agent` and `design/amoled-saved-editors`, unless explicitly desired.
2. Run/inspect the local toolkit on emulator for the modified routes.
3. After all merges, run `flutter test` from `apps/mobile` and `graphify update .` once on the integrated branch.

## Verdict

Las tres ramas avanzan en la misma dirección visual y son razonablemente homogéneas para revisión visual. No veo un bloqueo conceptual para integrarlas, pero sí recomiendo limpiar `subagent-output` de los commits y hacer una pasada visual con local toolkit antes de mergear definitivamente.

