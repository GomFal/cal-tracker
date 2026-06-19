No modifiqué archivos; por falta de herramienta de escritura, dejo aquí el contenido para `review2/flutter-context-map.md`.

# Mapa READ-ONLY de contexto Flutter (`apps/mobile`)

## Estructura principal

- `apps/mobile/lib/main.dart`: entrypoint normal; inicializa Marionette en debug y monta `CalTrackerBootstrap` (`main.dart:8-16`).
- `apps/mobile/lib/main_test.dart`: entrypoint E2E/Patrol con `ApiConfig(baseUrl: 'http://10.0.2.2:3000')` (`main_test.dart:9-14`).
- `apps/mobile/lib/main_local.dart`: entrypoint local toolkit con fakes y overlay (`main_local.dart:23-32`, `main_local.dart:42-51`).
- `apps/mobile/lib/app/`
  - `app.dart`: composition root, providers, `MaterialApp.router`, preload de datos autenticados.
  - `router.dart`: `go_router` y `StatefulShellRoute`.
  - theme/locale/update/performance ViewModels.
- `apps/mobile/lib/data/`
  - `repositories/`: `AuthRepository`, `NutritionRepository`.
  - `services/`: API config, cache, secure storage, audio recorder, telemetry, metadata, update checks.
- `apps/mobile/lib/domain/models/`: modelos JSON manuales de auth/nutrition/macros/update.
- `apps/mobile/lib/generated/api/cal_tracker_api.dart`: cliente HTTP manual ubicado bajo `generated`.
- `apps/mobile/lib/l10n/`: `app_en.arb`, `app_es.arb`, generated localizations, helpers.
- `apps/mobile/lib/ui/`
  - `core/`: shell, design system, content frame, modal lock, global voice button.
  - `features/`: auth, dashboard, history, templates, settings, voice log, agent chat, scan flow.
  - `shared/`: editores y paneles reutilizables de comida/nutrición.
- `apps/mobile/lib/local_toolkit/`: fakes, fixtures y overlay para desarrollo sin backend.
- `apps/mobile/test/`: unit/widget tests.
- `apps/mobile/patrol_test/`: E2E/device-backed tests.

## Patrones principales

### State management / DI

- Usa `provider` + `ChangeNotifier`, no Riverpod/BLoC.
- `CalTrackerBootstrap` crea un `MultiProvider` centralizado (`app.dart:102-181`) con:
  - servicios: telemetry, metadata, repos, audio, preferences.
  - ViewModels: update, theme, locale, auth, voice, agent chat, dashboard, history, templates, settings.
- Screens consumen ViewModels con `context.watch/read`, por ejemplo dashboard (`dashboard_screen.dart:38-40`) y voice meal (`voice_log_screen.dart:45-46`).
- ViewModels exponen flags separados: `isLoading`, `isRefreshing`, `isSaving`:
  - Dashboard: `isLoading => _isLoading && !hasVisibleData` (`dashboard_view_model.dart:32-36`).
  - History/Templates/Settings repiten el patrón (`meal_history_view_model.dart:39-43`, `meal_templates_view_model.dart:31-34`, `settings_view_model.dart:31-35`).

### Repositorios y caché

- `NutritionRepository` es el repositorio central y mezcla API, parsing, health monitor, cache orchestration y helpers de mutación (`nutrition_repository.dart:142-180`, `nutrition_repository.dart:338-876`, `nutrition_repository.dart:882-980`).
- Cache SWR:
  - `cachedDailySummary`, `refreshDailySummary`, `cachedTemplates`, `refreshTemplates`, `cachedUsualFoods`, `refreshUsualFoods` (`nutrition_repository.dart:193-335`).
  - Deduplicación/cooldown con `_dailySummaryRefreshes`, `_templatesRefresh`, `_usualFoodsRefresh` (`nutrition_repository.dart:163-168`, `nutrition_repository.dart:215-243`, `nutrition_repository.dart:266-335`).
- `NutritionCacheStore` usa `AppPreferencesStorage`, envelope con schema/cachedAt, user scope por base64 de user id, max age 7 días (`nutrition_cache_store.dart:17-27`, `nutrition_cache_store.dart:36-61`, `nutrition_cache_store.dart:89-140`).
- Activación/limpieza de cache por sesión en repositorio (`nutrition_repository.dart:172-181`) y en `app.dart` preloader (`app.dart:395-411`).
- Optimistic updates aparecen en ViewModels:
  - Dashboard edita/delete meals y objetivos (`dashboard_view_model.dart:87-119`, `dashboard_view_model.dart:127-212`).
  - Templates CRUD usual meals/foods (`meal_templates_view_model.dart:97-181`, `meal_templates_view_model.dart:185-372`).
  - Settings goals con rollback (`settings_view_model.dart:80-127`).

### API client

- `CalTrackerApiClient` usa `package:http`, no Dio (`cal_tracker_api.dart:5`, `cal_tracker_api.dart:35-50`).
- Soporta:
  - REST auth/nutrition/templates/usual foods/STT (`cal_tracker_api.dart:67-307`).
  - SSE agent chat texto/audio (`cal_tracker_api.dart:166-183`, `cal_tracker_api.dart:365-393`, `cal_tracker_api.dart:462-516`).
  - multipart upload para STT/voice meal (`cal_tracker_api.dart:307-353`, `cal_tracker_api.dart:396-450`).
  - token refresh en 401 (`cal_tracker_api.dart:630-646`).
  - headers de locale/auth/request id/metadata (`cal_tracker_api.dart:660-685`).
  - JSON decode en isolate si body grande (`cal_tracker_api.dart:788-793`).
- `ApiConfig.fromEnvironment` lee `API_BASE_URL`, default `http://localhost:3000` (`api_config.dart:4-10`).

### Localización

- Config Flutter l10n: `l10n.yaml:1-5`.
- ARB: `lib/l10n/app_en.arb`, `lib/l10n/app_es.arb`.
- `MaterialApp.router` registra delegates y supported locales (`app.dart:323-333`).
- Helper `context.l10n` (`app_localizations_context.dart:5-6`).
- Riesgo: aún hay strings hardcodeados en flows complejos, especialmente voice/local toolkit/audio errors (`voice_log_view_model.dart:676`, `voice_log_view_model.dart:705`, `voice_log_view_model.dart:763`, `audio_recorder_service.dart:99`, `local_fixture_store.dart:1070-1079`).

### Navegación

- `go_router` con redirect auth:
  - initial `/dashboard`.
  - redirect por `AuthViewModel` (`router.dart:28-45`).
- Rutas top-level: `/auth`, `/agent`, `/meal/create`, `/templates/ingredients/scan` (`router.dart:47-77`).
- `StatefulShellRoute` para tabs:
  - `/dashboard`, `/history`, `/templates`, `/settings` (`router.dart:78-196`).
  - Nested templates routes: ingredients/meals new/edit (`router.dart:142-180`).
- `AppShell` implementa responsive side/bottom nav y mantiene branches (`app_shell.dart:40-80`, `app_shell.dart:84-219`).
- Global center voice button enruta a chat/meal/templates según resultado (`app_shell.dart:21-37`, `app_shell.dart:371-496`).

### Native/device integrations

- Voice recording: `record`, `path_provider`, temp files, encoder fallback, min bytes guard (`audio_recorder_service.dart:42-80`, `audio_recorder_service.dart:83-124`, `audio_recorder_service.dart:143-169`).
- Camera/OCR scan: `camera`, `google_mlkit_text_recognition`, `permission_handler`, image crop/prep (`usual_food_scan_screen.dart:6-12`, `usual_food_scan_screen.dart:94-151`, `usual_food_scan_screen.dart:283-391`, `usual_food_scan_screen.dart:863-983`).
- Secure auth tokens: `flutter_secure_storage` (`secure_token_storage.dart:10-40`).
- Google auth: `google_sign_in` via `AuthRepository` (`auth_repository.dart:42-49`).

## Archivos calientes / probables god files

- `lib/ui/features/voice_log/views/voice_log_screen.dart` — ~2587 líneas; mezcla screen, manual food search, clarification UI, candidate swap, proposal editor, meal label sheet, summary cards. Principal god file UI.
- `lib/data/repositories/nutrition_repository.dart` — ~1093 líneas; repositorio, result DTOs, parsing de agent/chat, cache, CRUD, telemetry/cache-failure handling.
- `lib/local_toolkit/data/local_fixture_store.dart` — ~1378 líneas; fixtures, escenarios, store mutable, búsquedas locales, templates/usual foods, macros.
- `lib/generated/api/cal_tracker_api.dart` — ~805 líneas; cliente HTTP manual con REST/SSE/multipart/auth refresh/telemetry.
- `lib/ui/core/app_shell.dart` — ~685 líneas; shell responsive + global voice interaction state machine.
- `lib/ui/core/design_system.dart` — >850 líneas; paleta/theme extension + muchos componentes.
- `lib/ui/features/voice_log/view_models/voice_log_view_model.dart` — ~940 líneas; state machine de voice/agent/proposal/candidate selection.
- `lib/ui/features/meal_templates/views/usual_food_scan_screen.dart` — ~983 líneas; cámara/OCR/crop/UI/VM factory test hook.
- `lib/domain/models/nutrition_models.dart` — >897 líneas; modelos JSON manuales de todo nutrition.
- `lib/local_toolkit/data/local_fakes.dart` — ~535 líneas; repos fake concretos extendiendo repos reales.
- `lib/app/app.dart` — composition root y lifecycle/preload, con lógica de providers y auth cache.

## Convenciones de testing observadas

- `flutter_test_config.dart` hace fatales los hit-test warnings (`test/flutter_test_config.dart:5-7`), así que taps deben usar targets visibles/hit-testables.
- Tests unitarios y widget con `flutter test`; uso de `mocktail` y fakes:
  - cache/SWR/optimistic rollback en `data_view_model_cache_test.dart` (`data_view_model_cache_test.dart:19-68`, `data_view_model_cache_test.dart:107-231`).
  - voice state machine en `voice_log_view_model_test.dart` con mocks de repo/audio (`voice_log_view_model_test.dart:11-34`, `voice_log_view_model_test.dart:109-239`).
- Tests de repository/API/telemetry/localization están dispersos en `apps/mobile/test/*`.
- Patrol reservado para flows nativos/E2E en `apps/mobile/patrol_test/`, incluyendo smoke, meal label, multilingual parsing, dashboard/history/settings.

## Riesgos principales

1. **Complejidad concentrada en voice meal flow**  
   `voice_log_screen.dart` + `voice_log_view_model.dart` + `nutrition_repository.dart` concentran UI, state machine, parsing de agent results, candidate resolution, edición manual y confirmación. Riesgo alto de regresiones cruzadas.

2. **Ownership ambiguo de `AudioRecorderService` compartido**  
   `app.dart` crea un único `AudioRecorderService` y lo inyecta a `VoiceLogViewModel` y `AgentChatViewModel` (`app.dart:152-164`). `VoiceLogViewModel` por defecto considera owned un servicio inyectado si `ownsAudioRecorderService` queda true (`voice_log_view_model.dart:181-188`) y lo disposea (`voice_log_view_model.dart:933-938`), mientras `AgentChatViewModel` no lo disposea (`agent_chat_view_model.dart:63-66`, `agent_chat_view_model.dart:111-113`). Revisar lifecycle/dispose ordering.

3. **Repos concretos en lugar de interfaces**  
   Tests y local toolkit extienden o mockean clases concretas (`local_fakes.dart:38`, `local_fakes.dart:131`, `data_view_model_cache_test.dart:234-235`). Esto acopla fakes a constructores/API client dummy y dificulta modularizar.

4. **Cache consistency duplicada entre repo y ViewModels**  
   El repo actualiza caches en mutaciones (`nutrition_repository.dart:570-582`, `nutrition_repository.dart:767-871`), pero ViewModels también hacen optimistic write-through y rollback. Riesgo de inconsistencias cuando backend devuelve forma parcial o falla una escritura de cache.

5. **API/schema manual vulnerable a drift**  
   `cal_tracker_api.dart` y `nutrition_models.dart` parsean con casts directos; muchas respuestas agent usan formatos alternativos (`nutrition_repository.dart:491-557`, `nutrition_repository.dart:1057-1093`). Cambios backend pueden producir runtime exceptions.

6. **Localización incompleta en lógica/UI profunda**  
   Aunque ARB existe, hay mensajes hardcodeados en ViewModels/widgets/fixtures. Especialmente relevante para flows de comida/voz donde AGENTS.md prohíbe shortcuts/strings frágiles en food understanding.

7. **Native flows difíciles de cubrir sólo con widget tests**  
   Voice, camera/OCR, permissions, Google auth, secure storage y mobile updates requieren capas fakeadas + Patrol selectivo. `usual_food_scan_screen.dart` ya tiene `testViewModelFactory` (`usual_food_scan_screen.dart:981-983`), pero sigue siendo grande y acoplado a plugins.

8. **God files de UI dificultan revisión visual y accesibilidad**  
   `voice_log_screen.dart`, `dashboard_screen.dart`, `design_system.dart`, `app_shell.dart` contienen muchos widgets privados en un solo archivo. Riesgo de duplicación, keys inconsistentes y cambios visuales amplios.

## Zonas que merecen revisión profunda

1. **Voice meal creation / correction**
   - `lib/ui/features/voice_log/view_models/voice_log_view_model.dart`
   - `lib/ui/features/voice_log/views/voice_log_screen.dart`
   - `lib/data/repositories/nutrition_repository.dart`
   - `lib/ui/shared/meal_item_editor_sheet.dart`
   Revisar separación de UI, candidate resolution, mensajes localizados, ownership de audio y tests de edge cases.

2. **Data layer/cache contract**
   - `lib/data/repositories/nutrition_repository.dart`
   - `lib/data/services/nutrition_cache_store.dart`
   - `lib/generated/api/cal_tracker_api.dart`
   Revisar responsabilidades, schema drift, cache invalidation, user scoping y refresh cooldown.

3. **Composition root/lifecycle**
   - `lib/app/app.dart`
   - `lib/ui/features/agent_chat/view_models/agent_chat_view_model.dart`
   - `lib/ui/features/voice_log/view_models/voice_log_view_model.dart`
   Revisar provider disposal, shared services, auth-cache activation/deactivation y preload.

4. **Navigation/global voice routing**
   - `lib/app/router.dart`
   - `lib/ui/core/app_shell.dart`
   Revisar redirect auth, modal lock, branch keep-alive, center voice long-press behavior.

5. **Local toolkit debt**
   - `lib/main_local.dart`
   - `lib/local_toolkit/data/local_fixture_store.dart`
   - `lib/local_toolkit/data/local_fakes.dart`
   Separar fixtures/DSL, evitar que comportamiento fake diverja del backend, documentar límites.

6. **Localization/i18n audit**
   - `lib/l10n/app_en.arb`
   - `lib/l10n/app_es.arb`
   - grep de strings hardcodeados en `ui/features`, `data/services`, `local_toolkit`.
   Priorizar user-facing strings en ViewModels y native errors.

7. **Native scan flow**
   - `lib/ui/features/meal_templates/views/usual_food_scan_screen.dart`
   - `lib/ui/features/meal_templates/view_models/usual_food_scan_view_model.dart`
   Revisar plugin lifecycle, file cleanup, crop/OCR separation, testability.

8. **Domain model/codegen strategy**
   - `lib/domain/models/nutrition_models.dart`
   - `lib/generated/api/cal_tracker_api.dart`
   Evaluar si “generated” es realmente generado; si no, considerar contrato tipado/codegen o tests contractuales más fuertes.