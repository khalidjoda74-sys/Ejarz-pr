import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/receipt_document.dart';
import '../core/receipt_share.dart';

class ReceiptActionsDialog extends StatefulWidget {
  final Uint8List bytes;
  final String fileName;
  final ReceiptShare share;
  final bool Function() isCurrentAccount;
  const ReceiptActionsDialog(
      {super.key,
      required this.bytes,
      required this.fileName,
      required this.share,
      required this.isCurrentAccount});

  @override
  State<ReceiptActionsDialog> createState() => _ReceiptActionsDialogState();
}

class _ReceiptActionsDialogState extends State<ReceiptActionsDialog> {
  bool busy = false;
  String? error;

  Future<void> run(bool sharing, BuildContext buttonContext) async {
    if (busy) return;
    if (!widget.isCurrentAccount()) {
      Navigator.pop(context);
      return;
    }
    final box = buttonContext.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (sharing) {
        await widget.share.share(origin);
      } else {
        await downloadReceiptPdf(widget.bytes, widget.fileName,
            isCurrentAccount: widget.isCurrentAccount);
        if (mounted) Navigator.pop(context);
      }
    } catch (_) {
      if (mounted && widget.isCurrentAccount()) {
        setState(() => error = sharing
            ? 'تعذرت مشاركة الملف. يمكنك المحاولة مرة أخرى أو تحميله.'
            : 'تعذر تحميل الملف. حاول مرة أخرى.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final supported = widget.share.supported;
    final buttonShape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    return PopScope(
      canPop: !busy,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.picture_as_pdf_rounded,
                    size: 26, color: colors.primary),
              ),
              const SizedBox(height: 12),
              Text('ملف PDF جاهز',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('اختر تحميل المستند أو مشاركته',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: colors.onSurfaceVariant, fontSize: 13)),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: colors.onSurface.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: colors.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Text(widget.fileName,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12, color: colors.onSurfaceVariant)),
              ),
              const SizedBox(height: 16),
              Builder(
                  builder: (buttonContext) => SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 48),
                              shape: buttonShape,
                              textStyle: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                          icon: const Icon(Icons.share_outlined, size: 21),
                          label: const Text('مشاركة'),
                          onPressed: !busy && supported
                              ? () => run(true, buttonContext)
                              : null,
                        ),
                      )),
              const SizedBox(height: 10),
              Builder(
                  builder: (buttonContext) => SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 48),
                              shape: buttonShape,
                              side: BorderSide(
                                  color:
                                      colors.primary.withValues(alpha: 0.35)),
                              textStyle: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                          icon: const Icon(Icons.download_outlined, size: 22),
                          label: const Text('تحميل'),
                          onPressed:
                              !busy ? () => run(false, buttonContext) : null,
                        ),
                      )),
              if (!supported) ...[
                const SizedBox(height: 14),
                Text(
                    'مشاركة الملفات غير مدعومة على هذا الجهاز أو المتصفح. يمكنك تحميل الملف.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12, color: colors.onSurfaceVariant)),
              ],
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator(minHeight: 3),
                ),
              if (error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: colors.errorContainer,
                      borderRadius: BorderRadius.circular(12)),
                  child: Text(error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12, color: colors.onErrorContainer)),
                ),
              ],
              const SizedBox(height: 10),
              Center(
                  child: TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                style: TextButton.styleFrom(
                    minimumSize: const Size(100, 44),
                    foregroundColor: colors.onSurfaceVariant),
                child: const Text('إغلاق'),
              )),
            ]),
          ),
        ),
      ),
    );
  }
}
