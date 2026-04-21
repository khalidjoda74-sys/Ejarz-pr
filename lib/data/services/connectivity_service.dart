// lib/data/services/connectivity_service.dart
import 'dart:async';
import 'dart:io' show InternetAddress;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  final _connectivity = Connectivity();
  final _controller = StreamController<bool>.broadcast();
  final ValueNotifier<bool?> statusListenable = ValueNotifier<bool?>(null);
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  Stream<bool> get onConnectivityChanged => _controller.stream;

  bool _isOnline = false;
  bool get isOnline => _isOnline;
  bool? get currentStatus => statusListenable.value;

  Future<void> init() async {
    await refresh();
    await _subscription?.cancel();
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      unawaited(_updateStatus(results));
    });
  }

  Future<bool> refresh() async {
    final result = await _connectivity.checkConnectivity();
    return _updateStatus(result);
  }

  Future<bool> _updateStatus(List<ConnectivityResult> results) async {
    final hasConnection =
        results.isNotEmpty && !results.contains(ConnectivityResult.none);

    var hasReachableInternet = false;
    if (hasConnection) {
      hasReachableInternet = await _probeInternet();
    }

    if (_isOnline != hasReachableInternet) {
      _isOnline = hasReachableInternet;
      _controller.add(_isOnline);
    }
    if (statusListenable.value != hasReachableInternet) {
      statusListenable.value = hasReachableInternet;
    }
    return hasReachableInternet;
  }

  Future<bool> _probeInternet() async {
    try {
      final firestoreLookup = await InternetAddress.lookup(
        'firestore.googleapis.com',
      ).timeout(const Duration(seconds: 2));
      if (firestoreLookup.isNotEmpty &&
          firestoreLookup.first.rawAddress.isNotEmpty) {
        return true;
      }
    } catch (_) {}

    try {
      final googleLookup = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 2));
      return googleLookup.isNotEmpty &&
          googleLookup.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
