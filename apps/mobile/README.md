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

Production release builds should be signed with a real upload key, not the
debug key.

Create a local keystore and keep it out of git:

```bash
cd apps/mobile/android
keytool -genkeypair -v \
  -keystore upload-keystore.jks \
  -storetype JKS \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias upload
cp key.properties.example key.properties
```

Then edit `apps/mobile/android/key.properties` with the keystore passwords.
`key.properties`, `*.jks`, and `*.keystore` are ignored by git.

For a local-only production test APK without a release key:

```bash
ALLOW_DEBUG_SIGNING=1 bun run mobile:build:prod
```

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

It then publishes the already-built APK through
`scripts/mobile/deploy-server-apks.sh`.

Deployment SSH uses the dedicated `bettercalories-deploy` account and pinned
host keys. Configure the shared deployment secrets and provision the remote
dispatcher as described in
[`docs/trusted-production-deployments.md`](../../docs/trusted-production-deployments.md).
