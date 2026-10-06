import 'package:aqdak/core/firebase_repository.dart';
import 'package:aqdak/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy recovery keeps later review and final outcome at the end', () {
    for (final status in [
      ContractStatus.authenticated,
      ContractStatus.missingData,
      ContractStatus.rejected
    ]) {
      final outcome =
          FirebaseRepository.timelineEventFor(status, DateTime(2026, 10, 6));
      final timeline = FirebaseRepository.normalizeTimelineForStatus(
          status: status,
          items: [outcome],
          paymentStatus: 'paid',
          paidAt: DateTime.parse('2026-10-05T14:21:00Z'));
      expect(timeline.last.eventStatus, status);
      expect(
          timeline.where((item) => item.title == 'تم تأكيد سداد الرسوم').length,
          1);
      expect(timeline.last.current, status != ContractStatus.authenticated);
    }
  });
  test('old paid record recovers recorded settlement without duplicates', () {
    const old = [
      StatusTimelineItem(
          title: 'بانتظار الدفع',
          subtitle: 'بانتظار الدفع',
          date: '2026/10/05',
          time: '17:12',
          current: true)
    ];
    final paidAt = DateTime.parse('2026-10-05T14:21:00Z');
    final timeline = FirebaseRepository.normalizeTimelineForStatus(
        status: ContractStatus.processing,
        items: old,
        paymentStatus: 'paid',
        paidAt: paidAt,
        submittedAt: DateTime.parse('2026-10-05T14:12:00Z'));
    expect(timeline.map((item) => item.title), [
      'تم إرسال الطلب',
      'بانتظار الدفع',
      'تم تأكيد سداد الرسوم',
      'قيد المعالجة'
    ]);
    expect(timeline[2].time, '17:21');
    final repeated = FirebaseRepository.normalizeTimelineForStatus(
        status: ContractStatus.processing,
        items: timeline,
        paymentStatus: 'paid',
        paidAt: paidAt);
    expect(repeated.length, timeline.length);
    final pending = FirebaseRepository.normalizeTimelineForStatus(
        status: ContractStatus.processing,
        items: old,
        paymentStatus: 'pending',
        paidAt: paidAt);
    expect(
        pending.any((item) => item.title == 'تم تأكيد سداد الرسوم'), isFalse);
  });
  test('legacy future completion cannot become the current processing stage',
      () {
    final timeline = FirebaseRepository.normalizeTimelineForStatus(
      status: ContractStatus.processing,
      items: const [
        StatusTimelineItem(
            title: 'قيد المعالجة',
            subtitle: 'تحت المراجعة',
            date: '',
            time: '',
            current: true),
        StatusTimelineItem(
            title: 'مكتمل',
            subtitle: 'تم إصدار العقد النهائي',
            date: '',
            time: ''),
      ],
    );
    expect(timeline.single.title, 'قيد المعالجة');
    expect(timeline.single.current, isTrue);
    expect(timeline.single.completed, isFalse);
  });
  const items = <StatusTimelineItem>[
    StatusTimelineItem(
        title: 'تم حفظ المسودة',
        subtitle: 'لم يتم إرسال الطلب للمراجعة بعد',
        date: '2026/10/05',
        time: '15:01',
        current: true,
        eventStatus: ContractStatus.draft),
    StatusTimelineItem(
        title: 'تم إرسال الطلب',
        subtitle: 'تم الاستلام',
        date: '2026/10/05',
        time: '17:12'),
    StatusTimelineItem(
        title: 'بانتظار الدفع',
        subtitle: 'ادفع للمتابعة',
        date: '2026/10/05',
        time: '17:12',
        current: true,
        eventStatus: ContractStatus.awaitingPayment),
    StatusTimelineItem(
        title: 'تم تأكيد سداد الرسوم',
        subtitle: 'تم تأكيد الدفع من بوابة الدفع.',
        date: '2026/10/05',
        time: '17:40',
        completed: true),
    StatusTimelineItem(
        title: 'قيد المعالجة',
        subtitle: 'تم استلام الدفع، وجارٍ مراجعة طلبك.',
        date: '2026/10/05',
        time: '17:40',
        current: true,
        eventStatus: ContractStatus.processing),
  ];
  test('paid request has one current stage and completed history', () {
    final timeline = FirebaseRepository.normalizeTimelineForStatus(
        status: ContractStatus.processing, items: items);
    expect(timeline.where((item) => item.current).length, 1);
    expect(timeline.take(4).every((item) => item.completed), isTrue);
    expect(timeline.last.current, isTrue);
    expect(timeline.last.completed, isFalse);
    expect(timeline.first.subtitle, 'حُفظت المسودة قبل إرسال الطلب.');
    expect(timeline[2].subtitle, 'كانت الرسوم بانتظار السداد.');
    expect(timeline[3].time, '17:40');
    expect(items.first.subtitle, 'لم يتم إرسال الطلب للمراجعة بعد');
  });
  test('pending payment does not imply paid or processing', () {
    final timeline = FirebaseRepository.normalizeTimelineForStatus(
        status: ContractStatus.awaitingPayment, items: items.take(3).toList());
    expect(timeline.last.title, 'بانتظار الدفع');
    expect(timeline.last.subtitle, 'ادفع للمتابعة');
    expect(timeline.where((item) => item.current).length, 1);
    expect(timeline.where((item) => item.title == 'تم تأكيد سداد الرسوم'),
        isEmpty);
  });
  test('issued request completes all stages and rejection remains terminal',
      () {
    final complete = FirebaseRepository.normalizeTimelineForStatus(
        status: ContractStatus.authenticated, items: items);
    expect(complete.every((item) => item.completed && !item.current), isTrue);
    final rejected = FirebaseRepository.normalizeTimelineForStatus(
        status: ContractStatus.rejected,
        items: items,
        rejectionReason: 'سبب المراجعة');
    expect(rejected.last.title, 'تم رفض الطلب نهائيًا');
    expect(rejected.last.current, isTrue);
    expect(
        rejected
            .take(rejected.length - 1)
            .every((item) => item.completed && !item.current),
        isTrue);
  });
}
