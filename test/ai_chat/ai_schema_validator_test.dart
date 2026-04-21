import 'package:darvoo/ui/ai_chat/core/ai_schema_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const validator = AiSchemaValidator();

  test('fills nullable missing fields with null and rejects extras', () {
    final result = validator.validateObjectSchema(
      <String, dynamic>{
        'type': 'object',
        'additionalProperties': false,
        'properties': <String, dynamic>{
          'name': <String, dynamic>{'type': <String>['string', 'null']},
          'amount': <String, dynamic>{'type': <String>['number', 'null']},
        },
        'required': <String>['name', 'amount'],
      },
      <String, dynamic>{
        'name': 'Ahmad',
        'unknown': true,
      },
    );

    expect(result.isValid, isFalse);
    expect(result.normalizedArguments['name'], 'Ahmad');
    expect(result.normalizedArguments['amount'], isNull);
    expect(result.errors.any((error) => error.contains('unknown')), isTrue);
  });

  test('rejects invalid enum values', () {
    final result = validator.validateObjectSchema(
      <String, dynamic>{
        'type': 'object',
        'additionalProperties': false,
        'properties': <String, dynamic>{
          'payment_cycle': <String, dynamic>{
            'type': <String>['string', 'null'],
            'enum': <dynamic>['monthly', 'annual', null],
          },
        },
        'required': <String>['payment_cycle'],
      },
      <String, dynamic>{'payment_cycle': 'weekly'},
    );

    expect(result.isValid, isFalse);
    expect(
      result.errors.any((error) => error.contains('غير مسموحة')),
      isTrue,
    );
  });
}
