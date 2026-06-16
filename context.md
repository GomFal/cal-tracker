# Resumen de Worktrees — cal-tracker

Fecha del análisis: 2026-06-16

---

## 1. `clean-develop-work` (branch: `agent/clean-develop-work`)

- **Path**: `/home/antonio/code/cal-tracker/.worktrees/clean-develop-work`
- **Último commit**: `ab33008` — 2026-06-11 16:24:52 +0100 — `fix(mobile): resolve Trello UI fixes` (Javier Gómez)
- **Commits ahead de `develop`**: **0** (la rama apunta al mismo HEAD que `develop`)
- **Archivos modificados más recientemente (top 5, excluyendo `android/.gradle`)**:
  - 2026-06-15 22:42 `apps/mobile/lib/l10n/generated/app_localizations.dart`
  - 2026-06-15 22:42 `apps/mobile/lib/l10n/generated/app_localizations_es.dart`
  - 2026-06-15 22:42 `apps/mobile/lib/l10n/generated/app_localizations_en.dart`
  - 2026-06-15 22:41 `apps/mobile/lib/local_toolkit/ui/local_toolkit_overlay.dart`
  - 2026-06-15 22:38 `apps/mobile/lib/main_local.dart`
- **Qué se hizo**:
  1. El commit `ab33008` ya está en `develop` (l10n, `settings_screen`, `voice_log_screen`/`view_model`, nuevo test Patrol `trello_ui_fixes_test.dart`, plan en `docs/trello-jgf-ui-fixes-plan.md`).
  2. El working tree tiene **17 archivos modificados sin commitear** (WIP) que añaden al `LocalToolkitOverlay` las rutas `newUsualMeal` / `editFirstUsualMeal` / `newUsualFood` / `editFirstUsualFood` / `scanUsualFood` y un toggle de "performance overlay", más strings ARB en/es.
- **Estado**: **WIP sin commitear** sobre la base de `develop`. `status` muestra 17 `M` y nada staged. Nada que empujar: la rama no tiene commits divergentes. La actividad del 2026-06-15 22:42 corresponde a las modificaciones sin commitear, no a un commit nuevo.

---

## 2. `ios-appstore-build-spec` (branch: `docs/ios-appstore-build-spec`)

- **Path**: `/home/antonio/code/cal-tracker/.worktrees/ios-appstore-build-spec`
- **Último commit**: `1a83080` — 2026-06-10 20:46:03 +0100 — `docs: add ios app store build pipeline spec` (Antonio Javier Torres Bordón)
- **Commits ahead de `develop`**: **1** (`1a83080`)
- **Archivos modificados más recientemente (top 5)**:
  - 2026-06-10 20:45 `spec/spec-infrastructure-ios-appstore-build-pipeline.md`
  - 2026-06-10 20:43 `tools/usda_import/requirements.txt`
  - 2026-06-10 20:43 `tools/usda_import/import_usda.py`
  - 2026-06-10 20:43 `tools/usda_import/README.md`
  - 2026-06-10 20:43 `tsconfig.base.json`
  *(Los 4 últimos son timestamps de copia del worktree; el único archivo realmente cambiado por el commit es el spec.)*
- **Qué se hizo**: Commit único que añade el spec **`spec/spec-infrastructure-ios-appstore-build-pipeline.md`** (318 líneas, v1.0). Define la futura pipeline de GitHub Actions para construir la app Flutter de iOS firmada para App Store, **intencionalmente diferida** hasta que esté activa la membresía del Apple Developer Program y las credenciales de Apple estén disponibles. Restricciones clave: build sólo desde `main`, runners macOS hospedados, `.ipa` firmado, independiente de `infra/deploy/deploy.sh`.
- **Estado**: **1 commit local sin pushear** (`docs/ios-appstore-build-spec` no aparece como tracking remoto en `git branch -vv` — sólo `+` por estar checked-out en el worktree). Working tree limpio. Listo para review/PR contra `develop`.

---

## 3. `usual-food-scan-photo` (branch: `feature/usual-food-scan-photo`)

- **Path**: `/home/antonio/code/cal-tracker/.worktrees/usual-food-scan-photo`
- **Último commit**: `ad8d524` — 2026-06-08 13:34:36 +0100 — `chore(mobile): bump build to 15 for dev deploy` (Antonio Javier Torres Bordón)
- **Commits ahead de `develop`**: **0** (la rama apunta al mismo HEAD que `develop`)
- **Archivos modificados más recientemente (top 5)**:
  - 2026-06-08 13:34 `apps/mobile/pubspec.yaml`
  - 2026-06-08 13:32 `apps/mobile/test/features/meal_templates/usual_food_scan_e2e_test.dart`
  - 2026-06-08 13:26 `apps/mobile/test/meal_templates_widget_test.dart`
  - 2026-06-08 13:24 `apps/mobile/test/features/meal_templates/usual_food_scan_screen_test.dart`
  - 2026-06-08 13:23 `apps/mobile/test/features/meal_templates/usual_food_scan_view_model_test.dart`
- **Qué se hizo**: La rama ya está **integrada en `develop`**. Los commits relevantes previos (también en `develop`) son `5f0d0e0` "feat: add camera scan for nutrition labels with on-device OCR" (ViewModel + screen + viewfinder overlay, permisos CAMERA / NSCameraUsageDescription, ruta `/templates/ingredients/scan`, 14 unit + 7 widget tests) y `7d37a8c` "feat(scan-photo): preview captured photo + move button into editor form" (pausa del preview tras captura, pantalla de confirmación, botón movido al formulario de nuevo ingrediente, máquina de estados `UsualFoodScanPhase.previewing` con `confirmCapture/retakeCapture/cancel`).
- **Estado**: **Feature ya mergeada a `develop`** (0 commits ahead). Único resto en el worktree: archivo **untracked** `apps/mobile/inline` (2.9 KB, fechado 2026-06-08) — basura dejada tras la integración, conviene limpiar.

---

## Notas generales

- Ninguno de los 3 worktrees tiene commits sin mergear que aún no estén en `develop`: 2 están al día y 1 tiene sólo 1 commit (spec) pendiente de empujar/revisar.
- `clean-develop-work` y `usual-food-scan-photo` son efectivamente "ramas de trabajo ya integradas", la primera con WIP vivo y la segunda con un archivo huérfano.
- `ios-appstore-build-spec` es el único con un commit candidato para PR.
