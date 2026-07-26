import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Release-safe frame probe used only by explicit performance builds.
///
/// With no dart-define this branch is constant-false and removed by AOT.
class NavigationPerformanceProbe {
  const NavigationPerformanceProbe._();

  static const bool _enabled =
      bool.fromEnvironment('FORSA_PERF_PROBE', defaultValue: false);
  static final List<int> _frameCostsMicros = <int>[];
  static int _lastReportedCount = 0;

  static void startIfEnabled() {
    if (!_enabled) return;
    SchedulerBinding.instance.addTimingsCallback(_record);
  }

  static void _record(List<FrameTiming> timings) {
    for (final timing in timings) {
      _frameCostsMicros.add(
        math.max(
          timing.buildDuration.inMicroseconds,
          timing.rasterDuration.inMicroseconds,
        ),
      );
    }
    if (_frameCostsMicros.length - _lastReportedCount < 20) return;
    _lastReportedCount = _frameCostsMicros.length;

    final ordered = List<int>.from(_frameCostsMicros)..sort();
    final p95Index =
        ((ordered.length - 1) * .95).round().clamp(0, ordered.length - 1);
    final jankyFrames = ordered.where((duration) => duration > 16700).length;
    debugPrint(
      'FORSA_PERF '
      'total_frames=${ordered.length} '
      'janky=$jankyFrames '
      'p95_us=${ordered[p95Index]} '
      'worst_us=${ordered.last}',
    );
  }
}
