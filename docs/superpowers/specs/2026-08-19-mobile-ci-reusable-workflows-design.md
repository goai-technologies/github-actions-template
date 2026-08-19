# Mobile CI re-architecture — reusable workflows + shared setup action

- **Date:** 2026-08-19
- **Repo:** `goai-technologies/github-actions-template`
- **Status:** Design approved (revised to 3-file shape) — pending implementation plan
- **Supersedes:** the earlier `@app_builds` copy-then-reference approach for mobile CI
- **Revision:** store push folded into `mobile-release.yml` behind a reviewer gate; the separate
  `mobile-store-upload.yml` is dropped (no promote-without-rebuild requirement).

## 1. Problem

The mobile CI under `ci_workflows/mobile_ci/` is a **copy-paste tree**: three trigger-oriented workflows
(`mobile-ci.yml` PR smoke, `mobile-release.yml`, `mobile-store-upload.yml`) each re-declare the same
toolchain setup, and products consume the pipeline by copying the whole folder into their repo.

The same setup block is duplicated across nearly every build job:

| Block | Duplicated in (jobs) |
|---|---|
| A. JS toolchain + package-manager install | pr-smoke typecheck, pr-smoke android, release android, release ios |
| B. Ruby/Fastlane (`ruby/setup-ruby`, bundler-cache) | release android, release ios, both store-upload jobs |
| C. Android native (setup-java 17 + Gradle cache) | pr-smoke android, release android |
| D. Expo prebuild detect + `expo prebuild` | pr-smoke android, release android, release ios |
| E. Version resolve (`resolve_mobile_version.sh`) | release version, store resolve |
| F. iOS native (CocoaPods cache + `pod install`) | release ios, store ios-upload |
| G. Publish / upload glue | release publish, both store-upload jobs |

The Fastlane recipe (`Fastfile`, `Appfile`, `Matchfile`, `Gemfile`, `scripts/`) is *already* shared — the
duplication lives entirely in the workflow YAML.

## 2. Goals

- Reorganize by **stage/artifact** into **three** reusable workflows (android / ios / release), not by trigger.
- Put the **common code once** in the template; products **reference it from `@main`**.
- Products keep **one thin, manual workflow**: enter a `version`, pick `android | ios | both`, toggle
  `push_to_stores`.
- **Fold store push into the release run** behind a GitHub Environment reviewer gate — one run builds,
  cuts the GitHub Release, then (after approval) ships to TestFlight + Play.
- Preserve every existing safety property (see §9).

## 3. Non-goals

- **No PR / push checks.** All runs are manual (`workflow_dispatch`). The PR smoke test is removed.
- No change to the Fastlane recipe's lanes or signing logic.
- **No promote-without-rebuild.** Shipping is always build-then-ship in a single run. Re-uploading or
  promoting a previously-built release (internal→production weeks later, staged rollout %, App Store
  re-submit) is **out of scope** — the Fastfile lanes stay but no workflow wires them (see §9).

## 4. Locked decisions

1. **Structure A** — reusable workflows + one shared `mobile-setup` composite action.
2. **Manual only**, `workflow_dispatch` with a `version` input, an `android | ios | both` picker, and a
   `push_to_stores` boolean.
3. **Three reusable workflows.** Store push is **folded into `mobile-release.yml`** as separate jobs that
   run *after* build + GitHub Release, each gated by a GitHub Environment reviewer. A run never ships to
   users without human approval.
4. Products reference the template from **`@main`**.

## 5. Template structure (after)

```
.github/workflows/            # reusable workflows — MUST be repo-root for workflow_call
  ├── mobile-android.yml       # build APK + AAB → upload artifact
  ├── mobile-ios.yml           # build IPA → upload artifact
  └── mobile-release.yml       # version → android ∥ ios → GitHub Release → [gate] → TestFlight + Play
mobile-setup/
  └── action.yml               # composite: the shared toolchain block (blocks A + B + D + recipe)
ci_workflows/mobile_ci/        # recipe — kept, unchanged
  ├── fastlane/  (Fastfile, Appfile, Matchfile, metadata/)
  ├── Gemfile
  ├── scripts/  (resolve_mobile_version.sh, configure_android_signing.sh)
  └── .gitignore
docs/superpowers/specs/2026-08-19-mobile-ci-reusable-workflows-design.md   # this file
```

Removed:
- `ci_workflows/mobile_ci/.github/workflows/mobile-ci.yml` (PR smoke).
- `ci_workflows/mobile_ci/.github/workflows/mobile-store-upload.yml` (folded into release).

The nested `ci_workflows/mobile_ci/.github/workflows/mobile-release.yml` is replaced by the root-level
reusable workflow (single source of truth).

> **Naming:** workflows are named by platform (`mobile-android` / `mobile-ios`) to match the Fastfile's
> `android` / `ios` lanes. (User framing was "apk+aab / ipa"; platform names chosen as the convention.)

## 6. Components

### 6.1 `mobile-setup` composite action

Holds the code copy-pasted across every build job today.

- **Steps:** materialize the Fastlane recipe (`fastlane/` + `Gemfile`) from this action's own repo
  checkout into `mobile-path`; JS toolchain (`pnpm/action-setup`, `oven-sh/setup-bun`, `actions/setup-node`)
  + the package-manager install if-chain (pnpm/yarn/bun/npm); Ruby (`ruby/setup-ruby`, `bundler-cache: true`).
- **Inputs:** `mobile-path` (default `.`), `pnpm-filter` (default `.`), `node-version` (default `22`),
  `ruby-version` (default `3.1`).
- **Why a composite:** when referenced as `uses: org/repo/mobile-setup@main`, GitHub auto-checks-out the
  action's repo to `${{ github.action_path }}`, so the recipe travels with it — no manual cross-repo
  checkout in each workflow.
- **Not shared, stays in each build workflow:** Java + Gradle cache (Android only); CocoaPods cache +
  `pod install` (iOS only).

### 6.2 `mobile-android.yml` (reusable, `runs-on: ubuntu-latest`)

checkout → `mobile-setup` → `actions/setup-java@v4` (temurin 17) + Gradle cache →
`expo prebuild --platform android --no-install` → `bundle exec fastlane android build_android` →
`actions/upload-artifact`.
Inputs: `version`, `mobile-path`, `pnpm-filter`, `android-project-dir` (default `android`), `app-variant`.
`secrets: inherit`.

### 6.3 `mobile-ios.yml` (reusable, `runs-on: macos-latest`)

checkout → `mobile-setup` → CocoaPods/DerivedData cache →
`expo prebuild --platform ios --no-install` + `pod install` → `bundle exec fastlane ios build_ios` →
`actions/upload-artifact` (`if-no-files-found: warn`, `if: always()`).
Skips gracefully when iOS signing secrets are absent. Inputs mirror android (minus `android-project-dir`).

### 6.4 `mobile-release.yml` (reusable) — build + Release + gated store push

Inputs: `version`; `platform` (`android | ios | both`, default `both`); `push_to_stores` (bool, default
`true`); `android_track` (`internal | production`, default `internal`); `ios_target`
(`testflight | appstore`, default `testflight`); plus passthrough `mobile-path`, `pnpm-filter`,
`android-project-dir`, `app-variant`. `secrets: inherit`.

Jobs:

- **`version`** — checkout (`fetch-depth: 0` for tags) → `resolve_mobile_version.sh` → outputs `version`, `tag`.
- **`android`** — `if: platform in (android, both)` → `uses: ./.github/workflows/mobile-android.yml`,
  `secrets: inherit`. Uploads apk+aab artifact.
- **`ios`** — `if: platform in (ios, both)` → `uses: ./.github/workflows/mobile-ios.yml`,
  `secrets: inherit`. Uploads ipa artifact.
- **`publish`** — `needs: [version, android, ios]`, `if: always() && (android.result == 'success' ||
  ios.result == 'success')` → download artifacts (`merge-multiple`) → `softprops/action-gh-release@v2`
  (files: `app-*.apk`, `app-*.aab`, `app-*.ipa`, `build-metadata.json`). **No gate.**
- **`store-android`** — `needs: [version, android]`, `if: push_to_stores && android succeeded`,
  `runs-on: ubuntu-latest`, `environment: <gated>` → `download-artifact` (this run's apk/aab) →
  Ruby via `mobile-setup` → `bundle exec fastlane android play_upload track:<android_track>`.
- **`store-ios`** — `needs: [version, ios]`, `if: push_to_stores && ios succeeded`,
  `runs-on: macos-latest`, `environment: <gated>` → `download-artifact` (this run's ipa) →
  `bundle exec fastlane ios testflight_upload` (or `appstore_submit` when `ios_target == appstore`).

**Gate mechanics:** the two `store-*` jobs declare a GitHub **Environment** with required reviewers, so the
run pauses for human approval after build + Release complete. Decline → artifacts + GitHub Release still
exist; nothing ships. Default targets are the safe ones (Play `internal`, `TestFlight`).

**Simplification the fold enables:** build and push are now the **same run**, so `github.run_number`
(→ `APP_BUILD_NUMBER` → Play `versionCode`) is identical across build and push. The old
"read `versionCode` back from `build-metadata.json`" step (only needed because the separate store run had a
*different* run number) is **removed**. Store jobs consume the artifact via `download-artifact`, not
`gh release download`.

**Reuse, not duplication:** build logic lives once per platform; `release` *calls* the android/ios
workflows instead of re-declaring their steps.

## 7. Product-side workflow (the thin caller)

`<product>/.github/workflows/mobile-release.yml` — one manual entry point:

```yaml
name: Mobile Build & Release
on:
  workflow_dispatch:
    inputs:
      version:        { description: "Marketing version (x.y.z)", required: true, default: "1.0.1" }
      platform:       { type: choice, options: [android, ios, both], default: both }
      push_to_stores: { type: boolean, default: true }
      android_track:  { type: choice, options: [internal, production], default: internal }
      ios_target:     { type: choice, options: [testflight, appstore], default: testflight }
concurrency: { group: mobile-release-${{ github.ref }}, cancel-in-progress: true }
permissions: { contents: write }   # release job cuts a GitHub Release
jobs:
  release:
    uses: goai-technologies/github-actions-template/.github/workflows/mobile-release.yml@main
    with:
      version: ${{ inputs.version }}
      platform: ${{ inputs.platform }}
      push_to_stores: ${{ inputs.push_to_stores }}
      android_track: ${{ inputs.android_track }}
      ios_target: ${{ inputs.ios_target }}
      mobile-path: artifacts/mobile        # "." for single-app repos
      pnpm-filter: "@workspace/mobile"      # "." for single-app repos
    secrets: inherit
```

**Semantics:** `push_to_stores: false` → build both platforms + cut the GitHub Release, **skip** the gate
and store jobs entirely (pure build/release). `push_to_stores: true` (default) → same, then pause at the
reviewer gate and, on approval, ship to Play (`android_track`) + iOS (`ios_target`).

Optionally, a product can call `mobile-android.yml` / `mobile-ios.yml` directly for a build-only artifact
run with no Release — but `mobile-release.yml` with `push_to_stores: false` covers the common case.

Products also delete their local copy of the recipe (`artifacts/mobile/fastlane`, `Gemfile`, and the CI
scripts `resolve_mobile_version.sh` + `configure_android_signing.sh`); app-specific scripts
(`eas-*.sh`, `build-*-local.sh`) stay.

## 8. Secrets model

`secrets: inherit` must appear on **every** caller job at **every** hop — `inherit` forwards secrets only
to the *directly* called workflow, it does **not** cascade automatically down a chain (GitHub docs:
"Secrets are only passed to the directly called workflow"). So the product's `release` job uses
`secrets: inherit`, **and** `mobile-release.yml`'s `android` / `ios` jobs must *each also* declare
`secrets: inherit` to forward onward. All `ANDROID_*`, `IOS_*`, `ASC_*`, `MATCH_*`, `PLAY_*` resolve from
the product repo's own Actions secrets. No secret is ever listed by hand.

Data flow (release run): `product → mobile-release.yml → {mobile-android.yml, mobile-ios.yml}`, and each
build workflow uses the `mobile-setup` **composite action** internally. Composite actions do not count as
workflow-nesting levels, so the reusable-workflow depth is **3** (product caller → release → android/ios).
GitHub's limit is **10 levels** (top-level caller + up to 9 reusable), so depth 3 is comfortably within it. ✅
The `store-*` jobs live *inside* `mobile-release.yml` (not a further nested workflow), so they add no depth.

## 9. Safety invariants

Preserved, unchanged:

- iOS build **skips gracefully** when neither signing mode is configured; Android still ships.
- **CI never creates Apple certs** — DIRECT mode imports a pre-made `.p12` + profile; Match runs readonly.
- Signing material is **base64-secret-only**; `.gitignore` keeps `.p12/.p8/.mobileprovision/.keystore/.jks/
  keystore.properties/play*.json/private_keys/` out of git.
- **Store push never runs without human approval** — the `store-*` jobs sit behind a GitHub Environment
  reviewer gate. `push_to_stores: false` skips them outright. Default targets are Play `internal` +
  `TestFlight`; escalating to `production`/`appstore` still passes through the same gate. **Note:** the
  exact repo whose Environment rules apply cross-repo is an open item — see §12.

Changed by the fold:

- The gate is now a **per-run Environment gate inside `mobile-release.yml`**, not a separate manual
  `mobile-store-upload.yml`.
- Play `versionCode` comes directly from the build run's `APP_BUILD_NUMBER` (same run), so the
  `build-metadata.json` readback is no longer needed.
- ⚠️ **Dropped capability (by decision §3):** promote/upload a *previously-built* release without
  rebuilding, staged rollout %, and internal→production promotion are not wired by any workflow. The
  Fastfile lanes (`play_promote`, `appstore_submit`, `play_upload` rollout) remain and are harmless; if
  promotion is needed later, re-add a thin `mobile-store-upload.yml` caller — the recipe already supports it.

## 10. `@main` migration

Products pin `@main`, so all of the following must land on `main` of `github-actions-template`:
the 3 root reusable workflows, the `mobile-setup` action, and the `ci_workflows/mobile_ci/` recipe
(currently on `app_builds`). Plan: implement + validate on a work branch, then merge to `main`.
Until merged, a product may temporarily pin the work branch to test.

## 11. Verification

- Static: `actionlint` over all workflows + the composite.
- Functional: a manual `workflow_dispatch` run from a product repo (pinned to the work branch):
  - `push_to_stores: false` for each `platform` (`android`, `ios`, `both`) — confirm artifacts + GitHub
    Release, and that the run does **not** prompt for approval or touch stores.
  - `push_to_stores: true` — confirm the run **pauses at the reviewer gate** after the Release, and on
    approval ships to Play `internal` + TestFlight with a `versionCode` matching the built AAB.
  Reusable workflows cannot be fully exercised locally; the dispatch run is the real proof.

## 12. Risks / open items

- **Cross-repo reusable-workflow access** must be allowed for the org's private repos
  (Settings → Actions → "Access") so a product can call `github-actions-template`.
- **⚠️ Environment gate cross-repo — MUST verify (linchpin of the gated-push safety property).** When a
  reusable workflow in the *template* repo declares `environment:` on its `store-*` jobs but is called from
  a *product* repo, GitHub's docs do **not** explicitly state which repository's required-reviewer
  protection rules apply. Two possibilities: (a) the product (caller) repo's Environment enforces the gate
  — the intended design; or (b) the environment resolves in the template repo, which would misplace the
  gate. The implementation's first gated dispatch run (§11, `push_to_stores: true`) is the authoritative
  test: confirm the run pauses for approval using the product repo's reviewers. Document the required
  Environment name and the repo it must live in once verified. If (b) turns out true, fall back to putting
  the gate on the **product-side thin caller's** store step instead of inside the reusable workflow.
- **`mobile-setup` recipe path**: the action resolves the recipe via
  `${{ github.action_path }}/../ci_workflows/mobile_ci`; confirm this relative path once the action sits at
  repo root.
- **`app-variant` / env passthrough**: verify all env the Fastfile reads (`APP_VARIANT`,
  `ANDROID_PROJECT_DIR`, `APP_BUILD_NUMBER`) is threaded through the workflow inputs.
- **iOS store job on `macos-latest`** needs Ruby/Fastlane; ensure `mobile-setup` (or a minimal Ruby step)
  runs there before `testflight_upload`.
