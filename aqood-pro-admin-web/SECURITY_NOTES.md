# Security Notes

## المبادئ الأمنية

1. لا توجد مفاتيح سرية داخل الواجهة.
2. لا يوجد Firebase Admin SDK داخل المتصفح.
3. بوابة الدخول تعتمد على Firebase Auth ثم `adminUsers/{uid}.active === true`.
4. الواجهة لا تكفي وحدها للأمان؛ يجب نشر قواعد Firestore وStorage المناسبة.
5. العمليات الحساسة تسجل في `auditLogs`.
6. لا يوجد impersonation للمستخدمين.
7. لا يوجد حذف نهائي للأدمن؛ يتم التعطيل فقط.

## الحقول الجديدة غير الكاسرة

اللوحة قد تضيف حقولًا اختيارية مثل:

- `assignedAdminUid`
- `assignedAdminName`
- `finalPdfUrl`
- `finalPdfFileName`
- `missingItems`
- `internalNotes`
- `customerNote`
- `blocked`
- `blockReason`

كلها اختيارية ولا تكسر تطبيق Flutter إذا كان لا يستخدمها.

## قواعد Firebase

راجع:

- `firestore.rules.example`
- `storage.rules.example`

ولا تنشرها مباشرة قبل مطابقتها مع قواعد التطبيق الحالي إذا كان التطبيق منشورًا.
