import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme/theme_service.dart';

/// Glassmorphic container with backdrop blur, customizable gradient opacity, border glow, and hover states.
class GlassCard extends StatefulWidget {
  final Widget child;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final double borderRadius;
  final double? blurAmount;
  final Color? borderColor;
  final VoidCallback? onTap;
  final bool isActive;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 20,
    this.blurAmount,
    this.borderColor,
    this.onTap,
    this.isActive = false,
  });

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = _getThemeData(context);

    final effectiveBorderColor = widget.borderColor ??
        (widget.isActive
            ? theme.glassBorderColor.withValues(alpha: 0.6)
            : theme.textPrimary.withValues(alpha: 0.08));

    final blur = widget.blurAmount ?? theme.glassBlur;

    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          margin: widget.margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(
              color: _isHovered
                  ? effectiveBorderColor.withValues(alpha: 0.3)
                  : effectiveBorderColor,
              width: widget.isActive ? 1.5 : 1,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.textPrimary.withValues(
                    alpha: widget.isActive
                        ? theme.glassOpacity * 2
                        : (_isHovered ? theme.glassOpacity * 1.5 : theme.glassOpacity)),
                theme.textPrimary.withValues(
                    alpha: widget.isActive
                        ? theme.glassOpacity
                        : (_isHovered ? theme.glassOpacity * 0.8 : theme.glassOpacity * 0.33)),
              ],
            ),
            boxShadow: widget.isActive
                ? [
                    BoxShadow(
                      color: theme.glassGlow.withValues(alpha: 0.15),
                      blurRadius: 20,
                      spreadRadius: -5,
                    ),
                  ]
                : (_isHovered
                    ? [
                        BoxShadow(
                          color: theme.glassGlow.withValues(alpha: 0.08),
                          blurRadius: 12,
                          spreadRadius: -3,
                        ),
                      ]
                    : null),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: Padding(
                padding: widget.padding ?? const EdgeInsets.all(16),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }

  AppThemeData _getThemeData(BuildContext context) {
    try {
      final inherited = context.dependOnInheritedWidgetOfExactType<SpDropThemeProvider>();
      if (inherited != null) return inherited.themeData;
    } catch (_) {}
    return appThemes[AppTheme.midnightGlass]!;
  }
}

/// InheritedWidget providing theme tokens across the widget hierarchy.
class SpDropThemeProvider extends InheritedWidget {
  final AppThemeData themeData;

  const SpDropThemeProvider({
    super.key,
    required this.themeData,
    required super.child,
  });

  static AppThemeData of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<SpDropThemeProvider>();
    return provider?.themeData ?? appThemes[AppTheme.midnightGlass]!;
  }

  @override
  bool updateShouldNotify(SpDropThemeProvider oldWidget) {
    return themeData != oldWidget.themeData;
  }
}

/// Interactive glass card action tile with icon, title label, and micro-press animation.
class GlassActionCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color? iconColor;
  final VoidCallback? onTap;
  final bool isActive;

  const GlassActionCard({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.iconColor,
    this.onTap,
    this.isActive = false,
  });

  @override
  State<GlassActionCard> createState() => _GlassActionCardState();
}

class _GlassActionCardState extends State<GlassActionCard>
    with SingleTickerProviderStateMixin {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    final theme = SpDropThemeProvider.of(context);
    final color = widget.iconColor ?? theme.primary;

    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.95),
      onTapUp: (_) {
        setState(() => _scale = 1.0);
        widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _scale = 1.0),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 100),
        child: GlassCard(
          isActive: widget.isActive,
          borderColor: widget.isActive ? color.withValues(alpha: 0.5) : null,
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      color.withValues(alpha: 0.2),
                      color.withValues(alpha: 0.05),
                    ],
                  ),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                widget.label,
                style: TextStyle(
                  color: theme.textPrimary.withValues(alpha: 0.9),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (widget.subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  widget.subtitle!,
                  style: TextStyle(
                    color: theme.textTertiary,
                    fontSize: 10,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData get icon => widget.icon;
}
