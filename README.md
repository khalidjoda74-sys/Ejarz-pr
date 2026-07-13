# مجلسنا Flutter

تطبيق Flutter عربي RTL مرتبط بمشروع Firebase:

```text
majalisna-discussions-20260629
```

## الربط الحالي

- `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_storage`, `firebase_messaging`.
- قراءة المجالس من `councils`.
- قراءة التصنيفات من `categories`.
- قراءة التعليقات من `comments`.
- كتابة المستخدمين في `users`.
- التصويت والتعليقات والبلاغات عبر Cloud Functions.
- حفظ FCM token في `users/{uid}/fcmTokens` وأيضًا في `users/{uid}.fcmTokens`.
- دعم anonymous auth للمشاركة باسم مستعار.

## Collections الموحدة

```text
users
admins
roles
categories
councils
comments
reports
notifications
sponsorships
boosts
subscriptions
companyPolls
appSettings
auditLogs
analyticsDaily
```

## التشغيل

```bash
flutter pub get
flutter run
```

## التحقق

```bash
dart analyze
cmd /c npm --prefix functions run build
```

ملاحظة: في هذه البيئة قد يظهر `PathAccessException` بعد `dart analyze` بسبب رفض Windows كتابة ملف telemetry في AppData. نتيجة التحليل قبل ذلك كانت `No issues found!`.

## النشر

```bash
flutter build web
firebase deploy --only hosting
firebase deploy --only firestore:rules,firestore:indexes,storage
firebase deploy --only functions
```

## لوحة التحكم

تمت إضافة لوحة Next.js داخل:

```text
majlisna_admin_dashboard/
```

اللوحة تستخدم نفس Firebase Project ونفس collections. راجع `majlisna_admin_dashboard/README.md` لتعليمات env، إنشاء الأدمن، seed، وتشغيل اللوحة.
