import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class CollapsibleFilterHandle extends StatefulWidget {
  final bool collapsed;
  final VoidCallback onTap;

  const CollapsibleFilterHandle({
    super.key,
    required this.collapsed,
    required this.onTap,
  });

  @override
  State<CollapsibleFilterHandle> createState() =>
      _CollapsibleFilterHandleState();
}

class _CollapsibleFilterHandleState extends State<CollapsibleFilterHandle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999.r),
        onTap: widget.onTap,
        child: Ink(
          width: 72.w,
          height: 28.h,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1E3A8A), Color(0xFF0F172A)],
            ),
            borderRadius: BorderRadius.circular(999.r),
            border: Border.all(color: const Color(0x33FFFFFF)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999.r),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      final slide = (_controller.value * 120.w) - 60.w;
                      return Transform.translate(
                        offset: Offset(slide, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: 22.w,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [
                                  Colors.transparent,
                                  Color(0x22FFFFFF),
                                  Color(0x55FFFFFF),
                                  Color(0x22FFFFFF),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                AnimatedRotation(
                  turns: widget.collapsed ? 0.5 : 0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOutCubic,
                  child: Icon(
                    Icons.keyboard_arrow_up_rounded,
                    color: Colors.white,
                    size: 20.sp,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
