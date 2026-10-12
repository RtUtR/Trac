// lib/config/app_config.dart
// Keep secrets out of source code. Pass them at compile time using:
// flutter run --dart-define-from-file=config/env.json
//
// SECURITY NOTE: Only the publishable (anon) key may be used in the client.

enum MapStyleOption {
  positron,
  bright,
  dark,
}

class AppConfig {
  AppConfig._();

  // Read compile-time environment variables from config/env.json.
  // Only the publishable (anon) key may be used in the client.
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// Returns true only when both SUPABASE_URL and SUPABASE_ANON_KEY are non-empty,
  /// valid HTTPS URLs, and not the placeholder strings from env.example.json.
  static bool get isSupabaseConfigured {
    final url = supabaseUrl.trim();
    final key = supabaseAnonKey.trim();
    if (url.isEmpty || key.isEmpty) return false;
    if (!url.startsWith('https://')) return false;
    if (url.contains('YOUR-PROJECT') || url.contains('YOUR_PROJECT')) {
      return false;
    }
    if (key.contains('YOUR-PUBLISHABLE-KEY') ||
        key.contains('YOUR_SUPABASE_ANON_KEY')) {
      return false;
    }
    return true;
  }

  // Allowed 12-character group code alphabet (no 0, O, 1, I, L)
  static const String groupCodeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const int groupCodeLength = 12;

  /// Converts Persian (۰-۹) and Arabic-Indic (٠-٩) digits to Latin (0-9),
  /// uppercases text, and strips hyphens and whitespace.
  static String normalizeGroupCode(String raw) {
    final buffer = StringBuffer();
    for (final rune in raw.runes) {
      if (rune >= 0x06F0 && rune <= 0x06F9) {
        buffer.writeCharCode(0x30 + (rune - 0x06F0));
      } else if (rune >= 0x0660 && rune <= 0x0669) {
        buffer.writeCharCode(0x30 + (rune - 0x0660));
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer
        .toString()
        .toUpperCase()
        .replaceAll(RegExp(r'[\s\-]'), '');
  }

  /// Formats a normalized code as XXXX-XXXX-XXXX for display in the input field.
  static String formatGroupCodeDisplay(String raw) {
    final cleaned = normalizeGroupCode(raw);
    final clipped = cleaned.length > groupCodeLength
        ? cleaned.substring(0, groupCodeLength)
        : cleaned;
    final parts = <String>[];
    for (var i = 0; i < clipped.length; i += 4) {
      final end = (i + 4 < clipped.length) ? i + 4 : clipped.length;
      parts.add(clipped.substring(i, end));
    }
    return parts.join('-');
  }

  static bool isValidGroupCode(String normalized) {
    if (normalized.length != groupCodeLength) return false;
    for (var i = 0; i < normalized.length; i++) {
      if (!groupCodeAlphabet.contains(normalized[i])) {
        return false;
      }
    }
    return true;
  }

  // Single provider base constant so the tile provider can be swapped later in ONE place.
  static const String tileProviderBaseUrl = 'https://tiles.waymorphic.com/styles';

  static String styleUrl(MapStyleOption style) {
    switch (style) {
      case MapStyleOption.positron:
        return '$tileProviderBaseUrl/positron';
      case MapStyleOption.bright:
        return '$tileProviderBaseUrl/bright';
      case MapStyleOption.dark:
        return '$tileProviderBaseUrl/dark';
    }
  }

  // Tile zoom limit is 14; allow over-zoom up to 18.
  static const double maxSourceTileZoom = 14.0;
  static const double maxMapOverZoom = 18.0;
  static const double minMapZoom = 2.0;

  // Map ready timeout before degrading gracefully to chips + "Open in maps"
  static const Duration mapReadyTimeout = Duration(seconds: 20);

  // Background location sending parameters (battery & data friendly)
  static const int movingIntervalSeconds = 120;
  static const double minDisplacementMeters = 75.0;
  static const int stationaryHeartbeatSeconds = 1200;
}
