import 'package:flutter/material.dart';

import '../core/contract_calculation_engine.dart';
import '../core/contract_pricing.dart';
import '../core/document_links.dart';
import '../core/models.dart';
import '../core/theme.dart';
import 'common.dart';

/// Read-only review of the same draft that will be submitted.
class ContractReview extends StatelessWidget {
  final ContractDraft draft;
  final List<AttachmentData> requiredAttachments;
  final bool administrative;
  final VoidCallback onChanged;

  const ContractReview({
    super.key,
    required this.draft,
    required this.requiredAttachments,
    required this.onChanged,
    this.administrative = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = draft.property;
    final rep = draft.representative;
    final requiredKeys = requiredAttachments.map((a) => a.keyName).toSet();
    final uploadedRequired = requiredAttachments.where(_ready).length;
    final sections = <Widget>[
      _Section(title: 'ملخص العقد', icon: Icons.article_outlined, children: [
        _Line('نوع العقد', draft.type.label),
        _Line('صفة مقدم الطلب', draft.role.label),
        _Line('العنوان', _value(p.displayAddress)),
        _Line('الوحدة', _value(p.unitNumber)),
        _Line('مدة العقد',
            '${draft.durationYears} سنة / ${draft.durationMonths} شهر / ${draft.durationDays} يوم'),
        _Line('تاريخ البداية', _value(draft.startDate)),
        _Line('تاريخ النهاية', _value(draft.endDate)),
        _Line('الإجمالي المستحق الآن', _money(draft.totalPayable),
            strong: true),
      ]),
      _Section(
          title: 'بيانات الملكية',
          icon: Icons.verified_outlined,
          children: [
            _Line('نوع الإثبات', _value(p.ownershipDocumentType)),
            _Line('رقم الوثيقة', _value(p.ownershipDocumentNumber)),
            _Line('تاريخ الوثيقة', _value(p.ownershipDocumentDate)),
          ]),
      _party('بيانات المؤجر', draft.lessor),
      _party('بيانات المستأجر', draft.tenant),
      _Section(
          title: 'الحساب البنكي للمؤجر',
          icon: Icons.account_balance_outlined,
          children: [
            _Line('الآيبان', _value(draft.lessor.iban), paragraph: true),
            _Line('البنك', _value(draft.lessor.bankName)),
            _Line('صاحب الحساب', _value(draft.lessor.accountOwner)),
          ]),
      _Section(title: 'الممثل القانوني', icon: Icons.badge_outlined, children: [
        if (!rep.enabled)
          const _Line('الممثل القانوني', 'لا يوجد')
        else ...[
          _Line('يمثل', _value(rep.represents)),
          _Line('صفة الممثل', _value(rep.type)),
          _Line('الاسم', _value(rep.fullName)),
          _Line('نوع الهوية', _value(rep.idType)),
          _Line('رقم الهوية', _value(rep.idNumber)),
          _Line('تاريخ الميلاد', _value(rep.birthDate)),
          _Line('رقم الجوال', _value(rep.mobile)),
          _Line('رقم الوكالة أو التفويض', _value(rep.authorizationNumber)),
          _Line('تاريخ الوكالة أو التفويض', _value(rep.authorizationDate)),
          _Line('جهة الإصدار', _optional(rep.issuer)),
          _Line('تاريخ انتهاء الوكالة أو التفويض', _optional(rep.expiryDate)),
        ],
      ]),
      _Section(
          title: 'بيانات العقار',
          icon: Icons.apartment_outlined,
          children: [
            _Line('مصدر العقار', _value(p.propertySource)),
            _Line('اسم العقار أو المبنى', _optional(p.buildingName)),
            _Line('نوع العقار الرئيسي', _value(p.propertyType)),
            _Line('استخدام العقار', _value(p.propertyUsage)),
            _Line('عدد الأدوار', _value(p.floorsCount)),
            _Line('عدد الوحدات في كل دور', _optional(p.unitsPerFloor)),
            _Line('إجمالي الوحدات', _value(p.totalUnits)),
            _Line('المدينة', _value(p.city)),
            _Line('الحي', _value(p.district)),
            _Line('الشارع', _value(p.street)),
            _Line('رقم المبنى', _value(p.buildingNumber)),
            _Line('الرقم الإضافي', _value(p.additionalNumber)),
            _Line('الرمز البريدي', _value(p.postalCode)),
          ]),
      _Section(title: 'بيانات الوحدة', icon: Icons.home_outlined, children: [
        _Line('رقم الوحدة', _value(p.unitNumber)),
        _Line('اسم الوحدة', _value(p.unitName)),
        _Line('نوع الوحدة', _value(p.unitType)),
        if (p.residentialCategory.trim().isNotEmpty)
          _Line('الفئة السكنية', p.residentialCategory),
        _Line('رقم الدور', _value(p.floor)),
        _Line('مساحة الوحدة',
            p.area.trim().isEmpty ? 'غير محدد' : '${p.area} م²'),
        if (draft.type == ContractType.residential)
          _Line('عدد الغرف', _value(p.roomsCount)),
        _Line('دورات المياه', _value(p.bathroomsCount)),
        _Line('الصالات', _value(p.hallsCount)),
        _Line('حالة التأثيث', _value(p.furnishingStatus)),
        _Line('ملاحظات على الوحدة', _optional(p.notes), paragraph: true),
      ]),
      _Section(
          title: 'المرافق والعدادات',
          icon: Icons.grid_view_rounded,
          children: [
            _Line('غرفة خادمة', _yesNo(p.maidRoom)),
            _Line('عدد المطابخ', p.kitchenCount),
            _Line('عدد المجالس', p.majlisCount),
            _Line('عدد المخازن', p.storageCount),
            _Line('عدد مكيفات الشباك', p.acWindowCount),
            _Line('عدد مكيفات السبليت', p.acSplitCount),
            _Line('عدد أجهزة التكييف المركزي', p.acCentralCount),
            _Line('موقف خاص', _yesNo(p.privateParking)),
            _Line('رقم عداد الكهرباء', _optional(p.electricityMeter)),
            _Line('رقم عداد المياه', _optional(p.waterMeter)),
            _Line('رقم عداد الغاز', _optional(p.gasMeter)),
          ]),
      _Section(
          title: 'المبالغ والرسوم',
          icon: Icons.payments_outlined,
          children: [
            _Line('مبلغ الإيجار السنوي', _money(draft.rentValueNumber)),
            if (draft.rentalCalculation case final rental?)
              _Line('إجمالي الإيجار طوال العقد',
                  _money(rental.totalHalalas / 100),
                  strong: true),
            _Line(
                'الضمان',
                draft.hasSecurityDeposit
                    ? _money(draft.depositNumber)
                    : 'لا يوجد'),
            _Line('عمولة السعي', _amount(draft.brokerageFee)),
            _Line('دافع عمولة السعي', _value(draft.brokeragePayer)),
            _Line('مبالغ أخرى', _amount(draft.otherAmounts)),
            _Line('المؤجر خاضع لضريبة القيمة المضافة',
                draft.ownerSubjectToVat ? 'نعم' : 'لا'),
            if (draft.ownerSubjectToVat)
              _Line('قيمة الضريبة', _amount(draft.vatValue)),
            _Line('دافع رسوم منصة إيجار', _value(draft.officialFeePayer)),
            _Line('دافع عمولة عقدك', _value(draft.serviceFeePayer)),
            _Line('طريقة دفع رسوم الطلب', _paymentMethod(draft.paymentMethod)),
            _Line('رسوم السنة الأولى', _money(draft.price.firstYear)),
            _Line('رسوم المدة الإضافية', _money(draft.price.additionalAmount)),
            _Line('الإجمالي المستحق الآن', _money(draft.totalPayable),
                strong: true),
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(ContractPrice.inclusionNote)),
          ]),
      _Section(
          title: 'جدول الدفعات',
          icon: Icons.calendar_month_outlined,
          children: [
            _Line('دورة سداد الإيجار', _value(draft.rentPeriod)),
            _Line('نوع الجدولة', _value(draft.paymentScheduleType)),
            if (draft.paymentScheduleType == 'دوري')
              _Line('تكرار الدفع', _value(draft.paymentFrequency)),
            _Line('عدد الدفعات', '${draft.paymentCount}'),
            _Line('تاريخ أول دفعة', _value(draft.firstPaymentDate)),
            _Line('قناة دفع الإيجار', _value(draft.paymentChannel)),
            for (final installment in draft.installments)
              _Installment(installment),
          ]),
      _Section(
          title: 'الخدمات',
          icon: Icons.electrical_services_outlined,
          children: [
            ..._service('الكهرباء', draft.electricity),
            ..._service('المياه', draft.water),
            ..._service('الغاز', draft.gas),
            _Line('خدمات أو شروط مالية إضافية', _optional(draft.otherServices),
                paragraph: true),
          ]),
      _Section(title: 'الشروط', icon: Icons.rule_folder_outlined, children: [
        _Line('التأجير من الباطن', draft.allowSublease ? 'مسموح' : 'غير مسموح'),
        _Line('الشروط الإضافية', _optional(draft.specialTerms),
            paragraph: true),
      ]),
      _Section(title: 'المرفقات', icon: Icons.attach_file_rounded, children: [
        _Line('المرفقات المطلوبة',
            '$uploadedRequired / ${requiredAttachments.length} مكتملة',
            strong: true),
        _Line('إجمالي المرفقات المرفوعة',
            '${draft.attachments.where(_ready).length}'),
        for (final attachment in draft.attachments)
          _Attachment(attachment,
              requiredFile: requiredKeys.contains(attachment.keyName)),
      ]),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const AppPageHeader(
          title: 'المراجعة النهائية',
          subtitle:
              'راجع جميع البيانات والمرفقات قبل الإرسال. يمكنك طي أي قسم لتسهيل المراجعة.',
          icon: Icons.fact_check_outlined),
      const SizedBox(height: 16),
      for (final section in sections) ...[section, const SizedBox(height: 14)],
      if (!administrative) ...[
        ToggleCard(
            title: 'أقر بصحة البيانات والمستندات',
            subtitle: 'أتحمل مسؤولية دقة المعلومات المدخلة في الطلب',
            value: draft.acceptAccuracyDeclaration,
            icon: Icons.verified_user_outlined,
            onChanged: (v) {
              draft.acceptAccuracyDeclaration = v;
              onChanged();
            }),
        const SizedBox(height: 10),
        ToggleCard(
            title: 'أوافق على مشاركة البيانات اللازمة',
            subtitle: 'تستخدم البيانات لإتمام إصدار العقد ومراجعته',
            value: draft.acceptDataSharing,
            icon: Icons.shield_outlined,
            onChanged: (v) {
              draft.acceptDataSharing = v;
              onChanged();
            }),
        const SizedBox(height: 10),
        ToggleCard(
            title: 'أوافق على الشروط والأحكام',
            subtitle: 'لن يتم رفع الطلب قبل قبول الشروط',
            value: draft.acceptTerms,
            icon: Icons.policy_outlined,
            onChanged: (v) {
              draft.acceptTerms = v;
              onChanged();
            }),
        const SizedBox(height: 14),
      ],
      const InfoBanner(
          text:
              'بعد التأكيد سيتم إنشاء طلب مراجعة جديد ويمكنك متابعة حالته من صفحة العقود.',
          icon: Icons.info_outline_rounded),
    ]);
  }
}

Widget _party(String title, PartyData p) =>
    _Section(title: title, icon: Icons.person_outline_rounded, children: [
      _Line('نوع الطرف', p.kind == PartyKind.individual ? 'فرد' : 'منشأة'),
      _Line('الاسم', _value(p.fullName)),
      if (p.kind == PartyKind.individual) ...[
        _Line('نوع الهوية', _value(p.idType)),
        _Line('رقم الهوية', _value(p.idNumber)),
        _Line('تاريخ الميلاد', _value(p.birthDate)),
      ] else ...[
        _Line('السجل التجاري', _value(p.commercialRegistration)),
        _Line('الرقم الموحد للمنشأة', _value(p.unifiedNumber)),
        _Line('اسم المفوض', _value(p.authorizedPersonName)),
        _Line('هوية المفوض', _value(p.authorizedPersonId)),
      ],
      _Line('رقم الجوال', _value(p.mobile)),
      _Line('الجوال مسجل في أبشر', p.mobileRegisteredInAbsher ? 'نعم' : 'لا'),
      _Line('البريد الإلكتروني', _optional(p.email), paragraph: true),
      _Line('المدينة', _value(p.city)),
      _Line('الحي', _value(p.district)),
      _Line('العنوان الوطني', _value(p.nationalAddress), paragraph: true),
    ]);

List<Widget> _service(String title, ServiceCharge s) => [
      _Line(title, s.enabled ? 'مضافة إلى العقد' : 'غير مضافة'),
      if (s.enabled) ...[
        _Line('آلية احتساب $title', _value(s.calculationMethod)),
        if (s.calculationMethod == 'مبلغ مقطوع')
          _Line('مبلغ $title', _amount(s.fixedAmount)),
        _Line('قراءة عداد $title', _optional(s.currentReading)),
      ],
    ];

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _Section(
      {required this.title, required this.icon, required this.children});
  @override
  Widget build(BuildContext context) => AppCard(
        padding: EdgeInsets.zero,
        shadows: const [],
        child: ExpansionTile(
          key: PageStorageKey('contract-review-$title'),
          initiallyExpanded: true,
          maintainState: true,
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
          iconColor: AppColors.primary,
          collapsedIconColor: context.ejarzTheme.muted,
          leading: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: AppColors.primary, size: 21)),
          title: Text(title,
              style: TextStyle(
                  color: context.ejarzTheme.text,
                  fontSize: context.sp(14),
                  fontWeight: FontWeight.w800)),
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) Divider(color: context.ejarzTheme.border, height: 1),
              children[i],
            ]
          ],
        ),
      );
}

class _Line extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;
  final bool paragraph;
  const _Line(this.label, this.value,
      {this.strong = false, this.paragraph = false});
  @override
  Widget build(BuildContext context) {
    final labelWidget = Text(label,
        style: TextStyle(
            color: context.ejarzTheme.muted,
            fontSize: context.sp(12),
            fontWeight: FontWeight.w600));
    Widget text({TextAlign? align}) => SelectableText(value,
        textAlign: align,
        style: TextStyle(
            color: strong ? AppColors.primary : context.ejarzTheme.text,
            fontSize: context.sp(13),
            height: 1.6,
            fontWeight: strong ? FontWeight.w900 : FontWeight.w700));
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: LayoutBuilder(builder: (context, constraints) {
          if (paragraph ||
              value.length > 35 ||
              (constraints.maxWidth < 400 && label.length > 23)) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [labelWidget, const SizedBox(height: 5), text()]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: labelWidget),
            const SizedBox(width: 16),
            Flexible(child: text(align: TextAlign.end))
          ]);
        }));
  }
}

class _Installment extends StatelessWidget {
  final InstallmentData installment;
  const _Installment(this.installment);
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
              child: Text('الدفعة ${installment.index}',
                  style: const TextStyle(fontWeight: FontWeight.w800))),
          Text(_amount(installment.amount),
              style: const TextStyle(
                  color: AppColors.primary, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 6),
        Text('تاريخ الاستحقاق: ${_value(installment.dueDate)}',
            style: TextStyle(
                color: context.ejarzTheme.muted, fontSize: context.sp(12))),
        if (installment.note.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(installment.note)
        ],
      ]));
}

class _Attachment extends StatelessWidget {
  final AttachmentData attachment;
  final bool requiredFile;
  const _Attachment(this.attachment, {required this.requiredFile});
  @override
  Widget build(BuildContext context) {
    final ready = _ready(attachment);
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(ready ? Icons.task_outlined : Icons.description_outlined,
                size: 22,
                color: ready ? AppColors.primary : context.ejarzTheme.muted),
            const SizedBox(width: 9),
            Expanded(
                child: Text(attachment.title,
                    style: const TextStyle(fontWeight: FontWeight.w800))),
            Text(requiredFile ? 'مطلوب' : 'اختياري',
                style: TextStyle(
                    color: context.ejarzTheme.muted, fontSize: context.sp(11))),
          ]),
          const SizedBox(height: 7),
          if (ready) ...[
            SelectableText(_value(attachment.fileName),
                style: TextStyle(fontSize: context.sp(12), height: 1.5)),
            if (attachment.sizeLabel.trim().isNotEmpty)
              Text(attachment.sizeLabel,
                  style: TextStyle(
                      color: context.ejarzTheme.muted,
                      fontSize: context.sp(11))),
            Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  key: ValueKey('review-open-${attachment.keyName}'),
                  onPressed: safeDocumentUri(attachment.downloadUrl) == null
                      ? null
                      : () => openDocument(context, attachment.downloadUrl),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('عرض الملف'),
                )),
          ] else
            Text(requiredFile ? 'لم يتم رفع الملف المطلوب' : 'لم يُضف مرفق',
                style: TextStyle(
                    color: requiredFile
                        ? AppColors.orange
                        : context.ejarzTheme.muted,
                    fontSize: context.sp(12))),
        ]));
  }
}

bool _ready(AttachmentData a) => a.uploaded && a.downloadUrl.trim().isNotEmpty;
String _value(String v) => v.trim().isEmpty ? 'غير محدد' : v;
String _optional(String v) => v.trim().isEmpty ? 'لم يُضف' : v;
String _yesNo(bool v) => v ? 'يوجد' : 'لا يوجد';
String _money(num v) => '${v.toStringAsFixed(2)} ريال';
String _amount(String v) =>
    _money((ContractCalculationEngine.money(v) ?? 0) / 100);
String _paymentMethod(PaymentMethod m) => switch (m) {
      PaymentMethod.mada => 'بطاقة مدى',
      PaymentMethod.applePay => 'Apple Pay',
      PaymentMethod.bankTransfer => 'تحويل بنكي',
    };
