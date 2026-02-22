class BusPosition {
  final String busId;
  final String routeName;
  final double latitude;
  final double longitude;
  final double heading;
  final double speedKmh;
  final double timestamp;
  final String status;
  final int currentStopIdx;

  BusPosition({
    required this.busId,
    required this.routeName,
    required this.latitude,
    required this.longitude,
    required this.heading,
    required this.speedKmh,
    required this.timestamp,
    required this.status,
    required this.currentStopIdx,
  });

  /// Safe number parser — handles both num and String from Redis
  static double _toDouble(dynamic v, [double fallback = 0.0]) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }

  static int _toInt(dynamic v, [int fallback = -1]) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  factory BusPosition.fromJson(Map<String, dynamic> json) {
    return BusPosition(
      busId: json['bus_id']?.toString() ?? '',
      routeName: json['route_name']?.toString() ?? '',
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
      heading: _toDouble(json['heading']),
      speedKmh: _toDouble(json['speed_kmh']),
      timestamp: _toDouble(json['timestamp']),
      status: json['status']?.toString() ?? 'unknown',
      currentStopIdx: _toInt(json['current_stop_idx'], -1),
    );
  }

  String get headingDirection {
    if (heading >= 337.5 || heading < 22.5) return 'N';
    if (heading >= 22.5 && heading < 67.5) return 'NE';
    if (heading >= 67.5 && heading < 112.5) return 'E';
    if (heading >= 112.5 && heading < 157.5) return 'SE';
    if (heading >= 157.5 && heading < 202.5) return 'S';
    if (heading >= 202.5 && heading < 247.5) return 'SW';
    if (heading >= 247.5 && heading < 292.5) return 'W';
    return 'NW';
  }

  String get timeSinceUpdate {
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    final diff = (now - timestamp).round();
    if (diff < 5) return 'Just now';
    if (diff < 60) return '${diff}s ago';
    if (diff < 3600) return '${(diff / 60).round()}m ago';
    return '${(diff / 3600).round()}h ago';
  }
}
