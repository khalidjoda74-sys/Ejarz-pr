import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ai_chat_screen.dart';
import 'ai_chat_service.dart';

class AiChatFloatingIcon extends StatefulWidget {
  final bool isOfficeMode;
  final double size;

  const AiChatFloatingIcon({
    super.key,
    this.isOfficeMode = false,
    this.size = 56,
  });

  @override
  State<AiChatFloatingIcon> createState() => _AiChatFloatingIconState();
}

class _AiChatFloatingIconState extends State<AiChatFloatingIcon>
    with TickerProviderStateMixin {
  late final AnimationController _floatController;
  late final AnimationController _pulseController;
  late final AnimationController _ringController;
  late final AnimationController _orbitController;
  late final AnimationController _tapController;

  late final Animation<double> _floatAnim;
  late final Animation<double> _pulseAnim;
  late final Animation<double> _tapAnim;

  @override
  void initState() {
    super.initState();

    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2300),
    )..repeat(reverse: true);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();

    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5000),
    )..repeat();

    _tapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.0,
      upperBound: 1.0,
    );

    _floatAnim = Tween<double>(begin: 0, end: -8).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );

    _pulseAnim = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _tapAnim = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _tapController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _floatController.dispose();
    _pulseController.dispose();
    _ringController.dispose();
    _orbitController.dispose();
    _tapController.dispose();
    super.dispose();
  }

  String _statusMessage(AiChatApiKeyStatus status) {
    switch (status) {
      case AiChatApiKeyStatus.loading:
      case AiChatApiKeyStatus.unknown:
        return 'جاري تهيئة الشات الآن.';
      case AiChatApiKeyStatus.missing:
        return 'اتصال الشات غير مضبوط حاليًا.';
      case AiChatApiKeyStatus.error:
        return 'تعذر تهيئة اتصال الشات حاليًا.';
      case AiChatApiKeyStatus.ready:
        return 'المساعد الذكي جاهز.';
    }
  }

  Color _statusColor(AiChatApiKeyStatus status) {
    switch (status) {
      case AiChatApiKeyStatus.loading:
      case AiChatApiKeyStatus.unknown:
        return const Color(0xFFF59E0B);
      case AiChatApiKeyStatus.missing:
      case AiChatApiKeyStatus.error:
        return const Color(0xFFEF4444);
      case AiChatApiKeyStatus.ready:
        return const Color(0xFF10B981);
    }
  }

  Future<void> _handleTap(AiChatApiKeyStatus status) async {
    await _tapController.forward();
    await _tapController.reverse();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    var effectiveStatus = status;
    if (effectiveStatus != AiChatApiKeyStatus.ready) {
      effectiveStatus = await AiChatService.refreshApiKeyFromRemote();
    }
    if (!mounted) return;
    if (effectiveStatus != AiChatApiKeyStatus.ready) {
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(_statusMessage(effectiveStatus)),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }
    _openChat(context);
  }

  @override
  Widget build(BuildContext context) {
    final double size = widget.size;
    final double auraSize = size + 10;
    final double hitAreaSize = size + 42;
    final double orbitSize = size + 6;
    final double iconPadding = size * 0.08;

    return Positioned(
      left: 10,
      bottom: 80,
      child: ValueListenableBuilder<AiChatApiKeyStatus>(
        valueListenable: AiChatService.apiKeyStatusListenable,
        builder: (context, status, _) {
          final statusColor = _statusColor(status);
          final isReady = status == AiChatApiKeyStatus.ready;
          return Tooltip(
            message: _statusMessage(status),
            child: AnimatedBuilder(
              animation: Listenable.merge([
                _floatController,
                _pulseController,
                _ringController,
                _orbitController,
                _tapController,
              ]),
              builder: (context, child) {
                final double scale = _pulseAnim.value * _tapAnim.value;
                final double ringValue = _ringController.value;
                final double delayedRing = (ringValue + 0.5) % 1.0;
                final double orbitAngle = _orbitController.value * 2 * math.pi;

                return Transform.translate(
                  offset: Offset(0, _floatAnim.value),
                  child: Transform.scale(
                    scale: scale,
                    child: Opacity(
                      opacity: isReady ? 1.0 : 0.9,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () => _handleTap(status),
                        child: SizedBox(
                          width: hitAreaSize,
                          height: hitAreaSize,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: auraSize + 4,
                                height: auraSize + 4,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      const Color(0xFF5BC0FF)
                                          .withValues(alpha: 0.22),
                                      const Color(0xFF2E67FF)
                                          .withValues(alpha: 0.08),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                              Opacity(
                                opacity: (1 - ringValue) * 0.35,
                                child: Container(
                                  width: size + (ringValue * 10),
                                  height: size + (ringValue * 10),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFF7DD3FF),
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                              Opacity(
                                opacity: (1 - delayedRing) * 0.22,
                                child: Container(
                                  width: size + (delayedRing * 7),
                                  height: size + (delayedRing * 7),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFFA9E7FF),
                                      width: 1.8,
                                    ),
                                  ),
                                ),
                              ),
                              Transform.rotate(
                                angle: orbitAngle,
                                child: SizedBox(
                                  width: orbitSize,
                                  height: orbitSize,
                                  child: Align(
                                    alignment: Alignment.topCenter,
                                    child: Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Color(0xFFB9F3FF),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Color(0xFF9FE8FF),
                                            blurRadius: 10,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Container(
                                width: size,
                                height: size,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF54B8FF),
                                      Color(0xFF347DFF),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF3F91FF)
                                          .withValues(alpha: 0.45),
                                      blurRadius: 24,
                                      spreadRadius: 4,
                                    ),
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.18),
                                      blurRadius: 14,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Align(
                                      alignment: Alignment.topCenter,
                                      child: Container(
                                        width: size * 0.68,
                                        height: size * 0.26,
                                        margin: EdgeInsets.only(top: size * 0.12),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(100),
                                          gradient: LinearGradient(
                                            colors: [
                                              Colors.white.withValues(alpha: 0.26),
                                              Colors.white.withValues(alpha: 0.02),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: EdgeInsets.all(iconPadding),
                                      child: Image.asset(
                                        'assets/images/darfo_ai_bot_icon.png',
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                    Positioned(
                                      right: 4,
                                      bottom: 4,
                                      child: Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: statusColor,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 1.6,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _openChat(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) =>
            AiChatScreen(isOfficeMode: widget.isOfficeMode),
        transitionsBuilder: (_, anim, __, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }
}
