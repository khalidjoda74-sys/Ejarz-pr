import 'models.dart';

String normalizedUnitNumber(String value) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  var result = value.trim().toLowerCase();
  for (var i = 0; i < 10; i++) {
    result = result.replaceAll(arabic[i], '$i').replaceAll(persian[i], '$i');
  }
  return int.tryParse(result)?.toString() ?? result;
}

List<UnitRecord> mergePropertyUnits({
  required List<UnitRecord> current,
  required List<UnitRecord> additions,
  required int capacity,
  String replacingNumber = '',
}) {
  if (replacingNumber.isNotEmpty &&
      !current.any((u) => u.number == replacingNumber)) {
    throw StateError('تغيرت بيانات الوحدة. أعد فتحها وحاول مرة أخرى.');
  }
  if (replacingNumber.isNotEmpty && additions.length != 1) {
    throw StateError('يجب تعديل وحدة واحدة في كل عملية تعديل.');
  }
  final replacedIndex = current.indexWhere((u) => u.number == replacingNumber);
  final result = current.where((u) => u.number != replacingNumber).toList();
  final numbers = result.map((u) => normalizedUnitNumber(u.number)).toSet();
  for (final unit in additions) {
    final number = normalizedUnitNumber(unit.number);
    if (number.isEmpty || !numbers.add(number)) {
      throw StateError('رقم الوحدة ${unit.number} مستخدم في هذه العمارة.');
    }
    if (replacedIndex >= 0) {
      result.insert(replacedIndex, unit);
    } else {
      result.add(unit);
    }
  }
  if (result.length > capacity) {
    throw StateError('عدد الوحدات يتجاوز سعة العمارة ($capacity وحدة).');
  }
  return List<UnitRecord>.unmodifiable(result);
}

void validatePropertyStructure(PropertyRecord? previous, PropertyData next) {
  if (previous == null || previous.units.isEmpty) return;
  if (previous.managesUnits &&
      (next.rentalMode != 'units' || next.propertyType != previous.type)) {
    throw StateError(
        'لا يمكن تغيير نوع العمارة أو طريقة تأجيرها بعد تسجيل الوحدات.');
  }
}

PropertyRecord managedPropertyRecord(
    PropertyData data, String id, List<UnitRecord> units) {
  final capacity = int.tryParse(data.totalUnits) ?? 1;
  if (capacity < units.length) {
    throw StateError(
        'لا يمكن تقليل السعة عن عدد الوحدات المسجلة (${units.length}).');
  }
  final floors = int.tryParse(data.floorsCount) ?? 1;
  if (data.rentalMode == 'units' &&
      units.any((unit) {
        final floor = int.tryParse(unit.floor);
        return floor != null && (floor < 0 || floor >= floors);
      })) {
    throw StateError('رقم دور إحدى الوحدات خارج أدوار العمارة. الأرضي رقمه 0.');
  }
  return PropertyRecord(
    id: id,
    title: data.buildingName.trim().isEmpty
        ? '${data.propertyType} ${data.district}'.trim()
        : data.buildingName.trim(),
    city: data.city,
    district: data.district,
    type: data.propertyType,
    usage: data.propertyUsage,
    floors: floors,
    totalUnits: capacity,
    units: List<UnitRecord>.unmodifiable(units),
    data: PropertyData.copyOf(data),
  );
}
