# Auditoría AMOLED: meal create, food search, voice y agent chat

## 1. Alcance

Auditoría visual de UI Flutter visible en el rediseño AMOLED, centrada en antipatrónes de tarjetas/contenedores pesados en:

- creación manual/revisión de comida (`/meal/create`, implementada en `apps/mobile/lib/ui/features/voice_log/views/voice_log_screen.dart`);
- búsqueda de alimentos embebida en creación/edición;
- flujos de voz/agente (`/agent`, botón central inferior, resultados de herramientas);
- pantallas/sheets compartidas usadas por esos flujos.

No se implementa nada en este documento. No se tocaron fuentes, tests ni localización.

## 2. Mapa de rutas y accesibilidad

| Pantalla / flujo | Ruta / entrada | Cómo se accede | Confianza |
|---|---|---|---|
| Dashboard | `/dashboard` | Ruta inicial y tab inferior `Home`; `AppShell` branch 0. `apps/mobile/lib/app/router.dart:31`, `:103-110`; nav en `apps/mobile/lib/ui/core/app_shell.dart:221-276`. | Alta |
| Crear comida / food search manual | `/meal/create` | Ruta top-level autenticada; botón “Add meal” en Dashboard vacío; log desde una usual meal; salto directo local toolkit. `router.dart:58-69`; `dashboard_screen.dart:882-889`; `meal_templates_screen.dart:138-144`; `main_local.dart:171-175`. | Alta |
| Crear comida con propuesta/clarificación/autocommit | `/meal/create` | Escenarios local toolkit “proposal ready”, “clarification required”, “auto committed”; seleccionan fixture y navegan. `main_local.dart:219-232`; fixtures en `local_fixture_store.dart:1016-1054`. | Alta |
| Agent chat | `/agent` | Ruta top-level autenticada; botón central inferior abre chat con tap y graba con long-press. `router.dart:51-56`; `app_shell.dart:507-553`. | Alta |
| Agent chat: scan label | ruta interna por `MaterialPageRoute` | Desde botón scan del input bar; abre `UsualFoodScanScreen` y manda OCR como prompt. `agent_chat_screen.dart:130-134`, `:158-166`, `:1136-1141`. | Alta |
| Usual meal/food editors desde agente | `/templates/meals/new`, `/templates/ingredients/new` o `MaterialPageRoute` | Resultados de draft del agente abren editores; rutas declaradas en shell y botones de review usan `Navigator.push`. `router.dart:143-172`; `agent_chat_screen.dart:652-660`, `:724-734`. | Alta |
| Local toolkit | flavor `local`, overlay | Route chip “Log meal” va a `/meal/create`; scenarios cubren proposal/clarification/autocommit. No hay chip directo para `/agent`. `main_local.dart:159-188`, `:219-232`; `local_toolkit_overlay.dart:8-31`. | Alta |
| Meal confirmation | sin ruta encontrada | `MealConfirmationScreen` existe pero no está importada/ruteada fuera de su propio archivo. `meal_confirmation_screen.dart:6-24`; grep no encontró usos. | Alta |

Nota de estructura: no existe directorio `ui/features/meal_create`; el flujo de creación vive en `ui/features/voice_log/views/voice_log_screen.dart` con clase `MealCreateScreen` (`voice_log_screen.dart:18-24`).

## 3. Hallazgos

| Severidad | Archivo / widget | Antipatrón | Evidencia | Dirección sugerida |
|---|---|---|---|---|
| Alta | `apps/mobile/lib/ui/features/voice_log/views/voice_log_screen.dart` / `_ManualFoodSearchPanel` | La búsqueda inicial está dentro de una `FreshCard` completa, con promo del agente, icon chips y divisor; se siente como panel viejo dentro de una pantalla AMOLED que debería ser una lista/sección directa. | `FreshCard` en `voice_log_screen.dart:326-328`; promo y divider `:331-379`; header con icon chip `:380-399`. | Convertir a sección plana: título + input + resultados en filas separadas por reglas; mover CTA del agente a acción textual discreta o chip pequeño sin caja global. |
| Alta | `voice_log_screen.dart` / `_ManualDraftIngredientRow`, `_EditableIngredientRow` | Cada ingrediente editable es otra tarjeta completa con campos, botones, presets y warning, generando tarjetas anidadas en creación/edición. | `FreshCard` manual `:531-535`; propuesta editor `:2155-2159`; presets y botones `:581-621`, `:2218-2257`. | Rediseñar como bloques/rows con separadores, campos compactos y acciones inline; reservar contenedor solo para warning/error real. |
| Alta | `voice_log_screen.dart` / `_ProposalCard` | La propuesta lista para loguear usa `FreshCard` XL, icono prominente, `_MetricBlock` y botón primario ancho; pesa demasiado para el estilo minimal. | `FreshCard(radius: FreshRadii.xl)` `:1872-1874`; icon chip `:1877-1883`; metric block `:1902-1907`; botones `:1918-1934`. | Hacer propuesta como sección principal: título, kcal como texto grande, ingredientes con reglas, confirmar como acción inferior discreta pero clara; editar como texto/icono secundario. |
| Alta | `voice_log_screen.dart` / `_ResolverClarificationCard`, `_CandidateMealLine` | La clarificación de alimentos combina tarjeta padre + filas seleccionables con fondo `surfaceSoft` e icon chips; en listas largas se vuelve un stack de cajas. | `FreshCard` `:762-764`; candidatos Material con fondo `surfaceSoft`/lime `:1348-1356`; icon chip por fila `:1363-1370`. | Mantener legibilidad LLM con lista plana: grupo como encabezado, candidatos como filas con check/radio sutil y regla inferior; búsqueda expandida sin panel extra. |
| Media | `voice_log_screen.dart` / `_VoiceTranscriptCard`, `_ProposalChangeSuccessToast` | Transcript y toast usan tarjetas coloreadas (`limeWash`), aunque son estados auxiliares. | Transcript `FreshCard` `:264-272`; toast `FreshCard` `:698-705`. | Cambiar a texto inline/quote compacto (“Heard: …”) y toast tipo banner mínimo sin borde pesado; usar color solo en texto/ícono. |
| Media | `voice_log_screen.dart` / `_SummaryCard`, `_RemainingCard`, `_MealsCard`, `_NutritionItemsCard`, `_TemplatesCard`, `_MetricBlock` | Resultados informativos del agente/voice usan muchas `FreshCard` y métricas en cajitas coloreadas, duplicando patrones que el Dashboard ya resolvió con secciones y reglas. | Cards `:1565`, `:1605`, `:1637`, `:1662`, `:1689`; `_MetricBlock` container `:2463-2468`. | Consolidar en secciones planas con encabezados uppercase/regla y métricas tipográficas; evitar cajas para cada métrica. |
| Media | `apps/mobile/lib/ui/features/agent_chat/views/agent_chat_screen.dart` / `_AgentWelcomeCard` | Welcome state es una card grande con borde y chips de prompt, compite con la pantalla negra. | Container con color/borde `agent_chat_screen.dart:245-252`; ActionChips `:271-280`. | Convertir a bloque de bienvenida sin borde: icono pequeño, copy y prompts como filas/chips muy sutiles. |
| Alta | `agent_chat_screen.dart` / `_UserBubble`, `_AssistantBubble`, `_ToolCallCard` | Chat conserva burbujas/paneles pesados: usuario en lime sólido, asistente en caja bordeada, tool call en card con resultado embebido. | User lime `:316-324`; assistant surface/borde `:351-360`; tool card `:503-510`; resultado dentro `:547-552`. | Replantear timeline AMOLED: mensajes alineados pero con menos fondo; usuario como texto/acento compacto, asistente casi plano; tools como filas de estado con regla y spinner, no card. |
| Media | `agent_chat_screen.dart` / `_MetricPill`, result widgets | Los resultados dentro tools usan pills coloreadas para kcal/macros; son legibles pero añaden micro-contenedores. | `_NutritionHeader` pills `:908-928`; `_MetricPill` `DecoratedBox` `:959-967`. | Mantener jerarquía pero usar texto tabular + separadores; si hay pills, hacerlas transparentes o solo con regla muy suave. |
| Media | `agent_chat_screen.dart` / `_AgentInputBar` | Barra inferior tiene input filled + tres botones prominentes (`filledTonal`, `FilledButton`), formando una franja de controles pesada. | Bottom container `:1114-1118`; scan/mic filled tonal `:1136-1156`; send filled `:1158-1162`. | Reducir a input lineal y acciones icon-only transparentes/borde fino; send primario solo cuando hay texto. |
| Media | `apps/mobile/lib/ui/shared/food_search_panel.dart` / `FoodSearchPanel` | Panel compartido de búsqueda usa `FreshCard(surfaceSoft)` y cada resultado tiene `ListTile` con `FilledButton`, visible en edición de ingredientes/sheets. | `FreshCard` `food_search_panel.dart:73-77`; ListTile + FilledButton `:112-123`. | Alinear con la búsqueda nueva: input + filas compactas + acción textual; sin card padre. |
| Media | `apps/mobile/lib/ui/shared/meal_item_editor_sheet.dart` / `_MealTotalSummary`, `_IngredientEditorCard` | Sheet de edición desde Dashboard envuelve total e ingredientes en contenedores/paneles; además el sheet usa `palette.surface` en vez de negro puro. | Sheet fondo `:58-60`; total card `:248-255`; ingredient container `:362-367`. | Sheet AMOLED: fondo negro/screen, total como bloque tipográfico, ingredientes como filas editables con divisores. |
| Baja | `apps/mobile/lib/ui/shared/nutrition_edit_sheet.dart` / macro info | El mensaje “calculated from macros” usa una cajita `surfaceSoft`; menor impacto porque es sheet secundario. | DecoratedBox `nutrition_edit_sheet.dart:282-298`. | Convertir a nota inline con icono/texto muted. |
| Baja | `apps/mobile/lib/ui/features/meal_confirmation/views/meal_confirmation_screen.dart` | Pantalla no visible encontrada, pero si se reutiliza conserva `FreshCard` centrada. | `FreshCard` `meal_confirmation_screen.dart:14-24`; sin ruta/uso encontrado. | No priorizar salvo que vuelva a exponerse; si se usa, reemplazar por confirmación plana centrada. |

Patrón base relevante: `FreshColors` ya define AMOLED negro (`screen/appBg = 0xff000000`) y superficies muy oscuras (`surface`, `surfaceSoft`, `surfaceMuted`) en `apps/mobile/lib/ui/core/design_system.dart:8-18`. `FreshCard` siempre pinta `surface` + borde `rule` (`design_system.dart:374-413`), por lo que usarlo como wrapper por defecto contradice el objetivo “no unnecessary cards”.

## 4. Plan de rediseño propuesto

1. **Normalizar el lenguaje visual del flujo `/meal/create`.**
   - Quitar wrappers `FreshCard` de búsqueda manual, transcript, propuesta y resultados simples.
   - Definir patrón local de sección plana: encabezado pequeño, regla sutil, filas left-aligned, acciones secundarias discretas.

2. **Rediseñar food search y editores de ingredientes.**
   - Primero `_ManualFoodSearchPanel` y `_FoodSearchBox` de `voice_log_screen.dart`.
   - Después `_ManualDraftIngredientRow` y `_EditableIngredientRow`.
   - Reutilizar el mismo criterio en `FoodSearchPanel` compartido y `MealItemEditorSheet` para no dejar un estilo viejo al editar desde Dashboard/templates.

3. **Replantear propuesta y clarificaciones.**
   - `_ProposalCard`: convertirla en resumen principal sin card XL; mantener confirmación clara.
   - `_ResolverClarificationCard` / `_FoodCandidateStrip`: usar filas y reglas; preservar estados selected/running/error con iconos pequeños.

4. **Limpiar resultados computacionales/LLM.**
   - En meal create: `_SummaryCard`, `_RemainingCard`, `_MealsCard`, `_NutritionItemsCard`, `_TemplatesCard` como secciones planas.
   - En agent chat: `_ToolCallCard` como item de timeline compacto; resultados con métricas tipográficas.

5. **Afinar agent chat.**
   - Welcome, burbujas y input bar después de que meal create tenga patrones estables.
   - Mantener claridad de chat y de estados de herramienta, pero reducir fondos sólidos y bordes.

6. **Sheets secundarios.**
   - Ajustar `MealItemEditorSheet`, `FoodSearchPanel` y `NutritionEditSheet` para que no reintroduzcan tarjetas pesadas durante edición.

## 5. No objetivos de este pase

- No cambiar lógica de LLM/STT, resolución de alimentos, propuestas, clarificaciones ni repositorios.
- No introducir parsing determinista, hardcodes de ingredientes o atajos de idioma.
- No rediseñar Dashboard completo, History, Templates o Settings fuera de los puntos compartidos que afecten edición/búsqueda de comida.
- No cambiar navegación, auth gates, view models, API, cache ni modelos de dominio.
- No modificar strings/ARB salvo que una implementación posterior cambie textos visibles.
- No perseguir `MealConfirmationScreen` si sigue sin ruta/uso.

## 6. Validación sugerida

Automática:

- `cd apps/mobile && flutter analyze`
- `cd apps/mobile && flutter test test/voice_log_screen_test.dart`
- `cd apps/mobile && flutter test test/agent_chat_test.dart`
- `cd apps/mobile && flutter test test/dashboard_cleanup_widget_test.dart` si se toca `MealItemEditorSheet` desde Dashboard.
- `cd apps/mobile && flutter test test/meal_template_editor_widget_test.dart` si se toca `FoodSearchPanel` compartido/templates.
- `cd apps/mobile && flutter test test/bottom_mic_bubble_widget_test.dart test/bottom_mic_processing_spinner_widget_test.dart test/voice_action_button_test.dart` si se toca botón central/voz.

Manual / toolkit:

- Ejecutar flavor local (`lib/main_local.dart`) y revisar con local toolkit:
  - Route: Log meal (`/meal/create`) estado idle/manual search.
  - Scenarios: Proposal ready, Clarification required, Auto committed meal.
  - Dashboard empty day -> botón “Add meal” -> `/meal/create`.
  - Templates -> log usual meal -> `/meal/create` con `MealCreateInitialItems`.
- Revisar `/agent` desde botón central inferior: welcome, mensajes usuario/asistente, tool running/completed/error, resultados de propuesta/summary/drafts, input bar, scan label.
- Inspección visual AMOLED: fondo negro puro, secciones sin cajas innecesarias, reglas sutiles, controles no sobredimensionados, estados LLM legibles.

## 7. Riesgos y preguntas abiertas

- Eliminar demasiados contenedores puede afectar legibilidad en estados LLM densos (clarificación con muchos candidatos, tool results largos). Requiere probar datos largos.
- Muchas pruebas usan `ValueKey`s de widgets actuales; conservar keys o actualizar tests con intención clara.
- `FreshCard.shadow` existe pero no se usa en `FreshCard`; no basar decisiones en ese flag.
- Hay textos hardcoded en `MealCreateScreen` (`Create meal`, `Back`, `Start over`, varios labels de editor); este pase es visual, pero una implementación amplia podría requerir localización si cambia copy.
- El botón central inferior abre `/agent`, no `/meal/create`; cualquier cambio visual no debe romper long-press para grabar.
- Local toolkit no ofrece route chip directo para `/agent`; la validación manual debe abrirlo con el botón central o ruta directa en dev.
