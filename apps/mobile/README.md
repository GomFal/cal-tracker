# BetterCalories Mobile

Flutter app for BetterCalories.

## Android Local Builds

The Android app has two product flavors:

- `dev`: package `app.bettercalories.dev`, API `https://dev-api.bettercalories.app`
- `prod`: package `app.bettercalories`, API `https://api.bettercalories.app`

Build distributable APKs locally from the repository root:

```bash
bun run mobile:build:dev
bun run mobile:build:prod
bun run mobile:build:all
```

The scripts write APKs and SHA-256 checksums to:

```text
dist/mobile/android/
```

Before publishing an APK that should trigger the in-app automatic update prompt,
increment `apps/mobile/pubspec.yaml`'s build number (`version: x.y.z+N`). The
updater compares the published `latest.json` `versionCode` with the installed
app; rebuilding or reuploading the same `versionCode` will not prompt users to
update automatically.

To override API URLs for a local build:

```bash
DEV_API_BASE_URL=https://dev-api.bettercalories.app bun run mobile:build:dev
PROD_API_BASE_URL=https://api.bettercalories.app bun run mobile:build:prod
```

## Android Release Signing

Production release builds require the controlled release key and the approved
SHA-256 certificate fingerprint. They cannot fall back to the Android debug
key. Development and local debug builds do not require production material.

Create a local keystore and keep it out of git:

```bash
cd apps/mobile/android
keytool -genkeypair -v \
  -keystore bettercalories-release.jks \
  -storetype PKCS12 \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10000 \
  -alias bettercalories-release
cp key.properties.example key.properties
```

Then edit `apps/mobile/android/key.properties` with the keystore passwords.
`key.properties`, `*.jks`, and `*.keystore` are ignored by git.

Read the certificate fingerprint without exposing the private key, then provide
it when building:

```bash
keytool -list -v \
  -keystore apps/mobile/android/bettercalories-release.jks \
  -alias bettercalories-release
ANDROID_RELEASE_CERT_SHA256=<approved-sha256> bun run mobile:build:prod
```

The build verifies the resulting APK with `apksigner` before copying it into
`dist/`. See
[`docs/trusted-production-apk-signing.md`](../../docs/trusted-production-apk-signing.md)
for CI secrets, offline custody, recovery and rotation.

## Publish APKs To GitHub

Use GitHub Releases for downloadable APKs instead of committing binaries to
the repository.

Prerequisites:

- `gh` installed and authenticated with `gh auth login`
- current commit pushed to `origin`
- clean working tree, unless publishing intentionally with `ALLOW_DIRTY=1`

Publish locally-built APKs from the repository root:

```bash
bun run mobile:release:dev
bun run mobile:release:prod
```

The release script builds the APK first, then creates or updates a GitHub
Release and uploads the `.apk` plus `.sha256`.

Mobile release tags intentionally use the prefix `mobile-...` and must not
start with `v`, because this repository deploys the backend to production from
`v*` tags.

## Deploy APKs To The Server

Server-hosted APKs are built by the manual **Mobile APK Deploy** GitHub Actions
workflow. The workflow generates the Flutter `dart-define` config from these
repository secrets before running the Android build:

- `MOBILE_DEV_API_BASE_URL`
- `MOBILE_DEV_GOOGLE_SERVER_CLIENT_ID`
- `MOBILE_DEV_GOOGLE_ANDROID_CLIENT_ID`
- `MOBILE_PROD_API_BASE_URL`
- `MOBILE_PROD_GOOGLE_SERVER_CLIENT_ID`
- `MOBILE_PROD_GOOGLE_ANDROID_CLIENT_ID`

Production additionally reconstructs its release keystore temporarily from the
protected `production` GitHub environment and verifies the publisher
certificate before upload. Configure the five `ANDROID_RELEASE_*` secrets in
the signing runbook; do not configure them in the `development` environment.

It then publishes the already-built APK through
`scripts/mobile/deploy-server-apks.sh`.

Deployment SSH uses the dedicated `bettercalories-deploy` account and pinned
host keys. Configure the shared deployment secrets and provision the remote
dispatcher as described in
[`docs/trusted-production-deployments.md`](../../docs/trusted-production-deployments.md).
