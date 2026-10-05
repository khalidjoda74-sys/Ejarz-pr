import 'dart:typed_data';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'app_controller.dart';
import 'firebase_repository.dart';
import 'models.dart';
import 'runtime_config.dart';
import 'contract_files.dart';
import 'admin_editor_navigation.dart';

/// Owns a customer editor context, never a customer authentication session.
class AdminContractSession extends AppController {
  final String customerUid;
  final String actorUid;
  String contractId;
  int revision = 0;
  bool canWaive = false, canRecordExternal = false;
  String mode = 'customer', method = 'bankTransfer';
  String reason = '', reference = '', proofUrl = '', proofName = '';
  bool acknowledged = false;
  int uploadsInProgress = 0;
  bool _ended = false;
  ContractDraft? initialDraft;
  DraftProgress initialProgress = const DraftProgress();
  late final _reader = FirebaseRepository();
  AdminContractSession(this.customerUid, this.actorUid, this.contractId)
      : super(initializeSession: false);

  @override
  void notifyListeners() {
    if (!_ended) super.notifyListeners();
  }

  @override
  void dispose() {
    _ended = true;
    super.dispose();
  }

  Future<Map<String, dynamic>> _call(
      String name, Map<String, Object?> values) async {
    if (_ended || FirebaseAuth.instance.currentUser?.uid != actorUid) {
      throw StateError('تغير حساب المسؤول. أعد فتح المحرر.');
    }
    final response = await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable(name)
        .call({'uid': customerUid, ...values});
    if (FirebaseAuth.instance.currentUser?.uid != actorUid) {
      throw StateError('تغير حساب المسؤول. أعد فتح المحرر.');
    }
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> load() async {
    final cursors = <String, String?>{};
    bool first = true;
    do {
      final data = await _call('getAdminContractContext', {
        if (first && contractId.isNotEmpty) 'contractId': contractId,
        'cursors': cursors,
      });
      if (first) {
        final customer = Map<String, dynamic>.from(data['customer'] as Map);
        userName = '${customer['name'] ?? ''}';
        userPhone = '${customer['phone'] ?? ''}';
        userEmail = '${customer['email'] ?? ''}';
        AppRuntime.config = Map<String, dynamic>.from(data['config'] as Map);
        canWaive = data['permissions']['waive'] == true;
        canRecordExternal = data['permissions']['external'] == true;
        if (data['contract'] is Map) {
          final raw = Map<String, dynamic>.from(data['contract'] as Map);
          revision = (raw['revision'] as num).toInt();
          final record = _reader.contractFromMap(contractId, raw);
          initialDraft = record.draftData;
          initialProgress = record.draftProgress;
          final options =
              Map<String, dynamic>.from(raw['adminDraftOptions'] as Map? ?? {});
          mode = '${options['mode'] ?? 'customer'}';
          if ((mode == 'waived' && !canWaive) ||
              (mode == 'external' && !canRecordExternal)) {
            mode = 'customer';
          }
          method = '${options['method'] ?? 'bankTransfer'}';
          reason = '${options['reason'] ?? ''}';
          reference = '${options['reference'] ?? ''}';
          proofUrl = '${options['proofUrl'] ?? ''}';
          proofName = '${options['proofName'] ?? ''}';
        }
      }
      final pages = Map<String, dynamic>.from(data['pages'] as Map);
      for (final name in ['properties', 'savedParties']) {
        if (!first && cursors[name] == null) continue;
        for (final row in pages[name]['rows'] as List) {
          final raw = Map<String, dynamic>.from(row as Map);
          if (name == 'properties') {
            properties.add(_reader.propertyFromMap('${raw['id']}', raw));
          } else {
            savedParties.add(raw);
          }
        }
        cursors[name] = pages[name]['cursor'] as String?;
      }
      first = false;
    } while (cursors.values.any((value) => value != null));
    if (contractId.isEmpty) {
      contractId = FirebaseFirestore.instance.collection('contracts').doc().id;
    }
    loggedIn = true;
    notifyListeners();
  }

  Map<String, Object?> _payload(ContractDraft draft, DraftProgress progress) {
    final property = FirebaseRepository.propertyDocumentData(
        propertyId: '',
        uid: customerUid,
        contractId: contractId,
        data: draft.property)
      ..remove('createdAt')
      ..remove('updatedAt');
    return {
      'contractId': contractId,
      'expectedUpdatedAt': revision,
      'adminDraftOptions': {
        'mode': mode,
        'method': method,
        'reason': reason,
        'reference': reference,
        'proofUrl': proofUrl,
        'proofName': proofName
      },
      'draft': FirebaseRepository.draftToMap(draft),
      'progress': FirebaseRepository.draftProgressToMap(progress),
      'expectedAmount': draft.totalPayable,
      if (draft.property.propertySource.trim() == 'إضافة عقار جديد')
        'property': property,
      'presentation': {
        'title': draft.title,
        'propertySummary': draft.property.displayAddress,
        'propertyTitle': draft.property.buildingName,
        'city': draft.property.city,
        'district': draft.property.district,
        'lessorSummary': draft.lessor.displayName,
        'tenantSummary': draft.tenant.displayName,
        'contractDetails': FirebaseRepository.contractDetailsFromDraft(draft),
        'partyDetails': FirebaseRepository.partyDetailsFromDraft(draft),
        'propertyDetails': FirebaseRepository.propertyDetailsFromDraft(draft),
        'attachmentFiles': FirebaseRepository.attachmentFilesFromDraft(draft),
      },
    };
  }

  @override
  Future<ContractRecord> saveDraft(ContractDraft draft,
      {String draftId = '',
      DraftProgress progress = const DraftProgress()}) async {
    final data =
        await _call('saveAdminContractDraft', _payload(draft, progress));
    revision = (data['revision'] as num).toInt();
    savedAdminEditor(contractId);
    return _reader.contractFromMap(
        contractId, Map<String, dynamic>.from(data['record'] as Map));
  }

  @override
  Future<ContractRecord> submitContract(ContractDraft draft,
      {String draftId = '',
      DraftProgress progress = const DraftProgress()}) async {
    if (uploadsInProgress > 0) {
      throw StateError('انتظر اكتمال رفع المرفقات قبل الإرسال.');
    }
    if (!acknowledged) {
      throw StateError('أكد إعداد وإرسال الطلب نيابة عن العميل.');
    }
    final submitted = ContractDraft.copyOf(draft)
      ..acceptAccuracyDeclaration = true
      ..acceptDataSharing = true
      ..acceptTerms = true;
    late final Map<String, dynamic> data;
    try {
      data = await _call('submitAdminContract', {
        ..._payload(submitted, progress),
        'adminAcknowledged': true,
        'settlement': {
          'mode': mode,
          'method': method,
          'amount': draft.totalPayable,
          'reason': reason,
          'reference': reference,
          'proofUrl': proofUrl,
          'proofName': proofName
        },
      });
    } on FirebaseFunctionsException catch (error) {
      if (error.details is Map && error.details['reason'] == 'price_changed') {
        final context = await _call('getAdminContractContext', {});
        AppRuntime.config = Map<String, dynamic>.from(context['config'] as Map);
        acknowledged = false;
        notifyListeners();
      }
      rethrow;
    }
    revision = (data['revision'] as num).toInt();
    return _reader.contractFromMap(
        contractId, Map<String, dynamic>.from(data['record'] as Map));
  }

  Future<String> upload(String name, Uint8List bytes,
      {ContractDraft? draft}) async {
    final type = ContractFiles.contentType(name, bytes);
    if (revision == 0 && draft != null) await saveDraft(draft);
    if (revision == 0) throw StateError('احفظ المسودة قبل رفع المرفقات.');
    if (FirebaseAuth.instance.currentUser?.uid != actorUid) {
      throw StateError('تغير حساب المسؤول.');
    }
    final ref = FirebaseStorage.instance.ref(
        'contracts/$contractId/creation/${DateTime.now().microsecondsSinceEpoch}.${name.split('.').last.toLowerCase()}');
    final task = ref.putData(bytes, SettableMetadata(contentType: type));
    uploadsInProgress++;
    notifyListeners();
    try {
      await task.timeout(const Duration(seconds: 90));
      return await ref.getDownloadURL();
    } catch (_) {
      await task.cancel();
      rethrow;
    } finally {
      uploadsInProgress--;
      notifyListeners();
    }
  }

  @override
  Future<void> saveParty(PartyData party,
      {String id = '', bool archived = false}) async {
    throw StateError('سيتم حفظ أطراف العميل عند إرسال العقد.');
  }
}
