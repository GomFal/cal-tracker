# Mapa de contexto READ-ONLY: `apps/mobile`

Auditoría de contexto para deuda técnica. Se inspeccionó código fuente directamente; `graphify query` devolvió contexto demasiado genérico de docs/admin, así que las conclusiones abajo están verificadas contra source. No se modificó código de `apps/mobile`.

## Foto rápida

- App Flutter/Dart con `provider` + `ChangeNotifier`, `go_router`, HTTP manual, cache en `shared_preferences`, tokens en `flutter_secure_storage`, grabación con `record`, cámara/OCR con `camera` + ML Kit. Ver dependencias en `apps/mobile/pubspec.yaml:14-32`.
- Tamaño aproximado: 83 Dart files en `lib`, 47 tests en `test`, 22 Patrol tests, 2 `integration_test`.
- Arquitectura predominante: `app/` compone dependencias y providers; `data/repositories` encapsula API/cache; `domain/models` contiene DTOs/parsers; `ui/features/*/{view_models,views}` concentra pantallas por feature; `ui/shared` y `ui/core` contienen componentes transversales.

## Estructura de carpetas

```text
apps/mobile/
  lib/
    main.dart, main_test.dart, main_local.dart
    app/                  # bootstrap, router, theme, VM globales
    data/repositories/    # AuthRepository, NutritionRepository
    data/services/        # API config, storage, telemetry, audio, update, health
    domain/models/        # modelos/DTOs/parsing de auth/nutrición/macros
    generated/api/        # CalTrackerApiClient + openapi.json
    l10n/                 # ARB en/es + generated + helpers
    local_toolkit/        # fake repos/fixtures/overlay para flavor local
    ui/core/              # shell, design system, errores, overlay, mic global
    ui/features/          # auth, dashboard, history, templates, settings, voice, agent chat
    ui/shared/            # editores y food search compartidos
  test/                   # unit/widget tests con fakes/mocktail
  patrol_test/            # device/backend happy paths y flows nativos
  integration_test/       # legacy/integration smoke
```

## Patrones principales

### Bootstrap, DI y lifecycle

- `CalTrackerBootstrap` crea una composición explícita de dependencias y las publica en un `MultiProvider` (`apps/mobile/lib/app/app.dart:102-183`). Los repositorios/services se inyectan por constructor para tests/local toolkit.
- La composición por defecto instancia `SecureTokenStorage`, `AppPreferencesRepository`, `ClientTelemetryService`, `CalTrackerApiClient`, `AuthRepository`, `NutritionRepository` con `NutritionCacheStore`, y `AudioRecorderService` (`apps/mobile/lib/app/app.dart:221-255`).
- Al autenticar, activa cache por user id; al cerrar sesión resetea VMs y borra cache activa. También precarga dashboard/settings/templates de forma oportunista y evita precargar la semana completa de history por coste (`apps/mobile/lib/app/app.dart:397-435`).
- Entrypoints:
  - `lib/main.dart`: app real, Marionette binding en debug, portrait only.
  - `lib/main_test.dart:9-13`: E2E/Patrol usa `http://10.0.2.2:3000` hardcoded.
  - `lib/main_local.dart:31-50`: flavor local inyecta fakes y overlay; `local_toolkit/data/local_toolkit_data.dart:31-40` crea fixture store + fake repos.

### State management

- Patrón dominante: `ChangeNotifier` + `provider` (`ChangeNotifierProvider`, `context.watch/read`). No Riverpod/BLoC.
- ViewModels exponen flags separados: `isLoading` solo cuando no hay datos visibles; `isRefreshing` para refresh en background; `isSaving` para mutaciones. Ejemplo en `DashboardViewModel` (`apps/mobile/lib/ui/features/dashboard/view_models/dashboard_view_model.dart:12-76`).
- Cache-first/stale-while-revalidate implementado en VMs: hidratan cache, notifican UI, luego refrescan backend (`DashboardViewModel` lines `47-76`; análogos en history/templates/settings).
- Mutaciones CRUD usan optimistic UI + write-through cache + rollback. Ejemplo edición de meal en dashboard (`apps/mobile/lib/ui/features/dashboard/view_models/dashboard_view_model.dart:87-134`).
- Flujos LLM/STT tienen VMs específicos y más estado procedural:
  - `VoiceLogViewModel`: enum de fases y `VoiceLogUiState` grande (`apps/mobile/lib/ui/features/voice_log/view_models/voice_log_view_model.dart:15-89`), start/stop/toggle (`281-305`).
  - `AgentChatViewModel`: stream SSE, typing timer, audio stop/start y active proposal id (`apps/mobile/lib/ui/features/agent_chat/view_models/agent_chat_view_model.dart:97-184`).
  - `UsualFoodScanViewModel`: cámara/OCR inyectados como closures para testabilidad (`apps/mobile/lib/ui/features/meal_templates/view_models/usual_food_scan_view_model.dart:94-146`).

### Repositorios, API client, cache y storage

- `NutritionRepository` es el hub de nutrición/agent/templates/usual foods/summary. Mantiene in-flight dedupe y cooldown de refresh (`apps/mobile/lib/data/repositories/nutrition_repository.dart:142-168`, `215-241`).
- Cache persistente: `NutritionCacheStore` guarda envelopes JSON por usuario en `SharedPreferencesAsync`, con `schemaVersion`, `cachedAt`, TTL de 7 días, y claves `nutrition_cache:v1:<base64-user>:...` (`apps/mobile/lib/data/services/nutrition_cache_store.dart:17-140`).
- Cache write-through/merge ocurre en repository después de resultados agent y CRUD (`apps/mobile/lib/data/repositories/nutrition_repository.dart:882-1008`). Riesgo: mucha lógica de consistencia local centralizada en un archivo grande.
- API client central en `generated/api/cal_tracker_api.dart`; construye headers con `Accept-Language`, bearer token, `X-Request-Id` y metadata (`apps/mobile/lib/generated/api/cal_tracker_api.dart:660-686`). También parsea SSE de agent chat (`464-527`) y hace refresh token en 401 para requests normales/SSE/uploads.
- `AuthRepository` escribe tokens tras register/login/Google y limpia tokens si restore falla (`apps/mobile/lib/data/repositories/auth_repository.dart:20-60`). Tokens reales: `SecureTokenStorage` sobre `FlutterSecureStorage` (`apps/mobile/lib/data/services/secure_token_storage.dart:16-35`). Preferencias y cache usan `SharedPreferencesAsync` (`apps/mobile/lib/data/services/app_preferences_storage.dart:3-25`).
- Telemetry client en memoria: batch size 50, buffer 200, flush cada 30s, best-effort/no throw (`apps/mobile/lib/data/services/client_telemetry_service.dart:86-156`).

### Navegación

- `go_router` con `refreshListenable: AuthViewModel` y redirects auth/session (`apps/mobile/lib/app/router.dart:28-45`).
- Rutas top-level: `/auth`, `/agent`, `/meal/create`, `/templates/ingredients/scan`; shell con tabs `/dashboard`, `/history`, `/templates`, `/settings`; subrutas de templates para usual food/meal new/edit (`apps/mobile/lib/app/router.dart:46-205`).
- `StatefulShellRoute` usa `SlidingBranchContainer`/`PageView` y lock de modal para swipe/nav (`router.dart:78-98`). `AppShell` adapta side nav si ancho >=720 y bottom nav en móvil (`apps/mobile/lib/ui/core/app_shell.dart:40-64`).
- Botón de mic global vive en `AppShell` y acopla UI shell con `AgentChatViewModel`; maneja long-press recording y push a `/agent` (`apps/mobile/lib/ui/core/app_shell.dart:389-560`).

### Localización

- Config Flutter gen-l10n: `apps/mobile/l10n.yaml:1-5`; ARB source `lib/l10n/app_en.arb` y `app_es.arb` tienen 528 keys cada uno.
- App usa `AppLocalizations.delegate` y supported locales en `MaterialApp.router` (`apps/mobile/lib/app/app.dart:324-333`).
- `LocaleViewModel` normaliza tags guardados y soporta bare language fallback (`apps/mobile/lib/app/locale_view_model.dart:8-51`); API usa ese locale para `Accept-Language` vía bootstrap/API client.
- Helper `context.l10n` centraliza lookup (`lib/l10n/app_localizations_context.dart`).
- Riesgo evidente: `ui/core/user_visible_error.dart` contiene mensajes de usuario hardcodeados en inglés (`apps/mobile/lib/ui/core/user_visible_error.dart:116-170`), y también hay strings hardcodeadas en VMs como `AgentChatViewModel` status message (`apps/mobile/lib/ui/features/agent_chat/view_models/agent_chat_view_model.dart:175-180`). Esto bypassa ARB.

### UI/design system

- `ui/core/design_system.dart` es un design system custom con `FreshPalette`, tokens, cards/buttons/helpers; archivo grande (858 LOC).
- `app/theme.dart` construye light/dark `ThemeData` y añade `FreshPalette` como `ThemeExtension`.
- Pantallas pesadas combinan layout, estado local, formularios, bottom sheets y lógica de interacción en un solo archivo (ver hot files abajo).

### Testing y convenciones

- `apps/mobile/test/flutter_test_config.dart:5-7` hace fatales los hit-test warnings; tests deben usar keys estables, `ensureVisible`, `.hitTestable()` cuando aplique.
- `analysis_options.yaml:1-7` usa `flutter_lints` y reglas `prefer_const_constructors`, `prefer_final_fields`, `prefer_final_locals`.
- Hay tests específicos para cache-first/optimistic rollback (`test/data_view_model_cache_test.dart`), repository parsing/telemetry (`nutrition_repository_test.dart`, `nutrition_repository_telemetry_test.dart`), API headers/errors, auth VM, voice VM/screen, local toolkit, widgets de dashboard/history/templates/settings.
- Patrol cubre flows con backend/dispositivo/nativo: auth/navigation, agent multilingual, meal labels, macro wizard, goals/settings, food portions, history edits, etc. El entrypoint Patrol/local E2E no debe depender de `--dart-define` para base URL; `main_test.dart` ya fija `10.0.2.2`.

## Archivos calientes / posibles god files

Mayores archivos no generados en `lib`:

| LOC | Ruta | Por qué merece atención |
|---:|---|---|
| 2590 | `ui/features/voice_log/views/voice_log_screen.dart` | Pantalla muy grande; mezcla UI de propuesta/clarificación/edición/labels/manual items. |
| 2295 | `ui/features/dashboard/views/calorie_target_sheet.dart` | Wizard/form complejo en un sheet; alto riesgo de estado local duplicado. |
| 1378 | `local_toolkit/data/local_fixture_store.dart` | Fake backend/fixtures grandes; puede divergir del backend real. |
| 1254 | `ui/features/agent_chat/views/agent_chat_screen.dart` | Renderiza streaming chat, tool results, navegación a editors, summaries. |
| 1153 | `ui/features/dashboard/views/macro_distribution_sheet.dart` | Config macros compleja; validaciones/UI acopladas. |
| 1093 | `data/repositories/nutrition_repository.dart` | Hub de API parsing, cache consistency, telemetry, health, agent outputs. |
| 1040 | `ui/features/meal_templates/views/meal_template_editor_screen.dart` | Editor grande para usual meals. |
| 1013 | `ui/features/dashboard/views/dashboard_screen.dart` | Dashboard con acciones, refresh, hydration, sheets. |
| 983 | `ui/features/meal_templates/views/usual_food_scan_screen.dart` | Cámara + crop + OCR + lifecycle + UI. |
| 940 | `ui/features/voice_log/view_models/voice_log_view_model.dart` | State machine/manual result handling/telemetry/timers. |
| 912 | `domain/models/nutrition_models.dart` | Muchos DTOs/parsers en un solo archivo; casting JSON manual. |
| 858 | `ui/core/design_system.dart` | Tokens + múltiples componentes en archivo único. |

Generados grandes a excluir de deuda funcional directa salvo proceso de generación: `l10n/generated/app_localizations.dart` 3302 LOC, `app_localizations_en/es.dart` ~1.8k LOC.

## Riesgos principales observados

1. **Centralización excesiva de lógica de dominio/cache en mobile**: `NutritionRepository` parsea outputs heterogéneos del agent, hace merge de summaries/templates/usual foods y registra telemetry. Cambios backend pueden romper parsing/cache en muchos flows.
2. **UI monolítica**: varias pantallas/sheets >1000 LOC dificultan revisión visual, accesibilidad y regresiones de interacción.
3. **Internacionalización incompleta**: algunos errores/status user-facing están fuera de ARB (`user_visible_error.dart`, VMs), aunque la app tiene infraestructura i18n sólida.
4. **Acoplamiento shell ↔ agent chat/voice**: el mic global en `AppShell` lee `AgentChatViewModel` y controla navegación/recording; puede complicar lifecycle, permisos y testing de navegación.
5. **State machines manuales**: voice log, agent chat y scan OCR tienen muchas fases/timers/async paths. Riesgo de race conditions, double submit, missing cleanup, stale state.
6. **API client manual grande bajo `generated/api`**: centraliza auth refresh, SSE, uploads, headers, decode/telemetry. El path sugiere generado, pero tiene bastante lógica custom; revisar ownership/proceso de regeneración antes de tocar.
7. **Parsers JSON con casts directos**: `domain/models/nutrition_models.dart` y repository usan muchos `as Map/List/num`; errores de contrato suelen ser runtime exceptions no modeladas.
8. **Local toolkit/fakes pueden divergir**: útiles para visual dev, pero `local_fixture_store.dart` y `local_fakes.dart` replican comportamiento de backend/repository.
9. **Persistencia en SharedPreferences para payloads grandes**: daily summaries, templates y usual foods se serializan completos; el propio bootstrap comenta riesgo de JSON/cache work en UI isolate para history week (`app.dart:425-429`).
10. **Tests amplios pero costosos de mantener**: buena cobertura de cache/VM/widget/Patrol, pero muchos tests dependen de textos visibles; cambios i18n/UI pueden ser ruidosos.

## Zonas que merecen revisión profunda

1. **`data/repositories/nutrition_repository.dart`**: dividir responsabilidades (API facades, parsers, cache sync, telemetry) y crear contrato typed para agent outputs.
2. **`ui/features/voice_log/*`**: formalizar state machine, separar widgets/result sections, auditar timers/cleanup y errores localizados.
3. **`ui/features/agent_chat/*` + mic global en `ui/core/app_shell.dart`**: revisar coupling con navegación, recording lifecycle, stream error recovery y hardcoded strings.
4. **`ui/features/dashboard/views/calorie_target_sheet.dart` + `macro_distribution_sheet.dart`**: separar wizard/model/validation/rendering; revisar accesibilidad y tests de edge cases.
5. **`ui/features/meal_templates/views/usual_food_scan_screen.dart`**: aislar cámara/crop/OCR adapter de UI; validar lifecycle/permisos y memory/file cleanup en dispositivo real.
6. **`domain/models/nutrition_models.dart`**: agrupar DTOs por subdominio y endurecer parsing contra contratos backend variables.
7. **I18n debt**: mover `user_visible_error.dart` y status strings a ARB; añadir tests ES para errores importantes.
8. **Cache + optimistic updates**: revisar invariantes entre Dashboard/History/Settings/Templates cuando varios VMs editan el mismo summary/templates en paralelo.
9. **`local_toolkit`**: definir qué fixtures son contract tests vs sólo visual fakes; minimizar divergencia con responses reales.
10. **API client ownership**: aclarar si `generated/api/cal_tracker_api.dart` se genera o se mantiene a mano; si se genera, customizaciones actuales son riesgo.

## Checks útiles para una auditoría posterior

- `cd apps/mobile && flutter analyze`
- `cd apps/mobile && flutter test`
- Tests focales para zonas de riesgo: `test/data_view_model_cache_test.dart`, `test/voice_log_view_model_test.dart`, `test/voice_log_screen_test.dart`, `test/agent_chat_test.dart`, `test/features/meal_templates/usual_food_scan_view_model_test.dart`, `test/nutrition_repository_test.dart`.
- Para cambios UI: widget tests primero; Patrol sólo para cámara/audio/backend/device-critical flows. Para inspección visual, usar flavor local + Marionette según AGENTS.md.
