import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';

Future<String> getLocalIp() async {
  final ips = await getAllLocalIps();
  return ips.isNotEmpty ? ips.first : "127.0.0.1";
}

/// Get ALL valid local IPv4 addresses
Future<List<String>> getAllLocalIps() async {
  final List<String> result = [];
  try {
    final info = NetworkInfo();
    var wifiIP = await info.getWifiIP();
    if (wifiIP != null && wifiIP.isNotEmpty && wifiIP != "127.0.0.1") {
      result.add(wifiIP);
    }

    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: true,
    );

    for (var interface_ in interfaces) {
      String name = interface_.name.toLowerCase();
      if (name.contains('virtual') ||
          name.contains('veth') ||
          name.contains('wsl') ||
          name.contains('vpn') ||
          name.contains('vmware') ||
          name.contains('vbox') ||
          name.contains('docker')) {
        continue;
      }
      for (var addr in interface_.addresses) {
        if (!addr.isLoopback &&
            addr.type == InternetAddressType.IPv4 &&
            !result.contains(addr.address)) {
          result.add(addr.address);
        }
      }
    }
  } catch (e) {
    debugPrint("IP Lookup Error: $e");
  }
  return result.isEmpty ? ["127.0.0.1"] : result;
}
