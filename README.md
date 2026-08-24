# Mobile CI (Expo / React Native)

Build + release your mobile app (Android AAB/APK, iOS IPA) from **one** manual
workflow. The reusable logic lives here as **composite actions** (same pattern
as this repo's `build-and-push` action) and is consumed cross‑repo at `@main`.

---

## Can I just paste the example and it works?

**Almost — paste it, then do 3 one‑time setups.** The workflow itself is
copy‑paste; it will not *run successfully* until the product repo has repo
access, secrets, and (for store push) Environments. Checklist:

1. **This bundle must be on `main` of `goai-technologies/github-actions-template`.**
   The example pins `@main`, so the actions must be committed and pushed there
   first. (To test before merging, temporarily change the `@main` refs in your
   copied workflow to `@app_builds`.)
2. **Copy** [`examples/mobile-release.yml`](examples/mobile-release.yml) into your
   product repo at `.github/workflows/mobile-release.yml`.
3. **Set `MOBILE_PATH` / `PNPM_FILTER`** at the top of that file (leave both `"."`
   for a single‑app repo; for a monorepo set the app path + pnpm workspace name).
4. **Grant Actions access** (only if this template repo is *private*): in the
   **template** repo → Settings → Actions → General → "Access" → allow
   repositories in the org to use its actions.
5. **Add the secrets** your platforms need (see table below). Missing a
   platform's secrets → that platform is skipped, not failed.
6. **Create Environments** `beta` and `production` with **Required reviewers**
   (only needed when `push_to_stores: true` — this is the approval gate).

Your product also has to be a real Expo/RN app (has `package.json`, and either
Expo config `app.json`/`app.config.*` or committed `android/` + `ios/`).

---

## What runs

```
version → android ∥ ios → GitHub Release → [reviewer gate] → Play + TestFlight
```

One manual run. `push_to_stores: false` stops after the GitHub Release (no gate,
no upload). `push_to_stores: true` (default) pauses the store jobs at the
Environment reviewer gate, then uploads on approval. `APP_BUILD_NUMBER =
github.run_number` throughout the run, so the Play `versionCode` in the AAB
matches what the store job uses.

**Dispatch inputs:** `version` (x.y.z, required) · `platform`
(android|ios|both) · `push_to_stores` (bool) · `android_track`
(internal|production) · `ios_target` (testflight|appstore).

---

## The building blocks (called for you by the example workflow)

Referenced as `goai-technologies/github-actions-template/ci_workflows/mobile_ci/actions/<name>@main`:

| Action | Runner | Purpose |
|---|---|---|
| `actions/setup` | any | Materialize the Fastlane recipe into `MOBILE_PATH`; optional JS (pnpm/bun/npm) + Ruby/Fastlane. |
| `actions/build-android` | ubuntu | Java 17 + Gradle + Expo prebuild + `fastlane android build_android` → uploads `app-*.{apk,aab}`. |
| `actions/build-ios` | macOS | CocoaPods + Expo prebuild + `fastlane ios build_ios` → uploads `app-*.ipa`. Skips cleanly with no signing secrets. |
| `actions/play-upload` | ubuntu | Download AAB + `fastlane android play_upload`. |
| `actions/store-ios-upload` | macOS | Download IPA + `fastlane ios testflight_upload`/`appstore_submit`. |

Secrets are **not** action inputs — they're read from the **calling job's `env:`**
(same convention as `build-and-push`, which reads `env.AWS_ACCOUNT_ID`). The
example workflow already wires every `env:` block; you only add the secret
*values* in repo settings.

---

## Secrets (Settings → Secrets and variables → Actions → Secrets)

All are optional; absent secrets just skip that capability.

**Android**
| Secret | Needed for |
|---|---|
| `ANDROID_PACKAGE_NAME` | Play upload |
| `ANDROID_KEYSTORE_BASE64` | Release signing (absent → debug signing) |
| `ANDROID_KEYSTORE_PASSWORD` | Release signing |
| `ANDROID_KEY_ALIAS` | Release signing |
| `ANDROID_KEY_PASSWORD` | Release signing |
| `PLAY_JSON_BASE64` | Play upload (service‑account JSON, base64) |

**iOS** — the iOS build only runs when `ASC_*` **and** one signing mode are present.
| Secret | Needed for |
|---|---|
| `IOS_BUNDLE_ID`, `IOS_SCHEME` | iOS build |
| `ASC_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64` | iOS build export + upload (App Store Connect API key) |
| *Direct signing:* `IOS_DIST_CERT_P12_BASE64`, `IOS_DIST_CERT_PASSWORD`, `IOS_PROVISION_PROFILE_BASE64`, `IOS_PROVISION_PROFILE_NAME` | Signing (mode A) |
| *or Match signing:* `MATCH_GIT_URL`, `MATCH_PASSWORD`, `MATCH_GIT_BASIC_AUTHORIZATION`, `MATCH_GIT_BRANCH`, `MATCH_DIST_P12_BASE64`, `MATCH_DIST_P12_PASSWORD` | Signing (mode B) |

## Variables (Settings → … → Variables)
| Variable | Purpose |
|---|---|
| `TF_GROUPS` | Optional TestFlight external group names (comma‑separated) |

## Environments (Settings → Environments) — the approval gate
Create both with **Required reviewers**, or store pushes will NOT pause:
- **`beta`** — used for Play `internal` + `TestFlight` (defaults)
- **`production`** — used for Play `production` + App Store

Because the gate lives in *your* product workflow, approval requests go to *your*
repo's reviewers.

---

## Env vars you set in the workflow (not secrets)
At the top of the copied workflow:
- `MOBILE_PATH` — app root (default `"."`; e.g. `artifacts/mobile` in a monorepo)
- `PNPM_FILTER` — pnpm workspace filter (default `"."`; e.g. `@workspace/mobile`)

## Remove any old vendored copy from your product
Delete a local `fastlane/`, `Gemfile`, `resolve_mobile_version.sh`,
`configure_android_signing.sh` under `MOBILE_PATH` — `setup` materializes them.
App‑specific scripts (`eas-*.sh`, `build-*-local.sh`) stay.
