import 'package:aqood_pro/core/firebase_repository.dart';
import 'package:aqood_pro/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('rejected contract policy', () {
    test('requires a reason and rejects invalid source states', () {
      expect(
        () => FirebaseRepository.validateAdminStatusTransition(
          currentStatus: ContractStatus.processing,
          nextStatus: ContractStatus.rejected,
        ),
        throwsArgumentError,
      );
      expect(
        () => FirebaseRepository.validateAdminStatusTransition(
          currentStatus: ContractStatus.draft,
          nextStatus: ContractStatus.rejected,
          customerNote: 'سبب واضح',
        ),
        throwsStateError,
      );
      expect(
        () => FirebaseRepository.validateAdminStatusTransition(
          currentStatus: ContractStatus.authenticated,
          nextStatus: ContractStatus.rejected,
          customerNote: 'سبب واضح',
        ),
        throwsStateError,
      );
    });

    test('rejected is terminal', () {
      for (final next in ContractStatus.values) {
        expect(
          () => FirebaseRepository.validateAdminStatusTransition(
            currentStatus: ContractStatus.rejected,
            nextStatus: next,
            customerNote: 'سبب',
          ),
          throwsStateError,
        );
      }
    });

    test('normalizes legacy rejected timeline without completed outcome', () {
      final timeline = FirebaseRepository.normalizeTimelineForStatus(
        status: ContractStatus.rejected,
        rejectionReason: 'بيانات الملكية غير متطابقة',
        items: const <StatusTimelineItem>[
          StatusTimelineItem(
            title: 'تم استلام الطلب',
            subtitle: 'تم الاستلام',
            date: '2026/07/20',
            time: '10:00',
            completed: true,
          ),
          StatusTimelineItem(
            title: 'قيد المعالجة',
            subtitle: 'يعمل الفريق على الطلب',
            date: '2026/07/20',
            time: '11:00',
            current: true,
          ),
          StatusTimelineItem(
            title: 'مكتمل',
            subtitle: 'تم إصدار العقد النهائي',
            date: '2026/07/20',
            time: '12:00',
          ),
        ],
      );

      expect(timeline.map((item) => item.title), <String>[
        'تم استلام الطلب',
        'قيد المعالجة',
        'تم رفض الطلب نهائيًا',
      ]);
      expect(timeline[1].completed, isTrue);
      expect(timeline.last.current, isTrue);
      expect(timeline.last.eventStatus, ContractStatus.rejected);
      expect(timeline.last.subtitle, 'سبب الرفض: بيانات الملكية غير متطابقة');
    });

    test('keeps non-rejected timeline unchanged', () {
      const items = <StatusTimelineItem>[
        StatusTimelineItem(
          title: 'قيد المعالجة',
          subtitle: 'تحت المراجعة',
          date: '2026/07/20',
          time: '10:00',
          current: true,
        ),
      ];
      expect(
        FirebaseRepository.normalizeTimelineForStatus(
          status: ContractStatus.processing,
          items: items,
        ),
        same(items),
      );
    });
  });
}
