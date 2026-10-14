import setupGuideRaw from '../../SETUP_GUIDE.md?raw';
import envExampleRaw from '../../config/env.example.json?raw';
import flutterGitignoreRaw from '../../flutter_app/.gitignore?raw';
import vscodeLaunchRaw from '../../flutter_app/.vscode/launch.json?raw';
import githubWorkflowRaw from '../../flutter_app/.github/workflows/build-apk.yml?raw';
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
import androidRootBuildGradleRaw from '../../flutter_app/android/build.gradle?raw';
import androidSettingsGradleRaw from '../../flutter_app/android/settings.gradle?raw';
import androidGradlePropertiesRaw from '../../flutter_app/android/gradle.properties?raw';
import androidAppBuildGradleRaw from '../../flutter_app/android/app/build.gradle?raw';
import androidProguardRulesRaw from '../../flutter_app/android/app/proguard-rules.pro?raw';
import mainActivityKtRaw from '../../flutter_app/android/app/src/main/kotlin/com/familytrack/family_track/MainActivity.kt?raw';
import icLauncherXmlRaw from '../../flutter_app/android/app/src/main/res/drawable/ic_launcher.xml?raw';
import icBgServiceSmallXmlRaw from '../../flutter_app/android/app/src/main/res/drawable/ic_bg_service_small.xml?raw';
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
    id: 'github-workflow',
    path: '.github/workflows/build-apk.yml',
    title: '.github/workflows/build-apk.yml',
    category: 'platform',
    language: 'yaml',
    summary:
      'Fixed GitHub Actions workflow: safely writes config/env.json from secrets.ENV_JSON, preserves AndroidManifest.xml and proguard-rules.pro across flutter create, sets minSdk=23, and disables R8 shrinking in build.gradle(.kts).',
    content: githubWorkflowRaw,
  },
  {
    id: 'android-manifest',
    path: 'flutter_app/android/app/src/main/AndroidManifest.xml',
    title: 'android/app/src/main/AndroidManifest.xml',
    category: 'platform',
    language: 'xml',
    summary:
      'Uses android:name=".MainActivity" and android:icon="@mipmap/ic_launcher" to match flutter create --org com.familytrack --project-name family_track, plus tools:replace="android:exported" on BackgroundService.',
    content: androidManifestRaw,
  },
  {
    id: 'main-dart',
    path: 'flutter_app/lib/main.dart',
    title: 'lib/main.dart',
    category: 'dart',
    language: 'dart',
    summary:
      'Listens to AppLifecycleListener onResume to trigger immediate location sending upon return to foreground. Router guarantees the main page (MapScreen) is always the first screen for logged-in users, eliminating login page redirects.',
    content: mainDartRaw,
  },
  {
    id: 'background-location-service',
    path: 'flutter_app/lib/services/background_location_service.dart',
    title: 'lib/services/background_location_service.dart',
    category: 'dart',
    language: 'dart',
    summary:
      'Foreground service with persistent notification, 3-minute periodic timer, continuous position stream, 75m movement threshold, 20-minute stationary heartbeat, direct PostgREST HTTP fallback, and automated Supabase JWT token refresh.',
    content: backgroundLocationRaw,
  },
  {
    id: 'app-config',
    path: 'flutter_app/lib/config/app_config.dart',
    title: 'lib/config/app_config.dart',
    category: 'dart',
    language: 'dart',
    summary:
      'Reads SUPABASE_URL and SUPABASE_ANON_KEY via String.fromEnvironment, validates HTTPS URL, and configures background location intervals (3-min timer, 75m min move, 20-min heartbeat).',
    content: appConfigRaw,
  },
  {
    id: 'app-providers',
    path: 'flutter_app/lib/providers/app_providers.dart',
    title: 'lib/providers/app_providers.dart',
    category: 'dart',
    language: 'dart',
    summary:
      'Riverpod state controller: keeps Refresh strictly separate from sending (Refresh only calls fetch_locations), restores active group synchronously on launch, handles onAppResumed foreground location sends, and maintains 2-min rate limit ticker.',
    content: appProvidersRaw,
  },
  {
    id: 'supabase-service',
    path: 'flutter_app/lib/services/supabase_service.dart',
    title: 'lib/services/supabase_service.dart',
    category: 'dart',
    language: 'dart',
    summary:
      'Client calls to the deployed Supabase backend: passes explicit Authorization Bearer JWT header and apikey to join_group Edge Function, refreshes expired sessions automatically, extracts HTTP 429 too_many_attempts and HTTP 400 bad_request accurately, and performs JSON fetch_locations RPC.',
    content: supabaseServiceRaw,
  },
  {
    id: 'map-screen',
    path: 'flutter_app/lib/screens/map_screen.dart',
    title: 'lib/screens/map_screen.dart',
    category: 'dart',
    language: 'dart',
    summary:
      'Uses MapLibreMap, MapLibreMapController, _mapController?.setStyle(...) for runtime style switching and retry, and lowerCamelCase enums.',
    content: mapScreenRaw,
  },
  {
    id: 'login-screen',
    path: 'flutter_app/lib/screens/login_screen.dart',
    title: 'lib/screens/login_screen.dart',
    category: 'dart',
    language: 'dart',
    summary:
      'GroupCodeInputFormatter (XXXX-XXXX-XXXX, uppercase, Persian/Arabic digit conversion), live 2-minute cooldown timer display on rate-limit, disabled button with mm:ss countdown, and localized error messages.',
    content: loginScreenRaw,
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
    id: 'android-app-build-gradle',
    path: 'flutter_app/android/app/build.gradle',
    title: 'android/app/build.gradle',
    category: 'platform',
    language: 'groovy',
    summary:
      'Configured with namespace & applicationId "com.familytrack.family_track", compileSdk 35, minSdk 23, targetSdk 35, Java 21, minifyEnabled false, shrinkResources false, and proguard-rules.pro.',
    content: androidAppBuildGradleRaw,
  },
  {
    id: 'android-proguard-rules',
    path: 'flutter_app/android/app/proguard-rules.pro',
    title: 'android/app/proguard-rules.pro',
    category: 'platform',
    language: 'plaintext',
    summary:
      'ProGuard / R8 keep rules preserving Flutter wrapper, MapLibre native classes, flutter_background_service, and geolocator.',
    content: androidProguardRulesRaw,
  },
  {
    id: 'main-activity-kt',
    path: 'flutter_app/android/app/src/main/kotlin/com/familytrack/family_track/MainActivity.kt',
    title: 'android/.../MainActivity.kt',
    category: 'platform',
    language: 'kotlin',
    summary:
      'Android FlutterActivity entry point in package com.familytrack.family_track matching --org com.familytrack --project-name family_track.',
    content: mainActivityKtRaw,
  },
  {
    id: 'ic-launcher-xml',
    path: 'flutter_app/android/app/src/main/res/drawable/ic_launcher.xml',
    title: 'android/.../res/drawable/ic_launcher.xml',
    category: 'platform',
    language: 'xml',
    summary: 'Vector app icon foreground drawable.',
    content: icLauncherXmlRaw,
  },
  {
    id: 'ic-bg-service-small-xml',
    path: 'flutter_app/android/app/src/main/res/drawable/ic_bg_service_small.xml',
    title: 'android/.../res/drawable/ic_bg_service_small.xml',
    category: 'platform',
    language: 'xml',
    summary:
      'Default small notification vector icon expected by flutter_background_service_android.',
    content: icBgServiceSmallXmlRaw,
  },
  {
    id: 'pubspec',
    path: 'flutter_app/pubspec.yaml',
    title: 'pubspec.yaml',
    category: 'platform',
    language: 'yaml',
    summary:
      'Upgraded maplibre_gl to ^0.27.1, Dart SDK >=3.7.0 <4.0.0, Flutter >=3.29.0, and latest compatible supabase_flutter, geolocator, and flutter_background_service_android.',
    content: pubspecRaw,
  },
  {
    id: 'android-root-build-gradle',
    path: 'flutter_app/android/build.gradle',
    title: 'android/build.gradle',
    category: 'platform',
    language: 'groovy',
    summary:
      'Project-level build.gradle with ext.kotlin_version = 2.1.0, AGP 8.7.3, and google() / mavenCentral() repositories.',
    content: androidRootBuildGradleRaw,
  },
  {
    id: 'android-settings-gradle',
    path: 'flutter_app/android/settings.gradle',
    title: 'android/settings.gradle',
    category: 'platform',
    language: 'groovy',
    summary:
      'Declares com.android.application version 8.7.3 and org.jetbrains.kotlin.android version 2.1.0.',
    content: androidSettingsGradleRaw,
  },
  {
    id: 'android-gradle-properties',
    path: 'flutter_app/android/gradle.properties',
    title: 'android/gradle.properties',
    category: 'platform',
    language: 'properties',
    summary:
      'JVM arguments for Java 21 and android.builtInKotlin=false to suppress the KGP plugin warning.',
    content: androidGradlePropertiesRaw,
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
      'Required Flutter & Java 21 toolchain, creating config/env.json, --dart-define-from-file release APK/AAB build commands, Android/iOS permissions, and battery-optimization notes.',
    content: setupGuideRaw,
  },
];

export const FOLDER_STRUCTURE_TREE = `.github/
└── workflows/
    └── build-apk.yml            # Fixed CI workflow preserving manifest + ProGuard/R8 config
flutter_app/
├── .gitignore                   # Uses **/config/env.json
├── .vscode/
│   └── launch.json              # Passes --dart-define-from-file=config/env.json
├── config/
│   └── env.example.json         # Committed placeholder template
├── pubspec.yaml                 # maplibre_gl: ^0.27.1, Dart >=3.7.0, Flutter >=3.29.0
├── analysis_options.yaml
├── android/
│   ├── build.gradle             # ext.kotlin_version = '2.1.0', AGP 8.7.3
│   ├── settings.gradle          # AGP 8.7.3 + Kotlin 2.1.0
│   ├── gradle.properties        # Java 21 args + android.builtInKotlin=false
│   └── app/
│       ├── build.gradle         # namespace com.familytrack.family_track, minSdk 23, minifyEnabled false
│       ├── proguard-rules.pro   # Keep rules for Flutter, MapLibre, background service
│       └── src/main/
│           ├── AndroidManifest.xml  # .MainActivity, @mipmap/ic_launcher, flutterEmbedding=2
│           ├── kotlin/com/familytrack/family_track/MainActivity.kt
│           └── res/
│               ├── mipmap-anydpi-v26/ic_launcher.xml
│               ├── drawable/ic_launcher.xml
│               ├── drawable/ic_bg_service_small.xml
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
    ├── main.dart                # runZonedGuarded + try/catch + MissingConfigScreen
    ├── config/
    │   └── app_config.dart      # String.fromEnvironment + HTTPS/placeholder validation
    ├── l10n/
    │   └── app_localizations.dart
    ├── models/
    │   └── models.dart
    ├── providers/
    │   └── app_providers.dart
    ├── services/
    │   ├── supabase_service.dart
    │   └── background_location_service.dart # autoStart: false, autoStartOnBoot: false
    └── screens/
        ├── consent_screen.dart
        ├── login_screen.dart
        └── map_screen.dart`;
