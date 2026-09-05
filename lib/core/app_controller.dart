import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'firebase_bootstrap.dart';
import 'demo_config.dart';
import 'firebase_repository.dart';
import 'legal_links.dart';
import 'models.dart';
import 'contract_pricing.dart';
import 'property_management.dart';
import 'notification_service.dart';

class _PendingContractSubmission {
  final String localId;
  final String remoteDraftId;
  final ContractDraft draft;
  final ContractStatus status;
  final DraftProgress progress;

  const _PendingContractSubmission({
    required this.localId,
    this.remoteDraftId = '',
    required this.draft,
    required this.status,
    this.progress = const DraftProgress(),
  });
}

class _PendingPropertySave {
  final String localId;
  final PropertyData data;
  final String propertyId;
  final List<UnitRecord>? unitEdits;
  final List<UnitRecord>? expectedUnits;
  final String replacingNumber;

  const _PendingPropertySave({
    required this.localId,
    required this.data,
    required this.propertyId,
    this.unitEdits,
    this.expectedUnits,
    this.replacingNumber = '',
  });
}

class AppController extends ChangeNotifier {
  static const String _serverReachabilityCheckMessage =
      'تعذر تأكيد الاتصال بالخادم الآن. سيتم تحديث البيانات تلقائيًا عند توفر الاتصال.';

  bool splashCompleted = false;
  bool onboardingCompleted = false;
  bool loggedIn = false;
  bool darkMode = false;
  bool biometricEnabled = false;
  bool pushNotificationsEnabled = true;
  bool accountBlocked = false;
  bool maintenanceMode = false;
  bool adminBypassMaintenance = false;
  int mainNavigationIndex = 0;
  bool offlineMode = false;
  bool syncingPendingChanges = false;
  DateTime? lastSyncedAt;
  String offlineMessage = '';

  String userName = 'عميل عقود';
  String userPhone = '';
  String userEmail = '';
  String homeGreetingPrefix = 'مرحبًا';
  String homeWelcomeText = 'مرحبًا بك في عقود برو';
  String homeHeroTitle = 'إنشاء عقد جديد';
  String homeHeroSubtitle =
      'أنشئ طلب عقد احترافيًا في دقائق\nوأرسله للمراجعة والتوثيق.';
  String homeHeroButtonText = 'إنشاء عقد جديد';
  String homeServicesTitle = 'خدماتنا';
  String homeServicesAction = 'عرض الكل';
  String serviceResidentialTitle = 'عقد سكني';
  String serviceResidentialSubtitle = 'إنشاء عقد سكني';
  String serviceCommercialTitle = 'عقد تجاري';
  String serviceCommercialSubtitle = 'إنشاء عقد تجاري';
  String serviceRenewalTitle = 'تجديد عقد';
  String serviceRenewalSubtitle = 'تجديد عقد قائم';
  String serviceRenewalMessage =
      'خدمة تجديد العقد جاهزة ضمن نموذج إنشاء العقد.';
  String serviceHandoverTitle = 'عقاراتي';
  String serviceHandoverSubtitle = 'إدارة العقارات';
  String serviceHandoverMessage = 'سيتم فتح شاشة عقاراتي.';
  String homePropertiesTitle = 'العقارات المضافة مؤخرًا';
  String homePropertiesAction = 'عقاراتي';
  String homeEmptyPropertiesTitle = 'لا توجد عقارات محفوظة';
  String homeEmptyPropertiesSubtitle =
      'أضف عقاراتك ووحداتك لتسريع إنشاء العقود.';
  String homeEmptyPropertiesAction = 'إضافة عقار';
  String homeContractsTitle = 'آخر الطلبات';
  String homeContractsAction = 'عرض الكل';
  String homeEmptyContractsTitle = 'لا توجد عقود بعد';
  String homeEmptyContractsSubtitle = 'ابدأ بإنشاء أول عقد لك من التطبيق.';
  String homeEmptyContractsAction = 'إنشاء عقد';
  String legalPrivacyUrl = LegalLinks.privacy;
  String legalTermsUrl = LegalLinks.terms;
  String legalRefundUrl = LegalLinks.refund;
  String legalAccountDeletionUrl = LegalLinks.accountDeletion;

  bool get maintenanceBlocksApp =>
      maintenanceMode && !kEjarzDemoMode && !adminBypassMaintenance;

  final List<ContractRecord> contracts = <ContractRecord>[];
  final List<PropertyRecord> properties = <PropertyRecord>[];
  final List<NotificationItem> notifications = <NotificationItem>[];
  final List<SupportTicketRecord> supportTickets = <SupportTicketRecord>[];
  final List<WalletTransaction> transactions = <WalletTransaction>[];
  final List<_PendingContractSubmission> _pendingContractSubmissions =
      <_PendingContractSubmission>[];
  final List<_PendingPropertySave> _pendingPropertySaves =
      <_PendingPropertySave>[];
  final Map<String, String> _syncedDraftIds = <String, String>{};
  FirebaseRepository? _repository;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<bool>? _onlineStateSubscription;
  StreamSubscription<List<ContractRecord>>? _contractsSubscription;
  StreamSubscription<List<PropertyRecord>>? _propertiesSubscription;
  StreamSubscription<List<NotificationItem>>? _notificationsSubscription;
  StreamSubscription<List<SupportTicketRecord>>? _supportTicketsSubscription;
  StreamSubscription<String>? _fcmTokenSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _contentSubscription;
  Timer? _serverReachabilityTimer;
  bool _checkingServerReachability = false;

  int get pendingSyncCount =>
      _pendingContractSubmissions.length + _pendingPropertySaves.length;
  bool get hasPendingSync => pendingSyncCount > 0;
  bool isPropertyPendingSync(String propertyId) =>
      _pendingPropertySaves.any((item) => item.localId == propertyId);
  bool get hasCachedUserData =>
      contracts.isNotEmpty ||
      properties.isNotEmpty ||
      notifications.isNotEmpty ||
      supportTickets.isNotEmpty;

  AppController() {
    if (kEjarzLocalDemoMode) {
      _seedData();
      return;
    }
    if (FirebaseBootstrap.initialized) {
      _configureFirebase();
    } else {
      // Startup is intentionally non-blocking on every platform. Attach the
      // controller as soon as Firebase becomes ready instead of requiring it
      // to have completed before runApp.
      unawaited(_configureFirebaseWhenReady());
    }
    if (!kReleaseMode && !kEjarzDemoMode) {
      _seedData();
    }
  }

  Future<void> _configureFirebaseWhenReady() async {
    try {
      await FirebaseBootstrap.ready;
    } catch (_) {
      // Firebase is optional during launch. The UI remains usable and the
      // authentication flow can report an actionable connection error later.
      return;
    }
    if (!FirebaseBootstrap.initialized) return;
    _configureFirebase();
  }

  void _configureFirebase() {
    if (_repository != null) return;
    _repository = FirebaseRepository();
    if (kIsWeb) {
      unawaited(_syncCurrentWebUser());
    } else {
      _authSubscription =
          FirebaseAuth.instance.authStateChanges().listen(_syncFirebaseUser);
    }
    _contentSubscription = FirebaseFirestore.instance
        .collection('appContent')
        .doc('config')
        .snapshots()
        .listen(_syncAppContent);
  }

  Future<void> _syncCurrentWebUser() async {
    try {
      await Future<void>.delayed(Duration.zero);
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) _syncFirebaseUser(user);
    } catch (_) {
      // Keep the UI visible if the web auth bridge is unavailable.
    }
  }

  void _syncFirebaseUser(User? user) {
    if (user == null) {
      adminBypassMaintenance = false;
      _cancelUserStreams();
      return;
    }
    userPhone = user.phoneNumber ?? userPhone;
    userEmail = user.email ?? userEmail;
    unawaited(_bindFirebaseUser(user));
    notifyListeners();
  }

  Future<void> _bindFirebaseUser(User user) async {
    final repository = _repository;
    if (repository == null) return;
    try {
      if (kEjarzFirebaseDemoMode) {
        await repository.ensureUserProfile(
          uid: user.uid,
          phone: user.phoneNumber ?? userPhone,
          name: userName,
          email: user.email ?? userEmail,
          isDemo: true,
        );
        await repository.ensureDemoUserData(
          uid: user.uid,
          customerName: userName,
          customerPhone: userPhone,
          customerEmail: userEmail,
        );
      } else {
        final profileExists = await repository.userProfileExists(user.uid);
        if (!profileExists) {
          loggedIn = false;
          accountBlocked = false;
          _cancelUserStreams();
          notifyListeners();
          return;
        }
      }
      final prefs = await repository.userNotificationPrefs(user.uid);
      pushNotificationsEnabled = prefs['push'] != false;
      adminBypassMaintenance = await repository.isAdminUser(user.uid);
      unawaited(_registerMessagingToken(user.uid));
      final status = await repository.userStatus(user.uid);
      accountBlocked = status == 'blocked' || status == 'suspended';
      if (accountBlocked) {
        loggedIn = false;
        notifyListeners();
        return;
      }
    } catch (error) {
      loggedIn = true;
      accountBlocked = false;
      _handleServerOperationFailure(
        error,
        'تعذر الاتصال بالخادم. تم فتح التطبيق بآخر بيانات محفوظة.',
      );
    }
    loggedIn = true;
    _cancelUserStreams();
    _onlineStateSubscription = repository.watchUserOnlineState(user.uid).listen(
          _handleOnlineState,
          onError: (Object error) => _handleUserStreamError(
            error,
            _serverReachabilityCheckMessage,
          ),
        );
    _contractsSubscription =
        repository.watchUserContracts(user.uid).listen((items) {
      final pendingLocal =
          contracts.where((item) => item.pendingSync).toList(growable: false);
      contracts
        ..clear()
        ..addAll(items);
      for (final pending in pendingLocal) {
        if (!contracts.any((item) => item.id == pending.id)) {
          contracts.insert(0, pending);
        }
      }
      lastSyncedAt = DateTime.now();
      notifyListeners();
    },
            onError: (Object error) => _handleUserStreamError(
                  error,
                  'تعذر تحديث العقود الآن. يتم عرض آخر بيانات محفوظة.',
                ));
    _propertiesSubscription =
        repository.watchUserProperties(user.uid).listen((items) {
      final pendingIds =
          _pendingPropertySaves.map((item) => item.localId).toSet();
      final pendingLocal = properties
          .where((item) => pendingIds.contains(item.id))
          .toList(growable: false);
      properties
        ..clear()
        ..addAll(items);
      for (final pending in pendingLocal) {
        if (!properties.any((item) => item.id == pending.id)) {
          properties.insert(0, pending);
        }
      }
      lastSyncedAt = DateTime.now();
      notifyListeners();
    },
            onError: (Object error) => _handleUserStreamError(
                  error,
                  'تعذر تحديث العقارات الآن. يتم عرض آخر بيانات محفوظة.',
                ));
    _notificationsSubscription =
        repository.watchUserNotifications(user.uid).listen((items) {
      notifications
        ..clear()
        ..addAll(items);
      lastSyncedAt = DateTime.now();
      notifyListeners();
    },
            onError: (Object error) => _handleUserStreamError(
                  error,
                  'تعذر تحديث الإشعارات الآن. يتم عرض آخر بيانات محفوظة.',
                ));
    _supportTicketsSubscription =
        repository.watchUserSupportTickets(user.uid).listen((items) {
      supportTickets
        ..clear()
        ..addAll(items);
      lastSyncedAt = DateTime.now();
      notifyListeners();
    },
            onError: (Object error) => _handleUserStreamError(
                  error,
                  'تعذر تحديث الدعم الفني الآن. يتم عرض آخر بيانات محفوظة.',
                ));
  }

  void _cancelUserStreams() {
    _onlineStateSubscription?.cancel();
    _contractsSubscription?.cancel();
    _propertiesSubscription?.cancel();
    _notificationsSubscription?.cancel();
    _supportTicketsSubscription?.cancel();
    _fcmTokenSubscription?.cancel();
    _serverReachabilityTimer?.cancel();
    _onlineStateSubscription = null;
    _contractsSubscription = null;
    _propertiesSubscription = null;
    _notificationsSubscription = null;
    _supportTicketsSubscription = null;
    _fcmTokenSubscription = null;
    _serverReachabilityTimer = null;
  }

  void _markOffline([String message = 'أنت غير متصل بالإنترنت.']) {
    offlineMode = true;
    offlineMessage = message;
    notifyListeners();
  }

  void _markOnline({bool notify = true}) {
    _serverReachabilityTimer?.cancel();
    _serverReachabilityTimer = null;
    offlineMode = false;
    offlineMessage = '';
    lastSyncedAt = DateTime.now();
    if (notify) notifyListeners();
    if (pendingSyncCount > 0) {
      unawaited(syncPendingChangesNow());
    }
  }

  void _handleOnlineState(bool online) {
    if (online) {
      _markOnline();
    } else if (offlineMode) {
      _scheduleServerReachabilityCheck(
        _serverReachabilityCheckMessage,
      );
    }
  }

  void _handleUserStreamError(Object error, String offlineMessage) {
    if (_isConnectivityFailure(error)) {
      _markOffline(offlineMessage);
      return;
    }
    _scheduleServerReachabilityCheck(offlineMessage, delay: Duration.zero);
  }

  void _handleServerOperationFailure(Object error, String offlineMessage) {
    if (_isConnectivityFailure(error)) {
      _markOffline(offlineMessage);
      return;
    }
    _scheduleServerReachabilityCheck(offlineMessage, delay: Duration.zero);
  }

  void _scheduleServerReachabilityCheck(
    String offlineMessage, {
    Duration delay = const Duration(seconds: 2),
  }) {
    if (kEjarzLocalDemoMode) return;
    _serverReachabilityTimer?.cancel();
    _serverReachabilityTimer = Timer(delay, () {
      unawaited(_verifyServerReachability(offlineMessage));
    });
  }

  Future<void> _verifyServerReachability(String offlineMessage) async {
    if (_checkingServerReachability) return;
    final repository = _repository;
    final user = FirebaseBootstrap.initialized
        ? FirebaseAuth.instance.currentUser
        : null;
    if (repository == null || user == null) return;
    _checkingServerReachability = true;
    try {
      await repository
          .verifyServerReachable(user.uid)
          .timeout(const Duration(seconds: 8));
      _markOnline();
    } catch (error) {
      if (_isConnectivityFailure(error)) {
        _markOffline(offlineMessage);
      }
    } finally {
      _checkingServerReachability = false;
    }
  }

  bool _isConnectivityFailure(Object error) {
    if (error is TimeoutException) return true;
    if (error is FirebaseException) {
      return switch (error.code) {
        'unavailable' ||
        'deadline-exceeded' ||
        'network-request-failed' ||
        'retry-limit-exceeded' =>
          true,
        _ => false,
      };
    }
    return false;
  }

  Future<void> syncPendingChangesNow() async {
    if (syncingPendingChanges || pendingSyncCount == 0) return;
    final repository = _repository;
    final user = FirebaseBootstrap.initialized
        ? FirebaseAuth.instance.currentUser
        : null;
    if (repository == null || user == null) {
      _markOffline('تسجيل الدخول والاتصال مطلوبان لمزامنة المسودات.');
      return;
    }
    syncingPendingChanges = true;
    notifyListeners();
    final pendingItems =
        List<_PendingContractSubmission>.of(_pendingContractSubmissions);
    for (final pending in pendingItems) {
      try {
        final synced = await repository.submitContract(
          uid: user.uid,
          customerName: userName,
          customerPhone: userPhone,
          customerEmail: userEmail,
          draft: pending.draft,
          status: pending.status,
          existingDraftId: pending.remoteDraftId,
          progress: pending.progress,
        );
        if (pending.localId != synced.id) {
          _syncedDraftIds[pending.localId] = synced.id;
        }
        _pendingContractSubmissions.remove(pending);
        contracts.removeWhere(
          (item) => item.id == synced.id && item.id != pending.localId,
        );
        final index =
            contracts.indexWhere((item) => item.id == pending.localId);
        if (index == -1) {
          contracts.insert(0, synced);
        } else {
          contracts[index] = synced;
        }
        lastSyncedAt = DateTime.now();
      } catch (error) {
        syncingPendingChanges = false;
        _handleServerOperationFailure(
          error,
          'تعذرت المزامنة الآن. سنعيد المحاولة عند عودة الاتصال.',
        );
        notifyListeners();
        return;
      }
    }
    final pendingProperties = List<_PendingPropertySave>.of(
      _pendingPropertySaves,
    );
    for (final pending in pendingProperties) {
      try {
        final saved = await repository.saveProperty(
          uid: user.uid,
          data: pending.data,
          propertyId: pending.propertyId,
          unitEdits: pending.unitEdits,
          initialUnits: pending.unitEdits,
          expectedUnits: pending.expectedUnits,
          replacingNumber: pending.replacingNumber,
        );
        _pendingPropertySaves.remove(pending);
        final index =
            properties.indexWhere((item) => item.id == pending.localId);
        if (index == -1) {
          final remoteIndex =
              properties.indexWhere((item) => item.id == saved.id);
          if (remoteIndex == -1) {
            properties.insert(0, saved);
          } else {
            properties[remoteIndex] = saved;
          }
        } else {
          properties[index] = saved;
        }
        lastSyncedAt = DateTime.now();
      } catch (error) {
        syncingPendingChanges = false;
        _handleServerOperationFailure(
          error,
          'تعذرت المزامنة الآن. سنعيد المحاولة عند عودة الاتصال.',
        );
        notifyListeners();
        return;
      }
    }
    syncingPendingChanges = false;
    offlineMode = false;
    offlineMessage = '';
    lastSyncedAt = DateTime.now();
    notifyListeners();
  }

  Future<void> _registerMessagingToken(String uid) async {
    final repository = _repository;
    if (repository == null || kIsWeb) return;
    final token = await AppNotificationService.currentToken();
    if (token != null && token.trim().isNotEmpty) {
      await repository.saveFcmToken(
        uid: uid,
        token: token,
        platform: defaultTargetPlatform.name,
      );
    }
    await _fcmTokenSubscription?.cancel();
    _fcmTokenSubscription =
        AppNotificationService.tokenRefresh.listen((newToken) {
      unawaited(repository.saveFcmToken(
        uid: uid,
        token: newToken,
        platform: defaultTargetPlatform.name,
      ));
    });
  }

  void _syncAppContent(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    if (data == null) return;
    maintenanceMode = data['maintenanceMode'] == true;
    final legalLinks = data['legalLinks'];
    if (legalLinks is Map) {
      legalPrivacyUrl = _contentTextMap(legalLinks, 'privacy', legalPrivacyUrl);
      legalTermsUrl = _contentTextMap(legalLinks, 'terms', legalTermsUrl);
      legalRefundUrl = _contentTextMap(legalLinks, 'refund', legalRefundUrl);
      legalAccountDeletionUrl = _contentTextMap(
        legalLinks,
        'accountDeletion',
        legalAccountDeletionUrl,
      );
    }
    homeGreetingPrefix =
        _contentText(data, 'homeGreetingPrefix', homeGreetingPrefix);
    homeWelcomeText = _contentText(data, 'homeWelcome', homeWelcomeText);
    homeHeroTitle = _contentText(data, 'homeHeroTitle', homeHeroTitle);
    homeHeroSubtitle = _contentText(data, 'homeHeroSubtitle', homeHeroSubtitle);
    homeHeroButtonText =
        _contentText(data, 'homeHeroButtonText', homeHeroButtonText);
    homeServicesTitle =
        _contentText(data, 'homeServicesTitle', homeServicesTitle);
    homeServicesAction =
        _contentText(data, 'homeServicesAction', homeServicesAction);
    serviceResidentialTitle =
        _contentText(data, 'serviceResidentialTitle', serviceResidentialTitle);
    serviceResidentialSubtitle = _contentText(
        data, 'serviceResidentialSubtitle', serviceResidentialSubtitle);
    serviceCommercialTitle =
        _contentText(data, 'serviceCommercialTitle', serviceCommercialTitle);
    serviceCommercialSubtitle = _contentText(
        data, 'serviceCommercialSubtitle', serviceCommercialSubtitle);
    serviceRenewalTitle =
        _contentText(data, 'serviceRenewalTitle', serviceRenewalTitle);
    serviceRenewalSubtitle =
        _contentText(data, 'serviceRenewalSubtitle', serviceRenewalSubtitle);
    serviceRenewalMessage =
        _contentText(data, 'serviceRenewalMessage', serviceRenewalMessage);
    serviceHandoverTitle =
        _contentText(data, 'serviceHandoverTitle', serviceHandoverTitle);
    serviceHandoverSubtitle =
        _contentText(data, 'serviceHandoverSubtitle', serviceHandoverSubtitle);
    serviceHandoverMessage =
        _contentText(data, 'serviceHandoverMessage', serviceHandoverMessage);
    homePropertiesTitle =
        _contentText(data, 'homePropertiesTitle', homePropertiesTitle);
    homePropertiesAction =
        _contentText(data, 'homePropertiesAction', homePropertiesAction);
    homeEmptyPropertiesTitle = _contentText(
        data, 'homeEmptyPropertiesTitle', homeEmptyPropertiesTitle);
    homeEmptyPropertiesSubtitle = _contentText(
        data, 'homeEmptyPropertiesSubtitle', homeEmptyPropertiesSubtitle);
    homeEmptyPropertiesAction = _contentText(
        data, 'homeEmptyPropertiesAction', homeEmptyPropertiesAction);
    homeContractsTitle =
        _contentText(data, 'homeContractsTitle', homeContractsTitle);
    homeContractsAction =
        _contentText(data, 'homeContractsAction', homeContractsAction);
    homeEmptyContractsTitle =
        _contentText(data, 'homeEmptyContractsTitle', homeEmptyContractsTitle);
    homeEmptyContractsSubtitle = _contentText(
        data, 'homeEmptyContractsSubtitle', homeEmptyContractsSubtitle);
    homeEmptyContractsAction = _contentText(
        data, 'homeEmptyContractsAction', homeEmptyContractsAction);
    notifyListeners();
  }

  String _contentText(
    Map<String, dynamic> data,
    String key,
    String fallback,
  ) {
    final value = data[key];
    if (value is! String) return fallback;
    final trimmed = value.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }

  String _contentTextMap(
    Map<Object?, Object?> data,
    String key,
    String fallback,
  ) {
    final value = data[key];
    if (value is! String) return fallback;
    final trimmed = value.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _contentSubscription?.cancel();
    _serverReachabilityTimer?.cancel();
    _cancelUserStreams();
    super.dispose();
  }

  void _seedData() {
    if (contracts.isNotEmpty ||
        properties.isNotEmpty ||
        notifications.isNotEmpty ||
        transactions.isNotEmpty) {
      return;
    }
    contracts.addAll(<ContractRecord>[
      ContractRecord(
        id: 'EJ-DEMO-1009',
        requestNumber: 'REQ-DEMO-1009',
        uid: 'demo-user',
        type: ContractType.residential,
        role: UserRole.tenant,
        title: 'عقد سكني - شقة الياسمين',
        property: 'الرياض - حي الياسمين',
        lessorName: 'عبدالله العتيبي',
        tenantName: 'سالم الدوسري',
        date: '2026/07/04',
        status: ContractStatus.awaitingPayment,
        totalFees: 299,
        timeline: _timelineFor(ContractStatus.awaitingPayment),
        paymentStatus: 'pending',
        customerVisibleNote:
            'طلبك جاهز للدفع. إجمالي الرسوم 299 ريال، شاملة رسوم منصة إيجار.',
      ),
      ContractRecord(
        id: 'EJ-DEMO-1008',
        requestNumber: 'REQ-DEMO-1008',
        uid: 'demo-user',
        type: ContractType.commercial,
        role: UserRole.authorized,
        title: 'عقد تجاري - مكتب العليا',
        property: 'الرياض - العليا - طريق التخصصي',
        lessorName: 'شركة الرواد',
        tenantName: 'مؤسسة الإبداع',
        date: '2026/07/03',
        status: ContractStatus.missingData,
        totalFees: 799,
        timeline: _timelineFor(ContractStatus.missingData),
        customerVisibleNote:
            'توجد ملاحظات مراجعة على بعض البيانات والمستندات. يرجى الاطلاع عليها وإرسال التصحيح المطلوب.',
        missingRequirements: const <MissingRequirement>[
          MissingRequirement(
            id: 'MR-DEMO-01',
            title: 'السجل التجاري',
            description:
                'السجل التجاري المرفق غير واضح. يرجى إعادة رفع نسخة واضحة وكاملة.',
            type: 'file',
            issueCode: 'unclear',
            fieldPath: 'tenant.company.commercialRecordImage',
          ),
          MissingRequirement(
            id: 'MR-DEMO-02',
            title: 'رقم عداد الكهرباء',
            description:
                'تعذر التحقق من رقم عداد الكهرباء. يرجى مراجعته وإدخال القيمة الصحيحة.',
            type: 'field',
            issueCode: 'unverifiable',
            fieldPath: 'property.unit.electricityMeter',
          ),
        ],
      ),
      ContractRecord(
        id: 'EJ-DEMO-1007',
        requestNumber: 'REQ-DEMO-1007',
        uid: 'demo-user',
        type: ContractType.residential,
        role: UserRole.lessor,
        title: 'عقد سكني - فيلا النرجس',
        property: 'الرياض - حي النخيل',
        lessorName: 'محمد العتيبي',
        tenantName: 'خالد الشهري',
        date: '2026/07/02',
        status: ContractStatus.processing,
        totalFees: 299,
        timeline: _timelineFor(ContractStatus.processing),
        paymentStatus: 'paid',
        customerVisibleNote: 'تم استلام الدفع، وطلبك الآن قيد المعالجة.',
      ),
      ContractRecord(
        id: 'EJ-DEMO-1006',
        requestNumber: 'REQ-DEMO-1006',
        uid: 'demo-user',
        type: ContractType.commercial,
        role: UserRole.authorized,
        title: 'عقد تجاري - محل الواجهة',
        property: 'جدة - حي السلامة',
        lessorName: 'شركة الواجهة التجارية',
        tenantName: 'مؤسسة الخليج للتجزئة',
        date: '2026/06/30',
        status: ContractStatus.processing,
        totalFees: 799,
        timeline: _timelineFor(ContractStatus.processing),
        paymentStatus: 'paid',
        customerVisibleNote: 'طلبك قيد المعالجة لدى الفريق.',
      ),
      ContractRecord(
        id: 'EJ-DEMO-1005',
        requestNumber: 'REQ-DEMO-1005',
        uid: 'demo-user',
        type: ContractType.residential,
        role: UserRole.lessor,
        title: 'عقد سكني - شقة الملقا',
        property: 'الرياض - حي الملقا',
        lessorName: 'نورة القحطاني',
        tenantName: 'عبدالعزيز المطيري',
        date: '2026/06/29',
        status: ContractStatus.processing,
        totalFees: 299,
        timeline: _timelineFor(ContractStatus.processing),
        paymentStatus: 'paid',
        customerVisibleNote: 'طلبك قيد المعالجة لدى الفريق.',
      ),
      ContractRecord(
        id: 'EJ-DEMO-1004',
        requestNumber: 'REQ-DEMO-1004',
        uid: 'demo-user',
        type: ContractType.commercial,
        role: UserRole.lessor,
        title: 'عقد تجاري - مستودع السلي',
        property: 'الرياض - حي السلي',
        lessorName: 'شركة المخازن الحديثة',
        tenantName: 'شركة الإمداد السريع',
        date: '2026/06/27',
        status: ContractStatus.processing,
        totalFees: 799,
        timeline: _timelineFor(ContractStatus.processing),
        customerVisibleNote: 'طلبك قيد المعالجة لدى الفريق.',
      ),
      ContractRecord(
        id: 'EJ-DEMO-1003',
        requestNumber: 'REQ-DEMO-1003',
        uid: 'demo-user',
        type: ContractType.residential,
        role: UserRole.tenant,
        title: 'عقد سكني - شقة الروضة',
        property: 'الرياض - حي الروضة',
        lessorName: 'محمد العتيبي',
        tenantName: 'ناصر القحطاني',
        date: '2026/06/24',
        status: ContractStatus.authenticated,
        totalFees: 299,
        timeline: _timelineFor(ContractStatus.authenticated),
        finalPdfUrl: kDemoContractPdfUrl,
        finalPdfFileName: kDemoContractPdfFileName,
        paymentStatus: 'paid',
        paymentId: 'PAY-DEMO-1003',
        invoiceId: 'INV-DEMO-1003',
        invoiceNumber: 'INV-202606-1003',
        paymentMethod: 'mada',
        paymentProvider: 'demo',
        paymentReference: 'DEMO-1003',
        cardBrand: 'Mada',
        cardLast4: '1111',
        paidAt: '2026/06/24',
      ),
      ContractRecord(
        id: 'EJ-DEMO-1002',
        requestNumber: 'REQ-DEMO-1002',
        uid: 'demo-user',
        type: ContractType.residential,
        role: UserRole.lessor,
        title: 'مسودة عقد - شقة قرطبة',
        property: 'الرياض - حي قرطبة',
        lessorName: 'عميل النسخة التجريبية',
        tenantName: 'لم يتم تحديد المستأجر',
        date: '2026/06/22',
        status: ContractStatus.draft,
        totalFees: 0,
        timeline: _timelineFor(ContractStatus.draft),
        customerVisibleNote:
            'هذه مسودة محفوظة محليًا ويمكن إكمالها لاحقًا قبل الإرسال.',
        draftData: _demoSavedDraft(),
        draftProgress: const DraftProgress(
          lastStep: 2,
          touchedSections: <String>['contract', 'property', 'parties'],
        ),
      ),
      ContractRecord(
        id: 'EJ-DEMO-1001',
        requestNumber: 'REQ-DEMO-1001',
        uid: 'demo-user',
        type: ContractType.commercial,
        role: UserRole.authorized,
        title: 'عقد تجاري - معرض الرياض',
        property: 'الرياض - طريق الملك فهد',
        lessorName: 'شركة الرواد',
        tenantName: 'مؤسسة الخليج',
        date: '2026/06/20',
        status: ContractStatus.rejected,
        totalFees: 799,
        timeline: _timelineFor(ContractStatus.rejected),
        rejectionReason:
            'تعذر التحقق من تطابق بيانات وثيقة الملكية مع بيانات المؤجر.',
      ),
    ].map(_withDemoDetails));

    properties.addAll(<PropertyRecord>[
      PropertyRecord(
        id: 'PROP-001',
        title: 'عمارة النرجس',
        city: 'الرياض',
        district: 'حي النرجس',
        type: 'عمارة',
        usage: 'سكن عوائل',
        floors: 4,
        totalUnits: 8,
        units: <UnitRecord>[
          const UnitRecord(
            number: '101',
            name: 'شقة 101',
            type: 'شقة',
            floor: 'الأول',
            area: '145 م²',
            status: 'متاحة',
          ),
          const UnitRecord(
            number: '202',
            name: 'شقة 202',
            type: 'شقة',
            floor: 'الثاني',
            area: '132 م²',
            status: 'مؤجرة',
          ),
        ],
        data: PropertyData(
          propertySource: 'عقار محفوظ',
          ownershipDocumentNumber: '310123456789',
          ownershipDocumentType: 'صك إلكتروني',
          ownershipDocumentDate: '2026/06/20',
          propertyUsage: 'سكن عوائل',
          propertyType: 'عمارة',
          floorsCount: '4',
          unitsPerFloor: '2',
          totalUnits: '8',
          city: 'الرياض',
          district: 'حي النرجس',
          street: 'طريق عثمان بن عفان',
          buildingNumber: '1234',
          additionalNumber: '5678',
          postalCode: '13327',
          buildingName: 'عمارة النرجس',
          unitNumber: '101',
          unitName: 'شقة 101',
          unitType: 'شقة',
          floor: '1',
          area: '145',
          roomsCount: '4',
          bathroomsCount: '3',
          hallsCount: '1',
          maidRoom: true,
          kitchen: true,
          storage: true,
          majlis: true,
          furnishingStatus: 'غير مؤثثة',
          acSplit: true,
          privateParking: true,
          electricityMeter: '700100101',
          waterMeter: '710100101',
          gasMeter: '720100101',
          notes: 'مدخل مستقل وموقف مخصص للوحدة.',
        ),
      ),
      PropertyRecord(
        id: 'PROP-002',
        title: 'فيلا الياسمين',
        city: 'الرياض',
        district: 'حي الياسمين',
        type: 'فيلا',
        usage: 'سكن عوائل',
        floors: 2,
        totalUnits: 1,
        units: <UnitRecord>[
          const UnitRecord(
            number: '1',
            name: 'الفيلا الرئيسية',
            type: 'فيلا',
            floor: 'أرضي + أول',
            area: '420 م²',
            status: 'متاحة',
          ),
        ],
        data: PropertyData(
          propertySource: 'عقار محفوظ',
          ownershipDocumentNumber: '310123456790',
          ownershipDocumentType: 'صك إلكتروني',
          ownershipDocumentDate: '2026/05/18',
          propertyUsage: 'سكن عوائل',
          propertyType: 'فيلا',
          floorsCount: '2',
          unitsPerFloor: '1',
          totalUnits: '1',
          city: 'الرياض',
          district: 'حي الياسمين',
          street: 'شارع أنس بن مالك',
          buildingNumber: '2468',
          additionalNumber: '1357',
          postalCode: '13325',
          buildingName: 'فيلا الياسمين',
          unitNumber: '1',
          unitName: 'الفيلا الرئيسية',
          unitType: 'فيلا',
          floor: 'أرضي + أول',
          area: '420',
          roomsCount: '5',
          bathroomsCount: '4',
          hallsCount: '2',
          maidRoom: true,
          kitchen: true,
          storage: true,
          majlis: true,
          furnishingStatus: 'غير مؤثثة',
          acSplit: true,
          acCentral: true,
          privateParking: true,
          electricityMeter: '700100102',
          waterMeter: '710100102',
          gasMeter: '720100102',
          notes: 'حوش خاص ومدخل سيارة مستقل.',
        ),
      ),
      PropertyRecord(
        id: 'PROP-003',
        title: 'مكتب العليا',
        city: 'الرياض',
        district: 'العليا',
        type: 'برج',
        usage: 'تجاري',
        floors: 12,
        totalUnits: 36,
        units: <UnitRecord>[
          const UnitRecord(
            number: '8A',
            name: 'مكتب 8A',
            type: 'مكتب إداري',
            floor: 'الثامن',
            area: '96 م²',
            status: 'متاح',
          ),
        ],
        data: PropertyData(
          propertySource: 'عقار محفوظ',
          ownershipDocumentNumber: '310123456791',
          ownershipDocumentType: 'صك إلكتروني',
          ownershipDocumentDate: '2026/04/12',
          propertyUsage: 'تجاري',
          propertyType: 'برج',
          floorsCount: '12',
          unitsPerFloor: '3',
          totalUnits: '36',
          city: 'الرياض',
          district: 'العليا',
          street: 'طريق الملك فهد',
          buildingNumber: '8642',
          additionalNumber: '2468',
          postalCode: '12214',
          buildingName: 'مكتب العليا',
          unitNumber: '8A',
          unitName: 'مكتب 8A',
          unitType: 'مكتب إداري',
          floor: '8',
          area: '96',
          roomsCount: '3',
          bathroomsCount: '2',
          hallsCount: '1',
          kitchen: true,
          storage: true,
          furnishingStatus: 'مؤثثة بأثاث جديد',
          acCentral: true,
          privateParking: true,
          electricityMeter: '700100103',
          waterMeter: '710100103',
          gasMeter: '720100103',
          notes: 'واجهة زجاجية ومواقف مخصصة للموظفين والعملاء.',
        ),
      ),
    ]);

    notifications.addAll(<NotificationItem>[
      NotificationItem(
        id: 'NTF-DEMO-1009',
        contractId: 'EJ-DEMO-1009',
        type: 'awaitingPayment',
        actionType: 'contractDetails',
        actionPayload: const <String, dynamic>{'contractId': 'EJ-DEMO-1009'},
        title: 'طلبك جاهز للدفع',
        body:
            'تمت مراجعة عقد شقة الياسمين. ادفع إجمالي الرسوم 299 ريال للمتابعة.',
        time: 'منذ 8 دقائق',
        icon: Icons.payments_outlined,
        color: const Color(0xFF9D6C00),
      ),
      NotificationItem(
        id: 'NTF-DEMO-1008',
        contractId: 'EJ-DEMO-1008',
        type: 'missingRequirement',
        actionType: 'contractDetails',
        actionPayload: const <String, dynamic>{'contractId': 'EJ-DEMO-1008'},
        title: 'يوجد نقص مطلوب',
        body:
            'يرجى إعادة رفع السجل التجاري بصورة واضحة ومراجعة رقم عداد الكهرباء لعقد مكتب العليا.',
        time: 'منذ 24 دقيقة',
        icon: Icons.error_outline_rounded,
        color: const Color(0xFFC94B4B),
      ),
      NotificationItem(
        id: 'NTF-DEMO-1004',
        contractId: 'EJ-DEMO-1004',
        type: 'processing',
        actionType: 'contractDetails',
        actionPayload: const <String, dynamic>{'contractId': 'EJ-DEMO-1004'},
        title: 'طلبك قيد المعالجة',
        body: 'يعمل الفريق على معالجة عقد مستودع السلي.',
        time: 'منذ ساعة',
        icon: Icons.schedule_rounded,
        color: const Color(0xFFE99015),
      ),
      NotificationItem(
        id: 'NTF-DEMO-1007',
        contractId: 'EJ-DEMO-1007',
        type: 'contractSubmitted',
        actionType: 'contractDetails',
        actionPayload: const <String, dynamic>{'contractId': 'EJ-DEMO-1007'},
        title: 'تم استلام طلبك',
        body: 'استلم فريقنا طلب عقد فيلا النرجس وسيتم مراجعته خلال وقت قصير.',
        time: 'منذ ساعتين',
        icon: Icons.inventory_2_outlined,
        color: const Color(0xFF2F73E0),
      ),
      NotificationItem(
        id: 'NTF-DEMO-1003',
        contractId: 'EJ-DEMO-1003',
        type: 'finalPdfUploaded',
        actionType: 'contractDetails',
        actionPayload: const <String, dynamic>{'contractId': 'EJ-DEMO-1003'},
        title: 'تم توثيق العقد',
        body: 'تم توثيق عقد شقة الروضة بنجاح ويمكنك تحميل النسخة النهائية.',
        time: 'أمس',
        icon: Icons.verified_outlined,
        color: const Color(0xFF16875E),
        read: true,
      ),
      NotificationItem(
        id: 'NTF-DEMO-1006',
        contractId: 'EJ-DEMO-1006',
        type: 'processing',
        actionType: 'contractDetails',
        actionPayload: const <String, dynamic>{'contractId': 'EJ-DEMO-1006'},
        title: 'طلبك قيد المعالجة',
        body: 'يعمل الفريق على معالجة عقد محل الواجهة.',
        time: 'قبل 3 أيام',
        icon: Icons.miscellaneous_services_outlined,
        color: const Color(0xFF2F73E0),
        read: true,
      ),
    ]);

    transactions.addAll(const <WalletTransaction>[
      WalletTransaction(
        title: 'رسوم عقد شقة الروضة',
        reference: 'PAY-DEMO-1003',
        date: '2026/06/24',
        amount: 299,
        contractId: 'EJ-DEMO-1003',
      ),
      WalletTransaction(
        title: 'استرداد طلب تجريبي مغلق',
        reference: 'REF-DEMO-1001',
        date: '2026/06/20',
        amount: 299,
        incoming: true,
        contractId: 'EJ-DEMO-1001',
      ),
    ]);
  }

  static ContractRecord _withDemoDetails(ContractRecord contract) {
    final price = ContractPrice.calculate(
        commercial: contract.type == ContractType.commercial,
        years: contract.type == ContractType.commercial ? 2 : 1);
    return contract.copyWith(
      totalFees: contract.status == ContractStatus.draft ? 0 : price.total,
      customerVisibleNote: contract.status == ContractStatus.awaitingPayment
          ? 'طلبك جاهز للدفع. إجمالي الرسوم ${price.total.toStringAsFixed(0)} ريال، شاملة رسوم منصة إيجار.'
          : contract.customerVisibleNote,
      contractDetails: _demoContractDetails(contract),
      partyDetails: _demoPartyDetails(contract),
      propertyDetails: _demoPropertyDetails(contract),
      attachmentFiles: _demoAttachmentFiles(contract),
    );
  }

  static ContractDraft _demoSavedDraft() {
    final draft = ContractDraft();
    draft.property
      ..ownershipDocumentNumber = '310123456789'
      ..ownershipDocumentDate = '2026/06/20';
    draft.lessor
      ..fullName = 'عميل النسخة التجريبية'
      ..idNumber = '1012345678'
      ..birthDate = '1990/01/01'
      ..mobile = '0501234567';
    return draft;
  }

  static Map<String, String> _demoContractDetails(ContractRecord contract) {
    final commercial = contract.type == ContractType.commercial;
    final price = ContractPrice.calculate(
        commercial: commercial, years: commercial ? 2 : 1);
    return <String, String>{
      'مدة العقد': commercial ? '24 شهرًا' : '12 شهرًا',
      'تاريخ بداية العقد': commercial ? '2026/08/01' : '2026/07/15',
      'تاريخ نهاية العقد': commercial ? '2028/07/31' : '2027/07/14',
      'قيمة الإيجار السنوي': commercial ? '120,000 ريال' : '48,000 ريال',
      'دورة السداد': commercial ? 'نصف سنوي' : 'ربع سنوي',
      'عدد الدفعات': commercial ? '4 دفعات' : '4 دفعات',
      'قناة السداد': 'سداد / إيجار',
      'رسوم السنة الأولى': '${price.firstYear.toStringAsFixed(0)} ريال',
      'رسوم المدة الإضافية':
          '${price.additionalAmount.toStringAsFixed(0)} ريال',
      'شمول الأسعار': ContractPrice.inclusionNote,
      'الضمان': commercial ? '10,000 ريال' : '4,000 ريال',
      'الشروط الإضافية': commercial
          ? 'يتحمل المستأجر رسوم التشغيل الداخلي والصيانة الاستهلاكية.'
          : 'يلتزم المستأجر بالمحافظة على الوحدة وتسليمها بحالة سليمة.',
    };
  }

  static Map<String, String> _demoPartyDetails(ContractRecord contract) {
    final commercial = contract.type == ContractType.commercial;
    return <String, String>{
      'المؤجر - الصفة': commercial ? 'شركة مالكة / مفوض' : 'مالك فرد',
      'المؤجر - رقم الهوية/السجل': commercial ? '1010456789' : '1023456789',
      'المؤجر - الجوال': '0501234567',
      'المؤجر - البريد الإلكتروني': 'lessor@example.com',
      'المستأجر - الصفة': commercial ? 'منشأة تجارية' : 'فرد',
      'المستأجر - رقم الهوية/السجل': commercial ? '4030456789' : '1098765432',
      'المستأجر - جوال أبشر': '0559876543',
      'المستأجر - البريد الإلكتروني': 'tenant@example.com',
      if (commercial) 'المفوض': 'عبدالعزيز السالم - تفويض رقم AUTH-2026-118',
    };
  }

  static Map<String, String> _demoPropertyDetails(ContractRecord contract) {
    final commercial = contract.type == ContractType.commercial;
    final city = contract.property.split(' - ').first;
    return <String, String>{
      'مصدر العقار': 'عقار محفوظ في التطبيق',
      'رقم وثيقة الملكية': commercial ? '560000918273' : '550000482913',
      'نوع وثيقة الملكية': 'صك إلكتروني',
      'تاريخ الوثيقة': '1447/01/18',
      'المدينة': city,
      'الحي': commercial ? 'العليا' : 'الياسمين',
      'الشارع': commercial ? 'طريق التخصصي' : 'شارع القمرية',
      'رقم المبنى': commercial ? '7722' : '3145',
      'الرمز البريدي': commercial ? '12211' : '13325',
      'نوع العقار': commercial ? 'برج تجاري' : 'عمارة سكنية',
      'استخدام العقار': commercial ? 'تجاري / إداري' : 'سكن عوائل',
      'اسم المبنى': commercial ? 'برج الأعمال' : 'عمارة الياسمين',
      'الدور': commercial ? 'الثامن' : 'الثاني',
      'رقم الوحدة': commercial ? '8A' : '202',
      'اسم الوحدة': commercial ? 'مكتب 8A' : 'شقة 202',
      'نوع الوحدة': commercial ? 'مكتب إداري' : 'شقة',
      'المساحة': commercial ? '96 م²' : '132 م²',
      'الغرف': commercial ? '3 مكاتب + قاعة اجتماعات' : '3 غرف + صالة',
      'عداد الكهرباء': commercial ? '1002458891' : '1002387712',
      'عداد المياه': commercial ? 'W-772245' : 'W-314502',
    };
  }

  static Map<String, String> _demoAttachmentFiles(ContractRecord contract) {
    final commercial = contract.type == ContractType.commercial;
    return <String, String>{
      'هوية المؤجر': 'lessor_id_${contract.id}.pdf',
      'هوية المستأجر': commercial
          ? 'tenant_commercial_record_${contract.id}.pdf'
          : 'tenant_id_${contract.id}.pdf',
      'وثيقة الملكية': 'ownership_${contract.id}.pdf',
      'العنوان الوطني': 'national_address_${contract.id}.pdf',
      if (commercial) 'تفويض المفوض': 'authorization_${contract.id}.pdf',
      if (commercial) 'السجل التجاري': 'commercial_record_${contract.id}.pdf',
      if (contract.finalPdfUrl.trim().isNotEmpty)
        'نسخة العقد النهائية': contract.finalPdfFileName,
    };
  }

  static List<StatusTimelineItem> _timelineFor(ContractStatus status) {
    if (status == ContractStatus.draft) {
      return const <StatusTimelineItem>[
        StatusTimelineItem(
          title: 'تم حفظ المسودة',
          subtitle: 'لم يتم إرسال الطلب للمراجعة بعد',
          date: '2026/06/22',
          time: '09:20 ص',
          current: true,
        ),
      ];
    }
    if (status == ContractStatus.awaitingPayment) {
      return const <StatusTimelineItem>[
        StatusTimelineItem(
          title: 'تم إنشاء الطلب',
          subtitle: 'تم إنشاء الطلب بنجاح',
          date: '2026/07/04',
          time: '10:30 ص',
          completed: true,
        ),
        StatusTimelineItem(
          title: 'بانتظار الدفع',
          subtitle: 'ادفع رسوم العقد للمتابعة إلى قيد المعالجة',
          date: '2026/07/04',
          time: '10:31 ص',
          current: true,
        ),
      ];
    }
    if (status == ContractStatus.rejected) {
      return const <StatusTimelineItem>[
        StatusTimelineItem(
          title: 'تم استلام الطلب',
          subtitle: 'تم استلام الطلب بنجاح',
          date: '2026/06/20',
          time: '10:30 ص',
          completed: true,
        ),
        StatusTimelineItem(
          title: 'قيد المعالجة',
          subtitle: 'تمت مراجعة بيانات الطلب',
          date: '2026/06/20',
          time: '11:15 ص',
          completed: true,
          eventStatus: ContractStatus.processing,
        ),
        StatusTimelineItem(
          title: 'تم رفض الطلب نهائيًا',
          subtitle:
              'سبب الرفض: تعذر التحقق من تطابق بيانات وثيقة الملكية مع بيانات المؤجر.',
          date: '2026/06/20',
          time: '01:10 م',
          current: true,
          eventStatus: ContractStatus.rejected,
        ),
      ];
    }
    final currentIndex = switch (status) {
      ContractStatus.draft => -1,
      ContractStatus.awaitingPayment => -1,
      ContractStatus.processing => 0,
      ContractStatus.missingData => 0,
      ContractStatus.authenticated => 1,
      ContractStatus.rejected => -1,
    };

    final labels = <({String title, String subtitle, String time})>[
      (
        title: 'قيد المعالجة',
        subtitle: 'يعمل الفريق على معالجة طلبك',
        time: '11:15 ص',
      ),
      (
        title: 'مكتمل',
        subtitle: 'تم إصدار العقد النهائي بنجاح',
        time: '01:10 م',
      ),
    ];

    return <StatusTimelineItem>[
      const StatusTimelineItem(
        title: 'تم استلام الطلب',
        subtitle: 'تم استلام الطلب بنجاح',
        date: '2024/05/20',
        time: '10:30 ص',
        completed: true,
      ),
      for (var i = 0; i < labels.length; i++)
        StatusTimelineItem(
          title: labels[i].title,
          subtitle: labels[i].subtitle,
          date: '2024/05/20',
          time: labels[i].time,
          completed: i < currentIndex ||
              (status == ContractStatus.authenticated && i <= currentIndex),
          current: i == currentIndex && status != ContractStatus.authenticated,
        ),
    ];
  }

  int get unreadNotifications =>
      notifications.where((item) => !item.read).length;
  int get activeContracts => contracts
      .where((contract) =>
          contract.status != ContractStatus.authenticated &&
          contract.status != ContractStatus.rejected)
      .length;
  int get awaitingContracts => contracts
      .where((contract) => contract.status == ContractStatus.processing)
      .length;
  int get completedContracts => contracts
      .where((contract) => contract.status == ContractStatus.authenticated)
      .length;
  int get processingContracts => contracts
      .where((contract) => contract.status == ContractStatus.processing)
      .length;
  int get availableUnits => properties.fold<int>(
        0,
        (total, property) =>
            total + property.units.where((unit) => unit.isAvailable).length,
      );

  void completeSplash() {
    splashCompleted = true;
    notifyListeners();
  }

  void completeOnboarding() {
    onboardingCompleted = true;
    notifyListeners();
  }

  void login({String? name, String? phone, String? email}) {
    userName = name?.trim().isNotEmpty == true
        ? name!.trim()
        : kEjarzDemoMode
            ? kDemoUserName
            : userName;
    userPhone = phone?.trim().isNotEmpty == true ? phone!.trim() : userPhone;
    userEmail = email?.trim().isNotEmpty == true
        ? email!.trim()
        : kEjarzDemoMode
            ? kDemoUserEmail
            : userEmail;
    loggedIn = true;
    accountBlocked = false;
    if (kEjarzLocalDemoMode) {
      if (contracts.isEmpty) _seedData();
      notifyListeners();
      return;
    }
    final user = FirebaseBootstrap.initialized
        ? FirebaseAuth.instance.currentUser
        : null;
    if (user != null) {
      unawaited(_bindFirebaseUser(user));
    } else if (kEjarzDemoMode && contracts.isEmpty) {
      _seedData();
    }
    notifyListeners();
  }

  void logout() {
    _pendingContractSubmissions.clear();
    _pendingPropertySaves.clear();
    _syncedDraftIds.clear();
    offlineMode = false;
    offlineMessage = '';
    syncingPendingChanges = false;
    if (kEjarzLocalDemoMode) {
      loggedIn = false;
      accountBlocked = false;
      mainNavigationIndex = 0;
      notifyListeners();
      return;
    }
    final user = FirebaseBootstrap.initialized
        ? FirebaseAuth.instance.currentUser
        : null;
    final repository = _repository;
    if (user != null && repository != null && !kIsWeb) {
      unawaited(AppNotificationService.currentToken().then((token) async {
        if (token == null || token.trim().isEmpty) return;
        await repository.deactivateFcmToken(uid: user.uid, token: token);
      }));
    }
    try {
      unawaited(FirebaseAuth.instance.signOut());
    } catch (_) {
      // Firebase may be unavailable in lightweight widget tests.
    }
    loggedIn = false;
    accountBlocked = false;
    mainNavigationIndex = 0;
    _cancelUserStreams();
    notifyListeners();
  }

  Future<void> deleteOwnAccount() async {
    if (kEjarzLocalDemoMode) {
      return;
    }
    if (!FirebaseBootstrap.initialized) {
      throw StateError('خدمة حذف الحساب غير متاحة الآن. حاول مرة أخرى لاحقًا.');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('يلزم تسجيل الدخول قبل حذف الحساب.');
    }
    final callable = FirebaseFunctions.instance.httpsCallable(
      'deleteOwnAccount',
      options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
    );
    final result = await callable.call<Map<String, dynamic>>(
      <String, Object?>{'confirmation': 'DELETE_ACCOUNT'},
    );
    if (result.data['deleted'] != true) {
      throw StateError('لم يؤكد الخادم اكتمال حذف الحساب.');
    }
  }

  Future<void> completeDeletedAccountSignOut() async {
    _cancelUserStreams();
    _pendingContractSubmissions.clear();
    _pendingPropertySaves.clear();
    _syncedDraftIds.clear();
    contracts.clear();
    properties.clear();
    notifications.clear();
    supportTickets.clear();
    transactions.clear();
    userName = 'عميل عقود';
    userPhone = '';
    userEmail = '';
    loggedIn = false;
    accountBlocked = false;
    mainNavigationIndex = 0;
    offlineMode = false;
    offlineMessage = '';
    syncingPendingChanges = false;
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      // The server has already deleted the account; local sign-out is best effort.
    }
    notifyListeners();
  }

  void setNavigationIndex(int index) {
    mainNavigationIndex = index;
    notifyListeners();
  }

  void toggleDarkMode(bool value) {
    darkMode = value;
    notifyListeners();
  }

  void toggleBiometric(bool value) {
    biometricEnabled = value;
    notifyListeners();
  }

  void togglePushNotifications(bool value) {
    pushNotificationsEnabled = value;
    if (value) {
      // Ask only after an explicit user action. Never show the iOS permission
      // dialog while the application is still launching.
      unawaited(_enablePushNotifications());
    }
    _persistNotificationPrefs();
    notifyListeners();
  }

  Future<void> _enablePushNotifications() async {
    try {
      final authorized = await AppNotificationService.requestPermission();
      if (!authorized) return;
      final user = FirebaseBootstrap.initialized
          ? FirebaseAuth.instance.currentUser
          : null;
      if (user != null) await _registerMessagingToken(user.uid);
    } catch (_) {
      // Notification failures must never affect the rest of the application.
    }
  }

  void _persistNotificationPrefs() {
    final repository = _repository;
    final user = FirebaseBootstrap.initialized
        ? FirebaseAuth.instance.currentUser
        : null;
    if (repository == null || user == null) return;
    unawaited(
      repository
          .updateNotificationPrefs(
        uid: user.uid,
        push: pushNotificationsEnabled,
      )
          .catchError((Object error) {
        _handleServerOperationFailure(
          error,
          'تم حفظ تفضيلات الإشعارات محليًا وسيتم تحديثها لاحقًا.',
        );
      }),
    );
  }

  Future<void> markAllNotificationsRead() async {
    for (final item in notifications) {
      item.read = true;
    }
    notifyListeners();
    final repository = _repository;
    final user = FirebaseBootstrap.initialized
        ? FirebaseAuth.instance.currentUser
        : null;
    if (repository != null && user != null) {
      try {
        await repository.markAllNotificationsRead(user.uid);
      } catch (error) {
        _handleServerOperationFailure(
          error,
          'تم تعليم الإشعارات محليًا وسيتم التحديث لاحقًا.',
        );
      }
    }
  }

  Future<void> markNotificationRead(NotificationItem item) async {
    item.read = true;
    notifyListeners();
    final repository = _repository;
    if (repository != null && item.id.isNotEmpty) {
      try {
        await repository.markNotificationRead(item.id);
      } catch (error) {
        _handleServerOperationFailure(
          error,
          'تم تعليم الإشعار محليًا وسيتم التحديث لاحقًا.',
        );
      }
    }
  }

  Future<void> markNotificationReadById(String notificationId) async {
    if (notificationId.trim().isEmpty) return;
    for (final item in notifications) {
      if (item.id == notificationId) {
        await markNotificationRead(item);
        return;
      }
    }
    final repository = _repository;
    if (repository != null) {
      try {
        await repository.markNotificationRead(notificationId);
      } catch (error) {
        _handleServerOperationFailure(
          error,
          'سيتم تعليم الإشعار كمقروء عند عودة الاتصال.',
        );
      }
    }
  }

  Future<ContractRecord?> contractById(String contractId) async {
    for (final contract in contracts) {
      if (contract.id == contractId) return contract;
    }
    final repository = _repository;
    if (repository == null) return null;
    try {
      final contract = await repository.fetchContract(contractId);
      if (contract != null) {
        _scheduleServerReachabilityCheck(
          _serverReachabilityCheckMessage,
          delay: Duration.zero,
        );
      }
      return contract;
    } catch (error) {
      _handleServerOperationFailure(
        error,
        'تعذر جلب تفاصيل العقد الآن. يتم عرض البيانات المحفوظة.',
      );
      return null;
    }
  }

  Future<String> createSupportTicket({
    ContractRecord? contract,
    required String subject,
    required String message,
    String priority = 'normal',
  }) async {
    final user = FirebaseBootstrap.initialized
        ? FirebaseAuth.instance.currentUser
        : null;
    final repository = _repository;
    if (repository == null || user == null) {
      throw StateError('تسجيل الدخول مطلوب لإرسال طلب الدعم.');
    }
    late final String ticketId;
    try {
      ticketId = await repository.createSupportTicket(
        uid: user.uid,
        customerName: userName,
        customerPhone: userPhone,
        customerEmail: userEmail,
        contractId: contract?.id ?? '',
        subject: subject,
        message: message,
        priority: priority,
      );
      _scheduleServerReachabilityCheck(
        _serverReachabilityCheckMessage,
        delay: Duration.zero,
      );
    } catch (error) {
      _handleServerOperationFailure(
        error,
        'الدعم الفني يحتاج اتصال بالإنترنت. حاول مرة أخرى عند عودة الاتصال.',
      );
      rethrow;
    }
    return ticketId;
  }

  Future<String> submitMissingRequirementResponse({
    required ContractRecord contract,
    required MissingRequirement requirement,
    required String message,
    String fileName = '',
  }) async {
    final user = FirebaseBootstrap.initialized
        ? FirebaseAuth.instance.currentUser
        : null;
    final repository = _repository;
    if (repository == null || user == null) {
      throw StateError('لا يمكن إرسال التصحيح دون تسجيل الدخول.');
    }
    late final String responseId;
    try {
      responseId = await repository.submitMissingRequirementResponse(
        uid: user.uid,
        contract: contract,
        requirement: requirement,
        message: message,
        fileName: fileName,
      );
      _scheduleServerReachabilityCheck(
        _serverReachabilityCheckMessage,
        delay: Duration.zero,
      );
    } catch (error) {
      _handleServerOperationFailure(
        error,
        'إرسال النواقص يحتاج اتصال بالإنترنت. جهّز الرد ثم أرسله عند عودة الاتصال.',
      );
      rethrow;
    }
    return responseId;
  }

  Future<PropertyRecord> saveProperty(
    PropertyData data, {
    PropertyRecord? existing,
    List<UnitRecord>? unitEdits,
    String replacingNumber = '',
  }) async {
    if (existing != null) {
      existing = properties.firstWhere((p) => p.id == existing!.id,
          orElse: () => existing!);
    }
    validatePropertyStructure(existing, data);
    final units = data.rentalMode == 'units'
        ? mergePropertyUnits(
            current: existing?.units ?? const [],
            additions: unitEdits ?? const [],
            capacity: int.tryParse(data.totalUnits) ?? 1,
            replacingNumber: replacingNumber,
          )
        : <UnitRecord>[
            UnitRecord.fromData(data,
                status: existing?.units.firstOrNull?.status ?? 'متاحة')
          ];
    final user = FirebaseBootstrap.initialized
        ? FirebaseAuth.instance.currentUser
        : null;
    final repository = _repository;
    final existingId = existing?.id ?? '';
    final priorPending = _pendingPropertySaves
        .where((item) => item.localId == existingId)
        .firstOrNull;
    if (repository != null && user != null) {
      try {
        final saved = await repository.saveProperty(
          uid: user.uid,
          data: data,
          propertyId: existingId.startsWith('PROP-') ? '' : existingId,
          unitEdits: unitEdits,
          replacingNumber: replacingNumber,
          initialUnits: units,
          expectedUnits: priorPending?.expectedUnits,
        );
        _pendingPropertySaves.removeWhere((item) => item.localId == existingId);
        final index = properties
            .indexWhere((item) => item.id == saved.id || item.id == existingId);
        if (index == -1) {
          properties.insert(0, saved);
        } else {
          properties[index] = saved;
        }
        _scheduleServerReachabilityCheck(
          _serverReachabilityCheckMessage,
          delay: Duration.zero,
        );
        notifyListeners();
        return saved;
      } catch (error) {
        if (error is StateError || !_isConnectivityFailure(error)) rethrow;
        _handleServerOperationFailure(
          error,
          'تعذر حفظ العقار على الخادم. تم حفظه محليًا وسيتم رفعه لاحقًا.',
        );
      }
    }

    final local = managedPropertyRecord(
      data,
      existing?.id ?? 'PROP-${DateTime.now().millisecondsSinceEpoch}',
      units,
    );
    final index = properties.indexWhere((item) => item.id == local.id);
    if (index == -1) {
      properties.insert(0, local);
    } else {
      properties[index] = local;
    }
    if (!kEjarzLocalDemoMode) {
      final previousPending = _pendingPropertySaves
          .where((item) => item.localId == local.id)
          .firstOrNull;
      _pendingPropertySaves.removeWhere((item) => item.localId == local.id);
      _pendingPropertySaves.add(
        _PendingPropertySave(
          localId: local.id,
          data: _clonePropertyData(data),
          propertyId: existingId.startsWith('PROP-') ? '' : existingId,
          unitEdits: units,
          expectedUnits: previousPending?.expectedUnits ?? existing?.units,
          replacingNumber: '',
        ),
      );
      if (offlineMode) {
        offlineMessage = 'تم حفظ العقار محليًا وستتم مزامنته تلقائيًا.';
      }
    }
    notifyListeners();
    return local;
  }

  ContractDraft _cloneDraft(ContractDraft source) {
    final clone = ContractDraft()
      ..type = source.type
      ..role = source.role
      ..startDate = source.startDate
      ..durationYears = source.durationYears
      ..durationMonths = source.durationMonths
      ..durationDays = source.durationDays
      ..endDate = source.endDate
      ..rentValue = source.rentValue
      ..rentPeriod = source.rentPeriod
      ..hasSecurityDeposit = source.hasSecurityDeposit
      ..securityDeposit = source.securityDeposit
      ..brokerageFee = source.brokerageFee
      ..brokeragePayer = source.brokeragePayer
      ..ownerSubjectToVat = source.ownerSubjectToVat
      ..vatValue = source.vatValue
      ..otherAmounts = source.otherAmounts
      ..paymentScheduleType = source.paymentScheduleType
      ..paymentFrequency = source.paymentFrequency
      ..paymentCount = source.paymentCount
      ..firstPaymentDate = source.firstPaymentDate
      ..paymentChannel = source.paymentChannel
      ..officialFeePayer = source.officialFeePayer
      ..serviceFeePayer = source.serviceFeePayer
      ..otherServices = source.otherServices
      ..allowSublease = source.allowSublease
      ..autoRenewal = source.autoRenewal
      ..specialTerms = source.specialTerms
      ..acceptAccuracyDeclaration = source.acceptAccuracyDeclaration
      ..acceptDataSharing = source.acceptDataSharing
      ..acceptTerms = source.acceptTerms
      ..paymentMethod = source.paymentMethod;
    clone.property = _clonePropertyData(source.property);
    clone.lessor = _clonePartyData(source.lessor);
    clone.tenant = _clonePartyData(source.tenant);
    clone.representative = _cloneRepresentativeData(source.representative);
    clone.electricity = _cloneServiceCharge(source.electricity);
    clone.water = _cloneServiceCharge(source.water);
    clone.gas = _cloneServiceCharge(source.gas);
    clone.installments = source.installments
        .map(
          (item) => InstallmentData(
            index: item.index,
            amount: item.amount,
            dueDate: item.dueDate,
            note: item.note,
          ),
        )
        .toList();
    clone.attachments = source.attachments
        .map(
          (item) => AttachmentData(
            keyName: item.keyName,
            title: item.title,
            required: item.required,
            uploaded: item.uploaded,
            fileName: item.fileName,
            sizeLabel: item.sizeLabel,
          ),
        )
        .toList();
    return clone;
  }

  PartyData _clonePartyData(PartyData source) {
    return PartyData(
      kind: source.kind,
      fullName: source.fullName,
      idType: source.idType,
      idNumber: source.idNumber,
      birthDate: source.birthDate,
      mobile: source.mobile,
      email: source.email,
      city: source.city,
      district: source.district,
      nationalAddress: source.nationalAddress,
      mobileRegisteredInAbsher: source.mobileRegisteredInAbsher,
      commercialRegistration: source.commercialRegistration,
      unifiedNumber: source.unifiedNumber,
      authorizedPersonName: source.authorizedPersonName,
      authorizedPersonId: source.authorizedPersonId,
      iban: source.iban,
      bankName: source.bankName,
      accountOwner: source.accountOwner,
    );
  }

  RepresentativeData _cloneRepresentativeData(RepresentativeData source) {
    return RepresentativeData(
      enabled: source.enabled,
      represents: source.represents,
      type: source.type,
      fullName: source.fullName,
      idType: source.idType,
      idNumber: source.idNumber,
      birthDate: source.birthDate,
      mobile: source.mobile,
      authorizationNumber: source.authorizationNumber,
      authorizationDate: source.authorizationDate,
      issuer: source.issuer,
      expiryDate: source.expiryDate,
    );
  }

  PropertyData _clonePropertyData(PropertyData source) {
    return PropertyData(
      rentalMode: source.rentalMode,
      savedPropertyId: source.savedPropertyId,
      propertySource: source.propertySource,
      ownershipDocumentNumber: source.ownershipDocumentNumber,
      ownershipDocumentType: source.ownershipDocumentType,
      ownershipDocumentDate: source.ownershipDocumentDate,
      propertyUsage: source.propertyUsage,
      propertyType: source.propertyType,
      floorsCount: source.floorsCount,
      unitsPerFloor: source.unitsPerFloor,
      totalUnits: source.totalUnits,
      city: source.city,
      district: source.district,
      street: source.street,
      buildingNumber: source.buildingNumber,
      additionalNumber: source.additionalNumber,
      postalCode: source.postalCode,
      buildingName: source.buildingName,
      unitNumber: source.unitNumber,
      unitName: source.unitName,
      unitType: source.unitType,
      floor: source.floor,
      area: source.area,
      roomsCount: source.roomsCount,
      bathroomsCount: source.bathroomsCount,
      hallsCount: source.hallsCount,
      maidRoom: source.maidRoom,
      kitchen: source.kitchen,
      storage: source.storage,
      majlis: source.majlis,
      furnishingStatus: source.furnishingStatus,
      acWindow: source.acWindow,
      acSplit: source.acSplit,
      acCentral: source.acCentral,
      privateParking: source.privateParking,
      electricityMeter: source.electricityMeter,
      waterMeter: source.waterMeter,
      gasMeter: source.gasMeter,
      notes: source.notes,
    );
  }

  ServiceCharge _cloneServiceCharge(ServiceCharge source) {
    return ServiceCharge(
      enabled: source.enabled,
      calculationMethod: source.calculationMethod,
      fixedAmount: source.fixedAmount,
      currentReading: source.currentReading,
    );
  }

  Future<DemoPaymentResult> submitDemoPayment({
    required ContractRecord contract,
    required DemoPaymentMethod method,
    required String cardBrand,
    required String cardLast4,
    required bool success,
  }) async {
    if (contract.pendingSync) {
      return const DemoPaymentResult(
        success: false,
        failureReason:
            'الدفع يحتاج اتصال بالإنترنت ومزامنة الطلب أولًا. جهّز العقد الآن وسيظهر الدفع بعد عودة الاتصال.',
      );
    }
    final user = FirebaseBootstrap.initialized
        ? FirebaseAuth.instance.currentUser
        : null;
    final repository = _repository;
    if (repository != null && user != null) {
      try {
        final result = await repository.submitDemoPayment(
          contract: contract,
          uid: user.uid,
          method: method,
          cardBrand: cardBrand,
          cardLast4: cardLast4,
          success: success,
        );
        _scheduleServerReachabilityCheck(
          _serverReachabilityCheckMessage,
          delay: Duration.zero,
        );
        if (result.success) {
          _applySuccessfulDemoPayment(
            contract: contract,
            method: method,
            result: result,
            cardBrand: cardBrand,
            cardLast4: cardLast4,
          );
        }
        return result;
      } catch (error) {
        _handleServerOperationFailure(
          error,
          'الدفع يحتاج اتصال بالإنترنت. حاول مرة أخرى عند عودة الاتصال.',
        );
        if (_isConnectivityFailure(error)) {
          return const DemoPaymentResult(
            success: false,
            failureReason:
                'الدفع يحتاج اتصال بالإنترنت. حاول مرة أخرى عند عودة الاتصال.',
          );
        }
        rethrow;
      }
    }

    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!success) {
      return const DemoPaymentResult(
        success: false,
        failureReason: 'تعذر إتمام عملية الدفع التجريبية',
      );
    }
    final now = DateTime.now();
    final result = DemoPaymentResult(
      success: true,
      paymentId: 'PAY-DEMO-${now.millisecondsSinceEpoch}',
      invoiceId: 'INV-DEMO-${now.millisecondsSinceEpoch}',
      invoiceNumber:
          'INV-${now.year}${now.month.toString().padLeft(2, '0')}-${contract.requestNumber.replaceAll(RegExp(r'[^0-9A-Z]'), '').padRight(6, '0').substring(0, 6)}',
      providerReference: 'DEMO-${now.millisecondsSinceEpoch}',
    );
    _applySuccessfulDemoPayment(
      contract: contract,
      method: method,
      result: result,
      cardBrand: cardBrand,
      cardLast4: cardLast4,
    );
    return result;
  }

  void _applySuccessfulDemoPayment({
    required ContractRecord contract,
    required DemoPaymentMethod method,
    required DemoPaymentResult result,
    required String cardBrand,
    required String cardLast4,
  }) {
    final index = contracts.indexWhere((item) => item.id == contract.id);
    if (index == -1) return;
    final now = DateTime.now();
    final date =
        '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final updatedTimeline = <StatusTimelineItem>[
      ...contracts[index].timeline,
      StatusTimelineItem(
        title: 'تم الدفع',
        subtitle: 'تم استلام رسوم الطلب بنجاح.',
        date: date,
        time: time,
        completed: true,
      ),
      StatusTimelineItem(
        title: 'قيد المعالجة',
        subtitle: 'تمت محاكاة معالجة الطلب تلقائيًا في نسخة العرض.',
        date: date,
        time: time,
        completed: true,
      ),
      StatusTimelineItem(
        title: 'مكتمل',
        subtitle: 'تم إصدار نموذج عقد تجريبي للمعاينة.',
        date: date,
        time: time,
        completed: true,
      ),
    ];
    contracts[index] = contracts[index].copyWith(
      status: ContractStatus.authenticated,
      totalFees: contract.totalFees,
      timeline: updatedTimeline,
      customerVisibleNote:
          'تمت محاكاة الدفع ومعالجة الطلب تلقائيًا لأغراض العرض، وأصبح نموذج العقد التجريبي جاهزًا للمعاينة.',
      finalPdfUrl: kDemoContractPdfUrl,
      finalPdfFileName: kDemoContractPdfFileName,
      paymentStatus: 'paid',
      paymentId: result.paymentId,
      invoiceId: result.invoiceId,
      invoiceNumber: result.invoiceNumber,
      paymentMethod: method.code,
      paymentProvider: 'demo',
      paymentReference: result.providerReference,
      cardBrand: cardBrand,
      cardLast4: cardLast4,
      paidAt: date,
    );
    notifications.insert(
      0,
      NotificationItem(
        id: 'NTF-${result.paymentId}',
        contractId: contract.id,
        type: 'payment',
        actionType: 'contractDetails',
        actionPayload: <String, dynamic>{'contractId': contract.id},
        title: 'اكتمل الطلب التجريبي',
        body:
            'تم الدفع التجريبي ومحاكاة معالجة الطلب تلقائيًا، وأصبح نموذج العقد جاهزًا للمعاينة.',
        time: 'الآن',
        icon: Icons.payments_outlined,
        color: const Color(0xFF16875E),
      ),
    );
    transactions.insert(
      0,
      WalletTransaction(
        title: 'رسوم ${contract.title}',
        reference: result.providerReference,
        date: date,
        amount: contract.totalFees,
        contractId: contract.id,
      ),
    );
    notifyListeners();
  }

  Future<ContractRecord> submitContract(
    ContractDraft draft, {
    String draftId = '',
    DraftProgress progress = const DraftProgress(),
  }) async {
    final effectiveDraftId = _syncedDraftIds[draftId] ?? draftId;
    final user = FirebaseBootstrap.initialized
        ? FirebaseAuth.instance.currentUser
        : null;
    final repository = _repository;
    if (repository != null && user != null) {
      try {
        final record = await repository.submitContract(
          uid: user.uid,
          customerName: userName,
          customerPhone: userPhone,
          customerEmail: userEmail,
          draft: draft,
          status: ContractStatus.awaitingPayment,
          existingDraftId: effectiveDraftId,
          progress: progress,
        );
        mainNavigationIndex = 1;
        _scheduleServerReachabilityCheck(
          _serverReachabilityCheckMessage,
          delay: Duration.zero,
        );
        notifyListeners();
        return record;
      } catch (error) {
        _handleServerOperationFailure(
          error,
          'تعذر إرسال العقد الآن. تم حفظه محليًا وسيتم رفعه عند عودة الاتصال.',
        );
        return _queueContractSubmission(
          draft,
          ContractStatus.awaitingPayment,
          existingDraftId: effectiveDraftId,
          progress: progress,
        );
      }
    }
    if (!kEjarzLocalDemoMode) {
      return _queueContractSubmission(
        draft,
        ContractStatus.awaitingPayment,
        existingDraftId: effectiveDraftId,
        progress: progress,
      );
    }
    return effectiveDraftId.isEmpty
        ? _submitContractLocally(draft, progress: progress)
        : _submitDraftLocally(
            effectiveDraftId,
            draft,
            progress: progress,
          );
  }

  ContractRecord _queueContractSubmission(
    ContractDraft draft,
    ContractStatus status, {
    String existingDraftId = '',
    DraftProgress progress = const DraftProgress(),
  }) {
    final existingIndex = existingDraftId.isEmpty
        ? -1
        : contracts.indexWhere((item) => item.id == existingDraftId);
    var remoteDraftId = '';
    for (final pending in _pendingContractSubmissions) {
      if (pending.localId == existingDraftId &&
          pending.remoteDraftId.isNotEmpty) {
        remoteDraftId = pending.remoteDraftId;
        break;
      }
    }
    if (remoteDraftId.isEmpty &&
        existingIndex >= 0 &&
        !contracts[existingIndex].pendingSync) {
      remoteDraftId = existingDraftId;
    }
    final record = status == ContractStatus.draft
        ? _saveDraftLocally(
            draft,
            pendingSync: true,
            existingDraftId: existingDraftId,
            progress: progress,
          )
        : existingDraftId.isNotEmpty
            ? _submitDraftLocally(
                existingDraftId,
                draft,
                pendingSync: true,
                progress: progress,
              )
            : _submitContractLocally(
                draft,
                pendingSync: true,
                progress: progress,
              );
    _pendingContractSubmissions.removeWhere(
      (item) => item.localId == record.id,
    );
    _pendingContractSubmissions.add(
      _PendingContractSubmission(
        localId: record.id,
        remoteDraftId: remoteDraftId,
        draft: _cloneDraft(draft),
        status: status,
        progress: progress,
      ),
    );
    if (offlineMode) {
      offlineMessage = 'تم حفظ التغييرات محليًا وستتم مزامنتها تلقائيًا.';
    }
    notifyListeners();
    return record;
  }

  ContractRecord _submitContractLocally(
    ContractDraft draft, {
    bool pendingSync = false,
    DraftProgress progress = const DraftProgress(),
  }) {
    final now = DateTime.now();
    final serial = contracts.length + 124;
    final id = 'EJ-${now.year}-${serial.toString().padLeft(5, '0')}';
    final request = 'REQ-${now.year}-${serial.toString().padLeft(5, '0')}';
    final date =
        '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';

    final record = ContractRecord(
      id: id,
      requestNumber: request,
      type: draft.type,
      role: FirebaseRepository.roleFromDraft(draft),
      title: draft.title,
      property: draft.property.displayAddress,
      lessorName: draft.lessor.displayName,
      tenantName: draft.tenant.displayName,
      date: date,
      status: ContractStatus.awaitingPayment,
      totalFees: draft.totalPayable,
      timeline: _timelineFor(ContractStatus.awaitingPayment),
      paymentStatus: 'pending',
      pendingSync: pendingSync,
      contractDetails: FirebaseRepository.contractDetailsFromDraft(draft),
      partyDetails: FirebaseRepository.partyDetailsFromDraft(draft),
      propertyDetails: FirebaseRepository.propertyDetailsFromDraft(draft),
      attachmentFiles: FirebaseRepository.attachmentFilesFromDraft(draft),
      customerVisibleNote: 'تم إنشاء الطلب، يرجى دفع الرسوم للمتابعة.',
      draftData: ContractDraft.copyOf(draft),
      draftProgress: progress,
    );
    contracts.insert(0, record);
    if (draft.property.propertySource.trim() == 'إضافة عقار جديد' &&
        (draft.property.buildingName.trim().isNotEmpty ||
            draft.property.unitNumber.trim().isNotEmpty)) {
      properties.insert(
        0,
        PropertyRecord(
          id: 'PROP-${serial.toString().padLeft(3, '0')}',
          title: draft.property.buildingName.trim().isEmpty
              ? draft.property.propertyType
              : draft.property.buildingName.trim(),
          city: draft.property.city,
          district: draft.property.district.trim().isEmpty
              ? 'غير محدد'
              : draft.property.district.trim(),
          type: draft.property.propertyType,
          usage: draft.property.propertyUsage,
          floors: int.tryParse(draft.property.floorsCount) ?? 1,
          totalUnits: int.tryParse(draft.property.totalUnits) ?? 1,
          units: <UnitRecord>[
            UnitRecord(
              data: PropertyData.copyOf(draft.property),
              number: draft.property.unitNumber.trim().isEmpty
                  ? '-'
                  : draft.property.unitNumber.trim(),
              name: draft.property.unitName.trim().isEmpty
                  ? draft.property.unitType
                  : draft.property.unitName.trim(),
              type: draft.property.unitType,
              floor: draft.property.floor.trim().isEmpty
                  ? '-'
                  : draft.property.floor.trim(),
              area: draft.property.area.trim().isEmpty
                  ? '-'
                  : '${draft.property.area} م²',
              status: 'متاحة',
            ),
          ],
          data: _clonePropertyData(draft.property),
        ),
      );
    }
    notifications.insert(
      0,
      NotificationItem(
        title: pendingSync ? 'تم حفظ الطلب محليًا' : 'تم استلام طلب العقد',
        body: pendingSync
            ? 'تم حفظ طلب ${draft.title} على الجهاز وسيتم إرساله تلقائيًا عند عودة الاتصال.'
            : 'تم إنشاء طلب ${draft.title}. ادفع الرسوم للمتابعة إلى قيد المعالجة.',
        time: 'الآن',
        icon: pendingSync ? Icons.cloud_off_rounded : Icons.payments_outlined,
        color: pendingSync ? const Color(0xFFE99015) : const Color(0xFF9D6C00),
      ),
    );
    mainNavigationIndex = 1;
    notifyListeners();
    return record;
  }

  Future<ContractRecord> saveDraft(
    ContractDraft draft, {
    String draftId = '',
    DraftProgress progress = const DraftProgress(),
  }) async {
    final effectiveDraftId = _syncedDraftIds[draftId] ?? draftId;
    final user = FirebaseBootstrap.initialized
        ? FirebaseAuth.instance.currentUser
        : null;
    final repository = _repository;
    if (repository != null && user != null) {
      try {
        final record = await repository.submitContract(
          uid: user.uid,
          customerName: userName,
          customerPhone: userPhone,
          customerEmail: userEmail,
          draft: draft,
          status: ContractStatus.draft,
          existingDraftId: effectiveDraftId,
          progress: progress,
        );
        _scheduleServerReachabilityCheck(
          _serverReachabilityCheckMessage,
          delay: Duration.zero,
        );
        return record;
      } catch (error) {
        _handleServerOperationFailure(
          error,
          'تعذر حفظ المسودة على الخادم. تم حفظها محليًا وستتم مزامنتها لاحقًا.',
        );
        return _queueContractSubmission(
          draft,
          ContractStatus.draft,
          existingDraftId: effectiveDraftId,
          progress: progress,
        );
      }
    }
    if (!kEjarzLocalDemoMode) {
      return _queueContractSubmission(
        draft,
        ContractStatus.draft,
        existingDraftId: effectiveDraftId,
        progress: progress,
      );
    }
    return _saveDraftLocally(
      draft,
      existingDraftId: effectiveDraftId,
      progress: progress,
    );
  }

  ContractRecord _saveDraftLocally(
    ContractDraft draft, {
    bool pendingSync = false,
    String existingDraftId = '',
    DraftProgress progress = const DraftProgress(),
  }) {
    final now = DateTime.now();
    final serial = contracts.length + 124;
    final existingIndex = existingDraftId.isEmpty
        ? -1
        : contracts.indexWhere((item) => item.id == existingDraftId);
    final existing = existingIndex < 0 ? null : contracts[existingIndex];
    final id =
        existing?.id ?? 'DR-${now.year}-${serial.toString().padLeft(5, '0')}';
    final request = existing?.requestNumber ??
        'DRAFT-${now.year}-${serial.toString().padLeft(5, '0')}';
    final currentDate =
        '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';
    final date = existing?.date ?? currentDate;

    final record = ContractRecord(
      id: id,
      requestNumber: request,
      uid: existing?.uid ?? '',
      type: draft.type,
      role: FirebaseRepository.roleFromDraft(draft),
      title: draft.title,
      property: draft.property.displayAddress,
      lessorName: draft.lessor.displayName,
      tenantName: draft.tenant.displayName,
      date: date,
      status: ContractStatus.draft,
      totalFees: 0,
      pendingSync: pendingSync,
      contractDetails: FirebaseRepository.contractDetailsFromDraft(draft),
      partyDetails: FirebaseRepository.partyDetailsFromDraft(draft),
      propertyDetails: FirebaseRepository.propertyDetailsFromDraft(draft),
      attachmentFiles: FirebaseRepository.attachmentFilesFromDraft(draft),
      timeline: existing?.timeline ??
          <StatusTimelineItem>[
            StatusTimelineItem(
              title: 'تم حفظ المسودة',
              subtitle: pendingSync
                  ? 'محفوظة محليًا وستتم مزامنتها عند عودة الاتصال'
                  : 'لم يتم إرسال الطلب للمراجعة بعد',
              date: date,
              time:
                  '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
              current: true,
            ),
          ],
      draftData: ContractDraft.copyOf(draft),
      draftProgress: progress,
    );
    if (existingIndex < 0) {
      contracts.insert(0, record);
    } else {
      contracts[existingIndex] = record;
    }
    notifyListeners();
    return record;
  }

  ContractRecord _submitDraftLocally(
    String draftId,
    ContractDraft draft, {
    bool pendingSync = false,
    DraftProgress progress = const DraftProgress(),
  }) {
    final index = contracts.indexWhere((item) => item.id == draftId);
    if (index < 0 || contracts[index].status != ContractStatus.draft) {
      return _submitContractLocally(
        draft,
        pendingSync: pendingSync,
        progress: progress,
      );
    }
    final existing = contracts[index];
    final now = DateTime.now();
    final submittedEvent = StatusTimelineItem(
      title: pendingSync ? 'بانتظار إرسال المسودة' : 'تم إرسال الطلب',
      subtitle: pendingSync
          ? 'سيتم إرسال الطلب تلقائيًا عند عودة الاتصال'
          : 'أصبح الطلب جاهزًا لسداد الرسوم',
      date:
          '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}',
      time:
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
      current: true,
    );
    final previousTimeline = existing.timeline
        .map(
          (item) => StatusTimelineItem(
            title: item.title,
            subtitle: item.subtitle,
            date: item.date,
            time: item.time,
            completed: true,
          ),
        )
        .toList();
    final record = ContractRecord(
      id: existing.id,
      requestNumber: existing.requestNumber,
      uid: existing.uid,
      type: draft.type,
      role: FirebaseRepository.roleFromDraft(draft),
      title: draft.title,
      property: draft.property.displayAddress,
      lessorName: draft.lessor.displayName,
      tenantName: draft.tenant.displayName,
      date: existing.date,
      status: ContractStatus.awaitingPayment,
      totalFees: draft.totalPayable,
      timeline: <StatusTimelineItem>[...previousTimeline, submittedEvent],
      paymentStatus: 'pending',
      pendingSync: pendingSync,
      contractDetails: FirebaseRepository.contractDetailsFromDraft(draft),
      partyDetails: FirebaseRepository.partyDetailsFromDraft(draft),
      propertyDetails: FirebaseRepository.propertyDetailsFromDraft(draft),
      attachmentFiles: FirebaseRepository.attachmentFilesFromDraft(draft),
      customerVisibleNote: pendingSync
          ? 'الطلب محفوظ محليًا وسيتم إرساله عند عودة الاتصال.'
          : 'تم إنشاء الطلب، يرجى دفع الرسوم للمتابعة.',
      draftData: ContractDraft.copyOf(draft),
      draftProgress: progress,
    );
    contracts[index] = record;
    if (draft.property.propertySource.trim() == 'إضافة عقار جديد') {
      properties.insert(
        0,
        PropertyRecord(
          id: 'PROP-${now.millisecondsSinceEpoch}',
          title: draft.property.buildingName.trim().isEmpty
              ? draft.property.propertyType
              : draft.property.buildingName.trim(),
          city: draft.property.city,
          district: draft.property.district,
          type: draft.property.propertyType,
          usage: draft.property.propertyUsage,
          floors: int.tryParse(draft.property.floorsCount) ?? 1,
          totalUnits: int.tryParse(draft.property.totalUnits) ?? 1,
          units: <UnitRecord>[
            UnitRecord(
              data: PropertyData.copyOf(draft.property),
              number: draft.property.unitNumber,
              name: draft.property.unitName,
              type: draft.property.unitType,
              floor: draft.property.floor,
              area: '${draft.property.area} م²',
              status: 'متاحة',
            ),
          ],
          data: _clonePropertyData(draft.property),
        ),
      );
    }
    mainNavigationIndex = 1;
    if (!pendingSync) {
      notifications.insert(
        0,
        NotificationItem(
          title: 'تم استلام طلب العقد',
          body:
              'تم إنشاء طلب ${draft.title}. ادفع الرسوم للمتابعة إلى قيد المعالجة.',
          time: 'الآن',
          icon: Icons.payments_outlined,
          color: const Color(0xFF9D6C00),
        ),
      );
    }
    notifyListeners();
    return record;
  }

  void updateProfile(
      {required String name, required String phone, required String email}) {
    userName = name;
    userPhone = phone;
    userEmail = email;
    notifyListeners();
  }
}

class AppScope extends InheritedNotifier<AppController> {
  const AppScope({
    super.key,
    required AppController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppController of(BuildContext context, {bool listen = true}) {
    if (listen) {
      final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
      assert(scope != null, 'AppScope غير موجود في شجرة التطبيق');
      return scope!.notifier!;
    }
    final element = context.getElementForInheritedWidgetOfExactType<AppScope>();
    final scope = element?.widget as AppScope?;
    assert(scope != null, 'AppScope غير موجود في شجرة التطبيق');
    return scope!.notifier!;
  }
}
