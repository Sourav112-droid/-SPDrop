import 'package:flutter/material.dart';

import '../shared/widgets/glass_card.dart';

// Incoming Transfer Dialog — Glass Design

class IncomingTransferDialog extends StatefulWidget {
  final String senderName;
  final String previewText;

  const IncomingTransferDialog({super.key, required this.senderName, required this.previewText});

  @override
  State<IncomingTransferDialog> createState() => _IncomingTransferDialogState();
}

class _IncomingTransferDialogState extends State<IncomingTransferDialog> {
  bool _alwaysTrust = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: GlassCard(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.all(24),
        borderColor: const Color(0xFF4F8EF7).withValues(alpha: 0.3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  const Color(0xFF4F8EF7).withValues(alpha: 0.2),
                  Colors.transparent,
                ]),
              ),
              child: const Icon(Icons.file_download_rounded, size: 36, color: Color(0xFF4F8EF7)),
            ),
            const SizedBox(height: 16),
            Text("Incoming Transfer", style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: 20, fontWeight: FontWeight.w700,
            )),
            const SizedBox(height: 8),
            Text("From: ${widget.senderName}", style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(widget.previewText, style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8), fontSize: 13,
              ), textAlign: TextAlign.center),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: _alwaysTrust,
                    onChanged: (val) {
                      setState(() { _alwaysTrust = val ?? false; });
                    },
                    fillColor: WidgetStateProperty.resolveWith((states) => 
                      states.contains(WidgetState.selected) ? const Color(0xFF4F8EF7) : Colors.transparent
                    ),
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                  ),
                ),
                const SizedBox(width: 8),
                Text("Always trust this device", style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context, {'accepted': false, 'trust': false}),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.red.withValues(alpha: 0.1),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                      ),
                      alignment: Alignment.center,
                      child: Text("Decline", style: TextStyle(color: Colors.red.shade300, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context, {'accepted': true, 'trust': _alwaysTrust}),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: const Color(0xFF4F8EF7).withValues(alpha: 0.15),
                        border: Border.all(color: const Color(0xFF4F8EF7).withValues(alpha: 0.3)),
                      ),
                      alignment: Alignment.center,
                      child: const Text("Accept", style: TextStyle(
                        color: Color(0xFF4F8EF7), fontWeight: FontWeight.w700,
                      )),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
