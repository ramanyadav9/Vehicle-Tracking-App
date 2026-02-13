
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/bus_position.dart';
import '../services/websocket_service.dart';
import '../widgets/bus_detail_sheet.dart';
import '../widgets/connection_indicator.dart';
import '../widgets/stop_notification.dart';

const _busColor = Color(0xFF00E5CC);

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final _wsService = WebSocketService();
  final _mapController = MapController();
  BusPosition? _bus;
  bool _followBus = true;

  late AnimationController _markerFadeController;
  late Animation<double> _markerFadeAnimation;

  // Stop notification state
  StopEvent? _currentStopEvent;
  Timer? _stopNotificationTimer;

  @override
  void initState() {
    super.initState();

    _markerFadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _markerFadeAnimation = CurvedAnimation(
      parent: _markerFadeController,
      curve: Curves.easeOut,
    );

    _wsService.connect();

    // Listen for bus position updates
    _wsService.busStream.listen((buses) {
      if (buses.isEmpty) return;
      final newBus = buses.first;
      debugPrint('[MAP] Update: lat=${newBus.latitude.toStringAsFixed(6)} lng=${newBus.longitude.toStringAsFixed(6)} status=${newBus.status}');
      setState(() {
        _bus = newBus;
      });

      // Only re-center when bus is near edge of visible area
      if (_followBus && _bus != null) {
        try {
          final busLatLng = LatLng(_bus!.latitude, _bus!.longitude);
          final cam = _mapController.camera;
          final bounds = cam.visibleBounds;
          final latPad = (bounds.north - bounds.south) * 0.30;
          final lngPad = (bounds.east - bounds.west) * 0.30;
          final isNearEdge = _bus!.latitude > bounds.north - latPad ||
              _bus!.latitude < bounds.south + latPad ||
              _bus!.longitude > bounds.east - lngPad ||
              _bus!.longitude < bounds.west + lngPad;
          if (isNearEdge) {
            debugPrint('[MAP] Re-centering on bus');
            _mapController.move(busLatLng, cam.zoom);
          }
        } catch (e) {
          debugPrint('[MAP] Follow error: $e');
        }
      }

      if (!_markerFadeController.isCompleted) {
        _markerFadeController.forward();
      }
    });

    // Listen for stop events
    _wsService.stopStream.listen((event) {
      _showStopNotification(event);
    });
  }

  void _showStopNotification(StopEvent event) {
    _stopNotificationTimer?.cancel();
    setState(() {
      _currentStopEvent = event;
    });
    // Auto-dismiss after 4 seconds
    _stopNotificationTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _currentStopEvent = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _wsService.dispose();
    _markerFadeController.dispose();
    _stopNotificationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: Stack(
        children: [
          // Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(28.6674, 77.2274),
              initialZoom: 15.5,
              backgroundColor: const Color(0xFF0D1117),
              onTap: (_, __) {},
              onPositionChanged: (pos, hasGesture) {
                // Disable follow when user drags the map
                if (hasGesture) {
                  _followBus = false;
                }
              },
            ),
            children: [
              // Dark map tiles
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.bustracker.bus_tracker_app',
                retinaMode: true,
              ),

              // Bus marker
              if (_bus != null)
                FadeTransition(
                  opacity: _markerFadeAnimation,
                  child: MarkerLayer(
                    markers: [_buildBusMarker(_bus!)],
                  ),
                ),
            ],
          ),

          // Top gradient overlay
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 120,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF0D1117).withValues(alpha: 0.9),
                    const Color(0xFF0D1117).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),

          // App title
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _busColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _busColor.withValues(alpha: 0.25),
                        ),
                      ),
                      child: const Icon(
                        Icons.directions_bus_rounded,
                        color: _busColor,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'TRANSIT',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3.0,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'TRACK',
                      style: TextStyle(
                        color: _busColor.withValues(alpha: 0.7),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3.0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _bus != null
                      ? 'DL-01 | ${_bus!.routeName}'
                      : 'Waiting for bus...',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),

          // Connection indicator
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: ConnectionIndicator(
              statusNotifier: _wsService.connectionStatus,
              busCount: _bus != null ? 1 : 0,
            ),
          ),

          // Follow bus / recenter button
          Positioned(
            bottom: _bus != null ? 290 : 40,
            right: 16,
            child: GestureDetector(
              onTap: () {
                setState(() => _followBus = true);
                if (_bus != null) {
                  _mapController.move(
                    LatLng(_bus!.latitude, _bus!.longitude),
                    15.0,
                  );
                }
              },
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _followBus
                      ? _busColor.withValues(alpha: 0.15)
                      : const Color(0xFF0D1117).withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _followBus
                        ? _busColor.withValues(alpha: 0.3)
                        : Colors.white.withValues(alpha: 0.08),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  _followBus
                      ? Icons.gps_fixed_rounded
                      : Icons.gps_not_fixed_rounded,
                  color: _followBus
                      ? _busColor
                      : Colors.white.withValues(alpha: 0.6),
                  size: 22,
                ),
              ),
            ),
          ),

          // Stop notification flash
          if (_currentStopEvent != null)
            StopNotification(
              event: _currentStopEvent!,
              onDismiss: () {
                setState(() => _currentStopEvent = null);
                _stopNotificationTimer?.cancel();
              },
            ),

          // Bus detail sheet (always shown for single bus)
          if (_bus != null)
            BusDetailSheet(
              bus: _bus!,
              onClose: () {},
            ),
        ],
      ),
    );
  }

  Marker _buildBusMarker(BusPosition bus) {
    final isAtStop = bus.status == 'at_stop';

    return Marker(
      point: LatLng(bus.latitude, bus.longitude),
      width: 56,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Pulse ring when at stop
          if (isAtStop)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.8, end: 1.3),
              duration: const Duration(milliseconds: 800),
              builder: (context, value, child) {
                return Container(
                  width: 56 * value,
                  height: 56 * value,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _busColor.withValues(alpha: 0.4 / value),
                      width: 2,
                    ),
                  ),
                );
              },
            ),
          // Outer glow ring
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _busColor.withValues(alpha: 0.4),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: _busColor.withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          // Main marker body
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              shape: BoxShape.circle,
              border: Border.all(
                color: _busColor,
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: _busColor.withValues(alpha: 0.25),
                  blurRadius: 12,
                  spreadRadius: -2,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.directions_bus_rounded,
              color: _busColor,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}
