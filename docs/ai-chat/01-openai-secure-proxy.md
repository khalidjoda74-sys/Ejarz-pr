# إعداد OpenAI الآمن في دارفو

## القاعدة الأساسية

لا يجب وضع مفتاح OpenAI داخل تطبيق Flutter في الإنتاج.

المسار الآمن:

```text
Flutter
→ Backend / Cloud Function
→ تحقق Auth + صلاحيات + Tenant Scope
→ OpenAI
→ تنفيذ الأدوات الآمنة
→ الرد للعميل
```

## متغيرات التشغيل

```bash
--dart-define=DARFO_AI_PROXY_URL=https://YOUR_BACKEND/ai/chat
--dart-define=OPENAI_MODEL_FAST=gpt-5-mini
--dart-define=OPENAI_MODEL_DEFAULT=gpt-5-mini
--dart-define=OPENAI_MODEL_REASONING=gpt-5
--dart-define=OPENAI_MODEL_REPORTS=gpt-5
--dart-define=OPENAI_TEMPERATURE=0.1
--dart-define=OPENAI_MAX_TOOL_STEPS=1
--dart-define=OPENAI_TIMEOUT_MS=30000
```

## وضع التطوير فقط

يمكن تفعيل الاتصال المباشر مؤقتًا في بيئة محلية فقط:

```bash
--dart-define=ALLOW_CLIENT_OPENAI_DIRECT=true
```

لا تستخدم هذا الخيار في نسخة المتجر أو الإنتاج.
