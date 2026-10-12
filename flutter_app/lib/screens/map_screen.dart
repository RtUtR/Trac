// lib/screens/map_screen.dart
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class _MapScreenState extends ConsumerState<MapScreen> {
  static const String _geoJsonSourceId = 'familytrack-members-source';
  static const String _circleLayerId = 'familytrack-members-circle-layer';

  MapLibreMapController? _mapController;
  Timer? _mapLoadTimeoutTimer;

  bool _isMapLoading = true;
  bool _isStyleLoaded = false;
  bool _mapTimedOut = false;
  bool _hasFitInitialBounds = false;

  @override
  void initState() {
    super.initState();
    _startMapLoadingCycle();
  }

  @override
  void dispose() {
    _mapLoadTimeoutTimer?.cancel();
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
    await _syncGeoJsonCircleLayer();
    if (!_hasFitInitialBounds) {
      await _fitBoundsToVisibleMembers();
    }
  }

  void _onMapIdle() {
    if (_isStyleLoaded && _isMapLoading && mounted) {
      _mapLoadTimeoutTimer?.cancel();
      setState(() {
        _isMapLoading = false;
        _mapTimedOut = false;
      });
    }
  }

  /// Draws each followed member as a colored circle using a single GeoJSON source
  /// and data-driven circle layer.
  /// - GeoJSON Point coordinates use [lng, lat] order.
  /// - MapLibre Flutter camera methods use LatLng(lat, lng) order.
  /// - Member names are rendered as Flutter chips below, never inside the map layer.
  Future<void> _syncGeoJsonCircleLayer() async {
    final controller = _mapController;
    if (controller == null || !_isStyleLoaded) return;

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
      await controller.removeLayer(_circleLayerId);
    } catch (_) {}
    try {
      await controller.removeSource(_geoJsonSourceId);
    } catch (_) {}

    try {
      await controller.addGeoJsonSource(_geoJsonSourceId, featureCollection);
      await controller.addCircleLayer(
        _geoJsonSourceId,
        _circleLayerId,
        const CircleLayerProperties(
          circleColor: [Expressions.get, 'color'],
          circleRadius: 9.0,
          circleStrokeWidth: 2.5,
          circleStrokeColor: '#FFFFFF',
        ),
      );
    } catch (_) {}
  }

  Future<void> _fitBoundsToVisibleMembers() async {
    final controller = _mapController;
    if (controller == null) return;

    final state = ref.read(appControllerProvider);
    final visible = state.cachedLocations
        .where((loc) => state.followedUserIds.contains(loc.userId))
        .toList();

    if (visible.isEmpty) return;
    _hasFitInitialBounds = true;

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
  }

  Future<void> _focusMemberOnMap(MemberLocation loc) async {
    final controller = _mapController;
    if (controller == null) return;

    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(loc.lat, loc.lng), 15.5),
    );
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
    // Refresh group member roster from public.members before showing sheet
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
              await ref
                  .read(appControllerProvider.notifier)
                  .setMapStyle(style);
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
                  initialCameraPosition: const CameraPosition(
                    target: LatLng(35.6892, 51.3890),
                    zoom: 11.5,
                  ),
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
              ],
            ),
          ),

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
}
