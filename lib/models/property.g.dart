// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'property.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PropertyAdapter extends TypeAdapter<Property> {
  @override
  final int typeId = 3;

  @override
  Property read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Property(
      id: fields[0] as String?,
      name: fields[1] as String,
      type: fields[2] as PropertyType,
      address: fields[3] as String,
      price: fields[4] as double?,
      currency: fields[5] as String,
      rooms: fields[6] as int?,
      area: fields[7] as double?,
      floors: fields[8] as int?,
      totalUnits: fields[9] as int,
      occupiedUnits: fields[10] as int,
      rentalMode: fields[11] as RentalMode?,
      parentBuildingId: fields[12] as String?,
      description: fields[13] as String?,
      createdAt: fields[14] as DateTime?,
      updatedAt: fields[15] as DateTime?,
      isArchived: fields[16] as bool,
      documentType: fields[17] as String?,
      documentNumber: fields[18] as String?,
      documentDate: fields[19] as DateTime?,
      documentAttachmentPath: fields[20] as String?,
      documentAttachmentPaths: (fields[27] as List?)?.cast<String>(),
      electricityNumber: fields[21] as String?,
      electricityMode: fields[22] as String?,
      electricityShare: fields[23] as String?,
      waterNumber: fields[24] as String?,
      waterMode: fields[25] as String?,
      waterShare: fields[26] as String?,
      waterAmount: fields[28] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Property obj) {
    writer
      ..writeByte(29)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.type)
      ..writeByte(3)
      ..write(obj.address)
      ..writeByte(4)
      ..write(obj.price)
      ..writeByte(5)
      ..write(obj.currency)
      ..writeByte(6)
      ..write(obj.rooms)
      ..writeByte(7)
      ..write(obj.area)
      ..writeByte(8)
      ..write(obj.floors)
      ..writeByte(9)
      ..write(obj.totalUnits)
      ..writeByte(10)
      ..write(obj.occupiedUnits)
      ..writeByte(11)
      ..write(obj.rentalMode)
      ..writeByte(12)
      ..write(obj.parentBuildingId)
      ..writeByte(13)
      ..write(obj.description)
      ..writeByte(14)
      ..write(obj.createdAt)
      ..writeByte(15)
      ..write(obj.updatedAt)
      ..writeByte(16)
      ..write(obj.isArchived)
      ..writeByte(17)
      ..write(obj.documentType)
      ..writeByte(18)
      ..write(obj.documentNumber)
      ..writeByte(19)
      ..write(obj.documentDate)
      ..writeByte(20)
      ..write(obj.documentAttachmentPath)
      ..writeByte(27)
      ..write(obj.documentAttachmentPaths)
      ..writeByte(21)
      ..write(obj.electricityNumber)
      ..writeByte(22)
      ..write(obj.electricityMode)
      ..writeByte(23)
      ..write(obj.electricityShare)
      ..writeByte(24)
      ..write(obj.waterNumber)
      ..writeByte(25)
      ..write(obj.waterMode)
      ..writeByte(26)
      ..write(obj.waterShare)
      ..writeByte(28)
      ..write(obj.waterAmount);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PropertyAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class PropertyTypeAdapter extends TypeAdapter<PropertyType> {
  @override
  final int typeId = 1;

  @override
  PropertyType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return PropertyType.apartment;
      case 1:
        return PropertyType.villa;
      case 2:
        return PropertyType.building;
      case 3:
        return PropertyType.land;
      case 4:
        return PropertyType.office;
      case 5:
        return PropertyType.shop;
      case 6:
        return PropertyType.warehouse;
      default:
        return PropertyType.apartment;
    }
  }

  @override
  void write(BinaryWriter writer, PropertyType obj) {
    switch (obj) {
      case PropertyType.apartment:
        writer.writeByte(0);
        break;
      case PropertyType.villa:
        writer.writeByte(1);
        break;
      case PropertyType.building:
        writer.writeByte(2);
        break;
      case PropertyType.land:
        writer.writeByte(3);
        break;
      case PropertyType.office:
        writer.writeByte(4);
        break;
      case PropertyType.shop:
        writer.writeByte(5);
        break;
      case PropertyType.warehouse:
        writer.writeByte(6);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PropertyTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class RentalModeAdapter extends TypeAdapter<RentalMode> {
  @override
  final int typeId = 2;

  @override
  RentalMode read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return RentalMode.wholeBuilding;
      case 1:
        return RentalMode.perUnit;
      default:
        return RentalMode.wholeBuilding;
    }
  }

  @override
  void write(BinaryWriter writer, RentalMode obj) {
    switch (obj) {
      case RentalMode.wholeBuilding:
        writer.writeByte(0);
        break;
      case RentalMode.perUnit:
        writer.writeByte(1);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RentalModeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
