---
title: iOS App Store Build Pipeline Specification
version: 1.0
date_created: 2026-06-10
last_updated: 2026-06-10
owner: Cal Tracker Engineering
tags: [infrastructure, process, ci, ios, app-store, github-actions]
---

# Introduction

This specification defines the future GitHub Actions pipeline for building the
Cal Tracker Flutter mobile application for iOS App Store distribution. The
pipeline is intentionally deferred until the Apple Developer Program membership
is active and the required Apple credentials are available.

## 1. Purpose & Scope

The purpose of this specification is to preserve the intended iOS build and
signing design without implementing it immediately.

The future implementation shall:

- Build only from the `main` branch.
- Produce a signed App Store-ready `.ipa` artifact.
- Use GitHub-hosted macOS runners.
- Use GitHub CLI commands to inspect and monitor workflow execution.
- Remain independent from the existing backend deployment scripts, including
  `infra/deploy/deploy.sh`.

The future implementation shall not:

- Run on pushes to `develop`.
- Upload automatically to App Store Connect or TestFlight in the first version.
- Require secrets to exist before the Apple Developer Program subscription is
  active.

## 2. Definitions

- **Apple Developer Program**: The paid Apple membership required to create App
  IDs, certificates, provisioning profiles, and App Store Connect API keys.
- **App Store Connect API Key**: Apple-issued key used by CI to authenticate with
  App Store Connect and allow automatic provisioning.
- **Artifact**: A file produced by a GitHub Actions workflow and stored with the
  run, in this case the signed `.ipa`.
- **Bundle ID**: The unique iOS application identifier registered with Apple.
- **CI**: Continuous Integration.
- **IPA**: iOS App Store Package, the archive file uploaded to Apple.
- **Provisioning**: The Apple signing process that associates the application,
  bundle ID, team, certificate, and profile.
- **Workflow dispatch**: Manual workflow execution from the GitHub Actions UI or
  `gh workflow run`.

## 3. Requirements, Constraints & Guidelines

- **REQ-001**: The pipeline shall be implemented as a dedicated GitHub Actions
  workflow at `.github/workflows/ios-appstore-build.yml`.
- **REQ-002**: The workflow shall trigger automatically only on pushes to
  `main`.
- **REQ-003**: The workflow shall support manual execution with
  `workflow_dispatch`, but the job shall run only when `github.ref` is
  `refs/heads/main`.
- **REQ-004**: The workflow shall build the Flutter app with
  `API_BASE_URL=https://api.bettercalories.app`.
- **REQ-005**: The workflow shall produce a signed `.ipa` artifact suitable for
  manual upload to App Store Connect.
- **REQ-006**: The workflow shall upload the `.ipa` with
  `actions/upload-artifact`.
- **REQ-007**: The workflow shall validate Apple credential inputs before the
  expensive build steps and fail with a clear error if credentials are missing.
- **REQ-008**: The workflow shall run `flutter pub get`, `flutter analyze`, and
  `flutter test` before archiving.
- **REQ-009**: The workflow shall compute a monotonically increasing iOS build
  number from GitHub Actions run metadata.
- **REQ-010**: The workflow shall expose enough logs and artifacts for debugging
  failed archive/export steps.
- **REQ-011**: The implementation shall include GitHub CLI verification commands
  in the PR or implementation notes.
- **CON-001**: The current implementation is blocked until Apple Developer
  Program membership is active.
- **CON-002**: The first version shall not upload to App Store Connect or
  TestFlight automatically.
- **CON-003**: Pushes to `develop` shall never trigger the iOS App Store build.
- **CON-004**: The workflow shall not call or depend on `infra/deploy/deploy.sh`.
- **CON-005**: The workflow shall not hardcode Apple private keys,
  certificates, provisioning profile contents, or App Store Connect credentials.
- **CON-006**: iOS signing shall use GitHub Secrets or GitHub environment
  secrets, not committed files.
- **GUD-001**: Use `macos-latest` unless a specific Xcode version issue requires
  pinning a macOS runner image.
- **GUD-002**: Pin Flutter to the repo's known Flutter stable version at the time
  of implementation, currently `3.41.9`.
- **GUD-003**: Prefer automatic signing with App Store Connect API key
  authentication.
- **GUD-004**: Keep the workflow independent from backend CI and backend deploy
  workflows.

## 4. Interfaces & Data Contracts

### 4.1 Git Branch Interface

| Branch | Automatic iOS App Store build |
| --- | --- |
| `main` | Yes |
| `develop` | No |
| Feature branches | No |

If manual execution is supported, the job shall still guard execution with:

```yaml
if: github.ref == 'refs/heads/main'
```

### 4.2 Required GitHub Secrets

The implementation shall define these names and validate them at workflow start.
Values are intentionally not available until the Apple subscription is active.

| Secret name | Purpose |
| --- | --- |
| `APPLE_TEAM_ID` | Apple Developer Team ID used by Xcode signing. |
| `APP_STORE_CONNECT_KEY_ID` | Key ID for the App Store Connect API key. |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID for the App Store Connect API key. |
| `APP_STORE_CONNECT_API_KEY_P8` | Private `.p8` key body for App Store Connect API access. |

### 4.3 iOS Application Identity

| Field | Required value |
| --- | --- |
| Bundle ID | `app.bettercalories` |
| Display name | `BetterCalories` |
| API base URL | `https://api.bettercalories.app` |
| Export type | App Store / App Store Connect |

The Apple Developer account shall contain an App ID matching
`app.bettercalories` before the pipeline can produce a valid signed `.ipa`.

### 4.4 Expected Build Steps

The future workflow shall perform these logical steps:

1. Check out the repository.
2. Install the pinned Flutter SDK.
3. Install Flutter dependencies.
4. Run static analysis and tests.
5. Write the App Store Connect API key to a temporary file outside tracked
   source paths.
6. Build Flutter iOS release artifacts with the production API base URL.
7. Archive with Xcode using automatic signing.
8. Export the archive as an App Store `.ipa`.
9. Upload the `.ipa` and relevant logs as GitHub Actions artifacts.

### 4.5 GitHub CLI Monitoring Interface

The implementation shall document and use these commands during validation:

```bash
gh workflow list
gh workflow run "iOS App Store Build" --ref main
gh run list --workflow "iOS App Store Build" --branch main --limit 1
gh run watch <run-id> --exit-status
gh run view <run-id> --log-failed
```

## 5. Acceptance Criteria

- **AC-001**: Given a push to `develop`, when GitHub Actions evaluates
  workflows, then the iOS App Store build workflow shall not start.
- **AC-002**: Given a push to `main`, when all required Apple secrets are
  configured, then the workflow shall build and upload a signed `.ipa` artifact.
- **AC-003**: Given a manual workflow dispatch from `main`, when all required
  Apple secrets are configured, then the workflow shall build and upload a
  signed `.ipa` artifact.
- **AC-004**: Given a manual workflow dispatch from any branch other than
  `main`, when the job starts, then it shall skip or fail before building.
- **AC-005**: Given missing Apple secrets, when the workflow runs, then it shall
  fail in the preflight step with a clear list of missing secret names.
- **AC-006**: Given the first implementation before Apple secrets exist, when the
  workflow is manually triggered, then the expected result is the intentional
  preflight failure, not a late Xcode signing failure.
- **AC-007**: Given a successful workflow run, when artifacts are inspected, then
  exactly one App Store `.ipa` shall be available as a downloadable artifact.
- **AC-008**: Given a failed Xcode archive or export step, when logs are viewed
  with GitHub CLI, then the failure shall include enough context to diagnose
  signing, provisioning, or build errors.

## 6. Test Automation Strategy

- **Static validation**:
  - Run `git diff --check`.
  - Validate the workflow file syntax through GitHub Actions by pushing or
    dispatching the workflow.
  - Confirm no `develop` trigger exists in the workflow.

- **Flutter validation**:
  - Run `flutter pub get`.
  - Run `flutter analyze`.
  - Run `flutter test`.

- **GitHub Actions validation before Apple subscription**:
  - Trigger the workflow manually from `main`.
  - Confirm it fails at the secret preflight step.
  - Confirm the failure message lists the missing Apple secrets.

- **GitHub Actions validation after Apple subscription**:
  - Configure the required Apple secrets.
  - Trigger the workflow manually from `main`.
  - Confirm the `.ipa` artifact is produced.
  - Download the artifact and verify the archive name and file extension.

- **Regression validation**:
  - Push a harmless change to `develop` and confirm the iOS workflow does not
    run.

## 7. Rationale & Context

GitHub-hosted macOS runners provide the macOS and Xcode environment required for
iOS builds. The local Linux development machine cannot fully validate iOS
archive and App Store export behavior.

The project already has backend CI and deploy workflows. The iOS App Store build
pipeline is a separate release artifact pipeline and shall not reuse the backend
deployment shell script.

The pipeline is intentionally limited to producing a signed `.ipa` artifact.
Automatic upload to App Store Connect or TestFlight is deferred to avoid adding
release automation before the team has Apple account access and before the
manual signing/export path has been proven.

The app shall use `app.bettercalories` as the iOS bundle ID to align the iOS
production identity with Android production identity and the BetterCalories
brand.

## 8. Dependencies & External Integrations

### External Systems

- **EXT-001**: GitHub Actions - Executes the macOS CI pipeline.
- **EXT-002**: App Store Connect - Provides API key authentication and Apple
  signing/provisioning services.
- **EXT-003**: Apple Developer Program - Provides the Team ID, App ID, signing
  capabilities, and provisioning access.

### Third-Party Services

- **SVC-001**: GitHub artifact storage - Stores generated `.ipa` artifacts and
  build logs.

### Infrastructure Dependencies

- **INF-001**: GitHub-hosted macOS runner with Xcode installed.
- **INF-002**: GitHub Secrets or environment secrets for Apple credentials.

### Technology Platform Dependencies

- **PLT-001**: Flutter stable SDK, pinned at implementation time.
- **PLT-002**: Xcode command line tools capable of archiving and exporting App
  Store iOS builds.
- **PLT-003**: CocoaPods or Swift Package Manager support required by Flutter iOS
  plugin dependencies.

### Compliance Dependencies

- **COM-001**: Apple App Store signing and provisioning rules must be satisfied
  before the generated `.ipa` can be uploaded.

## 9. Examples & Edge Cases

### Missing Secrets Preflight

Expected behavior before the Apple subscription is active:

```text
Missing required Apple signing secrets:
- APPLE_TEAM_ID
- APP_STORE_CONNECT_KEY_ID
- APP_STORE_CONNECT_ISSUER_ID
- APP_STORE_CONNECT_API_KEY_P8
```

The workflow shall stop at this point and shall not run Xcode archive/export
commands.

### Manual Dispatch From Non-Main Branch

If a user manually dispatches the workflow from `develop`, the job shall not
produce an iOS artifact. The workflow shall either skip the build job or fail
with a clear branch guard message.

### Apple Subscription Not Active

If the Apple Developer Program is not active, the repository shall keep this
specification only. No App Store signing workflow secrets are required until the
subscription is active.

## 10. Validation Criteria

The future implementation is compliant with this specification when:

- The workflow file exists at `.github/workflows/ios-appstore-build.yml`.
- The workflow cannot run from `develop`.
- The workflow validates all required Apple secret names before building.
- The iOS bundle ID is `app.bettercalories`.
- The iOS display name is `BetterCalories`.
- The production API base URL is passed through `--dart-define`.
- A successful run on `main` uploads a signed `.ipa` artifact.
- GitHub CLI can be used to trigger, watch, and inspect the run.
- No implementation step depends on `infra/deploy/deploy.sh`.

## 11. Related Specifications / Further Reading

- `.github/workflows/backend-ci.yml`
- `.github/workflows/backend-deploy.yml`
- `apps/mobile/ios/Runner.xcodeproj/project.pbxproj`
- `apps/mobile/pubspec.yaml`
- Apple Developer Program documentation
- App Store Connect API documentation
- GitHub Actions macOS runner documentation
