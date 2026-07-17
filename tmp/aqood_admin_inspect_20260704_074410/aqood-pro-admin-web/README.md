# Aqood Pro Command Center

لوحة تحكم ويب عربية RTL لتطبيق **عقود برو**، مبنية بـ React + Vite + TypeScript + Firebase Web SDK.

## التشغيل المحلي

```bash
cd aqood-pro-admin-web
cp .env.example .env.local
npm install
npm run dev
```

املأ ملف `.env.local` بقيم Firebase Web App من مشروع Firebase `ejarz-pro-20260624`.

## البناء

```bash
npm run build
```

## الدخول

الدخول يتم عبر Firebase Auth. بعد تسجيل الدخول يجب أن توجد وثيقة:

```txt
adminUsers/{uid}
```

وفيها:

```json
{ "active": true, "role": "owner", "permissions": ["contracts.read"] }
```

## النشر على Firebase Hosting

```bash
npm run build
firebase use ejarz-pro-20260624
firebase deploy --only hosting
```

## ملاحظات مهمة

- لا يحتوي المشروع على Firebase Admin SDK.
- لا يحتوي على Service Account أو مفاتيح خاصة.
- كل Firebase config عبر env فقط.
- يوجد ملفان مقترحان للقواعد: `firestore.rules.example` و `storage.rules.example`.
- كل الصفحات تقرأ من Firebase الحقيقي وتعرض empty/error/loading states عند عدم وجود بيانات.
