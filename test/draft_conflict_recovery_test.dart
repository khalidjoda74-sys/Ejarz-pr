import 'package:aqdak/core/app_controller.dart';
import 'package:aqdak/core/models.dart';
import 'package:aqdak/core/runtime_config.dart';
import 'package:aqdak/core/theme.dart';
import 'package:aqdak/screens/create_contract.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class ConflictController extends AppController {
  ConflictController() : super(initializeSession: false);
  final saved = <ContractDraft>[];
  final ids = <String>[];
  @override
  Future<ContractRecord> saveDraft(ContractDraft draft,
      {String draftId = '',
      DraftProgress progress = const DraftProgress()}) async {
    saved.add(ContractDraft.copyOf(draft));
    ids.add(draftId);
    if (draftId.isNotEmpty) {
      throw FirebaseFunctionsException(
          code: 'aborted', message: 'تغيرت المسودة');
    }
    return ContractRecord(
        id: 'new-draft',
        requestNumber: 'REQ-NEW',
        uid: 'local-demo',
        type: draft.type,
        role: draft.role,
        title: draft.title,
        property: '',
        lessorName: '',
        tenantName: '',
        date: '',
        status: ContractStatus.draft,
        totalFees: 0,
        timeline: [],
        draftData: ContractDraft.copyOf(draft)..serverRevision = 456);
  }
}

void main() {
  testWidgets('save conflict is recoverable without overwriting the old draft',
      (tester) async {
    AppRuntime.config = {};
    final controller = ConflictController();
    addTearDown(controller.dispose);
    final draft = ContractDraft()
      ..serverRevision = 123
      ..specialTerms = 'طلب اختبار';
    draft.attachments.first
      ..uploaded = true
      ..fileName = 'test.pdf';
    await tester.pumpWidget(AppScope(
        controller: controller,
        child: MaterialApp(
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate
            ],
            theme: AppTheme.light(),
            home: CreateContractScreen(
                initialDraft: draft, draftId: 'old-draft', initialStep: 6))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ التعديلات'));
    await tester.pumpAndSettle();
    expect(find.text('احتفظ بتعديلاتك'), findsOneWidget);
    await tester.tap(find.text('حفظ تعديلاتي في مسودة جديدة'));
    await tester.pumpAndSettle();
    expect(controller.ids, ['old-draft', '']);
    expect(controller.saved.last.specialTerms, 'طلب اختبار');
    expect(controller.saved.last.attachments.first.uploaded, isTrue);
    expect(controller.saved.last.serverRevision, isNull);
    expect(find.textContaining('تمت مزامنة المسودة'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
