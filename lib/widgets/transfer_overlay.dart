import 'package:flutter/material.dart';
import '../shared/widgets/glass_card.dart';
import '../core/theme/theme_service.dart';

/// Fullscreen modal overlay visualizing active transfer progress, speed, ETA, and completion status.
class TransferOverlay extends StatelessWidget {
  final double progress; // 0.0 to 1.0 range
  final double speedMBps;
  final int etaSeconds;
  final String currentFile;
  final String statusLabel;
  final bool isCompleted;
  final VoidCallback? onCancel;
  final VoidCallback? onDone;

  const TransferOverlay({
    super.key,
    required this.progress,
    required this.speedMBps,
    required this.etaSeconds,
    required this.currentFile,
    this.statusLabel = 'Transferring',
    this.isCompleted = false,
    this.onCancel,
    this.onDone,
  });

  String get _etaString {
    if (etaSeconds <= 0) return '--:--';
    final min = etaSeconds ~/ 60;
    final sec = etaSeconds % 60;
    if (min > 0) return '${min}m ${sec}s';
    return '${sec}s';
  }

  String get _speedString {
    if (speedMBps >= 1.0) {
      return '${speedMBps.toStringAsFixed(1)} MB/s';
    } else {
      return '${(speedMBps * 1024).toStringAsFixed(0)} KB/s';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = SpDropThemeProvider.of(context);

    return Container(
      color: theme.scaffoldBg.withValues(alpha: 0.95),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(flex: 2),

            SizedBox(
              width: 180,
              height: 180,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: 1.0,
                      strokeWidth: 6,
                      strokeCap: StrokeCap.round,
                      color: theme.textPrimary.withValues(alpha: 0.06),
                    ),
                  ),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: progress),
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) {
                      return SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: value,
                          strokeWidth: 6,
                          strokeCap: StrokeCap.round,
                          color: isCompleted
                              ? theme.success
                              : theme.primary,
                        ),
                      );
                    },
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isCompleted)
                        Icon(
                          Icons.check_rounded,
                          color: theme.success,
                          size: 48,
                        )
                      else ...[
                        Text(
                          '${(progress * 100).toInt()}%',
                          style: TextStyle(
                            color: theme.textPrimary,
                            fontSize: 36,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          _speedString,
                          style: TextStyle(
                            color: theme.primary
                                .withValues(alpha: 0.8),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            Text(
              isCompleted ? 'Transfer Complete!' : statusLabel,
              style: TextStyle(
                color: isCompleted
                    ? theme.success
                    : theme.textPrimary.withValues(alpha: 0.9),
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                currentFile,
                style: TextStyle(
                  color: theme.textSecondary.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            if (!isCompleted) ...[
              const SizedBox(height: 6),
              Text(
                'ETA: $_etaString',
                style: TextStyle(
                  color: theme.textTertiary.withValues(alpha: 0.6),
                  fontSize: 13,
                ),
              ),
            ],

            const Spacer(flex: 2),

            if (isCompleted) ...[
              _buildActionButton(
                theme: theme,
                label: 'Done',
                color: theme.success,
                onTap: onDone,
                icon: Icons.check_circle_outline,
              ),
            ] else ...[
              _buildActionButton(
                theme: theme,
                label: 'Cancel',
                color: theme.error,
                onTap: onCancel,
                icon: Icons.close_rounded,
              ),
            ],

            const SizedBox(height: 40),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lan_outlined,
                  color: theme.textTertiary.withValues(alpha: 0.4),
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  'LAN Transfer • Not using internet',
                  style: TextStyle(
                    color: theme.textTertiary.withValues(alpha: 0.4),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required AppThemeData theme,
    required String label,
    required Color color,
    required VoidCallback? onTap,
    required IconData icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: color.withValues(alpha: 0.15),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
