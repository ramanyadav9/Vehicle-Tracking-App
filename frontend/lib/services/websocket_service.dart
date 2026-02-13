import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
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

class WebSocketService {
  static const String _wsUrl = 'ws://10.0.2.2:8000/ws/buses';
  static const String _httpUrl = 'http://10.0.2.2:8000/api/buses';

  WebSocketChannel? _channel;
  final _busController = StreamController<List<BusPosition>>.broadcast();
  final _stopController = StreamController<StopEvent>.broadcast();
  final connectionStatus = ValueNotifier(ConnectionStatus.disconnected);
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  Timer? _pollTimer;
  int _reconnectAttempts = 0;
  String _dataSource = 'unknown';
  bool _wsConnected = false;

  Stream<List<BusPosition>> get busStream => _busController.stream;
  Stream<StopEvent> get stopStream => _stopController.stream;
  String get dataSource => _dataSource;

  void connect() {
    _connectWebSocket();
    _startHttpPolling();
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
    if (connectionStatus.value == ConnectionStatus.connecting) return;
    connectionStatus.value = ConnectionStatus.connecting;
    debugPrint('[WS] Connecting to $_wsUrl...');

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));

      _channel!.stream.listen(
        (data) {
          if (!_wsConnected) {
            _wsConnected = true;
            connectionStatus.value = ConnectionStatus.connected;
            debugPrint('[WS] Connected! Switching to WebSocket mode.');
            _startPing();
          }
          _reconnectAttempts = 0;

          try {
            final decoded = jsonDecode(data as String) as Map<String, dynamic>;
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

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      try {
        _channel?.sink.add('ping');
      } catch (_) {}
    });
  }

  void _cleanupWs() {
    _pingTimer?.cancel();
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
    _channel?.sink.close();
    _busController.close();
    _stopController.close();
    connectionStatus.dispose();
  }
}
