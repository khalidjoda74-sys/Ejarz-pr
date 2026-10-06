import 'dart:io';
import 'dart:ui' as ui;

import 'package:aqdak/core/firebase_repository.dart';
import 'package:aqdak/core/theme.dart';
import 'package:aqdak/widgets/contract_review.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_complete_flow_test.dart' show completeDraft;
import 'contract_form_audit_test.dart' show shell;

void main() {
  setUpAll(() async {
    await (FontLoader(AppTheme.fontFamily)
          ..addFont(
              rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  for (final width in [390.0, 1180.0]) {
    testWidgets('saved residential draft is fully reviewable at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final original = completeDraft()
        ..brokerageFee = '٣٠٠٫٥٠'
        ..otherAmounts = '50.25'
        ..hasSecurityDeposit = true
        ..securityDeposit = '1000'
        ..frozenTotal = 1;
      original.property
        ..electricityMeter = '7000000001'
        ..waterMeter = '8000000001'
        ..gasMeter = '9000000001'
        ..notes =
            'ملاحظات اختبار طويلة للتأكد من عرض المحتوى كاملًا دون قصه. ' * 5;
      original.lessor.nationalAddress =
          'عنوان اختبار طويل لاختبار التفاف النص والمحافظة على كل البيانات. ' *
              5;
      original.electricity.currentReading = '1250';
      original.gas.enabled = false;
      original.regenerateInstallments();
      final draft = FirebaseRepository.draftFromMap(
          FirebaseRepository.draftToMap(original))!;
      final before = FirebaseRepository.draftToMap(draft);
      final boundary = GlobalKey();
      var changes = 0;
      await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: shell(Scaffold(
              body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: ContractReview(
                      draft: draft,
                      requiredAttachments: draft.attachments.take(3).toList(),
                      onChanged: () => changes++))))));
      await tester.pumpAndSettle();
      for (final value in [
        'بيانات المؤجر',
        'بيانات المستأجر',
        'الحساب البنكي للمؤجر',
        'SA0380000000608010167519',
        'رقم الدور',
        '120.5 م²',
        '7000000001',
        '8000000001',
        '9000000001',
        '300.50 ريال',
        '50.25 ريال',
        '1.00 ريال',
        'قراءة عداد الكهرباء',
        '1250',
        'الدفعة 4',
        '3 / 3 مكتملة'
      ]) {
        expect(find.text(value), findsWidgets, reason: value);
      }
      expect(find.text('قراءة عداد الغاز'), findsNothing);
      expect(
          find.byKey(const ValueKey('review-open-ownership')), findsOneWidget);
      Future<void> capture(String suffix) async {
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory('tmp/review-summary-qa').createSync(recursive: true);
          File('tmp/review-summary-qa/review-${width.toInt()}-$suffix.png')
              .writeAsBytesSync(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('top');
      await tester.ensureVisible(find.text('الحساب البنكي للمؤجر'));
      await tester.pumpAndSettle();
      await capture('party-bank');
      await tester
          .ensureVisible(find.byKey(const ValueKey('review-open-ownership')));
      await tester.pumpAndSettle();
      await capture('attachments');
      expect(FirebaseRepository.draftToMap(draft), before);
      expect(changes, 0);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('company representative VAT and fixed service charges are shown',
      (tester) async {
    final draft = completeDraft(commercial: true)
      ..ownerSubjectToVat = true
      ..vatValue = '1800.75';
    draft.representative
      ..authorizationDate = '2026/01/01'
      ..expiryDate = '2028/01/01'
      ..issuer = 'جهة تفويض الاختبار';
    draft.electricity
      ..calculationMethod = 'مبلغ مقطوع'
      ..fixedAmount = '٢٥٫٥٠';
    await tester.pumpWidget(shell(Scaffold(
        body: SingleChildScrollView(
            child: ContractReview(
                draft: draft,
                requiredAttachments: draft.attachments,
                administrative: true,
                onChanged: () {})))));
    await tester.pumpAndSettle();
    for (final value in [
      'السجل التجاري',
      '7123456789',
      'المفوض التجريبي',
      'الوكيل التجريبي',
      'جهة تفويض الاختبار',
      '2028/01/01',
      '1800.75 ريال',
      '25.50 ريال'
    ]) {
      expect(find.text(value), findsWidgets, reason: value);
    }
    expect(find.text('أوافق على الشروط والأحكام'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'missing and unsafe attachments cannot be opened; sections can collapse',
      (tester) async {
    final draft = completeDraft();
    draft.attachments[0].downloadUrl = 'javascript:alert(1)';
    draft.attachments[1].uploaded = false;
    await tester.pumpWidget(shell(Scaffold(
        body: SingleChildScrollView(
            child: ContractReview(
                draft: draft,
                requiredAttachments: draft.attachments.take(3).toList(),
                onChanged: () {})))));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextButton>(
                find.byKey(const ValueKey('review-open-ownership')))
            .onPressed,
        isNull);
    expect(find.byKey(const ValueKey('review-open-authorization')), findsNothing);
    expect(find.text('لم يتم رفع الملف المطلوب'), findsOneWidget);
    await tester.tap(find.text('ملخص العقد'));
    await tester.pumpAndSettle();
    expect(find.text('صفة مقدم الطلب'), findsNothing);
    await tester.tap(find.text('ملخص العقد'));
    await tester.pumpAndSettle();
    expect(find.text('صفة مقدم الطلب'), findsOneWidget);
    expect(draft.acceptAccuracyDeclaration, isFalse);
    expect(draft.acceptTerms, isFalse);
    expect(tester.takeException(), isNull);
  });
}
