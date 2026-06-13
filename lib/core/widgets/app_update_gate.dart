import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_update_config.dart';
import '../services/app_update_service.dart';

bool _appUpdateHandledThisLaunch = false;

class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({
    super.key,
    required this.child,
    this.service,
  });

  final Widget child;
  final AppUpdateService? service;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate> {
  late final AppUpdateService _service;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? AppUpdateService();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startCheckIfNeeded();
    });
  }

  void _startCheckIfNeeded() {
    if (!mounted || _started || _appUpdateHandledThisLaunch) return;
    _started = true;
    _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    final result = await _service.checkForIosUpdate();
    if (!mounted) return;
    _appUpdateHandledThisLaunch = true;
    if (!result.shouldShow) return;
    await _showUpdateDialog(result);
  }

  Future<void> _showUpdateDialog(AppUpdateCheckResult result) async {
    final locale = Localizations.maybeLocaleOf(context) ?? const Locale('ar');
    final theme = Theme.of(context);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: !result.isForce,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            icon: Icon(
              result.isForce ? Icons.system_update_alt_rounded : Icons.update,
              color: theme.colorScheme.primary,
              size: 34,
            ),
            title: Text(
              result.localizedTitle(locale),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  result.localizedMessage(locale),
                  textAlign: locale.languageCode.toLowerCase() == 'ar'
                      ? TextAlign.right
                      : TextAlign.left,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.7),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.colorScheme.primary.withOpacity(0.18),
                    ),
                  ),
                  child: Text(
                    result.localizedVersionDetails(locale),
                    textAlign: locale.languageCode.toLowerCase() == 'ar'
                        ? TextAlign.right
                        : TextAlign.left,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.7),
                  ),
                ),
              ],
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              if (result.isOptional)
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(result.localizedLaterLabel(locale)),
                ),
              FilledButton(
                onPressed: () => _handleUpdateNow(
                  dialogContext: dialogContext,
                  result: result,
                  locale: locale,
                ),
                child: Text(result.localizedUpdateLabel(locale)),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleUpdateNow({
    required BuildContext dialogContext,
    required AppUpdateCheckResult result,
    required Locale locale,
  }) async {
    final urlText = result.config.appStoreUrl.trim();
    final uri = Uri.tryParse(urlText);
    if (uri == null || urlText.isEmpty) {
      _showMessage(result.localizedInvalidUrlMessage(locale));
      return;
    }

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        _showMessage(result.localizedInvalidUrlMessage(locale));
        return;
      }
      if (!result.isForce && mounted) {
        Navigator.of(dialogContext).pop();
      }
    } catch (_) {
      _showMessage(result.localizedInvalidUrlMessage(locale));
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
