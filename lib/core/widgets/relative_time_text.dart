import 'dart:async';

import 'package:flutter/material.dart';

class RelativeTimeText extends StatefulWidget {
  const RelativeTimeText({
    super.key,
    required this.dateTime,
    this.publishedPrefix = false,
    this.style,
    this.textAlign,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
  });

  final DateTime? dateTime;
  final bool publishedPrefix;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  State<RelativeTimeText> createState() => _RelativeTimeTextState();
}

class _RelativeTimeTextState extends State<RelativeTimeText> {
  bool _listening = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _setListening(
      TickerMode.valuesOf(context).enabled && widget.dateTime != null,
    );
  }

  @override
  void didUpdateWidget(covariant RelativeTimeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dateTime != widget.dateTime) {
      _setListening(
        TickerMode.valuesOf(context).enabled && widget.dateTime != null,
      );
    }
  }

  @override
  void dispose() {
    _setListening(false);
    super.dispose();
  }

  void _setListening(bool value) {
    if (_listening == value) return;
    _listening = value;
    if (value) {
      _RelativeTimeTicker.instance.addListener(_handleTick);
    } else {
      _RelativeTimeTicker.instance.removeListener(_handleTick);
    }
  }

  void _handleTick() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final label = relativeOpportunityTimeLabel(
      widget.dateTime,
      publishedPrefix: widget.publishedPrefix,
    );
    if (label.isEmpty) return const SizedBox.shrink();

    return Text(
      label,
      textAlign: widget.textAlign,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      style: widget.style,
    );
  }
}

class _RelativeTimeTicker extends ChangeNotifier with WidgetsBindingObserver {
  _RelativeTimeTicker._() {
    WidgetsBinding.instance.addObserver(this);
  }

  static final _RelativeTimeTicker instance = _RelativeTimeTicker._();

  Timer? _timer;
  int _listenerCount = 0;
  AppLifecycleState _lifecycleState =
      WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _listenerCount++;
    _syncTimer();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (_listenerCount > 0) _listenerCount--;
    _syncTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    _syncTimer();
  }

  void _syncTimer() {
    final shouldRun =
        _listenerCount > 0 && _lifecycleState == AppLifecycleState.resumed;
    if (!shouldRun) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(
      const Duration(seconds: 10),
      (_) => notifyListeners(),
    );
  }
}

String relativeOpportunityTimeLabel(
  DateTime? dateTime, {
  bool publishedPrefix = false,
  DateTime? now,
}) {
  if (dateTime == null) return '';

  final currentUtc = (now ?? DateTime.now()).toUtc();
  final createdUtc = dateTime.toUtc();
  var difference = currentUtc.difference(createdUtc);
  if (difference.isNegative) difference = Duration.zero;

  final base = _relativeLabel(difference, createdUtc);
  if (!publishedPrefix) return base;

  return _isAbsoluteDate(base) ? 'نُشرت في $base' : 'نُشرت $base';
}

String _relativeLabel(Duration difference, DateTime createdUtc) {
  final seconds = difference.inSeconds;
  if (seconds < 10) return 'الآن';
  if (seconds < 60) return 'منذ ثوانٍ';

  final minutes = difference.inMinutes;
  if (minutes < 60) return _unitLabel(minutes, 'دقيقة', 'دقيقتين', 'دقائق');

  final hours = difference.inHours;
  if (hours < 24) return _unitLabel(hours, 'ساعة', 'ساعتين', 'ساعات');

  final days = difference.inDays;
  if (days < 7) return _unitLabel(days, 'يوم', 'يومين', 'أيام');

  return _saudiDateLabel(createdUtc);
}

String _unitLabel(int count, String single, String dual, String plural) {
  if (count <= 1) return 'منذ $single';
  if (count == 2) return 'منذ $dual';
  if (count <= 10) return 'منذ $count $plural';
  return 'منذ $count $single';
}

String _saudiDateLabel(DateTime createdUtc) {
  const months = [
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];
  final saudiTime = createdUtc.add(const Duration(hours: 3));
  return '${saudiTime.day} ${months[saudiTime.month - 1]} ${saudiTime.year}';
}

bool _isAbsoluteDate(String value) =>
    !value.startsWith('منذ') && value != 'الآن';
