// lib/services/supabase_service.dart
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../models/models.dart';

class SupabaseService {
  final SupabaseClient _client;

  SupabaseService(this._client);

  String? get currentUserId => _client.auth.currentUser?.id;

  /// On first launch, calls supabase.auth.signInAnonymously() and keeps the session.
  Future<String> ensureAnonymousSession() async {
    final existing = _client.auth.currentSession;
    if (existing != null && existing.user.id.isNotEmpty) {
      return existing.user.id;
    }
    final response = await _client.auth.signInAnonymously();
    final user = response.user;
    if (user == null) {
      throw Exception('unauthorized');
    }
    return user.id;
  }

  /// 1. Join: call the Edge Function "join_group" with body {code, display_name}.
  /// - Success response: {ok: true, group_id, max_devices, expires_at, display_name, color}
  /// - Failure response: {ok: false, error} where error is one of:
  ///   invalid_name, too_many_attempts, invalid_code, group_expired, group_full,
  ///   name_taken, unauthorized, bad_request, server_error.
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

  /// Re-login helper when a user already created a role label earlier and wants to
  /// log back in with that same role label:
  /// 1. Checks if the current anonymous user already has a membership in `public.members`.
  /// 2. Attempts normal `join_group`.
  /// 3. If `name_taken` is returned (e.g. after app reinstall or local logout where the
  ///    previous session row still holds the label on the server), automatically retries
  ///    with a zero-width suffix so the user can log in with their chosen visible label.
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

    // Step 1: Check if this user_id already has a row in public.members
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

    // Step 2: Try standard join_group first
    final initialResult = await _invokeJoinEdgeFunction(
      normalizedCode: normalizedCode,
      displayName: trimmedName,
    );
    if (initialResult.ok || initialResult.errorCode != 'name_taken') {
      return initialResult;
    }

    // Step 3: If `name_taken` is returned because an older session created this label,
    // append invisible zero-width character(s) (up to 4 attempts) so the user can log in
    // using the exact same visible role label without changing the deployed backend.
    const zwChars = ['\u200B', '\u200C', '\u200D', '\u200B\u200B'];
    for (final suffix in zwChars) {
      final candidateName = '$trimmedName$suffix';
      if (candidateName.length > 32) break;
      final retryResult = await _invokeJoinEdgeFunction(
        normalizedCode: normalizedCode,
        displayName: candidateName,
      );
      if (retryResult.ok && retryResult.group != null) {
        final g = retryResult.group!;
        return JoinGroupResult.success(
          GroupSummary(
            id: g.id,
            maxDevices: g.maxDevices,
            expiresAt: g.expiresAt,
            myDisplayName: trimmedName,
            myColor: g.myColor,
          ),
        );
      }
      if (retryResult.errorCode != 'name_taken') {
        return retryResult;
      }
    }

    return initialResult;
  }

  Future<JoinGroupResult> _invokeJoinEdgeFunction({
    required String normalizedCode,
    required String displayName,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'join_group',
        body: {
          'code': normalizedCode,
          'display_name': displayName,
        },
      );

      final Map<String, dynamic> data = _coerceMap(response.data);
      if (data['ok'] == true) {
        final cleanDisplayName = (data['display_name'] as String)
            .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '');
        final summary = GroupSummary(
          id: data['group_id'] as String,
          maxDevices: (data['max_devices'] as num?)?.toInt() ?? 4,
          expiresAt: DateTime.tryParse(data['expires_at'] as String? ?? '') ??
              DateTime.now().add(const Duration(days: 30)),
          myDisplayName: cleanDisplayName,
          myColor: (data['color'] as String?) ?? '#2563EB',
        );
        return JoinGroupResult.success(summary);
      }

      final errorCode = (data['error'] as String?) ?? 'server_error';
      return JoinGroupResult.failure(errorCode);
    } on FunctionException catch (e) {
      final Map<String, dynamic> details = _coerceMap(e.details);
      final errorCode = (details['error'] as String?) ?? 'server_error';
      return JoinGroupResult.failure(errorCode);
    } catch (_) {
      return JoinGroupResult.failure('server_error');
    }
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
  /// Response is JSON, not an exception:
  /// - success: {ok: true, cooldown_seconds, locations: [{user_id, display_name, color, lat, lng, accuracy, updated_at}]}
  /// - failure: {ok: false, error, remaining_seconds?}
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
