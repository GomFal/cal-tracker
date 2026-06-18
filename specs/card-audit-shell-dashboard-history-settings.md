# Auditoría UI AMOLED: shell, dashboard, historial, settings y auth

## 1. Alcance

Plan de análisis para eliminar el antipatrón de tarjetas/contenedores pesados en superficies visibles de navegación principal y pantallas base. No propone cambios de lógica, backend ni modelo de datos.

Pantallas revisadas:

- `apps/mobile/lib/app/router.dart`
- `apps/mobile/lib/ui/core/app_shell.dart`
- `apps/mobile/lib/ui/core/content_frame.dart`
- `apps/mobile/lib/ui/core/design_system.dart`
- `apps/mobile/lib/ui/features/dashboard/views/dashboard_screen.dart`
- `apps/mobile/lib/ui/features/meal_history/views/meal_history_screen.dart`
- `apps/mobile/lib/ui/features/settings/views/settings_screen.dart`
- `apps/mobile/lib/ui/features/auth/views/auth_screen.dart`

Estilo objetivo: AMOLED negro, jerarquía textual, filas a ancho completo, divisores sutiles, acciones discretas, pocos iconos decorativos, sin tarjetas pesadas salvo que haya una razón funcional clara.

## 2. Mapa de rutas y accesibilidad

| Pantalla | Ruta / entrada | Acceso visible | Confianza |
|---|---|---:|---:|
| Auth | `/auth` | Redirección si no hay sesión; también local toolkit | Alta (`router.dart:47-50`) |
| Dashboard | `/dashboard` | Tab principal inicial | Alta (`router.dart:103-110`) |
| History | `/history` | Bottom nav | Alta (`router.dart:118-125`) |
| My foods/templates | `/templates` | Bottom nav; se audita en spec separada | Alta (`router.dart:133-140`) |
| Settings | `/settings` | Bottom nav | Alta (`router.dart:187+`, import y shell branch) |
| Agent | `/agent` | Ruta directa / accesos de UI | Media-alta (`router.dart:51-56`) |
| Create meal | `/meal/create` | Dashboard `+ Add Meal`, templates, ruta directa | Alta (`router.dart:58-69`) |
| Scan ingredient | `/templates/ingredients/scan` | Desde editor de ingrediente/local toolkit | Alta (`router.dart:71-76`) |

## 3. Hallazgos

| Severidad | Archivo / widget | Evidencia | Antipatrón | Dirección propuesta |
|---|---|---|---|---|
| Alta | `settings_screen.dart` — cabecera usuario | `FreshCard` con fondo lima en `SettingsScreen.build`, líneas `57-99` | Es una tarjeta grande, saturada y decorativa; rompe con el patrón minimalista del dashboard. | Convertir a bloque header textual: nombre/email en columna, avatar pequeño o inicial discreta sin tarjeta; separador inferior. |
| Alta | `settings_screen.dart` — `_SettingsGoalRow` | `FreshCard` en líneas `679-723` | Cada ajuste se presenta como tarjeta individual con icon chip y chevron; parece lista de cards. | Cambiar a filas full-width con divisor inferior, icono opcional pequeño o sin icono, chevron discreto. |
| Media-alta | `settings_screen.dart` — `_DeveloperSettingsCard`, `_DataSourcesCard`, `_SettingsOption` | `FreshCard` líneas `504-533`, `554-590`, `607-615` | El patrón card se repite para settings secundarios. | Agrupar por secciones con `FreshSectionTitle` + filas. Para toggles, usar row + switch alineado, sin contenedor. |
| Media-alta | `meal_history_screen.dart` — `_CaloriesChartCard` | `Container` con `surface/surfaceSoft`, radio XL y borde, líneas `226-232` | Aunque funcional, sigue leyendo como tarjeta grande. En AMOLED debería sentirse como módulo abierto con gráfica. | Rehacer como sección: título + total + barras sobre fondo screen, usando reglas y spacing. Mantener contraste de barras, quitar caja exterior. |
| Media | `meal_history_screen.dart` — `_HistoryMealCard` | `Container` con divisor en líneas `388-397`, pero incluye `FreshIconChip` líneas `400-404` | Ya no es tarjeta, pero conserva icono decorativo pesado por fila. | Seguir patrón My foods: texto primero, calorías al final, sin icon chip; quizá menú `⋯` para acciones si tap no es obvio. |
| Media | `meal_history_screen.dart` — bottom sheet actions | `_SheetAction` devuelve `FreshCard` en línea `450` | Acciones del sheet aparecen como tarjetas. | Cambiar a filas de acción limpias en modal: icono pequeño + texto + divisor opcional. |
| Baja-media | `dashboard_screen.dart` — dashboard empty meals | `_DashboardEmptyMealsCard` líneas `845+` | Nombre y estructura indican tarjeta aunque visualmente ya fue suavizada. | Revisar visualmente: si aún tiene borde/fondo, migrar a empty row/empty text centrado; si ya está bien, solo renombrar internamente opcional. |
| Baja-media | `dashboard_screen.dart` — meal row labels | `_MealLabelChip` con `Container` líneas `975-987` | Chips pueden añadir ruido si se multiplican. | Mantener solo si aportan categoría; si no, texto secundario plano. |
| Media | `design_system.dart` — `FreshCard`, `FreshMetricCard`, `FreshIconChip` | `FreshCard` líneas `374+`, `FreshMetricCard` `491+`, `FreshIconChip` `458+` | El sistema de diseño todavía empuja a implementar todo como card/chip. | No eliminar aún, pero documentar que son componentes legacy/restringidos. Crear o favorecer componentes de fila/sección minimalista. |
| Media | `auth_screen.dart` — hero/login | `BoxDecoration` en hero carousel aprox. línea `461` | Auth puede mantener algo más visual, pero debe evitar estética de paneles genéricos. | Auditar visualmente con local toolkit: si hay tarjetas blancas/superficies, llevar a composición editorial AMOLED. |

## 4. Plan propuesto

1. **Settings primero**: es la superficie con mayor densidad de `FreshCard` visible. Migrar user header, goal rows, language/theme options, developer/data source blocks a filas y secciones.
2. **History después**: quitar caja exterior de `_CaloriesChartCard`, convertir comidas a filas sin icon chip y sustituir `_SheetAction` card por acción plana.
3. **Design system preventivo**: añadir/usar componentes tipo `FreshListRow`, `FreshActionRow` o patrones inline existentes; no reescribir todo el design system aún.
4. **Dashboard cleanup fino**: revisar empty meals y chips solo si visualmente siguen pareciendo contenedores.
5. **Auth visual pass**: revisar desde local toolkit; solo tocar si los paneles chocan claramente con AMOLED.

## 5. No-goals

- No cambiar navegación, rutas ni estado de sesión.
- No rediseñar create meal, agent, voice ni templates aquí; tienen spec separada.
- No eliminar `FreshCard` globalmente en una sola pasada.
- No cambiar textos/l10n salvo que sea necesario para una UI concreta.
- No introducir nuevas animaciones complejas.

## 6. Validación

Automática:

```bash
cd apps/mobile
flutter analyze --no-pub
flutter test test/settings_language_widget_test.dart
flutter test test/meal_history* test/dashboard_cleanup_widget_test.dart
flutter test
```

Manual/local toolkit:

```bash
flutter run --flavor local --debug --target lib/main_local.dart --dart-define=API_BASE_URL=http://10.0.2.2:3000 -d emulator-5554
```

Revisar escenarios:

- Dashboard normal/empty/over target/goals not configured.
- History con comidas y sin comidas.
- Settings con goals configurados, idioma/tema, developer settings.
- Auth si local toolkit permite `LocalToolkitRoute.auth`.

## 7. Riesgos y preguntas abiertas

- Settings puede perder escaneabilidad si se quitan todos los iconos; conviene mantener iconos solo donde sirvan como anclas semánticas.
- History chart necesita conservar percepción de “módulo” sin caja; puede requerir una regla superior/inferior y mayor spacing.
- `FreshCard` sigue siendo útil para diálogos/estados especiales; prohibirlo globalmente sería demasiado agresivo.
- Pendiente de decisión: ¿los chips de categoría/calorías deben desaparecer por completo o solo reducirse?

