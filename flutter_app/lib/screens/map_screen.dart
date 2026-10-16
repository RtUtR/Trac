// lib/screens/map_screen.dart
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../providers/app_providers.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with AutomaticKeepAliveClientMixin<MapScreen> {
  static const String _geoJsonSourceId = 'familytrack-members-source';
  static const String _circleLayerId = 'familytrack-members-circle-layer';

  @override
  bool get wantKeepAlive => true;

  MapLibreMapController? _mapController;
  Timer? _mapLoadTimeoutTimer;
  Timer? _cameraDebounceTimer;
  Timer? _statusTickerTimer;

  bool _isMapLoading = true;
  bool _isStyleLoaded = false;
  bool _layerAdded = false;
  bool _mapTimedOut = false;
  bool _hasFitInitialBounds = false;
  bool _hasSavedCamera = false;
  bool _isSyncingLayers = false;
  bool _pendingLayerSync = false;

  CameraPosition _initialCameraPosition = const CameraPosition(
    target: LatLng(0.0, 0.0),
    zoom: 2.0,
  );

  @override
  void initState() {
    super.initState();
    _startMapLoadingCycle();

    // 1. Initial camera priority:
    // (a) last saved camera from shared_preferences
    // (b) last known device position at zoom ~14
    // (c) only if neither exists, world view at zoom 2 (no city) until location arrives
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

    // Refresh status line relative time ("X min ago") every 30 seconds
    _statusTickerTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
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
    _isStyleLoaded = false;
    _layerAdded = false;
    _mapController = null;
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
      _layerAdded = false;
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
    if (!mounted || _mapController == null) return;
    _isStyleLoaded = true;
    _layerAdded = false;
    await _syncGeoJsonCircleLayer();
    if (!_hasFitInitialBounds && !_hasSavedCamera && mounted && _mapController != null) {
      await _fitBoundsToVisibleMembers();
    }
  }

  void _onMapIdle() {
    // 2. Save camera (lat, lng, zoom) to shared_preferences when idle (debounced)
    _cameraDebounceTimer?.cancel();
    _cameraDebounceTimer = Timer(const Duration(milliseconds: 600), () async {
      if (!mounted || _mapController == null) return;
      try {
        final cam = _mapController?.cameraPosition;
        if (cam != null) {
          final prefs = ref.read(sharedPreferencesProvider);
          await prefs.setDouble('ft_camera_lat', cam.target.latitude);
          await prefs.setDouble('ft_camera_lng', cam.target.longitude);
          await prefs.setDouble('ft_camera_zoom', cam.zoom);
        }
      } catch (_) {}
    });

    if (_isStyleLoaded && _isMapLoading && mounted) {
      _mapLoadTimeoutTimer?.cancel();
      setState(() {
        _isMapLoading = false;
        _mapTimedOut = false;
      });
    }
  }

  Map<String, dynamic> _buildFeatureCollection() {
    final state = ref.read(appControllerProvider);
    final visible = state.cachedLocations
        .where((loc) => state.followedUserIds.contains(loc.userId))
        .toList();

    final features = visible.map((loc) {
      return {
        'type': 'Feature',
        'id': loc.userId,
        'properties': {
          'user_id': loc.userId,
          'color': loc.color.isNotEmpty ? loc.color : '#2563EB',
        },
        'geometry': {
          'type': 'Point',
          'coordinates': [loc.lng, loc.lat],
        },
      };
    }).toList();

    return {
      'type': 'FeatureCollection',
      'features': features,
    };
  }

  /// Adds the GeoJSON source and circle layer ONLY when style is loaded.
  /// Called exclusively from onStyleLoadedCallback.
  /// - _layerAdded is set to true only after both addGeoJsonSource and addCircleLayer complete.
  /// - All calls to removeLayer and removeSource are wrapped in try/catch.
  Future<void> _syncGeoJsonCircleLayer() async {
    final controller = _mapController;
    if (controller == null || !_isStyleLoaded || !mounted) return;

    if (_isSyncingLayers) {
      _pendingLayerSync = true;
      return;
    }
    _isSyncingLayers = true;

    try {
      final featureCollection = _buildFeatureCollection();

      if (!_layerAdded) {
        try {
          await controller.removeLayer(_circleLayerId);
        } catch (_) {}
        try {
          await controller.removeSource(_geoJsonSourceId);
        } catch (_) {}

        await controller.addGeoJsonSource(_geoJsonSourceId, featureCollection);
        await controller.addCircleLayer(
          _geoJsonSourceId,
          _circleLayerId,
          const CircleLayerProperties(
            circleColor: [
              'case',
              ['has', 'color'],
              ['get', 'color'],
              '#2563EB',
            ],
            circleRadius: 9.0,
            circleStrokeWidth: 2.5,
            circleStrokeColor: '#FFFFFF',
          ),
        );
        // Set _layerAdded to true ONLY after both add calls complete successfully
        _layerAdded = true;
      } else {
        await controller.setGeoJsonSource(_geoJsonSourceId, featureCollection);
      }
    } catch (e) {
      _layerAdded = false;
      debugPrint('Error in _syncGeoJsonCircleLayer: $e');
    } finally {
      _isSyncingLayers = false;
      if (_pendingLayerSync && mounted && _layerAdded) {
        _pendingLayerSync = false;
        unawaited(_updateGeoJsonData());
      }
    }
  }

  /// Safe update of GeoJSON source data when member locations change.
  /// Called from ref.listen or member toggles. NEVER adds layers.
  Future<void> _updateGeoJsonData() async {
    final controller = _mapController;
    if (controller == null || !_layerAdded || !_isStyleLoaded || !mounted) {
      return;
    }
    try {
      final featureCollection = _buildFeatureCollection();
      await controller.setGeoJsonSource(_geoJsonSourceId, featureCollection);
    } catch (e) {
      debugPrint('Error updating GeoJSON data: $e');
    }
  }

  Future<void> _fitBoundsToVisibleMembers() async {
    final controller = _mapController;
    if (controller == null || !mounted) return;

    final state = ref.read(appControllerProvider);
    final visible = state.cachedLocations
        .where((loc) => state.followedUserIds.contains(loc.userId))
        .toList();

    if (visible.isEmpty) return;
    _hasFitInitialBounds = true;

    try {
      if (visible.length == 1) {
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(visible.first.lat, visible.first.lng),
            14.5,
          ),
        );
        return;
      }

      double minLat = visible.first.lat;
      double maxLat = visible.first.lat;
      double minLng = visible.first.lng;
      double maxLng = visible.first.lng;

      for (final loc in visible.skip(1)) {
        minLat = math.min(minLat, loc.lat);
        maxLat = math.max(maxLat, loc.lat);
        minLng = math.min(minLng, loc.lng);
        maxLng = math.max(maxLng, loc.lng);
      }

      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat - 0.005, minLng - 0.005),
            northeast: LatLng(maxLat + 0.005, maxLng + 0.005),
          ),
          left: 48,
          top: 48,
          right: 48,
          bottom: 48,
        ),
      );
    } catch (e) {
      debugPrint('animateCamera in _fitBoundsToVisibleMembers caught: $e');
    }
  }

  Future<void> _focusMemberOnMap(MemberLocation loc) async {
    final controller = _mapController;
    if (controller == null || !mounted) return;

    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(loc.lat, loc.lng), 15.5),
      );
    } catch (e) {
      debugPrint('focusMemberOnMap caught: $e');
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

    final Uri fallbackUri = Platform.isIOS
        ? Uri.parse(
            'https://maps.apple.com/?ll=$lat,$lng&q=${Uri.encodeComponent(loc.displayName)}',
          )
        : Uri.parse(
            'geo:$lat,$lng?q=$lat,$lng(${Uri.encodeComponent(loc.displayName)})',
          );

    if (useSystemChooser) {
      if (await canLaunchUrl(fallbackUri)) {
        await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
        return;
      }
    }

    if (await canLaunchUrl(primaryUri)) {
      await launchUrl(primaryUri, mode: LaunchMode.externalApplication);
    } else if (await canLaunchUrl(fallbackUri)) {
      await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openPeopleBottomSheet(BuildContext context) async {
    await ref.read(appControllerProvider.notifier).refreshGroupMembers();
    if (!context.mounted) return;

    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final state = ref.watch(appControllerProvider);
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.tr('people_sheet_title'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.tr('people_sheet_subtitle'),
                      style: Theme.of(context).textTheme.bodySmall,
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
                              await _updateGeoJsonData();
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
        _updateGeoJsonData();
      }
    });

    final visibleLocations = state.cachedLocations
        .where((loc) => state.followedUserIds.contains(loc.userId))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          state.activeGroup?.myDisplayName ?? l10n.tr('app_title'),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        actions: [
          // 1. Refresh (with server-enforced cooldown countdown)
          TextButton.icon(
            onPressed: state.cooldownRemainingSeconds > 0 || state.isLoading
                ? null
                : () {
                    _startMapLoadingCycle();
                    ref
                        .read(appControllerProvider.notifier)
                        .fetchFollowedLocations();
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
              _layerAdded = false;
              _isStyleLoaded = false;
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
                            TextButton(
                              onPressed: () {
                                _startMapLoadingCycle();
                                _layerAdded = false;
                                _isStyleLoaded = false;
                                try {
                                  _mapController?.setStyle(
                                    AppConfig.styleUrl(effectiveStyle),
                                  );
                                } catch (e) {
                                  debugPrint('retry setStyle error: $e');
                                }
                              },
                              child: Text(l10n.tr('retry')),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          _buildStatusLine(theme),
          _buildLastErrorLine(theme),

          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: theme.colorScheme.onSurface.withOpacity(0.12),
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: visibleLocations.isEmpty
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
                              padding: const EdgeInsetsDirectional.only(end: 8),
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
                        constraints: const BoxConstraints(maxHeight: 132),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: visibleLocations.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final loc = visibleLocations[index];
                            final updatedText =
                                l10n.formatUpdatedAgo(loc.updatedAt);
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
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
                                    child: Text(
                                      '${loc.displayName} — $updatedText',
                                      style: theme.textTheme.bodySmall,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () => _openInExternalMaps(loc),
                                    child: Text(
                                      l10n.tr('open_in_maps'),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: l10n.tr('open_in_system_geo'),
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
          ),
        ],
      ),
    );
  }

  Widget _buildStatusLine(ThemeData theme) {
    final prefs = ref.watch(sharedPreferencesProvider);
    final lastSentAtMs = prefs.getInt('bg_last_sent_at_ms');
    final lastCheckStatus = prefs.getString('bg_last_check_status');

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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.onSurface.withOpacity(0.08),
          ),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: theme.colorScheme.onSurface.withOpacity(0.55),
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// Displays the last recorded global error (from FlutterError, PlatformDispatcher, or Zone)
  /// with a tap-to-copy interaction so failures can be diagnosed directly on device.
  Widget _buildLastErrorLine(ThemeData theme) {
    final prefs = ref.watch(sharedPreferencesProvider);
    final lastErrMsg = prefs.getString('ft_last_error_message');
    final lastErrTime = prefs.getString('ft_last_error_time');
    final lastErrStack = prefs.getString('ft_last_error_stack') ?? '';

    if (lastErrMsg == null || lastErrMsg.isEmpty) {
      return const SizedBox.shrink();
    }

    return InkWell(
      onTap: () {
        final fullText = '$lastErrMsg ($lastErrTime)\n$lastErrStack';
        Clipboard.setData(ClipboardData(text: fullText));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error copied to clipboard'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: theme.colorScheme.error.withOpacity(0.12),
          border: Border(
            top: BorderSide(
              color: theme.colorScheme.error.withOpacity(0.3),
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, size: 14, color: theme.colorScheme.error),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Last error ($lastErrTime): $lastErrMsg (tap to copy)',
                style: TextStyle(
                  fontSize: 10.5,
                  color: theme.colorScheme.error,
                  fontFamily: 'monospace',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 14),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Dismiss',
              onPressed: () async {
                await prefs.remove('ft_last_error_message');
                await prefs.remove('ft_last_error_stack');
                await prefs.remove('ft_last_error_time');
                if (mounted) setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }
}
