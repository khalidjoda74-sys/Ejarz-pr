class AiSchemaValidationResult {
  final Map<String, dynamic> normalizedArguments;
  final List<String> errors;

  const AiSchemaValidationResult({
    required this.normalizedArguments,
    required this.errors,
  });

  bool get isValid => errors.isEmpty;
}

class AiSchemaValidator {
  const AiSchemaValidator();

  AiSchemaValidationResult validateObjectSchema(
    Map<String, dynamic> schema,
    Map<String, dynamic> rawArguments,
  ) {
    final errors = <String>[];
    final normalized = _validateValue(
      schema,
      rawArguments,
      path: 'root',
      errors: errors,
    );
    return AiSchemaValidationResult(
      normalizedArguments:
          normalized is Map<String, dynamic> ? normalized : <String, dynamic>{},
      errors: errors,
    );
  }

  dynamic _validateValue(
    Map<String, dynamic> schema,
    dynamic value, {
    required String path,
    required List<String> errors,
  }) {
    final enumValues = schema['enum'];
    if (enumValues is List && !_enumContains(enumValues, value)) {
      errors.add('القيمة في $path غير مسموحة.');
      return value;
    }

    final typeSpec = schema['type'];
    final normalizedTypes = _normalizeTypes(typeSpec);
    if (normalizedTypes.isNotEmpty &&
        !_matchesAnyType(normalizedTypes, value, schema)) {
      errors.add('نوع القيمة في $path غير صحيح.');
      return value;
    }

    if (value == null) return null;

    if (normalizedTypes.contains('object')) {
      final properties = Map<String, dynamic>.from(
        schema['properties'] as Map? ?? const <String, dynamic>{},
      );
      final requiredKeys = (schema['required'] as List? ?? const <dynamic>[])
          .map((item) => item.toString())
          .toSet();
      final additionalProperties = schema['additionalProperties'] == true;
      final rawMap = value is Map<String, dynamic>
          ? value
          : value is Map
              ? Map<String, dynamic>.from(value)
              : <String, dynamic>{};

      if (!additionalProperties) {
        for (final key in rawMap.keys) {
          if (!properties.containsKey(key)) {
            errors.add('الحقل $key غير مسموح به.');
          }
        }
      }

      final normalizedMap = <String, dynamic>{};
      for (final entry in properties.entries) {
        final childSchema =
            Map<String, dynamic>.from(entry.value as Map? ?? const <String, dynamic>{});
        final key = entry.key;
        if (!rawMap.containsKey(key)) {
          if (_allowsNull(childSchema)) {
            normalizedMap[key] = null;
            continue;
          }
          if (requiredKeys.contains(key)) {
            errors.add('الحقل $key مطلوب.');
          }
          continue;
        }
        normalizedMap[key] = _validateValue(
          childSchema,
          rawMap[key],
          path: '$path.$key',
          errors: errors,
        );
      }
      return normalizedMap;
    }

    if (normalizedTypes.contains('array')) {
      final rawList = value is List ? value : const <dynamic>[];
      final itemSchema = Map<String, dynamic>.from(
        schema['items'] as Map? ?? const <String, dynamic>{},
      );
      return rawList
          .asMap()
          .entries
          .map((entry) => _validateValue(
                itemSchema,
                entry.value,
                path: '$path[${entry.key}]',
                errors: errors,
              ))
          .toList(growable: false);
    }

    return value;
  }

  bool _matchesAnyType(
    List<String> types,
    dynamic value,
    Map<String, dynamic> schema,
  ) {
    for (final type in types) {
      if (_matchesType(type, value, schema)) return true;
    }
    return false;
  }

  bool _matchesType(
    String type,
    dynamic value,
    Map<String, dynamic> schema,
  ) {
    switch (type) {
      case 'null':
        return value == null;
      case 'string':
        return value is String;
      case 'number':
        return value is num;
      case 'integer':
        return value is int;
      case 'boolean':
        return value is bool;
      case 'object':
        return value is Map;
      case 'array':
        return value is List;
      default:
        return true;
    }
  }

  bool _enumContains(List<dynamic> enumValues, dynamic value) {
    for (final item in enumValues) {
      if (item == value) return true;
    }
    return false;
  }

  List<String> _normalizeTypes(dynamic rawType) {
    if (rawType is String) return <String>[rawType];
    if (rawType is List) {
      return rawType.map((item) => item.toString()).toList(growable: false);
    }
    return const <String>[];
  }

  bool _allowsNull(Map<String, dynamic> schema) {
    final types = _normalizeTypes(schema['type']);
    return types.contains('null');
  }
}
