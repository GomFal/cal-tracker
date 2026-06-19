## Review

No pude escribir en `review/flutter-architecture.md` ni actualizar `progress.md` porque la instrucción principal dice “READ-ONLY / No modifiques ningún fichero”; prioricé no editar.

### Correct
- La estructura base está separada en `app/`, `data/`, `domain/`, `ui/` y `local_toolkit/` (`apps/mobile/lib/...`), y `domain/` no importa `data/`, `ui/` ni `generated`.
- El composition root está centralizado en `apps/mobile/lib/app/app.dart:102-170`.
- Hay patrón cache-first en varios ViewModels: `DashboardViewModel.load` lee cache antes de refrescar (`dashboard_view_model.dart:47-71`), lo mismo en history/templates (`meal_history_view_model.dart:54-78`, `meal_templates_view_model.dart:52-80`).
- Existen tests dedicados a cache/stale-while-revalidate/rollback (`apps/mobile/test/data_view_model_cache_test.dart:19-180`).

### Fixed
- Nada: revisión read-only.

### Blocker
- Ningún P0 observado.

### Note

#### P1 — Ownership de cache y estado está dividido entre Repository, ViewModels y pantallas
**Evidencia**
- `NutritionRepository` ya expone cache y refresco con dedupe/cooldown: `cachedDailySummary`, `putCachedDailySummary`, `refreshDailySummary` (`nutrition_repository.dart:193-243`) y cache para templates/usual foods (`nutrition_repository.dart:246-335`).
- El repository también actualiza cache en mutaciones: commit/correct meal (`nutrition_repository.dart:562-582`), goals/hydration (`nutrition_repository.dart:639-679`), templates/usual foods (`nutrition_repository.dart:755-873`).
- Pero los ViewModels vuelven a escribir cache y hacen rollback manual:
  - Dashboard: `putCachedDailySummary` en optimistas/rollback (`dashboard_view_model.dart:87-164`).
  - History: `_persistWeekSummaries` después de edits/deletes (`meal_history_view_model.dart:103-152`).
  - Templates: `putCachedTemplates` en create/update/delete (`meal_templates_view_model.dart:97-225`).
  - Settings: `_persistGoalsToCachedSummary` después de update (`settings_view_model.dart:87-128`).
- Las pantallas coordinan manualmente refrescos de otros ViewModels:
  - Dashboard refresca history/settings (`dashboard_screen.dart:146`, `dashboard_screen.dart:177-180`, `dashboard_screen.dart:214-216`).
  - Settings refresca dashboard/settings/history (`settings_screen.dart:303-313`).
- Los resultados del agente cachean parcialmente (`nutrition_repository.dart:882-909`), pero `AgentRunResult.deleted` existe (`nutrition_repository.dart:543`) y `_cacheAgentResult` no trata deletes.

**Impacto**
- Riesgo alto de datos visibles obsoletos entre tabs/features.
- Cada nueva mutación debe recordar qué otros ViewModels refrescar.
- Duplicación de rollback/cache aumenta el coste de mantenimiento.

**Siguiente acción**
- Mover ownership de cache/mutaciones a repositorios/servicios de dominio con notificaciones o streams por entidad (`DailySummary`, `MealTemplates`, etc.).
- Dejar a los ViewModels suscribirse a estado/cache y eliminar escrituras directas `putCached*` desde UI/ViewModel salvo casos muy controlados.

#### P1 — `NutritionRepository` es un “god repository” y filtra modelos de data hacia UI
**Evidencia**
- Define DTOs/resultados de agente/chat/search en el propio repository (`nutrition_repository.dart:12-140`).
- La clase mezcla cache, health, telemetry, agente texto/audio/streaming, food search, meals, goals, hydration, templates, usual foods y transcripción (`nutrition_repository.dart:142-879`).
- UI importa directamente `data/repositories/nutrition_repository.dart` para tipos como `AgentRunResult` (`app_shell.dart:8`, `app_shell.dart:21-37`).
- Fakes locales/test heredan de la clase concreta y necesitan un API client falso (`local_fakes.dart:132`, `data_view_model_cache_test.dart:234-235`).

**Impacto**
- Cambios pequeños en nutrición/agente/templates fuerzan recompilar/mockear una superficie enorme.
- UI queda acoplada a la capa data.
- Tests y local toolkit dependen de implementación concreta en vez de puertos pequeños.

**Siguiente acción**
- Extraer interfaces/puertos por capacidad: `DailySummaryRepository`, `MealMutationRepository`, `MealTemplateRepository`, `FoodSearchRepository`, `AgentRepository`.
- Mover `AgentRunResult`, `FoodSearchResult`, etc. a `domain/` o a modelos feature-level.

#### P2 — `SettingsViewModel.load` no deduplica cargas como los demás ViewModels
**Evidencia**
- Dashboard/History/Templates tienen `_loadOperation` guard:
  - `dashboard_view_model.dart:39-44`
  - `meal_history_view_model.dart:46-51`
  - `meal_templates_view_model.dart:44-49`
- `SettingsViewModel.load` ejecuta directamente cache + refresh sin guard (`settings_view_model.dart:38-78`).
- Se llama desde preloader (`app.dart:430-435`), init de Settings screen y `_refreshGoalConsumers` (`settings_screen.dart:303-313`).

**Impacto**
- Cargas simultáneas pueden duplicar refreshes y provocar interleavings de estado/loading.
- Patrón inconsistente frente al resto de ViewModels.

**Siguiente acción**
- Añadir `_loadOperation` a `SettingsViewModel` con la misma semántica que Dashboard/History/Templates.

#### P2 — Ownership dudoso de `AudioRecorderService` compartido
**Evidencia**
- Composition crea un único `AudioRecorderService` y lo inyecta en VoiceLog y AgentChat (`app.dart:152-164`, `app.dart:255-265`).
- `VoiceLogViewModel` puede disponer ese servicio (`voice_log_view_model.dart:180-188`, `voice_log_view_model.dart:932-936`).
- `AgentChatViewModel` también lo mantiene (`agent_chat_view_model.dart:60-70`) pero no lo posee.

**Impacto**
- En recomposición/provider epoch o cambios futuros de scope, un ViewModel puede cerrar un servicio compartido que otro ViewModel aún referencia.
- Ownership queda implícito y frágil.

**Siguiente acción**
- Hacer que el composition root sea dueño y dispose del servicio compartido, o que cada VM reciba un servicio propio. Los ViewModels no deberían disponer dependencias inyectadas compartidas.

#### P2 — Rutas hardcodeadas en varios puntos
**Evidencia**
- Router declara rutas string (`router.dart:31-72`, `router.dart:134-144`).
- AppShell repite rutas para global voice (`app_shell.dart:21-37`) y bubble routes (`app_shell.dart:386-388`).
- También hay rutas duplicadas en local toolkit y pantallas.

**Impacto**
- Renombrar una ruta requiere buscar strings manualmente.
- Global voice/local toolkit pueden romperse sin error de compilación.

**Siguiente acción**
- Introducir constantes/named routes centralizadas o typed route helpers usados por router, AppShell, toolkit y pantallas.