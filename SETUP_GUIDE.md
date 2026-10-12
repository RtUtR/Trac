# FamilyTrack — Flutter Setup & Build Guide

> **Backend Note**: The backend (tables, RLS policies, RPC functions `fetch_locations` and `leave_group`, and the `join_group` Edge Function) is already deployed on Supabase and is not part of this repository.

---

## 1. Required Flutter Version

- **Flutter SDK**: Latest stable (`>= 3.22.0`, Dart SDK `>= 3.4.0 < 4.0.0`)
- **Android**: Android Studio / Android SDK (API 34+, `minSdkVersion 21`)
- **iOS**: Xcode 15+ and CocoaPods (`iOS 14.0+`)

---

## 2. Create `config/env.json` from `config/env.example.json`

The app reads `SUPABASE_URL` and `SUPABASE_ANON_KEY` at compile time via `String.fromEnvironment` in `lib/config/app_config.dart`. Only `config/env.example.json` is committed to version control; `**/config/env.json` is ignored by `.gitignore`.

1. Copy the template file inside `flutter_app/` (or from the repository root):
   ```bash
   cd flutter_app
   cp config/env.example.json config/env.json
   ```
2. Edit `config/env.json` and fill in your Supabase project URL and publishable (`anon`) key:
   ```json
   {
     "SUPABASE_URL": "https://YOUR-PROJECT.supabase.co",
     "SUPABASE_ANON_KEY": "YOUR-PUBLISHABLE-KEY"
   }
   ```
   - Only the publishable (`anon`) key may be placed in `config/env.json`.
   - If `SUPABASE_URL` or `SUPABASE_ANON_KEY` is missing at startup, the app displays a clear **Supabase Configuration Missing** screen rather than crashing silently.

---

## 3. Run and Build Commands

From inside `flutter_app/`:

```bash
cd flutter_app
flutter pub get

# Run on a connected device or emulator:
flutter run --dart-define-from-file=config/env.json

# Build Android APK:
flutter build apk --dart-define-from-file=config/env.json

# Build iOS Release:
flutter build ios --dart-define-from-file=config/env.json
```

### IDE Launch Configurations

- **VS Code (`.vscode/launch.json`)**: Included at `flutter_app/.vscode/launch.json` with `"toolArgs": ["--dart-define-from-file=config/env.json"]`.
- **Android Studio / IntelliJ IDEA**: Open **Run → Edit Configurations...**, select the `main.dart` Flutter configuration, and set **Additional run args** to:
  ```text
  --dart-define-from-file=config/env.json
  ```

---

## 4. Android & iOS Permission Notes

- **First-Launch Consent Flow**: On first launch, the app auto-detects Persian (`fa`, RTL) or English (`en`, LTR), displays a disclosure screen explaining background location sharing, and sequentially requests **When In Use** followed by **Always** location permission.
- **Android (`android/app/src/main/AndroidManifest.xml`)**:
  - Declares `ACCESS_COARSE_LOCATION`, `ACCESS_FINE_LOCATION`, `ACCESS_BACKGROUND_LOCATION`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`, and `POST_NOTIFICATIONS`.
  - Declares `<queries>` for `https` and `geo` intents so `url_launcher` can open Google Maps or the system map chooser on Android 11+.
- **iOS (`ios/Runner/Info.plist`)**:
  - Includes bilingual (English + Persian) usage descriptions for `NSLocationWhenInUseUsageDescription`, `NSLocationAlwaysAndWhenInUseUsageDescription`, and `NSLocationAlwaysUsageDescription`.
  - Declares `UIBackgroundModes` (`location`, `fetch`, `processing`).
  - Exact background timer intervals are not guaranteed by iOS, and behavior after a user force-quits the app from the iOS App Switcher must always be tested on a physical iPhone.

---

## 5. Battery-Optimization Notes (Xiaomi, Samsung, Huawei)

To keep the adaptive background location service running reliably (every ~2 minutes when moving more than ~75 m, and a ~20-minute stationary heartbeat):

- **Xiaomi (MIUI / HyperOS)**: Go to **App Info → Battery saver → No restrictions**, and enable **Autostart**.
- **Samsung (One UI)**: Go to **App Info → Battery → Unrestricted**, and ensure the app is not added to **Sleeping apps** or **Deep sleeping apps**.
- **Huawei (EMUI)**: Go to **Settings → Battery → App launch**, disable **Manage automatically**, and keep **Auto-launch**, **Secondary launch**, and **Run in background** enabled.
