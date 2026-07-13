import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class PremiumBackground extends StatelessWidget {
  const PremiumBackground({
    super.key,
    required this.child,
    this.showPattern = true,
  });

  final Widget child;
  final bool showPattern;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const ColoredBox(color: AppColors.cream),
        if (showPattern)
          Positioned.fill(
            child: CustomPaint(painter: _MajlisPatternPainter()),
          ),
        child,
      ],
    );
  }
}

class _MajlisPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = AppColors.gold.withValues(alpha: .14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;

    for (var i = 0; i < 6; i++) {
      final path = Path();
      final y = 38.0 + i * 9;
      path.moveTo(-20, y);
      path.cubicTo(
        size.width * .22,
        y - 38,
        size.width * .53,
        y + 36,
        size.width + 24,
        y - 10,
      );
      canvas.drawPath(path, linePaint);
    }

    final softPaint = Paint()
      ..color = AppColors.green900.withValues(alpha: .035)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(size.width + 30, size.height * .28),
      110,
      softPaint,
    );
    canvas.drawCircle(Offset(-30, size.height * .82), 130, softPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
