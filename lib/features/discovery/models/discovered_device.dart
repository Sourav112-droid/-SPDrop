class DiscoveredDevice {
  final String name;
  final List<String> ips;
  final int port;
  final String platform; // 'android', 'windows', 'ios', 'unknown'
  final String? stableId; // Unique device ID for deduplication
  DiscoveredDevice({
    required this.name,
    required this.ips,
    required this.port,
    this.platform = 'unknown',
    this.stableId,
  });

  /// Create a copy with updated fields
  DiscoveredDevice copyWith({
    String? name,
    List<String>? ips,
    int? port,
    String? platform,
    String? stableId,
  }) {
    return DiscoveredDevice(
      name: name ?? this.name,
      ips: ips ?? this.ips,
      port: port ?? this.port,
      platform: platform ?? this.platform,
      stableId: stableId ?? this.stableId,
    );
  }
}
