// lib/services/background_location_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../models/models.dart';

/// Background location sender:
/// - Sends ONLY this phone's own location via:
///   supabase.from('locations').upsert({'user_id': myUserId, 'lat': ..., 'lng': ..., 'accuracy': ...})
/// - Never sends `updated_at` (the server sets it).
/// - Never selects from `public.locations` or fetches other members in the background.
///
/// ANDROID CRASH PREVENTION NOTES:
/// 1. `autoStart: false` and `autoStartOnBoot: false` prevent `WatchdogReceiver` / `BootReceiver`
///    from throwing `ForegroundServiceStartNotAllowedException` on Android 14/15 (`targetSdk 35`).
/// 2. Omitting custom `notificationChannelId` lets `flutter_background_service_android` create
///    and use its default notification channel automatically.
/// 3. `startIfPermitted()` configures and starts the service ONLY after `runApp()` and ONLY after
///    verifying that runtime location permission (`whileInUse` or `always`) is granted.
class BackgroundLocationService {
  static const String _prefLastSentLat = 'bg_last_sent_lat';
  static const String _prefLastSentLng = 'bg_last_sent_lng';
  static const String _prefLastSentAtMs = 'bg_last_sent_at_ms';
  static const String _prefPendingPayload = 'bg_pending_location_payload';

  static bool _isConfigured = false;

  static Future<void> initialize() async {
    if (!AppConfig.isSupabaseConfigured) return;
    if (_isConfigured) return;

    try {
      final service = FlutterBackgroundService();

      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: onBackgroundStart,
          autoStart: false,
          autoStartOnBoot: false,
          isForegroundMode: true,
          // Omit notificationChannelId so flutter_background_service_android
          // automatically creates its default channel without crashing on Android 12-15.
          initialNotificationTitle: 'FamilyTrack Location Active',
          initialNotificationContent:
              'Sharing your latest location with your group in the background.',
          foregroundServiceNotificationId: 8842,
          foregroundServiceTypes: [AndroidForegroundType.location],
        ),
        iosConfiguration: IosConfiguration(
          autoStart: false,
          onForeground: onBackgroundStart,
          onBackground: onIosBackground,
        ),
      );
      _isConfigured = true;
    } catch (e) {
      debugPrint('BackgroundLocationService configure error: $e');
    }
  }

  /// Configures and starts the foreground/background service ONLY after verifying that
  /// location services are enabled and runtime location permission is granted (required on Android 14/15).
  static Future<void> startIfPermitted() async {
    if (!AppConfig.isSupabaseConfigured) return;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return;
      }

      await initialize();

      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();
      if (!isRunning) {
        await service.startService();
      }
    } catch (e) {
      debugPrint('BackgroundLocationService startIfPermitted error: $e');
    }
  }

  static Future<void> stop() async {
    if (!AppConfig.isSupabaseConfigured) return;
    if (!_isConfigured) return;
    try {
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();
      if (isRunning) {
        service.invoke('stopService');
      }
    } catch (e) {
      debugPrint('BackgroundLocationService stop error: $e');
    }
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      DartPluginRegistrant.ensureInitialized();
      await _performLocationCheckAndSend();
    } catch (_) {}
    return true;
  }

  @pragma('vm:entry-point')
  static void onBackgroundStart(ServiceInstance service) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      DartPluginRegistrant.ensureInitialized();
    } catch (_) {}

    service.on('stopService').listen((_) {
      service.stopSelf();
    });

    if (!AppConfig.isSupabaseConfigured) {
      service.stopSelf();
      return;
    }

    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl.trim(),
        anonKey: AppConfig.supabaseAnonKey.trim(),
      );
    } catch (_) {
      // Already initialized
    }

    await _performLocationCheckAndSend();

    Timer.periodic(
      const Duration(seconds: AppConfig.movingIntervalSeconds),
      (_) async {
        await _performLocationCheckAndSend();
      },
    );
  }

  static Future<void> _performLocationCheckAndSend() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      await _flushOfflineQueueIfPresent(prefs);

      Position position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            distanceFilter: 25,
            timeLimit: Duration(seconds: 20),
          ),
        );
      } catch (_) {
        return;
      }

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final lastLat = prefs.getDouble(_prefLastSentLat);
      final lastLng = prefs.getDouble(_prefLastSentLng);
      final lastSentAtMs = prefs.getInt(_prefLastSentAtMs);

      bool shouldSend = false;

      if (lastLat == null || lastLng == null || lastSentAtMs == null) {
        shouldSend = true;
      } else {
        final distanceMeters = Geolocator.distanceBetween(
          lastLat,
          lastLng,
          position.latitude,
          position.longitude,
        );
        final elapsedSeconds = (nowMs - lastSentAtMs) ~/ 1000;

        if (distanceMeters >= AppConfig.minDisplacementMeters) {
          shouldSend = true;
        } else if (elapsedSeconds >= AppConfig.stationaryHeartbeatSeconds) {
          shouldSend = true;
        }
      }

      if (!shouldSend) return;

      final payload = QueuedLocationPayload(
        lat: position.latitude,
        lng: position.longitude,
        accuracy: position.accuracy,
      );

      final sent = await _tryUpsertPayload(payload);
      if (sent) {
        await prefs.setDouble(_prefLastSentLat, payload.lat);
        await prefs.setDouble(_prefLastSentLng, payload.lng);
        await prefs.setInt(_prefLastSentAtMs, nowMs);
        await prefs.remove(_prefPendingPayload);
      } else {
        await prefs.setString(_prefPendingPayload, jsonEncode(payload.toJson()));
      }
    } catch (_) {}
  }

  static Future<void> _flushOfflineQueueIfPresent(
    SharedPreferences prefs,
  ) async {
    final raw = prefs.getString(_prefPendingPayload);
    if (raw == null) return;

    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final queued = QueuedLocationPayload.fromJson(map);
      final ok = await _tryUpsertPayload(queued);
      if (ok) {
        await prefs.setDouble(_prefLastSentLat, queued.lat);
        await prefs.setDouble(_prefLastSentLng, queued.lng);
        await prefs.setInt(
          _prefLastSentAtMs,
          DateTime.now().millisecondsSinceEpoch,
        );
        await prefs.remove(_prefPendingPayload);
      }
    } catch (_) {
      await prefs.remove(_prefPendingPayload);
    }
  }

  static Future<bool> _tryUpsertPayload(QueuedLocationPayload payload) async {
    try {
      final client = Supabase.instance.client;
      final myUserId = client.auth.currentUser?.id;
      if (myUserId == null) return false;

      // Never send updated_at (the server sets it)
      await client.from('locations').upsert({
        'user_id': myUserId,
        'lat': payload.lat,
        'lng': payload.lng,
        'accuracy': payload.accuracy,
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}
