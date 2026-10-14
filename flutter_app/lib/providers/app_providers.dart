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
  final prefs = ref.watch(sharedPreferencesProvider);
  return SupabaseService(Supabase.instance.client, prefs);
});

class AppState {
  final bool consentAccepted;
  final bool locationPermissionGranted;
  final GroupSummary? activeGroup;
  final GroupSummary? lastSavedGroup;
  final List<GroupMember> groupMembers;
  final Set<String> followedUserIds;
  final List<MemberLocation> cachedLocations;
  final int cooldownRemainingSeconds;
  final int loginCooldownRemainingSeconds;
  final MapStyleOption? userSelectedMapStyle;
  final bool isLoading;
  final bool isBootstrapping;
  final String? errorCode;

  const AppState({
    required this.consentAccepted,
    required this.locationPermissionGranted,
    this.activeGroup,
    this.lastSavedGroup,
    this.groupMembers = const [],
    this.followedUserIds = const {},
    this.cachedLocations = const [],
    this.cooldownRemainingSeconds = 0,
    this.loginCooldownRemainingSeconds = 0,
    this.userSelectedMapStyle,
    this.isLoading = false,
    this.isBootstrapping = false,
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
    GroupSummary? lastSavedGroup,
    bool clearLastSavedGroup = false,
    List<GroupMember>? groupMembers,
    Set<String>? followedUserIds,
    List<MemberLocation>? cachedLocations,
    int? cooldownRemainingSeconds,
    int? loginCooldownRemainingSeconds,
    MapStyleOption? userSelectedMapStyle,
    bool? isLoading,
    bool? isBootstrapping,
    String? errorCode,
    bool clearErrorCode = false,
  }) {
    return AppState(
      consentAccepted: consentAccepted ?? this.consentAccepted,
      locationPermissionGranted:
          locationPermissionGranted ?? this.locationPermissionGranted,
      activeGroup: clearActiveGroup ? null : (activeGroup ?? this.activeGroup),
      lastSavedGroup:
          clearLastSavedGroup ? null : (lastSavedGroup ?? this.lastSavedGroup),
      groupMembers: groupMembers ?? this.groupMembers,
      followedUserIds: followedUserIds ?? this.followedUserIds,
      cachedLocations: cachedLocations ?? this.cachedLocations,
      cooldownRemainingSeconds:
          cooldownRemainingSeconds ?? this.cooldownRemainingSeconds,
      loginCooldownRemainingSeconds:
          loginCooldownRemainingSeconds ?? this.loginCooldownRemainingSeconds,
      userSelectedMapStyle: userSelectedMapStyle ?? this.userSelectedMapStyle,
      isLoading: isLoading ?? this.isLoading,
      isBootstrapping: isBootstrapping ?? this.isBootstrapping,
      errorCode: clearErrorCode ? null : (errorCode ?? this.errorCode),
    );
  }
}

class AppController extends StateNotifier<AppState> {
  final SharedPreferences _prefs;
  final SupabaseService _supabase;
  Timer? _cooldownTimer;
  Timer? _loginCooldownTimer;

  static const _prefConsent = 'ft_consent_accepted';
  static const _prefMapStyle = 'ft_map_style';
  static const _prefGroupId = 'ft_group_id';
  static const _prefMyDisplayName = 'ft_my_display_name';
  static const _prefMyColor = 'ft_my_color';
  static const _prefGroupExpiresAt = 'ft_group_expires_at';
  static const _prefGroupMaxDevices = 'ft_group_max_devices';
  static const _prefLoginCooldownUntil = 'ft_login_cooldown_until';
  static const _prefMyUserId = 'ft_my_user_id';

  AppController(this._prefs, this._supabase)
      : super(
          _buildInitialState(_prefs),
        ) {
    _bootstrap();
  }

  static AppState _buildInitialState(SharedPreferences prefs) {
    final summary = _readSavedGroupSummaryStatic(prefs);
    final cached = _readCachedLocationsStatic(prefs, summary?.id);
    final followed = _readFollowedUserIdsStatic(prefs, summary?.id, cached);

    return AppState(
      consentAccepted: prefs.getBool(_prefConsent) ?? false,
      locationPermissionGranted: false,
      activeGroup: summary,
      lastSavedGroup: summary,
      cachedLocations: cached,
      followedUserIds: followed,
      userSelectedMapStyle: _parseStyle(prefs.getString(_prefMapStyle)),
      isBootstrapping: true,
    );
  }

  static List<MemberLocation> _readCachedLocationsStatic(
    SharedPreferences prefs,
    String? groupId,
  ) {
    if (groupId == null || groupId.isEmpty) return const [];
    final raw = prefs.getString('ft_cached_locs_$groupId');
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => MemberLocation.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Set<String> _readFollowedUserIdsStatic(
    SharedPreferences prefs,
    String? groupId,
    List<MemberLocation> cached,
  ) {
    if (groupId == null || groupId.isEmpty) return const {};
    final list = prefs.getStringList('ft_followed_$groupId');
    if (list != null && list.isNotEmpty) return list.toSet();
    return cached.map((e) => e.userId).toSet();
  }

  static MapStyleOption? _parseStyle(String? raw) {
    if (raw == null) return null;
    for (final s in MapStyleOption.values) {
      if (s.name == raw) return s;
    }
    return null;
  }

  static GroupSummary? _readSavedGroupSummaryStatic(SharedPreferences prefs) {
    final savedGroupId = prefs.getString(_prefGroupId);
    final savedDisplayName = prefs.getString(_prefMyDisplayName);
    if (savedGroupId == null ||
        savedGroupId.trim().isEmpty ||
        savedDisplayName == null ||
        savedDisplayName.trim().isEmpty) {
      return null;
    }
    final savedColor = prefs.getString(_prefMyColor) ?? '#2563EB';
    final savedExpiresRaw = prefs.getString(_prefGroupExpiresAt);
    final expiresAt = (savedExpiresRaw != null
            ? DateTime.tryParse(savedExpiresRaw)
            : null) ??
        DateTime.now().add(const Duration(days: 30));
    final maxDevices = prefs.getInt(_prefGroupMaxDevices) ?? 4;

    return GroupSummary(
      id: savedGroupId.trim(),
      maxDevices: maxDevices,
      expiresAt: expiresAt,
      myDisplayName: savedDisplayName.trim(),
      myColor: savedColor,
    );
  }

  GroupSummary? _readSavedGroupSummary() =>
      _readSavedGroupSummaryStatic(_prefs);

  Future<void> _bootstrap() async {
    try {
      await _prefs.reload();
    } catch (_) {}

    await refreshPermissionStatus();

    try {
      await _supabase.ensureAnonymousSession();
    } catch (_) {}

    // Check for active login cooldown (e.g. from previous too_many_attempts)
    final loginCooldownUntilMs = _prefs.getInt(_prefLoginCooldownUntil) ?? 0;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final loginRem =
        ((loginCooldownUntilMs - nowMs) / 1000).ceil().clamp(0, 7200);
    if (loginRem > 0) {
      _startLoginCooldownTicker(loginRem);
    }

    final savedSummary = _readSavedGroupSummary();
    if (!state.consentAccepted || savedSummary == null) {
      state = state.copyWith(isBootstrapping: false);
      return;
    }

    // Check expiry silently in background without taking user to login screen unless expired
    try {
      final groupInfo = await _supabase.fetchGroupInfo(savedSummary.id);
      if (groupInfo != null && groupInfo.isExpired) {
        await _clearLocalGroupData(savedSummary.id);
        state = state.copyWith(
          isLoading: false,
          isBootstrapping: false,
          clearActiveGroup: true,
          clearLastSavedGroup: true,
          errorCode: 'group_expired',
        );
        return;
      }

      final effectiveSummary = GroupSummary(
        id: savedSummary.id,
        maxDevices: groupInfo?.maxDevices ?? savedSummary.maxDevices,
        expiresAt: groupInfo?.expiresAt ?? savedSummary.expiresAt,
        myDisplayName: savedSummary.myDisplayName,
        myColor: savedSummary.myColor,
      );

      await _activateGroupSession(effectiveSummary, silent: true);
      if (state.locationPermissionGranted) {
        await BackgroundLocationService.startIfPermitted();
      }
    } catch (_) {
      // Offline: keep cached active group session intact
      if (state.activeGroup == null) {
        state = state.copyWith(
          activeGroup: savedSummary,
          lastSavedGroup: savedSummary,
        );
      }
    } finally {
      state = state.copyWith(isBootstrapping: false);
    }
  }

  Future<void> refreshPermissionStatus() async {
    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      final perm = await Geolocator.checkPermission();
      final granted = serviceOn &&
          (perm == LocationPermission.always ||
              perm == LocationPermission.whileInUse);
      state = state.copyWith(locationPermissionGranted: granted);
    } catch (_) {
      state = state.copyWith(locationPermissionGranted: false);
    }
  }

  Future<void> acceptConsentAndRequestPermissions() async {
    await _prefs.setBool(_prefConsent, true);

    try {
      await _supabase.ensureAnonymousSession();
    } catch (_) {}

    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.whileInUse) {
        perm = await Geolocator.requestPermission();
      }
    } catch (_) {}

    await refreshPermissionStatus();
    state = state.copyWith(consentAccepted: true);
    // Background service will start after successful join_group, not prematurely.
  }

  /// 1. Join or Log In to group.
  Future<bool> joinGroup({
    required String code,
    required String displayName,
    bool isExistingLogin = false,
  }) async {
    // If login cooldown is currently active, prevent spamming the server
    if (state.loginCooldownRemainingSeconds > 0) return false;

    state = state.copyWith(isLoading: true, clearErrorCode: true);

    final result = isExistingLogin
        ? await _supabase.loginWithExistingRole(
            rawCode: code,
            displayName: displayName,
          )
        : await _supabase.joinGroup(
            rawCode: code,
            displayName: displayName,
          );

    if (!result.ok || result.group == null) {
      final err = result.errorCode ?? 'server_error';
      if (err == 'too_many_attempts') {
        _startLoginCooldownTicker(120);
      }
      state = state.copyWith(
        isLoading: false,
        errorCode: err,
      );
      return false;
    }

    final group = result.group!;
    await _saveLocalGroupSummary(group);

    await _sendImmediateOwnPosition();
    await _activateGroupSession(group);
    if (state.locationPermissionGranted) {
      await BackgroundLocationService.startIfPermitted();
    }
    return true;
  }

  /// Re-opens a previously joined group session saved on this phone without calling join_group again.
  Future<void> resumeSavedGroup() async {
    final saved = state.lastSavedGroup ?? _readSavedGroupSummary();
    if (saved == null) return;
    state = state.copyWith(isLoading: true, clearErrorCode: true);
    await _activateGroupSession(saved);
    if (state.locationPermissionGranted) {
      await BackgroundLocationService.startIfPermitted();
    }
  }

  /// Called whenever the app returns to the foreground.
  /// Sends one location immediately (independent of distance and timer) as required,
  /// reloads session tokens from storage into SupabaseClient, re-verifies permissions,
  /// keeps background service alive, and updates member list.
  Future<void> onAppResumed() async {
    try {
      await _prefs.reload();
      // Reload persisted session so if background isolate rotated refresh token, Supabase client has it
      await _supabase.reloadPersistedSession();
      await refreshPermissionStatus();

      final group = state.activeGroup ?? _readSavedGroupSummary();
      if (group != null) {
        if (state.activeGroup == null) {
          state = state.copyWith(activeGroup: group, lastSavedGroup: group);
        }

        // Send one location immediately when returning to foreground (independent of distance & timer)
        unawaited(_sendImmediateOwnPosition());

        if (state.locationPermissionGranted) {
          unawaited(BackgroundLocationService.startIfPermitted());
        }

        unawaited(refreshGroupMembers());

        // Silently verify if group has expired without kicking out offline users
        try {
          final groupInfo = await _supabase.fetchGroupInfo(group.id);
          if (groupInfo != null && groupInfo.isExpired) {
            await _clearLocalGroupData(group.id);
            state = state.copyWith(
              clearActiveGroup: true,
              clearLastSavedGroup: true,
              cachedLocations: [],
              groupMembers: [],
              errorCode: 'group_expired',
            );
          }
        } catch (_) {}
      }
    } catch (_) {}
  }


  void _startLoginCooldownTicker(int seconds) {
    _loginCooldownTimer?.cancel();
    final untilMs = DateTime.now().millisecondsSinceEpoch + (seconds * 1000);
    _prefs.setInt(_prefLoginCooldownUntil, untilMs);

    state = state.copyWith(
      loginCooldownRemainingSeconds: seconds,
      errorCode: 'too_many_attempts',
    );

    _loginCooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final rem =
          ((untilMs - DateTime.now().millisecondsSinceEpoch) / 1000).ceil();
      if (rem <= 0) {
        timer.cancel();
        _prefs.remove(_prefLoginCooldownUntil);
        state = state.copyWith(
          loginCooldownRemainingSeconds: 0,
          clearErrorCode: state.errorCode == 'too_many_attempts',
        );
      } else {
        state = state.copyWith(loginCooldownRemainingSeconds: rem);
      }
    });
  }

  Future<void> _saveLocalGroupSummary(GroupSummary group) async {
    final uid = _supabase.currentUserId;
    if (uid != null && uid.isNotEmpty) {
      await _prefs.setString(_prefMyUserId, uid);
    }
    await _prefs.setString(_prefGroupId, group.id);
    await _prefs.setString(_prefMyDisplayName, group.myDisplayName);
    await _prefs.setString(_prefMyColor, group.myColor);
    await _prefs.setString(
      _prefGroupExpiresAt,
      group.expiresAt.toIso8601String(),
    );
    await _prefs.setInt(_prefGroupMaxDevices, group.maxDevices);
    state = state.copyWith(
      activeGroup: group,
      lastSavedGroup: group,
    );
  }

  Future<void> _activateGroupSession(
    GroupSummary group, {
    bool silent = false,
  }) async {
    try {
      final groupInfo = await _supabase.fetchGroupInfo(group.id);
      if (groupInfo != null && groupInfo.isExpired) {
        await _clearLocalGroupData(group.id);
        state = state.copyWith(
          clearActiveGroup: true,
          clearLastSavedGroup: true,
          isLoading: false,
          errorCode: 'group_expired',
        );
        return;
      }
    } catch (_) {}

    final members = await _supabase.fetchGroupMembers(group.id);

    final myUid = _supabase.currentUserId ?? _prefs.getString(_prefMyUserId);
    final defaultFollowed = members.isNotEmpty
        ? members.map((m) => m.userId).toSet()
        : (myUid != null ? {myUid} : <String>{});

    final savedFollowed =
        _prefs.getStringList('ft_followed_${group.id}')?.toSet() ??
            defaultFollowed;

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
      lastSavedGroup: group,
      groupMembers: members,
      followedUserIds: savedFollowed,
      cachedLocations: cached,
      cooldownRemainingSeconds: remaining,
      isLoading: false,
      clearErrorCode: true,
    );

    if (remaining > 0) {
      _startCooldownTicker(group.id, remaining);
    } else if (!silent) {
      await fetchFollowedLocations();
    }
  }

  Future<void> refreshGroupMembers() async {
    final group = state.activeGroup;
    if (group == null) return;
    try {
      final members = await _supabase.fetchGroupMembers(group.id);
      if (members.isNotEmpty) {
        state = state.copyWith(groupMembers: members);
      }
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
  Future<void> fetchFollowedLocations() async {
    final group = state.activeGroup;
    if (group == null) return;
    if (state.cooldownRemainingSeconds > 0) return;

    final targets = state.followedUserIds.toList();
    if (targets.isEmpty) return;

    state = state.copyWith(isLoading: true, clearErrorCode: true);

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

    // If 'not_authenticated', recover session without kicking user to login screen!
    if (err == 'not_authenticated') {
      try {
        await _supabase.ensureAnonymousSession();
        final retryResult = await _supabase.fetchLocations(
          groupId: group.id,
          targetUserIds: targets,
        );
        if (retryResult.ok) {
          final cooldownSec = retryResult.cooldownSeconds ?? 180;
          await _prefs.setString(
            'ft_cached_locs_${group.id}',
            jsonEncode(retryResult.locations.map((l) => l.toJson()).toList()),
          );
          if (cooldownSec > 0) {
            _startCooldownTicker(group.id, cooldownSec);
          }
          state = state.copyWith(
            cachedLocations: retryResult.locations,
            cooldownRemainingSeconds: cooldownSec,
            isLoading: false,
          );
          return;
        }
      } catch (_) {}
    }

    if (err == 'group_expired' || err == 'not_a_member') {
      await _clearLocalGroupData(group.id);
      state = state.copyWith(
        clearActiveGroup: true,
        clearLastSavedGroup: true,
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
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) return;
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        return;
      }

      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }

      if (pos != null) {
        await _supabase.upsertOwnLocation(
          lat: pos.latitude,
          lng: pos.longitude,
          accuracy: pos.accuracy,
        );
      }
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

  /// 5. Exit: supabase.rpc('leave_group', params: {'p_group_id': groupId})
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
      clearLastSavedGroup: true,
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
    await _prefs.remove(_prefGroupExpiresAt);
    await _prefs.remove(_prefGroupMaxDevices);
    await _prefs.remove('ft_followed_$groupId');
    await _prefs.remove('ft_cached_locs_$groupId');
    await _prefs.remove('ft_cooldown_until_$groupId');
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _loginCooldownTimer?.cancel();
    super.dispose();
  }
}

final appControllerProvider =
    StateNotifierProvider<AppController, AppState>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final supabase = ref.watch(supabaseServiceProvider);
  return AppController(prefs, supabase);
});
