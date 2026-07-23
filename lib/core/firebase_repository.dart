import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'missing_requirement_policy.dart';
import 'models.dart';

class FirebaseRepository {
  static const int _demoPropertyDataVersion = 2;

  FirebaseRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore firestore;
  final FirebaseStorage storage;

  Future<void> verifyServerReachable(String uid) async {
    await firestore.collection('users').doc(uid).get(
          const GetOptions(source: Source.server),
        );
  }

  Stream<bool> watchUserOnlineState(String uid) {
    return firestore
        .collection('users')
        .doc(uid)
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) => !snapshot.metadata.isFromCache)
        .distinct();
  }

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

  Stream<List<SupportTicketRecord>> watchUserSupportTickets(String uid) {
    return firestore
        .collection('supportTickets')
        .where('uid', isEqualTo: uid)
        .orderBy('updatedAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => supportTicketFromDoc(doc)).toList());
  }

  Future<void> ensureUserProfile({
    required String uid,
    required String phone,
    required String name,
    required String email,
    bool isDemo = false,
  }) async {
    final ref = firestore.collection('users').doc(uid);
    final snapshot = await ref.get();
    final data = <String, Object?>{
      'uid': uid,
      'phone': phone,
      'name': name,
      'email': email,
      'lastLoginAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (isDemo) 'isDemoUser': true,
    };
    if (snapshot.exists) {
      await ref.set(data, SetOptions(merge: true));
      return;
    }
    await ref.set(<String, Object?>{
      ...data,
      'role': 'customer',
      'status': 'active',
      'notesFromAdmin': '',
      'notificationPrefs': <String, Object?>{
        'inApp': true,
        'push': true,
      },
      'stats': <String, Object?>{
        'contractsCount': 0,
        'completedContractsCount': 0,
      },
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<bool> userProfileExists(String uid) async {
    final snapshot = await firestore.collection('users').doc(uid).get();
    return snapshot.exists;
  }

  Future<String> userStatus(String uid) async {
    final snapshot = await firestore.collection('users').doc(uid).get();
    return (snapshot.data()?['status'] as String?) ?? 'active';
  }

  Future<Map<String, dynamic>> userNotificationPrefs(String uid) async {
    final snapshot = await firestore.collection('users').doc(uid).get();
    final prefs = snapshot.data()?['notificationPrefs'];
    if (prefs is Map) return Map<String, dynamic>.from(prefs);
    return <String, dynamic>{
      'inApp': true,
      'push': true,
    };
  }

  Future<void> updateNotificationPrefs({
    required String uid,
    required bool push,
  }) {
    return firestore.collection('users').doc(uid).set(
      <String, Object?>{
        'notificationPrefs': <String, Object?>{
          'inApp': true,
          'push': push,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> saveFcmToken({
    required String uid,
    required String token,
    required String platform,
  }) {
    final tokenId = base64Url.encode(utf8.encode(token));
    return firestore
        .collection('users')
        .doc(uid)
        .collection('fcmTokens')
        .doc(tokenId)
        .set(
      <String, Object?>{
        'token': token,
        'platform': platform,
        'active': true,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> deactivateFcmToken({
    required String uid,
    required String token,
  }) {
    final tokenId = base64Url.encode(utf8.encode(token));
    return firestore
        .collection('users')
        .doc(uid)
        .collection('fcmTokens')
        .doc(tokenId)
        .set(
      <String, Object?>{
        'token': token,
        'active': false,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> markNotificationRead(String notificationId) {
    return firestore.collection('notifications').doc(notificationId).update(
      <String, Object?>{
        'read': true,
        'readAt': FieldValue.serverTimestamp(),
      },
    );
  }

  Future<void> markAllNotificationsRead(String uid) async {
    final snapshot = await firestore
        .collection('notifications')
        .where('uid', isEqualTo: uid)
        .where('read', isEqualTo: false)
        .limit(100)
        .get();
    final batch = firestore.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, <String, Object?>{
        'read': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<ContractRecord?> fetchContract(String contractId) async {
    final snapshot =
        await firestore.collection('contracts').doc(contractId).get();
    if (!snapshot.exists) return null;
    return contractFromDoc(snapshot);
  }

  Future<bool> isAdminUser(String uid) async {
    final snapshot = await firestore.collection('adminUsers').doc(uid).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return false;
    return data['active'] != false;
  }

  Future<String> createSupportTicket({
    required String uid,
    required String customerName,
    required String customerPhone,
    required String customerEmail,
    required String subject,
    required String message,
    String contractId = '',
    String priority = 'normal',
  }) async {
    final ref = firestore.collection('supportTickets').doc();
    await ref.set(<String, Object?>{
      'id': ref.id,
      'uid': uid,
      'userId': uid,
      'contractId': contractId.trim(),
      'subject': subject.trim(),
      'message': message.trim(),
      'status': 'open',
      'priority': priority,
      'replies': <Map<String, Object?>>[],
      'customerName': customerName,
      'customerPhone': customerPhone,
      'customerEmail': customerEmail,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<String> submitMissingRequirementResponse({
    required String uid,
    required ContractRecord contract,
    required MissingRequirement requirement,
    required String message,
    String fileName = '',
  }) async {
    final ref = firestore
        .collection('contracts')
        .doc(contract.id)
        .collection('missingResponses')
        .doc();
    await ref.set(<String, Object?>{
      'id': ref.id,
      'uid': uid,
      'userId': uid,
      'contractId': contract.id,
      'missingRequirementId': requirement.id,
      'missingRequirementTitle': requirement.title,
      'message': message.trim(),
      'fileName': fileName.trim(),
      'status': 'pendingAdminReview',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<PropertyRecord> saveProperty({
    required String uid,
    required PropertyData data,
    String propertyId = '',
  }) async {
    final ref = propertyId.trim().isEmpty
        ? firestore.collection('properties').doc()
        : firestore.collection('properties').doc(propertyId.trim());
    final payload = propertyDocumentData(
      propertyId: ref.id,
      uid: uid,
      contractId: '',
      data: data,
    );
    if (propertyId.trim().isEmpty) {
      await ref.set(payload);
    } else {
      await ref.set(<String, Object?>{
        ...payload,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    final snapshot = await ref.get();
    return propertyFromDoc(snapshot);
  }

  Future<void> ensureDemoUserData({
    required String uid,
    required String customerName,
    required String customerPhone,
    required String customerEmail,
  }) async {
    await ensureUserProfile(
      uid: uid,
      phone: customerPhone,
      name: customerName,
      email: customerEmail,
      isDemo: true,
    );
    final existing = await firestore
        .collection('contracts')
        .where('uid', isEqualTo: uid)
        .where('isDemo', isEqualTo: true)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      await _upgradeExistingDemoProperties(uid);
      await _ensureRejectedDemoContract(
        uid: uid,
        customerName: customerName,
        customerPhone: customerPhone,
        customerEmail: customerEmail,
      );
      return;
    }

    final batch = firestore.batch();
    final demos = <_DemoContractSeed>[
      _DemoContractSeed(
        draft: _demoDraft(
          type: ContractType.residential,
          role: UserRole.tenant,
          unitType: 'شقة',
          district: 'الملقا',
          buildingName: 'برج الياسمين',
          lessorName: 'عبدالله العتيبي',
          tenantName: 'محمد القحطاني',
          rentValue: '52000',
        ),
        status: ContractStatus.awaitingPayment,
        paymentStatus: 'pending',
        note: 'الطلب جاهز للدفع. إجمالي الرسوم 398 ريال.',
      ),
      _DemoContractSeed(
        draft: _demoDraft(
          type: ContractType.commercial,
          role: UserRole.authorized,
          unitType: 'محل تجاري',
          district: 'العليا',
          buildingName: 'مركز الواجهة',
          lessorName: 'شركة الواجهة',
          tenantName: 'مؤسسة الرواد',
          rentValue: '84000',
        ),
        status: ContractStatus.missingData,
        paymentStatus: 'paid',
        note: 'توجد ملاحظات مراجعة على بعض بيانات ومستندات العقد.',
        missingRequirements: const <MissingRequirement>[
          MissingRequirement(
            id: 'MR-DEMO-CR',
            title: 'السجل التجاري',
            description:
                'السجل التجاري المرفق غير واضح. يرجى إعادة رفع نسخة واضحة وكاملة.',
            type: 'file',
            issueCode: 'unclear',
            fieldPath: 'draftData.attachments.commercial_registration',
          ),
          MissingRequirement(
            id: 'MR-DEMO-METER',
            title: 'رقم عداد الكهرباء',
            description:
                'تعذر التحقق من رقم عداد الكهرباء. يرجى مراجعته وإدخال القيمة الصحيحة.',
            type: 'field',
            issueCode: 'unverifiable',
            fieldPath: 'draftData.property.electricityMeter',
          ),
        ],
      ),
      _DemoContractSeed(
        draft: _demoDraft(
          type: ContractType.residential,
          role: UserRole.lessor,
          unitType: 'فيلا',
          district: 'النرجس',
          buildingName: 'فيلا النرجس',
          lessorName: 'محمد الدوسري',
          tenantName: 'خالد السالم',
          rentValue: '110000',
        ),
        status: ContractStatus.processing,
        paymentStatus: 'paid',
        note: 'تم السداد والطلب قيد المعالجة.',
      ),
      _DemoContractSeed(
        draft: _demoDraft(
          type: ContractType.residential,
          role: UserRole.lessor,
          unitType: 'شقة',
          district: 'الروضة',
          buildingName: 'شقة الروضة',
          lessorName: 'سعد الدوسري',
          tenantName: 'نورة الشمري',
          rentValue: '46000',
        ),
        status: ContractStatus.authenticated,
        paymentStatus: 'paid',
        note: 'تم إصدار العقد النهائي وإرفاقه للتحميل.',
        finalPdf: true,
      ),
      _DemoContractSeed(
        draft: _demoDraft(
          type: ContractType.commercial,
          role: UserRole.authorized,
          unitType: 'معرض تجاري',
          district: 'العليا',
          buildingName: 'معرض الرياض',
          lessorName: 'شركة الرواد',
          tenantName: 'مؤسسة الخليج',
          rentValue: '72000',
        ),
        status: ContractStatus.rejected,
        paymentStatus: 'notPaid',
        note: '',
        rejectionReason:
            'تعذر التحقق من تطابق بيانات وثيقة الملكية مع بيانات المؤجر.',
      ),
    ];

    for (var i = 0; i < demos.length; i++) {
      final seed = demos[i];
      final contractRef = firestore.collection('contracts').doc();
      final propertyRef = firestore.collection('properties').doc();
      final now = DateTime.now().subtract(Duration(days: i));
      final requestNumber =
          'REQ-DEMO-${(1000 + i + 1).toString().padLeft(4, '0')}';
      final timelineItems = normalizeTimelineForStatus(
        status: seed.status,
        items: initialTimeline(seed.status, now),
        rejectionReason: seed.rejectionReason,
        rejectedAt: now,
      );
      final timeline = timelineItems.map(timelineToMap).toList();
      final total = seed.status == ContractStatus.draft ? 0.0 : 398.0;
      batch.set(contractRef, <String, Object?>{
        'id': contractRef.id,
        'requestNumber': requestNumber,
        'uid': uid,
        'userId': uid,
        'customerName': customerName,
        'customerPhone': customerPhone,
        'customerEmail': customerEmail,
        'type': seed.draft.type.name,
        'role': seed.draft.role.name,
        'status': seed.status.name,
        'title': seed.draft.title,
        'propertyId': propertyRef.id,
        'propertySummary': seed.draft.property.displayAddress,
        'propertyTitle': seed.draft.property.buildingName,
        'city': seed.draft.property.city,
        'district': seed.draft.property.district,
        'lessorSummary': seed.draft.lessor.displayName,
        'tenantSummary': seed.draft.tenant.displayName,
        'contractDetails': contractDetailsFromDraft(seed.draft),
        'partyDetails': partyDetailsFromDraft(seed.draft),
        'propertyDetails': propertyDetailsFromDraft(seed.draft),
        'attachmentFiles': attachmentFilesFromDraft(seed.draft),
        'draftData': draftToMap(seed.draft),
        'totalFees': total,
        'totalPayable': total,
        'ejarPlatformFee': 299,
        'serviceFee': 99,
        'paymentStatus': seed.paymentStatus,
        'adminAssignedTo': '',
        'adminInternalNotes': '',
        'customerVisibleNote': seed.note,
        if (seed.status == ContractStatus.rejected) ...<String, Object?>{
          'rejectionReason': seed.rejectionReason,
          'rejectedAt': FieldValue.serverTimestamp(),
          'rejectedBy': 'demo-system',
        },
        'missingRequirements': seed.missingRequirements
            .map((item) => missingRequirementToMap(item))
            .toList(),
        'finalPdfUrl': seed.finalPdf ? kDemoContractPdfUrl : '',
        'finalPdfFileName': seed.finalPdf ? kDemoContractPdfFileName : '',
        if (seed.finalPdf) 'finalPdfUploadedAt': FieldValue.serverTimestamp(),
        if (seed.finalPdf) 'completedAt': FieldValue.serverTimestamp(),
        'timeline': timeline,
        'isDemo': true,
        if (seed.finalPdf) 'isDemoPayment': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'submittedAt': FieldValue.serverTimestamp(),
      });
      batch.set(
        propertyRef,
        <String, Object?>{
          ...propertyDocumentData(
            propertyId: propertyRef.id,
            uid: uid,
            contractId: contractRef.id,
            data: seed.draft.property,
          ),
          'isDemo': true,
          'demoDataVersion': _demoPropertyDataVersion,
        },
      );
      if (seed.paymentStatus == 'paid') {
        final paymentRef = firestore.collection('payments').doc();
        final invoiceRef = firestore.collection('invoices').doc();
        final paymentReference = 'DEMO-SEED-${paymentRef.id.substring(0, 6)}';
        batch.set(paymentRef, <String, Object?>{
          'id': paymentRef.id,
          'uid': uid,
          'userId': uid,
          'contractId': contractRef.id,
          'amount': 398,
          'currency': 'SAR',
          'ejarPlatformFee': 299,
          'serviceFee': 99,
          'method': 'mada',
          'provider': 'demo',
          'providerReference': paymentReference,
          'cardBrand': 'Mada',
          'cardLast4': '1111',
          'status': 'paid',
          'isDemo': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'paidAt': FieldValue.serverTimestamp(),
        });
        batch.set(invoiceRef, <String, Object?>{
          'id': invoiceRef.id,
          'uid': uid,
          'userId': uid,
          'contractId': contractRef.id,
          'invoiceNumber':
              'INV-DEMO-${invoiceRef.id.substring(0, 6).toUpperCase()}',
          'amount': 398,
          'currency': 'SAR',
          'status': 'paid',
          'paymentId': paymentRef.id,
          'pdfUrl': seed.finalPdf ? kDemoContractPdfUrl : '',
          'isDemo': true,
          'items': <Map<String, Object?>>[
            <String, Object?>{'title': 'رسوم منصة إيجار', 'amount': 299},
            <String, Object?>{'title': 'عمولة عقود برو', 'amount': 99},
          ],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
    await batch.commit();
  }

  Future<void> _ensureRejectedDemoContract({
    required String uid,
    required String customerName,
    required String customerPhone,
    required String customerEmail,
  }) async {
    final existing = await firestore
        .collection('contracts')
        .where('uid', isEqualTo: uid)
        .get();
    final hasRejectedDemo = existing.docs.any((doc) {
      final data = doc.data();
      return data['isDemo'] == true &&
          data['status'] == ContractStatus.rejected.name;
    });
    if (hasRejectedDemo) return;

    const reason =
        'تعذر التحقق من تطابق بيانات وثيقة الملكية مع بيانات المؤجر.';
    final draft = _demoDraft(
      type: ContractType.commercial,
      role: UserRole.authorized,
      unitType: 'معرض تجاري',
      district: 'العليا',
      buildingName: 'معرض الرياض',
      lessorName: 'شركة الرواد',
      tenantName: 'مؤسسة الخليج',
      rentValue: '72000',
    );
    final now = DateTime.now();
    final contractRef =
        firestore.collection('contracts').doc('demo-rejected-$uid');
    final propertyRef =
        firestore.collection('properties').doc('demo-rejected-$uid');
    final suffix = uid.length <= 6 ? uid : uid.substring(uid.length - 6);
    final timeline = normalizeTimelineForStatus(
      status: ContractStatus.rejected,
      items: initialTimeline(ContractStatus.rejected, now),
      rejectionReason: reason,
      rejectedAt: now,
    ).map(timelineToMap).toList();
    final batch = firestore.batch();
    batch.set(contractRef, <String, Object?>{
      'id': contractRef.id,
      'requestNumber': 'REQ-DEMO-${suffix.toUpperCase()}',
      'uid': uid,
      'userId': uid,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'customerEmail': customerEmail,
      'type': draft.type.name,
      'role': draft.role.name,
      'status': ContractStatus.rejected.name,
      'title': draft.title,
      'propertyId': propertyRef.id,
      'propertySummary': draft.property.displayAddress,
      'propertyTitle': draft.property.buildingName,
      'city': draft.property.city,
      'district': draft.property.district,
      'lessorSummary': draft.lessor.displayName,
      'tenantSummary': draft.tenant.displayName,
      'contractDetails': contractDetailsFromDraft(draft),
      'partyDetails': partyDetailsFromDraft(draft),
      'propertyDetails': propertyDetailsFromDraft(draft),
      'attachmentFiles': attachmentFilesFromDraft(draft),
      'draftData': draftToMap(draft),
      'totalFees': 398,
      'totalPayable': 398,
      'ejarPlatformFee': 299,
      'serviceFee': 99,
      'paymentStatus': 'notPaid',
      'adminAssignedTo': '',
      'adminInternalNotes': '',
      'customerVisibleNote': '',
      'rejectionReason': reason,
      'rejectedAt': FieldValue.serverTimestamp(),
      'rejectedBy': 'demo-system',
      'missingRequirements': <Map<String, Object?>>[],
      'finalPdfUrl': '',
      'finalPdfFileName': '',
      'timeline': timeline,
      'isDemo': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'submittedAt': FieldValue.serverTimestamp(),
    });
    batch.set(propertyRef, <String, Object?>{
      ...propertyDocumentData(
        propertyId: propertyRef.id,
        uid: uid,
        contractId: contractRef.id,
        data: draft.property,
      ),
      'isDemo': true,
      'demoDataVersion': _demoPropertyDataVersion,
    });
    await batch.commit();
  }

  Future<void> _upgradeExistingDemoProperties(String uid) async {
    final snapshot = await firestore
        .collection('properties')
        .where('uid', isEqualTo: uid)
        .get();
    final batch = firestore.batch();
    var hasUpdates = false;
    var demoIndex = 0;

    for (final doc in snapshot.docs) {
      final raw = doc.data();
      if (raw['isDemo'] != true) continue;
      final currentVersion = (raw['demoDataVersion'] as num?)?.toInt() ?? 0;
      if (currentVersion >= _demoPropertyDataVersion) continue;

      final source = propertyFromDoc(doc).data!;
      final suffix = (demoIndex + 1).toString().padLeft(2, '0');
      final unitNumber = _demoText(source.unitNumber, '${demoIndex + 1}');
      final unitType = _demoText(source.unitType, 'شقة');
      final completed = PropertyData(
        propertySource: 'عقار محفوظ',
        ownershipDocumentNumber: _demoText(
          source.ownershipDocumentNumber,
          '3101234567$suffix',
        ),
        ownershipDocumentType: _demoText(
          source.ownershipDocumentType,
          'صك إلكتروني',
        ),
        ownershipDocumentDate: _demoText(
          source.ownershipDocumentDate,
          '2026/06/20',
        ),
        propertyUsage: _demoText(source.propertyUsage, 'سكن عوائل'),
        propertyType: _demoText(source.propertyType, 'عمارة'),
        floorsCount: _demoPositiveInteger(source.floorsCount, '1'),
        unitsPerFloor: _demoPositiveInteger(source.unitsPerFloor, '1'),
        totalUnits: _demoPositiveInteger(source.totalUnits, '1'),
        city: _demoText(source.city, 'الرياض'),
        district: _demoText(source.district, 'حي النموذج'),
        street: _demoText(source.street, 'طريق الملك فهد'),
        buildingNumber: _demoFixedDigits(
          source.buildingNumber,
          4,
          '78$suffix',
        ),
        additionalNumber: _demoFixedDigits(
          source.additionalNumber,
          4,
          '45$suffix',
        ),
        postalCode: _demoFixedDigits(
          source.postalCode,
          5,
          '133$suffix',
        ),
        buildingName: _demoText(source.buildingName, 'عقار تجريبي'),
        unitNumber: unitNumber,
        unitName: _demoText(source.unitName, '$unitType $unitNumber'),
        unitType: unitType,
        floor: _demoText(source.floor, '1'),
        area: _demoPositiveNumber(source.area, '120'),
        roomsCount: _demoPositiveInteger(source.roomsCount, '3'),
        bathroomsCount: _demoPositiveInteger(source.bathroomsCount, '2'),
        hallsCount: _demoNonNegativeInteger(source.hallsCount, '1'),
        maidRoom: source.maidRoom,
        kitchen: source.kitchen,
        storage: source.storage,
        majlis: source.majlis,
        furnishingStatus: _demoText(
          source.furnishingStatus,
          'غير مؤثثة',
        ),
        acWindow: source.acWindow,
        acSplit: source.acSplit || (!source.acWindow && !source.acCentral),
        acCentral: source.acCentral,
        privateParking: source.privateParking,
        electricityMeter: _demoPositiveInteger(
          source.electricityMeter,
          '7002001$suffix',
        ),
        waterMeter: _demoPositiveInteger(
          source.waterMeter,
          '7102001$suffix',
        ),
        gasMeter: _demoPositiveInteger(
          source.gasMeter,
          '7202001$suffix',
        ),
        notes: _demoText(
          source.notes,
          'بيانات عقار مكتملة للعرض في النسخة التجريبية.',
        ),
      );
      final payload = propertyDocumentData(
        propertyId: doc.id,
        uid: uid,
        contractId: _textFromAny(raw['sourceContractId']),
        data: completed,
      )
        ..remove('createdAt')
        ..['isDemo'] = true
        ..['demoDataVersion'] = _demoPropertyDataVersion;
      batch.set(doc.reference, payload, SetOptions(merge: true));
      hasUpdates = true;
      demoIndex++;
    }

    if (hasUpdates) await batch.commit();
  }

  static String _demoText(String value, String fallback) {
    final text = value.trim();
    return text.isEmpty || text == '-' ? fallback : text;
  }

  static String _demoPositiveInteger(String value, String fallback) {
    final parsed = int.tryParse(value.trim());
    return parsed != null && parsed > 0 ? parsed.toString() : fallback;
  }

  static String _demoNonNegativeInteger(String value, String fallback) {
    final parsed = int.tryParse(value.trim());
    return parsed != null && parsed >= 0 ? parsed.toString() : fallback;
  }

  static String _demoPositiveNumber(String value, String fallback) {
    final parsed = double.tryParse(value.trim().replaceAll(',', ''));
    return parsed != null && parsed > 0 ? value.trim() : fallback;
  }

  static String _demoFixedDigits(
    String value,
    int length,
    String fallback,
  ) {
    final text = value.trim();
    return RegExp('^\\d{$length}\$').hasMatch(text) ? text : fallback;
  }

  Map<String, Object?> notificationData({
    required String uid,
    required String contractId,
    required String title,
    required String body,
    required String type,
    String priority = 'normal',
    Map<String, bool>? channels,
    Map<String, Object?>? actionPayload,
  }) {
    return <String, Object?>{
      'uid': uid,
      'contractId': contractId,
      'title': title,
      'body': body,
      'type': type,
      'read': false,
      'actionType': 'contractDetails',
      'actionPayload':
          actionPayload ?? <String, Object?>{'contractId': contractId},
      'channels': channels ?? notificationChannels(type),
      'priority': priority,
      'delivery': <String, Object?>{
        'pushStatus': 'pending',
        'error': '',
      },
      'createdAt': FieldValue.serverTimestamp(),
      'readAt': null,
      'sentAt': null,
    };
  }

  Map<String, bool> notificationChannels(String type) {
    return <String, bool>{
      'inApp': true,
      'push': type != 'draftSaved',
    };
  }

  String notificationTypeForStatus(ContractStatus status) {
    return switch (status) {
      ContractStatus.awaitingPayment => 'awaitingPayment',
      ContractStatus.missingData => 'missingRequirement',
      ContractStatus.processing => 'processing',
      ContractStatus.authenticated => 'authenticated',
      ContractStatus.rejected => 'rejected',
      ContractStatus.draft => 'draftSaved',
    };
  }

  Future<DemoPaymentResult> submitDemoPayment({
    required ContractRecord contract,
    required String uid,
    required DemoPaymentMethod method,
    required String cardBrand,
    required String cardLast4,
    required bool success,
  }) async {
    const total = 398.0;
    const ejarFee = 299.0;
    const serviceFee = 99.0;
    final now = DateTime.now();
    final paymentRef = firestore.collection('payments').doc();
    final invoiceRef = firestore.collection('invoices').doc();
    final providerReference = 'DEMO-${now.millisecondsSinceEpoch}';
    final invoiceNumber =
        'INV-${now.year}${now.month.toString().padLeft(2, '0')}-${invoiceRef.id.substring(0, 6).toUpperCase()}';
    final paymentPayload = <String, Object?>{
      'id': paymentRef.id,
      'uid': uid,
      'userId': uid,
      'contractId': contract.id,
      'amount': total,
      'currency': 'SAR',
      'ejarPlatformFee': ejarFee,
      'serviceFee': serviceFee,
      'method': method.code,
      'provider': 'demo',
      'providerReference': providerReference,
      'cardBrand': cardBrand,
      'cardLast4': cardLast4,
      'status': success ? 'paid' : 'failed',
      'failureReason': success ? '' : 'تعذر إتمام عملية الدفع التجريبية',
      'isDemo': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (success) 'paidAt': FieldValue.serverTimestamp(),
    };

    final batch = firestore.batch();
    batch.set(paymentRef, paymentPayload);

    if (!success) {
      await batch.commit();
      return DemoPaymentResult(
        success: false,
        paymentId: paymentRef.id,
        providerReference: providerReference,
        failureReason: 'تعذر إتمام عملية الدفع التجريبية',
      );
    }

    final invoicePayload = <String, Object?>{
      'id': invoiceRef.id,
      'uid': uid,
      'userId': uid,
      'contractId': contract.id,
      'invoiceNumber': invoiceNumber,
      'amount': total,
      'currency': 'SAR',
      'status': 'paid',
      'paymentId': paymentRef.id,
      'pdfUrl': kDemoContractPdfUrl,
      'isDemo': true,
      'items': <Map<String, Object?>>[
        <String, Object?>{'title': 'رسوم منصة إيجار', 'amount': ejarFee},
        <String, Object?>{'title': 'رسوم الخدمة', 'amount': serviceFee},
      ],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final paymentTimeline = <String, Object?>{
      'title': 'تم الدفع',
      'subtitle': 'تم استلام رسوم الطلب بنجاح.',
      'description': 'تم استلام رسوم الطلب بنجاح.',
      'status': ContractStatus.processing.name,
      'date': _dateLabel(now),
      'time': _timeLabel(now),
      'completed': true,
      'current': false,
      'createdAt': FieldValue.serverTimestamp(),
    };
    final reviewTimeline = <String, Object?>{
      'title': 'قيد المعالجة',
      'subtitle': 'تمت محاكاة معالجة الطلب تلقائيًا في نسخة العرض.',
      'description': 'تمت محاكاة معالجة الطلب تلقائيًا في نسخة العرض.',
      'status': ContractStatus.processing.name,
      'date': _dateLabel(now),
      'time': _timeLabel(now),
      'completed': true,
      'current': false,
      'createdAt': FieldValue.serverTimestamp(),
    };
    final completedTimeline = <String, Object?>{
      'title': 'مكتمل',
      'subtitle': 'تم إصدار نموذج عقد تجريبي للمعاينة.',
      'description': 'تم إصدار نموذج عقد تجريبي للمعاينة.',
      'status': ContractStatus.authenticated.name,
      'date': _dateLabel(now),
      'time': _timeLabel(now),
      'completed': true,
      'current': false,
      'createdAt': FieldValue.serverTimestamp(),
    };

    batch.set(invoiceRef, invoicePayload);
    batch.update(
        firestore.collection('contracts').doc(contract.id), <String, Object?>{
      'status': ContractStatus.authenticated.name,
      'paymentStatus': 'paid',
      'paidAt': FieldValue.serverTimestamp(),
      'totalFees': total,
      'totalPayable': total,
      'ejarPlatformFee': ejarFee,
      'serviceFee': serviceFee,
      'paymentId': paymentRef.id,
      'invoiceId': invoiceRef.id,
      'invoiceNumber': invoiceNumber,
      'paymentMethod': method.code,
      'paymentProvider': 'demo',
      'paymentProviderReference': providerReference,
      'cardBrand': cardBrand,
      'cardLast4': cardLast4,
      'isDemoPayment': true,
      'finalPdfUrl': kDemoContractPdfUrl,
      'finalPdfFileName': kDemoContractPdfFileName,
      'finalPdfUploadedAt': FieldValue.serverTimestamp(),
      'completedAt': FieldValue.serverTimestamp(),
      'customerVisibleNote':
          'تمت محاكاة الدفع ومعالجة الطلب تلقائيًا لأغراض العرض، وأصبح نموذج العقد التجريبي جاهزًا للمعاينة.',
      'updatedAt': FieldValue.serverTimestamp(),
      'timeline': FieldValue.arrayUnion(<Map<String, Object?>>[
        paymentTimeline,
        reviewTimeline,
        completedTimeline,
      ]),
    });
    batch.set(
      firestore.collection('notifications').doc(),
      notificationData(
        uid: uid,
        contractId: contract.id,
        title: 'اكتمل الطلب التجريبي',
        body:
            'تم الدفع التجريبي ومحاكاة معالجة الطلب تلقائيًا، وأصبح نموذج العقد جاهزًا للمعاينة.',
        type: 'payment',
        priority: 'normal',
        channels: const <String, bool>{'inApp': true, 'push': true},
      ),
    );
    await batch.commit();
    return DemoPaymentResult(
      success: true,
      paymentId: paymentRef.id,
      invoiceId: invoiceRef.id,
      invoiceNumber: invoiceNumber,
      providerReference: providerReference,
    );
  }

  Future<ContractRecord> submitContract({
    required String uid,
    required String customerName,
    required String customerPhone,
    required String customerEmail,
    required ContractDraft draft,
    required ContractStatus status,
    String existingDraftId = '',
    DraftProgress progress = const DraftProgress(),
  }) async {
    if (existingDraftId.trim().isNotEmpty) {
      return _updateExistingDraft(
        contractId: existingDraftId.trim(),
        uid: uid,
        draft: draft,
        status: status,
        progress: progress,
      );
    }
    final now = DateTime.now();
    final doc = firestore.collection('contracts').doc();
    final shouldCreateProperty = status != ContractStatus.draft &&
        draft.property.propertySource.trim() == 'إضافة عقار جديد';
    final propertyRef =
        shouldCreateProperty ? firestore.collection('properties').doc() : null;
    final propertyId = propertyRef?.id ?? '';
    final requestNumber =
        'REQ-${now.year}-${doc.id.substring(0, 6).toUpperCase()}';
    final timeline = initialTimeline(status, now);
    final role = roleFromDraft(draft);
    final record = ContractRecord(
      id: doc.id,
      requestNumber: requestNumber,
      uid: uid,
      type: draft.type,
      role: role,
      title: draft.title,
      property: draft.property.displayAddress,
      lessorName: draft.lessor.displayName,
      tenantName: draft.tenant.displayName,
      date: _dateLabel(now),
      status: status,
      totalFees: status == ContractStatus.draft ? 0 : draft.totalPayable,
      timeline: timeline,
      contractDetails: contractDetailsFromDraft(draft),
      partyDetails: partyDetailsFromDraft(draft),
      propertyDetails: propertyDetailsFromDraft(draft),
      attachmentFiles: attachmentFilesFromDraft(draft),
      draftData: ContractDraft.copyOf(draft),
      draftProgress: progress,
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
      'role': role.name,
      'status': status.name,
      'title': draft.title,
      'propertySummary': draft.property.displayAddress,
      if (propertyId.isNotEmpty) 'propertyId': propertyId,
      'propertyTitle': draft.property.buildingName.trim().isEmpty
          ? draft.property.propertyType
          : draft.property.buildingName.trim(),
      'city': draft.property.city,
      'district': draft.property.district,
      'lessorSummary': draft.lessor.displayName,
      'tenantSummary': draft.tenant.displayName,
      'contractDetails': contractDetailsFromDraft(draft),
      'partyDetails': partyDetailsFromDraft(draft),
      'propertyDetails': propertyDetailsFromDraft(draft),
      'attachmentFiles': attachmentFilesFromDraft(draft),
      'draftData': draftToMap(draft),
      'draftProgress': draftProgressToMap(progress),
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
    if (propertyRef != null) {
      batch.set(
        propertyRef,
        propertyDocumentData(
          propertyId: propertyId,
          uid: uid,
          contractId: doc.id,
          data: draft.property,
        ),
      );
    }
    await batch.commit();
    return record;
  }

  Future<ContractRecord> _updateExistingDraft({
    required String contractId,
    required String uid,
    required ContractDraft draft,
    required ContractStatus status,
    required DraftProgress progress,
  }) async {
    if (status != ContractStatus.draft &&
        status != ContractStatus.awaitingPayment) {
      throw ArgumentError('لا يمكن نقل المسودة إلى الحالة المطلوبة.');
    }
    final contractRef = firestore.collection('contracts').doc(contractId);
    final propertyRef = status == ContractStatus.awaitingPayment &&
            draft.property.propertySource.trim() == 'إضافة عقار جديد'
        ? firestore.collection('properties').doc()
        : null;
    await firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(contractRef);
      final current = snapshot.data();
      if (current == null) {
        throw StateError('المسودة غير موجودة.');
      }
      if ((current['uid'] as String?) != uid ||
          (current['status'] as String?) != ContractStatus.draft.name) {
        throw StateError('لا يمكن تعديل هذه المسودة أو أنها أُرسلت مسبقًا.');
      }
      final isSubmitting = status == ContractStatus.awaitingPayment;
      final shouldCreateProperty = isSubmitting &&
          propertyRef != null &&
          ((current['propertyId'] as String?) ?? '').trim().isEmpty;
      final role = roleFromDraft(draft);
      final update = <String, Object?>{
        'type': draft.type.name,
        'role': role.name,
        'title': draft.title,
        'propertySummary': draft.property.displayAddress,
        'propertyTitle': draft.property.buildingName.trim().isEmpty
            ? draft.property.propertyType
            : draft.property.buildingName.trim(),
        'city': draft.property.city,
        'district': draft.property.district,
        'lessorSummary': draft.lessor.displayName,
        'tenantSummary': draft.tenant.displayName,
        'contractDetails': contractDetailsFromDraft(draft),
        'partyDetails': partyDetailsFromDraft(draft),
        'propertyDetails': propertyDetailsFromDraft(draft),
        'attachmentFiles': attachmentFilesFromDraft(draft),
        'draftData': draftToMap(draft),
        'draftProgress': draftProgressToMap(progress),
        'totalFees': isSubmitting ? draft.totalPayable : 0,
        'updatedAt': FieldValue.serverTimestamp(),
        if (isSubmitting) ...<String, Object?>{
          'status': ContractStatus.awaitingPayment.name,
          'paymentStatus': 'pending',
          'submittedAt': FieldValue.serverTimestamp(),
          'customerVisibleNote': '',
          'timeline': FieldValue.arrayUnion(<Map<String, Object?>>[
            timelineToMap(
              timelineEventFor(
                ContractStatus.awaitingPayment,
                DateTime.now(),
                'تم إرسال المسودة بنجاح وأصبح الطلب جاهزًا للدفع.',
              ),
            ),
          ]),
          if (shouldCreateProperty) 'propertyId': propertyRef.id,
        },
      };
      transaction.update(contractRef, update);
      if (shouldCreateProperty) {
        final newPropertyRef = propertyRef;
        transaction.set(
          newPropertyRef,
          propertyDocumentData(
            propertyId: newPropertyRef.id,
            uid: uid,
            contractId: contractId,
            data: draft.property,
          ),
        );
      }
    });
    final updated = await contractRef.get();
    return contractFromDoc(updated);
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
      final currentStatus = _contractStatus((data['status'] as String?) ?? '');
      final note = customerNote.trim();
      validateAdminStatusTransition(
        currentStatus: currentStatus,
        nextStatus: status,
        customerNote: note,
      );
      final title = (data['title'] as String?) ?? 'طلب العقد';
      final event = timelineEventFor(status, DateTime.now(), note);
      transaction.update(ref, <String, Object?>{
        'status': status.name,
        'customerVisibleNote': status == ContractStatus.rejected ? '' : note,
        'updatedAt': FieldValue.serverTimestamp(),
        if (status == ContractStatus.rejected) ...<String, Object?>{
          'rejectionReason': note,
          'rejectedAt': FieldValue.serverTimestamp(),
          'rejectedBy': adminUid,
        },
        if (status == ContractStatus.authenticated)
          'completedAt': FieldValue.serverTimestamp(),
        'timeline': FieldValue.arrayUnion(<Map<String, Object?>>[
          timelineToMap(event),
        ]),
      });
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
          if (status == ContractStatus.rejected) 'reason': note,
          'createdAt': FieldValue.serverTimestamp(),
        },
      );
    });
  }

  static void validateAdminStatusTransition({
    required ContractStatus currentStatus,
    required ContractStatus nextStatus,
    String customerNote = '',
  }) {
    if (currentStatus == ContractStatus.rejected) {
      throw StateError('الطلب مرفوض نهائيًا ولا يمكن تغيير حالته.');
    }
    if (nextStatus != ContractStatus.rejected) return;
    if (currentStatus == ContractStatus.draft ||
        currentStatus == ContractStatus.authenticated) {
      throw StateError('لا يمكن رفض مسودة أو عقد مكتمل.');
    }
    if (customerNote.trim().isEmpty) {
      throw ArgumentError('يجب كتابة سبب واضح لرفض الطلب.');
    }
  }

  Future<void> addMissingRequirement({
    required String contractId,
    required String uid,
    required String title,
    required String description,
    required String type,
    required String issueCode,
    required String fieldPath,
    required String adminUid,
  }) async {
    await _ensureContractIsNotRejected(contractId);
    if (title.trim().isEmpty || description.trim().isEmpty) {
      throw ArgumentError('يجب تحديد المتطلب وصياغة ملاحظة واضحة للعميل.');
    }
    if (issueCode != MissingReviewIssue.additionalDocument.code &&
        containsIllogicalMissingClaim(description)) {
      throw ArgumentError(
        'لا يمكن وصف متطلب إجباري بأنه غير مرفق أو غير مكتمل بعد إرسال العقد.',
      );
    }
    final item = <String, Object?>{
      'id': firestore.collection('_').doc().id,
      'title': title,
      'description': description,
      'type': type,
      'issueCode': issueCode,
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
    batch.set(
      firestore.collection('notifications').doc(),
      notificationData(
        uid: uid,
        contractId: contractId,
        title: 'يوجد نقص مطلوب في طلبك',
        body: description,
        type: 'missingRequirement',
        priority: 'high',
      ),
    );
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
    await _ensureContractIsNotRejected(contractId);
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
    batch.set(
      firestore.collection('notifications').doc(),
      notificationData(
        uid: uid,
        contractId: contractId,
        title: 'تم إصدار العقد النهائي',
        body: 'يمكنك الآن تحميل ملف العقد النهائي من تفاصيل الطلب.',
        type: 'finalPdfUploaded',
        priority: 'high',
      ),
    );
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

  Future<void> _ensureContractIsNotRejected(String contractId) async {
    final snapshot =
        await firestore.collection('contracts').doc(contractId).get();
    final status = (snapshot.data()?['status'] as String?) ?? '';
    if (status == ContractStatus.rejected.name) {
      throw StateError('الطلب مرفوض نهائيًا ولا يمكن تنفيذ هذا الإجراء.');
    }
  }

  ContractRecord contractFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final type = _contractType((data['type'] as String?) ?? '');
    final status = _contractStatus((data['status'] as String?) ?? '');
    final customerVisibleNote = _readableText(data['customerVisibleNote'], '');
    final rejectionReason = _readableText(
      data['rejectionReason'],
      status == ContractStatus.rejected ? customerVisibleNote : '',
    );
    final rejectedAt = _dateTimeFromAny(data['rejectedAt']);
    final rawTimeline = ((data['timeline'] as List?) ?? const <Object?>[])
        .whereType<Map>()
        .map((item) => timelineFromMap(Map<String, dynamic>.from(item)))
        .toList();
    final timeline = normalizeTimelineForStatus(
      status: status,
      items: rawTimeline,
      rejectionReason: rejectionReason,
      rejectedAt: rejectedAt,
    );
    final defaultTitle =
        type == ContractType.commercial ? 'طلب عقد تجاري' : 'طلب عقد سكني';
    return ContractRecord(
      id: doc.id,
      requestNumber: (data['requestNumber'] as String?) ?? doc.id,
      uid: (data['uid'] as String?) ?? '',
      type: type,
      role: _userRole((data['role'] as String?) ?? ''),
      title: _readableText(data['title'], defaultTitle),
      property: _readableText(data['propertySummary'], 'عقار غير محدد'),
      lessorName: _readableText(data['lessorSummary'], 'مالك غير محدد'),
      tenantName: _readableText(data['tenantSummary'], 'مستأجر غير محدد'),
      date: _dateFromAny(data['createdAt']),
      status: status,
      totalFees: ((data['totalFees'] as num?) ?? 0).toDouble(),
      timeline: timeline,
      customerVisibleNote: customerVisibleNote,
      rejectionReason: rejectionReason,
      rejectedAt: rejectedAt,
      rejectedBy: _readableText(data['rejectedBy'], ''),
      finalPdfUrl: (data['finalPdfUrl'] as String?) ?? '',
      finalPdfFileName: _readableText(data['finalPdfFileName'], ''),
      missingRequirements:
          ((data['missingRequirements'] as List?) ?? const <Object?>[])
              .whereType<Map>()
              .map((item) =>
                  missingRequirementFromMap(Map<String, dynamic>.from(item)))
              .toList(),
      paymentStatus: (data['paymentStatus'] as String?) ?? '',
      paymentId: (data['paymentId'] as String?) ?? '',
      invoiceId: (data['invoiceId'] as String?) ?? '',
      invoiceNumber: (data['invoiceNumber'] as String?) ?? '',
      paymentMethod: (data['paymentMethod'] as String?) ?? '',
      paymentProvider: (data['paymentProvider'] as String?) ?? '',
      paymentReference: (data['paymentProviderReference'] as String?) ??
          (data['providerReference'] as String?) ??
          '',
      cardBrand: (data['cardBrand'] as String?) ?? '',
      cardLast4: (data['cardLast4'] as String?) ?? '',
      paidAt: data['paidAt'] == null ? '' : _dateFromAny(data['paidAt']),
      isDemo: data['isDemo'] == true,
      contractDetails: _readableStringMap(data['contractDetails']),
      partyDetails: _readableStringMap(data['partyDetails']),
      propertyDetails: _readableStringMap(data['propertyDetails']),
      attachmentFiles: _readableStringMap(data['attachmentFiles']),
      draftData: draftFromMap(data['draftData']),
      draftProgress: draftProgressFromMap(data['draftProgress']),
    );
  }

  PropertyRecord propertyFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final address = data['address'] is Map
        ? Map<String, dynamic>.from(data['address'] as Map)
        : <String, dynamic>{};
    final ownership = data['ownership'] is Map
        ? Map<String, dynamic>.from(data['ownership'] as Map)
        : <String, dynamic>{};
    final units = ((data['units'] as List?) ?? const <Object?>[])
        .whereType<Map>()
        .map((unit) => unitFromMap(Map<String, dynamic>.from(unit)))
        .toList();
    final unitMaps = ((data['units'] as List?) ?? const <Object?>[])
        .whereType<Map>()
        .map((unit) => Map<String, dynamic>.from(unit))
        .toList();
    final firstUnit = unitMaps.isEmpty ? null : unitMaps.first;
    final floors = ((data['floors'] as num?) ?? 1).toInt();
    final unitsPerFloor = ((data['unitsPerFloor'] as num?) ?? 1).toInt();
    final totalUnits = ((data['totalUnits'] as num?) ?? 1).toInt();
    final details = PropertyData(
      propertySource: 'عقار محفوظ',
      ownershipDocumentType:
          _readableText(ownership['documentType'], 'صك إلكتروني'),
      ownershipDocumentNumber: _readableText(ownership['documentNumber'], ''),
      ownershipDocumentDate: _readableText(ownership['documentDate'], ''),
      propertyUsage: _readableText(data['usage'], 'سكن عوائل'),
      propertyType: _readableText(data['type'], 'عمارة'),
      floorsCount: floors.toString(),
      unitsPerFloor: unitsPerFloor.toString(),
      totalUnits: totalUnits.toString(),
      city: _readableText(address['city'] ?? data['city'], 'الرياض'),
      district: _readableText(address['district'] ?? data['district'], ''),
      street: _readableText(address['street'], ''),
      buildingNumber: _readableText(address['buildingNumber'], ''),
      additionalNumber: _readableText(address['additionalNumber'], ''),
      postalCode: _readableText(address['postalCode'], ''),
      buildingName: _readableText(data['title'], ''),
      unitNumber: _readableText(firstUnit?['number'], ''),
      unitName: _readableText(firstUnit?['name'], ''),
      unitType: _readableText(firstUnit?['type'], 'شقة'),
      floor: _readableText(firstUnit?['floor'], ''),
      area: _readableText(firstUnit?['area'], ''),
      roomsCount: _readableText(firstUnit?['roomsCount'], ''),
      bathroomsCount: _readableText(firstUnit?['bathroomsCount'], ''),
      hallsCount: _readableText(firstUnit?['hallsCount'], ''),
      maidRoom: firstUnit?['maidRoom'] == true,
      kitchen: firstUnit?['kitchen'] != false,
      storage: firstUnit?['storage'] == true,
      majlis: firstUnit?['majlis'] == true,
      furnishingStatus: _readableText(
        firstUnit?['furnishingStatus'],
        'غير مؤثثة',
      ),
      privateParking: firstUnit?['privateParking'] == true,
      electricityMeter: _readableText(firstUnit?['electricityMeter'], ''),
      waterMeter: _readableText(firstUnit?['waterMeter'], ''),
      gasMeter: _readableText(firstUnit?['gasMeter'], ''),
      acWindow: firstUnit?['acWindow'] == true,
      acSplit: firstUnit?['acSplit'] != false,
      acCentral: firstUnit?['acCentral'] == true,
      notes: _readableText(firstUnit?['notes'], ''),
    );
    return PropertyRecord(
      id: doc.id,
      title: _readableText(data['title'], 'عقار'),
      city: _readableText(data['city'], 'الرياض'),
      district: _readableText(data['district'], ''),
      type: _readableText(data['type'], 'عمارة'),
      usage: _readableText(data['usage'], 'سكن عوائل'),
      floors: floors,
      totalUnits: totalUnits,
      units: units,
      data: details,
    );
  }

  UnitRecord unitFromMap(Map<String, dynamic> data) {
    return UnitRecord(
      number: _readableText(data['number'], '1'),
      name: _readableText(data['name'], 'وحدة'),
      type: _readableText(data['type'], 'شقة'),
      floor: _readableText(data['floor'], '1'),
      area: _readableText(data['area'], ''),
      status: _readableText(data['status'], 'متاحة'),
    );
  }

  NotificationItem notificationFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final type = (data['type'] as String?) ?? 'general';
    final fallbackTitle = _notificationFallbackTitle(type);
    final fallbackBody = _notificationFallbackBody(type);
    final status = _statusForNotificationType(type);
    final channels = (data['channels'] as Map?) ?? const <Object?, Object?>{};
    final actionPayload =
        (data['actionPayload'] as Map?) ?? const <Object?, Object?>{};
    final delivery = (data['delivery'] as Map?) ?? const <Object?, Object?>{};
    return NotificationItem(
      id: doc.id,
      contractId: (data['contractId'] as String?) ??
          (actionPayload['contractId'] as String?) ??
          '',
      title: _readableText(data['title'], fallbackTitle),
      body: _readableText(data['body'], fallbackBody),
      time: _dateFromAny(data['createdAt']),
      createdAt: _dateTimeFromAny(data['createdAt']),
      type: type,
      actionType: (data['actionType'] as String?) ?? '',
      actionPayload: Map<String, dynamic>.from(actionPayload),
      channels: channels.map(
        (key, value) => MapEntry('$key', value == true),
      ),
      priority: (data['priority'] as String?) ?? 'normal',
      readAt: _dateTimeFromAny(data['readAt']),
      sentAt: _dateTimeFromAny(data['sentAt']),
      delivery: Map<String, dynamic>.from(delivery),
      icon: status.icon,
      color: status.color,
      read: (data['read'] as bool?) ?? false,
    );
  }

  SupportTicketRecord supportTicketFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final replies = ((data['replies'] as List?) ?? const <Object?>[])
        .whereType<Map>()
        .map((item) => supportReplyFromMap(Map<String, dynamic>.from(item)))
        .where((reply) => reply.visibility != 'admin')
        .toList();
    return SupportTicketRecord(
      id: doc.id,
      contractId: (data['contractId'] as String?) ?? '',
      subject: _readableText(data['subject'], 'تذكرة دعم'),
      message: _readableText(data['message'], ''),
      status: (data['status'] as String?) ?? 'open',
      priority: (data['priority'] as String?) ?? 'normal',
      createdAt: _dateTimeFromAny(data['createdAt']),
      replies: replies,
    );
  }

  SupportReplyRecord supportReplyFromMap(Map<String, dynamic> data) {
    return SupportReplyRecord(
      id: (data['id'] as String?) ?? '',
      message: _readableText(data['message'], ''),
      createdByName: _readableText(data['createdByName'], 'الدعم'),
      visibility: (data['visibility'] as String?) ?? 'customer',
      createdAt: _dateTimeFromAny(data['createdAt']),
    );
  }

  static Map<String, Object?> missingRequirementToMap(
    MissingRequirement item,
  ) {
    return <String, Object?>{
      'id': item.id,
      'title': item.title,
      'description': item.description,
      'type': item.type,
      'issueCode': item.issueCode,
      'fieldPath': item.fieldPath,
      'required': item.required,
      'resolved': item.resolved,
    };
  }

  static ContractDraft _demoDraft({
    required ContractType type,
    required UserRole role,
    required String unitType,
    required String district,
    required String buildingName,
    required String lessorName,
    required String tenantName,
    required String rentValue,
  }) {
    final draft = ContractDraft()
      ..type = type
      ..role = role
      ..startDate = '2026/07/01'
      ..endDate = '2027/06/30'
      ..rentValue = rentValue
      ..firstPaymentDate = '2026/07/01'
      ..paymentCount = 4
      ..lessor.fullName = lessorName
      ..lessor.idNumber = '1012345678'
      ..lessor.mobile = '0500000001'
      ..lessor.birthDate = '1985/01/01'
      ..tenant.fullName = tenantName
      ..tenant.idNumber = '1023456789'
      ..tenant.mobile = '0500000002'
      ..tenant.birthDate = '1990/02/02';
    draft.property
      ..propertySource = 'إضافة عقار جديد'
      ..ownershipDocumentNumber = '310123456789'
      ..ownershipDocumentType = 'صك إلكتروني'
      ..ownershipDocumentDate = '2026/06/20'
      ..propertyUsage = type == ContractType.residential ? 'سكن عوائل' : 'تجاري'
      ..propertyType = unitType == 'فيلا' ? 'فيلا' : 'عمارة'
      ..floorsCount = '4'
      ..unitsPerFloor = '2'
      ..totalUnits = '8'
      ..city = 'الرياض'
      ..district = district
      ..street = 'طريق الملك فهد'
      ..buildingNumber = '7788'
      ..additionalNumber = '4455'
      ..postalCode = '13321'
      ..buildingName = buildingName
      ..unitNumber = '12'
      ..unitName = unitType
      ..unitType = unitType
      ..floor = '2'
      ..area = '145'
      ..roomsCount = type == ContractType.residential ? '3' : '1'
      ..bathroomsCount = '2'
      ..hallsCount = '1'
      ..maidRoom = type == ContractType.residential
      ..kitchen = true
      ..storage = true
      ..majlis = type == ContractType.residential
      ..furnishingStatus = 'غير مؤثثة'
      ..acWindow = false
      ..acSplit = true
      ..acCentral = type == ContractType.commercial
      ..privateParking = true
      ..electricityMeter = '700200101'
      ..waterMeter = '710200101'
      ..gasMeter = '720200101'
      ..notes = 'بيانات عقار مكتملة للعرض في النسخة التجريبية.';
    for (final attachment in draft.attachments) {
      if (attachment.required ||
          attachment.keyName == 'commercial_registration' &&
              type == ContractType.commercial) {
        attachment.uploaded = true;
        attachment.fileName = '${attachment.keyName}_demo.pdf';
        attachment.sizeLabel = '420 KB';
      }
    }
    draft.regenerateInstallments();
    return draft;
  }

  static Map<String, Object?> draftToMap(ContractDraft draft) {
    return <String, Object?>{
      'type': draft.type.name,
      'role': roleFromDraft(draft).name,
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
        'brokerageFee': draft.brokerageFee,
        'brokeragePayer': draft.brokeragePayer,
        'ownerSubjectToVat': draft.ownerSubjectToVat,
        'vatValue': draft.vatValue,
        'otherAmounts': draft.otherAmounts,
        'paymentScheduleType': draft.paymentScheduleType,
        'paymentFrequency': draft.paymentFrequency,
        'paymentCount': draft.paymentCount,
        'firstPaymentDate': draft.firstPaymentDate,
        'paymentChannel': draft.paymentChannel,
        'officialFeePayer': draft.officialFeePayer,
        'serviceFeePayer': draft.serviceFeePayer,
        'paymentMethod': draft.paymentMethod.name,
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
      'declarations': <String, Object?>{
        'acceptAccuracyDeclaration': draft.acceptAccuracyDeclaration,
        'acceptDataSharing': draft.acceptDataSharing,
        'acceptTerms': draft.acceptTerms,
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

  static Map<String, Object?> draftProgressToMap(DraftProgress progress) =>
      <String, Object?>{
        'lastStep': progress.lastStep.clamp(0, 6),
        'touchedSections': progress.touchedSections.toSet().toList(),
      };

  static ContractDraft? draftFromMap(Object? value) {
    final root = _dynamicMap(value);
    if (root.isEmpty) return null;
    final draft = ContractDraft();
    draft.type = ContractType.values.firstWhere(
      (item) => item.name == _mapString(root, 'type'),
      orElse: () => draft.type,
    );
    draft.role = UserRole.values.firstWhere(
      (item) => item.name == _mapString(root, 'role'),
      orElse: () => draft.role,
    );

    final property = _dynamicMap(root['property']);
    draft.property = PropertyData(
      propertySource:
          _mapString(property, 'propertySource', draft.property.propertySource),
      ownershipDocumentNumber: _mapString(property, 'ownershipDocumentNumber'),
      ownershipDocumentType: _mapString(
        property,
        'ownershipDocumentType',
        draft.property.ownershipDocumentType,
      ),
      ownershipDocumentDate: _mapString(property, 'ownershipDocumentDate'),
      propertyUsage:
          _mapString(property, 'propertyUsage', draft.property.propertyUsage),
      propertyType:
          _mapString(property, 'propertyType', draft.property.propertyType),
      floorsCount: _mapString(property, 'floorsCount'),
      unitsPerFloor: _mapString(property, 'unitsPerFloor'),
      totalUnits: _mapString(property, 'totalUnits'),
      city: _mapString(property, 'city', draft.property.city),
      district: _mapString(property, 'district'),
      street: _mapString(property, 'street'),
      buildingNumber: _mapString(property, 'buildingNumber'),
      additionalNumber: _mapString(property, 'additionalNumber'),
      postalCode: _mapString(property, 'postalCode'),
      buildingName: _mapString(property, 'buildingName'),
      unitNumber: _mapString(property, 'unitNumber'),
      unitName: _mapString(property, 'unitName'),
      unitType: _mapString(property, 'unitType', draft.property.unitType),
      floor: _mapString(property, 'floor'),
      area: _mapString(property, 'area'),
      roomsCount: _mapString(property, 'roomsCount'),
      bathroomsCount: _mapString(property, 'bathroomsCount'),
      hallsCount: _mapString(property, 'hallsCount'),
      maidRoom: _mapBool(property, 'maidRoom', draft.property.maidRoom),
      kitchen: _mapBool(property, 'kitchen', draft.property.kitchen),
      storage: _mapBool(property, 'storage', draft.property.storage),
      majlis: _mapBool(property, 'majlis', draft.property.majlis),
      furnishingStatus: _mapString(
        property,
        'furnishingStatus',
        draft.property.furnishingStatus,
      ),
      acWindow: _mapBool(property, 'acWindow', draft.property.acWindow),
      acSplit: _mapBool(property, 'acSplit', draft.property.acSplit),
      acCentral: _mapBool(property, 'acCentral', draft.property.acCentral),
      privateParking:
          _mapBool(property, 'privateParking', draft.property.privateParking),
      electricityMeter: _mapString(property, 'electricityMeter'),
      waterMeter: _mapString(property, 'waterMeter'),
      gasMeter: _mapString(property, 'gasMeter'),
      notes: _mapString(property, 'notes'),
    );

    draft.lessor = _partyFromMap(root['lessor']);
    draft.tenant = _partyFromMap(root['tenant']);
    draft.representative = _representativeFromMap(root['representative']);

    final duration = _dynamicMap(root['duration']);
    draft
      ..startDate = _mapString(duration, 'startDate')
      ..endDate = _mapString(duration, 'endDate')
      ..durationYears = _mapString(duration, 'years', draft.durationYears)
      ..durationMonths = _mapString(duration, 'months', draft.durationMonths)
      ..durationDays = _mapString(duration, 'days', draft.durationDays);

    final financial = _dynamicMap(root['financial']);
    draft
      ..rentValue = _mapString(financial, 'rentValue')
      ..rentPeriod = _mapString(financial, 'rentPeriod', draft.rentPeriod)
      ..hasSecurityDeposit = _mapBool(
        financial,
        'hasSecurityDeposit',
        draft.hasSecurityDeposit,
      )
      ..securityDeposit = _mapString(financial, 'securityDeposit')
      ..brokerageFee = _mapString(financial, 'brokerageFee')
      ..brokeragePayer =
          _mapString(financial, 'brokeragePayer', draft.brokeragePayer)
      ..ownerSubjectToVat =
          _mapBool(financial, 'ownerSubjectToVat', draft.ownerSubjectToVat)
      ..vatValue = _mapString(financial, 'vatValue')
      ..otherAmounts = _mapString(financial, 'otherAmounts')
      ..paymentScheduleType = _mapString(
        financial,
        'paymentScheduleType',
        draft.paymentScheduleType,
      )
      ..paymentFrequency = _mapString(
        financial,
        'paymentFrequency',
        draft.paymentFrequency,
      )
      ..paymentCount = _mapInt(financial, 'paymentCount', draft.paymentCount)
      ..firstPaymentDate = _mapString(financial, 'firstPaymentDate')
      ..paymentChannel =
          _mapString(financial, 'paymentChannel', draft.paymentChannel)
      ..officialFeePayer =
          _mapString(financial, 'officialFeePayer', draft.officialFeePayer)
      ..serviceFeePayer =
          _mapString(financial, 'serviceFeePayer', draft.serviceFeePayer)
      ..paymentMethod = PaymentMethod.values.firstWhere(
        (item) => item.name == _mapString(financial, 'paymentMethod'),
        orElse: () => draft.paymentMethod,
      );

    final services = _dynamicMap(root['services']);
    draft
      ..electricity = _serviceFromMap(
        services['electricity'],
        fallback: draft.electricity,
      )
      ..water = _serviceFromMap(services['water'], fallback: draft.water)
      ..gas = _serviceFromMap(services['gas'], fallback: draft.gas)
      ..otherServices = _mapString(services, 'otherServices');

    final terms = _dynamicMap(root['terms']);
    draft
      ..allowSublease = _mapBool(terms, 'allowSublease', draft.allowSublease)
      ..autoRenewal = _mapBool(terms, 'autoRenewal', draft.autoRenewal)
      ..specialTerms = _mapString(terms, 'specialTerms');
    final declarations = _dynamicMap(root['declarations']);
    draft
      ..acceptAccuracyDeclaration = _mapBool(
        declarations,
        'acceptAccuracyDeclaration',
        draft.acceptAccuracyDeclaration,
      )
      ..acceptDataSharing = _mapBool(
        declarations,
        'acceptDataSharing',
        draft.acceptDataSharing,
      )
      ..acceptTerms = _mapBool(declarations, 'acceptTerms', draft.acceptTerms);

    final storedAttachments =
        ((root['attachments'] as List?) ?? const <Object?>[])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
    if (storedAttachments.isNotEmpty) {
      final byKey = <String, Map<String, dynamic>>{
        for (final item in storedAttachments) _mapString(item, 'keyName'): item,
      };
      draft.attachments = draft.attachments.map((fallback) {
        final item = byKey[fallback.keyName];
        if (item == null) return fallback;
        return AttachmentData(
          keyName: fallback.keyName,
          title: _mapString(item, 'title', fallback.title),
          required: _mapBool(item, 'required', fallback.required),
          uploaded: _mapBool(item, 'uploaded', fallback.uploaded),
          fileName: _mapString(item, 'fileName'),
          sizeLabel: _mapString(item, 'sizeLabel'),
        );
      }).toList();
    }
    draft.installments = ((root['installments'] as List?) ?? const <Object?>[])
        .whereType<Map>()
        .map((item) {
      final data = Map<String, dynamic>.from(item);
      return InstallmentData(
        index: _mapInt(data, 'index', 1),
        amount: _mapString(data, 'amount'),
        dueDate: _mapString(data, 'dueDate'),
        note: _mapString(data, 'note'),
      );
    }).toList();
    return draft;
  }

  static DraftProgress draftProgressFromMap(Object? value) {
    final data = _dynamicMap(value);
    return DraftProgress(
      lastStep: _mapInt(data, 'lastStep').clamp(0, 6),
      touchedSections: ((data['touchedSections'] as List?) ?? const <Object?>[])
          .map((item) => '$item'.trim())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList(),
    );
  }

  static PartyData _partyFromMap(Object? value) {
    final data = _dynamicMap(value);
    final defaults = PartyData();
    return PartyData(
      kind: PartyKind.values.firstWhere(
        (item) => item.name == _mapString(data, 'kind'),
        orElse: () => defaults.kind,
      ),
      fullName: _mapString(data, 'fullName'),
      idType: _mapString(data, 'idType', defaults.idType),
      idNumber: _mapString(data, 'idNumber'),
      birthDate: _mapString(data, 'birthDate'),
      mobile: _mapString(data, 'mobile'),
      email: _mapString(data, 'email'),
      city: _mapString(data, 'city', defaults.city),
      district: _mapString(data, 'district'),
      nationalAddress: _mapString(data, 'nationalAddress'),
      mobileRegisteredInAbsher: _mapBool(
        data,
        'mobileRegisteredInAbsher',
        defaults.mobileRegisteredInAbsher,
      ),
      commercialRegistration: _mapString(data, 'commercialRegistration'),
      unifiedNumber: _mapString(data, 'unifiedNumber'),
      authorizedPersonName: _mapString(data, 'authorizedPersonName'),
      authorizedPersonId: _mapString(data, 'authorizedPersonId'),
      iban: _mapString(data, 'iban'),
      bankName: _mapString(data, 'bankName'),
      accountOwner: _mapString(data, 'accountOwner'),
    );
  }

  static RepresentativeData _representativeFromMap(Object? value) {
    final data = _dynamicMap(value);
    final defaults = RepresentativeData();
    return RepresentativeData(
      enabled: _mapBool(data, 'enabled', defaults.enabled),
      represents: _mapString(data, 'represents', defaults.represents),
      type: _mapString(data, 'type', defaults.type),
      fullName: _mapString(data, 'fullName'),
      idType: _mapString(data, 'idType', defaults.idType),
      idNumber: _mapString(data, 'idNumber'),
      birthDate: _mapString(data, 'birthDate'),
      mobile: _mapString(data, 'mobile'),
      authorizationNumber: _mapString(data, 'authorizationNumber'),
      authorizationDate: _mapString(data, 'authorizationDate'),
      issuer: _mapString(data, 'issuer'),
      expiryDate: _mapString(data, 'expiryDate'),
    );
  }

  static ServiceCharge _serviceFromMap(
    Object? value, {
    required ServiceCharge fallback,
  }) {
    final data = _dynamicMap(value);
    return ServiceCharge(
      enabled: _mapBool(data, 'enabled', fallback.enabled),
      calculationMethod:
          _mapString(data, 'calculationMethod', fallback.calculationMethod),
      fixedAmount: _mapString(data, 'fixedAmount'),
      currentReading: _mapString(data, 'currentReading'),
    );
  }

  static Map<String, dynamic> _dynamicMap(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static String _mapString(
    Map<String, dynamic> data,
    String key, [
    String fallback = '',
  ]) {
    final value = data[key];
    return value == null ? fallback : '$value';
  }

  static bool _mapBool(
    Map<String, dynamic> data,
    String key,
    bool fallback,
  ) =>
      data[key] is bool ? data[key] as bool : fallback;

  static int _mapInt(
    Map<String, dynamic> data,
    String key, [
    int fallback = 0,
  ]) =>
      data[key] is num ? (data[key] as num).toInt() : fallback;

  static Map<String, String> contractDetailsFromDraft(ContractDraft draft) {
    return <String, String>{
      'نوع العقد': draft.type.label,
      'تاريخ بداية العقد': _valueOrDash(draft.startDate),
      'تاريخ نهاية العقد': _valueOrDash(draft.endDate),
      'مدة العقد':
          '${_valueOrDash(draft.durationYears)} سنة، ${_valueOrDash(draft.durationMonths)} شهر، ${_valueOrDash(draft.durationDays)} يوم',
      'قيمة الإيجار': _moneyOrDash(draft.rentValue),
      'فترة الإيجار': _valueOrDash(draft.rentPeriod),
      'دورة السداد': _valueOrDash(draft.paymentFrequency),
      'عدد الدفعات': '${draft.paymentCount}',
      'تاريخ أول دفعة': _valueOrDash(draft.firstPaymentDate),
      'قناة السداد': _valueOrDash(draft.paymentChannel),
      'مبلغ الضمان': draft.hasSecurityDeposit
          ? _moneyOrDash(draft.securityDeposit)
          : 'لا يوجد',
      'رسوم منصة إيجار': '${draft.officialFee.toStringAsFixed(2)} ريال',
      'عمولة عقود برو': '${draft.serviceFee.toStringAsFixed(2)} ريال',
      'إجمالي الرسوم': '${draft.totalPayable.toStringAsFixed(2)} ريال',
      'دافع رسوم منصة إيجار': _valueOrDash(draft.officialFeePayer),
      'دافع عمولة عقود برو': _valueOrDash(draft.serviceFeePayer),
      'الكهرباء': _serviceLabel(draft.electricity),
      'المياه': _serviceLabel(draft.water),
      'الغاز': _serviceLabel(draft.gas),
      'تأجير من الباطن': _yesNo(draft.allowSublease),
      'تجديد تلقائي': _yesNo(draft.autoRenewal),
      if (draft.otherServices.trim().isNotEmpty)
        'خدمات إضافية': draft.otherServices.trim(),
      if (draft.specialTerms.trim().isNotEmpty)
        'شروط إضافية': draft.specialTerms.trim(),
    };
  }

  static UserRole roleFromDraft(ContractDraft draft) {
    return draft.representative.enabled ? UserRole.authorized : UserRole.lessor;
  }

  static Map<String, String> partyDetailsFromDraft(ContractDraft draft) {
    final lessor = draft.lessor;
    final tenant = draft.tenant;
    final representative = draft.representative;
    return <String, String>{
      ..._partyDetails('المؤجر', 'للمؤجر', lessor, includeBank: true),
      ..._partyDetails('المستأجر', 'للمستأجر', tenant),
      if (representative.enabled) ...<String, String>{
        'اسم الوكيل': _valueOrDash(representative.fullName),
        'يمثل': _valueOrDash(representative.represents),
        'نوع الوكالة': _valueOrDash(representative.type),
        'هوية الوكيل':
            '${_valueOrDash(representative.idType)} - ${_valueOrDash(representative.idNumber)}',
        'جوال الوكيل': _valueOrDash(representative.mobile),
        'رقم التفويض': _valueOrDash(representative.authorizationNumber),
        'جهة الإصدار': _valueOrDash(representative.issuer),
        'تاريخ انتهاء التفويض': _valueOrDash(representative.expiryDate),
      },
    };
  }

  static Map<String, String> _partyDetails(
    String label,
    String suffix,
    PartyData data, {
    bool includeBank = false,
  }) {
    return <String, String>{
      'اسم $label': data.displayName,
      'نوع $label': _partyKindLabel(data.kind),
      if (data.kind == PartyKind.individual) ...<String, String>{
        'هوية $label': _partyId(data),
        'تاريخ ميلاد $label': _valueOrDash(data.birthDate),
      } else ...<String, String>{
        'السجل التجاري $suffix': _valueOrDash(data.commercialRegistration),
        'الرقم الموحد $suffix': _valueOrDash(data.unifiedNumber),
        'اسم المفوض $suffix': _valueOrDash(data.authorizedPersonName),
        'هوية المفوض $suffix': _valueOrDash(data.authorizedPersonId),
      },
      'جوال $label': _valueOrDash(data.mobile),
      'بريد $label': _valueOrDash(data.email),
      'مدينة $label': _valueOrDash(data.city),
      'حي $label': _valueOrDash(data.district),
      'العنوان الوطني $suffix': _valueOrDash(data.nationalAddress),
      if (includeBank) ...<String, String>{
        'آيبان المؤجر': _valueOrDash(data.iban),
        'بنك المؤجر': _valueOrDash(data.bankName),
        'صاحب حساب المؤجر': _valueOrDash(data.accountOwner),
      },
    };
  }

  static Map<String, String> propertyDetailsFromDraft(ContractDraft draft) {
    final property = draft.property;
    return <String, String>{
      'مصدر العقار': _valueOrDash(property.propertySource),
      'رقم وثيقة الملكية': _valueOrDash(property.ownershipDocumentNumber),
      'نوع وثيقة الملكية': _valueOrDash(property.ownershipDocumentType),
      'تاريخ وثيقة الملكية': _valueOrDash(property.ownershipDocumentDate),
      'استخدام العقار': _valueOrDash(property.propertyUsage),
      'نوع العقار': _valueOrDash(property.propertyType),
      'المدينة': _valueOrDash(property.city),
      'الحي': _valueOrDash(property.district),
      'الشارع': _valueOrDash(property.street),
      'رقم المبنى': _valueOrDash(property.buildingNumber),
      'الرقم الإضافي': _valueOrDash(property.additionalNumber),
      'الرمز البريدي': _valueOrDash(property.postalCode),
      'اسم المبنى': _valueOrDash(property.buildingName),
      'عدد الأدوار': _valueOrDash(property.floorsCount),
      'الوحدات في كل دور': _valueOrDash(property.unitsPerFloor),
      'إجمالي الوحدات': _valueOrDash(property.totalUnits),
      'رقم الوحدة': _valueOrDash(property.unitNumber),
      'اسم الوحدة': _valueOrDash(property.unitName),
      'نوع الوحدة': _valueOrDash(property.unitType),
      'الدور': _valueOrDash(property.floor),
      'المساحة':
          property.area.trim().isEmpty ? '-' : '${property.area.trim()} م²',
      'عدد الغرف': _valueOrDash(property.roomsCount),
      'عدد دورات المياه': _valueOrDash(property.bathroomsCount),
      'عدد الصالات': _valueOrDash(property.hallsCount),
      'غرفة عاملة': _yesNo(property.maidRoom),
      'مطبخ': _yesNo(property.kitchen),
      'مستودع': _yesNo(property.storage),
      'مجلس': _yesNo(property.majlis),
      'حالة التأثيث': _valueOrDash(property.furnishingStatus),
      'مكيفات شباك': _yesNo(property.acWindow),
      'مكيفات سبليت': _yesNo(property.acSplit),
      'تكييف مركزي': _yesNo(property.acCentral),
      'موقف خاص': _yesNo(property.privateParking),
      'عداد الكهرباء': _valueOrDash(property.electricityMeter),
      'عداد المياه': _valueOrDash(property.waterMeter),
      'عداد الغاز': _valueOrDash(property.gasMeter),
      if (property.notes.trim().isNotEmpty)
        'ملاحظات العقار': property.notes.trim(),
    };
  }

  static Map<String, String> attachmentFilesFromDraft(ContractDraft draft) {
    return <String, String>{
      for (final attachment in draft.attachments)
        attachment.title: attachment.uploaded
            ? (attachment.fileName.trim().isEmpty
                ? 'مرفق'
                : attachment.fileName.trim())
            : (attachment.required ? 'مطلوب' : 'اختياري'),
    };
  }

  static String _partyKindLabel(PartyKind kind) {
    return switch (kind) {
      PartyKind.individual => 'فرد',
      PartyKind.company => 'منشأة',
    };
  }

  static String _partyId(PartyData data) {
    if (data.kind == PartyKind.company) {
      return _valueOrDash(data.commercialRegistration);
    }
    return '${_valueOrDash(data.idType)} - ${_valueOrDash(data.idNumber)}';
  }

  static String _serviceLabel(ServiceCharge service) {
    if (!service.enabled) {
      return 'غير مضافة';
    }
    final method = _valueOrDash(service.calculationMethod);
    final amount = service.fixedAmount.trim();
    final reading = service.currentReading.trim();
    final parts = <String>[method];
    if (amount.isNotEmpty) {
      parts.add('${amount.replaceAll(',', '')} ريال');
    }
    if (reading.isNotEmpty) {
      parts.add('قراءة حالية $reading');
    }
    return parts.join(' - ');
  }

  static String _yesNo(bool value) => value ? 'نعم' : 'لا';

  static String _moneyOrDash(String value) {
    final cleaned = value.trim().replaceAll(',', '');
    return cleaned.isEmpty ? '-' : '$cleaned ريال';
  }

  static String _valueOrDash(String value) {
    final cleaned = value.trim();
    return cleaned.isEmpty ? '-' : cleaned;
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

  static Map<String, Object?> propertyDocumentData({
    required String propertyId,
    required String uid,
    required String contractId,
    required PropertyData data,
  }) {
    final title = data.buildingName.trim().isEmpty
        ? '${data.propertyType} ${data.district}'.trim()
        : data.buildingName.trim();
    final unit = unitDocumentData(data);
    return <String, Object?>{
      'id': propertyId,
      'uid': uid,
      'userId': uid,
      'sourceContractId': contractId,
      'title': title.isEmpty ? data.propertyType : title,
      'city': data.city,
      'district': data.district,
      'type': data.propertyType,
      'usage': data.propertyUsage,
      'floors': _intFromText(data.floorsCount, fallback: 1),
      'unitsPerFloor': _intFromText(data.unitsPerFloor),
      'totalUnits': _intFromText(data.totalUnits, fallback: 1),
      'status': 'active',
      'address': <String, Object?>{
        'city': data.city,
        'district': data.district,
        'street': data.street,
        'buildingNumber': data.buildingNumber,
        'additionalNumber': data.additionalNumber,
        'postalCode': data.postalCode,
      },
      'ownership': <String, Object?>{
        'documentType': data.ownershipDocumentType,
        'documentNumber': data.ownershipDocumentNumber,
        'documentDate': data.ownershipDocumentDate,
      },
      'units': <Map<String, Object?>>[unit],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static Map<String, Object?> unitDocumentData(PropertyData data) {
    return <String, Object?>{
      'number': data.unitNumber,
      'name': data.unitName,
      'type': data.unitType,
      'floor': data.floor,
      'area': data.area,
      'status': 'available',
      'roomsCount': _intFromText(data.roomsCount),
      'bathroomsCount': _intFromText(data.bathroomsCount),
      'hallsCount': _intFromText(data.hallsCount),
      'maidRoom': data.maidRoom,
      'kitchen': data.kitchen,
      'storage': data.storage,
      'majlis': data.majlis,
      'furnishingStatus': data.furnishingStatus,
      'privateParking': data.privateParking,
      'electricityMeter': data.electricityMeter,
      'waterMeter': data.waterMeter,
      'gasMeter': data.gasMeter,
      'acWindow': data.acWindow,
      'acSplit': data.acSplit,
      'acCentral': data.acCentral,
      'notes': data.notes,
    };
  }

  static int _intFromText(String value, {int fallback = 0}) {
    final parsed = int.tryParse(value.trim());
    return parsed ?? fallback;
  }

  static String _textFromAny(Object? value) {
    if (value == null) return '';
    return '$value';
  }

  static bool _looksCorruptedText(String text) {
    final value = text.trim();
    if (value.isEmpty) return false;
    return RegExp(r'\?{3,}').hasMatch(value) ||
        value.contains('�') ||
        value.contains('Ø') ||
        value.contains('Ù') ||
        value.contains('Ã');
  }

  static String _readableText(Object? value, String fallback) {
    final text = _textFromAny(value).trim();
    if (text.isEmpty || _looksCorruptedText(text)) return fallback;
    return text;
  }

  static Map<String, String> _readableStringMap(Object? value) {
    if (value is! Map) return const <String, String>{};
    final result = <String, String>{};
    for (final entry in value.entries) {
      final key = _readableText(entry.key, '');
      final text = _readableText(entry.value, '');
      if (key.isNotEmpty && text.isNotEmpty) result[key] = text;
    }
    return result;
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
    if (status == ContractStatus.rejected) {
      return <StatusTimelineItem>[
        StatusTimelineItem(
          title: 'تم استلام الطلب',
          subtitle: 'تم استلام الطلب بنجاح',
          date: _dateLabel(now),
          time: _timeLabel(now),
          completed: true,
        ),
        StatusTimelineItem(
          title: 'قيد المعالجة',
          subtitle: 'تمت مراجعة بيانات الطلب',
          date: _dateLabel(now),
          time: _timeLabel(now),
          completed: true,
          eventStatus: ContractStatus.processing,
        ),
        StatusTimelineItem(
          title: 'تم رفض الطلب نهائيًا',
          subtitle: 'تم رفض الطلب بعد مراجعته.',
          date: _dateLabel(now),
          time: _timeLabel(now),
          current: true,
          eventStatus: ContractStatus.rejected,
        ),
      ];
    }
    return <StatusTimelineItem>[
      StatusTimelineItem(
        title: status == ContractStatus.draft
            ? 'تم حفظ المسودة'
            : 'تم استلام الطلب',
        subtitle: status == ContractStatus.draft
            ? 'لم يتم إرسال الطلب للمراجعة بعد'
            : status == ContractStatus.awaitingPayment
                ? 'تم إنشاء الطلب، ادفع الرسوم للمتابعة.'
                : 'تم استلام الطلب وهو قيد المعالجة.',
        date: _dateLabel(now),
        time: _timeLabel(now),
        completed: status != ContractStatus.draft,
        current: status == ContractStatus.draft ||
            status == ContractStatus.awaitingPayment ||
            status == ContractStatus.processing,
        eventStatus: status,
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
      ContractStatus.processing => 'قيد المعالجة',
      ContractStatus.authenticated => 'تم إصدار العقد النهائي',
      ContractStatus.rejected => 'تم رفض الطلب نهائيًا',
      ContractStatus.awaitingPayment => 'بانتظار الدفع',
      ContractStatus.draft => 'مسودة',
    };
    return StatusTimelineItem(
      title: title,
      subtitle: note.isEmpty ? status.label : note,
      date: _dateLabel(now),
      time: _timeLabel(now),
      completed: status == ContractStatus.authenticated,
      current: status != ContractStatus.authenticated,
      eventStatus: status,
    );
  }

  static List<StatusTimelineItem> normalizeTimelineForStatus({
    required ContractStatus status,
    required List<StatusTimelineItem> items,
    String rejectionReason = '',
    DateTime? rejectedAt,
  }) {
    if (status != ContractStatus.rejected) return items;
    final normalized = <StatusTimelineItem>[];
    StatusTimelineItem? rejectionEvent;
    for (final item in items) {
      final isRejected = item.eventStatus == ContractStatus.rejected ||
          item.title.contains('رفض');
      final isCompletedContract =
          item.eventStatus == ContractStatus.authenticated ||
              item.title == 'مكتمل' ||
              item.title.contains('العقد النهائي');
      if (isCompletedContract) continue;
      if (isRejected) {
        rejectionEvent = item;
        continue;
      }
      normalized.add(
        StatusTimelineItem(
          title: item.title,
          subtitle: item.subtitle,
          date: item.date,
          time: item.time,
          completed: true,
          eventStatus: item.eventStatus,
        ),
      );
    }
    final reason = rejectionReason.trim();
    final fallbackDate = rejectionEvent?.date ??
        (rejectedAt == null ? '' : _dateLabel(rejectedAt));
    final fallbackTime = rejectionEvent?.time ??
        (rejectedAt == null ? '' : _timeLabel(rejectedAt));
    normalized.add(
      StatusTimelineItem(
        title: 'تم رفض الطلب نهائيًا',
        subtitle: reason.isEmpty
            ? 'تم رفض الطلب نهائيًا بعد مراجعته.'
            : 'سبب الرفض: $reason',
        date: fallbackDate,
        time: fallbackTime,
        current: true,
        eventStatus: ContractStatus.rejected,
      ),
    );
    return normalized;
  }

  static Map<String, Object?> timelineToMap(StatusTimelineItem item) {
    return <String, Object?>{
      'title': item.title,
      'subtitle': item.subtitle,
      'date': item.date,
      'time': item.time,
      'completed': item.completed,
      'current': item.current,
      if (item.eventStatus != null) 'eventStatus': item.eventStatus!.name,
    };
  }

  static StatusTimelineItem timelineFromMap(Map<String, dynamic> data) {
    return StatusTimelineItem(
      title: _readableText(data['title'], ''),
      subtitle: _readableText(data['subtitle'], ''),
      date: _readableText(data['date'], ''),
      time: _readableText(data['time'], ''),
      completed: (data['completed'] as bool?) ?? false,
      current: (data['current'] as bool?) ?? false,
      eventStatus: _contractStatusOrNull(
        _readableText(data['eventStatus'], ''),
      ),
    );
  }

  static MissingRequirement missingRequirementFromMap(
    Map<String, dynamic> data,
  ) {
    var title = _readableText(data['title'], 'متطلب مراجعة');
    var description = _readableText(data['description'], '');
    var issueCode = _readableText(data['issueCode'], '');
    final fieldPath = _readableText(data['fieldPath'], '');
    final legacyText = '$title $description $fieldPath';
    if (issueCode.isEmpty && containsIllogicalMissingClaim(legacyText)) {
      if (legacyText.contains('السجل التجاري') ||
          legacyText.toLowerCase().contains('commercial')) {
        title = 'السجل التجاري';
        issueCode = MissingReviewIssue.unclear.code;
        description = buildMissingReviewDescription(
          target: title,
          issue: MissingReviewIssue.unclear,
        );
      } else if (legacyText.contains('عداد الكهرباء') ||
          legacyText.contains('electricityMeter')) {
        title = 'رقم عداد الكهرباء';
        issueCode = MissingReviewIssue.unverifiable.code;
        description = buildMissingReviewDescription(
          target: title,
          issue: MissingReviewIssue.unverifiable,
        );
      } else {
        issueCode = MissingReviewIssue.incorrect.code;
        description = buildMissingReviewDescription(
          target: title,
          issue: MissingReviewIssue.incorrect,
        );
      }
    }
    return MissingRequirement(
      id: (data['id'] as String?) ?? '',
      title: title,
      description: description,
      type: _readableText(data['type'], 'field'),
      issueCode: issueCode,
      fieldPath: fieldPath,
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
    return switch (value) {
      'underReview' ||
      'readyForEjar' ||
      'enteredInEjar' ||
      'awaitingAuthentication' =>
        ContractStatus.processing,
      _ => ContractStatus.values.firstWhere(
          (item) => item.name == value,
          orElse: () => ContractStatus.processing,
        ),
    };
  }

  static ContractStatus? _contractStatusOrNull(String value) {
    if (value.isEmpty) return null;
    for (final status in ContractStatus.values) {
      if (status.name == value) return status;
    }
    return null;
  }

  static String _notificationFallbackTitle(String type) {
    return switch (type) {
      'payment' => 'تم الدفع التجريبي',
      'paymentRequired' => 'بانتظار الدفع',
      'missingRequirement' => 'يوجد نقص مطلوب في طلبك',
      'finalPdfUploaded' => 'تم إصدار العقد النهائي',
      'rejected' => 'تم رفض طلب العقد',
      'supportReply' => 'رد جديد من الدعم',
      _ => 'تنبيه',
    };
  }

  static String _notificationFallbackBody(String type) {
    return switch (type) {
      'payment' => 'تم تسجيل عملية الدفع التجريبية بنجاح.',
      'paymentRequired' => 'طلبك جاهز للدفع، إجمالي الرسوم 398 ريال.',
      'missingRequirement' => 'يوجد نقص مطلوب لاستكمال معالجة الطلب.',
      'finalPdfUploaded' => 'يمكنك الآن عرض تفاصيل العقد النهائي.',
      'rejected' =>
        'تم رفض هذا الطلب نهائيًا. يمكنك تقديم طلب جديد أو التواصل مع الدعم الفني.',
      'supportReply' => 'وصلك رد جديد من فريق الدعم.',
      _ => '',
    };
  }

  static ContractStatus _statusForNotificationType(String value) {
    return switch (value) {
      'awaitingPayment' || 'paymentRequired' => ContractStatus.awaitingPayment,
      'missingRequirement' ||
      'missingResponseReturned' =>
        ContractStatus.missingData,
      'processing' ||
      'readyForEjar' ||
      'enteredInEjar' =>
        ContractStatus.processing,
      'authenticated' ||
      'finalPdfUploaded' ||
      'finalContractReady' =>
        ContractStatus.authenticated,
      'rejected' => ContractStatus.rejected,
      'draftSaved' => ContractStatus.draft,
      'contractSubmitted' ||
      'underReview' ||
      'payment' =>
        ContractStatus.processing,
      _ => ContractStatus.processing,
    };
  }

  static String _dateFromAny(Object? value) {
    if (value is Timestamp) return _dateLabel(value.toDate());
    return _dateLabel(DateTime.now());
  }

  static DateTime? _dateTimeFromAny(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  static String _dateLabel(DateTime value) {
    return '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';
  }

  static String _timeLabel(DateTime value) {
    return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }
}

class _DemoContractSeed {
  final ContractDraft draft;
  final ContractStatus status;
  final String paymentStatus;
  final String note;
  final String rejectionReason;
  final List<MissingRequirement> missingRequirements;
  final bool finalPdf;

  const _DemoContractSeed({
    required this.draft,
    required this.status,
    required this.paymentStatus,
    required this.note,
    this.rejectionReason = '',
    this.missingRequirements = const <MissingRequirement>[],
    this.finalPdf = false,
  });
}
