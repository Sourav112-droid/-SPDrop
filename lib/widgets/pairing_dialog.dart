import 'package:flutter/material.dart';
import '../shared/widgets/glass_card.dart';

/// Modal dialog for displaying or inputting a 6-digit OTP pairing code to verify trusted device state.
class PairingDialog extends StatefulWidget {
  final String? pairingCode;
  final String deviceName;
  final Function(String code)? onCodeEntered;
  final VoidCallback? onCancel;

  const PairingDialog({
    super.key,
    this.pairingCode,
    required this.deviceName,
    this.onCodeEntered,
    this.onCancel,
  });

  @override
  State<PairingDialog> createState() => _PairingDialogState();
}

class _PairingDialogState extends State<PairingDialog> {
  final _controllers = List.generate(6, (_) => TextEditingController());
  final _focusNodes = List.generate(6, (_) => FocusNode());

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _onDigitChanged(int index, String value) {
    if (value.isEmpty && index > 0) {
      _controllers[index].text = '';
      _focusNodes[index - 1].requestFocus();
      return;
    }
    if (value.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
    final code = _controllers.map((c) => c.text).join();
    if (code.length == 6) {
      widget.onCodeEntered?.call(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isShowingCode = widget.pairingCode != null;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: GlassCard(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.all(24),
        borderColor: const Color(0xFFFFB347).withValues(alpha: 0.3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFFB347).withValues(alpha: 0.2),
                    Colors.transparent,
                  ],
                ),
              ),
              child: const Icon(
                Icons.handshake_outlined,
                color: Color(0xFFFFB347),
                size: 28,
              ),
            ),
            const SizedBox(height: 16),

            Text(
              isShowingCode ? 'Your Pairing Code' : 'Enter Pairing Code',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.95),
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),

            Text(
              isShowingCode
                  ? 'Show this code to "${widget.deviceName}" to pair'
                  : 'Enter the code shown on "${widget.deviceName}"',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            if (isShowingCode) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: widget.pairingCode!.split('').map((digit) {
                  return Container(
                    width: 42,
                    height: 54,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white.withValues(alpha: 0.08),
                      border: Border.all(
                        color: const Color(0xFFFFB347).withValues(alpha: 0.3),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      digit,
                      style: const TextStyle(
                        color: Color(0xFFFFB347),
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Text(
                'Waiting for peer to enter code...',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 12,
                ),
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (index) {
                  return Container(
                    width: 42,
                    height: 54,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    child: TextField(
                      controller: _controllers[index],
                      focusNode: _focusNodes[index],
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      maxLength: 1,
                      style: const TextStyle(
                        color: Color(0xFFFFB347),
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.06),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: const Color(0xFFFFB347)
                                .withValues(alpha: 0.2),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFFFB347),
                          ),
                        ),
                      ),
                      onChanged: (value) => _onDigitChanged(index, value),
                    ),
                  );
                }),
              ),
            ],

            const SizedBox(height: 24),

            GestureDetector(
              onTap: widget.onCancel ?? () => Navigator.of(context).pop(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white.withValues(alpha: 0.06),
                ),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
