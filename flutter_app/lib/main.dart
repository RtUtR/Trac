// lib/main.dart
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/app_config.dart';
import 'l10n/app_localizations.dart';
import 'providers/app_providers.dart';
import 'screens/consent_screen.dart';
import 'screens/login_screen.dart';
import 'screens/map_screen.dart';

void main() {
  // Catch all synchronous and asynchronous errors so the app never force-closes silently.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError: ${details.exceptionAsString()}');
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      debugPrint('PlatformDispatcher Error: $error\n$stack');
      return true; // Prevent native force-close on uncaught async error
    };

    ErrorWidget.builder = (FlutterErrorDetails details) {
      return Material(
        color: const Color(0xFFFFFFFF),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: Text(
                'UI Error:\n${details.exceptionAsString()}',
                style: const TextStyle(
                  color: Color(0xFF111111),
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ),
      );
    };

    SharedPreferences? prefs;
    String? startupError;

    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e) {
      startupError = 'SharedPreferences initialization failed: $e';
    }

    bool supabaseReady = false;
    if (AppConfig.isSupabaseConfigured) {
      try {
        await Supabase.initialize(
          url: AppConfig.supabaseUrl.trim(),
          anonKey: AppConfig.supabaseAnonKey.trim(),
        );
        supabaseReady = true;

        // Sign in anonymously in the background without blocking startup if offline
        final auth = Supabase.instance.client.auth;
        if (auth.currentSession == null) {
          unawaited(
            auth.signInAnonymously().catchError((Object e) {
              debugPrint('Initial anonymous sign-in deferred: $e');
              return AuthResponse();
            }),
          );
        }
      } catch (e) {
        startupError = 'Supabase initialization failed: $e';
      }
    }

    // Note: BackgroundLocationService is NOT initialized before runApp().
    // It is configured lazily inside BackgroundLocationService.startIfPermitted()
    // ONLY after the user accepts consent and grants runtime location permission.

    runApp(
      ProviderScope(
        overrides: [
          if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: FamilyTrackApp(
          isConfigured:
              AppConfig.isSupabaseConfigured && supabaseReady && prefs != null,
          startupError: startupError,
        ),
      ),
    );
  }, (Object error, StackTrace stackTrace) {
    debugPrint('Uncaught Zone Error: $error\n$stackTrace');
  });
}

class FamilyTrackApp extends ConsumerWidget {
  final bool isConfigured;
  final String? startupError;

  const FamilyTrackApp({
    super.key,
    required this.isConfigured,
    this.startupError,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FamilyTrack',
      supportedLocales: const [
        Locale('en'),
        Locale('fa'),
      ],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: ThemeMode.system,
      theme: _buildMonochromeTheme(Brightness.light),
      darkTheme: _buildMonochromeTheme(Brightness.dark),
      home: !isConfigured
          ? MissingConfigScreen(errorDetail: startupError)
          : const _ConfiguredHomeRouter(),
    );
  }

  ThemeData _buildMonochromeTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0A0A0A) : const Color(0xFFFFFFFF);
    final fg = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF111111);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: fg,
        onPrimary: bg,
        secondary: fg,
        onSecondary: bg,
        error: fg,
        onError: bg,
        surface: bg,
        onSurface: fg,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: fg,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
    );
  }
}

class _ConfiguredHomeRouter extends ConsumerWidget {
  const _ConfiguredHomeRouter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: !state.consentAccepted
          ? const ConsentScreen(key: ValueKey('consent'))
          : state.activeGroup == null
              ? const LoginScreen(key: ValueKey('login'))
              : const MapScreen(key: ValueKey('map')),
    );
  }
}

/// Shown if SUPABASE_URL or SUPABASE_ANON_KEY is empty/invalid at startup (never crashes silently).
class MissingConfigScreen extends StatelessWidget {
  final String? errorDetail;

  const MissingConfigScreen({super.key, this.errorDetail});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: theme.colorScheme.onSurface,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l10n.tr('missing_config_title'),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.tr('missing_config_body'),
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                  if (errorDetail != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorDetail!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: theme.colorScheme.onSurface.withOpacity(0.25),
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const SelectableText(
                        'flutter build apk --release --dart-define-from-file=config/env.json',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
