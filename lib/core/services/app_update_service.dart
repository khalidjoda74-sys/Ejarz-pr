import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/app_update_config.dart';

class AppUpdateService {
  AppUpdateService({
    FirebaseFirestore? firestore,
    Future<PackageInfo> Function()? packageInfoLoader,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform;

  final FirebaseFirestore _firestore;
  final Future<PackageInfo> Function() _packageInfoLoader;

  static const String publicConfigPath = 'app_config/app_update_config';
  static const String fallbackConfigPath = 'app_config/config';

  Future<AppUpdateCheckResult> checkForIosUpdate() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return const AppUpdateCheckResult(
        availability: AppUpdateAvailability.none,
        currentVersion: '',
        config: AppUpdateConfig.disabled,
      );
    }

    try {
      final packageInfo = await _packageInfoLoader();
      final currentVersion = _normalizeVersion(packageInfo.version);
      if (currentVersion.isEmpty) {
        return const AppUpdateCheckResult(
          availability: AppUpdateAvailability.none,
          currentVersion: '',
          config: AppUpdateConfig.disabled,
        );
      }

      final config = await _loadConfig();
      return AppUpdateCheckResult(
        availability: _resolveAvailability(
          currentVersion: currentVersion,
          config: config,
        ),
        currentVersion: currentVersion,
        config: config,
      );
    } catch (_) {
      return const AppUpdateCheckResult(
        availability: AppUpdateAvailability.none,
        currentVersion: '',
        config: AppUpdateConfig.disabled,
      );
    }
  }

  Future<AppUpdateConfig> _loadConfig() async {
    try {
      final publicDoc = await _firestore.doc(publicConfigPath).get();
      if (publicDoc.exists) {
        return AppUpdateConfig.fromMap(publicDoc.data());
      }
    } catch (_) {}

    try {
      final fallbackDoc = await _firestore.doc(fallbackConfigPath).get();
      if (fallbackDoc.exists) {
        return AppUpdateConfig.fromMap(fallbackDoc.data());
      }
    } catch (_) {}

    return AppUpdateConfig.disabled;
  }

  AppUpdateAvailability _resolveAvailability({
    required String currentVersion,
    required AppUpdateConfig config,
  }) {
    if (!config.enabled) return AppUpdateAvailability.none;

    final normalizedCurrent = _normalizeVersion(currentVersion);
    final normalizedMin = _normalizeVersion(config.minimumSupportedVersion);
    final normalizedLatest = _normalizeVersion(config.latestVersion);

    if (normalizedMin.isNotEmpty &&
        _compareVersions(normalizedCurrent, normalizedMin) < 0) {
      return AppUpdateAvailability.force;
    }

    if (normalizedLatest.isNotEmpty &&
        _compareVersions(normalizedCurrent, normalizedLatest) < 0) {
      return config.forceUpdate
          ? AppUpdateAvailability.force
          : AppUpdateAvailability.optional;
    }

    return AppUpdateAvailability.none;
  }

  static String _normalizeVersion(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.split('+').first.trim();
  }

  static int _compareVersions(String a, String b) {
    final partsA = a.split('.').map(_segmentToInt).toList(growable: false);
    final partsB = b.split('.').map(_segmentToInt).toList(growable: false);
    final length = partsA.length > partsB.length ? partsA.length : partsB.length;
    for (int i = 0; i < length; i++) {
      final left = i < partsA.length ? partsA[i] : 0;
      final right = i < partsB.length ? partsB[i] : 0;
      if (left == right) continue;
      return left < right ? -1 : 1;
    }
    return 0;
  }

  static int _segmentToInt(String segment) {
    final match = RegExp(r'\d+').firstMatch(segment.trim());
    if (match == null) return 0;
    return int.tryParse(match.group(0) ?? '') ?? 0;
  }
}
