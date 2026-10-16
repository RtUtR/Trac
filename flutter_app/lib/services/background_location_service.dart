// lib/services/background_location_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../models/models.dart';

/// Background location service for FamilyTrack:
/// - Android: Runs as a Foreground Service of type "location" with a persistent notification
///   (requires FOREGROUND_SERVICE_LOCATION, POST_NOTIFICATIONS, and ACCESS_FINE_LOCATION permissions).
///   Periodically checks location every 3 minutes (LOCATION_CHECK_INTERVAL) and listens to position updates.
///   - If device moved > 75 m (MIN_MOVE_METERS) since last send: upserts position in public.locations.
///   - If stationary: sends a heartbeat upsert if > 20 minutes (HEARTBEAT_INTERVAL) elapsed.
///   - Otherwise skips sending.
/// - iOS: Uses background location updates with the same rules (75 m movement, 20 minute heartbeat).
///   Note: On iOS, exact timing is controlled by system power management and is not guaranteed.
/// - Never sends `updated_at` (server sets it automatically).
/// - Never selects from `locations` or calls `fetch_locations` (Refresh button only).
/// - Restores session JWT before upserting so Supabase RLS (auth.uid() = user_id) succeeds in background.
class BackgroundLocationService {
  static const String _prefLastSentLat = 'bg_last_sent_lat';
  static const String _prefLastSentLng = 'bg_last_sent_lng';
  static const String _prefLastSentAtMs = 'bg_last_sent_at_ms';
  static const String _prefPendingPayload = 'bg_pending_location_payload';
  static const String _prefLastCheckStatus = 'bg_last_check_status';
  static const String _prefRefreshLockMs = 'ft_refresh_lock_ms';
  static const String _prefMyUserId = 'ft_my_user_id';
  static const String _prefAccessToken = 'ft_access_token';
  static const String _prefRefreshToken = 'ft_refresh_token';

  static bool _isConfigured = false;
  static bool _notificationChannelCreated = false;

  /// Requests POST_NOTIFICATIONS permission on Android 13+ and creates the foreground
  /// notification channel ('my_foreground') before the background service is configured or started.
  static Future<void> requestNotificationPermission() async {
    if (_notificationChannelCreated) return;
    try {
      final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
      const initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
      );
      await flutterLocalNotificationsPlugin.initialize(initializationSettings);

      final androidImplementation =
          flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidImplementation != null) {
        const channel = AndroidNotificationChannel(
          'my_foreground',
          'FamilyTrack Location Active',
          description:
              'Sharing your latest location with your group in the background.',
          importance: Importance.low,
        );
        await androidImplementation.createNotificationChannel(channel);
        try {
          await androidImplementation.requestNotificationsPermission();
        } catch (_) {}
        _notificationChannelCreated = true;
      }
    } catch (e) {
      debugPrint('Notification channel/permission setup caught: $e');
    }
  }

  static Future<void> initialize() async {
    if (!AppConfig.isSupabaseConfigured) return;
    if (_isConfigured) return;

    try {
      // Create notification channel first to prevent BadForegroundServiceNotificationException
      await requestNotificationPermission();

      final service = FlutterBackgroundService();

      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: onBackgroundStart,
          autoStart: false,
          autoStartOnBoot: false,
          isForegroundMode: true,
          notificationChannelId: 'my_foreground',
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
  /// location services are enabled, runtime location permission is ALREADY GRANTED
  /// ("While in use" or "Always"), and notification permission has been requested.
  /// Never throws or crashes: reports any failure in the status line so it can be retried.
  static Future<void> startIfPermitted() async {
    if (!AppConfig.isSupabaseConfigured) return;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('startIfPermitted: location service is disabled');
        return;
      }

      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        debugPrint('startIfPermitted: location permission not granted ($permission)');
        return;
      }

      // Request notification permission and create channel before configure
      await requestNotificationPermission();

      if (!_isConfigured) {
        await initialize();
      }

      final service = FlutterBackgroundService();
      try {
        final isRunning = await service.isRunning();
        if (!isRunning) {
          final ok = await service.startService();
          if (!ok) {
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(
                _prefLastCheckStatus,
                'Background service failed to start',
              );
            } catch (_) {}
          }
        }
      } catch (serviceErr) {
        debugPrint('BackgroundLocationService startService error caught: $serviceErr');
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            _prefLastCheckStatus,
            'Background service error: $serviceErr',
          );
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('BackgroundLocationService startIfPermitted error: $e');
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _prefLastCheckStatus,
          'Background service error: $e',
        );
      } catch (_) {}
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
    // Note for iOS: Background execution intervals are managed by iOS power policy
    // and exact timing is not guaranteed by the OS.
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
        try {
          service.setAsForegroundService();
        } catch (_) {}
      });
      service.on('setAsBackground').listen((_) {
        try {
          service.setAsBackgroundService();
        } catch (_) {}
      });

      try {
        await service.setAsForegroundService();
      } catch (e) {
        debugPrint('Background isolate setAsForegroundService error: $e');
      }

      try {
        service.setForegroundNotificationInfo(
          title: 'FamilyTrack Location Active',
          content: 'Sharing your latest location with your group in the background.',
        );
      } catch (e) {
        debugPrint('Background isolate setForegroundNotificationInfo error: $e');
      }
    }

    service.on('stopService').listen((_) {
      try {
        service.stopSelf();
      } catch (_) {}
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

    // 3. Periodic timer every 3 minutes (AppConfig.locationCheckIntervalSeconds):
    // Verifies movement and sends stationary heartbeat (every 20 min)
    Timer.periodic(
      const Duration(seconds: AppConfig.locationCheckIntervalSeconds),
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
        // First send after joining or restarting service
        shouldSend = true;
      } else {
        final distanceMeters = Geolocator.distanceBetween(
          lastLat,
          lastLng,
          position.latitude,
          position.longitude,
        );
        final elapsedSeconds = (nowMs - lastSentAtMs) ~/ 1000;

        // If moved > 75 meters (MIN_MOVE_METERS)
        if (distanceMeters >= AppConfig.minMoveMeters) {
          shouldSend = true;
        } else if (elapsedSeconds >= AppConfig.heartbeatIntervalSeconds) {
          // Stationary heartbeat: > 20 minutes passed since last send
          shouldSend = true;
        } else {
          // Record skip status so user can verify check results on screen
          await prefs.setString(
            _prefLastCheckStatus,
            'skipped, moved ${distanceMeters.round()} m',
          );
        }
      }

      if (!shouldSend) return;

      final payload = QueuedLocationPayload(
        lat: position.latitude,
        lng: position.longitude,
        accuracy: position.accuracy,
      );

      String sendReason = 'sent (initial)';
      if (lastLat != null && lastLng != null) {
        final dist = Geolocator.distanceBetween(
          lastLat,
          lastLng,
          position.latitude,
          position.longitude,
        );
        if (dist >= AppConfig.minMoveMeters) {
          sendReason = 'sent, moved ${dist.round()} m';
        } else {
          sendReason = 'sent (heartbeat)';
        }
      }

      final sent = await _tryUpsertPayload(payload, prefs);
      if (sent) {
        await prefs.setDouble(_prefLastSentLat, payload.lat);
        await prefs.setDouble(_prefLastSentLng, payload.lng);
        await prefs.setInt(_prefLastSentAtMs, nowMs);
        await prefs.setString(_prefLastCheckStatus, sendReason);
        await prefs.remove(_prefPendingPayload);

        if (service is AndroidServiceInstance) {
          final now = DateTime.now().toLocal();
          final timeStr =
              '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
          service.setForegroundNotificationInfo(
            title: 'FamilyTrack Location Active',
            content: 'Last updated at $timeStr • $sendReason',
          );
        }
      } else {
        await prefs.setString(
          _prefLastCheckStatus,
          'offline, queued (${payload.accuracy.toStringAsFixed(0)}m accuracy)',
        );
        // Cache in offline queue if temporarily unreachable
        await prefs.setString(
          _prefPendingPayload,
          jsonEncode(payload.toJson()),
        );
      }
    } catch (e) {
      debugPrint('Background _handleNewPosition error: $e');
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

      // Method 1: Use SupabaseClient with Bearer JWT
      try {
        final client = SupabaseClient(
          AppConfig.supabaseUrl.trim(),
          AppConfig.supabaseAnonKey.trim(),
          headers: {
            if (accessToken != null && accessToken.isNotEmpty)
              'Authorization': 'Bearer $accessToken',
          },
        );

        if (refreshToken != null && refreshToken.isNotEmpty) {
          try {
            final authRes = await client.auth.setSession(refreshToken);
            final newSession = authRes.session;
            if (newSession != null) {
              await prefs.setString(_prefAccessToken, newSession.accessToken);
              if (newSession.refreshToken != null) {
                await prefs.setString(
                  _prefRefreshToken,
                  newSession.refreshToken!,
                );
              }
            }
          } catch (_) {}
        }

        await client.from('locations').upsert({
          'user_id': myUserId,
          'lat': payload.lat,
          'lng': payload.lng,
          'accuracy': payload.accuracy,
        }, onConflict: 'user_id');
        return true;
      } catch (clientErr) {
        debugPrint('SupabaseClient upsert attempt failed: $clientErr');
      }

      // Method 2: Resilient direct HTTP POST to PostgREST with token refresh
      return await _sendLocationHttpDirect(
        myUserId: myUserId,
        lat: payload.lat,
        lng: payload.lng,
        accuracy: payload.accuracy,
        accessToken: accessToken,
        refreshToken: refreshToken,
        prefs: prefs,
      );
    } catch (e) {
      debugPrint('Background _tryUpsertPayload uncaught error: $e');
      return false;
    }
  }

  /// Sends the location row directly to Supabase REST PostgREST endpoint
  /// (`/rest/v1/locations?on_conflict=user_id`) with exact Bearer authorization header
  /// and "Prefer: resolution=merge-duplicates,return=minimal".
  static Future<bool> _sendLocationHttpDirect({
    required String myUserId,
    required double lat,
    required double lng,
    required double accuracy,
    required String? accessToken,
    required String? refreshToken,
    required SharedPreferences prefs,
  }) async {
    final baseUrl = AppConfig.supabaseUrl.trim();
    final anonKey = AppConfig.supabaseAnonKey.trim();
    if (baseUrl.isEmpty || anonKey.isEmpty) return false;

    Future<int> doUpsert(String token) async {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      try {
        final uri = Uri.parse('$baseUrl/rest/v1/locations?on_conflict=user_id');
        final req = await client.postUrl(uri);
        req.headers.set('apikey', anonKey);
        req.headers.set('Authorization', 'Bearer $token');
        req.headers.set('Content-Type', 'application/json');
        req.headers.set('Prefer', 'resolution=merge-duplicates,return=minimal');
        req.write(jsonEncode({
          'user_id': myUserId,
          'lat': lat,
          'lng': lng,
          'accuracy': accuracy,
        }));
        final resp = await req.close();
        return resp.statusCode;
      } catch (_) {
        return 0;
      } finally {
        client.close();
      }
    }

    int status = 0;
    if (accessToken != null && accessToken.isNotEmpty) {
      status = await doUpsert(accessToken);
      if (status >= 200 && status < 300) return true;
    }

    // If token expired (401/403) or not yet sent, refresh via Supabase Auth REST
    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final lockMs = prefs.getInt(_prefRefreshLockMs) ?? 0;
        if (nowMs - lockMs < 12000) {
          // Another isolate is currently refreshing; pause and reload
          await Future.delayed(const Duration(milliseconds: 1200));
          await prefs.reload();
          final freshAccess = prefs.getString(_prefAccessToken);
          if (freshAccess != null && freshAccess.isNotEmpty) {
            final ok = await doUpsert(freshAccess);
            if (ok >= 200 && ok < 300) return true;
          }
        }

        await prefs.setInt(_prefRefreshLockMs, nowMs);

        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 15);
        final refreshUri =
            Uri.parse('$baseUrl/auth/v1/token?grant_type=refresh_token');
        final req = await client.postUrl(refreshUri);
        req.headers.set('apikey', anonKey);
        req.headers.set('Content-Type', 'application/json');
        req.write(jsonEncode({'refresh_token': refreshToken}));
        final resp = await req.close();
        final bodyStr = await resp.transform(utf8.decoder).join();
        client.close();

        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          final data = jsonDecode(bodyStr) as Map<String, dynamic>;
          final newAccess = data['access_token'] as String?;
          final newRefresh = data['refresh_token'] as String?;
          if (newAccess != null && newAccess.isNotEmpty) {
            await prefs.setString(_prefAccessToken, newAccess);
            if (newRefresh != null && newRefresh.isNotEmpty) {
              await prefs.setString(_prefRefreshToken, newRefresh);
            }
            final retryStatus = await doUpsert(newAccess);
            return retryStatus >= 200 && retryStatus < 300;
          }
        } else if (resp.statusCode == 400 || resp.statusCode == 401) {
          // Refresh token permanently invalid / revoked
          await prefs.setString(
            _prefLastCheckStatus,
            'Session expired. Please re-open the app to sign in.',
          );
        }
      } catch (e) {
        debugPrint('Direct REST token refresh error: $e');
      }
    }

    return false;
  }
}
