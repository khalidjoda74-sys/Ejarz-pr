// lib/models/tenant.dart
import 'package:hive/hive.dart';

/// موديل المستأجر (أفراد فقط) + أدابتر Hive يدوي (بدون codegen)
class Tenant extends HiveObject {
  // مفاتيح أساسية
  String id;
  String fullName;
  String nationalId;
  String phone;

  // معلومات إضافية (اختيارية)
  String? email;
  String? nationality;
  DateTime? idExpiry;

  // عنوان
  String? addressLine;
  String? city;
  String? region;
  String? postalCode;

  // طوارئ
  String? emergencyName;
  String? emergencyPhone;

  // ملاحظات ووسوم
  String? notes;
  List<String> tags;

  // حالات
  bool isArchived;
  bool isBlacklisted;
  String? blacklistReason;

  // تكامل مع العقود
  int activeContractsCount;

  // تتبع
  DateTime createdAt;
  DateTime updatedAt;

  Tenant({
    required this.id,
    required this.fullName,
    required this.nationalId,
    required this.phone,
    this.email,
    this.nationality,
    this.idExpiry,
    this.addressLine,
    this.city,
    this.region,
    this.postalCode,
    this.emergencyName,
    this.emergencyPhone,
    this.notes,
    List<String>? tags,
    this.isArchived = false,
    this.isBlacklisted = false,
    this.blacklistReason,
    this.activeContractsCount = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : tags = tags ?? <String>[],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();
}

/// أدابتر Hive يدوي (تأكد من تسجيله في main.dart)
class TenantAdapter extends TypeAdapter<Tenant> {
  @override
  final int typeId = 10; // غيّر الرقم إذا لديك تعارض مع موديلات أخرى

  @override
  Tenant read(BinaryReader r) {
    final numOfFields = r.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) r.readByte(): r.read(),
    };

    return Tenant(
      id: fields[0] as String,
      fullName: fields[1] as String,
      nationalId: fields[2] as String,
      phone: fields[3] as String,
      email: fields[4] as String?,
      nationality: fields[5] as String?,
      idExpiry: fields[6] as DateTime?,
      addressLine: fields[7] as String?,
      city: fields[8] as String?,
      region: fields[9] as String?,
      postalCode: fields[10] as String?,
      emergencyName: fields[11] as String?,
      emergencyPhone: fields[12] as String?,
      notes: fields[13] as String?,
      tags: (fields[14] as List?)?.cast<String>() ?? <String>[],
      isArchived: fields[15] as bool? ?? false,
      isBlacklisted: fields[16] as bool? ?? false,
      blacklistReason: fields[17] as String?,
      activeContractsCount: fields[18] as int? ?? 0,
      createdAt: fields[19] as DateTime? ?? DateTime.now(),
      updatedAt: fields[20] as DateTime? ?? DateTime.now(),
    );
  }

  @override
  void write(BinaryWriter w, Tenant t) {
    w
      ..writeByte(21) // عدد الحقول
      ..writeByte(0)
      ..write(t.id)
      ..writeByte(1)
      ..write(t.fullName)
      ..writeByte(2)
      ..write(t.nationalId)
      ..writeByte(3)
      ..write(t.phone)
      ..writeByte(4)
      ..write(t.email)
      ..writeByte(5)
      ..write(t.nationality)
      ..writeByte(6)
      ..write(t.idExpiry)
      ..writeByte(7)
      ..write(t.addressLine)
      ..writeByte(8)
      ..write(t.city)
      ..writeByte(9)
      ..write(t.region)
      ..writeByte(10)
      ..write(t.postalCode)
      ..writeByte(11)
      ..write(t.emergencyName)
      ..writeByte(12)
      ..write(t.emergencyPhone)
      ..writeByte(13)
      ..write(t.notes)
      ..writeByte(14)
      ..write(t.tags)
      ..writeByte(15)
      ..write(t.isArchived)
      ..writeByte(16)
      ..write(t.isBlacklisted)
      ..writeByte(17)
      ..write(t.blacklistReason)
      ..writeByte(18)
      ..write(t.activeContractsCount)
      ..writeByte(19)
      ..write(t.createdAt)
      ..writeByte(20)
      ..write(t.updatedAt);
  }
}
