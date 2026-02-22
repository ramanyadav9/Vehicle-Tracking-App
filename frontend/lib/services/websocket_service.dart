import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config.dart';
import '../models/bus_position.dart';

enum ConnectionStatus { connected, connecting, disconnected }

/// Event emitted when bus arrives at a stop
class StopEvent {
  final String stopName;
  final double stopLat;
  final double stopLng;
  final int stopIndex;
  final int totalStops;

  StopEvent({
    required this.stopName,
    required this.stopLat,
    required this.stopLng,
    required this.stopIndex,
    required this.totalStops,
  });

  factory StopEvent.fromJson(Map<String, dynamic> json) {
    return StopEvent(
      stopName: json['stop_name'] as String,
      stopLat: (json['stop_lat'] as num).toDouble(),
      stopLng: (json['stop_lng'] as num).toDouble(),
      stopIndex: json['stop_index'] as int,
      totalStops: json['total_stops'] as int,
    );
  }
}

/// A bus stop on the route
class BusStop {
  final String name;
  final double lat;
  final double lng;
  final int waypointIdx;

  BusStop({required this.name, required this.lat, required this.lng, required this.waypointIdx});

  factory BusStop.fromJson(Map<String, dynamic> json) {
    return BusStop(
      name: json['name'] as String,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      waypointIdx: (json['waypoint_idx'] as num).toInt(),
    );
  }
}

class WebSocketService {
  static const String _wsUrl = 'ws://$backendHost:$backendPort/ws/buses';
  static const String _httpUrl = 'http://$backendHost:$backendPort/api/buses';
  static const String _stopsUrl = 'http://$backendHost:$backendPort/api/stops';

  WebSocketChannel? _channel;
  StreamSubscription? _wsSubscription;
  final _busController = StreamController<List<BusPosition>>.broadcast();
  final _stopController = StreamController<StopEvent>.broadcast();
  final connectionStatus = ValueNotifier(ConnectionStatus.disconnected);
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  Timer? _pollTimer;
  int _reconnectAttempts = 0;
  String _dataSource = 'unknown';
  bool _wsConnected = false;

  List<BusStop> _stops = [];

  Stream<List<BusPosition>> get busStream => _busController.stream;
  Stream<StopEvent> get stopStream => _stopController.stream;
  String get dataSource => _dataSource;
  List<BusStop> get stops => _stops;

  void connect() {
    _reconnectTimer?.cancel();
    _forceCloseWs();

    // Step 1: Fetch latest state immediately via REST (instant data)
    _fetchLatestNow();
    _fetchStops();

    // Step 2: Connect WebSocket for real-time updates
    _connectWebSocket();

    // Step 3: HTTP polling as fallback if WS drops
    _startHttpPolling();
  }

  /// Immediate one-shot REST fetch — gives us data right away without waiting
  /// for WS handshake or poll timer
  Future<void> _fetchLatestNow() async {
    try {
      final response = await http.get(Uri.parse(_httpUrl))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final busList = (decoded['buses'] as List)
            .map((b) => BusPosition.fromJson(b as Map<String, dynamic>))
            .toList();
        if (busList.isNotEmpty) {
          debugPrint('[REST] Instant fetch: ${busList.length} buses | lat=${busList.first.latitude.toStringAsFixed(5)}');
          _busController.add(busList);
        }
      }
    } catch (e) {
      debugPrint('[REST] Instant fetch error: $e');
    }
  }

  /// Force close everything — old channel, subscription, timers
  void _forceCloseWs() {
    _pingTimer?.cancel();
    _wsSubscription?.cancel();
    _wsSubscription = null;
    try { _channel?.sink.close(); } catch (_) {}
    _channel = null;
    _wsConnected = false;
    connectionStatus.value = ConnectionStatus.disconnected;
  }

  /// Fetch bus stops from backend
  Future<void> _fetchStops() async {
    try {
      final response = await http.get(Uri.parse(_stopsUrl))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        _stops = (decoded['stops'] as List)
            .map((s) => BusStop.fromJson(s as Map<String, dynamic>))
            .toList();
        debugPrint('[STOPS] Loaded ${_stops.length} stops');
      }
    } catch (e) {
      debugPrint('[STOPS] Fetch error: $e');
    }
  }

  /// HTTP polling — always works, runs every 3s as fallback
  void _startHttpPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_wsConnected) return; // skip polling when WS is active
      try {
        final response = await http.get(Uri.parse(_httpUrl))
            .timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body) as Map<String, dynamic>;
          final busList = (decoded['buses'] as List)
              .map((b) => BusPosition.fromJson(b as Map<String, dynamic>))
              .toList();
          if (busList.isNotEmpty) {
            debugPrint('[HTTP] Polled ${busList.length} buses | lat=${busList.first.latitude.toStringAsFixed(5)}');
            if (connectionStatus.value != ConnectionStatus.connected) {
              connectionStatus.value = ConnectionStatus.connected;
            }
            _dataSource = 'http-poll';
            _busController.add(busList);
          }
        }
      } catch (e) {
        debugPrint('[HTTP] Poll error: $e');
      }
    });
  }

  /// WebSocket — preferred, real-time with stop events
  void _connectWebSocket() {
    // Guard: don't connect if already connecting or connected
    if (_wsConnected || connectionStatus.value == ConnectionStatus.connecting) {
      debugPrint('[WS] Already ${_wsConnected ? "connected" : "connecting"}, skipping');
      return;
    }
    connectionStatus.value = ConnectionStatus.connecting;
    debugPrint('[WS] Connecting to $_wsUrl...');

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));

      _wsSubscription = _channel!.stream.listen(
        (data) {
          final msg = data as String;

          // Ignore pong responses
          if (msg == 'pong') return;

          if (!_wsConnected) {
            _wsConnected = true;
            connectionStatus.value = ConnectionStatus.connected;
            debugPrint('[WS] Connected! Switching to WebSocket mode.');
            _startPing();
          }
          _reconnectAttempts = 0;

          try {
            final decoded = jsonDecode(msg) as Map<String, dynamic>;
            _dataSource = (decoded['source'] as String?) ?? 'unknown';
            final busList = (decoded['buses'] as List)
                .map((b) => BusPosition.fromJson(b as Map<String, dynamic>))
                .toList();
            debugPrint('[WS] Received ${busList.length} buses | lat=${busList.first.latitude.toStringAsFixed(5)}');
            _busController.add(busList);

            // Check for stop event
            if (decoded.containsKey('stop_event') &&
                decoded['stop_event'] != null) {
              final stopEvent = StopEvent.fromJson(
                  decoded['stop_event'] as Map<String, dynamic>);
              debugPrint('[WS] Stop event: ${stopEvent.stopName}');
              _stopController.add(stopEvent);
            }
          } catch (e) {
            debugPrint('[WS] Parse error: $e');
          }
        },
        onError: (error) {
          debugPrint('[WS] Error: $error');
          _cleanupWs();
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('[WS] Connection closed');
          _cleanupWs();
          _scheduleReconnect();
        },
      );
    } catch (e) {
      debugPrint('[WS] Connect error: $e');
      _cleanupWs();
      _scheduleReconnect();
    }
  }

  /// Ping every 10s to keep connection alive
  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      try {
        _channel?.sink.add('ping');
      } catch (_) {
        _cleanupWs();
        _scheduleReconnect();
      }
    });
  }

  void _cleanupWs() {
    _pingTimer?.cancel();
    _wsSubscription?.cancel();
    _wsSubscription = null;
    _channel = null;
    _wsConnected = false;
  }

  void _scheduleReconnect() {
    final delaySec = (_reconnectAttempts < 5)
        ? (1 << _reconnectAttempts)
        : 30;
    _reconnectAttempts++;
    debugPrint('[WS] Reconnecting in ${delaySec}s (attempt $_reconnectAttempts)');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySec), _connectWebSocket);
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _pollTimer?.cancel();
    _wsSubscription?.cancel();
    try { _channel?.sink.close(); } catch (_) {}
    _busController.close();
    _stopController.close();
    connectionStatus.dispose();
  }
}
