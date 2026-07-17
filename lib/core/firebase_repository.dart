import 'dart:convert';
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
    if (existing.docs.isNotEmpty) return;

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
        note: 'يوجد نقص في بيانات المستأجر ومرفقات العقد.',
        missingRequirements: const <MissingRequirement>[
          MissingRequirement(
            id: 'MR-DEMO-CR',
            title: 'إرفاق صورة السجل التجاري',
            description: 'السجل التجاري للمستأجر غير مرفق.',
            type: 'file',
            fieldPath: 'draftData.tenant.commercialRegistration',
          ),
          MissingRequirement(
            id: 'MR-DEMO-METER',
            title: 'رقم عداد الكهرباء',
            description: 'أدخل رقم عداد الكهرباء للوحدة محل العقد.',
            type: 'field',
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
    ];

    for (var i = 0; i < demos.length; i++) {
      final seed = demos[i];
      final contractRef = firestore.collection('contracts').doc();
      final propertyRef = firestore.collection('properties').doc();
      final now = DateTime.now().subtract(Duration(days: i));
      final requestNumber =
          'REQ-DEMO-${(1000 + i + 1).toString().padLeft(4, '0')}';
      final timeline =
          initialTimeline(seed.status, now).map(timelineToMap).toList();
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
        'draftData': draftToMap(seed.draft),
        'totalFees': total,
        'totalPayable': total,
        'ejarPlatformFee': 299,
        'serviceFee': 99,
        'paymentStatus': seed.paymentStatus,
        'adminAssignedTo': '',
        'adminInternalNotes': '',
        'customerVisibleNote': seed.note,
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
  }) async {
    final now = DateTime.now();
    final doc = firestore.collection('contracts').doc();
    final shouldCreateProperty =
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
        notificationData(
          uid: uid,
          contractId: contractId,
          title: event.title,
          body: status == ContractStatus.awaitingPayment
              ? 'طلبك جاهز للدفع، إجمالي الرسوم 398 ريال.'
              : customerNote.isEmpty
                  ? event.subtitle
                  : customerNote,
          type: notificationTypeForStatus(status),
          priority: status == ContractStatus.awaitingPayment ||
                  status == ContractStatus.rejected
              ? 'high'
              : 'normal',
        ),
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

  ContractRecord contractFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final type = _contractType((data['type'] as String?) ?? '');
    final status = _contractStatus((data['status'] as String?) ?? '');
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
      timeline: ((data['timeline'] as List?) ?? const <Object?>[])
          .whereType<Map>()
          .map((item) => timelineFromMap(Map<String, dynamic>.from(item)))
          .toList(),
      customerVisibleNote: _readableText(data['customerVisibleNote'], ''),
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
    );
  }

  PropertyRecord propertyFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final units = ((data['units'] as List?) ?? const <Object?>[])
        .whereType<Map>()
        .map((unit) => unitFromMap(Map<String, dynamic>.from(unit)))
        .toList();
    return PropertyRecord(
      id: doc.id,
      title: _readableText(data['title'], 'عقار'),
      city: _readableText(data['city'], 'الرياض'),
      district: _readableText(data['district'], ''),
      type: _readableText(data['type'], 'عمارة'),
      usage: _readableText(data['usage'], 'سكن عوائل'),
      floors: ((data['floors'] as num?) ?? 1).toInt(),
      totalUnits: ((data['totalUnits'] as num?) ?? 1).toInt(),
      units: units,
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
      ..ownershipDocumentNumber = 'DOC-DEMO-2026'
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
      ..roomsCount = type == ContractType.residential ? '3' : '0'
      ..bathroomsCount = '2'
      ..hallsCount = '1'
      ..electricityMeter = 'EM-DEMO-7788'
      ..waterMeter = 'WM-DEMO-7788';
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

  Map<String, Object?> draftToMap(ContractDraft draft) {
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
      ContractStatus.rejected => 'تم رفض الطلب',
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
      title: _readableText(data['title'], ''),
      subtitle: _readableText(data['subtitle'], ''),
      date: _readableText(data['date'], ''),
      time: _readableText(data['time'], ''),
      completed: (data['completed'] as bool?) ?? false,
      current: (data['current'] as bool?) ?? false,
    );
  }

  static MissingRequirement missingRequirementFromMap(
    Map<String, dynamic> data,
  ) {
    return MissingRequirement(
      id: (data['id'] as String?) ?? '',
      title: _readableText(data['title'], 'نقص مطلوب'),
      description: _readableText(data['description'], ''),
      type: _readableText(data['type'], 'field'),
      fieldPath: _readableText(data['fieldPath'], ''),
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

  static String _notificationFallbackTitle(String type) {
    return switch (type) {
      'payment' => 'تم الدفع التجريبي',
      'paymentRequired' => 'بانتظار الدفع',
      'missingRequirement' => 'يوجد نقص مطلوب في طلبك',
      'finalPdfUploaded' => 'تم إصدار العقد النهائي',
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
      'supportReply' => 'وصلك رد جديد من فريق الدعم.',
      _ => '',
    };
  }

  static ContractStatus _statusForNotificationType(String value) {
    return switch (value) {
      'awaitingPayment' => ContractStatus.awaitingPayment,
      'missingRequirement' => ContractStatus.missingData,
      'processing' ||
      'readyForEjar' ||
      'enteredInEjar' =>
        ContractStatus.processing,
      'authenticated' || 'finalPdfUploaded' => ContractStatus.authenticated,
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
  final List<MissingRequirement> missingRequirements;
  final bool finalPdf;

  const _DemoContractSeed({
    required this.draft,
    required this.status,
    required this.paymentStatus,
    required this.note,
    this.missingRequirements = const <MissingRequirement>[],
    this.finalPdf = false,
  });
}
