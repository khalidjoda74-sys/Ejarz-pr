import 'package:flutter/material.dart';

import '../core/theme.dart';

Future<bool> showAccountConfirmation(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required IconData icon,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
          backgroundColor: dialogContext.ejarzTheme.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
            side: BorderSide(color: dialogContext.ejarzTheme.border),
          ),
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
                        color: Theme.of(dialogContext)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon,
                          size: 31,
                          color: Theme.of(dialogContext).colorScheme.primary),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(dialogContext).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 9),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style:
                        Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                              color: dialogContext.ejarzTheme.muted,
                              height: 1.6,
                            ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: Text(confirmLabel),
                  ),
                  const SizedBox(height: 9),
                  OutlinedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('إلغاء'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ) ??
      false;
}
