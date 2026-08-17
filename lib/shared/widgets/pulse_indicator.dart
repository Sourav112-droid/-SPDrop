import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

/// Concentric expanding pulse wave animation indicating active device discovery.
class PulseIndicator extends StatefulWidget {
  final double size;
  final Color color;
  final bool isActive;
  final Widget? child;
  final int pulseCount;

  const PulseIndicator({
    super.key,
    this.size = 120,
    this.color = const Color(0xFF4F8EF7),
    this.isActive = true,
    this.child,
    this.pulseCount = 3,
  });

  @override
  State<PulseIndicator> createState() => _PulseIndicatorState();
}

class _PulseIndicatorState extends State<PulseIndicator>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _initAnimations();
  }

  void _initAnimations() {
    _controllers = List.generate(widget.pulseCount, (index) {
      return AnimationController(
        duration: const Duration(milliseconds: 2000),
        vsync: this,
      );
    });

    _animations = _controllers.map((controller) {
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeOut),
      );
    }).toList();

    if (widget.isActive) {
      _startAnimations();
    }
  }

  final List<Timer> _timers = [];

  void _startAnimations() {
    for (var t in _timers) {
      t.cancel();
    }
    _timers.clear();
    for (int i = 0; i < _controllers.length; i++) {
      _timers.add(Timer(Duration(milliseconds: i * 600), () {
        if (mounted && widget.isActive) {
          _controllers[i].repeat();
        }
      }));
    }
  }

  @override
  void didUpdateWidget(PulseIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _startAnimations();
      } else {
        for (var t in _timers) {
          t.cancel();
        }
        _timers.clear();
        for (var c in _controllers) {
          c.stop();
          c.reset();
        }
      }
    }
  }

  @override
  void dispose() {
    for (var t in _timers) {
      t.cancel();
    }
    for (var c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ...List.generate(widget.pulseCount, (index) {
            return AnimatedBuilder(
              animation: _animations[index],
              builder: (context, child) {
                final value = _animations[index].value;
                final scale = 1.0 + (value * 0.6);
                final opacity = (1.0 - value).clamp(0.0, 0.4);
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: widget.size * 0.6,
                    height: widget.size * 0.6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.color.withValues(alpha: opacity),
                        width: 2,
                      ),
                    ),
                  ),
                );
              },
            );
          }),
          Container(
            width: widget.size * 0.45,
            height: widget.size * 0.45,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  widget.color.withValues(alpha: 0.3),
                  widget.color.withValues(alpha: 0.05),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.2),
                  blurRadius: 30,
                  spreadRadius: -5,
                ),
              ],
            ),
            child: widget.child ??
                Icon(
                  Icons.wifi_tethering,
                  color: widget.color,
                  size: widget.size * 0.2,
                ),
          ),
        ],
      ),
    );
  }
}

/// Glowing status dot with optional pulsing animation.
class StatusDot extends StatefulWidget {
  final Color color;
  final double size;
  final bool pulse;

  const StatusDot({
    super.key,
    this.color = const Color(0xFF3DD68C),
    this.size = 10,
    this.pulse = false,
  });

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.pulse) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.pulse) {
      _controller.stop();
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: _animation.value * 0.5),
                blurRadius: widget.size * 2,
                spreadRadius: widget.size * 0.2,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Rotating radar sweep animation representing background discovery scanning.
class RadarScan extends StatefulWidget {
  final double size;
  final Color color;
  final bool isScanning;

  const RadarScan({
    super.key,
    this.size = 200,
    this.color = const Color(0xFF4F8EF7),
    this.isScanning = true,
  });

  @override
  State<RadarScan> createState() => _RadarScanState();
}

class _RadarScanState extends State<RadarScan>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );
    if (widget.isScanning) _controller.repeat();
  }

  @override
  void didUpdateWidget(RadarScan oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isScanning && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isScanning) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _RadarPainter(
              progress: _controller.value,
              color: widget.color,
            ),
            child: child,
          );
        },
        child: Center(
          child: Icon(
            Icons.wifi_tethering,
            color: widget.color,
            size: widget.size * 0.15,
          ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double progress;
  final Color color;

  _RadarPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    for (int i = 1; i <= 3; i++) {
      final radius = maxRadius * (i / 3);
      final paint = Paint()
        ..color = color.withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawCircle(center, radius, paint);
    }

    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: progress * 2 * pi,
        endAngle: progress * 2 * pi + pi / 2,
        colors: [
          Colors.transparent,
          color.withValues(alpha: 0.15),
          color.withValues(alpha: 0.05),
          Colors.transparent,
        ],
        stops: const [0.0, 0.3, 0.7, 1.0],
        transform: GradientRotation(progress * 2 * pi),
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius));

    canvas.drawCircle(center, maxRadius, sweepPaint);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      progress != oldDelegate.progress;
}
