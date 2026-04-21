import 'ai_chat_types.dart';

class AiResponseFormatter {
  const AiResponseFormatter();

  AiGatewayResponse plain(String text) {
    return AiGatewayResponse(
      type: AiAssistantResponseType.plainAnswer,
      text: text,
    );
  }

  AiGatewayResponse clarification(
    String text, {
    List<dynamic> missingFields = const <dynamic>[],
  }) {
    return AiGatewayResponse(
      type: AiAssistantResponseType.clarificationQuestion,
      text: text,
      payload: <String, dynamic>{
        'missing_fields': missingFields,
      },
    );
  }

  AiGatewayResponse disambiguation(
    String text, {
    List<dynamic> candidates = const <dynamic>[],
  }) {
    return AiGatewayResponse(
      type: AiAssistantResponseType.disambiguation,
      text: text,
      payload: <String, dynamic>{
        'candidates': candidates,
      },
    );
  }

  AiGatewayResponse confirmation({
    required String text,
    required String pendingActionId,
    required Map<String, dynamic> preview,
    required String toolName,
  }) {
    return AiGatewayResponse(
      type: AiAssistantResponseType.confirmationRequired,
      text: text,
      pendingActionId: pendingActionId,
      toolName: toolName,
      payload: <String, dynamic>{
        'preview': preview,
      },
    );
  }

  AiGatewayResponse permissionDenied(String text) {
    return AiGatewayResponse(
      type: AiAssistantResponseType.permissionDenied,
      text: text,
    );
  }

  AiGatewayResponse executionFailed(
    String text, {
    Map<String, dynamic> payload = const <String, dynamic>{},
  }) {
    return AiGatewayResponse(
      type: AiAssistantResponseType.executionFailed,
      text: text,
      payload: payload,
    );
  }

  AiGatewayResponse verificationFailed(
    String text, {
    Map<String, dynamic> payload = const <String, dynamic>{},
  }) {
    return AiGatewayResponse(
      type: AiAssistantResponseType.verificationFailed,
      text: text,
      payload: payload,
    );
  }

  AiGatewayResponse report(
    String text, {
    required Map<String, dynamic> report,
    String? toolHistoryResult,
  }) {
    return AiGatewayResponse(
      type: AiAssistantResponseType.reportSummary,
      text: text,
      payload: report,
      toolHistoryResult: toolHistoryResult,
    );
  }

  AiGatewayResponse toolResult(
    String text, {
    Map<String, dynamic> payload = const <String, dynamic>{},
    String? toolHistoryResult,
  }) {
    return AiGatewayResponse(
      type: AiAssistantResponseType.toolResult,
      text: text,
      payload: payload,
      toolHistoryResult: toolHistoryResult,
    );
  }
}
