# End-to-End Mobile CI/CD Template Guide (`ci_workflows/`)

This directory contains a **production-ready, generalized mobile CI/CD pipeline template** for **Android** and **iOS** using **GitHub Actions** and **Fastlane**.

It supports **Expo**, **React Native CLI**, **Flutter**, and **Native iOS/Android** apps, with universal package manager support (**`pnpm`**, **`yarn`**, **`bun`**, and **`npm`**).

---

## 📁 Clean Execution Template Structure

All documentation has been consolidated into this single master guide. The template contains **only** executable code, workflows, and Fastlane scripts:

```
ci_workflows/
├── README.md                                # Single master end-to-end guide (this file)
└── mobile_ci/                               # Ready-to-copy execution tree
    ├── .github/workflows/
    │   ├── mobile-ci.yml                    # PR Smoke test (Typecheck, lint, test, Android APK/AAB)
    │   ├── mobile-release.yml               # Production build (Android APK/AAB + iOS IPA -> GitHub Release)
    │   └── mobile-store-upload.yml          # Store upload (Play Console Internal/Prod + TestFlight/App Store)
    ├── fastlane/
    │   ├── Appfile                          # Fastlane Apple ID & Package Name configuration
    │   ├── Fastfile                         # Master Fastlane build & upload lanes
    │   ├── Matchfile                        # Fastlane Match certificates git repo configuration
    │   └── metadata/                        # Release notes & store changelog templates
    ├── scripts/
    │   ├── configure_android_signing.sh     # Materializes Android release.keystore & properties from secret
    │   └── resolve_mobile_version.sh        # Resolves semver version and git tags (vX.Y.Z)
    ├── Gemfile                              # Ruby dependencies (fastlane, cocoapods)
    └── .gitignore                           # Git ignore rules for build outputs & temporary keys
```

---

## 🚀 End-to-End Setup & Quickstart

### Step 1: Copy Template to App Repository
Copy the contents of `ci_workflows/mobile_ci/` into your mobile app repository root (or mobile package root in a monorepo):

```bash
cp -r ci_workflows/mobile_ci/* /path/to/your/app/repo/
cp -r ci_workflows/mobile_ci/.github /path/to/your/app/repo/
cp ci_workflows/mobile_ci/.gitignore /path/to/your/app/repo/
```

### Step 2: Configure Repository Secrets
Go to **GitHub Repo → Settings → Secrets and variables → Actions** and configure the required secrets listed in the [Secrets Reference Matrix](#-secrets-reference-matrix) below.

### Step 3: Configure GitHub Environments (Optional but Recommended)
Under **Settings → Environments**, create two environments:
1. **`beta`**: For automated TestFlight / Google Play Internal track builds.
2. **`production`**: Configure **Required Reviewers** on this environment so production store deployments require human approval before submitting to the App Store or Play Store production track.

---

## 🔑 Secrets Reference Matrix

### 🤖 Android Secrets

| Secret Name | Required | Purpose / Description |
| :--- | :---: | :--- |
| `ANDROID_PACKAGE_NAME` | **Yes** | App ID / Package Name (e.g. `com.company.app`) |
| `ANDROID_KEYSTORE_BASE64` | For Release | Base64-encoded string of `.keystore` / `.jks` release key. *(If missing, CI falls back to debug signing for QA builds)* |
| `ANDROID_KEYSTORE_PASSWORD` | With Keystore | Password for the release keystore. |
| `ANDROID_KEY_ALIAS` | With Keystore | Key alias inside the keystore. |
| `ANDROID_KEY_PASSWORD` | With Keystore | Password for the specific key alias. |
| `PLAY_JSON_BASE64` | For Upload | Base64-encoded Google Play Console Service Account JSON key (for uploading to Play Store). |

### 🍎 iOS Secrets

| Secret Name | Required | Purpose / Description |
| :--- | :---: | :--- |
| `IOS_BUNDLE_ID` | **Yes** | App Bundle Identifier (e.g. `com.company.app`) |
| `IOS_SCHEME` | Optional | Xcode scheme name (e.g. `App`). Auto-detected from `.xcodeproj` if omitted. |
| `ASC_TEAM_ID` | **Yes** | Apple Developer Team ID (10-character alphanumeric ID). |
| `ASC_KEY_ID` | **Yes** | App Store Connect API Key ID. |
| `ASC_ISSUER_ID` | **Yes** | App Store Connect Issuer ID (UUID). |
| `ASC_KEY_P8_BASE64` | **Yes** | Base64-encoded content of the App Store Connect `.p8` API key file. |

#### iOS Code Signing Modes (Choose A or B):

- **Mode A: Direct Signing (Recommended - No external git repo needed)**:
  | Secret Name | Purpose |
  | :--- | :--- |
  | `IOS_DIST_CERT_P12_BASE64` | Base64-encoded `.p12` Distribution Certificate. |
  | `IOS_DIST_CERT_PASSWORD` | Password for the `.p12` file (leave empty string if none). |
  | `IOS_PROVISION_PROFILE_BASE64` | Base64-encoded App Store `.mobileprovision` file. |
  | `IOS_PROVISION_PROFILE_NAME` | Optional override for provisioning profile name in Xcode. |

- **Mode B: Fastlane Match (Legacy)**:
  | Secret Name | Purpose |
  | :--- | :--- |
  | `MATCH_GIT_URL` | Private git repo URL storing encrypted certificates. |
  | `MATCH_PASSWORD` | Passphrase to decrypt Match certificates. |
  | `MATCH_GIT_BASIC_AUTHORIZATION` | Optional HTTPS auth token for certs repo. |

---

## 🔄 Workflow Triggers & Execution Flow

### 1. PR Smoke Test (`mobile-ci.yml`)
- **Trigger**: Opening a Pull Request or pushing to `main` / `master` / `develop`.
- **Actions**:
  - Automatically detects package manager (`pnpm`, `yarn`, `bun`, `npm`) and installs dependencies.
  - Runs typecheck, linting, and tests.
  - Prebuilds Android (if Expo) and compiles unsigned/signed APK & AAB binaries.
  - Attaches build artifacts to the GitHub Actions run.

### 2. Full Production Build & GitHub Release (`mobile-release.yml`)
- **Trigger**: Pushing a version tag `v*` (e.g. `v1.0.0`) or manual `workflow_dispatch`.
- **Actions**:
  - Resolves semantic versioning from tag or workflow input.
  - Runs parallel jobs:
    - **Android** (on `ubuntu-latest`): Builds signed AAB & APK via Gradle + Fastlane.
    - **iOS** (on `macos-latest`): Decodes signing certs, sets up keychain, builds signed IPA via Xcode + Fastlane.
  - Publishes a **GitHub Release** (`v1.0.0`) with `.apk`, `.aab`, `.ipa`, and `build-metadata.json`.

### 3. Store Upload (`mobile-store-upload.yml`)
- **Trigger**: Manual `workflow_dispatch` (selecting platform, version tag, and target track).
- **Actions**:
  - **Play Store Internal / Production**: Uploads prebuilt AAB to Google Play tracks via Fastlane `play_upload` / `play_promote`.
  - **TestFlight / App Store**: Uploads prebuilt IPA to TestFlight or submits to App Store Review via Fastlane `testflight_upload` / `appstore_submit`.
  - Requires human reviewer approval when target environment is `production`.

---

## 🛠 Framework Customization Notes

- **Expo Apps**: Keep your `app.json` / `app.config.js`. Workflows automatically run `npx expo prebuild` before building.
- **React Native CLI / Native Apps**: If native `android/` and `ios/` folders are committed in git, or if `SKIP_PREBUILD: "true"` environment variable is set, prebuilding is automatically skipped.
- **Monorepos**: Set environment variable `PNPM_FILTER="@workspace/mobile"` and `MOBILE_PATH="apps/mobile"` in `.github/workflows/` files.
