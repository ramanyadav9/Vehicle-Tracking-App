class BusPosition {
  final String busId;
  final String routeName;
  final double latitude;
  final double longitude;
  final double heading;
  final double speedKmh;
  final double timestamp;
  final String status;

  BusPosition({
    required this.busId,
    required this.routeName,
    required this.latitude,
    required this.longitude,
    required this.heading,
    required this.speedKmh,
    required this.timestamp,
    required this.status,
  });

  factory BusPosition.fromJson(Map<String, dynamic> json) {
    return BusPosition(
      busId: json['bus_id'] as String,
      routeName: json['route_name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      heading: (json['heading'] as num).toDouble(),
      speedKmh: (json['speed_kmh'] as num).toDouble(),
      timestamp: (json['timestamp'] as num).toDouble(),
      status: json['status'] as String,
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
