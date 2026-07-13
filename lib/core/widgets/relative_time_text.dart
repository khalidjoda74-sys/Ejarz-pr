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
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant RelativeTimeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dateTime != widget.dateTime) _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.dateTime == null) return;
    _scheduleNextTick();
  }

  void _scheduleNextTick() {
    final delay = _nextRefreshDelay();
    if (delay == null) return;
    _timer = Timer(delay, () {
      if (!mounted) return;
      setState(() {});
      _scheduleNextTick();
    });
  }

  Duration? _nextRefreshDelay() {
    final dateTime = widget.dateTime;
    if (dateTime == null) return null;
    final difference = DateTime.now().toUtc().difference(dateTime.toUtc());
    if (difference.inMinutes < 1) return const Duration(seconds: 10);
    if (difference.inHours < 1) return const Duration(minutes: 1);
    if (difference.inDays < 1) return const Duration(minutes: 5);
    return const Duration(minutes: 30);
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

bool _isAbsoluteDate(String value) => !value.startsWith('منذ') && value != 'الآن';