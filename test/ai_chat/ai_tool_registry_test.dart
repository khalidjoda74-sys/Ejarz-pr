import 'package:darvoo/ui/ai_chat/core/ai_tool_registry.dart';
import 'package:darvoo/ui/ai_chat/core/ai_chat_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tool catalog schemas are strict objects', () {
    for (final definition in AiToolRegistry.catalog) {
      final schema = definition.inputSchema;
      expect(schema['type'], 'object', reason: definition.name);
      expect(schema['additionalProperties'], false, reason: definition.name);

      final properties =
          Map<String, dynamic>.from(schema['properties'] as Map? ?? const <String, dynamic>{});
      final required = (schema['required'] as List? ?? const <dynamic>[])
          .map((item) => item.toString())
          .toSet();
      expect(required, equals(properties.keys.toSet()), reason: definition.name);
    }
  });

  test('critical operational tools require confirmation', () {
    final contractsCreate = AiToolRegistry.resolve('contracts.create');
    final paymentsCreate = AiToolRegistry.resolve('payments.create');
    final maintenanceCreate = AiToolRegistry.resolve('maintenance.create_ticket');

    expect(contractsCreate.operationType, AiToolOperationType.write);
    expect(contractsCreate.requiresConfirmation, isTrue);

    expect(paymentsCreate.operationType, AiToolOperationType.write);
    expect(paymentsCreate.requiresConfirmation, isTrue);

    expect(maintenanceCreate.operationType, AiToolOperationType.write);
    expect(maintenanceCreate.requiresConfirmation, isTrue);
  });

  test('openai tools do not expose bare object properties under strict mode', () {
    final tools = AiToolRegistry.buildOpenAiTools(
      isOfficeMode: true,
      canWrite: true,
      canReadAll: true,
    );

    for (final tool in tools) {
      final function =
          Map<String, dynamic>.from(tool['function'] as Map? ?? const <String, dynamic>{});
      final parameters = Map<String, dynamic>.from(
        function['parameters'] as Map? ?? const <String, dynamic>{},
      );
      _expectStrictSchemaWithoutBareObjects(
        parameters,
        path: function['name']?.toString() ?? 'unknown_tool',
      );
    }
  });
}

void _expectStrictSchemaWithoutBareObjects(
  Map<String, dynamic> schema, {
  required String path,
}) {
  final rawType = schema['type'];
  final types = rawType is List
      ? rawType.map((item) => item.toString()).toSet()
      : <String>{if (rawType != null) rawType.toString()};

  if (types.contains('object')) {
    final hasProperties = schema['properties'] is Map;
    final hasStrictAdditionalProperties = schema['additionalProperties'] == false;
    expect(
      hasProperties && hasStrictAdditionalProperties,
      isTrue,
      reason: '$path must define strict object properties',
    );

    final properties =
        Map<String, dynamic>.from(schema['properties'] as Map? ?? const <String, dynamic>{});
    for (final entry in properties.entries) {
      final nested = Map<String, dynamic>.from(entry.value as Map? ?? const <String, dynamic>{});
      _expectStrictSchemaWithoutBareObjects(nested, path: '$path.${entry.key}');
    }
  }

  if (schema['items'] is Map) {
    _expectStrictSchemaWithoutBareObjects(
      Map<String, dynamic>.from(schema['items'] as Map),
      path: '$path[]',
    );
  }
}
