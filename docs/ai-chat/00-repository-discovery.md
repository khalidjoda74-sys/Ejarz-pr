# Repository Discovery

## Detected stack

- Flutter / Dart application
- Hive local storage
- Firebase Auth / Firestore / Storage / Functions
- Direct client OpenAI HTTP integration

## Existing AI chat flow

1. `lib/ui/ai_chat/ai_chat_screen.dart`
2. `lib/ui/ai_chat/ai_chat_service.dart`
3. `lib/ui/ai_chat/ai_chat_executor.dart`
4. `lib/ui/ai_chat/core/*`

## Problems found in current AI flow

- Legacy and new tool paths coexist.
- Confirmation historically depended on UI flow.
- Tool strictness and permission checks needed centralization.
- Read-back verification needed a mandatory gateway stage.

## Existing models/entities relevant to property management

- `Property`
- `Tenant`
- `Contract`
- `Invoice`
- `MaintenanceRequest`

## Existing permissions

- UI role resolver in `ai_chat_permissions.dart`
- AI permission guard in `ai_permission_guard.dart`

## Existing report endpoints/services

- `ai_chat_reports_bridge.dart`
- `comprehensive_reports_service.dart`

## Existing risks

- OpenAI call path is still client-side in this repository.
- Some domain models live inside large UI files.
- Legacy tool aliases remain for compatibility.

## Exact files that need to change

- `lib/ui/ai_chat/ai_chat_screen.dart`
- `lib/ui/ai_chat/ai_chat_service.dart`
- `lib/ui/ai_chat/ai_chat_executor.dart`
- `lib/ui/ai_chat/ai_chat_tools.dart`
- `lib/ui/ai_chat/ai_chat_permissions.dart`
- `lib/ui/ai_chat/core/*`
- `lib/data/services/ai_chat_reports_bridge.dart`
- `tools/ai_generate_context.dart`
- `tools/ai_eval.dart`
- `test/ai_chat/*`

## Discovery counts

- tools detected: 43
- modules detected: 14
- env vars detected: 8
