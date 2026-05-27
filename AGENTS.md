# Agent Operations Guide

This file contains environment-specific instructions for coding agents working on the Cal Tracker project.

---

## Food and LLM Flow Engineering Rules

Do not hardcode ingredients, ingredient translations, meal names, meal proposal titles, or natural-language parsing fallbacks. Regex-based intent parsing, deterministic ingredient inference, and language-specific shortcuts are not acceptable in food logging, meal proposal, meal correction, or agent-provider fallback flows. These approaches are not scalable, are brittle across languages and datasets, and do not follow the software engineering principles expected in this project. Food understanding must come from structured LLM/tool output, database-backed resolution, explicit user input, or clarification/error responses.

---

## Branch Workflow

Always do development work on the `develop` branch. Before making code or documentation changes, switch to `develop` and update it from the remote when possible. Use `main` only when explicitly asked to sync, release, or inspect production-aligned history.

---

## Deployed Environment URLs

Current backend API environments:

- Dev: `https://dev-api.bettercalories.app`
- Production: `https://api.bettercalories.app`

Backend deployment rules:

- Dev deploys from pushes to `develop`.
- Production deploys from tags matching `v*`.

When compiling the mobile app against the deployed dev environment, use:

```bash
cd /home/javier/dev/cal-tracker/apps/mobile
flutter build apk --flavor dev --debug --dart-define=API_BASE_URL=https://dev-api.bettercalories.app
```

Use the local emulator URL only for local backend testing:

```bash
flutter build apk --flavor dev --debug --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

---

## Production VPS SSH Access

Production host:

- Host: `bettercalories.app`
- User: `root`
- Verified OS hostname: `ubuntu`

Use this non-mutating smoke test to confirm access:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=10 root@bettercalories.app 'printf "connected as %s on %s\n" "$(whoami)" "$(hostname)"'
```

Expected response:

```text
connected as root on ubuntu
```

If the named private key is available locally, keep it under `~/.ssh/jgf` with private-key permissions and connect explicitly:

```bash
ssh -i ~/.ssh/jgf root@bettercalories.app
```

---

## Flutter Testing and Visual Validation

Use this testing pyramid for mobile work:

1. **Dart unit tests** for pure logic, ViewModels, repositories, parsers, cache behavior, localization helpers, and service wrappers.
2. **Flutter widget tests** as the main validation layer for Flutter UI. Use `flutter test` to cover rendering, state changes, form validation, taps, drags, swipes, navigation, loading/success/empty/error states, disabled/enabled controls, and screen flows that do not require native platform UI.
3. **Golden tests** selectively for stable visual surfaces where regressions are costly, such as complex cards, forms, modals, responsive layouts, and light/dark theme variants.
4. **Semantics/accessibility tests** for important interactive controls, icon-only buttons, tap targets, disabled states, and labels.
5. **Patrol/integration tests** only for the small set of flows that need a real device/emulator, platform plugins, native dialogs, permissions, microphone/recording, OS integrations, external apps, or final release confidence.

For Flutter UI changes, prefer widget tests over Patrol. A new screen, form, modal, navigation path, swipe action, or stateful component should normally add or update `apps/mobile/test/...` coverage with fake repositories or mocked platform services. Do not call the real backend from widget tests, and avoid mocking HTTP in every screen test; prefer injecting a fake repository/ViewModel at the Provider boundary. Mock the generated API client only in repository tests, and mock platform channels/services only for plugin-facing service tests.

Every new Flutter UI feature must update all ARB language files with precise English and Spanish strings and regenerate the localization output before verification.

Widget tests should use stable keys, semantics labels, and visible text. For tap/drag targets that may also exist offstage or underneath another widget, use `.hitTestable()` or `tester.ensureVisible(...)` before the interaction. `apps/mobile/test/flutter_test_config.dart` makes hit-test warnings fatal, so a tap on a covered/offscreen/disabled target should fail the test instead of only logging a warning.

Use **Patrol** for critical device-backed flows only. Good Patrol candidates are app startup smoke, one happy-path auth/backend journey, microphone permission and recording, native permission dialogs, Android AppFunctions/iOS App Intents, deep links, push notifications, platform views, and pre-release smoke tests. Do not add Patrol coverage for Flutter-only UI states that can be exercised with `WidgetTester`.

Use **Marionette MCP** as a development and visual-validation tool for the coding agent. After implementing UI changes, the agent should use Marionette to interact with the running Flutter app, take screenshots, inspect the visible UI, tap/scroll/type where needed, and verify that the implemented changes are visually correct. Marionette is not a replacement for automated tests; it is used to give the agent "eyes and hands" during development so it can detect layout issues, bad spacing, overflow, broken visual states, or screens that do not update correctly after changes.

Expected UI workflow:

```text
implement change
run flutter analyze / flutter test
use Marionette MCP for visual inspection when UI changed
fix visual or interaction issues
add/update widget tests for Flutter-only behavior
add/update Patrol only when native/device behavior is part of the acceptance criteria
```


---

## Android Emulator Initialization

Required local assumptions:

- Android SDK: `/home/javier/Android/Sdk`
- AVD: `cal_tracker_api36`
- Device ID after boot: `emulator-5554`
- KVM must be available at `/dev/kvm`

Use this exact startup sequence for local development and voice-capable testing. Start the emulator as a transient user systemd service so it is not tied to the coding agent command process, but do not give the service an automatic restart policy. If the emulator crashes, inspect the crash instead of masking it with a restart loop.

```bash
export PATH="/home/javier/Android/Sdk/emulator:/home/javier/Android/Sdk/platform-tools:$PATH"

# Stop only Cal Tracker emulator/app services from previous runs.
systemctl --user stop cal-tracker-app-watch.service 2>/dev/null || true
systemctl --user stop cal-tracker-emulator.service 2>/dev/null || true
systemctl --user stop cal-tracker-emulator-test.service 2>/dev/null || true

# Remove stale emulator processes only.
ps aux | awk '/qemu-system/ && !/awk/ {print $2}' | xargs -r kill -9
sleep 2

systemd-run --user --unit=cal-tracker-emulator --collect \
  --working-directory=/home/javier/dev/cal-tracker \
  -E PATH=/home/javier/Android/Sdk/emulator:/home/javier/Android/Sdk/platform-tools:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  -E DISPLAY=:1 \
  -E XAUTHORITY=/run/user/1000/gdm/Xauthority \
  -E XDG_RUNTIME_DIR=/run/user/1000 \
  -E DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  -p StandardOutput=append:/tmp/emulator-systemd.log \
  -p StandardError=append:/tmp/emulator-systemd.log \
  /home/javier/Android/Sdk/emulator/emulator -avd cal_tracker_api36 -no-snapshot -no-snapshot-save -allow-host-audio -no-boot-anim -gpu off -accel on

adb wait-for-device
adb -s emulator-5554 shell 'while [[ $(getprop sys.boot_completed) != 1 ]]; do sleep 1; done; echo Boot completed'
adb -s emulator-5554 shell 'pm list packages -f | grep android | wc -l'
adb -s emulator-5554 shell echo alive
```

Important constraints:

- Always cold boot with `-no-snapshot -no-snapshot-save`; corrupted snapshots have caused missing Android services.
- Do not use `-no-audio` when testing Whisper/STT or microphone flows. `-no-audio` disables emulator audio support.
- Use `-allow-host-audio` for voice testing. Without it, Android Emulator can zero out host microphone input before it reaches the virtual device.
- Use `-gpu off` on Android Emulator 36.5.11 for the `cal_tracker_api36` AVD. This was the stable local path for keeping the emulator alive while running Flutter with hot reload. `-gpu software` and `-gpu swiftshader_indirect` have both led to native emulator graphics crashes or host `RenderThread` segfaults on this machine.
- Do not add `Restart=always` to the emulator service. Repeated `qemu-system-x86_64` `SIGSEGV` failures become a constant restart loop and hide the real crash.
- Do not use an app watchdog service while using `flutter run`; it can fight the Flutter tool. Let `flutter run` own install, launch, logs, hot reload, and hot restart.
- Keep emulator logs in `/tmp/emulator-systemd.log` and inspect the service with `systemctl --user status cal-tracker-emulator.service`.
- Wait for `sys.boot_completed == 1` before `adb install`, `flutter run`, or package-manager checks.
- Do not use broad kill patterns such as `pkill -f bun`; they may kill the backend.

### Emulator Microphone Setup

For Whisper/STT manual testing, the host microphone must be available to the emulator:

1. Start the emulator with the voice-capable command above.
2. Confirm the Linux desktop session allows microphone access for the Android Emulator or its `qemu-system-*` process.
3. After installing the app, grant microphone permission if the runtime prompt is not convenient:

```bash
adb -s emulator-5554 shell pm grant app.bettercalories.dev android.permission.RECORD_AUDIO
```

4. Open the app, tap the microphone control, speak into the host machine microphone, stop recording, and submit the transcript flow.

If the emulator boots but records silence, cold boot again with an explicit Linux audio backend:

```bash
systemd-run --user --unit=cal-tracker-emulator --collect \
  --working-directory=/home/javier/dev/cal-tracker \
  -E PATH=/home/javier/Android/Sdk/emulator:/home/javier/Android/Sdk/platform-tools:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  -E DISPLAY=:1 \
  -E XAUTHORITY=/run/user/1000/gdm/Xauthority \
  -E XDG_RUNTIME_DIR=/run/user/1000 \
  -E DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  -p StandardOutput=append:/tmp/emulator-systemd.log \
  -p StandardError=append:/tmp/emulator-systemd.log \
  /home/javier/Android/Sdk/emulator/emulator -avd cal_tracker_api36 -no-snapshot -no-snapshot-save -allow-host-audio -audio alsa -no-boot-anim -gpu off -accel on
```

Use `-no-audio` only for non-voice tests where microphone input is irrelevant.

### Installing and Running the Flutter App

The Android app uses product flavors. For current development builds, always run the `dev` flavor. Do not use plain `flutter run` or plain `flutter build apk`; unflavored commands can target stale/default packages or fail to find the flavored APK output. The dev flavor installs as package `app.bettercalories.dev` and outputs `app-dev-debug.apk`.

For normal development and any "start the whole system" request, start the emulator using the Android Emulator Initialization section first, verify `sys.boot_completed == 1`, then start the app with the dev-flavor `flutter run` command so hot reload and hot restart stay available:

```bash
cd /home/javier/dev/cal-tracker/apps/mobile
flutter run --flavor dev --debug --dart-define=API_BASE_URL=http://10.0.2.2:3000 -d emulator-5554
```

Keep the `flutter run` process attached. Use these Flutter run keys from that terminal:

```text
r  Hot reload
R  Hot restart
d  Detach from Flutter while leaving the app running
q  Quit the app and Flutter run session
```

### Local Parallel Worktree Flavors

Use one shared Android emulator for parallel worktree development. Do not start a second emulator unless explicitly required; two Android emulators can push this machine into OOM.

Local-only Android flavors are injected from the user Gradle init script at:

```text
/home/javier/.gradle/init.d/cal-tracker-local-flavors.gradle
```

Expected init script body:

```groovy
allprojects { project ->
    project.plugins.withId('com.android.application') {
        if (project.path != ':app') {
            return
        }

        if (!project.rootProject.projectDir.absolutePath.endsWith('/apps/mobile/android')) {
            return
        }

        project.android.productFlavors {
            def local1 = maybeCreate('local1')
            local1.dimension = 'env'
            local1.applicationIdSuffix = '.dev.local1'
            local1.resValue('string', 'app_name', 'local1:BetterCalories')

            def local2 = maybeCreate('local2')
            local2.dimension = 'env'
            local2.applicationIdSuffix = '.dev.local2'
            local2.resValue('string', 'app_name', 'local2:BetterCalories')
        }

        project.android.variantFilter { variant ->
            def isLocal = variant.flavors.any { flavor ->
                flavor.name == 'local1' || flavor.name == 'local2'
            }

            if (isLocal && variant.buildType.name != 'debug') {
                variant.setIgnore(true)
            }
        }
    }
}
```

That script must stay outside the repository. It adds debug-only flavors without changing the tracked `dev` and `prod` flavors:

- `dev`: package `app.bettercalories.dev`, tracked production/dev configuration.
- `prod`: package `app.bettercalories`, tracked production configuration.
- `local1`: package `app.bettercalories.dev.local1`, local debug-only configuration.
- `local2`: package `app.bettercalories.dev.local2`, local debug-only configuration.

Use `local1` and `local2` when two Codex agents or worktrees need to visualize different Flutter app builds on the same running emulator. Example:

```bash
# Worktree A
cd /home/javier/dev/cal-tracker/apps/mobile
flutter run --flavor local1 --debug --dart-define=API_BASE_URL=http://10.0.2.2:3000 -d emulator-5554

# Worktree B
cd /home/javier/dev/cal-tracker-ui-experimenting/apps/mobile
flutter run --flavor local2 --debug --dart-define=API_BASE_URL=http://10.0.2.2:3000 -d emulator-5554
```

For a one-off local APK install:

```bash
cd /home/javier/dev/cal-tracker-ui-experimenting/apps/mobile
flutter build apk --flavor local1 --debug --dart-define=API_BASE_URL=http://10.0.2.2:3000
adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-local1-debug.apk
adb -s emulator-5554 shell am start -n app.bettercalories.dev.local1/com.example.cal_tracker_mobile.MainActivity
```

If a future session cannot resolve `local1` or `local2`, inspect or recreate `/home/javier/.gradle/init.d/cal-tracker-local-flavors.gradle`. Do not add these local flavors to release, deploy, or GitHub release scripts. Google auth flows are not expected to work on the local package IDs unless matching OAuth clients are configured.

Use `flutter build apk` plus `adb install -r` only when you specifically need a one-off APK install without a live Flutter tool session:

```bash
cd /home/javier/dev/cal-tracker/apps/mobile
flutter build apk --flavor dev --debug --dart-define=API_BASE_URL=http://10.0.2.2:3000
adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-dev-debug.apk
adb -s emulator-5554 shell am start -n app.bettercalories.dev/com.example.cal_tracker_mobile.MainActivity
```

### Taking Screenshots

```bash
adb -s emulator-5554 shell screencap -p /data/local/tmp/screen.png
adb -s emulator-5554 pull /data/local/tmp/screen.png /tmp/emulator_screen.png
```

### Troubleshooting

- `offline` in `adb devices`: still booting; wait and retry.
- `Can't find service: package`: Android services are not ready; wait for `sys.boot_completed` or cold boot again.
- Sluggish UI is expected with the stable `-gpu off` emulator path.
- Constant emulator restarts usually mean a native emulator `SIGSEGV` is being masked by a systemd restart policy. Stop the service, remove `Restart=always`, and inspect `/tmp/emulator-systemd.log` plus `journalctl --user -u cal-tracker-emulator.service --no-pager`.
- `adb` not found: export the Android SDK `PATH` shown above.

---

## Backend Startup

### Environment File Location

The backend loads `.env` from **`apps/backend/.env`** (NOT the project root) when using `bun --env-file=.env`.

### Critical: Unset Shell Environment Variables

Bun inherits shell environment variables, which **override** `.env` file values. If the shell has old placeholder values exported, the backend will use those instead of the real keys in `.env`.

```bash
# Always unset these before starting the backend
unset STT_API_KEY OPENROUTER_API_KEY
```

### Start Backend

```bash
cd /home/javier/dev/cal-tracker/apps/backend
bun --env-file=.env src/index.ts
```

### Background Mode

```bash
cd /home/javier/dev/cal-tracker/apps/backend
unset STT_API_KEY OPENROUTER_API_KEY
nohup bun --env-file=.env src/index.ts > /tmp/backend.log 2>&1 &
```

### Verify Health

```bash
curl -s http://localhost:3000/v1/health
# Expected: {"ok":true,"service":"cal-tracker-backend"}
```

---

## PostgreSQL Database

### Local Volume Policy

Always use the original loaded local PostgreSQL volume for development, including from feature worktrees. The canonical Compose project is the original checkout at `/home/javier/dev/cal-tracker`; it owns the loaded database volume named `cal-tracker_cal_tracker_postgres`.

Do not run plain `docker compose up -d postgres` from a feature worktree. Docker Compose derives the project name from the current directory, so starting Postgres from a worktree such as `/home/javier/dev/cal-tracker-voice-meal-proposal-rescue` creates a separate empty volume like `cal-tracker-voice-meal-proposal-rescue_cal_tracker_postgres`, which breaks local food search because the USDA/Open Food data is missing.

From any worktree, start the shared local database through the canonical project:

```bash
docker compose --project-directory /home/javier/dev/cal-tracker \
  -f /home/javier/dev/cal-tracker/docker-compose.yml \
  up -d postgres
```

The backend `DATABASE_URL` can still point to `postgres://cal_tracker:cal_tracker@localhost:5432/cal_tracker`; the important part is that port `5432` is served by the canonical `cal-tracker-postgres-1` container backed by `cal-tracker_cal_tracker_postgres`.

If a worktree-specific Postgres container was started accidentally, stop that container and restart the canonical database. Do not delete Docker volumes unless the user explicitly asks.

### Start (Docker)

```bash
cd /home/javier/dev/cal-tracker
docker compose up -d postgres
```

### Verify

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep cal-tracker-postgres-1
docker volume ls | grep cal-tracker_cal_tracker_postgres
# Should show cal-tracker-postgres-1 as healthy and the loaded cal-tracker_cal_tracker_postgres volume.
```

---

## Full Development Environment Startup

Run these services in separate terminals or detached sessions. For emulator details, use the Android section above.

After every local PostgreSQL start, apply pending migrations before starting the backend, emulator-driven app, or Flutter. Local schema drift has repeatedly caused runtime failures when the backend expected newly migrated columns.

```bash
# Database
docker compose --project-directory /home/javier/dev/cal-tracker \
  -f /home/javier/dev/cal-tracker/docker-compose.yml \
  up -d postgres

# Pending database migrations
cd /home/javier/dev/cal-tracker/apps/backend
unset STT_API_KEY OPENROUTER_API_KEY
bun --env-file=.env run db:migrate

# Backend
cd /home/javier/dev/cal-tracker/apps/backend
unset STT_API_KEY OPENROUTER_API_KEY
bun --env-file=.env src/index.ts

# Emulator
# Follow "Android Emulator Initialization".

# Flutter app with hot reload/hot restart enabled
cd /home/javier/dev/cal-tracker/apps/mobile
flutter run --flavor dev --debug --dart-define=API_BASE_URL=http://10.0.2.2:3000 -d emulator-5554
```

---

## Testing Commands

### Backend Tests

```bash
cd /home/javier/dev/cal-tracker/apps/backend
bun test
```

### Flutter Tests

```bash
cd /home/javier/dev/cal-tracker/apps/mobile
flutter test
```

Use this as the default Flutter validation command for PR-sized work. It runs unit, ViewModel, repository, service, and widget tests without starting an emulator.

For golden updates, run only when the visual baseline intentionally changes:

```bash
cd /home/javier/dev/cal-tracker/apps/mobile
flutter test --update-goldens
```

### Patrol E2E Tests

Patrol is not the default validation layer for every UI change. Run it for native/device-critical flows, release smoke, or when the changed behavior cannot be represented with `WidgetTester`.

Patrol tests and `apps/mobile/lib/main_test.dart` must use `CalTrackerBootstrap(apiConfig: ApiConfig(baseUrl: 'http://10.0.2.2:3000'))` directly. Do not depend on a Patrol `--dart-define` for the backend URL; Patrol also injects its own app/test server ports, and those must never become the API base URL. If a Patrol auth failure shows a URL such as `http://10.0.2.2:<random-port>/v1/auth/...`, the test entrypoint is using the wrong API config.

Before running Patrol, verify the backend is reachable from the host on port 3000 and restart it if needed:

```bash
curl -s http://localhost:3000/v1/health
```

Expected response:

```json
{"ok":true,"service":"cal-tracker-backend"}
```

If the backend is not healthy, start it using the Backend Startup section above. Then run Patrol:

```bash
cd /home/javier/dev/cal-tracker/apps/mobile
export PATH="/home/javier/Android/Sdk/emulator:/home/javier/Android/Sdk/platform-tools:$HOME/.pub-cache/bin:$PATH"
export ANDROID_HOME=/home/javier/Android/Sdk ANDROID_SDK_ROOT=/home/javier/Android/Sdk PATROL_ANALYTICS_ENABLED=false

# Stop stale Patrol/Gradle test runs only. Do not kill the emulator or backend.
ps aux | awk '/patrol test|connectedDebugAndroidTest|test_bundle.dart/ && !/awk/ {print $2}' | xargs -r kill
sleep 2

patrol test --target patrol_test/patrol_smoke_test.dart --device emulator-5554 --no-label
```

If Patrol reports `ClassNotFoundException: androidx.test.services.shellexecutor.ShellMain`, `DELETE_FAILED_INTERNAL_ERROR`, or `Total: 0`, the emulator package manager/test-services state is corrupted. Cold boot the emulator using the Android Emulator Initialization section, then rerun Patrol. Do not keep retrying on the corrupted emulator instance.

### Marionette MCP

```bash
cd /home/javier/dev/cal-tracker/apps/mobile
export PATH="$HOME/.pub-cache/bin:$PATH"
marionette_mcp
```

Run the Flutter app in debug mode first and use the VM Service `ws://.../ws` URI printed by `flutter run` with Marionette's `connect` tool. Use Marionette after UI changes for visual confidence, but keep the durable regression coverage in `flutter test` unless the flow requires Patrol.

### Groq STT Isolation Test

```bash
cd /home/javier/dev/cal-tracker/apps/backend
bun --env-file=.env scripts/test-groq-whisper.ts
```


*Last updated: 2026-05-12*
