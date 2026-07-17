# QA Checklist

## Auth

- [ ] تسجيل الدخول ببريد وكلمة مرور.
- [ ] رفض المستخدم غير الموجود في `adminUsers`.
- [ ] رفض الأدمن غير النشط.
- [ ] ظهور الصلاحيات حسب الدور.

## Responsive

- [ ] 390px: navigation سفلي والبطاقات تعمل.
- [ ] 430px: تفاصيل العقد تظهر accordion.
- [ ] 768px: sidebar قابل للطي.
- [ ] 1024px: الجداول واضحة.
- [ ] 1440px: كثافة المعلومات جيدة.

## Contracts

- [ ] عرض العقود.
- [ ] البحث والفلترة.
- [ ] تفاصيل العقد.
- [ ] تغيير الحالة.
- [ ] إضافة نقص.
- [ ] إضافة ملاحظة داخلية.
- [ ] رفع PDF نهائي.
- [ ] إنشاء notification و auditLog.

## Users

- [ ] عرض المستخدمين.
- [ ] بحث المستخدمين.
- [ ] تفاصيل المستخدم.
- [ ] حظر وفك حظر.
- [ ] عرض FCM tokens.

## Content

- [ ] قراءة `appContent/config`.
- [ ] تعديل الحقول.
- [ ] maintenanceMode confirmation.
- [ ] auditLog.

## Reports

- [ ] فلترة تاريخ.
- [ ] Charts.
- [ ] CSV export.

## Firebase

- [ ] env configured.
- [ ] Firestore rules تسمح للأدمن فقط.
- [ ] Storage final PDFs للأدمن فقط.
