enum DiscoverySource {
  mDNS,
  udp,
  cached,
  manual,
}

/// Represents a discovered peer device and its available endpoints.
class PeerModel {
  final String deviceId;
  final String name;
  final String platform;
  final List<String> ips;
  final int port;
  final Set<DiscoverySource> discoverySources;
  final DateTime lastSeen;

  PeerModel({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.ips,
    required this.port,
    required this.discoverySources,
    required this.lastSeen,
  });

  PeerModel copyWith({
    String? deviceId,
    String? name,
    String? platform,
    List<String>? ips,
    int? port,
    Set<DiscoverySource>? discoverySources,
    DateTime? lastSeen,
  }) {
    return PeerModel(
      deviceId: deviceId ?? this.deviceId,
      name: name ?? this.name,
      platform: platform ?? this.platform,
      ips: ips ?? this.ips,
      port: port ?? this.port,
      discoverySources: discoverySources ?? this.discoverySources,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  /// Merges endpoint and source metadata from another peer record into this instance.
  PeerModel merge(PeerModel other) {
    if (deviceId.isNotEmpty && other.deviceId.isNotEmpty && deviceId != other.deviceId) {
      throw Exception('Cannot merge peers with different device IDs');
    }

    final mergedIps = {...ips, ...other.ips}.toList();
    final mergedSources = {...discoverySources, ...other.discoverySources};
    final mergedLastSeen = lastSeen.isAfter(other.lastSeen) ? lastSeen : other.lastSeen;
    final newest = lastSeen.isAfter(other.lastSeen) ? this : other;

    return PeerModel(
      deviceId: deviceId.isNotEmpty ? deviceId : other.deviceId,
      name: newest.name,
      platform: (newest.platform == 'unknown' && other.platform != 'unknown') ? other.platform : newest.platform,
      ips: mergedIps,
      port: newest.port,
      discoverySources: mergedSources,
      lastSeen: mergedLastSeen,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PeerModel) return false;
    
    // Match by stable device identifier if present.
    if (deviceId.isNotEmpty && other.deviceId.isNotEmpty) {
      return deviceId == other.deviceId;
    }
    
    // Fall back to matching by network endpoint when device ID is absent.
    if (port == other.port && ips.any((ip) => other.ips.contains(ip))) {
      return true;
    }
    
    return false;
  }

  @override
  int get hashCode {
    if (deviceId.isNotEmpty) return deviceId.hashCode;
    return Object.hash(port, ips.isNotEmpty ? ips.first : 0);
  }

  @override
  String toString() {
    return 'PeerModel{name: $name, id: $deviceId, ips: $ips, port: $port, platform: $platform, sources: $discoverySources}';
  }
}
