import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../core/app_colors.dart';

/// Custom loading spinner — dual arc + soft pulse, khớp theme cyberpunk.
class PremiumLoading extends StatefulWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const PremiumLoading({
    super.key,
    this.size = 24,
    this.color,
    this.strokeWidth = 2.5,
  });

  @override
  State<PremiumLoading> createState() => _PremiumLoadingState();
}

class _PremiumLoadingState extends State<PremiumLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AppColors.primary;
    final size = widget.size;

    return SizedBox(
      width: size.w,
      height: size.w,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _PremiumSpinnerPainter(
              progress: _controller.value,
              color: color,
              strokeWidth: widget.strokeWidth,
            ),
          );
        },
      ),
    );
  }
}

class _PremiumSpinnerPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;

  _PremiumSpinnerPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Track mờ
    final track = Paint()
      ..color = color.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    // Arc chính xoay
    final sweep = 0.65 + 0.25 * math.sin(progress * math.pi * 2);
    final start = progress * math.pi * 2;
    final arc = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: [
          color.withOpacity(0.15),
          color,
          color.withOpacity(0.9),
        ],
        stops: const [0.0, 0.55, 1.0],
        transform: GradientRotation(start),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start, math.pi * 2 * sweep, false, arc);

    // Chấm highlight ở đầu arc
    final tipAngle = start + math.pi * 2 * sweep;
    final tip = Offset(
      center.dx + radius * math.cos(tipAngle),
      center.dy + radius * math.sin(tipAngle),
    );
    final glow = Paint()..color = color.withOpacity(0.9);
    canvas.drawCircle(tip, strokeWidth * 0.55, glow);
  }

  @override
  bool shouldRepaint(covariant _PremiumSpinnerPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
