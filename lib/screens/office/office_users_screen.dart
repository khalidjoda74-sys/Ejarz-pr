import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:darvoo/data/services/activity_log_service.dart';
import 'package:darvoo/data/services/package_limit_service.dart';
import 'package:darvoo/data/services/user_scope.dart' as scope;
import 'package:shared_preferences/shared_preferences.dart';

class OfficeUsersScreen extends StatefulWidget {
  const OfficeUsersScreen({super.key});

  @override
  State<OfficeUsersScreen> createState() => _OfficeUsersScreenState();
}

class _OfficeUsersScreenState extends State<OfficeUsersScreen> {
  static const Color _primary = Color(0xFF0F766E);
  final Stopwatch _screenTraceWatch = Stopwatch();
  Timer? _initialLoadTimer;
  bool _showInitialLoadWarning = false;
  bool _loggedInitialWaiting = false;
  bool _loggedFirstData = false;
  bool _loggedMissingRef = false;
  int _streamEventSeq = 0;
  String? _lastSnapshotSignature;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _usersStreamCache;
  bool _isBlockingProcessing = false;

  @override
  void initState() {
    super.initState();
    _screenTraceWatch.start();
    _traceUsers(
      'init authUid=${FirebaseAuth.instance.currentUser?.uid ?? ''} officeUid=${_officeUid ?? ''}',
    );
    _usersStreamCache = _createUsersStream();
    _initialLoadTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      _traceUsers(
        'initial-load warning triggered officeUid=${_officeUid ?? ''} waitingForFirstSnapshot=true',
      );
      setState(() => _showInitialLoadWarning = true);
    });
  }

  @override
  void dispose() {
    _initialLoadTimer?.cancel();
    _traceUsers('dispose');
    super.dispose();
  }

  bool _isOfficeUserDoc(Map<String, dynamic> m) {
    final role = (m['role'] ?? '').toString();
    final entityType = (m['entityType'] ?? '').toString();
    final accountType = (m['accountType'] ?? '').toString();
    final targetRole = (m['targetRole'] ?? '').toString();
    final officePermission = (m['officePermission'] ?? '').toString();
    final permission = (m['permission'] ?? '').toString();
    return role == 'office_staff' ||
        entityType == 'office_user' ||
        accountType == 'office_staff' ||
        targetRole == 'office' ||
        officePermission == 'full' ||
        officePermission == 'view' ||
        permission == 'full' ||
        permission == 'view';
  }

  String? get _officeUid {
    final scopedUid = scope.effectiveUid();
    if (scopedUid.isNotEmpty && scopedUid != 'guest') return scopedUid;
    return FirebaseAuth.instance.currentUser?.uid;
  }

  CollectionReference<Map<String, dynamic>>? get _usersRef {
    final uid = _officeUid;
    if (uid == null || uid.isEmpty) return null;
    return FirebaseFirestore.instance
        .collection('offices')
        .doc(uid)
        .collection('clients');
  }

  Future<bool> _hasInternetConnection() async {
    try {
      final r = await InternetAddress.lookup('example.com')
          .timeout(const Duration(seconds: 2));
      return r.isNotEmpty && r.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: GoogleFonts.cairo())),
    );
  }

  Future<void> _showBlockingOverlay() async {
    if (_isBlockingProcessing) return;
    if (!mounted) return;
    if (mounted) {
      setState(() => _isBlockingProcessing = true);
    }
    unawaited(
      showDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        barrierColor: Colors.black54,
        builder: (_) => PopScope(
          canPop: false,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
                decoration: BoxDecoration(
                  color: const Color(0xEE0F172A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x33FFFFFF)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'جاري المعالجة',
                      style: GoogleFonts.cairo(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> _hideBlockingOverlay() async {
    if (!mounted) return;
    final nav = Navigator.of(context, rootNavigator: true);
    if (nav.canPop()) {
      nav.pop();
    }
    if (mounted && _isBlockingProcessing) {
      setState(() => _isBlockingProcessing = false);
    }
  }

  String _compactStackTrace(StackTrace stackTrace, [int maxLines = 3]) {
    return stackTrace
        .toString()
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .take(maxLines)
        .join(' | ');
  }

  void _traceUsers(String message) {
    debugPrint(
      '[OfficeUsersTrace][${DateTime.now().toIso8601String()}][+${_screenTraceWatch.elapsedMilliseconds}ms] $message',
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>>? _createUsersStream() {
    final ref = _usersRef;
    final officeUid = _officeUid ?? '';
    if (ref == null) {
      _traceUsers('stream-create skipped officeUid-missing');
      return null;
    }
    _traceUsers(
      'stream-create path=offices/$officeUid/clients orderBy=createdAt desc includeMetadataChanges=true',
    );
    return ref
        .orderBy('createdAt', descending: true)
        .snapshots(includeMetadataChanges: true)
        .transform(
          StreamTransformer<QuerySnapshot<Map<String, dynamic>>,
              QuerySnapshot<Map<String, dynamic>>>.fromHandlers(
            handleData: (snap, sink) {
              final signature = '${snap.docs.length}|'
                  '${snap.metadata.isFromCache}|'
                  '${snap.metadata.hasPendingWrites}';
              if (_lastSnapshotSignature != signature) {
                _streamEventSeq++;
                _lastSnapshotSignature = signature;
                _traceUsers(
                  'stream-data#$_streamEventSeq docs=${snap.docs.length} fromCache=${snap.metadata.isFromCache} pendingWrites=${snap.metadata.hasPendingWrites}',
                );
              }
              sink.add(snap);
            },
            handleError: (error, stack, sink) {
              _traceUsers(
                'stream-error err=$error stack=${_compactStackTrace(stack)}',
              );
              sink.addError(error, stack);
            },
          ),
        );
  }

  void _traceResetLink(String message) {
    debugPrint('[OfficeUsersScreen][reset-link] $message');
  }

  Future<void> _traceResetLinkContext({
    required String email,
    required String docId,
    required String targetUid,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    _traceResetLink(
      'context email=$email docId=$docId targetUid=$targetUid '
      'currentUid=${currentUser?.uid ?? ''} officeUid=${_officeUid ?? ''}',
    );

    if (currentUser == null) {
      _traceResetLink('context no authenticated Firebase user');
      return;
    }

    try {
      final token = await currentUser.getIdTokenResult(true);
      final claims = token.claims ?? const <String, dynamic>{};
      _traceResetLink(
        'claims role=${claims['role']} '
        'officeId=${claims['officeId'] ?? claims['office_id']} '
        'accountType=${claims['accountType']} '
        'entityType=${claims['entityType']} '
        'targetRole=${claims['targetRole']} '
        'officePermission=${claims['officePermission']} '
        'permission=${claims['permission']} '
        'isOfficeClient=${claims['is_office_client']}',
      );
    } catch (e) {
      _traceResetLink('claims-error $e');
    }
  }

  void _logOfficeUserAction({
    required String actionType,
    required String entityId,
    required String entityName,
    required String description,
    Map<String, dynamic>? oldData,
    Map<String, dynamic>? newData,
    Map<String, dynamic>? metadata,
  }) {
    final officeUid = _officeUid;
    if (officeUid == null || officeUid.isEmpty) return;
    unawaited(
      ActivityLogService.instance.logEntityAction(
        actionType: actionType,
        entityType: 'office_user',
        entityId: entityId,
        entityName: entityName,
        description: description,
        oldData: oldData,
        newData: newData,
        metadata: metadata,
        workspaceUidOverride: officeUid,
      ),
    );
  }

  Future<void> _cacheOfficeUserLookups(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final officeUid = _officeUid;
    if (officeUid == null || officeUid.isEmpty) return;
    try {
      final sp = await SharedPreferences.getInstance();
      for (final d in docs) {
        final m = d.data();
        if (!_isOfficeUserDoc(m)) continue;
        final email = (m['email'] ?? '').toString().trim().toLowerCase();
        final uid = (m['uid'] ?? '').toString().trim();
        if (email.isNotEmpty) {
          await sp.setString('office_workspace_email_$email', officeUid);
        }
        if (uid.isNotEmpty) {
          await sp.setString('office_workspace_uid_$uid', officeUid);
        }
      }
    } catch (_) {}
  }

  Future<void> _showAddUserDialog() async {
    if (_isBlockingProcessing) return;
    final decision = await PackageLimitService.canAddOfficeUser();
    if (!decision.allowed) {
      _showSnack(
        decision.message ??
            'لا يمكن إضافة مستخدم مكتب جديد، لقد وصلت إلى الحد الأقصى المسموح.',
      );
      return;
    }
    await _showUserDialog();
  }

  Future<void> _showUserDialog({
    String? docId,
    String initialUid = '',
    String initialName = '',
    String initialEmail = '',
    String initialPermission = 'view',
    bool isEdit = false,
  }) async {
    final nameCtrl = TextEditingController(text: initialName);
    final emailCtrl = TextEditingController(text: initialEmail);
    String permission = initialPermission;
    bool loading = false;
    String? nameError;
    String? emailError;

    await showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (dctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> submit() async {
              final name = nameCtrl.text.trim();
              final email = emailCtrl.text.trim().toLowerCase();
              if (name.isEmpty || email.isEmpty || !email.contains('@')) {
                _showSnack('يرجى إدخال الاسم والبريد الإلكتروني بشكل صحيح.');
                return;
              }
              if (name.characters.length > 30 || email.characters.length > 30) {
                setLocal(() {
                  if (name.characters.length > 30) {
                    nameError = 'الحد الأقصى للاسم 30 حرفًا.';
                  }
                  if (email.characters.length > 30) {
                    emailError = 'الحد الأقصى للبريد الإلكتروني 30 حرفًا.';
                  }
                });
                return;
              }

              setLocal(() => loading = true);
              final blockingForCreate = !isEdit;
              try {
                if (blockingForCreate) {
                  await _showBlockingOverlay();
                }
                final ref = _usersRef;
                final officeUid = _officeUid ?? '';
                if (ref != null) {
                  if (isEdit) {
                    if (docId == null || docId.isEmpty) {
                      _showSnack('تعذر تحديد المستخدم المراد تعديله.');
                      setLocal(() => loading = false);
                      return;
                    }
                    final online = await _hasInternetConnection();
                    if (!online) {
                      _showSnack('الإنترنت مطلوب لتعديل مستخدم المكتب.');
                      setLocal(() => loading = false);
                      return;
                    }
                    final functions =
                        FirebaseFunctions.instanceFor(region: 'us-central1');
                    final targetUid =
                        initialUid.isNotEmpty ? initialUid : docId;
                    final updateProfile =
                        functions.httpsCallable('updateUserProfile');
                    await updateProfile.call({
                      'uid': targetUid,
                      'name': name,
                    });
                    final currentPermission =
                        initialPermission == 'full' ? 'full' : 'view';
                    final nextPermission =
                        permission == 'full' ? 'full' : 'view';
                    if (nextPermission != currentPermission) {
                      final permissionCallable =
                          functions.httpsCallable('officeUpdateUserPermission');
                      await permissionCallable.call({
                        'uid': targetUid,
                        'permission': nextPermission,
                      });
                    }
                    await ref.doc(docId).set({
                      'name': name,
                      'permission': nextPermission,
                      'officePermission': nextPermission,
                      'updatedAt': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true));
                    _logOfficeUserAction(
                      actionType: 'update',
                      entityId: targetUid,
                      entityName: name,
                      description: 'تم تعديل بيانات مستخدم المكتب $name',
                      oldData: <String, dynamic>{
                        'name': initialName,
                        'email': initialEmail,
                        'permission': currentPermission,
                      },
                      newData: <String, dynamic>{
                        'name': name,
                        'email': email,
                        'permission': nextPermission,
                      },
                      metadata: <String, dynamic>{'docId': docId},
                    );
                  } else {
                    final limitDecision =
                        await PackageLimitService.canAddOfficeUser();
                    if (!limitDecision.allowed) {
                      _showSnack(
                        limitDecision.message ??
                            'لا يمكن إضافة مستخدم مكتب جديد، لقد وصلت إلى الحد الأقصى المسموح.',
                      );
                      setLocal(() => loading = false);
                      return;
                    }

                    final online = await _hasInternetConnection();
                    if (!online) {
                      _showSnack('الإنترنت مطلوب لإضافة مستخدم جديد.');
                      setLocal(() => loading = false);
                      return;
                    }

                    final functions =
                        FirebaseFunctions.instanceFor(region: 'us-central1');
                    final createCallable =
                        functions.httpsCallable('officeCreateClient');
                    final result = await createCallable.call({
                      'name': name,
                      'email': email,
                      'phone': '',
                      'notes': '',
                      'officeId': officeUid,
                      'office_id': officeUid,
                      'accountType': 'office_staff',
                      'targetRole': 'office',
                      'officePermission': permission,
                    });

                    String? createdUid;
                    final data = result.data;
                    if (data is Map) {
                      final uid = data['uid']?.toString();
                      if (uid != null && uid.isNotEmpty) createdUid = uid;
                    }

                    if (createdUid == null || createdUid.isEmpty) {
                      await ref.doc(email).set({
                        'uid': '',
                        'name': name,
                        'email': email,
                        'role': 'office_staff',
                        'entityType': 'office_user',
                        'targetRole': 'office',
                        'permission': permission,
                        'officePermission': permission,
                        'officeId': officeUid,
                        'office_id': officeUid,
                        'accountType': 'office_staff',
                        'blocked': false,
                        'createdAt': FieldValue.serverTimestamp(),
                        'updatedAt': FieldValue.serverTimestamp(),
                      }, SetOptions(merge: true));
                    }
                    final entityId =
                        (createdUid != null && createdUid.isNotEmpty)
                            ? createdUid
                            : email;
                    _logOfficeUserAction(
                      actionType: 'create',
                      entityId: entityId,
                      entityName: name,
                      description: 'تم إضافة مستخدم مكتب جديد: $name',
                      newData: <String, dynamic>{
                        'name': name,
                        'email': email,
                        'permission': permission,
                        'blocked': false,
                      },
                      metadata: <String, dynamic>{
                        'docId': createdUid != null && createdUid.isNotEmpty
                            ? createdUid
                            : email,
                      },
                    );

                    try {
                      final sp = await SharedPreferences.getInstance();
                      await sp.setString(
                          'office_workspace_email_$email', officeUid);
                      if (createdUid != null && createdUid.isNotEmpty) {
                        await sp.setString(
                          'office_workspace_uid_$createdUid',
                          officeUid,
                        );
                      }
                    } catch (_) {}
                  }
                }

                if (!mounted) return;
                Navigator.of(dctx).pop();
                _showSnack(
                  isEdit
                      ? 'تم حفظ تعديلات المستخدم.'
                      : 'تمت إضافة المستخدم بنجاح.',
                );
              } on FirebaseFunctionsException catch (e) {
                _showSnack(
                  e.message ??
                      (isEdit ? 'تعذر حفظ التعديلات.' : 'تعذر إضافة المستخدم.'),
                );
              } catch (e) {
                _showSnack(
                  isEdit ? 'تعذر حفظ التعديلات: $e' : 'تعذر إضافة المستخدم: $e',
                );
              } finally {
                if (blockingForCreate) {
                  await _hideBlockingOverlay();
                }
                if (ctx.mounted) {
                  setLocal(() => loading = false);
                }
              }
            }

            return Directionality(
              textDirection: TextDirection.rtl,
              child: Dialog(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                child: Builder(
                  builder: (_) {
                    final mq = MediaQuery.of(ctx);
                    final maxDialogHeight =
                        (mq.size.height - mq.viewInsets.bottom - 24)
                            .clamp(280.0, mq.size.height * 0.95)
                            .toDouble();
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      constraints: BoxConstraints(
                        maxHeight: maxDialogHeight,
                      ),
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isEdit
                                  ? 'تعديل مستخدم المكتب'
                                  : 'إضافة مستخدم للمكتب',
                              style: GoogleFonts.cairo(
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: nameCtrl,
                              onChanged: (value) {
                                final len = value.characters.length;
                                if (len > 30) {
                                  final trimmed =
                                      value.characters.take(30).toString();
                                  nameCtrl.value = TextEditingValue(
                                    text: trimmed,
                                    selection: TextSelection.collapsed(
                                        offset: trimmed.length),
                                  );
                                  setLocal(() {
                                    nameError = 'الحد الأقصى للاسم 30 حرفًا.';
                                  });
                                } else {
                                  if (nameError != null) {
                                    setLocal(() => nameError = null);
                                  }
                                }
                              },
                              decoration: InputDecoration(
                                labelText: 'الاسم',
                                errorText: nameError,
                                labelStyle: GoogleFonts.cairo(),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: emailCtrl,
                              enabled: !isEdit,
                              keyboardType: TextInputType.emailAddress,
                              onChanged: (value) {
                                final len = value.characters.length;
                                if (len > 30) {
                                  final trimmed =
                                      value.characters.take(30).toString();
                                  emailCtrl.value = TextEditingValue(
                                    text: trimmed,
                                    selection: TextSelection.collapsed(
                                        offset: trimmed.length),
                                  );
                                  setLocal(() {
                                    emailError =
                                        'الحد الأقصى للبريد الإلكتروني 30 حرفًا.';
                                  });
                                } else {
                                  if (emailError != null) {
                                    setLocal(() => emailError = null);
                                  }
                                }
                              },
                              decoration: InputDecoration(
                                labelText: 'البريد الإلكتروني',
                                errorText: emailError,
                                labelStyle: GoogleFonts.cairo(),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'الصلاحية',
                              style: GoogleFonts.cairo(
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF334155),
                              ),
                            ),
                            const SizedBox(height: 6),
                            RadioListTile<String>(
                              contentPadding: EdgeInsets.zero,
                              value: 'full',
                              groupValue: permission,
                              activeColor: _primary,
                              title: Text(
                                'تحكم كامل',
                                style: GoogleFonts.cairo(
                                    fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(
                                'إضافة، تعديل، حذف وإدارة كاملة.',
                                style: GoogleFonts.cairo(fontSize: 12),
                              ),
                              onChanged: (v) =>
                                  setLocal(() => permission = v ?? 'full'),
                            ),
                            RadioListTile<String>(
                              contentPadding: EdgeInsets.zero,
                              value: 'view',
                              groupValue: permission,
                              activeColor: _primary,
                              title: Text(
                                'مشاهدة فقط',
                                style: GoogleFonts.cairo(
                                    fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(
                                'عرض البيانات بدون أي تعديل.',
                                style: GoogleFonts.cairo(fontSize: 12),
                              ),
                              onChanged: (v) =>
                                  setLocal(() => permission = v ?? 'view'),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: loading ? null : submit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _primary,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: loading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white),
                                      )
                                    : Text(
                                        isEdit
                                            ? 'حفظ التعديلات'
                                            : 'إضافة المستخدم',
                                        style: GoogleFonts.cairo(
                                            fontWeight: FontWeight.w800),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: loading
                                    ? null
                                    : () => Navigator.of(dctx).pop(),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                      color: Color(0xFFCBD5E1)),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child:
                                    Text('إلغاء', style: GoogleFonts.cairo()),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _generateResetLink({
    required String email,
    required String docId,
    required String uid,
  }) async {
    final online = await _hasInternetConnection();
    if (!online) {
      _traceResetLink(
        'aborted offline email=$email docId=$docId targetUid=$uid',
      );
      _showSnack('الإنترنت مطلوب لتوليد رابط تعيين كلمة المرور.');
      return;
    }

    final watch = Stopwatch()..start();
    await _traceResetLinkContext(email: email, docId: docId, targetUid: uid);

    try {
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable('generatePasswordResetLink');
      final normalizedEmail = email.trim().toLowerCase();
      _traceResetLink('calling generatePasswordResetLink region=us-central1');
      final res = await callable.call({'email': normalizedEmail});
      final link = (res.data as Map?)?['resetLink']?.toString();

      _traceResetLink(
        'success ms=${watch.elapsedMilliseconds} '
        'hasLink=${link != null && link.isNotEmpty}',
      );
      if (link == null || link.isEmpty) {
        _showSnack('تعذر توليد الرابط.');
        return;
      }
      _logOfficeUserAction(
        actionType: 'password_reset_link',
        entityId: uid.isNotEmpty ? uid : docId,
        entityName: email,
        description: 'تم توليد رابط إعادة تعيين كلمة المرور للمستخدم $email',
        metadata: <String, dynamic>{
          'email': email,
          'docId': docId,
        },
      );
      final generatedLink = link;

      if (!mounted) return;
      await showDialog(
        context: context,
        barrierColor: Colors.black54,
        builder: (dctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text('رابط تعيين كلمة المرور',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
            content: SelectableText(generatedLink,
                style: GoogleFonts.cairo(fontSize: 13)),
            actions: [
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: generatedLink));
                  if (mounted) _showSnack('تم نسخ الرابط.');
                },
                child: Text('نسخ', style: GoogleFonts.cairo()),
              ),
              TextButton(
                onPressed: () => Navigator.of(dctx).pop(),
                child: Text('حسنًا', style: GoogleFonts.cairo()),
              ),
            ],
          ),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      _traceResetLink(
        'functions-error ms=${watch.elapsedMilliseconds} '
        'code=${e.code} message=${e.message ?? ''} details=${e.details}',
      );
      _showSnack(e.message ?? 'تعذر توليد الرابط.');
    } catch (e) {
      _traceResetLink(
        'unexpected-error ms=${watch.elapsedMilliseconds} error=$e',
      );
      _showSnack('تعذر توليد الرابط.');
    }
  }

  Future<void> _toggleBlocked({
    required String docId,
    required String uid,
    required String name,
    required String email,
    required bool currentlyBlocked,
  }) async {
    final online = await _hasInternetConnection();
    if (!online) {
      _showSnack('الإنترنت مطلوب لتنفيذ هذا الإجراء.');
      return;
    }

    try {
      final nextBlocked = !currentlyBlocked;
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable('updateUserStatus');
      await callable.call({'uid': uid, 'blocked': nextBlocked});
      final ref = _usersRef;
      if (ref != null) {
        await ref.doc(docId).set({
          'blocked': nextBlocked,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      _logOfficeUserAction(
        actionType: 'status_change',
        entityId: uid.isNotEmpty ? uid : docId,
        entityName: name,
        description: nextBlocked
            ? 'تم إيقاف مستخدم المكتب $name'
            : 'تم تفعيل مستخدم المكتب $name',
        oldData: <String, dynamic>{'blocked': currentlyBlocked},
        newData: <String, dynamic>{'blocked': nextBlocked},
        metadata: <String, dynamic>{'email': email, 'docId': docId},
      );
      _showSnack(nextBlocked ? 'تم إيقاف الدخول.' : 'تم السماح بالدخول.');
    } on FirebaseFunctionsException catch (e) {
      _showSnack(e.message ?? 'تعذر تحديث الحالة.');
    } catch (_) {
      _showSnack('تعذر تحديث الحالة.');
    }
  }

  Future<void> _updatePermission({
    required String docId,
    required String uid,
    required String name,
    required String email,
    required String permission,
  }) async {
    final ref = _usersRef;
    if (ref == null) return;
    final next = permission == 'full' ? 'view' : 'full';
    try {
      final online = await _hasInternetConnection();
      if (!online) {
        _showSnack('الإنترنت مطلوب لتعديل الصلاحية.');
        return;
      }
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable('officeUpdateUserPermission');
      await callable.call({'uid': uid, 'permission': next});
      await ref.doc(docId).set({
        'permission': next,
        'officePermission': next,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _logOfficeUserAction(
        actionType: 'update',
        entityId: uid.isNotEmpty ? uid : docId,
        entityName: name,
        description: 'تم تعديل صلاحيات مستخدم المكتب $name',
        oldData: <String, dynamic>{'permission': permission},
        newData: <String, dynamic>{'permission': next},
        metadata: <String, dynamic>{'email': email, 'docId': docId},
      );
      _showSnack(next == 'full'
          ? 'تم منح صلاحية التحكم الكامل.'
          : 'تم تحويل الصلاحية إلى مشاهدة فقط.');
    } catch (_) {
      _showSnack('تعذر تعديل الصلاحية.');
    }
  }

  Future<void> _deleteUser({
    required String docId,
    required String uid,
    required String name,
    required String email,
    required String permission,
    required bool blocked,
  }) async {
    final ref = _usersRef;
    if (ref == null) return;
    await _showBlockingOverlay();
    try {
      final online = await _hasInternetConnection();
      if (!online) {
        _showSnack('الإنترنت مطلوب لحذف المستخدم.');
        return;
      }
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable('officeDeleteClient');
      await callable.call({'clientUid': uid});
      _logOfficeUserAction(
        actionType: 'delete',
        entityId: uid.isNotEmpty ? uid : docId,
        entityName: name,
        description: 'تم حذف مستخدم المكتب $name',
        oldData: <String, dynamic>{
          'name': name,
          'email': email,
          'permission': permission,
          'blocked': blocked,
        },
        metadata: <String, dynamic>{'docId': docId},
      );
      await ref.doc(docId).delete().catchError((_) {});
      _showSnack('تم حذف المستخدم.');
    } on FirebaseFunctionsException catch (e) {
      _showSnack(e.message ?? 'تعذر حذف المستخدم.');
    } catch (_) {
      _showSnack('تعذر حذف المستخدم.');
    } finally {
      await _hideBlockingOverlay();
    }
  }

  Future<void> _showDeleteUserDialog({
    required String docId,
    required String uid,
    required String name,
    required String email,
    required String permission,
    required bool blocked,
  }) async {
    if (_isBlockingProcessing) return;
    await showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (dctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Dialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تنبيه',
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'هل تريد حذف المستخدم ${name.isEmpty ? '' : '"$name"'}؟',
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.of(dctx).pop();
                      await _deleteUser(
                        docId: docId,
                        uid: uid,
                        name: name,
                        email: email,
                        permission: permission,
                        blocked: blocked,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFB91C1C),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'حذف',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(dctx).pop(),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text('إلغاء', style: GoogleFonts.cairo()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ref = _usersRef;
    final usersStream = _usersStreamCache ??= _createUsersStream();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: PopScope(
        canPop: !_isBlockingProcessing,
        child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          centerTitle: true,
          leading: IconButton(
            onPressed: _isBlockingProcessing
                ? null
                : () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
          ),
          title: Text(
            'مستخدمو المكتب',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w800),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          onPressed: _isBlockingProcessing ? null : _showAddUserDialog,
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: Text('إضافة مستخدم',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
        ),
        body: ref == null
            ? Center(
                child: Text(
                  'تعذر تحديد حساب المكتب.',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
                ),
              )
            : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: usersStream,
                builder: (context, snap) {
                  if (!_loggedMissingRef && usersStream == null) {
                    _loggedMissingRef = true;
                    _traceUsers(
                        'builder abort usersStream-null despite ref-available');
                  }
                  if (snap.hasError) {
                    _traceUsers(
                      'builder error connectionState=${snap.connectionState} err=${snap.error}',
                    );
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'تعذر تحميل مستخدمي المكتب. تحقق من القواعد أو الاتصال ثم أعد المحاولة.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.cairo(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFB91C1C),
                          ),
                        ),
                      ),
                    );
                  }

                  if (!snap.hasData &&
                      snap.connectionState == ConnectionState.waiting) {
                    if (!_loggedInitialWaiting) {
                      _loggedInitialWaiting = true;
                      _traceUsers(
                        'builder waiting hasData=false officeUid=${_officeUid ?? ''}',
                      );
                    }
                    if (_showInitialLoadWarning) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 16),
                              Text(
                                'تحميل مستخدمي المكتب يستغرق أطول من المتوقع. غالبًا السبب اتصال بطيء أو قراءة Firestore متأخرة.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF475569),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = (snap.data?.docs ?? const [])
                      .where((d) => _isOfficeUserDoc(d.data()))
                      .toList(growable: false);
                  if (!_loggedFirstData) {
                    _loggedFirstData = true;
                    _initialLoadTimer?.cancel();
                    _traceUsers(
                      'builder first-data rawDocs=${snap.data?.docs.length ?? 0} filteredDocs=${docs.length} fromCache=${snap.data?.metadata.isFromCache ?? false}',
                    );
                  }
                  _cacheOfficeUserLookups(docs);
                  if (docs.isEmpty) {
                    _traceUsers(
                      'builder empty filteredDocs=0 rawDocs=${snap.data?.docs.length ?? 0}',
                    );
                    return Center(
                      child: Text(
                        'لا يوجد مستخدمون إضافيون حتى الآن.',
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF475569),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (ctx, i) {
                      final d = docs[i];
                      final m = d.data();
                      final name = (m['name'] ?? '').toString();
                      final email = (m['email'] ?? '').toString();
                      final permission = (m['permission'] ?? 'view').toString();
                      final blocked = (m['blocked'] == true);
                      final uid = (m['uid'] ?? '').toString();
                      final canManageAuth = uid.isNotEmpty;

                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x11000000),
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: const Color(0xFFEFF4FF),
                                    child: Text(
                                      (name.isEmpty
                                              ? '?'
                                              : name.characters.first)
                                          .toUpperCase(),
                                      style: GoogleFonts.cairo(
                                        color: _primary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name.isEmpty ? 'بدون اسم' : name,
                                          style: GoogleFonts.cairo(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 15,
                                            color: const Color(0xFF0F172A),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          email,
                                          style: GoogleFonts.cairo(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                            color: const Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: permission == 'full'
                                          ? const Color(0xFFDCFCE7)
                                          : const Color(0xFFE2E8F0),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      permission == 'full'
                                          ? 'تحكم كامل'
                                          : 'مشاهدة فقط',
                                      style: GoogleFonts.cairo(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 11,
                                        color: permission == 'full'
                                            ? const Color(0xFF166534)
                                            : const Color(0xFF334155),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _updatePermission(
                                        docId: d.id,
                                        uid: uid,
                                        name: name,
                                        email: email,
                                        permission: permission,
                                      ),
                                      icon: const Icon(
                                          Icons.admin_panel_settings_outlined,
                                          size: 18),
                                      label: Text(
                                        permission == 'full'
                                            ? 'تحويل لمشاهدة'
                                            : 'منح تحكم كامل',
                                        style: GoogleFonts.cairo(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _generateResetLink(
                                        email: email,
                                        docId: d.id,
                                        uid: uid,
                                      ),
                                      icon: const Icon(Icons.link_rounded,
                                          size: 18),
                                      label: Text(
                                        'رابط كلمة المرور',
                                        style: GoogleFonts.cairo(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                blocked
                                                    ? 'الدخول: موقوف'
                                                    : 'الدخول: مسموح',
                                                style: GoogleFonts.cairo(
                                                  fontWeight: FontWeight.w700,
                                                  color: blocked
                                                      ? const Color(0xFFB91C1C)
                                                      : const Color(0xFF166534),
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: 'تعديل',
                                              onPressed: () => _showUserDialog(
                                                docId: d.id,
                                                initialUid: uid,
                                                initialName: name,
                                                initialEmail: email,
                                                initialPermission: permission,
                                                isEdit: true,
                                              ),
                                              icon: const Icon(
                                                Icons.edit_rounded,
                                                color: Color(0xFF0F766E),
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: 'حذف',
                                              onPressed: () =>
                                                  _showDeleteUserDialog(
                                                docId: d.id,
                                                uid: uid,
                                                name: name,
                                                email: email,
                                                permission: permission,
                                                blocked: blocked,
                                              ),
                                              icon: const Icon(
                                                Icons.delete_outline_rounded,
                                                color: Color(0xFFB91C1C),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Switch(
                                    value: !blocked,
                                    onChanged: canManageAuth
                                        ? (_) => _toggleBlocked(
                                              docId: d.id,
                                              uid: uid,
                                              name: name,
                                              email: email,
                                              currentlyBlocked: blocked,
                                            )
                                        : null,
                                    activeColor: const Color(0xFF16A34A),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
        ),
      ),
    );
  }
}
