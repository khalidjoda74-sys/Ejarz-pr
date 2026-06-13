# AI Chat Implementation Report

## Summary

ØªÙ…Øª Ø¥Ø¹Ø§Ø¯Ø© Ø¨Ù†Ø§Ø¡ Ù…Ø³Ø§Ø± Ø¯Ø±Ø¯Ø´Ø© Ø§Ù„Ø°ÙƒØ§Ø¡ Ø§Ù„Ø§ØµØ·Ù†Ø§Ø¹ÙŠ ÙÙŠ Ejarz Pro Ù„ÙŠØ¹Ù…Ù„ Ø¨Ø·Ø¨Ù‚Ø© ØªÙ†ÙÙŠØ° Ø¢Ù…Ù†Ø© ÙˆÙ…Ø¹ÙŠØ§Ø±ÙŠØ© Ø¨Ø¯Ù„ Ø§Ù„Ø§Ø¹ØªÙ…Ø§Ø¯ Ø¹Ù„Ù‰ Ø§Ø³ØªØ¬Ø§Ø¨Ø§Øª Ø­Ø±Ø© Ù…Ù† Ø§Ù„Ù†Ù…ÙˆØ°Ø¬. Ø§Ù„ØªÙ†ÙÙŠØ° Ø§Ù„Ø­Ø§Ù„ÙŠ ÙŠØ¶ÙŠÙ:

- Ø³Ø¬Ù„ Ø£Ø¯ÙˆØ§Øª Ù…Ø±ÙƒØ²ÙŠ ØµØ§Ø±Ù… `AiToolRegistry`
- Ø·Ø¨Ù‚Ø© ØªØ­Ù‚Ù‚ Ù…Ù† Ø§Ù„Ù…Ø®Ø·Ø·Ø§Øª `AiSchemaValidator`
- Ø·Ø¨Ù‚Ø© ØµÙ„Ø§Ø­ÙŠØ§Øª `AiPermissionGuard`
- ØªØ¯ÙÙ‚ ØªØ£ÙƒÙŠØ¯ Ù…Ø¹Ù„Ù‚ `AiConfirmationService`
- ØªÙ†ÙÙŠØ° Ø£Ø¯ÙˆØ§Øª Ù…Ø­ÙƒÙˆÙ… `AiToolExecutor`
- ØªØ­Ù‚Ù‚ Ù‚Ø±Ø§Ø¡Ø© Ø¨Ø¹Ø¯ Ø§Ù„ØªÙ†ÙÙŠØ° `AiReadBackVerifier`
- Ø³Ø¬Ù„Ø§Øª ØªØ¯Ù‚ÙŠÙ‚ `AiAuditLogger`
- Ù…Ù†Ø³Ù‚ Ø§Ø³ØªØ¬Ø§Ø¨Ø§Øª Ù…Ù†Ø¸Ù… Ù„Ù„ÙˆØ§Ø¬Ù‡Ø© `AiResponseFormatter`
- Ø·Ø¨Ù‚Ø© ØªÙ†Ø³ÙŠÙ‚ ÙˆØ³ÙŠØ§Ù‚ Ù„Ù„Ù†Ù…ÙˆØ°Ø¬ `AiContextProvider` Ùˆ `AiOpenAiConfig`
- ØªØ­Ø¯ÙŠØ« ÙˆØ§Ø¬Ù‡Ø© Ø§Ù„Ø¯Ø±Ø¯Ø´Ø© Ù„Ø¯Ø¹Ù… Ø¨Ø·Ø§Ù‚Ø§Øª Ø§Ù„ØªØ£ÙƒÙŠØ¯ØŒ Ø§Ù„Ø§Ø®ØªÙŠØ§Ø± Ø¨ÙŠÙ† Ø§Ù„Ù…Ø±Ø´Ø­ÙŠÙ†ØŒ ÙˆØ§Ù„ØªÙ‚Ø§Ø±ÙŠØ±

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
- `evals/ejarz-pro-ai-ar.jsonl`

## Latest Hardening

- Added an execution-claim step before confirmed write actions so the same pending request is not executed twice across repeated confirmations or parallel sessions.
- Added hybrid `Hive` + `Firestore` synchronization for pending actions and AI audit logs, with local-first fallback when Firebase is unavailable.

- ØªÙ… Ù…Ù†Ø¹ ØªØ¹Ø¯Ø¯ Ø·Ù„Ø¨Ø§Øª Ø§Ù„ØªØ£ÙƒÙŠØ¯ Ø§Ù„ÙØ¹Ù‘Ø§Ù„Ø© Ø¯Ø§Ø®Ù„ Ù†ÙØ³ Ø§Ù„Ù…Ø­Ø§Ø¯Ø«Ø© Ø¹Ø¨Ø± Ø¥Ù„ØºØ§Ø¡ Ø§Ù„Ø·Ù„Ø¨ Ø§Ù„Ø£Ù‚Ø¯Ù… Ø¹Ù†Ø¯ Ø¥Ù†Ø´Ø§Ø¡ Ø·Ù„Ø¨ Ø£Ø­Ø¯Ø«.
- ØªÙ… Ø¥Ø¹Ø§Ø¯Ø© Ø§Ø³ØªØ®Ø¯Ø§Ù… Ø·Ù„Ø¨ Ø§Ù„ØªØ£ÙƒÙŠØ¯ Ø§Ù„Ù…Ø·Ø§Ø¨Ù‚ Ø¨Ø¯Ù„ Ø¥Ù†Ø´Ø§Ø¡ Ø³Ø¬Ù„ Ù…ÙƒØ±Ø± Ù„Ù†ÙØ³ Ø§Ù„Ø¹Ù…Ù„ÙŠØ©.
- ØªÙ…Øª Ø¥Ø¶Ø§ÙØ© ØªÙ†Ø¸ÙŠÙ Ø¯ÙˆØ±ÙŠ Ù„Ø³Ø¬Ù„Ø§Øª `pending actions` ÙˆØ³Ø¬Ù„Ø§Øª `audit logs` Ø§Ù„Ù‚Ø¯ÙŠÙ…Ø©.
- ØªÙ…Øª Ø¥Ø¶Ø§ÙØ© ØªØ³Ø¬ÙŠÙ„ ØµØ±ÙŠØ­ Ù„Ø­Ø§Ù„Ø© Ø§Ù„ØªØ­Ù‚Ù‚ Ø¨Ø¹Ø¯ Ø§Ù„ØªÙ†ÙÙŠØ° Ø¯Ø§Ø®Ù„ `AiAuditLogger`.
- ØªÙ… ØªÙˆØ³ÙŠØ¹ `AiReadBackVerifier` Ù„ÙŠØªØ­Ù‚Ù‚ Ù…Ù† Ø­Ù‚ÙˆÙ„ Ø£ÙƒØ«Ø± ÙÙŠ Ø§Ù„Ø¹Ù‚Ø§Ø± ÙˆØ§Ù„Ø¹Ù…ÙŠÙ„ ÙˆØ§Ù„Ø¹Ù‚Ø¯ ÙˆØ·Ù„Ø¨ Ø§Ù„ØµÙŠØ§Ù†Ø©.
- ØªÙ…Øª Ø¥Ø¶Ø§ÙØ© Ø§Ø®ØªØ¨Ø§Ø±Ø§Øª Ù„Ù…Ø³Ø§Ø±Ø§Øª Ø§Ù„Ø¥Ù„ØºØ§Ø¡ØŒ ÙˆØ¥Ø¹Ø§Ø¯Ø© Ø§Ù„Ø§Ø³ØªØ®Ø¯Ø§Ù…ØŒ ÙˆÙØ´Ù„ Ø§Ù„ØªØ­Ù‚Ù‚ Ø¨Ø¹Ø¯ Ø§Ù„ØªÙ†ÙÙŠØ°.

## New Architecture

Ù…Ø³Ø§Ø± Ø§Ù„ØªÙ†ÙÙŠØ° Ø§Ù„Ø­Ø§Ù„ÙŠ:

1. ØªØµÙ„ Ø±Ø³Ø§Ù„Ø© Ø§Ù„Ù…Ø³ØªØ®Ø¯Ù… Ø¥Ù„Ù‰ Ø§Ù„ÙˆØ§Ø¬Ù‡Ø©.
2. ØªØ¨Ù†ÙŠ Ø§Ù„Ø®Ø¯Ù…Ø© `system prompt` ÙˆØ³ÙŠØ§Ù‚ Ø§Ù„Ø£Ø¯ÙˆØ§Øª Ø§Ù„Ù…Ø³Ù…ÙˆØ­Ø© Ø­Ø³Ø¨ Ø§Ù„Ø¯ÙˆØ± ÙˆØ§Ù„Ù†Ø·Ø§Ù‚.
3. ØªÙ…Ø± Ø£ÙŠ Ø£Ø¯Ø§Ø© Ù…Ø®ØªØ§Ø±Ø© Ø¥Ù„Ù‰ `AiChatGateway`.
4. ÙŠØ·Ø¨Ù‚ Ø§Ù„Ù€ gateway:
   - Ø­Ù„ Ø§Ù„Ø£Ø¯Ø§Ø© Ù…Ù† Ø§Ù„Ø³Ø¬Ù„
   - ØªØ­Ù‚Ù‚ Ø§Ù„ØµÙ„Ø§Ø­ÙŠØ§Øª
   - ØªØ­Ù‚Ù‚ Ø§Ù„Ù…Ø®Ø·Ø·
   - Ø¥Ù†Ø´Ø§Ø¡ ØªØ£ÙƒÙŠØ¯ Ù…Ø¹Ù„Ù‚ Ø¥Ø°Ø§ ÙƒØ§Ù†Øª Ø§Ù„Ø¹Ù…Ù„ÙŠØ© Ø¹Ø§Ù„ÙŠØ© Ø§Ù„Ø®Ø·ÙˆØ±Ø© Ø£Ùˆ ÙƒØªØ§Ø¨Ø©
   - ØªÙ†ÙÙŠØ° Ø§Ù„Ø£Ø¯Ø§Ø© Ø¹Ø¨Ø± `AiToolExecutor`
   - ØªØ³Ø¬ÙŠÙ„ Ø§Ù„ØªØ¯Ù‚ÙŠÙ‚
   - Ø§Ù„ØªØ­Ù‚Ù‚ Ù…Ù† Ø§Ù„Ù†ØªÙŠØ¬Ø© Ø¹Ø¨Ø± `AiReadBackVerifier`
   - Ø¥Ø¹Ø§Ø¯Ø© Ø§Ø³ØªØ¬Ø§Ø¨Ø© Ù…Ù†Ø¸Ù…Ø© Ù„Ù„ÙˆØ§Ø¬Ù‡Ø©

## Tool List

ØªÙ… ØªØ¹Ø±ÙŠÙ Ø£Ø¯ÙˆØ§Øª Ù…Ø¹ÙŠØ§Ø±ÙŠØ© Ù„ÙØ¦Ø§Øª:

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

ÙˆÙŠØªÙ… Ø£ÙŠØ¶Ù‹Ø§ ØªØºÙ„ÙŠÙ Ø§Ù„Ø£Ø¯ÙˆØ§Øª Ø§Ù„Ù‚Ø¯ÙŠÙ…Ø© Ø¶Ù…Ù† Ø·Ø¨Ù‚Ø© Ø­Ù…Ø§ÙŠØ© Ø¹Ù†Ø¯ Ø§Ù„Ø­Ø§Ø¬Ø© Ø¹Ø¨Ø± `legacy.*`.

## Confirmation Flow

- Ø£ÙŠ Ø¹Ù…Ù„ÙŠØ© ÙƒØªØ§Ø¨Ø© Ø£Ùˆ Ø­Ø°Ù Ø£Ùˆ ØªØµØ¯ÙŠØ± Ø£Ùˆ Ø¹Ù…Ù„ÙŠØ© Ø¹Ø§Ù„ÙŠØ© Ø§Ù„Ø®Ø·ÙˆØ±Ø© Ù„Ø§ ØªÙ†ÙØ° Ù…Ø¨Ø§Ø´Ø±Ø©.
- ÙŠÙ†Ø´Ø£ Ø³Ø¬Ù„ Ù…Ø¹Ù„Ù‚ Ø¯Ø§Ø®Ù„ `AiConfirmationService`.
- ØªØ­ÙØ¸ Ø§Ù„ÙˆØ³Ø§Ø¦Ø· Ø§Ù„Ù…Ø¹ÙŠØ§Ø±ÙŠØ© Ùˆ `idempotency key`.
- ØªØ¹Ø±Ø¶ Ø§Ù„ÙˆØ§Ø¬Ù‡Ø© Ø¨Ø·Ø§Ù‚Ø© ØªØ£ÙƒÙŠØ¯ Ù…Ù†Ø¸Ù…Ø© Ø¨Ø¯Ù„ Ø§Ù„Ø§Ø¹ØªÙ…Ø§Ø¯ Ø¹Ù„Ù‰ Ù†Øµ Ø­Ø±.
- Ø¹Ù†Ø¯ Ø§Ù„ØªØ£ÙƒÙŠØ¯ ÙŠØªÙ… ØªÙ†ÙÙŠØ° Ø§Ù„ÙˆØ³Ø§Ø¦Ø· Ø§Ù„Ù…Ø®Ø²Ù†Ø© Ù†ÙØ³Ù‡Ø§ØŒ ÙˆÙ„ÙŠØ³ Ø¥Ø¹Ø§Ø¯Ø© ØªÙˆÙ„ÙŠØ¯Ù‡Ø§ Ù…Ù† Ù†Øµ Ø§Ù„Ù…Ø³ØªØ®Ø¯Ù….
- Ø¹Ù†Ø¯ Ø§Ù„ØªØ£ÙƒÙŠØ¯ Ø§Ù„Ù…ÙƒØ±Ø± Ù„Ù†ÙØ³ Ø§Ù„Ø¹Ù…Ù„ÙŠØ© ÙŠØ¹Ø§Ø¯ Ø§Ø³ØªØ®Ø¯Ø§Ù… Ø§Ù„Ù†ØªÙŠØ¬Ø© Ø§Ù„Ù…Ù†ÙØ°Ø© Ø¨Ø¯Ù„ ØªÙƒØ±Ø§Ø± Ø§Ù„Ø¥Ù†Ø´Ø§Ø¡.

## Report Flow

- Ø§Ù„ØªÙ‚Ø§Ø±ÙŠØ± ØªÙ…Ø«Ù„ Ø£Ø¯ÙˆØ§Øª Ù…Ø³ØªÙ‚Ù„Ø© Ù…Ù† Ù†ÙˆØ¹ `report`.
- Ù„Ø§ ÙŠÙÙØªØ±Ø¶ Ø¨Ø§Ù„Ù†Ù…ÙˆØ°Ø¬ Ø­Ø³Ø§Ø¨ Ø§Ù„Ø¥Ø¬Ù…Ø§Ù„ÙŠØ§Øª Ù…Ù† Ø§Ù„Ø³Ø¬Ù„Ø§Øª Ø§Ù„Ø®Ø§Ù….
- Ø§Ù„Ø§Ø³ØªØ¬Ø§Ø¨Ø© ØªØ±Ø¬Ø¹ Ø¨Ù‡ÙŠÙƒÙ„ ØªÙ‚Ø±ÙŠØ± Ù…Ù†Ø¸Ù…ØŒ Ø«Ù… ØªÙ„Ø®ØµÙ‡ Ø§Ù„ÙˆØ§Ø¬Ù‡Ø© Ø£Ùˆ Ø§Ù„Ù†Øµ Ø§Ù„Ø¹Ø±Ø¨ÙŠ.
- ØªÙ… ØªÙˆØ«ÙŠÙ‚ Ø§Ù„ØªÙ‡ÙŠØ¦Ø© ÙˆØ§Ù„Ù†Ù…Ø§Ø°Ø¬ ÙÙŠ `ai-context/reports.md` Ùˆ `ai-context/tools_catalog.json`.

## Permission Flow

- Ø§Ù„ØµÙ„Ø§Ø­ÙŠØ§Øª ØªÙØ¨Ù†Ù‰ Ø¹Ù„Ù‰ Ø§Ù„Ø®Ø§Ø¯Ù…/Ø§Ù„ØªØ·Ø¨ÙŠÙ‚ Ù…Ù† Ø§Ù„Ø¯ÙˆØ± ÙˆØ§Ù„Ù†Ø·Ø§Ù‚ Ø§Ù„ÙØ¹Ù„ÙŠØŒ ÙˆÙ„ÙŠØ³ Ù…Ù† Ù†Øµ Ø§Ù„Ù†Ù…ÙˆØ°Ø¬.
- `AiPermissionGuard` ÙŠÙ‚Ø±Ø± Ø§Ù„Ø³Ù…Ø§Ø­ Ø£Ùˆ Ø§Ù„Ù…Ù†Ø¹ Ù„ÙƒÙ„ Ø£Ø¯Ø§Ø©.
- Ø¹Ù†Ø¯ Ø§Ù„Ù…Ù†Ø¹ ÙŠØ±Ø¬Ø¹ Ø§Ù„Ø±Ø¯ Ø¨ØµÙŠØºØ© Ø¹Ø±Ø¨ÙŠØ© Ø¢Ù…Ù†Ø© Ø¯ÙˆÙ† ÙƒØ´Ù ØªÙØ§ØµÙŠÙ„ Ø­Ø³Ø§Ø³Ø©.
- ØªÙ… ØªÙˆØ«ÙŠÙ‚ Ø§Ù„ØµÙ„Ø§Ø­ÙŠØ§Øª ÙÙŠ `ai-context/permissions.md`.

## Tests Added

- Duplicate-confirmation lock coverage was added for both `AiConfirmationService` and `AiChatGateway`.
- ØµÙ„Ø§Ø­ÙŠØ© ÙˆØ£Ù…Ø§Ù† Ø³Ø¬Ù„ Ø§Ù„Ø£Ø¯ÙˆØ§Øª
- ØµØ±Ø§Ù…Ø© Ù…Ø®Ø·Ø·Ø§Øª JSON
- Ù…Ù†Ø¹ Ø§Ù„ÙƒØªØ§Ø¨Ø© Ø¨Ø¯ÙˆÙ† ØµÙ„Ø§Ø­ÙŠØ©
- Ø¥Ù†Ø´Ø§Ø¡/Ø§Ù†ØªÙ‡Ø§Ø¡/ØªÙ†ÙÙŠØ° Ø·Ù„Ø¨Ø§Øª Ø§Ù„ØªØ£ÙƒÙŠØ¯
- Ù…Ù†Ø¹ Ø§Ù„ØªÙƒØ±Ø§Ø± Ø¹Ø¨Ø± `idempotency`
- Ù…Ø³Ø§Ø± gateway Ù„Ù„ØªØ£ÙƒÙŠØ¯ ÙˆØ§Ù„ØªÙ†ÙÙŠØ°

## Eval Results

Ù†ØªÙŠØ¬Ø© `tools/ai_eval.dart` Ø§Ù„Ø£Ø®ÙŠØ±Ø©:

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

- Ø§Ù„ØªØ®Ø²ÙŠÙ† Ø§Ù„Ø­Ø§Ù„ÙŠ Ù„Ù„ØªØ£ÙƒÙŠØ¯Ø§Øª ÙˆØ§Ù„Ø³Ø¬Ù„Ø§Øª ÙŠØ¹ØªÙ…Ø¯ Ø¹Ù„Ù‰ `Hive` Ø¯Ø§Ø®Ù„ Ø§Ù„ØªØ·Ø¨ÙŠÙ‚ØŒ ÙˆÙ„ÙŠØ³ Ø¬Ø¯ÙˆÙ„ Ù‚Ø§Ø¹Ø¯Ø© Ø¨ÙŠØ§Ù†Ø§Øª Ù…Ù†ÙØµÙ„ Ø¹Ù„Ù‰ Ø§Ù„Ø®Ø§Ø¯Ù….
- Ø¬Ø²Ø¡ Ù…Ù† Ø§Ù„ØªÙ†ÙÙŠØ° Ù…Ø§ Ø²Ø§Ù„ ÙŠØºÙ„Ù Ø£Ø¯ÙˆØ§Øª Ù‚Ø¯ÙŠÙ…Ø© Ù…ÙˆØ¬ÙˆØ¯Ø© Ø£ØµÙ„Ù‹Ø§ ÙÙŠ Ø§Ù„ØªØ·Ø¨ÙŠÙ‚ØŒ Ù„Ø°Ù„Ùƒ Ø§Ù„ØªØ·ÙˆÙŠØ± Ø§Ù„Ù‚Ø§Ø¯Ù… Ø§Ù„Ø£ÙØ¶Ù„ Ù‡Ùˆ Ù†Ù‚Ù„ Ù…Ø²ÙŠØ¯ Ù…Ù† Ø§Ù„Ù…Ù†Ø·Ù‚ Ø§Ù„Ø­Ø±Ø¬ Ø¥Ù„Ù‰ Ø®Ø¯Ù…Ø§Øª Ø¯ÙˆÙ…ÙŠÙ† ØµØ±ÙŠØ­Ø©.
- Ù…Ø¬Ù…ÙˆØ¹Ø© Ø§Ù„Ù€ `evals` Ø§Ù„Ø­Ø§Ù„ÙŠØ© ØªÙ‚ÙŠØ³ Ø¯Ù‚Ø© Ø§Ù„ØªØµÙ†ÙŠÙ ÙˆØ§Ù„Ø³Ù„Ø§Ù…Ø© ÙˆØ§Ù„Ø­Ù‚ÙˆÙ„ Ø§Ù„Ù†Ø§Ù‚ØµØ©ØŒ Ù„ÙƒÙ†Ù‡Ø§ Ù„Ø§ ØªØ³ØªØ¨Ø¯Ù„ Ø§Ø®ØªØ¨Ø§Ø±Ø§Øª ØªÙƒØ§Ù…Ù„ ÙƒØ§Ù…Ù„Ø© Ù…Ø¹ OpenAI Ø£Ùˆ Firebase Ø§Ù„Ø¥Ù†ØªØ§Ø¬ÙŠ.

## Exact Next Steps

1. Promote the hybrid storage layer to a server-managed workflow if stricter multi-device governance or retention controls become necessary.

1. Ù†Ù‚Ù„ Ø³Ø¬Ù„Ø§Øª `pending actions` Ùˆ `audit logs` Ø¥Ù„Ù‰ Ø·Ø¨Ù‚Ø© ØªØ®Ø²ÙŠÙ† Ù…Ø±ÙƒØ²ÙŠØ© Ø¥Ø°Ø§ Ø£ØµØ¨Ø­ Ø§Ù„Ø´Ø§Øª Ù…ØªØ¹Ø¯Ø¯ Ø§Ù„Ø£Ø¬Ù‡Ø²Ø© Ø£Ùˆ Ù…ØªØ¹Ø¯Ø¯ Ø§Ù„Ø¬Ù„Ø³Ø§Øª.
2. Ø¥Ø¶Ø§ÙØ© Ø§Ø®ØªØ¨Ø§Ø±Ø§Øª ØªÙƒØ§Ù…Ù„ Ø£ÙˆØ³Ø¹ Ù„Ù…Ø³Ø§Ø±Ø§Øª Ø§Ù„Ø¹Ù‚ÙˆØ¯ ÙˆØ§Ù„Ù…Ø¯ÙÙˆØ¹Ø§Øª ÙˆØ§Ù„ØµÙŠØ§Ù†Ø© Ù…Ø¹ Ø¨ÙŠØ§Ù†Ø§Øª Hive Ø­Ù‚ÙŠÙ‚ÙŠØ© Ø£ÙƒØ«Ø±.
3. ØªÙˆØ³ÙŠØ¹ `AiReadBackVerifier` Ù„ÙŠØºØ·ÙŠ Ù…Ø²ÙŠØ¯Ù‹Ø§ Ù…Ù† Ø¹Ù…Ù„ÙŠØ§Øª Ø§Ù„ØªØ­Ø¯ÙŠØ« ÙˆØ§Ù„Ø­Ø°Ù ÙˆØ§Ù„ØªÙ‚Ø§Ø±ÙŠØ± Ø§Ù„Ù…ØªÙ‚Ø¯Ù…Ø©.
4. Ø±Ø¨Ø· `tools/ai_eval.dart` Ø¨Ø£Ù…Ø± CI Ø«Ø§Ø¨Øª Ø¹Ù†Ø¯ ØªÙˆÙØ± Ø®Ø· CI Ù…Ø®ØµØµ Ù„Ù„Ø°ÙƒØ§Ø¡ Ø§Ù„Ø§ØµØ·Ù†Ø§Ø¹ÙŠ.
