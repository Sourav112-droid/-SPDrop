import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Security verification dialog displaying peer public key fingerprint and SAS authentication code.
class TrustDeviceDialog extends StatefulWidget {
  final String deviceName;
  final String platform;
  final Uint8List peerPublicKey;
  final String? sas;
  final bool keyChanged;

  const TrustDeviceDialog({
    super.key,
    required this.deviceName,
    required this.platform,
    required this.peerPublicKey,
    this.sas,
    this.keyChanged = false,
  });

  @override
  State<TrustDeviceDialog> createState() => _TrustDeviceDialogState();
}

class _TrustDeviceDialogState extends State<TrustDeviceDialog> {
  bool _sasConfirmed = false;

  String get _fingerprint {
    return '${widget.peerPublicKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join('').substring(0, 32)}...';
  }

  String get _formattedSas {
    if (widget.sas == null || widget.sas!.length < 4) return 'UNKNOWN';
    return '${widget.sas!.substring(0, 2)} ${widget.sas!.substring(2, 4)}';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.keyChanged ? 'SECURITY WARNING' : 'Verify New Device', 
        style: TextStyle(color: widget.keyChanged ? Colors.red : null, fontWeight: widget.keyChanged ? FontWeight.bold : null)
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.keyChanged)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 16),
                color: Colors.red.withValues(alpha: 0.1),
                child: const Text('WARNING: This device (IP) previously connected with a different identity key. This could be a Man-in-the-Middle attack or the device was reset. Verify the SAS carefully!', 
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)
                ),
              )
            else
              const Text('An unknown device is trying to connect.'),
            const SizedBox(height: 16),
            Text('Name: ${widget.deviceName}', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Platform: ${widget.platform}'),
            const SizedBox(height: 8),
            const Text('Public Key Fingerprint:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(
              _fingerprint,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            if (widget.sas != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text('Authentication Code (SAS)', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                      _formattedSas,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 24,
                        letterSpacing: 4,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'CRITICAL: You MUST verify that the other device displays this EXACT SAME code. Do not accept if the codes differ.',
                style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('I have manually verified the code matches on both devices', style: TextStyle(fontSize: 12)),
                value: _sasConfirmed,
                onChanged: (val) {
                  setState(() {
                    _sasConfirmed = val ?? false;
                  });
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Reject', style: TextStyle(color: Colors.red)),
        ),
        FilledButton(
          onPressed: (widget.sas == null || _sasConfirmed)
              ? () => Navigator.of(context).pop(true)
              : null,
          child: const Text('Accept & Trust'),
        ),
      ],
    );
  }
}
