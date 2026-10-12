// lib/providers/app_providers.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../models/models.dart';
import '../services/background_location_service.dart';
import '../services/supabase_service.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Initialized in main.dart ProviderScope override');
});

final supabaseServiceProvider = Provider<SupabaseService>((ref) {
  return SupabaseService(Supabase.instance.client);
});

class AppState {
  final bool consentAccepted;
  final bool locationPermissionGranted;
  final GroupSummary? activeGroup;
  final List<GroupMember> groupMembers;
  final Set<String> followedUserIds;
  final List<MemberLocation> cachedLocations;
  final int cooldownRemainingSeconds;
  final MapStyleOption? userSelectedMapStyle;
  final bool isLoading;
  final String? errorCode;

  const AppState({
    required this.consentAccepted,
    required this.locationPermissionGranted,
    this.activeGroup,
    this.groupMembers = const [],
    this.followedUserIds = const {},
    this.cachedLocations = const [],
    this.cooldownRemainingSeconds = 0,
    this.userSelectedMapStyle,
    this.isLoading = false,
    this.errorCode,
  });

  /// Default: Positron in light app theme, Dark in dark app theme, until the user picks one.
  MapStyleOption effectiveMapStyle(Brightness platformBrightness) {
    if (userSelectedMapStyle != null) return userSelectedMapStyle!;
    return platformBrightness == Brightness.dark
        ? MapStyleOption.dark
        : MapStyleOption.positron;
  }

  AppState copyWith({
    bool? consentAccepted,
    bool? locationPermissionGranted,
    GroupSummary? activeGroup,
    bool clearActiveGroup = false,
    List<GroupMember>? groupMembers,
    Set<String>? followedUserIds,
    List<MemberLocation>? cachedLocations,
    int? cooldownRemainingSeconds,
    MapStyleOption? userSelectedMapStyle,
    bool? isLoading,
    String? errorCode,
    bool clearErrorCode = false,
  }) {
    return AppState(
      consentAccepted: consentAccepted ?? this.consentAccepted,
      locationPermissionGranted:
          locationPermissionGranted ?? this.locationPermissionGranted,
      activeGroup: clearActiveGroup ? null : (activeGroup ?? this.activeGroup),
      groupMembers: groupMembers ?? this.groupMembers,
      followedUserIds: followedUserIds ?? this.followedUserIds,
      cachedLocations: cachedLocations ?? this.cachedLocations,
      cooldownRemainingSeconds:
          cooldownRemainingSeconds ?? this.cooldownRemainingSeconds,
      userSelectedMapStyle: userSelectedMapStyle ?? this.userSelectedMapStyle,
      isLoading: isLoading ?? this.isLoading,
      errorCode: clearErrorCode ? null : (errorCode ?? this.errorCode),
    );
  }
}

class AppController extends StateNotifier<AppState> {
  final SharedPreferences _prefs;
  final SupabaseService _supabase;
  Timer? _cooldownTimer;

  static const _prefConsent = 'ft_consent_accepted';
  static const _prefMapStyle = 'ft_map_style';
  static const _prefGroupId = 'ft_group_id';
  static const _prefMyDisplayName = 'ft_my_display_name';
  static const _prefMyColor = 'ft_my_color';

  AppController(this._prefs, this._supabase)
      : super(
          AppState(
            consentAccepted: _prefs.getBool(_prefConsent) ?? false,
            locationPermissionGranted: false,
            userSelectedMapStyle: _parseStyle(_prefs.getString(_prefMapStyle)),
          ),
        ) {
    _bootstrap();
  }

  static MapStyleOption? _parseStyle(String? raw) {
    if (raw == null) return null;
    for (final s in MapStyleOption.values) {
      if (s.name == raw) return s;
    }
    return null;
  }

  Future<void> _bootstrap() async {
    await refreshPermissionStatus();

    // Ensure Anonymous Auth session on first launch and keep the session
    try {
      await _supabase.ensureAnonymousSession();
    } catch (_) {}

    if (!state.consentAccepted) return;

    final savedGroupId = _prefs.getString(_prefGroupId);
    final savedDisplayName = _prefs.getString(_prefMyDisplayName);
    final savedColor = _prefs.getString(_prefMyColor);

    if (savedGroupId == null ||
        savedDisplayName == null ||
        savedColor == null) {
      return;
    }

    state = state.copyWith(isLoading: true, clearErrorCode: true);
    try {
      // Check group info: supabase.from('groups').select('id, max_devices, expires_at').eq('id', groupId)
      final groupInfo = await _supabase.fetchGroupInfo(savedGroupId);
      if (groupInfo == null || groupInfo.isExpired) {
        await _clearLocalGroupData(savedGroupId);
        state = state.copyWith(
          isLoading: false,
          clearActiveGroup: true,
          errorCode: 'group_expired',
        );
        return;
      }

      final summary = GroupSummary(
        id: groupInfo.id,
        maxDevices: groupInfo.maxDevices,
        expiresAt: groupInfo.expiresAt,
        myDisplayName: savedDisplayName,
        myColor: savedColor,
      );

      await _activateGroupSession(summary);
      await BackgroundLocationService.startIfPermitted();
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> refreshPermissionStatus() async {
    final serviceOn = await Geolocator.isLocationServiceEnabled();
    final perm = await Geolocator.checkPermission();
    final granted = serviceOn &&
        (perm == LocationPermission.always ||
            perm == LocationPermission.whileInUse);
    state = state.copyWith(locationPermissionGranted: granted);
  }

  Future<void> acceptConsentAndRequestPermissions() async {
    await _prefs.setBool(_prefConsent, true);

    try {
      await _supabase.ensureAnonymousSession();
    } catch (_) {}

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.whileInUse) {
      perm = await Geolocator.requestPermission();
    }

    await refreshPermissionStatus();
    state = state.copyWith(consentAccepted: true);

    if (state.locationPermissionGranted) {
      await BackgroundLocationService.startIfPermitted();
    }
  }

  /// 1. Join via Edge Function "join_group" with body {code, display_name}.
  /// After success save group_id, my display_name and color locally.
  Future<bool> joinGroup({
    required String code,
    required String displayName,
  }) async {
    state = state.copyWith(isLoading: true, clearErrorCode: true);

    final result = await _supabase.joinGroup(
      rawCode: code,
      displayName: displayName,
    );

    if (!result.ok || result.group == null) {
      state = state.copyWith(
        isLoading: false,
        errorCode: result.errorCode ?? 'server_error',
      );
      return false;
    }

    final group = result.group!;
    // Save group_id, my display_name, and color locally
    await _prefs.setString(_prefGroupId, group.id);
    await _prefs.setString(_prefMyDisplayName, group.myDisplayName);
    await _prefs.setString(_prefMyColor, group.myColor);

    await _sendImmediateOwnPosition();
    await _activateGroupSession(group);
    await BackgroundLocationService.startIfPermitted();
    return true;
  }

  Future<void> _activateGroupSession(GroupSummary group) async {
    // 2. Fetch group info & check expiry
    final groupInfo = await _supabase.fetchGroupInfo(group.id);
    if (groupInfo == null || groupInfo.isExpired) {
      await _clearLocalGroupData(group.id);
      state = state.copyWith(
        clearActiveGroup: true,
        isLoading: false,
        errorCode: 'group_expired',
      );
      return;
    }

    // 2. Members list: supabase.from('members').select('user_id, display_name, color').eq('group_id', groupId)
    final members = await _supabase.fetchGroupMembers(group.id);

    final savedFollowed =
        _prefs.getStringList('ft_followed_${group.id}')?.toSet() ??
            members.map((m) => m.userId).toSet();

    final cachedRaw = _prefs.getString('ft_cached_locs_${group.id}');
    List<MemberLocation> cached = [];
    if (cachedRaw != null) {
      try {
        final decoded = jsonDecode(cachedRaw) as List<dynamic>;
        cached = decoded
            .map((e) => MemberLocation.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }

    final cooldownUntilMs = _prefs.getInt('ft_cooldown_until_${group.id}') ?? 0;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final remaining = ((cooldownUntilMs - nowMs) / 1000).ceil().clamp(0, 86400);

    state = state.copyWith(
      activeGroup: group,
      groupMembers: members,
      followedUserIds: savedFollowed,
      cachedLocations: cached,
      cooldownRemainingSeconds: remaining,
      isLoading: false,
      clearErrorCode: true,
    );

    if (remaining > 0) {
      _startCooldownTicker(group.id, remaining);
    } else {
      await fetchFollowedLocations();
    }
  }

  Future<void> refreshGroupMembers() async {
    final group = state.activeGroup;
    if (group == null) return;
    try {
      final members = await _supabase.fetchGroupMembers(group.id);
      state = state.copyWith(groupMembers: members);
    } catch (_) {}
  }

  Future<void> toggleFollowedMember(String userId) async {
    final group = state.activeGroup;
    if (group == null) return;

    final updated = Set<String>.from(state.followedUserIds);
    if (updated.contains(userId)) {
      updated.remove(userId);
    } else {
      updated.add(userId);
    }

    await _prefs.setStringList('ft_followed_${group.id}', updated.toList());
    state = state.copyWith(followedUserIds: updated);
  }

  Future<void> setMapStyle(MapStyleOption style) async {
    await _prefs.setString(_prefMapStyle, style.name);
    state = state.copyWith(userSelectedMapStyle: style);
  }

  /// 4. Fetch others via RPC `fetch_locations(p_group_id, p_target_user_ids)`.
  /// Server enforces cooldown (currently 180s) and returns JSON `{ok: ...}`.
  Future<void> fetchFollowedLocations() async {
    final group = state.activeGroup;
    if (group == null) return;
    if (state.cooldownRemainingSeconds > 0) return;

    final targets = state.followedUserIds.toList();
    if (targets.isEmpty) return;

    state = state.copyWith(isLoading: true, clearErrorCode: true);

    await _sendImmediateOwnPosition();

    final result = await _supabase.fetchLocations(
      groupId: group.id,
      targetUserIds: targets,
    );

    if (result.ok) {
      final cooldownSec = result.cooldownSeconds ?? 180;
      await _prefs.setString(
        'ft_cached_locs_${group.id}',
        jsonEncode(result.locations.map((l) => l.toJson()).toList()),
      );

      if (cooldownSec > 0) {
        _startCooldownTicker(group.id, cooldownSec);
      }

      state = state.copyWith(
        cachedLocations: result.locations,
        cooldownRemainingSeconds: cooldownSec,
        isLoading: false,
      );
      return;
    }

    // Handle JSON failure {ok: false, error, remaining_seconds?}
    final err = result.errorCode ?? 'server_error';
    if (err == 'cooldown_active') {
      final rem = result.remainingSeconds ?? 180;
      _startCooldownTicker(group.id, rem);
      state = state.copyWith(
        cooldownRemainingSeconds: rem,
        isLoading: false,
      );
      return;
    }

    if (err == 'group_expired' ||
        err == 'not_a_member' ||
        err == 'not_authenticated') {
      await _clearLocalGroupData(group.id);
      state = state.copyWith(
        clearActiveGroup: true,
        cachedLocations: [],
        groupMembers: [],
        cooldownRemainingSeconds: 0,
        isLoading: false,
        errorCode: err,
      );
      return;
    }

    state = state.copyWith(
      isLoading: false,
      errorCode: err,
    );
  }

  Future<void> _sendImmediateOwnPosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
      await _supabase.upsertOwnLocation(
        lat: pos.latitude,
        lng: pos.longitude,
        accuracy: pos.accuracy,
      );
    } catch (_) {}
  }

  void _startCooldownTicker(String groupId, int seconds) {
    _cooldownTimer?.cancel();
    final untilMs = DateTime.now().millisecondsSinceEpoch + (seconds * 1000);
    _prefs.setInt('ft_cooldown_until_$groupId', untilMs);

    state = state.copyWith(cooldownRemainingSeconds: seconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final rem =
          ((untilMs - DateTime.now().millisecondsSinceEpoch) / 1000).ceil();
      if (rem <= 0) {
        timer.cancel();
        state = state.copyWith(cooldownRemainingSeconds: 0);
      } else {
        state = state.copyWith(cooldownRemainingSeconds: rem);
      }
    });
  }

  /// 5. Exit: supabase.rpc('leave_group', params: {'p_group_id': groupId}),
  /// clear local data, go to the login screen.
  Future<void> exitCurrentGroup() async {
    final group = state.activeGroup;
    if (group == null) return;

    state = state.copyWith(isLoading: true);
    try {
      await _supabase.leaveGroup(group.id);
    } catch (_) {}

    await _clearLocalGroupData(group.id);
    await BackgroundLocationService.stop();

    state = state.copyWith(
      clearActiveGroup: true,
      cachedLocations: [],
      groupMembers: [],
      followedUserIds: {},
      cooldownRemainingSeconds: 0,
      isLoading: false,
      clearErrorCode: true,
    );
  }

  Future<void> _clearLocalGroupData(String groupId) async {
    _cooldownTimer?.cancel();
    await _prefs.remove(_prefGroupId);
    await _prefs.remove(_prefMyDisplayName);
    await _prefs.remove(_prefMyColor);
    await _prefs.remove('ft_followed_$groupId');
    await _prefs.remove('ft_cached_locs_$groupId');
    await _prefs.remove('ft_cooldown_until_$groupId');
  }
}

final appControllerProvider =
    StateNotifierProvider<AppController, AppState>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final supabase = ref.watch(supabaseServiceProvider);
  return AppController(prefs, supabase);
});
