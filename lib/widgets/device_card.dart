import 'package:flutter/material.dart';
import '../shared/widgets/glass_card.dart';
import '../shared/widgets/pulse_indicator.dart';

/// Interactive card displaying peer device status, platform icon, trust state, and action triggers.
class DeviceCard extends StatefulWidget {
  final String name;
  final String platform;
  final bool isTrusted;
  final bool isConnected;
  final bool isOffline;
  final VoidCallback? onSend;
  final VoidCallback? onPair;
  final VoidCallback? onConnect;
  final VoidCallback? onDisconnect;

  const DeviceCard({
    super.key,
    required this.name,
    this.platform = 'unknown',
    this.isTrusted = false,
    this.isConnected = false,
    this.isOffline = false,
    this.onSend,
    this.onPair,
    this.onConnect,
    this.onDisconnect,
  });

  @override
  State<DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<DeviceCard>
    with SingleTickerProviderStateMixin {
  double _scale = 1.0;

  IconData get _platformIcon {
    switch (widget.platform) {
      case 'android':
        return Icons.phone_android;
      case 'windows':
        return Icons.laptop_windows;
      case 'ios':
        return Icons.phone_iphone;
      case 'macos':
        return Icons.laptop_mac;
      default:
        return Icons.devices;
    }
  }

  String get _platformLabel {
    switch (widget.platform) {
      case 'android':
        return 'Android';
      case 'windows':
        return 'Windows';
      case 'ios':
        return 'iOS';
      case 'macos':
        return 'macOS';
      default:
        return 'Device';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = SpDropThemeProvider.of(context);

    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.97),
      onTapUp: (_) => setState(() => _scale = 1.0),
      onTapCancel: () => setState(() => _scale = 1.0),
      child: Opacity(
        opacity: widget.isOffline ? 0.6 : 1.0,
        child: AnimatedScale(
          scale: _scale,
          duration: const Duration(milliseconds: 100),
          child: GlassCard(
            isActive: widget.isConnected,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        if (widget.isOffline)
                          theme.textTertiary.withValues(alpha: 0.1)
                        else if (widget.isConnected)
                          theme.success.withValues(alpha: 0.2)
                        else
                          theme.primary.withValues(alpha: 0.2),
                        Colors.transparent,
                      ],
                    ),
                    boxShadow: widget.isConnected
                        ? [
                            BoxShadow(
                              color: theme.success.withValues(alpha: 0.2),
                              blurRadius: 12,
                              spreadRadius: -2,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    _platformIcon,
                    color: widget.isOffline 
                        ? theme.textTertiary.withValues(alpha: 0.3)
                        : (widget.isConnected ? theme.success : theme.primary),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.name,
                              style: TextStyle(
                                color: widget.isOffline ? theme.textTertiary.withValues(alpha: 0.5) : theme.textPrimary.withValues(alpha: 0.95),
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (widget.isTrusted) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.success
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.verified_user,
                                    size: 10,
                                    color: theme.success
                                        .withValues(alpha: 0.9),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                      children: [
                        StatusDot(
                          size: 7,
                          color: widget.isConnected
                              ? theme.success
                              : theme.textTertiary.withValues(alpha: 0.5),
                          pulse: widget.isConnected,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.isConnected
                              ? 'Connected'
                              : _platformLabel,
                          style: TextStyle(
                            color: widget.isConnected
                                ? theme.success.withValues(alpha: 0.8)
                                : theme.textSecondary.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              if (widget.isOffline)
                Text(
                  'Not reachable',
                  style: TextStyle(color: theme.textTertiary.withValues(alpha: 0.5), fontSize: 11),
                )
              else if (widget.isConnected) ...[
                _ActionButton(
                  icon: Icons.send_rounded,
                  color: theme.primary,
                  onTap: widget.onSend,
                  tooltip: 'Send',
                ),
                const SizedBox(width: 6),
                _ActionButton(
                  icon: Icons.link_off,
                  color: theme.error,
                  onTap: widget.onDisconnect,
                  tooltip: 'Disconnect',
                ),
              ] else ...[
                _ActionButton(
                  icon: Icons.link,
                  color: theme.success,
                  onTap: widget.onConnect,
                  tooltip: 'Connect',
                ),
                const SizedBox(width: 6),
                _ActionButton(
                  icon: Icons.send_rounded,
                  color: theme.primary,
                  onTap: widget.onSend,
                  tooltip: 'Send',
                ),
                if (!widget.isTrusted) ...[
                  const SizedBox(width: 6),
                  _ActionButton(
                    icon: Icons.handshake_outlined,
                    color: theme.warning,
                    onTap: widget.onPair,
                    tooltip: 'Pair',
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final String tooltip;

  const _ActionButton({
    required this.icon,
    required this.color,
    this.onTap,
    required this.tooltip,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.85),
      onTapUp: (_) {
        setState(() => _scale = 1.0);
        widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _scale = 1.0),
      child: Tooltip(
        message: widget.tooltip,
        child: AnimatedScale(
          scale: _scale,
          duration: const Duration(milliseconds: 80),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(alpha: 0.15),
            ),
            child: Icon(
              widget.icon,
              color: widget.color,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }
}
