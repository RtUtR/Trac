// lib/main.dart
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
import 'services/background_location_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();

  if (AppConfig.isSupabaseConfigured) {
    // Initialize Supabase once at startup
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );

    // On first launch call supabase.auth.signInAnonymously() and keep the session
    final auth = Supabase.instance.client.auth;
    if (auth.currentSession == null) {
      try {
        await auth.signInAnonymously();
      } catch (_) {}
    }

    await BackgroundLocationService.initialize();
  }

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const FamilyTrackApp(),
    ),
  );
}

class FamilyTrackApp extends ConsumerWidget {
  const FamilyTrackApp({super.key});

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
      home: !AppConfig.isSupabaseConfigured
          ? const MissingConfigScreen()
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

/// Shown if SUPABASE_URL or SUPABASE_ANON_KEY is empty at startup (never crashes silently).
class MissingConfigScreen extends StatelessWidget {
  const MissingConfigScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
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
                      'flutter run --dart-define-from-file=config/env.json',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
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
    );
  }
}
