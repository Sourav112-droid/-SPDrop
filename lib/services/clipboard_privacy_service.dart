import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/identity/identity_service.dart';

/// Heuristic privacy filter preventing automatic transmission of sensitive clipboard content
/// (e.g., JWT tokens, PEM private keys, payment card numbers, one-time passwords).
class ClipboardPrivacyService {
  static final RegExp _jwtRegex = RegExp(r'^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$');
  static final RegExp _privateKeyRegex = RegExp(r'-----BEGIN (.*)PRIVATE KEY-----');
  static final RegExp _creditCardRegex = RegExp(r'\b(?:\d{4}[ -]?){3}\d{4}\b|\b\d{4}[ -]?\d{6}[ -]?\d{5}\b');
  static final RegExp _otpRegex = RegExp(r'^\s*([0-9]{4,8}|[A-Z0-9]{6,8})\s*$');
  
  /// Evaluates whether text matches known sensitive patterns.
  static bool isContentSensitive(String text) {
    if (text.isEmpty) return false;
    
    // Fast-path length guard to prevent heavy regex execution on large payloads.
    if (text.length > 50000) {
       if (_privateKeyRegex.hasMatch(text.substring(0, 5000))) {
         logPrivacyEvent('Sensitive clipboard content blocked: Private Key detected in large text.');
         return true;
       }
       return false;
    }
    
    if (_jwtRegex.hasMatch(text.trim())) {
      logPrivacyEvent('Sensitive clipboard content blocked: JWT detected.');
      return true;
    }
    
    if (_privateKeyRegex.hasMatch(text)) {
      logPrivacyEvent('Sensitive clipboard content blocked: Private Key detected.');
      return true;
    }
    
    if (_creditCardRegex.hasMatch(text)) {
      logPrivacyEvent('Sensitive clipboard content blocked: Credit Card pattern detected.');
      return true;
    }
    
    if (text.length < 20) {
      if (_otpRegex.hasMatch(text)) {
        // Exclude common 4-digit years (1900-2099) from OTP heuristic.
        final trimmed = text.trim();
        if (RegExp(r'^(19|20)\d{2}$').hasMatch(trimmed)) {
          return false;
        }
        logPrivacyEvent('Sensitive clipboard content blocked: OTP pattern detected.');
        return true;
      }
    }
    
    return false;
  }
  
  /// Safe logging that never prints the payload.
  static void logPrivacyEvent(String event) {
    debugPrint('[Privacy] $event');
  }
  
  static Future<bool> isDeviceAllowedForClipboard(String fingerprint) async {
    final prefs = await SharedPreferences.getInstance();
    final allowedDevices = prefs.getStringList('clipboard_allowed_devices') ?? [];
    return allowedDevices.contains(fingerprint);
  }

  static Future<void> setDeviceAllowedForClipboard(String fingerprint, bool allowed) async {
    final prefs = await SharedPreferences.getInstance();
    final allowedDevices = prefs.getStringList('clipboard_allowed_devices') ?? [];
    if (allowed) {
      if (!allowedDevices.contains(fingerprint)) allowedDevices.add(fingerprint);
    } else {
      allowedDevices.remove(fingerprint);
    }
    await prefs.setStringList('clipboard_allowed_devices', allowedDevices);
  }

  /// Checks whether clipboard sync is authorized to a specific device.
  static Future<bool> canSyncToDevice(String? peerPublicKeyFingerprint, String deviceName) async {
    // Current policy: Target must be a cryptographically trusted device AND explicitly allowed for clipboard.
    if (peerPublicKeyFingerprint == null || peerPublicKeyFingerprint.isEmpty) {
      logPrivacyEvent('Clipboard sync blocked: Target device "$deviceName" did not provide a public key fingerprint.');
      return false;
    }
    
    final identityService = IdentityService();
    bool isTrusted = await identityService.isFingerprintTrusted(peerPublicKeyFingerprint);
    if (!isTrusted) {
      logPrivacyEvent('Clipboard sync blocked: Target device "$deviceName" ($peerPublicKeyFingerprint) is not trusted.');
      return false;
    }

    bool isAllowed = await isDeviceAllowedForClipboard(peerPublicKeyFingerprint);
    if (!isAllowed) {
      logPrivacyEvent('Clipboard sync blocked: Target device "$deviceName" is trusted but not allowed for clipboard sync.');
      return false;
    }

    return true;
  }
}
