import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'models.dart';

class FirebaseRepository {
  FirebaseRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore firestore;
  final FirebaseStorage storage;

  Stream<List<ContractRecord>> watchUserContracts(String uid) {
    return firestore
        .collection('contracts')
        .where('uid', isEqualTo: uid)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => contractFromDoc(doc)).toList());
  }

  Stream<List<PropertyRecord>> watchUserProperties(String uid) {
    return firestore
        .collection('properties')
        .where('uid', isEqualTo: uid)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => propertyFromDoc(doc)).toList());
  }

  Stream<List<NotificationItem>> watchUserNotifications(String uid) {
    return firestore
        .collection('notifications')
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(80)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => notificationFromDoc(doc)).toList());
  }

  Future<void> ensureUserProfile({
    required String uid,
    required String phone,
    required String name,
    required String email,
  }) async {
    final ref = firestore.collection('users').doc(uid);
    final snapshot = await ref.get();
    final data = <String, Object?>{
      'uid': uid,
      'phone': phone,
      'name': name,
      'email': email,
      'role': 'customer',
      'lastLoginAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (snapshot.exists) {
      await ref.set(data, SetOptions(merge: true));
      return;
    }
    await ref.set(<String, Object?>{
      ...data,
      'status': 'active',
      'notesFromAdmin': '',
      'stats': <String, Object?>{
        'contractsCount': 0,
        'completedContractsCount': 0,
      },
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String> userStatus(String uid) async {
    final snapshot = await firestore.collection('users').doc(uid).get();
    return (snapshot.data()?['status'] as String?) ?? 'active';
  }

  Future<ContractRecord> submitContract({
    required String uid,
    required String customerName,
    required String customerPhone,
    required String customerEmail,
    required ContractDraft draft,
    required ContractStatus status,
  }) async {
    final now = DateTime.now();
    final doc = firestore.collection('contracts').doc();
    final requestNumber =
        'REQ-${now.year}-${doc.id.substring(0, 6).toUpperCase()}';
    final timeline = initialTimeline(status, now);
    final record = ContractRecord(
      id: doc.id,
      requestNumber: requestNumber,
      uid: uid,
      type: draft.type,
      role: draft.role,
      title: draft.title,
      property: draft.property.displayAddress,
      lessorName: draft.lessor.displayName,
      tenantName: draft.tenant.displayName,
      date: _dateLabel(now),
      status: status,
      totalFees: status == ContractStatus.draft ? 0 : draft.totalPayable,
      timeline: timeline,
    );

    final batch = firestore.batch();
    batch.set(doc, <String, Object?>{
      'id': doc.id,
      'requestNumber': requestNumber,
      'uid': uid,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'customerEmail': customerEmail,
      'type': draft.type.name,
      'role': draft.role.name,
      'status': status.name,
      'title': draft.title,
      'propertySummary': draft.property.displayAddress,
      'propertyTitle': draft.property.buildingName.trim().isEmpty
          ? draft.property.propertyType
          : draft.property.buildingName.trim(),
      'city': draft.property.city,
      'district': draft.property.district,
      'lessorSummary': draft.lessor.displayName,
      'tenantSummary': draft.tenant.displayName,
      'draftData': draftToMap(draft),
      'totalFees': record.totalFees,
      'adminAssignedTo': '',
      'adminInternalNotes': '',
      'customerVisibleNote': '',
      'missingRequirements': <Map<String, Object?>>[],
      'finalPdfUrl': '',
      'finalPdfFileName': '',
      'timeline': timeline.map(timelineToMap).toList(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'submittedAt':
          status == ContractStatus.draft ? null : FieldValue.serverTimestamp(),
      'completedAt': null,
    });
    batch.set(
      firestore.collection('notifications').doc(),
      <String, Object?>{
        'uid': uid,
        'contractId': doc.id,
        'title': status == ContractStatus.draft
            ? 'تم حفظ المسودة'
            : 'تم استلام طلب العقد',
        'body': status == ContractStatus.draft
            ? 'تم حفظ مسودة ${draft.title} ويمكنك إكمالها لاحقًا.'
            : 'تم استلام طلب ${draft.title} وسيتم مراجعته من فريق إيجارز برو.',
        'type': 'contract',
        'read': false,
        'actionType': 'contractDetails',
        'actionPayload': <String, Object?>{'contractId': doc.id},
        'createdAt': FieldValue.serverTimestamp(),
      },
    );
    batch.set(
      firestore.collection('users').doc(uid),
      <String, Object?>{
        'stats.contractsCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
    return record;
  }

  Future<void> updateContractStatus({
    required String contractId,
    required ContractStatus status,
    required String adminUid,
    String customerNote = '',
  }) async {
    final ref = firestore.collection('contracts').doc(contractId);
    await firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data() ?? <String, Object?>{};
      final uid = (data['uid'] as String?) ?? '';
      final title = (data['title'] as String?) ?? 'طلب العقد';
      final event = timelineEventFor(status, DateTime.now(), customerNote);
      transaction.update(ref, <String, Object?>{
        'status': status.name,
        'customerVisibleNote': customerNote,
        'updatedAt': FieldValue.serverTimestamp(),
        if (status == ContractStatus.authenticated)
          'completedAt': FieldValue.serverTimestamp(),
        'timeline': FieldValue.arrayUnion(<Map<String, Object?>>[
          timelineToMap(event),
        ]),
      });
      transaction.set(
        firestore.collection('notifications').doc(),
        <String, Object?>{
          'uid': uid,
          'contractId': contractId,
          'title': event.title,
          'body': customerNote.isEmpty ? event.subtitle : customerNote,
          'type': 'contractStatus',
          'read': false,
          'actionType': 'contractDetails',
          'actionPayload': <String, Object?>{'contractId': contractId},
          'createdAt': FieldValue.serverTimestamp(),
        },
      );
      transaction.set(
        firestore.collection('auditLogs').doc(),
        <String, Object?>{
          'adminUid': adminUid,
          'action': 'updateContractStatus',
          'targetType': 'contract',
          'targetId': contractId,
          'before': data['status'],
          'after': status.name,
          'title': title,
          'createdAt': FieldValue.serverTimestamp(),
        },
      );
    });
  }

  Future<void> addMissingRequirement({
    required String contractId,
    required String uid,
    required String title,
    required String description,
    required String type,
    required String fieldPath,
    required String adminUid,
  }) async {
    final item = <String, Object?>{
      'id': firestore.collection('_').doc().id,
      'title': title,
      'description': description,
      'type': type,
      'fieldPath': fieldPath,
      'required': true,
      'resolved': false,
    };
    final event = timelineEventFor(
      ContractStatus.missingData,
      DateTime.now(),
      description,
    );
    final batch = firestore.batch();
    final ref = firestore.collection('contracts').doc(contractId);
    batch.update(ref, <String, Object?>{
      'status': ContractStatus.missingData.name,
      'customerVisibleNote': description,
      'missingRequirements': FieldValue.arrayUnion(<Map<String, Object?>>[
        item,
      ]),
      'timeline': FieldValue.arrayUnion(<Map<String, Object?>>[
        timelineToMap(event),
      ]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(firestore.collection('notifications').doc(), <String, Object?>{
      'uid': uid,
      'contractId': contractId,
      'title': 'يوجد نقص مطلوب في طلبك',
      'body': description,
      'type': 'missingRequirement',
      'read': false,
      'actionType': 'contractDetails',
      'actionPayload': <String, Object?>{'contractId': contractId},
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(firestore.collection('auditLogs').doc(), <String, Object?>{
      'adminUid': adminUid,
      'action': 'addMissingRequirement',
      'targetType': 'contract',
      'targetId': contractId,
      'after': item,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> attachFinalPdf({
    required String contractId,
    required String uid,
    required String fileName,
    required Uint8List bytes,
    required String adminUid,
  }) async {
    final storagePath =
        'contracts/$contractId/final/${DateTime.now().millisecondsSinceEpoch}-$fileName';
    final ref = storage.ref(storagePath);
    await ref.putData(
      bytes,
      SettableMetadata(contentType: 'application/pdf'),
    );
    final url = await ref.getDownloadURL();
    final event =
        timelineEventFor(ContractStatus.authenticated, DateTime.now());
    final batch = firestore.batch();
    final contractRef = firestore.collection('contracts').doc(contractId);
    batch.update(contractRef, <String, Object?>{
      'status': ContractStatus.authenticated.name,
      'finalPdfUrl': url,
      'finalPdfFileName': fileName,
      'finalPdfUploadedAt': FieldValue.serverTimestamp(),
      'completedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'timeline': FieldValue.arrayUnion(<Map<String, Object?>>[
        timelineToMap(event),
      ]),
    });
    batch.set(contractRef.collection('files').doc(), <String, Object?>{
      'fileType': 'finalPdf',
      'title': 'العقد النهائي',
      'storagePath': storagePath,
      'downloadUrl': url,
      'uploadedBy': 'admin',
      'createdAt': FieldValue.serverTimestamp(),
      'required': false,
      'status': 'active',
    });
    batch.set(firestore.collection('notifications').doc(), <String, Object?>{
      'uid': uid,
      'contractId': contractId,
      'title': 'تم إصدار العقد النهائي',
      'body': 'يمكنك الآن تحميل ملف العقد النهائي من تفاصيل الطلب.',
      'type': 'finalPdf',
      'read': false,
      'actionType': 'contractDetails',
      'actionPayload': <String, Object?>{'contractId': contractId},
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(firestore.collection('auditLogs').doc(), <String, Object?>{
      'adminUid': adminUid,
      'action': 'attachFinalPdf',
      'targetType': 'contract',
      'targetId': contractId,
      'after': <String, Object?>{
        'fileName': fileName,
        'storagePath': storagePath
      },
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  ContractRecord contractFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return ContractRecord(
      id: doc.id,
      requestNumber: (data['requestNumber'] as String?) ?? doc.id,
      uid: (data['uid'] as String?) ?? '',
      type: _contractType((data['type'] as String?) ?? ''),
      role: _userRole((data['role'] as String?) ?? ''),
      title: (data['title'] as String?) ?? 'طلب عقد',
      property: (data['propertySummary'] as String?) ?? '',
      lessorName: (data['lessorSummary'] as String?) ?? '',
      tenantName: (data['tenantSummary'] as String?) ?? '',
      date: _dateFromAny(data['createdAt']),
      status: _contractStatus((data['status'] as String?) ?? ''),
      totalFees: ((data['totalFees'] as num?) ?? 0).toDouble(),
      timeline: ((data['timeline'] as List?) ?? const <Object?>[])
          .whereType<Map>()
          .map((item) => timelineFromMap(Map<String, dynamic>.from(item)))
          .toList(),
      customerVisibleNote: (data['customerVisibleNote'] as String?) ?? '',
      finalPdfUrl: (data['finalPdfUrl'] as String?) ?? '',
      finalPdfFileName: (data['finalPdfFileName'] as String?) ?? '',
      missingRequirements:
          ((data['missingRequirements'] as List?) ?? const <Object?>[])
              .whereType<Map>()
              .map((item) =>
                  missingRequirementFromMap(Map<String, dynamic>.from(item)))
              .toList(),
    );
  }

  PropertyRecord propertyFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return PropertyRecord(
      id: doc.id,
      title: (data['title'] as String?) ?? 'عقار',
      city: (data['city'] as String?) ?? 'الرياض',
      district: (data['district'] as String?) ?? '',
      type: (data['type'] as String?) ?? '',
      usage: (data['usage'] as String?) ?? '',
      floors: ((data['floors'] as num?) ?? 1).toInt(),
      totalUnits: ((data['totalUnits'] as num?) ?? 1).toInt(),
      units: const <UnitRecord>[],
    );
  }

  NotificationItem notificationFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return NotificationItem(
      title: (data['title'] as String?) ?? 'تنبيه',
      body: (data['body'] as String?) ?? '',
      time: _dateFromAny(data['createdAt']),
      icon: ContractStatus.underReview.icon,
      color: ContractStatus.underReview.color,
      read: (data['read'] as bool?) ?? false,
    );
  }

  Map<String, Object?> draftToMap(ContractDraft draft) {
    return <String, Object?>{
      'type': draft.type.name,
      'role': draft.role.name,
      'urgent': draft.urgent,
      'property': propertyDataToMap(draft.property),
      'lessor': partyDataToMap(draft.lessor),
      'tenant': partyDataToMap(draft.tenant),
      'representative': representativeToMap(draft.representative),
      'duration': <String, Object?>{
        'startDate': draft.startDate,
        'endDate': draft.endDate,
        'years': draft.durationYears,
        'months': draft.durationMonths,
        'days': draft.durationDays,
      },
      'financial': <String, Object?>{
        'rentValue': draft.rentValue,
        'rentPeriod': draft.rentPeriod,
        'hasSecurityDeposit': draft.hasSecurityDeposit,
        'securityDeposit': draft.securityDeposit,
        'paymentFrequency': draft.paymentFrequency,
        'paymentCount': draft.paymentCount,
        'paymentChannel': draft.paymentChannel,
        'officialFeePayer': draft.officialFeePayer,
        'serviceFeePayer': draft.serviceFeePayer,
        'ejarPlatformFee': draft.officialFee,
        'serviceFee': draft.serviceFee,
        'totalPayable': draft.totalPayable,
      },
      'services': <String, Object?>{
        'electricity': serviceChargeToMap(draft.electricity),
        'water': serviceChargeToMap(draft.water),
        'gas': serviceChargeToMap(draft.gas),
        'otherServices': draft.otherServices,
      },
      'terms': <String, Object?>{
        'allowSublease': draft.allowSublease,
        'autoRenewal': draft.autoRenewal,
        'specialTerms': draft.specialTerms,
      },
      'attachments': draft.attachments.map(attachmentToMap).toList(),
      'installments': draft.installments
          .map((item) => <String, Object?>{
                'index': item.index,
                'amount': item.amount,
                'dueDate': item.dueDate,
                'note': item.note,
              })
          .toList(),
    };
  }

  static Map<String, Object?> partyDataToMap(PartyData data) {
    return <String, Object?>{
      'kind': data.kind.name,
      'fullName': data.fullName,
      'idType': data.idType,
      'idNumber': data.idNumber,
      'birthDate': data.birthDate,
      'mobile': data.mobile,
      'email': data.email,
      'city': data.city,
      'district': data.district,
      'nationalAddress': data.nationalAddress,
      'mobileRegisteredInAbsher': data.mobileRegisteredInAbsher,
      'commercialRegistration': data.commercialRegistration,
      'unifiedNumber': data.unifiedNumber,
      'authorizedPersonName': data.authorizedPersonName,
      'authorizedPersonId': data.authorizedPersonId,
      'iban': data.iban,
      'bankName': data.bankName,
      'accountOwner': data.accountOwner,
    };
  }

  static Map<String, Object?> propertyDataToMap(PropertyData data) {
    return <String, Object?>{
      'propertySource': data.propertySource,
      'ownershipDocumentNumber': data.ownershipDocumentNumber,
      'ownershipDocumentType': data.ownershipDocumentType,
      'ownershipDocumentDate': data.ownershipDocumentDate,
      'propertyUsage': data.propertyUsage,
      'propertyType': data.propertyType,
      'floorsCount': data.floorsCount,
      'unitsPerFloor': data.unitsPerFloor,
      'totalUnits': data.totalUnits,
      'city': data.city,
      'district': data.district,
      'street': data.street,
      'buildingNumber': data.buildingNumber,
      'additionalNumber': data.additionalNumber,
      'postalCode': data.postalCode,
      'buildingName': data.buildingName,
      'unitNumber': data.unitNumber,
      'unitName': data.unitName,
      'unitType': data.unitType,
      'floor': data.floor,
      'area': data.area,
      'roomsCount': data.roomsCount,
      'bathroomsCount': data.bathroomsCount,
      'hallsCount': data.hallsCount,
      'maidRoom': data.maidRoom,
      'kitchen': data.kitchen,
      'storage': data.storage,
      'majlis': data.majlis,
      'furnishingStatus': data.furnishingStatus,
      'acWindow': data.acWindow,
      'acSplit': data.acSplit,
      'acCentral': data.acCentral,
      'privateParking': data.privateParking,
      'electricityMeter': data.electricityMeter,
      'waterMeter': data.waterMeter,
      'gasMeter': data.gasMeter,
      'notes': data.notes,
    };
  }

  static Map<String, Object?> representativeToMap(RepresentativeData data) {
    return <String, Object?>{
      'enabled': data.enabled,
      'represents': data.represents,
      'type': data.type,
      'fullName': data.fullName,
      'idType': data.idType,
      'idNumber': data.idNumber,
      'birthDate': data.birthDate,
      'mobile': data.mobile,
      'authorizationNumber': data.authorizationNumber,
      'authorizationDate': data.authorizationDate,
      'issuer': data.issuer,
      'expiryDate': data.expiryDate,
    };
  }

  static Map<String, Object?> serviceChargeToMap(ServiceCharge data) {
    return <String, Object?>{
      'enabled': data.enabled,
      'calculationMethod': data.calculationMethod,
      'fixedAmount': data.fixedAmount,
      'currentReading': data.currentReading,
    };
  }

  static Map<String, Object?> attachmentToMap(AttachmentData data) {
    return <String, Object?>{
      'keyName': data.keyName,
      'title': data.title,
      'required': data.required,
      'uploaded': data.uploaded,
      'fileName': data.fileName,
      'sizeLabel': data.sizeLabel,
    };
  }

  static List<StatusTimelineItem> initialTimeline(
    ContractStatus status,
    DateTime now,
  ) {
    return <StatusTimelineItem>[
      StatusTimelineItem(
        title: status == ContractStatus.draft
            ? 'تم حفظ المسودة'
            : 'تم استلام الطلب',
        subtitle: status == ContractStatus.draft
            ? 'لم يتم إرسال الطلب للمراجعة بعد'
            : 'تم استلام الطلب وسيبدأ فريق إيجارز برو بمراجعته',
        date: _dateLabel(now),
        time: _timeLabel(now),
        completed: status != ContractStatus.draft,
        current: status == ContractStatus.draft ||
            status == ContractStatus.underReview,
      ),
    ];
  }

  static StatusTimelineItem timelineEventFor(
    ContractStatus status,
    DateTime now, [
    String note = '',
  ]) {
    final title = switch (status) {
      ContractStatus.missingData => 'يوجد نقص مطلوب',
      ContractStatus.readyForEjar => 'جاهز للإدخال في إيجار',
      ContractStatus.enteredInEjar => 'تم الإدخال في إيجار',
      ContractStatus.awaitingAuthentication => 'بانتظار التوثيق',
      ContractStatus.authenticated => 'تم إصدار العقد النهائي',
      ContractStatus.rejected => 'تم رفض الطلب',
      ContractStatus.awaitingPayment => 'بانتظار الدفع',
      ContractStatus.draft => 'مسودة',
      ContractStatus.underReview => 'قيد المراجعة',
    };
    return StatusTimelineItem(
      title: title,
      subtitle: note.isEmpty ? status.label : note,
      date: _dateLabel(now),
      time: _timeLabel(now),
      completed: status == ContractStatus.authenticated,
      current: status != ContractStatus.authenticated,
    );
  }

  static Map<String, Object?> timelineToMap(StatusTimelineItem item) {
    return <String, Object?>{
      'title': item.title,
      'subtitle': item.subtitle,
      'date': item.date,
      'time': item.time,
      'completed': item.completed,
      'current': item.current,
    };
  }

  static StatusTimelineItem timelineFromMap(Map<String, dynamic> data) {
    return StatusTimelineItem(
      title: (data['title'] as String?) ?? '',
      subtitle: (data['subtitle'] as String?) ?? '',
      date: (data['date'] as String?) ?? '',
      time: (data['time'] as String?) ?? '',
      completed: (data['completed'] as bool?) ?? false,
      current: (data['current'] as bool?) ?? false,
    );
  }

  static MissingRequirement missingRequirementFromMap(
    Map<String, dynamic> data,
  ) {
    return MissingRequirement(
      id: (data['id'] as String?) ?? '',
      title: (data['title'] as String?) ?? 'نقص مطلوب',
      description: (data['description'] as String?) ?? '',
      type: (data['type'] as String?) ?? 'field',
      fieldPath: (data['fieldPath'] as String?) ?? '',
      required: (data['required'] as bool?) ?? true,
      resolved: (data['resolved'] as bool?) ?? false,
    );
  }

  static ContractType _contractType(String value) {
    return ContractType.values.firstWhere(
      (item) => item.name == value,
      orElse: () => ContractType.residential,
    );
  }

  static UserRole _userRole(String value) {
    return UserRole.values.firstWhere(
      (item) => item.name == value,
      orElse: () => UserRole.lessor,
    );
  }

  static ContractStatus _contractStatus(String value) {
    return ContractStatus.values.firstWhere(
      (item) => item.name == value,
      orElse: () => ContractStatus.underReview,
    );
  }

  static String _dateFromAny(Object? value) {
    if (value is Timestamp) return _dateLabel(value.toDate());
    return _dateLabel(DateTime.now());
  }

  static String _dateLabel(DateTime value) {
    return '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';
  }

  static String _timeLabel(DateTime value) {
    return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }
}
