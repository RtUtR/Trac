// lib/services/background_location_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../models/models.dart';

/// Background location sender:
/// - Runs as an Android Foreground Service with persistent notification.
/// - Sends ONLY this phone's own location via:
///   supabase.from('locations').upsert({'user_id': myUserId, 'lat': ..., 'lng': ..., 'accuracy': ...})
/// - Never sends `updated_at` (the server sets it).
/// - Never selects from `public.locations` or fetches other members in the background.
/// - Reads ft_my_user_id, ft_access_token, ft_refresh_token from SharedPreferences so requests
///   include the user's valid Bearer JWT header, satisfying Supabase RLS policies (auth.uid() = user_id).
/// - While moving (>75 m displacement): sends every ~2 minutes.
/// - While stationary: sends heartbeat every ~20 minutes.
class BackgroundLocationService {
  static const String _prefLastSentLat = 'bg_last_sent_lat';
  static const String _prefLastSentLng = 'bg_last_sent_lng';
  static const String _prefLastSentAtMs = 'bg_last_sent_at_ms';
  static const String _prefPendingPayload = 'bg_pending_location_payload';
  static const String _prefMyUserId = 'ft_my_user_id';
  static const String _prefAccessToken = 'ft_access_token';
  static const String _prefRefreshToken = 'ft_refresh_token';

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
      await _performLocationCheckAndSend(service);
    } catch (_) {}
    return true;
  }

  @pragma('vm:entry-point')
  static void onBackgroundStart(ServiceInstance service) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      DartPluginRegistrant.ensureInitialized();
    } catch (_) {}

    // On Android, explicitly promote to foreground service with persistent notification
    if (service is AndroidServiceInstance) {
      service.on('setAsForeground').listen((_) {
        service.setAsForegroundService();
      });
      service.on('setAsBackground').listen((_) {
        service.setAsBackgroundService();
      });

      await service.setAsForegroundService();
      service.setForegroundNotificationInfo(
        title: 'FamilyTrack Location Active',
        content: 'Sharing your latest location with your group in the background.',
      );
    }

    service.on('stopService').listen((_) {
      service.stopSelf();
    });

    if (!AppConfig.isSupabaseConfigured) {
      service.stopSelf();
      return;
    }

    // 1. Immediate location check & send upon service start
    await _performLocationCheckAndSend(service);

    // 2. Continuous position stream listener:
    // Listens to location changes from the OS so background movement is actively detected
    try {
      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen(
        (position) async {
          await _handleNewPosition(position, service);
        },
        onError: (err) {
          debugPrint('Background location stream error: $err');
        },
      );
    } catch (e) {
      debugPrint('getPositionStream subscription failed: $e');
    }

    // 3. Fallback periodic timer every 2 minutes:
    // Ensures stationary heartbeat (every 20 min) is sent even if device has not moved
    Timer.periodic(
      const Duration(seconds: AppConfig.movingIntervalSeconds),
      (_) async {
        await _performLocationCheckAndSend(service);
      },
    );
  }

  static Future<void> _performLocationCheckAndSend([ServiceInstance? service]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      await _flushOfflineQueueIfPresent(prefs);

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 15),
          ),
        );
      } catch (_) {
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) return;
      await _handleNewPosition(position, service);
    } catch (_) {}
  }

  static Future<void> _handleNewPosition(
    Position position,
    ServiceInstance? service,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

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

        // Moving: > 75m displacement & ~2 min elapsed
        if (distanceMeters >= AppConfig.minDisplacementMeters &&
            elapsedSeconds >= AppConfig.movingIntervalSeconds) {
          shouldSend = true;
        } else if (elapsedSeconds >= AppConfig.stationaryHeartbeatSeconds) {
          // Stationary heartbeat: ~20 min
          shouldSend = true;
        }
      }

      if (!shouldSend) return;

      final payload = QueuedLocationPayload(
        lat: position.latitude,
        lng: position.longitude,
        accuracy: position.accuracy,
      );

      final sent = await _tryUpsertPayload(payload, prefs);
      if (sent) {
        await prefs.setDouble(_prefLastSentLat, payload.lat);
        await prefs.setDouble(_prefLastSentLng, payload.lng);
        await prefs.setInt(_prefLastSentAtMs, nowMs);
        await prefs.remove(_prefPendingPayload);

        if (service is AndroidServiceInstance) {
          final timeStr =
              DateTime.now().toLocal().toString().substring(11, 16);
          service.setForegroundNotificationInfo(
            title: 'FamilyTrack Location Active',
            content: 'Last updated at $timeStr • Sharing with group',
          );
        }
      } else {
        await prefs.setString(
          _prefPendingPayload,
          jsonEncode(payload.toJson()),
        );
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
      final ok = await _tryUpsertPayload(queued, prefs);
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

  static Future<bool> _tryUpsertPayload(
    QueuedLocationPayload payload,
    SharedPreferences prefs,
  ) async {
    try {
      await prefs.reload();
      final myUserId = prefs.getString(_prefMyUserId);
      final accessToken = prefs.getString(_prefAccessToken);
      final refreshToken = prefs.getString(_prefRefreshToken);

      if (myUserId == null || myUserId.isEmpty) {
        debugPrint('Background location: No myUserId found in SharedPreferences');
        return false;
      }

      // Instantiate a SupabaseClient with the user's Bearer JWT in the Authorization header
      // so Supabase Postgres RLS (auth.uid() = user_id) allows the upsert.
      final client = SupabaseClient(
        AppConfig.supabaseUrl.trim(),
        AppConfig.supabaseAnonKey.trim(),
        headers: {
          if (accessToken != null && accessToken.isNotEmpty)
            'Authorization': 'Bearer $accessToken',
        },
      );

      try {
        // Never send updated_at (the server sets it)
        await client.from('locations').upsert({
          'user_id': myUserId,
          'lat': payload.lat,
          'lng': payload.lng,
          'accuracy': payload.accuracy,
        });
        return true;
      } catch (upsertError) {
        debugPrint('Background primary upsert error: $upsertError');
        // If JWT expired (401), attempt session refresh with saved refresh token
        if (refreshToken != null && refreshToken.isNotEmpty) {
          try {
            final authRes = await client.auth.setSession(refreshToken);
            final newSession = authRes.session;
            if (newSession != null) {
              await prefs.setString(_prefAccessToken, newSession.accessToken);
              if (newSession.refreshToken != null) {
                await prefs.setString(_prefRefreshToken, newSession.refreshToken!);
              }
              final freshClient = SupabaseClient(
                AppConfig.supabaseUrl.trim(),
                AppConfig.supabaseAnonKey.trim(),
                headers: {
                  'Authorization': 'Bearer ${newSession.accessToken}',
                },
              );
              await freshClient.from('locations').upsert({
                'user_id': myUserId,
                'lat': payload.lat,
                'lng': payload.lng,
                'accuracy': payload.accuracy,
              });
              return true;
            }
          } catch (refreshError) {
            debugPrint('Background token refresh failed: $refreshError');
          }
        }
        return false;
      }
    } catch (e) {
      debugPrint('Background _tryUpsertPayload uncaught error: $e');
      return false;
    }
  }
}
