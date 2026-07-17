import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

class BrandMark extends StatelessWidget {
  final double size;

  const BrandMark({super.key, this.size = 38});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _BrandMarkPainter(),
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final green = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.12
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final gold = Paint()
      ..color = AppColors.secondary
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.11
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final roof = Path()
      ..moveTo(size.width * 0.12, size.height * 0.42)
      ..lineTo(size.width * 0.50, size.height * 0.14)
      ..lineTo(size.width * 0.88, size.height * 0.42)
      ..lineTo(size.width * 0.88, size.height * 0.72)
      ..lineTo(size.width * 0.50, size.height * 0.58)
      ..lineTo(size.width * 0.12, size.height * 0.72)
      ..close();
    canvas.drawPath(roof, green);

    final lower = Path()
      ..moveTo(size.width * 0.18, size.height * 0.82)
      ..lineTo(size.width * 0.50, size.height * 0.68)
      ..lineTo(size.width * 0.82, size.height * 0.82);
    canvas.drawPath(lower, gold);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class HeroContractIllustration extends StatelessWidget {
  final double width;
  final double height;

  const HeroContractIllustration({
    super.key,
    this.width = 170,
    this.height = 150,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _HeroContractPainter(),
    );
  }
}

class _HeroContractPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final city = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final cityFill = Paint()
      ..color = Colors.white.withValues(alpha: 0.055)
      ..style = PaintingStyle.fill;

    final skylineBase = size.height * 0.84;
    final buildings = <Rect>[
      Rect.fromLTWH(size.width * 0.05, size.height * 0.45, size.width * 0.10,
          skylineBase - size.height * 0.45),
      Rect.fromLTWH(size.width * 0.17, size.height * 0.30, size.width * 0.12,
          skylineBase - size.height * 0.30),
      Rect.fromLTWH(size.width * 0.31, size.height * 0.54, size.width * 0.08,
          skylineBase - size.height * 0.54),
      Rect.fromLTWH(size.width * 0.66, size.height * 0.35, size.width * 0.10,
          skylineBase - size.height * 0.35),
      Rect.fromLTWH(size.width * 0.78, size.height * 0.48, size.width * 0.12,
          skylineBase - size.height * 0.48),
    ];
    for (final rect in buildings) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)), cityFill);
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)), city);
    }

    final pedestal = Paint()
      ..color = Colors.black.withValues(alpha: 0.13)
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.49, size.height * 0.83),
        width: size.width * 0.66,
        height: size.height * 0.18,
      ),
      pedestal,
    );

    final paperShadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.16)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    final paperRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.28, size.height * 0.13, size.width * 0.44,
          size.height * 0.62),
      const Radius.circular(14),
    );
    canvas.drawRRect(paperRect.shift(const Offset(4, 7)), paperShadow);

    final paper = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[Color(0xFFFFFFFF), Color(0xFFE9F2EE)],
      ).createShader(paperRect.outerRect);
    canvas.drawRRect(paperRect, paper);

    final linePaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.80)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final shortLinePaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.38)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final y = size.height * (0.27 + i * 0.105);
      canvas.drawLine(
        Offset(size.width * 0.38, y),
        Offset(size.width * (i == 2 ? 0.58 : 0.64), y),
        i == 2 ? shortLinePaint : linePaint,
      );
    }

    final signature = Path()
      ..moveTo(size.width * 0.39, size.height * 0.61)
      ..cubicTo(
        size.width * 0.44,
        size.height * 0.53,
        size.width * 0.44,
        size.height * 0.69,
        size.width * 0.50,
        size.height * 0.60,
      )
      ..cubicTo(
        size.width * 0.54,
        size.height * 0.54,
        size.width * 0.57,
        size.height * 0.68,
        size.width * 0.63,
        size.height * 0.60,
      );
    canvas.drawPath(
      signature,
      Paint()
        ..color = AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );

    final sealCenter = Offset(size.width * 0.73, size.height * 0.66);
    final sealRadius = size.width * 0.105;
    canvas.drawCircle(
      sealCenter,
      sealRadius,
      Paint()
        ..shader = const RadialGradient(
          colors: <Color>[Color(0xFFF5D481), Color(0xFFC6952E)],
        ).createShader(Rect.fromCircle(center: sealCenter, radius: sealRadius)),
    );
    canvas.drawCircle(
      sealCenter,
      sealRadius * 0.74,
      Paint()
        ..color = const Color(0xFFFFE7A6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final check = Path()
      ..moveTo(sealCenter.dx - sealRadius * 0.38, sealCenter.dy)
      ..lineTo(
          sealCenter.dx - sealRadius * 0.08, sealCenter.dy + sealRadius * 0.28)
      ..lineTo(
          sealCenter.dx + sealRadius * 0.42, sealCenter.dy - sealRadius * 0.32);
    canvas.drawPath(
      check,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class PropertyIllustration extends StatelessWidget {
  final bool commercial;
  final double size;

  const PropertyIllustration({
    super.key,
    this.commercial = false,
    this.size = 130,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size * 0.76),
      painter: _PropertyPainter(commercial: commercial),
    );
  }
}

class _PropertyPainter extends CustomPainter {
  final bool commercial;

  _PropertyPainter({required this.commercial});

  @override
  void paint(Canvas canvas, Size size) {
    final soft = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.055)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(size.width * 0.50, size.height * 0.47),
      size.width * 0.38,
      soft,
    );

    final body = Paint()
      ..color = const Color(0xFFF1EFE7)
      ..style = PaintingStyle.fill;
    final edge = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final green = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.fill;
    final dark = Paint()
      ..color = AppColors.primaryDark
      ..style = PaintingStyle.fill;

    if (commercial) {
      final building = RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.18, size.height * 0.20, size.width * 0.64,
            size.height * 0.58),
        const Radius.circular(5),
      );
      canvas.drawRRect(building, body);
      canvas.drawRRect(building, edge);
      canvas.drawRect(
        Rect.fromLTWH(size.width * 0.20, size.height * 0.39, size.width * 0.60,
            size.height * 0.10),
        green,
      );
      for (var i = 0; i < 3; i++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              size.width * (0.27 + i * 0.18),
              size.height * 0.25,
              size.width * 0.11,
              size.height * 0.09,
            ),
            const Radius.circular(2),
          ),
          Paint()..color = AppColors.primary.withValues(alpha: 0.55),
        );
      }
      canvas.drawRect(
        Rect.fromLTWH(size.width * 0.40, size.height * 0.53, size.width * 0.20,
            size.height * 0.25),
        dark,
      );
      for (var i = 0; i < 5; i++) {
        final x = size.width * (0.21 + i * 0.12);
        final awning = Path()
          ..moveTo(x, size.height * 0.39)
          ..lineTo(x + size.width * 0.06, size.height * 0.39)
          ..lineTo(x + size.width * 0.05, size.height * 0.47)
          ..lineTo(x + size.width * 0.01, size.height * 0.47)
          ..close();
        canvas.drawPath(awning,
            Paint()..color = i.isEven ? AppColors.primary : Colors.white);
      }
    } else {
      final house = Path()
        ..moveTo(size.width * 0.22, size.height * 0.42)
        ..lineTo(size.width * 0.50, size.height * 0.16)
        ..lineTo(size.width * 0.79, size.height * 0.42)
        ..lineTo(size.width * 0.74, size.height * 0.42)
        ..lineTo(size.width * 0.74, size.height * 0.78)
        ..lineTo(size.width * 0.26, size.height * 0.78)
        ..lineTo(size.width * 0.26, size.height * 0.42)
        ..close();
      canvas.drawPath(house, body);
      canvas.drawPath(house, edge);
      final roof = Path()
        ..moveTo(size.width * 0.18, size.height * 0.43)
        ..lineTo(size.width * 0.50, size.height * 0.12)
        ..lineTo(size.width * 0.84, size.height * 0.43)
        ..lineTo(size.width * 0.77, size.height * 0.46)
        ..lineTo(size.width * 0.50, size.height * 0.22)
        ..lineTo(size.width * 0.24, size.height * 0.46)
        ..close();
      canvas.drawPath(roof, green);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(size.width * 0.43, size.height * 0.52,
              size.width * 0.14, size.height * 0.26),
          const Radius.circular(2),
        ),
        dark,
      );
      for (final x in <double>[0.31, 0.63]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(size.width * x, size.height * 0.46, size.width * 0.11,
                size.height * 0.12),
            const Radius.circular(2),
          ),
          Paint()..color = AppColors.primary.withValues(alpha: 0.48),
        );
      }
    }

    final ground = Paint()
      ..color = Colors.black.withValues(alpha: 0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.50, size.height * 0.82),
        width: size.width * 0.72,
        height: size.height * 0.11,
      ),
      ground,
    );
  }

  @override
  bool shouldRepaint(covariant _PropertyPainter oldDelegate) {
    return oldDelegate.commercial != commercial;
  }
}

class MiniMapPreview extends StatelessWidget {
  final double height;

  const MiniMapPreview({super.key, this.height = 118});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(double.infinity, height),
      painter: _MapPainter(),
    );
  }
}

class _MapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = const Color(0xFFF4F6F5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(15)),
      background,
    );

    final park = Paint()..color = AppColors.primaryLight;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.04, size.height * 0.08, size.width * 0.27,
            size.height * 0.82),
        const Radius.circular(8),
      ),
      park,
    );

    final roads = Paint()
      ..color = Colors.white
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    final thinRoads = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, size.height * 0.58),
        Offset(size.width, size.height * 0.24), roads);
    canvas.drawLine(Offset(size.width * 0.48, 0),
        Offset(size.width * 0.36, size.height), roads);
    for (var i = 0; i < 5; i++) {
      final y = size.height * (0.15 + i * 0.17);
      canvas.drawLine(Offset(size.width * 0.30, y),
          Offset(size.width, y + size.height * 0.04), thinRoads);
    }

    final pinCenter = Offset(size.width * 0.53, size.height * 0.48);
    final pin = Path()
      ..moveTo(pinCenter.dx, pinCenter.dy + 24)
      ..cubicTo(pinCenter.dx - 20, pinCenter.dy + 2, pinCenter.dx - 17,
          pinCenter.dy - 18, pinCenter.dx, pinCenter.dy - 18)
      ..cubicTo(pinCenter.dx + 17, pinCenter.dy - 18, pinCenter.dx + 20,
          pinCenter.dy + 2, pinCenter.dx, pinCenter.dy + 24)
      ..close();
    canvas.drawPath(pin, Paint()..color = AppColors.primary);
    canvas.drawCircle(
        pinCenter.translate(0, -4), 6, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class SuccessBurst extends StatefulWidget {
  final double size;

  const SuccessBurst({super.key, this.size = 120});

  @override
  State<SuccessBurst> createState() => _SuccessBurstState();
}

class _SuccessBurstState extends State<SuccessBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = Curves.elasticOut.transform(_controller.value);
        return Transform.scale(
          scale: value,
          child: CustomPaint(
            size: Size.square(widget.size),
            painter: _SuccessPainter(progress: _controller.value),
          ),
        );
      },
    );
  }
}

class _SuccessPainter extends CustomPainter {
  final double progress;

  _SuccessPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (var i = 0; i < 12; i++) {
      final angle = (math.pi * 2 / 12) * i;
      final start = Offset(
        center.dx + math.cos(angle) * size.width * 0.42,
        center.dy + math.sin(angle) * size.width * 0.42,
      );
      final end = Offset(
        center.dx + math.cos(angle) * size.width * (0.46 + 0.08 * progress),
        center.dy + math.sin(angle) * size.width * (0.46 + 0.08 * progress),
      );
      canvas.drawLine(
        start,
        end,
        Paint()
          ..color = i.isEven ? AppColors.secondary : AppColors.primary
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.drawCircle(
        center, size.width * 0.34, Paint()..color = AppColors.primaryLight);
    canvas.drawCircle(
        center, size.width * 0.27, Paint()..color = AppColors.primary);
    final check = Path()
      ..moveTo(size.width * 0.34, size.height * 0.50)
      ..lineTo(size.width * 0.46, size.height * 0.62)
      ..lineTo(size.width * 0.68, size.height * 0.38);
    canvas.drawPath(
      check,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SuccessPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
