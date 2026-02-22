import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../config.dart';
import '../theme.dart';
import '../models/bus_position.dart';
import '../services/websocket_service.dart';
import '../widgets/stop_notification.dart';
import '../widgets/route_stops_sheet.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  final _wsService = WebSocketService();
  MapLibreMapController? _mapController;
  bool _followBus = true;
  String? _styleJson;
  bool _mapReady = false;

  // Bus data as ValueNotifier — only overlay widgets rebuild, NOT the map
  final _busNotifier = ValueNotifier<BusPosition?>(null);
  final _showStopsSheet = ValueNotifier<bool>(false);
  final _stopEventNotifier = ValueNotifier<StopEvent?>(null);

  // Native map objects
  Symbol? _busSymbol;
  Circle? _busGlow;
  bool _creatingMarker = false; // Sync lock to prevent duplicate creation

  // Smooth position animation
  late AnimationController _posController;
  LatLng _fromLatLng = const LatLng(28.6674, 77.2274);
  LatLng _toLatLng = const LatLng(28.6674, 77.2274);
  LatLng _currentLatLng = const LatLng(28.6674, 77.2274);
  bool _hasFirstPosition = false;
  double _currentHeading = 0;

  // Stop notification
  Timer? _stopNotificationTimer;

  // Throttle marker updates during animation
  DateTime _lastMarkerUpdate = DateTime.now();

  // Skip animation on first update after resume (jump to current position)
  bool _skipNextAnimation = false;

  // Cached map widget — never rebuilt
  Widget? _cachedMap;

  // Incremented on theme toggle to force Flutter to fully recreate the
  // MapLibreMap (new State, new native view) instead of reusing the old one.
  int _mapKey = 0;

  // Saved zoom for theme switch (preserves user's zoom level)
  double _savedZoom = 14.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _posController = AnimationController(
      duration: const Duration(milliseconds: 4500),
      vsync: this,
    )..addListener(_onPositionTick);

    _loadOlaStyle();
    _wsService.connect();
    WakelockPlus.enable(); // Keep screen on while tracking

    _wsService.busStream.listen((buses) {
      if (buses.isEmpty) return;
      final newBus = buses.first;
      _busNotifier.value = newBus;

      final newLatLng = LatLng(newBus.latitude, newBus.longitude);
      debugPrint('[MAP] Bus update: lat=${newBus.latitude.toStringAsFixed(5)} '
          'lng=${newBus.longitude.toStringAsFixed(5)} | '
          'stop=${newBus.currentStopIdx} | status=${newBus.status} | '
          'mapReady=$_mapReady | hasSymbol=${_busSymbol != null}');

      if (!_hasFirstPosition) {
        _hasFirstPosition = true;
        _fromLatLng = newLatLng;
        _toLatLng = newLatLng;
        _currentLatLng = newLatLng;
        _currentHeading = newBus.heading;
        // Trigger rebuild so the map creates with the real bus position
        // as its initialCameraPosition (instead of a hardcoded default)
        setState(() {});
        _updateNativeMarker(newLatLng, newBus.heading);
        if (_followBus && _mapController != null) {
          _mapController!.animateCamera(CameraUpdate.newLatLng(newLatLng));
        }
        return;
      }

      // After screen off/on, skip animation and jump to new position immediately
      if (_skipNextAnimation) {
        _skipNextAnimation = false;
        debugPrint('[MAP] Skipping animation — jumping to new position');
        _fromLatLng = newLatLng;
        _toLatLng = newLatLng;
        _currentLatLng = newLatLng;
        _currentHeading = newBus.heading;
        _updateNativeMarker(newLatLng, newBus.heading);
        if (_followBus && _mapController != null) {
          _mapController!.animateCamera(CameraUpdate.newLatLng(newLatLng));
        }
        return;
      }

      _fromLatLng = _currentLatLng;
      _toLatLng = newLatLng;
      _currentHeading = newBus.heading;
      _posController.forward(from: 0);

      if (_followBus && _mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLng(newLatLng),
          duration: const Duration(milliseconds: 2000),
        );
      }
    });

    _wsService.stopStream.listen(_showStopNotification);
  }

  // ─── Theme toggle ───────────────────────────────────────────────
  void _toggleTheme() async {
    // 1. Save current zoom before destroying the controller
    _savedZoom = _mapController?.cameraPosition?.zoom ?? _savedZoom;

    // 2. Flip theme
    themeNotifier.value = !themeNotifier.value;

    // 3. Fetch new style WHILE the old map is still visible (no spinner)
    final newStyle = await _fetchStyleJson();
    if (!mounted) return;

    // 4. Now swap — destroy old map and rebuild instantly with preloaded style
    _cachedMap = null;
    _busSymbol = null;
    _busGlow = null;
    _creatingMarker = false;
    _mapController = null;
    _mapReady = false;
    _mapKey++; // New key forces Flutter to fully recreate the native map
    setState(() => _styleJson = newStyle);
  }

  /// Fetch and process Ola Maps style.json, returning the processed JSON string.
  /// On failure, returns a fallback CartoDB style.
  Future<String> _fetchStyleJson() async {
    try {
      final url = '$olaStyleUrl?api_key=$olaApiKey';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        debugPrint('[OLA] Style fetch failed: ${response.statusCode}');
        return _buildFallbackStyleJson();
      }

      final style = jsonDecode(response.body) as Map<String, dynamic>;
      _processOlaStyle(style);

      debugPrint('[OLA] Style loaded');
      return jsonEncode(style);
    } catch (e) {
      debugPrint('[OLA] Style fetch error: $e');
      return _buildFallbackStyleJson();
    }
  }

  /// Inject API key into all URLs within an Ola Maps style object.
  void _processOlaStyle(Map<String, dynamic> style) {
    if (style.containsKey('sources')) {
      final sources = style['sources'] as Map<String, dynamic>;
      for (final key in sources.keys) {
        final source = sources[key];
        if (source is Map<String, dynamic>) {
          if (source.containsKey('url')) {
            final sourceUrl = source['url'] as String;
            final jsonMatch = RegExp(r'^(.*)/([^/]+)\.json(\?.*)$').firstMatch(sourceUrl);
            if (jsonMatch != null) {
              final basePath = jsonMatch.group(1);
              final sourceName = jsonMatch.group(2);
              final queryParams = jsonMatch.group(3);
              final tileUrl = '$basePath/$sourceName/{z}/{x}/{y}.pbf$queryParams&api_key=$olaApiKey';
              source['tiles'] = [tileUrl];
              source.remove('url');
            } else {
              source['url'] = _appendApiKey(sourceUrl);
            }
          }
          if (source.containsKey('tiles')) {
            final tiles = source['tiles'] as List;
            for (int i = 0; i < tiles.length; i++) {
              tiles[i] = _appendApiKey(tiles[i] as String);
            }
          }
        }
      }
    }

    if (style.containsKey('glyphs') && style['glyphs'] is String) {
      style['glyphs'] = _appendApiKey(style['glyphs'] as String);
    }
    if (style.containsKey('sprite') && style['sprite'] is String) {
      style['sprite'] = _appendApiKey(style['sprite'] as String);
    }
  }

  /// Initial style load on startup
  Future<void> _loadOlaStyle() async {
    final styleStr = await _fetchStyleJson();
    if (!mounted) return;
    setState(() => _styleJson = styleStr);
  }

  String _appendApiKey(String url) {
    if (url.contains('api_key')) return url;
    return url.contains('?') ? '$url&api_key=$olaApiKey' : '$url?api_key=$olaApiKey';
  }

  String _buildFallbackStyleJson() {
    final tileVariant = isDark ? 'dark_all' : 'light_all';
    return jsonEncode({
      "version": 8,
      "sources": {
        "carto": {
          "type": "raster",
          "tiles": [
            "https://a.basemaps.cartocdn.com/$tileVariant/{z}/{x}/{y}@2x.png",
            "https://b.basemaps.cartocdn.com/$tileVariant/{z}/{x}/{y}@2x.png",
          ],
          "tileSize": 256,
        }
      },
      "layers": [
        {"id": "carto-tiles", "type": "raster", "source": "carto"}
      ],
    });
  }

  void _onMapCreated(MapLibreMapController controller) {
    _mapController = controller;
  }

  void _onStyleLoaded() async {
    // Register bus icon image BEFORE setting _mapReady.
    // Otherwise a bus update tick can race in, create a symbol referencing
    // 'bus-icon' that hasn't been added yet, and the marker is invisible.
    await _addBusIconToMap();
    _mapReady = true;
    if (_hasFirstPosition) {
      await _updateNativeMarker(_currentLatLng, _currentHeading);
    }
  }

  Future<void> _addBusIconToMap() async {
    if (_mapController == null) return;

    const size = 96.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));

    canvas.drawCircle(
      Offset(size / 2, size / 2), size / 2,
      Paint()..color = AppColors.accent.withValues(alpha: AppColors.mapGlowAlpha),
    );
    canvas.drawCircle(
      Offset(size / 2, size / 2), size / 2.8,
      Paint()..color = AppColors.busIconFill,
    );
    canvas.drawCircle(
      Offset(size / 2, size / 2), size / 2.8,
      Paint()
        ..color = AppColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5,
    );

    final busPaint = Paint()..color = AppColors.accent;
    final center = Offset(size / 2, size / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: center, width: size * 0.38, height: size * 0.48), const Radius.circular(6)),
      busPaint,
    );

    final fillPaint = Paint()..color = AppColors.busIconFill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(center.dx, center.dy - size * 0.1), width: size * 0.28, height: size * 0.12), const Radius.circular(3)),
      fillPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(center.dx, center.dy + size * 0.04), width: size * 0.28, height: size * 0.08), const Radius.circular(2)),
      fillPaint,
    );
    canvas.drawCircle(Offset(center.dx - size * 0.12, center.dy + size * 0.24), size * 0.05, fillPaint);
    canvas.drawCircle(Offset(center.dx + size * 0.12, center.dy + size * 0.24), size * 0.05, fillPaint);

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData != null) {
      await _mapController!.addImage('bus-icon', Uint8List.view(byteData.buffer));
    }
  }

  Future<void> _createNativeMarker(LatLng pos, double heading) async {
    if (_mapController == null) return;
    // Guard: if markers already exist, just update them
    if (_busGlow != null || _busSymbol != null) {
      await _updateNativeMarker(pos, heading);
      return;
    }
    // Sync lock: _busGlow is only set AFTER the async addCircle completes.
    // Without this flag, a second call can sneak in during the await gap
    // and create duplicate markers.
    if (_creatingMarker) return;
    _creatingMarker = true;

    try {
      _busGlow = await _mapController!.addCircle(CircleOptions(
        geometry: pos,
        circleRadius: 24,
        circleColor: AppColors.accentHex,
        circleOpacity: AppColors.mapCircleOpacity,
        circleStrokeWidth: 0,
      ));

      _busSymbol = await _mapController!.addSymbol(SymbolOptions(
        geometry: pos,
        iconImage: 'bus-icon',
        iconSize: 0.55,
      ));
    } finally {
      _creatingMarker = false;
    }
  }

  Future<void> _updateNativeMarker(LatLng pos, [double? heading]) async {
    if (_mapController == null || !_mapReady) return;
    if (_busGlow == null || _busSymbol == null) {
      await _createNativeMarker(pos, heading ?? _currentHeading);
      return;
    }

    await _mapController!.updateCircle(_busGlow!, CircleOptions(geometry: pos));
    await _mapController!.updateSymbol(_busSymbol!, SymbolOptions(geometry: pos));
  }

  void _onPositionTick() {
    final t = Curves.easeInOut.transform(_posController.value);
    _currentLatLng = LatLng(
      _fromLatLng.latitude + (_toLatLng.latitude - _fromLatLng.latitude) * t,
      _fromLatLng.longitude + (_toLatLng.longitude - _fromLatLng.longitude) * t,
    );

    final now = DateTime.now();
    if (now.difference(_lastMarkerUpdate).inMilliseconds > 66) {
      _lastMarkerUpdate = now;
      _updateNativeMarker(_currentLatLng);
    }
  }

  void _showStopNotification(StopEvent event) {
    _stopNotificationTimer?.cancel();
    _stopEventNotifier.value = event;
    _stopNotificationTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) _stopEventNotifier.value = null;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[LIFECYCLE] App resumed — reconnecting and skipping next animation');
      _skipNextAnimation = true;
      _wsService.connect(); // reconnect WS + HTTP polling
    }
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    WidgetsBinding.instance.removeObserver(this);
    _wsService.dispose();
    _posController.dispose();
    _stopNotificationTimer?.cancel();
    _busNotifier.dispose();
    _showStopsSheet.dispose();
    _stopEventNotifier.dispose();
    super.dispose();
  }

  /// Build the map widget ONCE and cache it.
  /// Waits for BOTH style JSON AND first bus position so the camera
  /// starts at the real bus location instead of a hardcoded default.
  Widget _buildMap() {
    if (_styleJson == null || !_hasFirstPosition) {
      return Center(child: CircularProgressIndicator(color: AppColors.accent));
    }
    _cachedMap ??= MapLibreMap(
      key: ValueKey(_mapKey),
      styleString: _styleJson!,
      onMapCreated: _onMapCreated,
      onStyleLoadedCallback: _onStyleLoaded,
      initialCameraPosition: CameraPosition(
        target: _currentLatLng,
        zoom: _savedZoom,
      ),
      minMaxZoomPreference: const MinMaxZoomPreference(3.0, 14.0),
      myLocationEnabled: false,
      trackCameraPosition: true,
      onMapClick: (point, latLng) {
        if (_hasFirstPosition) {
          final dLat = (latLng.latitude - _currentLatLng.latitude).abs();
          final dLng = (latLng.longitude - _currentLatLng.longitude).abs();
          if (dLat < 0.002 && dLng < 0.002) {
            _showStopsSheet.value = true;
          }
        }
      },
    );
    return _cachedMap!;
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          // Map — cached, never rebuilds after creation
          _buildMap(),

          // Top gradient
          Positioned(
            top: 0, left: 0, right: 0, height: 120,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.bg.withValues(alpha: 0.9),
                      AppColors.bg.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // App title
          Positioned(
            top: topPadding + 12,
            left: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
                      ),
                      child: Icon(Icons.directions_bus_rounded, color: AppColors.accent, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Text('BUS', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 3.0)),
                    const SizedBox(width: 4),
                    Text('TRACKER', style: TextStyle(color: AppColors.accent.withValues(alpha: 0.7), fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 3.0)),
                  ],
                ),
                const SizedBox(height: 4),
                ValueListenableBuilder<BusPosition?>(
                  valueListenable: _busNotifier,
                  builder: (_, bus, __) => Text(
                    bus != null ? 'DL-01 | ${bus.routeName}' : 'Waiting for bus...',
                    style: TextStyle(color: AppColors.textFaint, fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.5),
                  ),
                ),
              ],
            ),
          ),

          // Theme toggle button (top-right, replaces ConnectionIndicator)
          Positioned(
            top: topPadding + 16,
            right: 16,
            child: GestureDetector(
              onTap: _toggleTheme,
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: AppColors.surfaceTranslucent,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: Icon(
                  isDark ? Icons.wb_sunny_rounded : Icons.nightlight_round,
                  color: isDark ? const Color(0xFFFFB800) : const Color(0xFF5C6BC0),
                  size: 22,
                ),
              ),
            ),
          ),

          // Right side buttons
          ValueListenableBuilder<BusPosition?>(
            valueListenable: _busNotifier,
            builder: (_, bus, __) => ValueListenableBuilder<bool>(
              valueListenable: _showStopsSheet,
              builder: (_, showSheet, __) {
                // Dynamic bottom: float above whatever bottom widget is showing
                final double bottomOffset;
                if (showSheet) {
                  // Above the stops sheet (55% of screen)
                  bottomOffset = MediaQuery.of(context).size.height * 0.55 + 16;
                } else if (bus != null) {
                  // Above the bottom info bar (~76px card + 24px margin)
                  bottomOffset = 24 + 76 + 16;
                } else {
                  bottomOffset = 40;
                }
                return AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                bottom: bottomOffset,
                right: 16,
                child: Column(
                  children: [
                    if (bus != null && !showSheet)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: GestureDetector(
                          onTap: () => _showStopsSheet.value = true,
                          child: Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceTranslucent,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.border),
                              boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 12, offset: const Offset(0, 4))],
                            ),
                            child: Icon(Icons.route_rounded, color: AppColors.textSubtle, size: 22),
                          ),
                        ),
                      ),
                    GestureDetector(
                      onTap: () {
                        _followBus = true;
                        if (_mapController != null && _hasFirstPosition) {
                          _mapController!.animateCamera(
                            CameraUpdate.newLatLngZoom(_currentLatLng, 15.0),
                            duration: const Duration(milliseconds: 1000),
                          );
                        }
                      },
                      child: Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          color: _followBus
                              ? AppColors.accent.withValues(alpha: 0.15)
                              : AppColors.surfaceTranslucent,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _followBus ? AppColors.accent.withValues(alpha: 0.3) : AppColors.border,
                          ),
                          boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 12, offset: const Offset(0, 4))],
                        ),
                        child: Icon(
                          _followBus ? Icons.gps_fixed_rounded : Icons.gps_not_fixed_rounded,
                          color: _followBus ? AppColors.accent : AppColors.textSubtle,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                ),
              );
              },
            ),
          ),

          // Stop notification
          ValueListenableBuilder<StopEvent?>(
            valueListenable: _stopEventNotifier,
            builder: (_, event, __) {
              if (event == null) return const SizedBox.shrink();
              return StopNotification(
                event: event,
                onDismiss: () {
                  _stopEventNotifier.value = null;
                  _stopNotificationTimer?.cancel();
                },
              );
            },
          ),

          // Route stops sheet
          ValueListenableBuilder<bool>(
            valueListenable: _showStopsSheet,
            builder: (_, showSheet, __) {
              if (!showSheet) return const SizedBox.shrink();
              final bus = _busNotifier.value;
              if (bus == null) return const SizedBox.shrink();
              return Positioned(
                left: 0, right: 0, bottom: 0,
                height: MediaQuery.of(context).size.height * 0.55,
                child: RouteStopsSheet(
                  busId: bus.busId,
                  routeName: bus.routeName,
                  stops: _wsService.stops,
                  currentStopIdx: bus.currentStopIdx,
                  busStatus: bus.status,
                  onClose: () => _showStopsSheet.value = false,
                ),
              );
            },
          ),

          // Bottom info bar
          ValueListenableBuilder<BusPosition?>(
            valueListenable: _busNotifier,
            builder: (_, bus, __) => ValueListenableBuilder<bool>(
              valueListenable: _showStopsSheet,
              builder: (_, showSheet, __) {
                if (bus == null || showSheet) return const SizedBox.shrink();
                return Positioned(
                  left: 16, right: 16, bottom: 24,
                  child: GestureDetector(
                    onTap: () => _showStopsSheet.value = true,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceHeavy,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.accent.withValues(alpha: 0.12)),
                        boxShadow: [BoxShadow(color: AppColors.shadowHeavy, blurRadius: 24, offset: const Offset(0, 8))],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                            ),
                            child: Icon(Icons.directions_bus_rounded, color: AppColors.accent, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(bus.busId, style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
                                const SizedBox(height: 2),
                                Text(
                                  bus.currentStopIdx >= 0 && _wsService.stops.isNotEmpty && bus.currentStopIdx < _wsService.stops.length
                                      ? 'Near ${_wsService.stops[bus.currentStopIdx].name}'
                                      : bus.routeName,
                                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('${bus.speedKmh.toStringAsFixed(0)} km/h', style: TextStyle(color: AppColors.accent, fontSize: 16, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text(
                                bus.status.toUpperCase(),
                                style: TextStyle(
                                  color: bus.status == 'at_stop' ? AppColors.warning : AppColors.accent.withValues(alpha: 0.6),
                                  fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.chevron_right_rounded, color: AppColors.textFaint, size: 24),
                        ],
                      ),
                    ),
                  ),
                );
            },
            ),
          ),
        ],
      ),
    );
  }
}
