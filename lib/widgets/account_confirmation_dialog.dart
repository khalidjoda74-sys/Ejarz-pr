import 'package:flutter/material.dart';

import '../core/theme.dart';

Future<bool> showAccountConfirmation(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required IconData icon,
  String cancelLabel = 'إلغاء',
  String? confirmationWord,
  bool destructive = false,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (_) => AccountConfirmationDialog(
          title: title,
          message: message,
          confirmLabel: confirmLabel,
          cancelLabel: cancelLabel,
          icon: icon,
          confirmationWord: confirmationWord,
          destructive: destructive,
        ),
      ) ??
      false;
}

class AccountConfirmationDialog extends StatefulWidget {
  final String title, message, confirmLabel, cancelLabel;
  final IconData icon;
  final String? confirmationWord;
  final bool destructive;

  const AccountConfirmationDialog(
      {super.key,
      required this.title,
      required this.message,
      required this.confirmLabel,
      required this.icon,
      this.cancelLabel = 'إلغاء',
      this.confirmationWord,
      this.destructive = false});

  @override
  State<AccountConfirmationDialog> createState() =>
      _AccountConfirmationDialogState();
}

class _AccountConfirmationDialogState extends State<AccountConfirmationDialog> {
  String _confirmation = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = widget.destructive
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    final iconColor = widget.destructive && theme.brightness == Brightness.dark
        ? const Color(0xFFFFB4AB)
        : accent;
    final canConfirm = widget.confirmationWord == null ||
        _confirmation.trim() == widget.confirmationWord;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      backgroundColor: context.ejarzTheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: BorderSide(color: context.ejarzTheme.border)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 390),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                  child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                          color: iconColor.withValues(alpha: .10),
                          shape: BoxShape.circle),
                      child: Icon(widget.icon, size: 31, color: iconColor))),
              const SizedBox(height: 18),
              Text(widget.title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall),
              const SizedBox(height: 9),
              Text(widget.message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: context.ejarzTheme.muted, height: 1.6)),
              if (widget.confirmationWord != null) ...[
                const SizedBox(height: 20),
                Text('للتأكيد اكتب كلمة: ${widget.confirmationWord}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                TextField(
                  textAlign: TextAlign.center,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                      hintText: widget.confirmationWord,
                      labelText: 'كلمة التأكيد',
                      floatingLabelBehavior: FloatingLabelBehavior.always),
                  onChanged: (value) => setState(() => _confirmation = value),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: widget.destructive ? accent : null,
                      foregroundColor:
                          widget.destructive ? theme.colorScheme.onError : null,
                      minimumSize: const Size.fromHeight(48),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12)),
                  onPressed:
                      canConfirm ? () => Navigator.of(context).pop(true) : null,
                  child:
                      Text(widget.confirmLabel, textAlign: TextAlign.center)),
              const SizedBox(height: 9),
              OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.primary,
                      side: BorderSide(
                          color: theme.colorScheme.primary, width: 1.2),
                      minimumSize: const Size.fromHeight(48),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12)),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(widget.cancelLabel, textAlign: TextAlign.center)),
            ],
          ),
        ),
      ),
    );
  }
}
