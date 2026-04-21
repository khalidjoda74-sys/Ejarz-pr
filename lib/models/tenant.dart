// lib/models/tenant.dart
import 'package:darvoo/utils/ksa_time.dart';
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
  DateTime? dateOfBirth; // تاريخ الميلاد
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
  String clientType;
  String? tenantBankName;
  String? tenantBankAccountNumber;
  String? tenantTaxNumber;
  String? companyName;
  String? companyCommercialRegister;
  String? companyTaxNumber;
  String? companyRepresentativeName;
  String? companyRepresentativePhone;
  String? companyBankAccountNumber;
  String? companyBankName;
  String? serviceSpecialization;
  List<String> attachmentPaths;

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
    this.dateOfBirth,
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
    this.clientType = 'tenant',
    this.tenantBankName,
    this.tenantBankAccountNumber,
    this.tenantTaxNumber,
    this.companyName,
    this.companyCommercialRegister,
    this.companyTaxNumber,
    this.companyRepresentativeName,
    this.companyRepresentativePhone,
    this.companyBankAccountNumber,
    this.companyBankName,
    this.serviceSpecialization,
    List<String>? attachmentPaths,
    this.isArchived = false,
    this.isBlacklisted = false,
    this.blacklistReason,
    this.activeContractsCount = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : tags = tags ?? <String>[],
        attachmentPaths = attachmentPaths ?? <String>[],
        createdAt = createdAt ?? KsaTime.now(),
        updatedAt = updatedAt ?? KsaTime.now();
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
      createdAt: fields[19] as DateTime? ?? KsaTime.now(),
      updatedAt: fields[20] as DateTime? ?? KsaTime.now(),
      clientType: (fields[21] as String?) ?? 'tenant',
      tenantBankName: fields[22] as String?,
      tenantBankAccountNumber: fields[23] as String?,
      tenantTaxNumber: fields[24] as String?,
      companyName: fields[25] as String?,
      companyCommercialRegister: fields[26] as String?,
      companyTaxNumber: fields[27] as String?,
      companyRepresentativeName: fields[28] as String?,
      companyRepresentativePhone: fields[29] as String?,
      companyBankAccountNumber: fields[30] as String?,
      companyBankName: fields[31] as String?,
      serviceSpecialization: fields[32] as String?,
      attachmentPaths: (fields[33] as List?)?.cast<String>() ?? <String>[],
      dateOfBirth: fields[34] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter w, Tenant t) {
    w
      ..writeByte(35) // عدد الحقول
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
      ..write(t.updatedAt)
      ..writeByte(21)
      ..write(t.clientType)
      ..writeByte(22)
      ..write(t.tenantBankName)
      ..writeByte(23)
      ..write(t.tenantBankAccountNumber)
      ..writeByte(24)
      ..write(t.tenantTaxNumber)
      ..writeByte(25)
      ..write(t.companyName)
      ..writeByte(26)
      ..write(t.companyCommercialRegister)
      ..writeByte(27)
      ..write(t.companyTaxNumber)
      ..writeByte(28)
      ..write(t.companyRepresentativeName)
      ..writeByte(29)
      ..write(t.companyRepresentativePhone)
      ..writeByte(30)
      ..write(t.companyBankAccountNumber)
      ..writeByte(31)
      ..write(t.companyBankName)
      ..writeByte(32)
      ..write(t.serviceSpecialization)
      ..writeByte(33)
      ..write(t.attachmentPaths)
      ..writeByte(34)
      ..write(t.dateOfBirth);
  }
}



