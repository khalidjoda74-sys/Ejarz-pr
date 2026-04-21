# Debugging

## Inspect failed AI requests

- Review request assembly in `ai_chat_service.dart`
- Review gateway decisions in `ai_chat_gateway.dart`
- Review audit entries in `ai_audit_logger.dart`

## Add a new tool

1. Add it to `ai_tool_registry.dart`
2. Implement it in `ai_tool_executor.dart`
3. Add verification if it writes data
4. Add tests and eval coverage

## Add a new report

1. Add backend/report bridge support
2. Add a `reports.*` tool
3. Return structured totals and rows

## Troubleshoot wrong answers

- Check tool selection
- Check missing field detection
- Check disambiguation
- Check permission guard
- Check read-back verification
