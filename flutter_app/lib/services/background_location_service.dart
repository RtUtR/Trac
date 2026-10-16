// lib/services/background_location_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../models/models.dart';

/// Background location service for FamilyTrack:
/// - Android: Runs as a Foreground Service of type "location" with a persistent notification.
/// - Two independent triggers using the SAME send function and the SAME persisted "last sent" record:
///   1. Movement trigger: Geolocator.getPositionStream with distanceFilter: 30.
///      If accuracy > 100 m: skipped (recorded).
///      If distance >= MIN_MOVE_METERS (75 m): sent immediately.
///   2. Time trigger: Timer.periodic(30 seconds) checking (now - lastSentTime) >= SEND_INTERVAL (180s).
///      If so, sends a fresh GPS fix even when stationary.
/// - A movement-triggered send automatically updates lastSentTime, resetting the 3-minute timer countdown.
/// - Every send attempt and every skipped movement check is recorded to SharedPreferences (last 20 logs).
class BackgroundLocationService {
  static const String _prefLastSentLat = 'bg_last_sent_lat';
  static const String _prefLastSentLng = 'bg_last_sent_lng';
  static const String _prefLastSentAtMs = 'bg_last_sent_at_ms';
  static const String _prefLastCheckStatus = 'bg_last_check_status';
  static const String _prefLocationLogs = 'bg_location_logs_json';
  static const String _prefMyUserId = 'ft_my_user_id';
  static const String _prefAccessToken = 'ft_access_token';
  static const String _prefRefreshToken = 'ft_refresh_token';
  static const String _prefRefreshLockMs = 'ft_refresh_lock_ms';

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
    } catch (e, stack) {
      debugPrint('BackgroundLocationService configure error: $e');
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefLastCheckStatus, 'Service config error: $e');
        await prefs.setString('ft_last_error_msg', 'Service config: $e');
        await prefs.setString('ft_last_error_stack', stack.toString());
        await prefs.setString(
          'ft_last_error_time',
          DateTime.now().toLocal().toIso8601String().substring(11, 19),
        );
      } catch (_) {}
    }
  }

  /// Configures and starts the foreground/background service ONLY after verifying that
  /// location services are enabled and runtime location permission is granted.
  static Future<bool> startIfPermitted() async {
    if (!AppConfig.isSupabaseConfigured) return false;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefLastCheckStatus, 'Location service turned off');
        return false;
      }

      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefLastCheckStatus, 'Location permission not granted');
        return false;
      }

      if (!_isConfigured) {
        await initialize();
      }

      final service = FlutterBackgroundService();
      try {
        final isRunning = await service.isRunning();
        if (!isRunning) {
          await service.startService();
        }
        return true;
      } catch (serviceErr, stack) {
        debugPrint('BackgroundLocationService startService error: $serviceErr');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefLastCheckStatus, 'Background start failed: $serviceErr');
        await prefs.setString('ft_last_error_msg', 'Background service start: $serviceErr');
        await prefs.setString('ft_last_error_stack', stack.toString());
        await prefs.setString(
          'ft_last_error_time',
          DateTime.now().toLocal().toIso8601String().substring(11, 19),
        );
        return false;
      }
    } catch (e, stack) {
      debugPrint('BackgroundLocationService startIfPermitted error: $e');
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefLastCheckStatus, 'Background start error: $e');
        await prefs.setString('ft_last_error_msg', 'Background start: $e');
        await prefs.setString('ft_last_error_stack', stack.toString());
        await prefs.setString(
          'ft_last_error_time',
          DateTime.now().toLocal().toIso8601String().substring(11, 19),
        );
      } catch (_) {}
      return false;
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
      await _handleTimeTrigger(service);
    } catch (_) {}
    return true;
  }

  @pragma('vm:entry-point')
  static void onBackgroundStart(ServiceInstance service) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      DartPluginRegistrant.ensureInitialized();
    } catch (_) {}

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
        debugPrint('setAsForegroundService error: $e');
      }

      try {
        service.setForegroundNotificationInfo(
          title: 'FamilyTrack Location Active',
          content: 'Sharing your latest location with your group in the background.',
        );
      } catch (e) {
        debugPrint('setForegroundNotificationInfo error: $e');
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

    // Trigger immediate send if no last sent record exists
    unawaited(_handleTimeTrigger(service));

    // 1. Movement trigger:
    // Listen to Geolocator.getPositionStream with AndroidSettings(accuracy: LocationAccuracy.high, distanceFilter: 30, forceLocationManager: true).
    try {
      final LocationSettings locationSettings;
      if (defaultTargetPlatform == TargetPlatform.android) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 30,
          forceLocationManager: true,
        );
      } else {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 30,
        );
      }

      Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (position) async {
          try {
            await _handleMovementFix(position, service);
          } catch (e) {
            debugPrint('Movement stream error: $e');
          }
        },
        onError: (err) {
          debugPrint('Background location stream error: $err');
        },
      );
    } catch (e) {
      debugPrint('getPositionStream subscription failed: $e');
    }

    // 2. Time trigger:
    // Timer.periodic(30 seconds) that checks (now - lastSentTime) >= SEND_INTERVAL (180 seconds).
    Timer.periodic(const Duration(seconds: 30), (_) async {
      try {
        await _handleTimeTrigger(service);
      } catch (e) {
        debugPrint('Periodic time trigger error: $e');
      }
    });
  }

  /// Evaluates whether a location fix should be sent to the server:
  /// 1. If accuracy > 100m: ignores fix (records poor accuracy reason).
  /// 2. If no last-sent record exists: sends initial fix to establish baseline.
  /// 3. Computes distance between last successfully sent location and current location.
  /// 4. If distance >= MIN_MOVE_METERS (75m): automatically sends new location to server.
  /// 5. If distance < 75m: does NOT send anything (records skipped log).
  static Future<void> _evaluateAndSendIfMoved({
    required Position position,
    required String triggerSource,
    ServiceInstance? service,
    SharedPreferences? prefs,
  }) async {
    final p = prefs ?? await SharedPreferences.getInstance();
    await p.reload();

    // Ignore fixes with accuracy worse than 100 m (record the reason)
    if (position.accuracy > 100.0) {
      await _recordLog(
        prefs: p,
        lat: position.latitude,
        lng: position.longitude,
        accuracy: position.accuracy,
        distance: null,
        decision:
            'skipped: accuracy ${position.accuracy.toStringAsFixed(1)}m > 100m',
        method: 'none',
        statusOrError: 'poor_accuracy',
      );
      return;
    }

    final lastLat = p.getDouble(_prefLastSentLat);
    final lastLng = p.getDouble(_prefLastSentLng);
    final lastSentAtMs = p.getInt(_prefLastSentAtMs);

    // If there is no last-sent record: send initial position
    if (lastLat == null || lastLng == null || lastSentAtMs == null) {
      await _sendPosition(
        position: position,
        decision: 'sent: first fix ($triggerSource)',
        distance: null,
        service: service,
        prefs: p,
      );
      return;
    }

    // Calculate distance between last successfully sent location and current location
    final distance = Geolocator.distanceBetween(
      lastLat,
      lastLng,
      position.latitude,
      position.longitude,
    );

    // If the distance is 75 meters or more, automatically send the new location to the server
    if (distance >= AppConfig.MIN_MOVE_METERS) {
      await _sendPosition(
        position: position,
        decision:
            'sent: moved ${distance.round()}m (>= ${AppConfig.MIN_MOVE_METERS.round()}m)',
        distance: distance,
        service: service,
        prefs: p,
      );
    } else {
      // If the distance is less than 75 meters, do not send anything
      await _recordLog(
        prefs: p,
        lat: position.latitude,
        lng: position.longitude,
        accuracy: position.accuracy,
        distance: distance,
        decision:
            'skipped: moved ${distance.round()}m (< ${AppConfig.MIN_MOVE_METERS.round()}m)',
        method: 'none',
        statusOrError: 'n/a',
      );
    }
  }

  /// Trigger 1: Movement check
  static Future<void> _handleMovementFix(
    Position position,
    ServiceInstance? service,
  ) async {
    await _evaluateAndSendIfMoved(
      position: position,
      triggerSource: 'movement stream',
      service: service,
    );
  }

  /// Trigger 2: Periodic distance check
  /// Checks distance between last successfully sent location and current location.
  /// If distance >= 75 meters, sends to server.
  /// If distance < 75 meters, does NOT send anything.
  static Future<void> _handleTimeTrigger(ServiceInstance? service) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        return;
      }

      final position = await _getCurrentPositionSafe();
      if (position == null) return;

      await _evaluateAndSendIfMoved(
        position: position,
        triggerSource: 'periodic check',
        service: service,
        prefs: prefs,
      );
    } catch (e) {
      debugPrint('Periodic check error: $e');
    }
  }

  /// Evaluates current position and sends ONLY if moved >= 75m or initial fix.
  /// If moved < 75m, does NOT send anything.
  static Future<bool> sendIfMoved({
    required String reason,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;

      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        return false;
      }

      final position = await _getCurrentPositionSafe();
      if (position == null) return false;

      if (position.accuracy > 100.0) {
        await _recordLog(
          prefs: prefs,
          lat: position.latitude,
          lng: position.longitude,
          accuracy: position.accuracy,
          distance: null,
          decision:
              'skipped: accuracy ${position.accuracy.toStringAsFixed(1)}m > 100m',
          method: 'none',
          statusOrError: 'poor_accuracy',
        );
        return false;
      }

      final lastLat = prefs.getDouble(_prefLastSentLat);
      final lastLng = prefs.getDouble(_prefLastSentLng);
      final lastSentAtMs = prefs.getInt(_prefLastSentAtMs);

      if (lastLat == null || lastLng == null || lastSentAtMs == null) {
        return await _sendPosition(
          position: position,
          decision: 'sent: initial fix ($reason)',
          distance: null,
          prefs: prefs,
        );
      }

      final distance = Geolocator.distanceBetween(
        lastLat,
        lastLng,
        position.latitude,
        position.longitude,
      );

      if (distance >= AppConfig.MIN_MOVE_METERS) {
        return await _sendPosition(
          position: position,
          decision:
              'sent: moved ${distance.round()}m (>= ${AppConfig.MIN_MOVE_METERS.round()}m)',
          distance: distance,
          prefs: prefs,
        );
      } else {
        await _recordLog(
          prefs: prefs,
          lat: position.latitude,
          lng: position.longitude,
          accuracy: position.accuracy,
          distance: distance,
          decision:
              'skipped: moved ${distance.round()}m (< ${AppConfig.MIN_MOVE_METERS.round()}m)',
          method: 'none',
          statusOrError: 'n/a',
        );
        return false;
      }
    } catch (e) {
      debugPrint('sendIfMoved error: $e');
      return false;
    }
  }

  /// Sends a fresh device GPS fix immediately from foreground (e.g. Refresh button in UI).
  /// EXCEPTION: The location must be sent to the server immediately, regardless of the distance moved.
  /// using the EXACT SAME send function and updating the SAME persisted "last sent" record.
  static Future<bool> sendImmediateFix({
    required String reason,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await _recordLog(
          prefs: prefs,
          lat: null,
          lng: null,
          accuracy: null,
          distance: null,
          decision: 'failed: location service disabled',
          method: 'none',
          statusOrError: 'disabled',
        );
        return false;
      }

      final position = await _getCurrentPositionSafe();
      if (position == null) {
        await _recordLog(
          prefs: prefs,
          lat: null,
          lng: null,
          accuracy: null,
          distance: null,
          decision: 'failed: GPS fix unavailable',
          method: 'none',
          statusOrError: 'no_fix',
        );
        return false;
      }

      final lastLat = prefs.getDouble(_prefLastSentLat);
      final lastLng = prefs.getDouble(_prefLastSentLng);
      double? distance;
      if (lastLat != null && lastLng != null) {
        distance = Geolocator.distanceBetween(
          lastLat,
          lastLng,
          position.latitude,
          position.longitude,
        );
      }

      return await _sendPosition(
        position: position,
        decision: reason,
        distance: distance,
        prefs: prefs,
      );
    } catch (e) {
      debugPrint('sendImmediateFix error: $e');
      return false;
    }
  }

  /// THE SINGLE SEND FUNCTION:
  /// Upserts position into public.locations. Updates persisted "last sent" record ONLY upon successful upsert.
  /// Writes log entry to SharedPreferences (keeping last 20).
  static Future<bool> _sendPosition({
    required Position position,
    required String decision,
    double? distance,
    ServiceInstance? service,
    SharedPreferences? prefs,
  }) async {
    final p = prefs ?? await SharedPreferences.getInstance();
    await p.reload();

    final myUserId = p.getString(_prefMyUserId);
    final accessToken = p.getString(_prefAccessToken);
    final refreshToken = p.getString(_prefRefreshToken);

    if (myUserId == null || myUserId.isEmpty) {
      await _recordLog(
        prefs: p,
        lat: position.latitude,
        lng: position.longitude,
        accuracy: position.accuracy,
        distance: distance,
        decision: 'failed: no user id',
        method: 'none',
        statusOrError: 'unauthorized',
      );
      return false;
    }

    String methodUsed = 'Supabase client';
    String statusOrError = '';
    bool success = false;

    // Method 1: Supabase client
    try {
      final client = SupabaseClient(
        AppConfig.supabaseUrl.trim(),
        AppConfig.supabaseAnonKey.trim(),
        headers: {
          if (accessToken != null && accessToken.isNotEmpty)
            'Authorization': 'Bearer $accessToken',
        },
      );

      await client.from('locations').upsert({
        'user_id': myUserId,
        'lat': position.latitude,
        'lng': position.longitude,
        'accuracy': position.accuracy,
      }, onConflict: 'user_id');

      success = true;
      statusOrError = '201';
    } catch (clientErr) {
      debugPrint('Method 1 Supabase client upsert error: $clientErr');
      statusOrError = clientErr.toString();
    }

    // Method 2: Direct REST fallback with token refresh
    if (!success) {
      methodUsed = 'REST fallback';
      final restResult = await _sendLocationHttpDirect(
        myUserId: myUserId,
        lat: position.latitude,
        lng: position.longitude,
        accuracy: position.accuracy,
        accessToken: accessToken,
        refreshToken: refreshToken,
        prefs: p,
      );

      success = restResult.success;
      statusOrError = restResult.statusOrError;
    }

    // Write record to last 20 logs
    await _recordLog(
      prefs: p,
      lat: position.latitude,
      lng: position.longitude,
      accuracy: position.accuracy,
      distance: distance,
      decision: success ? decision : '$decision failed',
      method: methodUsed,
      statusOrError: statusOrError,
    );

    // Persisted "last sent" record is updated ONLY AFTER a successful upsert
    if (success) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      await p.setDouble(_prefLastSentLat, position.latitude);
      await p.setDouble(_prefLastSentLng, position.longitude);
      await p.setInt(_prefLastSentAtMs, nowMs);

      if (service is AndroidServiceInstance) {
        final now = DateTime.now().toLocal();
        final timeStr =
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
        try {
          service.setForegroundNotificationInfo(
            title: 'FamilyTrack Location Active',
            content: 'Last updated at $timeStr • $decision',
          );
        } catch (_) {}
      }
    }

    return success;
  }

  static Future<Position?> _getCurrentPositionSafe() async {
    try {
      final LocationSettings settings;
      if (defaultTargetPlatform == TargetPlatform.android) {
        settings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          forceLocationManager: true,
          timeLimit: const Duration(seconds: 15),
        );
      } else {
        settings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        );
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: settings,
      );
    } catch (_) {
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
  }

  /// Writes a log record to shared_preferences, keeping the last 20.
  static Future<void> _recordLog({
    required SharedPreferences prefs,
    required double? lat,
    required double? lng,
    required double? accuracy,
    required double? distance,
    required String decision,
    required String method,
    required String statusOrError,
  }) async {
    try {
      final now = DateTime.now().toLocal();
      final timeStr =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

      final Map<String, dynamic> entry = {
        'time': timeStr,
        'lat': lat != null ? double.parse(lat.toStringAsFixed(6)) : null,
        'lng': lng != null ? double.parse(lng.toStringAsFixed(6)) : null,
        'accuracy': accuracy != null ? double.parse(accuracy.toStringAsFixed(1)) : null,
        'distance': distance != null ? double.parse(distance.toStringAsFixed(1)) : null,
        'decision': decision,
        'method': method,
        'status': statusOrError,
      };

      final raw = prefs.getString(_prefLocationLogs);
      List<dynamic> logs = [];
      if (raw != null && raw.isNotEmpty) {
        try {
          logs = jsonDecode(raw) as List<dynamic>;
        } catch (_) {}
      }
      logs.insert(0, entry);
      if (logs.length > 20) {
        logs = logs.sublist(0, 20);
      }
      await prefs.setString(_prefLocationLogs, jsonEncode(logs));
      await prefs.setString(_prefLastCheckStatus, decision);
    } catch (e) {
      debugPrint('Error recording location log: $e');
    }
  }

  static Future<_RestSendResult> _sendLocationHttpDirect({
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
    if (baseUrl.isEmpty || anonKey.isEmpty) {
      return _RestSendResult(false, 'missing_config');
    }

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
      } catch (e) {
        return 0;
      } finally {
        client.close();
      }
    }

    int status = 0;
    if (accessToken != null && accessToken.isNotEmpty) {
      status = await doUpsert(accessToken);
      if (status >= 200 && status < 300) {
        return _RestSendResult(true, '$status');
      }
    }

    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
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
            if (retryStatus >= 200 && retryStatus < 300) {
              return _RestSendResult(true, '$retryStatus (refreshed)');
            }
            return _RestSendResult(false, 'HTTP $retryStatus');
          }
        }
        return _RestSendResult(false, 'refresh_failed_${resp.statusCode}');
      } catch (e) {
        return _RestSendResult(false, 'refresh_error: $e');
      }
    }

    return _RestSendResult(false, status > 0 ? 'HTTP $status' : 'network_error');
  }
}

class _RestSendResult {
  final bool success;
  final String statusOrError;

  _RestSendResult(this.success, this.statusOrError);
}
