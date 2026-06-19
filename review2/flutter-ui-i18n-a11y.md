## Review

- Correct:
  - La infraestructura base de i18n y tema está bien encaminada: `MaterialApp.router` usa `AppLocalizations`, delegados Flutter y `supportedLocales` (`apps/mobile/lib/app/app.dart:323-333`), además de `theme`, `darkTheme` y `themeMode` (`apps/mobile/lib/app/app.dart:334-336`).
  - Hay ViewModels con patrón cache-first/SWR: `DashboardViewModel` separa `isLoading`, `isRefreshing` y datos visibles (`apps/mobile/lib/ui/features/dashboard/view_models/dashboard_view_model.dart:32-64`); `MealTemplatesViewModel` hace algo similar (`apps/mobile/lib/ui/features/meal_templates/view_models/meal_templates_view_model.dart:29-70`).

- Fixed:
  - Nada. La tarea era READ-ONLY; no modifiqué `progress.md` ni escribí `review2/flutter-ui-i18n-a11y.md` por conflicto con “No modifiques ningún fichero”.
  - `plan.md` no existe en `/home/antonio/code/cal-tracker/plan.md`; sí leí `progress.md`.

- Blocker:
  - Ningún blocker funcional verificado, pero sí hay deuda P1 antes de considerar la UI lista para i18n/accesibilidad consistente.

- Note — hallazgos priorizados:

  1. **P1 — Flujo “Create meal” tiene muchas cadenas hardcodeadas aunque ya existen claves ARB.**  
     `voice_log_screen.dart` usa textos directos para título, tooltips, banners, labels y formularios: `Create meal`, `Back`, `Start over`, `Transcribing...` (`apps/mobile/lib/ui/features/voice_log/views/voice_log_screen.dart:57-87`), error/retry/logged (`:1567-1592`), métricas (`:1609-1627`, `:1732-1749`), meal label sheet (`:1816-1882`) y editor de ingredientes (`:2039-2085`, `:2220-2251`).  
     Esto es especialmente claro porque las claves ya existen en ARB: `voiceTitle`, `voiceStartOver`, `voiceTranscribingTitle`, `voiceErrorTitle`, `mealLabelQuestion`, `mealLabelCustomType`, `mealProposalConfirm`, etc. (`apps/mobile/lib/l10n/app_en.arb:683-767`). Además, los chips usan `label.label` en vez de `localizedMealLabel(...)` (`voice_log_screen.dart:1830-1834`; helper disponible en `apps/mobile/lib/l10n/meal_label_localizations.dart:4-14`).  
     **Refactor recomendado:** pasar todo el flujo a `context.l10n`, usar `localizedMealLabel`, y añadir widget tests con locale `es`.

  2. **P1 — Pantallas monolíticas y componentes duplicados.**  
     Hay ficheros demasiado grandes: `voice_log_screen.dart` tiene 2590 líneas y 42 clases; `calorie_target_sheet.dart` 2295 líneas y 26 clases; `agent_chat_screen.dart` 1254 líneas y 27 clases.  
     Además, `voice_log_screen.dart` reimplementa piezas ya compartidas: `_EditableIngredientRow` (`apps/mobile/lib/ui/features/voice_log/views/voice_log_screen.dart:2167-2255`) y `_InlineReplacementFoodSearch` (`:2372-2430`) duplican patrones existentes en `MealItemEditorSheet` y `FoodSearchPanel` (`apps/mobile/lib/ui/shared/meal_item_editor_sheet.dart:12-25`, `:144-190`, `:532-598`).  
     **Refactor recomendado:** extraer `voice_log` en widgets/sections por responsabilidad y adaptar el editor de propuesta para reutilizar `MealItemEditorSheet`/`FoodSearchPanel`.

  3. **P2 — Accesibilidad: controles icon-only y visualizaciones con semántica incompleta.**
     - `FoodSearchPanel` tiene `suffixIcon: IconButton` sin `tooltip`/semantics (`apps/mobile/lib/ui/shared/food_search_panel.dart:86-97`).
     - El botón de enviar en chat es un `FilledButton` con solo icono y sin label/tooltip (`apps/mobile/lib/ui/features/agent_chat/views/agent_chat_screen.dart:1202-1205`).
     - `FreshProgressRing` dibuja progreso con `CustomPaint` sin `Semantics(value/label)` (`apps/mobile/lib/ui/core/design_system.dart:626-647`).
     - Las barras de historial exponen “Select {label}” pero no el porcentaje/calorías visibles (`apps/mobile/lib/ui/features/meal_history/views/meal_history_screen.dart:294-319`).  
     **Refactor recomendado:** exigir tooltip/semanticLabel en componentes icon-only, envolver gráficos en `Semantics`, y añadir tests de semantics para botones principales.

  4. **P2 — Estados error/empty pueden inducir datos falsos cuando no hay cache.**  
     En dashboard, si falla la carga y `summary == null`, se muestra banner de error pero también tarjetas con defaults: calorías consumidas `0`, target `2200`, remaining calculado (`apps/mobile/lib/ui/features/dashboard/views/dashboard_screen.dart:55-80`, `:255-262`) y agua `0 / 0` (`:687-688`).  
     **Refactor recomendado:** cuando no hay datos visibles, mostrar un estado error dedicado; usar defaults solo para setup explícito, no como estado de fallo.

  5. **P2 — Riesgo responsive/large text en layouts fijos.**
     - `_DailyProgressCard` fija altura `124/136` y combina texto grande + ring en una fila (`apps/mobile/lib/ui/features/dashboard/views/dashboard_screen.dart:263-283`, `:295-344`), lo que puede romper con text scale alto o pantallas estrechas.
     - `_MealLabelSheet` usa `Column(mainAxisSize: min)` con teclado (`viewInsets`) pero sin `SingleChildScrollView`; al mostrar “Other” añade campo y botones (`apps/mobile/lib/ui/features/voice_log/views/voice_log_screen.dart:1798-1883`).  
     **Refactor recomendado:** usar `LayoutBuilder`, `SingleChildScrollView`/`ConstrainedBox`, y widget tests con `textScaleFactor` alto y ancho compacto.

  6. **P3 — Colores ad hoc fuera del sistema de tema.**  
     La tarjeta de agua define colores dark/light locales (`apps/mobile/lib/ui/features/dashboard/views/dashboard_screen.dart:691-708`, `:796-805`) en vez de vivir en `FreshPalette`/tokens.  
     **Refactor recomendado:** mover estos tokens al design system y validar contraste en light/dark.