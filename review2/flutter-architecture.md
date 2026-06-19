## Review

No modifiqué ficheros: la orden READ-ONLY/no modificar entra en conflicto con “Update progress” y “Write findings to…”, así que no escribí `progress.md` ni `review2/flutter-architecture.md`. `plan.md` no existe en el checkout; `progress.md` solo contenía estado genérico.

- Correct:
  - La estructura base separa `data/`, `domain/`, `ui/` y `app/`.
  - Hay DI centralizada en `CalTrackerBootstrap` con repositorios/servicios inyectables (`apps/mobile/lib/app/app.dart:102-185`).
  - El patrón cache-first existe en ViewModels: `DashboardViewModel` lee cache antes de refrescar (`apps/mobile/lib/ui/features/dashboard/view_models/dashboard_view_model.dart:39-64`) y el repositorio deduplica refrescos/cooldown (`apps/mobile/lib/data/repositories/nutrition_repository.dart:215-230`).
  - Hay tests específicos de cache/SWR/rollback (`apps/mobile/test/data_view_model_cache_test.dart:1-120`).

- Fixed:
  - Ninguno; revisión read-only.

- Blocker:
  - P0: No encontré bloqueadores arquitectónicos inmediatos.

- Note:
  - **P1 — Estado/cache de nutrición duplicado entre ViewModels y sincronización manual entre pantallas.**  
    Evidencia: Dashboard hace optimistic update y escribe cache directamente en edición/borrado (`dashboard_view_model.dart:87-113`, `127-154`); History replica lógica equivalente (`meal_history_view_model.dart:103-123`, `134-155`, `200-203`). La UI de Dashboard refresca manualmente otros ViewModels tras cambios (`dashboard_screen.dart:146`, `177-180`, `214-217`), pero History al borrar solo llama a su propio VM (`meal_history_screen.dart:184-185`).  
    Impacto: riesgo de datos stale entre tabs, más lugares que tocar por cada mutación, rollback/cache inconsistentes.  
    Siguiente acción: centralizar mutaciones y propagación de snapshots en una capa de estado/repository coordinada; las pantallas no deberían saber qué otros ViewModels refrescar.

  - **P1 — `NutritionRepository` es un “god repository”.**  
    Evidencia: 1093 líneas; combina cache/user scoping/health/telemetry (`nutrition_repository.dart:142-190`), STT/agent/chat streams (`338-408`), food search telemetry (`410-430`, `1013-1054`), parsing de respuestas agent (`461-560`), meals/goals/templates/usual foods (`562-760`) y merge de cache (`911-978`).  
    Impacto: alto acoplamiento; cualquier feature de nutrición/agent/templates toca el mismo archivo y los tests fingen el repositorio concreto heredándolo (`apps/mobile/test/data_view_model_cache_test.dart:234-235`).  
    Siguiente acción: dividir por bounded contexts (`DailySummaryRepository`, `MealTemplateRepository`, `AgentRepository`, `FoodSearchRepository`) o introducir interfaces de dominio.

  - **P1 — Mensajes de error de UI hardcodeados en inglés y acoplados al API generado.**  
    Evidencia: `user_visible_error.dart` importa `generated/api/cal_tracker_api.dart` (`apps/mobile/lib/ui/core/user_visible_error.dart:6`) y devuelve strings literales (`40-87`, `130-178`); esos textos no aparecen en ARB.  
    Impacto: la app soporta ES/EN, pero muchos errores serán siempre inglés; además UI core depende del tipo concreto `ApiException`.  
    Siguiente acción: devolver error codes/typed failures desde data/domain y mapearlos a `AppLocalizations` en presentación.

  - **P2 — UI/ViewModels dependen de data concreta, no de contratos de dominio.**  
    Evidencia: imports directos a `data/repositories`, `data/services` y `generated/api` desde UI/ViewModels (`app_shell.dart:8`, `voice_log_view_model.dart:6-10`, `usual_food_scan_screen.dart:14`, etc.).  
    Impacto: tests requieren mocks/subclases de clases concretas; cambiar transporte/cache impacta UI.  
    Siguiente acción: mover interfaces a `domain` o feature contracts e inyectar abstracciones.

  - **P2 — Navegación con rutas string duplicadas y mezcla GoRouter/Navigator.**  
    Evidencia: rutas en `router.dart` (`31-72`), duplicadas en `app_shell.dart` (`21-37`, `386-388`, `505-507`) y `main_local.dart` (`171-186`); AgentChat abre pantallas con `MaterialPageRoute` en vez de rutas GoRouter (`agent_chat_screen.dart:178-185`, `677-682`, `770-775`).  
    Impacto: cambios de path pueden romper deep links/toolkit/agent flows; algunas pantallas saltan guards/observadores/nesting uniforme.  
    Siguiente acción: crear una tabla typed de rutas y navegar consistentemente vía GoRouter.

  - **P2 — Utilidades de fecha duplicadas.**  
    Evidencia: formato `yyyy-MM-dd` repetido en Dashboard (`dashboard_view_model.dart:306-309`), History (`meal_history_view_model.dart:233-235`), Settings (`settings_view_model.dart:171-174`) y Repository (`nutrition_repository.dart:980-984`).  
    Impacto: cambios de zona horaria/date-only o formato requieren múltiples ediciones.  
    Siguiente acción: extraer `DateOnly`/formatter compartido en domain/core con tests.