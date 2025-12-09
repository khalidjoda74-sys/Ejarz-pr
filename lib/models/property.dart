// lib/models/property.dart
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'property.g.dart'; // <-- يولّده build_runner

@HiveType(typeId: 1)
enum PropertyType {
  @HiveField(0) apartment,
  @HiveField(1) villa,
  @HiveField(2) building,
  @HiveField(3) land,
  @HiveField(4) office,
  @HiveField(5) shop,
  @HiveField(6) warehouse,
}

extension PropertyTypeLabel on PropertyType {
  String get label {
    switch (this) {
      case PropertyType.apartment: return 'شقة';
      case PropertyType.villa:     return 'فيلا';
      case PropertyType.building:  return 'عمارة';
      case PropertyType.land:      return 'أرض';
      case PropertyType.office:    return 'مكتب';
      case PropertyType.shop:      return 'محل';
      case PropertyType.warehouse: return 'مستودع';
    }
  }
}

@HiveType(typeId: 2)
enum RentalMode {
  @HiveField(0) wholeBuilding,
  @HiveField(1) perUnit,
}

extension RentalModeLabel on RentalMode {
  String get label {
    switch (this) {
      case RentalMode.wholeBuilding: return 'تأجير كامل العمارة';
      case RentalMode.perUnit:       return 'تأجير الوحدات';
    }
  }
}

@HiveType(typeId: 3)
class Property extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  PropertyType type;

  @HiveField(3)
  String address;

  @HiveField(4)
  double? price;

  @HiveField(5)
  String currency;

  @HiveField(6)
  int? rooms;

  @HiveField(7)
  double? area;

  @HiveField(8)
  int? floors;

  /// للعمارة فقط (نمط تأجير الوحدات)
  @HiveField(9)
  int totalUnits;

  @HiveField(10)
  int occupiedUnits;

  /// للعمارة فقط
  @HiveField(11)
  RentalMode? rentalMode;

  /// ربط الشقق بالعمارة
  @HiveField(12)
  String? parentBuildingId;

  @HiveField(13)
  String? description;

  // ✅ حقول التاريخ
  @HiveField(14)
  DateTime? createdAt;

  @HiveField(15)
  DateTime? updatedAt;

  // ✅ حالة الأرشفة (جديد)
  @HiveField(16)
  bool isArchived;

  Property({
    String? id,
    this.name = '',
    this.type = PropertyType.apartment,
    this.address = '',
    this.price,
    this.currency = 'SAR',
    this.rooms,
    this.area,
    this.floors,
    this.totalUnits = 0,
    this.occupiedUnits = 0,
    this.rentalMode,
    this.parentBuildingId,
    this.description,
    this.createdAt, // يُملأ عند الإنشاء من المنادِي
    this.updatedAt, // يُحدَّث عند التعديل من المنادِي
    this.isArchived = false, // 👈 افتراضي غير مؤرشف
  }) : id = (id == null || id.trim().isEmpty) ? const Uuid().v4() : id;
}
