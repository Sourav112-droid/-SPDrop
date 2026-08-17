/// Represents a paired and trusted remote peer device configuration.
class TrustedDevice {
  final String name;
  final String ip;
  final int port;
  final DateTime lastSeen;
  final String platform; // 'android', 'windows', 'ios'
  final bool isTrusted;  // verified via OTP
  final bool notificationsEnabled;
  final bool isDefault; // explicit default device
  final String? stableId; // Stable device ID for deduplication
  final String? publicKeyFingerprint; // Cryptographic Trust Anchor

  TrustedDevice({
    required this.name,
    required this.ip,
    required this.port,
    required this.lastSeen,
    this.platform = 'unknown',
    this.isTrusted = false,
    this.notificationsEnabled = false,
    this.isDefault = false,
    this.stableId,
    this.publicKeyFingerprint,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'ip': ip,
    'port': port,
    'lastSeen': lastSeen.toIso8601String(),
    'platform': platform,
    'isTrusted': isTrusted,
    'notificationsEnabled': notificationsEnabled,
    'isDefault': isDefault,
    'stableId': stableId,
    'publicKeyFingerprint': publicKeyFingerprint,
  };

  factory TrustedDevice.fromJson(Map<String, dynamic> json) {
    return TrustedDevice(
      name: json['name'],
      ip: json['ip'],
      port: json['port'] ?? 8888,
      lastSeen: DateTime.parse(json['lastSeen']),
      platform: json['platform'] ?? 'unknown',
      isTrusted: json['isTrusted'] ?? false,
      notificationsEnabled: json['notificationsEnabled'] ?? false,
      isDefault: json['isDefault'] ?? false,
      stableId: json['stableId'],
      publicKeyFingerprint: json['publicKeyFingerprint'],
    );
  }

  TrustedDevice copyWith({
    String? name,
    String? ip,
    int? port,
    DateTime? lastSeen,
    String? platform,
    bool? isTrusted,
    bool? notificationsEnabled,
    bool? isDefault,
    String? stableId,
    String? publicKeyFingerprint,
  }) {
    return TrustedDevice(
      name: name ?? this.name,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      lastSeen: lastSeen ?? this.lastSeen,
      platform: platform ?? this.platform,
      isTrusted: isTrusted ?? this.isTrusted,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      isDefault: isDefault ?? this.isDefault,
      stableId: stableId ?? this.stableId,
      publicKeyFingerprint: publicKeyFingerprint ?? this.publicKeyFingerprint,
    );
  }
}
