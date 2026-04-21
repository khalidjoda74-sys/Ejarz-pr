# AI Chat Implementation Report

## Summary

تمت إعادة بناء مسار دردشة الذكاء الاصطناعي في دارفو ليعمل بطبقة تنفيذ آمنة ومعيارية بدل الاعتماد على استجابات حرة من النموذج. التنفيذ الحالي يضيف:

- سجل أدوات مركزي صارم `AiToolRegistry`
- طبقة تحقق من المخططات `AiSchemaValidator`
- طبقة صلاحيات `AiPermissionGuard`
- تدفق تأكيد معلق `AiConfirmationService`
- تنفيذ أدوات محكوم `AiToolExecutor`
- تحقق قراءة بعد التنفيذ `AiReadBackVerifier`
- سجلات تدقيق `AiAuditLogger`
- منسق استجابات منظم للواجهة `AiResponseFormatter`
- طبقة تنسيق وسياق للنموذج `AiContextProvider` و `AiOpenAiConfig`
- تحديث واجهة الدردشة لدعم بطاقات التأكيد، الاختيار بين المرشحين، والتقارير

## Files Changed

### Core orchestration

- `lib/ui/ai_chat/core/ai_chat_types.dart`
- `lib/ui/ai_chat/core/ai_schema_validator.dart`
- `lib/ui/ai_chat/core/ai_permission_guard.dart`
- `lib/ui/ai_chat/core/ai_confirmation_service.dart`
- `lib/ui/ai_chat/core/ai_audit_logger.dart`
- `lib/ui/ai_chat/core/ai_pending_action_store.dart`
- `lib/ui/ai_chat/core/ai_audit_log_store.dart`
- `lib/ui/ai_chat/core/ai_openai_config.dart`
- `lib/ui/ai_chat/core/ai_context_provider.dart`
- `lib/ui/ai_chat/core/ai_tool_registry.dart`
- `lib/ui/ai_chat/core/ai_tool_executor.dart`
- `lib/ui/ai_chat/core/ai_read_back_verifier.dart`
- `lib/ui/ai_chat/core/ai_response_formatter.dart`
- `lib/ui/ai_chat/core/ai_error_mapper.dart`
- `lib/ui/ai_chat/core/ai_chat_gateway.dart`

### Chat integration

- `lib/ui/ai_chat/ai_chat_service.dart`
- `lib/ui/ai_chat/ai_chat_screen.dart`
- `lib/ui/ai_chat/ai_chat_tools.dart`

### Tooling and generated context

- `tools/ai_generate_context.dart`
- `tools/ai_eval.dart`
- `ai-context/product_overview.md`
- `ai-context/modules.md`
- `ai-context/entities.md`
- `ai-context/permissions.md`
- `ai-context/business_rules.md`
- `ai-context/reports.md`
- `ai-context/workflows.md`
- `ai-context/tools_catalog.json`
- `ai-context/system_prompt.md`
- `ai-context/arabic_terms.md`
- `ai-context/examples.jsonl`

### Documentation

- `docs/ai-chat/00-repository-discovery.md`
- `docs/ai-chat/01-openai-config.md`
- `docs/ai-chat/02-debugging.md`
- `docs/ai-chat/03-adding-ai-tools.md`
- `docs/ai-chat/04-ai-safety-model.md`
- `docs/ai-chat/05-implementation-report.md`

### Tests and evals

- `test/ai_chat/ai_test_support.dart`
- `test/ai_chat/ai_tool_registry_test.dart`
- `test/ai_chat/ai_schema_validator_test.dart`
- `test/ai_chat/ai_permission_guard_test.dart`
- `test/ai_chat/ai_confirmation_service_test.dart`
- `test/ai_chat/ai_chat_gateway_test.dart`
- `test/ai_chat/ai_storage_fallback_test.dart`
- `evals/darfo-ai-ar.jsonl`

## Latest Hardening

- Added an execution-claim step before confirmed write actions so the same pending request is not executed twice across repeated confirmations or parallel sessions.
- Added hybrid `Hive` + `Firestore` synchronization for pending actions and AI audit logs, with local-first fallback when Firebase is unavailable.

- تم منع تعدد طلبات التأكيد الفعّالة داخل نفس المحادثة عبر إلغاء الطلب الأقدم عند إنشاء طلب أحدث.
- تم إعادة استخدام طلب التأكيد المطابق بدل إنشاء سجل مكرر لنفس العملية.
- تمت إضافة تنظيف دوري لسجلات `pending actions` وسجلات `audit logs` القديمة.
- تمت إضافة تسجيل صريح لحالة التحقق بعد التنفيذ داخل `AiAuditLogger`.
- تم توسيع `AiReadBackVerifier` ليتحقق من حقول أكثر في العقار والعميل والعقد وطلب الصيانة.
- تمت إضافة اختبارات لمسارات الإلغاء، وإعادة الاستخدام، وفشل التحقق بعد التنفيذ.

## New Architecture

مسار التنفيذ الحالي:

1. تصل رسالة المستخدم إلى الواجهة.
2. تبني الخدمة `system prompt` وسياق الأدوات المسموحة حسب الدور والنطاق.
3. تمر أي أداة مختارة إلى `AiChatGateway`.
4. يطبق الـ gateway:
   - حل الأداة من السجل
   - تحقق الصلاحيات
   - تحقق المخطط
   - إنشاء تأكيد معلق إذا كانت العملية عالية الخطورة أو كتابة
   - تنفيذ الأداة عبر `AiToolExecutor`
   - تسجيل التدقيق
   - التحقق من النتيجة عبر `AiReadBackVerifier`
   - إعادة استجابة منظمة للواجهة

## Tool List

تم تعريف أدوات معيارية لفئات:

- `app.*`
- `properties.*`
- `units.*`
- `owners.*`
- `tenants.*`
- `contracts.*`
- `invoices.*`
- `payments.*`
- `maintenance.*`
- `expenses.*`
- `reports.*`
- `notifications.*`

ويتم أيضًا تغليف الأدوات القديمة ضمن طبقة حماية عند الحاجة عبر `legacy.*`.

## Confirmation Flow

- أي عملية كتابة أو حذف أو تصدير أو عملية عالية الخطورة لا تنفذ مباشرة.
- ينشأ سجل معلق داخل `AiConfirmationService`.
- تحفظ الوسائط المعيارية و `idempotency key`.
- تعرض الواجهة بطاقة تأكيد منظمة بدل الاعتماد على نص حر.
- عند التأكيد يتم تنفيذ الوسائط المخزنة نفسها، وليس إعادة توليدها من نص المستخدم.
- عند التأكيد المكرر لنفس العملية يعاد استخدام النتيجة المنفذة بدل تكرار الإنشاء.

## Report Flow

- التقارير تمثل أدوات مستقلة من نوع `report`.
- لا يُفترض بالنموذج حساب الإجماليات من السجلات الخام.
- الاستجابة ترجع بهيكل تقرير منظم، ثم تلخصه الواجهة أو النص العربي.
- تم توثيق التهيئة والنماذج في `ai-context/reports.md` و `ai-context/tools_catalog.json`.

## Permission Flow

- الصلاحيات تُبنى على الخادم/التطبيق من الدور والنطاق الفعلي، وليس من نص النموذج.
- `AiPermissionGuard` يقرر السماح أو المنع لكل أداة.
- عند المنع يرجع الرد بصيغة عربية آمنة دون كشف تفاصيل حساسة.
- تم توثيق الصلاحيات في `ai-context/permissions.md`.

## Tests Added

- Duplicate-confirmation lock coverage was added for both `AiConfirmationService` and `AiChatGateway`.
- صلاحية وأمان سجل الأدوات
- صرامة مخططات JSON
- منع الكتابة بدون صلاحية
- إنشاء/انتهاء/تنفيذ طلبات التأكيد
- منع التكرار عبر `idempotency`
- مسار gateway للتأكيد والتنفيذ

## Eval Results

نتيجة `tools/ai_eval.dart` الأخيرة:

- `total_cases: 115`
- `passed: 115`
- `failed: 0`
- `tool_selection_pass: 115/115`
- `confirmation_pass: 115/115`
- `missing_fields_pass: 115/115`
- `permission_cases_pass: 5/5`
- `prompt_injection_pass: 5/5`
- `report_cases_pass: 15/15`

## Commands Run

- `C:\flutter\bin\cache\dart-sdk\bin\dart.exe tools\ai_generate_context.dart`
- `C:\flutter\bin\flutter.bat test test\ai_chat`
- `C:\flutter\bin\cache\dart-sdk\bin\dart.exe tools\ai_eval.dart`

## Known Limitations

- Hybrid storage now covers per-user `Hive` + `Firestore` sync, but it is not yet a dedicated server-managed workflow with centralized TTL policies.

- التخزين الحالي للتأكيدات والسجلات يعتمد على `Hive` داخل التطبيق، وليس جدول قاعدة بيانات منفصل على الخادم.
- جزء من التنفيذ ما زال يغلف أدوات قديمة موجودة أصلًا في التطبيق، لذلك التطوير القادم الأفضل هو نقل مزيد من المنطق الحرج إلى خدمات دومين صريحة.
- مجموعة الـ `evals` الحالية تقيس دقة التصنيف والسلامة والحقول الناقصة، لكنها لا تستبدل اختبارات تكامل كاملة مع OpenAI أو Firebase الإنتاجي.

## Exact Next Steps

1. Promote the hybrid storage layer to a server-managed workflow if stricter multi-device governance or retention controls become necessary.

1. نقل سجلات `pending actions` و `audit logs` إلى طبقة تخزين مركزية إذا أصبح الشات متعدد الأجهزة أو متعدد الجلسات.
2. إضافة اختبارات تكامل أوسع لمسارات العقود والمدفوعات والصيانة مع بيانات Hive حقيقية أكثر.
3. توسيع `AiReadBackVerifier` ليغطي مزيدًا من عمليات التحديث والحذف والتقارير المتقدمة.
4. ربط `tools/ai_eval.dart` بأمر CI ثابت عند توفر خط CI مخصص للذكاء الاصطناعي.
