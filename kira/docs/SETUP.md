# Kira Setup Guide

## Prerequisites

| Requirement | Minimum Version | Notes |
|---|---|---|
| Flutter SDK | 3.16+ | Stable channel |
| Dart SDK | 3.2+ | Included with Flutter |
| Android Studio | 2023.1+ | With Android SDK 34 |
| Xcode | 15.0+ | macOS only; required for iOS builds |
| CocoaPods | 1.14+ | macOS only; `sudo gem install cocoapods` |
| Git | 2.30+ | For cloning and version control |

Verify your environment:

```bash
flutter doctor -v
```

All checks should pass for your target platform(s) before proceeding.

---

## Clone and Setup

```bash
# Clone the repository
git clone <repository-url> kira
cd kira

# Install Flutter dependencies
flutter pub get

# Generate localization files
flutter gen-l10n

# Generate Drift database code
dart run build_runner build --delete-conflicting-outputs

# Verify the project builds
flutter analyze
flutter test
```

### iOS Additional Setup

```bash
cd ios
pod install
cd ..
```

Open `ios/Runner.xcworkspace` in Xcode to configure signing:

1. Select the **Runner** target.
2. Under **Signing & Capabilities**, select your development team.
3. Ensure the bundle identifier matches your provisioning profile.

### Android Additional Setup

Open `android/` in Android Studio and verify:

1. `compileSdkVersion` is set to 34 or higher in `android/app/build.gradle`.
2. `minSdkVersion` is set to 23 (Android 6.0) for Keystore support.
3. Your `local.properties` file points to the correct Android SDK path.

---

## Provider Registration

> **Important:** Provider registration is performed by Kira developers during
> project setup. End users NEVER paste API keys, client IDs, or secrets.
> All authentication is handled in-app via OAuth with PKCE. Users simply tap
> "Connect" and complete the consent flow in their browser.

### Google Cloud Console (Google Drive)

1. Go to [Google Cloud Console](https://console.cloud.google.com/).
2. Create a new project or select the existing Kira project.
3. Navigate to **APIs & Services > Credentials**.
4. Create an **OAuth 2.0 Client ID** for each platform:

   **Android:**
   - Application type: Android
   - Package name: `com.kira.app`
   - SHA-1 certificate fingerprint: obtain from your keystore with
     `keytool -list -v -keystore <keystore-path>`

   **iOS:**
   - Application type: iOS
   - Bundle ID: `com.kira.app`

5. Configure **Redirect URIs:**
   - Android: `com.kira.app:/oauth2redirect`
   - iOS: `com.kira.app:/oauth2redirect`

6. Under **APIs & Services > Library**, enable the **Google Drive API**.

7. Configure the **OAuth consent screen:**
   - App name: Kira
   - Scopes: `https://www.googleapis.com/auth/drive.file`
     (access only to files created by Kira -- not the user's entire Drive)
   - User type: External

8. Store the client IDs in the environment configuration (see below). The
   client secret is NOT used -- PKCE replaces it.

### Dropbox App Console

1. Go to [Dropbox App Console](https://www.dropbox.com/developers/apps).
2. Create a new app:
   - API: Scoped access
   - Access type: App folder (Kira only accesses its own folder)
   - Name: Kira

3. Under **Settings > OAuth 2:**
   - Enable **PKCE** (no client secret required for mobile).
   - Add redirect URI: `com.kira.app://oauth2redirect/dropbox`

4. Under **Permissions**, enable:
   - `files.content.write`
   - `files.content.read`
   - `files.metadata.read`

5. Note the **App Key** (this is the client ID, not a secret).

### Microsoft Azure (OneDrive)

1. Go to [Azure Portal > App Registrations](https://portal.azure.com/#blade/Microsoft_AAD_RegisteredApps).
2. Register a new application:
   - Name: Kira
   - Supported account types: Personal Microsoft accounts + Organizational
   - Redirect URI (Mobile/Desktop):
     - Android: `msauth://com.kira.app/<base64-url-encoded-signature-hash>`
     - iOS: `msauth.com.kira.app://auth`

3. Under **API Permissions**, add:
   - `Files.ReadWrite.AppFolder`
   - `User.Read`
   - `offline_access`

4. Under **Authentication:**
   - Enable "Allow public client flows" (required for PKCE on mobile).
   - Add the platform-specific redirect URIs.

5. Note the **Application (client) ID**.

6. Create MSAL configuration files:
   - Android: `android/app/src/main/res/raw/msal_config.json`
   - iOS: MSAL config in Info.plist (LSApplicationQueriesSchemes)

### Box Developer Console

1. Go to [Box Developer Console](https://app.box.com/developers/console).
2. Create a new app:
   - Authentication method: Standard OAuth 2.0 (User Authentication)
   - App name: Kira

3. Under **Configuration:**
   - Add redirect URI: `com.kira.app://oauth2redirect/box`
   - Application scopes: Read and write all files and folders
   - Enable PKCE.

4. Note the **Client ID**. The client secret is not embedded in the app.

### Intuit Developer Portal (QuickBooks)

1. Go to [Intuit Developer Portal](https://developer.intuit.com/).
2. Create a new app:
   - Platform: QuickBooks Online
   - Scope: Accounting

3. Under **Keys & credentials:**
   - Note the **Client ID**.
   - Configure redirect URI: `com.kira.app://oauth2redirect/quickbooks`

4. Required scopes:
   - `com.intuit.quickbooks.accounting` (read/write expenses)

5. OAuth flow uses PKCE; no client secret is embedded in the mobile app.

---

## Environment Configuration

**No secrets are committed to source control.** All provider credentials are
injected at build time via environment variables or a `.env` file that is
listed in `.gitignore`.

Create a `.env` file in the project root (never committed):

```env
# Google Drive
GOOGLE_CLIENT_ID_ANDROID=<your-android-client-id>.apps.googleusercontent.com
GOOGLE_CLIENT_ID_IOS=<your-ios-client-id>.apps.googleusercontent.com

# Dropbox
DROPBOX_APP_KEY=<your-dropbox-app-key>

# Microsoft / OneDrive
MICROSOFT_CLIENT_ID=<your-azure-app-client-id>

# Box
BOX_CLIENT_ID=<your-box-client-id>

# QuickBooks / Intuit
QUICKBOOKS_CLIENT_ID=<your-intuit-client-id>

# Kira Backend
KIRA_API_BASE_URL=https://api.kira.example.com
KIRA_CLIENT_ID=<your-kira-client-id>
```

These values are read at build time using the `--dart-define-from-file`
flag:

```bash
flutter run --dart-define-from-file=.env
flutter build apk --dart-define-from-file=.env
flutter build ios --dart-define-from-file=.env
```

In CI/CD, set these as pipeline environment variables or secrets.

---

## Build Commands

### Debug

```bash
# Run on connected device / emulator
flutter run --dart-define-from-file=.env
```

### Release -- Android

```bash
# Build release APK
flutter build apk --release --dart-define-from-file=.env

# Build release App Bundle (recommended for Play Store)
flutter build appbundle --release --dart-define-from-file=.env
```

Output: `build/app/outputs/flutter-apk/app-release.apk`
or `build/app/outputs/bundle/release/app-release.aab`

### Release -- iOS

```bash
# Build release IPA
flutter build ios --release --dart-define-from-file=.env

# Archive in Xcode for App Store submission
# Open ios/Runner.xcworkspace, select Product > Archive
```

### Clean Build

```bash
flutter clean
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
```

---

## Running Tests

```bash
# Run all unit and widget tests
flutter test

# Run tests with coverage
flutter test --coverage

# View coverage report (requires lcov)
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html

# Run a specific test file
flutter test test/unit/sync_engine_test.dart

# Run integration tests
flutter test integration_test/
```

---

## Localization

Kira uses Flutter's built-in localization system with ARB (Application Resource
Bundle) files.

### ARB file locations

```
lib/l10n/
  app_en.arb        # English (default)
  app_fr_CA.arb     # French (Canada)
  app_es_US.arb     # Spanish (United States)
```

### Generate localization code

```bash
flutter gen-l10n
```

This generates `lib/gen_l10n/app_localizations.dart` and the per-locale
delegate classes. The generated files are not committed to source control;
they are regenerated on each build.

### Adding a new string

1. Add the key and English value to `app_en.arb`:
   ```json
   {
     "receiptCaptured": "Receipt captured successfully",
     "@receiptCaptured": {
       "description": "Shown after a receipt is captured via the camera"
     }
   }
   ```
2. Add translations to `app_fr_CA.arb` and `app_es_US.arb`.
3. Run `flutter gen-l10n`.
4. Use in code: `AppLocalizations.of(context)!.receiptCaptured`

### Locale-aware formatting

Date, currency, and number formatting are handled by the `intl` package and
respect the active locale:

```dart
// Date formatting
DateFormat.yMd(locale).format(date);

// Currency formatting
NumberFormat.currency(locale: locale, symbol: currencySymbol).format(amount);
```
