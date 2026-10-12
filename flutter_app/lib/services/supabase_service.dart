// lib/services/supabase_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../models/models.dart';

class SupabaseService {
  final SupabaseClient _client;
  final SharedPreferences _prefs;

  static const String _prefMyUserId = 'ft_my_user_id';
  static const String _prefAccessToken = 'ft_access_token';
  static const String _prefRefreshToken = 'ft_refresh_token';

  SupabaseService(this._client, this._prefs) {
    _initAuthListener();
  }

  void _initAuthListener() {
    _client.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      if (session != null) {
        _persistSessionTokens(session);
      }
    });
  }

  Future<void> _persistSessionTokens(Session session) async {
    try {
      await _prefs.setString(_prefMyUserId, session.user.id);
      if (session.accessToken.isNotEmpty) {
        await _prefs.setString(_prefAccessToken, session.accessToken);
      }
      final refresh = session.refreshToken;
      if (refresh != null && refresh.isNotEmpty) {
        await _prefs.setString(_prefRefreshToken, refresh);
      }
    } catch (_) {}
  }

  String? get currentUserId =>
      _client.auth.currentUser?.id ?? _prefs.getString(_prefMyUserId);

  /// On first launch or when needed, ensures a valid anonymous session exists.
  /// If the current session exists and is valid, returns the user ID and keeps the session.
  /// If the session is expired, refreshes it.
  /// If in-memory session is null, attempts recovery via saved refresh token.
  /// ONLY signs in anonymously if no session has ever been created on this device.
  Future<String> ensureAnonymousSession() async {
    final existing = _client.auth.currentSession;
    if (existing != null && !existing.isExpired && existing.user.id.isNotEmpty) {
      await _persistSessionTokens(existing);
      return existing.user.id;
    }

    if (existing != null && existing.isExpired) {
      try {
        final refreshRes = await _client.auth.refreshSession();
        final refreshedSession = refreshRes.session;
        if (refreshedSession != null) {
          await _persistSessionTokens(refreshedSession);
          return refreshedSession.user.id;
        }
      } catch (e) {
        debugPrint('Session refresh failed: $e');
      }
    }

    // Try recovering via saved refresh token from SharedPreferences
    final savedRefreshToken = _prefs.getString(_prefRefreshToken);
    if (savedRefreshToken != null && savedRefreshToken.isNotEmpty) {
      try {
        final authRes = await _client.auth.setSession(savedRefreshToken);
        final restoredSession = authRes.session;
        if (restoredSession != null) {
          await _persistSessionTokens(restoredSession);
          return restoredSession.user.id;
        }
      } catch (e) {
        debugPrint('setSession with saved refresh token failed: $e');
      }
    }

    // Only sign in anonymously if there is no user session saved yet
    final existingUserId = _prefs.getString(_prefMyUserId);
    if (existingUserId == null || existingUserId.isEmpty) {
      try {
        final response = await _client.auth.signInAnonymously();
        final session = response.session;
        if (session != null) {
          await _persistSessionTokens(session);
          return session.user.id;
        }
      } catch (e) {
        debugPrint('signInAnonymously failed: $e');
      }
    }

    final fallback = _client.auth.currentSession?.user.id ??
        _prefs.getString(_prefMyUserId);
    if (fallback != null && fallback.isNotEmpty) {
      return fallback;
    }

    throw Exception('unauthorized');
  }

  /// 1. Join: calls Edge Function "join_group" with body {code, display_name}.
  /// - Includes Bearer JWT token in Authorization header so the server can authenticate.
  /// - Normalizes Persian/Arabic digits, strips hyphens and spaces.
  /// - Returns JoinGroupResult with parsed summary or error code.
  Future<JoinGroupResult> joinGroup({
    required String rawCode,
    required String displayName,
  }) async {
    try {
      await ensureAnonymousSession();
    } catch (_) {
      return JoinGroupResult.failure('unauthorized');
    }

    final normalizedCode = AppConfig.normalizeGroupCode(rawCode);
    if (!AppConfig.isValidGroupCode(normalizedCode)) {
      return JoinGroupResult.failure('invalid_code');
    }

    final trimmedName = displayName.trim();
    if (trimmedName.isEmpty || trimmedName.length > 32) {
      return JoinGroupResult.failure('invalid_name');
    }

    return _invokeJoinEdgeFunction(
      normalizedCode: normalizedCode,
      displayName: trimmedName,
    );
  }

  /// Re-login helper when a user already joined a group earlier on this device:
  /// 1. Checks if current anonymous user_id already has a row in `public.members`.
  ///    If yes, immediately returns the group summary without calling join_group.
  /// 2. If not, invokes `join_group` once with the normalized credentials.
  Future<JoinGroupResult> loginWithExistingRole({
    required String rawCode,
    required String displayName,
  }) async {
    String userId;
    try {
      userId = await ensureAnonymousSession();
    } catch (_) {
      return JoinGroupResult.failure('unauthorized');
    }

    final normalizedCode = AppConfig.normalizeGroupCode(rawCode);
    if (!AppConfig.isValidGroupCode(normalizedCode)) {
      return JoinGroupResult.failure('invalid_code');
    }

    final trimmedName = displayName.trim();
    if (trimmedName.isEmpty || trimmedName.length > 32) {
      return JoinGroupResult.failure('invalid_name');
    }

    // Check if this user_id already has an active membership in public.members
    try {
      final existingRows = await _client
          .from('members')
          .select('group_id, user_id, display_name, color')
          .eq('user_id', userId);
      final list = existingRows as List<dynamic>;
      for (final item in list) {
        final map = item as Map<String, dynamic>;
        final existingName = (map['display_name'] as String? ?? '')
            .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
            .trim();
        if (existingName.toLowerCase() == trimmedName.toLowerCase()) {
          final gId = map['group_id'] as String;
          final groupInfo = await fetchGroupInfo(gId);
          return JoinGroupResult.success(
            GroupSummary(
              id: gId,
              maxDevices: groupInfo?.maxDevices ?? 4,
              expiresAt: groupInfo?.expiresAt ??
                  DateTime.now().add(const Duration(days: 30)),
              myDisplayName: trimmedName,
              myColor: (map['color'] as String?) ?? '#2563EB',
            ),
          );
        }
      }
    } catch (_) {}

    // Otherwise invoke join_group once
    return _invokeJoinEdgeFunction(
      normalizedCode: normalizedCode,
      displayName: trimmedName,
    );
  }

  Future<JoinGroupResult> _invokeJoinEdgeFunction({
    required String normalizedCode,
    required String displayName,
    bool isRetry = false,
  }) async {
    try {
      final session = _client.auth.currentSession;
      final accessToken = session?.accessToken ?? _prefs.getString(_prefAccessToken);

      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (accessToken != null && accessToken.isNotEmpty)
          'Authorization': 'Bearer $accessToken',
        if (AppConfig.supabaseAnonKey.isNotEmpty)
          'apikey': AppConfig.supabaseAnonKey,
      };

      final response = await _client.functions.invoke(
        'join_group',
        headers: headers,
        body: {
          'code': normalizedCode,
          'display_name': displayName,
        },
      );

      final Map<String, dynamic> data = _coerceMap(response.data);
      if (data['ok'] == true) {
        final cleanDisplayName =
            (data['display_name'] as String? ?? displayName)
                .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '');
        final summary = GroupSummary(
          id: (data['group_id'] as String?) ?? '',
          maxDevices: (data['max_devices'] as num?)?.toInt() ?? 4,
          expiresAt: DateTime.tryParse(data['expires_at'] as String? ?? '') ??
              DateTime.now().add(const Duration(days: 30)),
          myDisplayName: cleanDisplayName,
          myColor: (data['color'] as String?) ?? '#2563EB',
        );
        return JoinGroupResult.success(summary);
      }

      final errorCode = _extractErrorCode(data, null);
      if (errorCode == 'unauthorized' && !isRetry) {
        try {
          await ensureAnonymousSession();
          return _invokeJoinEdgeFunction(
            normalizedCode: normalizedCode,
            displayName: displayName,
            isRetry: true,
          );
        } catch (_) {}
      }

      return JoinGroupResult.failure(errorCode);
    } on FunctionException catch (e) {
      final Map<String, dynamic> details = _coerceMap(e.details);
      final errorCode = _extractErrorCode(details, e);

      if (errorCode == 'unauthorized' && !isRetry) {
        try {
          await ensureAnonymousSession();
          return _invokeJoinEdgeFunction(
            normalizedCode: normalizedCode,
            displayName: displayName,
            isRetry: true,
          );
        } catch (_) {}
      }

      return JoinGroupResult.failure(errorCode);
    } catch (e) {
      debugPrint('Unexpected join_group exception: $e');
      return JoinGroupResult.failure('server_error');
    }
  }

  String _extractErrorCode(Map<String, dynamic> data, FunctionException? fe) {
    if (data['error'] is String && (data['error'] as String).isNotEmpty) {
      return data['error'] as String;
    }
    if (data['message'] is String && (data['message'] as String).isNotEmpty) {
      final msg = (data['message'] as String).toLowerCase();
      for (final code in [
        'invalid_name',
        'too_many_attempts',
        'invalid_code',
        'group_expired',
        'group_full',
        'name_taken',
        'unauthorized',
        'bad_request',
      ]) {
        if (msg.contains(code)) return code;
      }
    }
    if (fe != null) {
      if (fe.status == 429) return 'too_many_attempts';
      if (fe.status == 401 || fe.status == 403) return 'unauthorized';
      if (fe.status == 400) return 'bad_request';
      if (fe.details is String) {
        final str = (fe.details as String).toLowerCase();
        for (final code in [
          'invalid_name',
          'too_many_attempts',
          'invalid_code',
          'group_expired',
          'group_full',
          'name_taken',
          'unauthorized',
          'bad_request',
        ]) {
          if (str.contains(code)) return code;
        }
      }
    }
    return 'server_error';
  }

  /// 2a. Group info:
  /// supabase.from('groups').select('id, max_devices, expires_at').eq('id', groupId)
  Future<GroupInfoRow?> fetchGroupInfo(String groupId) async {
    try {
      final rows = await _client
          .from('groups')
          .select('id, max_devices, expires_at')
          .eq('id', groupId);

      final list = rows as List<dynamic>;
      if (list.isEmpty) return null;
      return GroupInfoRow.fromJson(list.first as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// 2b. Members list:
  /// supabase.from('members').select('user_id, display_name, color').eq('group_id', groupId)
  Future<List<GroupMember>> fetchGroupMembers(String groupId) async {
    try {
      final rows = await _client
          .from('members')
          .select('user_id, display_name, color')
          .eq('group_id', groupId);

      return (rows as List<dynamic>).map((r) {
        final map = Map<String, dynamic>.from(r as Map);
        if (map['display_name'] is String) {
          map['display_name'] = (map['display_name'] as String)
              .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '');
        }
        return GroupMember.fromJson(map);
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  /// 3. Send my location:
  /// supabase.from('locations').upsert({'user_id': myUserId, 'lat': ..., 'lng': ..., 'accuracy': ...})
  /// Never send updated_at (the server sets it). Never select from public.locations.
  Future<void> upsertOwnLocation({
    required double lat,
    required double lng,
    required double accuracy,
  }) async {
    final myUserId = await ensureAnonymousSession();
    await _client.from('locations').upsert({
      'user_id': myUserId,
      'lat': lat,
      'lng': lng,
      'accuracy': accuracy,
    });
  }

  /// 4. Fetch others:
  /// supabase.rpc('fetch_locations', params: {'p_group_id': groupId, 'p_target_user_ids': [selected member ids]})
  /// Do NOT send a cooldown value; the server enforces it (currently 180 seconds).
  Future<FetchLocationsResult> fetchLocations({
    required String groupId,
    required List<String> targetUserIds,
  }) async {
    if (targetUserIds.isEmpty) {
      return FetchLocationsResult.success(
        cooldownSeconds: 0,
        locations: const [],
      );
    }

    try {
      final rawResponse = await _client.rpc(
        'fetch_locations',
        params: {
          'p_group_id': groupId,
          'p_target_user_ids': targetUserIds,
        },
      );

      final Map<String, dynamic> data = _coerceMap(rawResponse);
      if (data['ok'] == true) {
        final cooldownSeconds =
            (data['cooldown_seconds'] as num?)?.toInt() ?? 180;
        final rawList = (data['locations'] as List<dynamic>?) ?? const [];
        final locations = rawList.map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          if (map['display_name'] is String) {
            map['display_name'] = (map['display_name'] as String)
                .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '');
          }
          return MemberLocation.fromJson(map);
        }).toList();

        return FetchLocationsResult.success(
          cooldownSeconds: cooldownSeconds,
          locations: locations,
        );
      }

      final errorCode = (data['error'] as String?) ?? 'server_error';
      final remainingSeconds = (data['remaining_seconds'] as num?)?.toInt();
      return FetchLocationsResult.failure(
        errorCode: errorCode,
        remainingSeconds: remainingSeconds,
      );
    } catch (_) {
      return FetchLocationsResult.failure(errorCode: 'server_error');
    }
  }

  /// 5. Exit:
  /// supabase.rpc('leave_group', params: {'p_group_id': groupId})
  Future<void> leaveGroup(String groupId) async {
    await _client.rpc('leave_group', params: {'p_group_id': groupId});
  }

  Map<String, dynamic> _coerceMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return const {};
  }
}
