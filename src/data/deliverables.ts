import setupGuideRaw from '../../SETUP_GUIDE.md?raw';
import envExampleRaw from '../../config/env.example.json?raw';
import flutterGitignoreRaw from '../../flutter_app/.gitignore?raw';
import vscodeLaunchRaw from '../../flutter_app/.vscode/launch.json?raw';
import pubspecRaw from '../../flutter_app/pubspec.yaml?raw';
import analysisOptionsRaw from '../../flutter_app/analysis_options.yaml?raw';
import appConfigRaw from '../../flutter_app/lib/config/app_config.dart?raw';
import appLocalizationsRaw from '../../flutter_app/lib/l10n/app_localizations.dart?raw';
import modelsRaw from '../../flutter_app/lib/models/models.dart?raw';
import supabaseServiceRaw from '../../flutter_app/lib/services/supabase_service.dart?raw';
import backgroundLocationRaw from '../../flutter_app/lib/services/background_location_service.dart?raw';
import appProvidersRaw from '../../flutter_app/lib/providers/app_providers.dart?raw';
import consentScreenRaw from '../../flutter_app/lib/screens/consent_screen.dart?raw';
import loginScreenRaw from '../../flutter_app/lib/screens/login_screen.dart?raw';
import mapScreenRaw from '../../flutter_app/lib/screens/map_screen.dart?raw';
import mainDartRaw from '../../flutter_app/lib/main.dart?raw';
import androidManifestRaw from '../../flutter_app/android/app/src/main/AndroidManifest.xml?raw';
import androidAppBuildGradleRaw from '../../flutter_app/android/app/build.gradle?raw';
import mainActivityKtRaw from '../../flutter_app/android/app/src/main/kotlin/com/example/family_track/MainActivity.kt?raw';
import infoPlistRaw from '../../flutter_app/ios/Runner/Info.plist?raw';
import iosPodfileRaw from '../../flutter_app/ios/Podfile?raw';
import appDelegateSwiftRaw from '../../flutter_app/ios/Runner/AppDelegate.swift?raw';

export interface DeliverableFile {
  id: string;
  path: string;
  title: string;
  category: 'dart' | 'platform' | 'setup';
  language: string;
  summary: string;
  content: string;
}

export const DELIVERABLE_FILES: DeliverableFile[] = [
  {
    id: 'app-config',
    path: 'flutter_app/lib/config/app_config.dart',
    title: 'lib/config/app_config.dart',
    category: 'dart',
    language: 'dart',
    summary:
      'Reads SUPABASE_URL and SUPABASE_ANON_KEY via String.fromEnvironment, normalizes Persian/Arabic digits into XXXX-XXXX-XXXX group codes, and configures Waymorphic styles.',
    content: appConfigRaw,
  },
  {
    id: 'supabase-service',
    path: 'flutter_app/lib/services/supabase_service.dart',
    title: 'lib/services/supabase_service.dart',
    category: 'dart',
    language: 'dart',
    summary:
      'Client calls to the deployed Supabase backend: signInAnonymously(), join_group {code, display_name}, members/groups queries, location upsert (without updated_at), JSON fetch_locations RPC, and leave_group.',
    content: supabaseServiceRaw,
  },
  {
    id: 'app-providers',
    path: 'flutter_app/lib/providers/app_providers.dart',
    title: 'lib/providers/app_providers.dart',
    category: 'dart',
    language: 'dart',
    summary:
      'Riverpod state controller saving group_id, display_name, and color locally, handling JSON {ok, error, remaining_seconds} responses, and redirecting to login on expiry.',
    content: appProvidersRaw,
  },
  {
    id: 'login-screen',
    path: 'flutter_app/lib/screens/login_screen.dart',
    title: 'lib/screens/login_screen.dart',
    category: 'dart',
    language: 'dart',
    summary:
      'GroupCodeInputFormatter (XXXX-XXXX-XXXX, uppercase, Persian/Arabic digit conversion) and localized error display for all 9 join_group error codes.',
    content: loginScreenRaw,
  },
  {
    id: 'map-screen',
    path: 'flutter_app/lib/screens/map_screen.dart',
    title: 'lib/screens/map_screen.dart',
    category: 'dart',
    language: 'dart',
    summary:
      'Native MapLibreMap with Waymorphic styles, top linear progress bar + 20s timeout fallback, single GeoJSON data-driven circle layer, member chips, and external Google Maps / geo: links.',
    content: mapScreenRaw,
  },
  {
    id: 'background-location-service',
    path: 'flutter_app/lib/services/background_location_service.dart',
    title: 'lib/services/background_location_service.dart',
    category: 'dart',
    language: 'dart',
    summary:
      'Android foreground service + iOS background handler upserting {user_id, lat, lng, accuracy} (never sending updated_at) every ~2m while moving (>75m) or ~20m stationary heartbeat.',
    content: backgroundLocationRaw,
  },
  {
    id: 'main-dart',
    path: 'flutter_app/lib/main.dart',
    title: 'lib/main.dart',
    category: 'dart',
    language: 'dart',
    summary:
      'Initializes Supabase once at startup, calls signInAnonymously() on first launch, and shows MissingConfigScreen if SUPABASE_URL or SUPABASE_ANON_KEY is empty.',
    content: mainDartRaw,
  },
  {
    id: 'app-localizations',
    path: 'flutter_app/lib/l10n/app_localizations.dart',
    title: 'lib/l10n/app_localizations.dart',
    category: 'dart',
    language: 'dart',
    summary:
      'English (LTR) and Persian/Farsi (RTL) translations for all UI strings and exact backend error codes.',
    content: appLocalizationsRaw,
  },
  {
    id: 'models',
    path: 'flutter_app/lib/models/models.dart',
    title: 'lib/models/models.dart',
    category: 'dart',
    language: 'dart',
    summary:
      'Models for GroupSummary, GroupInfoRow, GroupMember, MemberLocation, JoinGroupResult, FetchLocationsResult, and QueuedLocationPayload.',
    content: modelsRaw,
  },
  {
    id: 'consent-screen',
    path: 'flutter_app/lib/screens/consent_screen.dart',
    title: 'lib/screens/consent_screen.dart',
    category: 'dart',
    language: 'dart',
    summary:
      'First-launch disclosure explaining background location sharing, sequential When In Use -> Always permissions, and Xiaomi/Samsung battery optimization guidance.',
    content: consentScreenRaw,
  },
  {
    id: 'pubspec',
    path: 'flutter_app/pubspec.yaml',
    title: 'pubspec.yaml',
    category: 'platform',
    language: 'yaml',
    summary:
      'Flutter dependencies: flutter_riverpod, supabase_flutter, geolocator, flutter_background_service, maplibre_gl, url_launcher, flutter_localizations, shared_preferences.',
    content: pubspecRaw,
  },
  {
    id: 'env-example-json',
    path: 'flutter_app/config/env.example.json',
    title: 'config/env.example.json',
    category: 'platform',
    language: 'json',
    summary:
      'Committed placeholder template for --dart-define-from-file=config/env.json (**/config/env.json is ignored by .gitignore).',
    content: envExampleRaw,
  },
  {
    id: 'flutter-gitignore',
    path: 'flutter_app/.gitignore',
    title: '.gitignore',
    category: 'platform',
    language: 'plaintext',
    summary:
      'Uses **/config/env.json so environment credentials are ignored at any folder depth while keeping config/env.example.json tracked.',
    content: flutterGitignoreRaw,
  },
  {
    id: 'vscode-launch',
    path: 'flutter_app/.vscode/launch.json',
    title: '.vscode/launch.json',
    category: 'platform',
    language: 'json',
    summary:
      'VS Code launch configuration passing --dart-define-from-file=config/env.json.',
    content: vscodeLaunchRaw,
  },
  {
    id: 'android-manifest',
    path: 'flutter_app/android/app/src/main/AndroidManifest.xml',
    title: 'android/app/src/main/AndroidManifest.xml',
    category: 'platform',
    language: 'xml',
    summary:
      'Android permissions for ACCESS_FINE_LOCATION, ACCESS_BACKGROUND_LOCATION, FOREGROUND_SERVICE_LOCATION, battery optimization exemption, and geo/https intent queries.',
    content: androidManifestRaw,
  },
  {
    id: 'android-app-build-gradle',
    path: 'flutter_app/android/app/build.gradle',
    title: 'android/app/build.gradle',
    category: 'platform',
    language: 'groovy',
    summary:
      'Android application Gradle configuration (compileSdk 34, minSdk 21, Java 17).',
    content: androidAppBuildGradleRaw,
  },
  {
    id: 'main-activity-kt',
    path: 'flutter_app/android/app/src/main/kotlin/com/example/family_track/MainActivity.kt',
    title: 'android/.../MainActivity.kt',
    category: 'platform',
    language: 'kotlin',
    summary: 'Android FlutterActivity entry point.',
    content: mainActivityKtRaw,
  },
  {
    id: 'ios-info-plist',
    path: 'flutter_app/ios/Runner/Info.plist',
    title: 'ios/Runner/Info.plist',
    category: 'platform',
    language: 'xml',
    summary:
      'iOS bilingual (English + Persian) NSLocationWhenInUse / NSLocationAlwaysAndWhenInUseUsageDescription strings, UIBackgroundModes (location, fetch, processing), and map schemes.',
    content: infoPlistRaw,
  },
  {
    id: 'ios-podfile',
    path: 'flutter_app/ios/Podfile',
    title: 'ios/Podfile',
    category: 'platform',
    language: 'ruby',
    summary: 'iOS CocoaPods configuration targeting iOS 14.0+.',
    content: iosPodfileRaw,
  },
  {
    id: 'ios-app-delegate',
    path: 'flutter_app/ios/Runner/AppDelegate.swift',
    title: 'ios/Runner/AppDelegate.swift',
    category: 'platform',
    language: 'swift',
    summary: 'iOS AppDelegate registering Flutter plugins.',
    content: appDelegateSwiftRaw,
  },
  {
    id: 'analysis-options',
    path: 'flutter_app/analysis_options.yaml',
    title: 'analysis_options.yaml',
    category: 'platform',
    language: 'yaml',
    summary: 'Flutter lint rules configuration.',
    content: analysisOptionsRaw,
  },
  {
    id: 'setup-guide',
    path: 'SETUP_GUIDE.md',
    title: 'SETUP_GUIDE.md',
    category: 'setup',
    language: 'markdown',
    summary:
      'Required Flutter version, creating config/env.json from config/env.example.json, --dart-define-from-file build commands (apk & ios), Android/iOS permissions, and battery-optimization notes.',
    content: setupGuideRaw,
  },
];

export const FOLDER_STRUCTURE_TREE = `flutter_app/
├── .gitignore                   # Uses **/config/env.json (ignores env.json at any depth)
├── .vscode/
│   └── launch.json              # Passes --dart-define-from-file=config/env.json
├── config/
│   └── env.example.json         # Committed placeholder template
├── pubspec.yaml
├── analysis_options.yaml
├── android/
│   ├── build.gradle
│   ├── settings.gradle
│   ├── gradle.properties
│   └── app/
│       ├── build.gradle
│       └── src/main/
│           ├── AndroidManifest.xml
│           ├── kotlin/com/example/family_track/MainActivity.kt
│           └── res/
│               ├── drawable/launch_background.xml
│               ├── values/styles.xml
│               └── values-night/styles.xml
├── ios/
│   ├── Podfile
│   └── Runner/
│       ├── AppDelegate.swift
│       ├── Runner-Bridging-Header.h
│       └── Info.plist
└── lib/
    ├── main.dart
    ├── config/
    │   └── app_config.dart
    ├── l10n/
    │   └── app_localizations.dart
    ├── models/
    │   └── models.dart
    ├── providers/
    │   └── app_providers.dart
    ├── services/
    │   ├── supabase_service.dart
    │   └── background_location_service.dart
    └── screens/
        ├── consent_screen.dart
        ├── login_screen.dart
        └── map_screen.dart`;
