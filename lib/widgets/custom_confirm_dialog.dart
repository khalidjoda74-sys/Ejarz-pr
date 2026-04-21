import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CustomConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final String? cancelLabel;
  final bool showCancel;
  final Color? confirmColor;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;

  const CustomConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel = 'تأكيد',
    this.cancelLabel,
    this.showCancel = true,
    this.confirmColor,
    this.onConfirm,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 8,
      backgroundColor: Colors.white,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // الشريط العلوي (العنوان) - خلفية ملونة فاتحة وجميلة
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                color: confirmColor?.withOpacity(0.1) ?? const Color(0xFFF1F5F9),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                border: Border(
                  bottom: BorderSide(
                    color: confirmColor?.withOpacity(0.2) ?? const Color(0xFFE2E8F0),
                    width: 1,
                  ),
                ),
              ),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  color: confirmColor ?? const Color(0xFF1E293B),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            
            // محتوى الرسالة - خلفية بيضاء نقية
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  color: const Color(0xFF475569),
                  fontSize: 16,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            
            // الأزرار - عمودية كما طلب المستخدم (تراجع تحت زر التأكيد بنفس الحجم)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // زر التأكيد (الغاء السند مثلاً)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: onConfirm ?? () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: confirmColor ?? const Color(0xFFDC2626), // أحمر هادئ افتراضي
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        confirmLabel,
                        style: GoogleFonts.cairo(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),

                  if (showCancel) ...[
                    const SizedBox(height: 12),

                  // زر التراجع (دائماً موجود تحت زر التأكيد بنفس الحجم)
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: onCancel ?? () => Navigator.pop(context, false),
                      style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFFF1F5F9), // لون خلفية مختلف (رمادي فاتح)
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                      ),
                      child: Text(
                        cancelLabel ?? 'تراجع',
                        style: GoogleFonts.cairo(
                          color: const Color(0xFF475569),
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<bool> show({
    required BuildContext context,
    required String title,
    required String message,
    String confirmLabel = 'تأكيد',
    String? cancelLabel,
    bool showCancel = true,
    Color? confirmColor,
    bool canPop = true,
    bool forceBlockedDialog = false,
  }) async {
    final effectiveShowCancel = forceBlockedDialog ? false : showCancel;
    final effectiveCanPop = forceBlockedDialog ? false : canPop;
    final effectiveConfirmLabel =
        forceBlockedDialog && confirmLabel == 'تأكيد'
            ? 'إغلاق التطبيق'
            : confirmLabel;

    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: PopScope(
          canPop: effectiveCanPop,
          child: CustomConfirmDialog(
            title: title,
            message: message,
            confirmLabel: effectiveConfirmLabel,
            cancelLabel: cancelLabel,
            showCancel: effectiveShowCancel,
            confirmColor: confirmColor,
          ),
        ),
      ),
    ) ?? false;
  }
}
