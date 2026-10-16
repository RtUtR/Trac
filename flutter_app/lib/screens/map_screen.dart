// lib/screens/map_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../providers/app_providers.dart';
import '../services/background_location_service.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with AutomaticKeepAliveClientMixin<MapScreen>, WidgetsBindingObserver {
  static const String _geoJsonSourceId = 'familytrack-members-source';
  static const String _circleLayerId = 'familytrack-members-circle-layer';

  @override
  bool get wantKeepAlive => true;

  MapLibreMapController? _mapController;
  Timer? _mapLoadTimeoutTimer;
  Timer? _cameraDebounceTimer;
  Timer? _statusTickerTimer;
  Timer? _prefsReloadTimer;
  StreamSubscription<Position>? _livePositionSub;

  bool _isMapLoading = true;
  bool _isStyleLoaded = false;
  bool _layerAdded = false;
  bool _mapTimedOut = false;
  bool _hasFitInitialBounds = false;
  bool _hasSavedCamera = false;
  bool _isSyncingLayers = false;
  bool _pendingLayerSync = false;
  bool _isLocatingMe = false;

  // Local live fix for self (updated immediately without network or server cooldown)
  MemberLocation? _myLocalLiveLocation;

  CameraPosition _initialCameraPosition = const CameraPosition(
    target: LatLng(0.0, 0.0),
    zoom: 2.0,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startMapLoadingCycle();

    // 1. Post-frame startup:
    // Request notification permission (POST_NOTIFICATIONS on Android 13+) with permission_handler,
    // start background service only after first frame, and fetch others once if cooldown allows.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        try {
          final notifStatus = await Permission.notification.status;
          if (!notifStatus.isGranted) {
            await Permission.notification.request();
          }
        } catch (_) {}

        final state = ref.read(appControllerProvider);
        if (state.locationPermissionGranted) {
          await BackgroundLocationService.startIfPermitted();
        }

        // Fetch once when map screen opens if cooldown allows
        if (state.activeGroup != null && state.cooldownRemainingSeconds == 0) {
          await ref
              .read(appControllerProvider.notifier)
              .fetchFollowedLocations();
        }
      } catch (e) {
        debugPrint('PostFrame startup error: $e');
      }
    });

    // 2. Initial camera priority:
    // (a) last saved camera from shared_preferences
    // (b) last known device position at zoom ~14
    // (c) only if neither exists, world view at zoom 2
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final savedLat = prefs.getDouble('ft_camera_lat');
      final savedLng = prefs.getDouble('ft_camera_lng');
      final savedZoom = prefs.getDouble('ft_camera_zoom');

      if (savedLat != null &&
          savedLng != null &&
          savedZoom != null &&
          savedLat >= -90 &&
          savedLat <= 90 &&
          savedLng >= -180 &&
          savedLng <= 180) {
        _hasSavedCamera = true;
        _initialCameraPosition = CameraPosition(
          target: LatLng(savedLat, savedLng),
          zoom: savedZoom,
        );
      } else {
        _resolveDevicePositionOnStart();
      }
    } catch (_) {
      _resolveDevicePositionOnStart();
    }

    // 3. Listen to live device location to update "my" circle with distanceFilter 10m
    _startLivePositionStream();

    // 4. Reload SharedPreferences every 15 seconds while map is visible so background isolate writes are fresh
    _prefsReloadTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      try {
        final prefs = ref.read(sharedPreferencesProvider);
        await prefs.reload();
        if (mounted) setState(() {});
      } catch (_) {}
    });

    // Refresh status line relative time ("X min ago") every 30 seconds
    _statusTickerTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) {
      ref.read(sharedPreferencesProvider).reload().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  /// Listens to live device location stream (distanceFilter: 10m)
  /// Updates local circle immediately without network call or cooldown.
  void _startLivePositionStream() {
    _livePositionSub?.cancel();
    try {
      final LocationSettings locationSettings;
      if (defaultTargetPlatform == TargetPlatform.android) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
          forceLocationManager: true,
        );
      } else {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        );
      }
      _livePositionSub = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (pos) {
          _updateMyLocalLivePosition(pos, animateCamera: false);
        },
        onError: (err) {
          debugPrint('Live position stream error: $err');
        },
      );
    } catch (e) {
      debugPrint('Live position stream exception: $e');
    }
  }

  /// Updates my circle and chip immediately from a local device GPS fix
  void _updateMyLocalLivePosition(
    Position pos, {
    required bool animateCamera,
  }) {
    if (!mounted) return;
    final state = ref.read(appControllerProvider);
    final group = state.activeGroup;
    final prefs = ref.read(sharedPreferencesProvider);
    final myUid = prefs.getString('ft_my_user_id') ??
        ref.read(supabaseServiceProvider).currentUserId ??
        '';
    final name = group?.myDisplayName ?? 'Me';
    final color = group?.myColor ?? '#2563EB';

    setState(() {
      _myLocalLiveLocation = MemberLocation(
        userId: myUid,
        displayName: name,
        color: color,
        lat: pos.latitude,
        lng: pos.longitude,
        accuracy: pos.accuracy,
        updatedAt: DateTime.now(),
      );
    });

    _syncGeoJsonCircleLayer();

    if (animateCamera) {
      try {
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(pos.latitude, pos.longitude),
            15.5,
          ),
        );
      } catch (e) {
        debugPrint('Camera animation error: $e');
      }
    }
  }

  /// "Locate me" button handler:
  /// Gets a fresh device GPS fix (15 second limit, forceLocationManager: true),
  /// updates MY circle and chip immediately from that fix, and animates camera.
  /// Makes NO server call and ignores cooldown.
  Future<void> _locateMe() async {
    if (_isLocatingMe) return;
    setState(() => _isLocatingMe = true);

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

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: settings,
      );
      _updateMyLocalLivePosition(pos, animateCamera: true);
    } catch (e) {
      debugPrint('Locate me error: $e');
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          _updateMyLocalLivePosition(last, animateCamera: true);
        }
      } catch (_) {}
    } finally {
      if (mounted) {
        setState(() => _isLocatingMe = false);
      }
    }
  }

  Future<void> _resolveDevicePositionOnStart() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        return;
      }

      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && mounted && !_hasSavedCamera) {
        try {
          await _mapController?.animateCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(lastKnown.latitude, lastKnown.longitude),
              14.0,
            ),
          );
        } catch (_) {}
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      );
      if (mounted && !_hasSavedCamera) {
        try {
          await _mapController?.animateCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(pos.latitude, pos.longitude),
              14.0,
            ),
          );
        } catch (_) {}
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _livePositionSub?.cancel();
    _prefsReloadTimer?.cancel();
    _mapLoadTimeoutTimer?.cancel();
    _cameraDebounceTimer?.cancel();
    _statusTickerTimer?.cancel();
    super.dispose();
  }

  void _startMapLoadingCycle() {
    _mapLoadTimeoutTimer?.cancel();
    setState(() {
      _isMapLoading = true;
      _isStyleLoaded = false;
      _mapTimedOut = false;
    });

    _mapLoadTimeoutTimer = Timer(AppConfig.mapReadyTimeout, () {
      if (!mounted) return;
      if (_isMapLoading) {
        setState(() {
          _isMapLoading = false;
          _mapTimedOut = true;
        });
      }
    });
  }

  Future<void> _onStyleLoaded() async {
    _isStyleLoaded = true;
    _layerAdded = false;
    await _addGeoJsonCircleLayer();
    if (!_hasFitInitialBounds && !_hasSavedCamera) {
      await _fitBoundsToVisibleMembers();
    }
  }

  /// Computes the effective list of locations to show:
  /// - Substitutes "my" position with _myLocalLiveLocation if present.
  /// - Other members come strictly from state.cachedLocations (updated only via fetch_locations).
  List<MemberLocation> _getEffectiveVisibleLocations() {
    final state = ref.read(appControllerProvider);
    final prefs = ref.read(sharedPreferencesProvider);
    final myUid = prefs.getString('ft_my_user_id') ??
        ref.read(supabaseServiceProvider).currentUserId ??
        '';

    final list = <MemberLocation>[];
    for (final loc in state.cachedLocations) {
      if ((myUid.isNotEmpty && loc.userId == myUid) &&
          _myLocalLiveLocation != null) {
        list.add(_myLocalLiveLocation!);
      } else {
        list.add(loc);
      }
    }

    if (_myLocalLiveLocation != null &&
        !list.any((l) => l.userId == _myLocalLiveLocation!.userId)) {
      list.insert(0, _myLocalLiveLocation!);
    }

    return list.where((loc) {
      if (_myLocalLiveLocation != null &&
          loc.userId == _myLocalLiveLocation!.userId) {
        if (state.followedUserIds.isNotEmpty &&
            myUid.isNotEmpty &&
            !state.followedUserIds.contains(myUid)) {
          return false;
        }
        return true;
      }
      return state.followedUserIds.contains(loc.userId);
    }).toList();
  }

  Future<void> _addGeoJsonCircleLayer() async {
    final controller = _mapController;
    if (controller == null || !_isStyleLoaded || _layerAdded) return;

    try {
      final visible = _getEffectiveVisibleLocations();

      final features = visible.map((loc) {
        return {
          'type': 'Feature',
          'id': loc.userId,
          'properties': {
            'user_id': loc.userId,
            'color': loc.color,
          },
          'geometry': {
            'type': 'Point',
            'coordinates': [loc.lng, loc.lat],
          },
        };
      }).toList();

      final featureCollection = {
        'type': 'FeatureCollection',
        'features': features,
      };

      try {
        await controller.addGeoJsonSource(_geoJsonSourceId, featureCollection);
      } catch (e) {
        debugPrint('addGeoJsonSource error: $e');
      }

      try {
        await controller.addCircleLayer(
          _geoJsonSourceId,
          _circleLayerId,
          const CircleLayerProperties(
            circleColor: ['get', 'color'],
            circleRadius: 9.0,
            circleStrokeWidth: 2.5,
            circleStrokeColor: '#FFFFFF',
          ),
        );
      } catch (e) {
        debugPrint('addCircleLayer error: $e');
      }

      _layerAdded = true;
    } catch (e) {
      debugPrint('_addGeoJsonCircleLayer error: $e');
    }
  }

  void _onMapIdle() {
    _cameraDebounceTimer?.cancel();
    _cameraDebounceTimer = Timer(const Duration(milliseconds: 600), () async {
      final cam = _mapController?.cameraPosition;
      if (cam != null) {
        final prefs = ref.read(sharedPreferencesProvider);
        await prefs.setDouble('ft_camera_lat', cam.target.latitude);
        await prefs.setDouble('ft_camera_lng', cam.target.longitude);
        await prefs.setDouble('ft_camera_zoom', cam.zoom);
      }
    });

    if (_isStyleLoaded && _isMapLoading && mounted) {
      _mapLoadTimeoutTimer?.cancel();
      setState(() {
        _isMapLoading = false;
        _mapTimedOut = false;
      });
    }
  }

  Future<void> _syncGeoJsonCircleLayer() async {
    final controller = _mapController;
    if (controller == null || !_isStyleLoaded || !_layerAdded) return;

    if (_isSyncingLayers) {
      _pendingLayerSync = true;
      return;
    }
    _isSyncingLayers = true;

    try {
      final visible = _getEffectiveVisibleLocations();

      final features = visible.map((loc) {
        return {
          'type': 'Feature',
          'id': loc.userId,
          'properties': {
            'user_id': loc.userId,
            'color': loc.color,
          },
          'geometry': {
            'type': 'Point',
            'coordinates': [loc.lng, loc.lat],
          },
        };
      }).toList();

      final featureCollection = {
        'type': 'FeatureCollection',
        'features': features,
      };

      try {
        await controller.setGeoJsonSource(_geoJsonSourceId, featureCollection);
      } catch (e) {
        debugPrint('setGeoJsonSource error: $e');
      }
    } catch (_) {
    } finally {
      _isSyncingLayers = false;
      if (_pendingLayerSync) {
        _pendingLayerSync = false;
        unawaited(_syncGeoJsonCircleLayer());
      }
    }
  }

  Future<void> _fitBoundsToVisibleMembers() async {
    final controller = _mapController;
    if (controller == null) return;
    try {
      final visible = _getEffectiveVisibleLocations();
      if (visible.isEmpty) return;

      if (visible.length == 1) {
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(visible.first.lat, visible.first.lng),
            14.0,
          ),
        );
        _hasFitInitialBounds = true;
        return;
      }

      double minLat = visible.first.lat;
      double maxLat = visible.first.lat;
      double minLng = visible.first.lng;
      double maxLng = visible.first.lng;

      for (final loc in visible) {
        minLat = math.min(minLat, loc.lat);
        maxLat = math.max(maxLat, loc.lat);
        minLng = math.min(minLng, loc.lng);
        maxLng = math.max(maxLng, loc.lng);
      }

      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng),
          ),
          left: 48,
          top: 48,
          right: 48,
          bottom: 48,
        ),
      );
      _hasFitInitialBounds = true;
    } catch (e) {
      debugPrint('fitBounds error: $e');
    }
  }

  Future<void> _focusMemberOnMap(MemberLocation loc) async {
    final controller = _mapController;
    if (controller == null) return;

    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(loc.lat, loc.lng), 15.5),
      );
    } catch (e) {
      debugPrint('focusMember error: $e');
    }
  }

  Future<void> _openInExternalMaps(
    MemberLocation loc, {
    bool useSystemChooser = false,
  }) async {
    final lat = loc.lat.toStringAsFixed(6);
    final lng = loc.lng.toStringAsFixed(6);

    final Uri primaryUri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    final Uri systemGeoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng');

    try {
      if (useSystemChooser && Platform.isAndroid) {
        final launchedGeo = await launchUrl(
          systemGeoUri,
          mode: LaunchMode.externalApplication,
        );
        if (launchedGeo) return;
      }

      final launchedWeb = await launchUrl(
        primaryUri,
        mode: LaunchMode.externalApplication,
      );
      if (launchedWeb) return;

      await launchUrl(primaryUri, mode: LaunchMode.platformDefault);
    } catch (_) {
      try {
        await launchUrl(primaryUri, mode: LaunchMode.inAppWebView);
      } catch (_) {}
    }
  }

  void _openPeopleBottomSheet(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final state = ref.watch(appControllerProvider);
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20.0,
                  vertical: 16.0,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.tr('people_sheet_title'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.tr('people_sheet_subtitle'),
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: state.groupMembers.length,
                        itemBuilder: (context, index) {
                          final member = state.groupMembers[index];
                          final selected =
                              state.followedUserIds.contains(member.userId);
                          return CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: selected,
                            onChanged: (_) async {
                              await ref
                                  .read(appControllerProvider.notifier)
                                  .toggleFollowedMember(member.userId);
                              await _syncGeoJsonCircleLayer();
                            },
                            secondary: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: _parseHexColor(member.color),
                                shape: BoxShape.circle,
                              ),
                            ),
                            title: Text(member.displayName),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatCooldown(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Color _parseHexColor(String hex) {
    final cleaned = hex.replaceAll('#', '');
    final val = int.tryParse('FF$cleaned', radix: 16) ?? 0xFF2563EB;
    return Color(val);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(appControllerProvider);
    final theme = Theme.of(context);
    final effectiveStyle = state.effectiveMapStyle(theme.brightness);

    ref.listen<AppState>(appControllerProvider, (prev, next) {
      if (prev?.cachedLocations != next.cachedLocations ||
          prev?.followedUserIds != next.followedUserIds) {
        _syncGeoJsonCircleLayer();
      }
    });

    final visibleLocations = _getEffectiveVisibleLocations();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          state.activeGroup?.myDisplayName ?? l10n.tr('app_title'),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        actions: [
          // 1. Top Refresh button:
          // Sends own location immediately (fresh GPS fix, upsert into public.locations)
          // AND fetches followed members if cooldown allows.
          // If on cooldown, still sends my location and shows the remaining cooldown.
          TextButton.icon(
            onPressed: state.isLoading
                ? null
                : () async {
                    final wasOnCooldown = state.cooldownRemainingSeconds > 0;
                    if (!wasOnCooldown) {
                      _startMapLoadingCycle();
                    }
                    await ref
                        .read(appControllerProvider.notifier)
                        .onTopRefreshPressed();
                    if (wasOnCooldown && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            l10n.tr(
                              'wait_cooldown',
                              params: {
                                'time': _formatCooldown(
                                  state.cooldownRemainingSeconds,
                                )
                              },
                            ),
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(
              state.cooldownRemainingSeconds > 0
                  ? _formatCooldown(state.cooldownRemainingSeconds)
                  : l10n.tr('refresh'),
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
                fontSize: 12,
              ),
            ),
          ),

          // 2. People (bottom sheet to choose which members to follow)
          IconButton(
            tooltip: l10n.tr('people'),
            icon: const Icon(Icons.group_outlined),
            onPressed: () => _openPeopleBottomSheet(context),
          ),

          // 3. Map style (Positron / Bright / Dark, saved locally)
          PopupMenuButton<MapStyleOption>(
            tooltip: l10n.tr('map_style'),
            icon: const Icon(Icons.layers_outlined),
            onSelected: (style) async {
              if (style == effectiveStyle) return;
              _startMapLoadingCycle();
              _isStyleLoaded = false;
              _layerAdded = false;
              await ref
                  .read(appControllerProvider.notifier)
                  .setMapStyle(style);
              try {
                await _mapController?.setStyle(AppConfig.styleUrl(style));
              } catch (e) {
                debugPrint('setStyle error: $e');
              }
            },
            itemBuilder: (context) => [
              CheckedPopupMenuItem(
                value: MapStyleOption.positron,
                checked: effectiveStyle == MapStyleOption.positron,
                child: Text(l10n.tr('style_positron')),
              ),
              CheckedPopupMenuItem(
                value: MapStyleOption.bright,
                checked: effectiveStyle == MapStyleOption.bright,
                child: Text(l10n.tr('style_bright')),
              ),
              CheckedPopupMenuItem(
                value: MapStyleOption.dark,
                checked: effectiveStyle == MapStyleOption.dark,
                child: Text(l10n.tr('style_dark')),
              ),
            ],
          ),

          // 4. Exit group
          IconButton(
            tooltip: l10n.tr('exit_group'),
            icon: const Icon(Icons.logout_outlined),
            onPressed: () =>
                ref.read(appControllerProvider.notifier).exitCurrentGroup(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!state.locationPermissionGranted)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: theme.colorScheme.onSurface,
              child: Text(
                l10n.tr('location_off_notice'),
                style: TextStyle(
                  color: theme.colorScheme.surface,
                  fontSize: 12,
                ),
              ),
            ),

          if (state.errorCode != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.onSurface.withOpacity(0.18),
                  ),
                ),
              ),
              child: Text(
                l10n.translateErrorCode(state.errorCode),
                style: theme.textTheme.bodySmall,
              ),
            ),

          Expanded(
            child: Stack(
              children: [
                MapLibreMap(
                  styleString: AppConfig.styleUrl(effectiveStyle),
                  initialCameraPosition: _initialCameraPosition,
                  minMaxZoomPreference: const MinMaxZoomPreference(
                    AppConfig.minMapZoom,
                    AppConfig.maxMapOverZoom,
                  ),
                  attributionButtonPosition:
                      AttributionButtonPosition.bottomRight,
                  compassEnabled: true,
                  myLocationEnabled: false,
                  onMapCreated: (controller) {
                    _mapController = controller;
                  },
                  onStyleLoadedCallback: _onStyleLoaded,
                  onMapIdle: _onMapIdle,
                ),

                if (_isMapLoading || state.isLoading)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(minHeight: 3),
                  ),

                if (_mapTimedOut)
                  Positioned(
                    top: 12,
                    left: 16,
                    right: 16,
                    child: Material(
                      elevation: 2,
                      borderRadius: BorderRadius.circular(10),
                      color: theme.colorScheme.surface,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n.tr('map_unavailable'),
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () {
                                _startMapLoadingCycle();
                                _layerAdded = false;
                                _mapController?.setStyle(
                                  AppConfig.styleUrl(effectiveStyle),
                                );
                              },
                              child: Text(l10n.tr('retry')),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // "Locate me" button: gets fresh GPS fix, updates MY circle and chip immediately (no server call)
                // Positioned on the bottom-right, directly above the attribution
                Positioned(
                  bottom: 48,
                  right: 14,
                  child: FloatingActionButton.small(
                    heroTag: 'locate_me_fab',
                    tooltip: l10n.tr('locate_me'),
                    backgroundColor: theme.colorScheme.surface,
                    foregroundColor: theme.colorScheme.primary,
                    elevation: 3,
                    onPressed: _isLocatingMe ? null : _locateMe,
                    child: _isLocatingMe
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location, size: 20),
                  ),
                ),
              ],
            ),
          ),

          // Followed members list and status area
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  offset: const Offset(0, -2),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.tr('people'),
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      '${visibleLocations.length} / ${state.groupMembers.length}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                visibleLocations.isEmpty
                    ? Text(
                        l10n.tr('no_followed_members'),
                        style: theme.textTheme.bodySmall,
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: visibleLocations.map((loc) {
                                final updatedLabel =
                                    l10n.formatUpdatedAgo(loc.updatedAt);
                                return Padding(
                                  padding:
                                      const EdgeInsetsDirectional.only(end: 8),
                                  child: ActionChip(
                                    onPressed: () => _focusMemberOnMap(loc),
                                    avatar: Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: _parseHexColor(loc.color),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    label: Text(
                                      '${loc.displayName} · $updatedLabel',
                                      style: const TextStyle(fontSize: 12.5),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 120),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: visibleLocations.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final loc = visibleLocations[index];
                                final updatedText =
                                    l10n.formatUpdatedAgo(loc.updatedAt);
                                return Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: _parseHexColor(loc.color),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              loc.displayName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                              ),
                                            ),
                                            Text(
                                              updatedText,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                color: theme
                                                    .colorScheme.onSurface
                                                    .withOpacity(0.6),
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: l10n.tr('open_in_maps'),
                                        icon: const Icon(
                                          Icons.open_in_new,
                                          size: 16,
                                        ),
                                        onPressed: () => _openInExternalMaps(
                                          loc,
                                          useSystemChooser: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
              ],
            ),
          ),

          // Small status line: "Last sent: X min ago • <last decision>"
          // Tapping expands the last 20 records with a Copy button (not hidden in release builds)
          _buildStatusLine(theme),
        ],
      ),
    );
  }

  /// Small status line:
  /// Displays "Last sent: X min ago • <last decision>". Tapping expands last 20 records.
  Widget _buildStatusLine(ThemeData theme) {
    final prefs = ref.watch(sharedPreferencesProvider);
    final lastSentAtMs = prefs.getInt('bg_last_sent_at_ms');
    final lastCheckStatus = prefs.getString('bg_last_check_status');
    final lastErrorMsg = prefs.getString('ft_last_error_msg');
    final lastErrorTime = prefs.getString('ft_last_error_time');
    final lastErrorStack = prefs.getString('ft_last_error_stack') ?? '';

    String text;
    if (lastSentAtMs == null) {
      text = lastCheckStatus ??
          'Background service active • Checking location every 3 min';
    } else {
      final elapsedSec =
          (DateTime.now().millisecondsSinceEpoch - lastSentAtMs) ~/ 1000;
      final elapsedMin = elapsedSec ~/ 60;
      final ago = elapsedMin <= 0 ? 'just now' : '$elapsedMin min ago';
      text =
          'Last sent: $ago${lastCheckStatus != null ? ' • $lastCheckStatus' : ''}';
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (lastErrorMsg != null && lastErrorMsg.isNotEmpty)
          InkWell(
            onTap: () async {
              final payload =
                  'Time: $lastErrorTime\nMessage: $lastErrorMsg\nStack:\n$lastErrorStack';
              await Clipboard.setData(ClipboardData(text: payload));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Last error copied to clipboard'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              color: Colors.red.withOpacity(0.08),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, size: 13, color: Colors.red),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Last error ($lastErrorTime): $lastErrorMsg (tap to copy)',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.red,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Interactive status line -> opens modal bottom sheet with last 20 records
        InkWell(
          onTap: () => _showLocationLogsSheet(context),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: theme.colorScheme.onSurface.withOpacity(0.08),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.receipt_long_outlined,
                  size: 14,
                  color: theme.colorScheme.onSurface.withOpacity(0.45),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Displays the modal sheet with the last 20 location service records and a Copy button
  Future<void> _showLocationLogsSheet(BuildContext context) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.reload();

    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final raw = prefs.getString('bg_location_logs_json');
    List<dynamic> logs = [];
    if (raw != null && raw.isNotEmpty) {
      try {
        logs = jsonDecode(raw) as List<dynamic>;
      } catch (_) {}
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (_, scrollController) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.tr('service_logs_title'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (logs.isNotEmpty)
                        TextButton.icon(
                          icon: const Icon(Icons.copy, size: 16),
                          label: Text(l10n.tr('copy_logs')),
                          onPressed: () async {
                            final text = const JsonEncoder.withIndent('  ')
                                .convert(logs);
                            await Clipboard.setData(ClipboardData(text: text));
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text(l10n.tr('logs_copied')),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                        ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: logs.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24.0),
                            child: Text(
                              'No location service records recorded yet.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          itemCount: logs.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 10),
                          itemBuilder: (c, idx) {
                            final map = logs[idx] as Map<String, dynamic>;
                            final time = map['time']?.toString() ?? '';
                            final decision = map['decision']?.toString() ?? '';
                            final lat = map['lat'];
                            final lng = map['lng'];
                            final accuracy = map['accuracy'];
                            final distance = map['distance'];
                            final method = map['method']?.toString() ?? '';
                            final status = map['status']?.toString() ?? '';

                            final isSkipped = decision.startsWith('skipped');
                            final isFailed = decision.contains('failed');

                            Color badgeColor = Colors.green;
                            if (isSkipped) badgeColor = Colors.orange;
                            if (isFailed) badgeColor = Colors.red;

                            return Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.04),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.08),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        time,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          fontFeatures: [
                                            FontFeature.tabularFigures()
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          decision,
                                          style: TextStyle(
                                            color: badgeColor,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  if (lat != null && lng != null)
                                    Text(
                                      'Fix: $lat, $lng (±${accuracy ?? '?'}m)',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: theme.colorScheme.onSurface
                                            .withOpacity(0.75),
                                      ),
                                    ),
                                  if (distance != null)
                                    Text(
                                      'Distance from last: ${distance}m',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: theme.colorScheme.onSurface
                                            .withOpacity(0.75),
                                      ),
                                    ),
                                  Text(
                                    'Method: $method • Status: $status',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.55),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
