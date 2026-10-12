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
/// - Adaptive interval: checks every ~2 minutes while moving (moved > ~75 m from last sent),
///   and sends a stationary heartbeat every ~20 minutes when still.
/// - Queues and retries when offline.
///
/// NOTE ON iOS BACKGROUND EXECUTION:
/// iOS uses `Always` permission with significant-location-change + periodic updates.
/// Exact timing is not guaranteed on iOS and behavior after the user force-quits the app
/// must be tested on a real device.
class BackgroundLocationService {
  static const String _prefLastSentLat = 'bg_last_sent_lat';
  static const String _prefLastSentLng = 'bg_last_sent_lng';
  static const String _prefLastSentAtMs = 'bg_last_sent_at_ms';
  static const String _prefPendingPayload = 'bg_pending_location_payload';

  static Future<void> initialize() async {
    if (!AppConfig.isSupabaseConfigured) return;

    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onBackgroundStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'familytrack_location_channel',
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
  }

  static Future<void> startIfPermitted() async {
    if (!AppConfig.isSupabaseConfigured) return;
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    if (!isRunning) {
      await service.startService();
    }
  }

  static Future<void> stop() async {
    if (!AppConfig.isSupabaseConfigured) return;
    final service = FlutterBackgroundService();
    service.invoke('stopService');
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    await _performLocationCheckAndSend();
    return true;
  }

  @pragma('vm:entry-point')
  static void onBackgroundStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();

    service.on('stopService').listen((_) {
      service.stopSelf();
    });

    if (!AppConfig.isSupabaseConfigured) {
      service.stopSelf();
      return;
    }

    // Initialize Supabase in background isolate if needed
    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        anonKey: AppConfig.supabaseAnonKey,
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

      // Send if moved more than ~75m OR if stationary for >= ~20 minutes (heartbeat)
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
