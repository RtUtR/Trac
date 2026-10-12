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

    try {
      final response = await _client.functions.invoke(
        'join_group',
        body: {
          'code': normalizedCode,
          'display_name': trimmedName,
        },
      );

      final Map<String, dynamic> data = _coerceMap(response.data);
      if (data['ok'] == true) {
        final summary = GroupSummary(
          id: data['group_id'] as String,
          maxDevices: (data['max_devices'] as num).toInt(),
          expiresAt: DateTime.parse(data['expires_at'] as String),
          myDisplayName: data['display_name'] as String,
          myColor: data['color'] as String,
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
    final rows = await _client
        .from('groups')
        .select('id, max_devices, expires_at')
        .eq('id', groupId);

    final list = rows as List<dynamic>;
    if (list.isEmpty) return null;
    return GroupInfoRow.fromJson(list.first as Map<String, dynamic>);
  }

  /// 2b. Members list:
  /// supabase.from('members').select('user_id, display_name, color').eq('group_id', groupId)
  Future<List<GroupMember>> fetchGroupMembers(String groupId) async {
    final rows = await _client
        .from('members')
        .select('user_id, display_name, color')
        .eq('group_id', groupId);

    return (rows as List<dynamic>)
        .map((r) => GroupMember.fromJson(r as Map<String, dynamic>))
        .toList();
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
        final locations = rawList
            .map((item) => MemberLocation.fromJson(item as Map<String, dynamic>))
            .toList();

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
