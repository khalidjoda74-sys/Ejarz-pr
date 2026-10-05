import 'dart:io';
import 'dart:ui' as ui;
import 'package:aqdak/core/admin_contract_session.dart';
import 'package:aqdak/core/app_controller.dart';
import 'package:aqdak/core/models.dart';
import 'package:aqdak/core/runtime_config.dart';
import 'package:aqdak/core/theme.dart';
import 'package:aqdak/screens/create_contract.dart';
import 'package:aqdak/widgets/admin_contract_fee_panel.dart';
import 'package:aqdak/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class EditorSession extends AdminContractSession {
  ContractDraft? saved;
  EditorSession() : super('customer', 'employee', 'draft123') {
    userName = 'خالد أحمد';
    userPhone = '0501234567';
    canWaive = true;
    canRecordExternal = true;
  }
  @override
  Future<ContractRecord> saveDraft(ContractDraft draft,
      {String draftId = '',
      DraftProgress progress = const DraftProgress()}) async {
    saved = ContractDraft.copyOf(draft);
    revision = 123;
    return ContractRecord(
        id: contractId,
        requestNumber: 'REQ-123',
        uid: customerUid,
        type: draft.type,
        role: draft.role,
        title: draft.title,
        property: 'عقار',
        lessorName: '',
        tenantName: '',
        date: '',
        status: ContractStatus.draft,
        totalFees: 0,
        timeline: [],
        draftData: saved);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fonts = FontLoader(AppTheme.fontFamily)
      ..addFont(rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf'));
    await fonts.load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  for (final width in [390.0, 1280.0]) {
    testWidgets(
        'shared administrative editor saves customer draft at width $width',
        (tester) async {
      AppRuntime.config = {};
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = EditorSession();
      addTearDown(session.dispose);
      final preview = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: preview,
          child: AppScope(
              controller: session,
              child: MaterialApp(
                  locale: const Locale('ar'),
                  supportedLocales: const [Locale('ar'), Locale('en')],
                  localizationsDelegates: const [
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate
                  ],
                  theme: AppTheme.light(),
                  home: CreateContractScreen(
                      adminSession: session,
                      initialDraft: ContractDraft(),
                      draftId: session.contractId,
                      initialStep: 6)))));
      await tester.pumpAndSettle();
      expect(find.byType(AdminContractFeePanel), findsOneWidget);
      expect(find.text('أوافق على الشروط والأحكام'), findsNothing);
      expect(find.text('أقر بإعداد وإرسال الطلب نيابةً عن العميل'),
          findsOneWidget);
      expect(find.text('العميل: خالد أحمد • 0501234567'), findsOneWidget);
      await tester.tap(find.text('حفظ التعديلات'));
      await tester.pumpAndSettle();
      expect(session.saved, isNotNull);
      expect(session.customerUid, 'customer');
      expect(session.actorUid, 'employee');
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('تنفيذ مباشر — إعفاء من الرسوم').last);
      await tester.pumpAndSettle();
      expect(session.mode, 'waived');
      expect(
          find.byWidgetPredicate((widget) =>
              widget is AppTextField && widget.label == 'سبب الإعفاء'),
          findsOneWidget);
      expect(find.text('سيظهر الطلب للعميل قيد المعالجة دون مرحلة دفع.'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final image = await (preview.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory('tmp/admin-contract-qa').createSync(recursive: true);
        File('tmp/admin-contract-qa/editor-${width.toInt()}.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    });
  }
  test('administrative fee actions require explicit grants in the editor', () {
    final session = AdminContractSession('customer', 'employee', 'draft');
    expect(session.canWaive, isFalse);
    expect(session.canRecordExternal, isFalse);
    expect(session.acknowledged, isFalse);
    session.dispose();
  });
}
