import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'firebase_bootstrap.dart';
import 'firebase_repository.dart';
import 'models.dart';

class AppController extends ChangeNotifier {
  bool splashCompleted = false;
  bool onboardingCompleted = false;
  bool loggedIn = false;
  bool subscriptionActive = false;
  bool darkMode = false;
  bool biometricEnabled = false;
  bool pushNotificationsEnabled = true;
  bool emailNotificationsEnabled = true;
  bool smsNotificationsEnabled = true;
  bool accountBlocked = false;
  int mainNavigationIndex = 0;
  SubscriptionPlan selectedPlan = SubscriptionPlan.professional;

  String userName = 'عميل إيجارز';
  String userPhone = '';
  String userEmail = '';
  String homeGreetingPrefix = 'مرحبًا';
  String homeWelcomeText = 'مرحبًا بك في إيجارز برو';
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
  String homeSubscriptionTitle = 'الباقة الاحترافية نشطة';
  String homeSubscriptionSubtitle = 'يتبقى 12 يومًا على موعد التجديد.';
  String homeSubscriptionAction = 'إدارة';
  String homeSubscriptionMessage = 'يمكن إدارة الاشتراك من صفحة حسابي.';

  final List<ContractRecord> contracts = <ContractRecord>[];
  final List<PropertyRecord> properties = <PropertyRecord>[];
  final List<NotificationItem> notifications = <NotificationItem>[];
  final List<WalletTransaction> transactions = <WalletTransaction>[];
  FirebaseRepository? _repository;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<List<ContractRecord>>? _contractsSubscription;
  StreamSubscription<List<PropertyRecord>>? _propertiesSubscription;
  StreamSubscription<List<NotificationItem>>? _notificationsSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _contentSubscription;

  AppController() {
    if (kIsWeb) {
      unawaited(_configureFirebaseWhenReady());
    } else if (FirebaseBootstrap.initialized) {
      _configureFirebase();
    }
    if (!kReleaseMode) {
      _seedData();
    }
  }

  Future<void> _configureFirebaseWhenReady() async {
    await FirebaseBootstrap.ready;
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
      _cancelUserStreams();
      return;
    }
    userPhone = user.phoneNumber ?? userPhone;
    userEmail = user.email ?? userEmail;
    loggedIn = true;
    unawaited(_bindFirebaseUser(user));
    notifyListeners();
  }

  Future<void> _bindFirebaseUser(User user) async {
    final repository = _repository;
    if (repository == null) return;
    await repository.ensureUserProfile(
      uid: user.uid,
      phone: user.phoneNumber ?? userPhone,
      name: userName,
      email: user.email ?? userEmail,
    );
    final status = await repository.userStatus(user.uid);
    accountBlocked = status == 'blocked' || status == 'suspended';
    if (accountBlocked) {
      loggedIn = false;
      notifyListeners();
      return;
    }
    _cancelUserStreams();
    _contractsSubscription =
        repository.watchUserContracts(user.uid).listen((items) {
      contracts
        ..clear()
        ..addAll(items);
      notifyListeners();
    });
    _propertiesSubscription =
        repository.watchUserProperties(user.uid).listen((items) {
      properties
        ..clear()
        ..addAll(items);
      notifyListeners();
    });
    _notificationsSubscription =
        repository.watchUserNotifications(user.uid).listen((items) {
      notifications
        ..clear()
        ..addAll(items);
      notifyListeners();
    });
  }

  void _cancelUserStreams() {
    _contractsSubscription?.cancel();
    _propertiesSubscription?.cancel();
    _notificationsSubscription?.cancel();
    _contractsSubscription = null;
    _propertiesSubscription = null;
    _notificationsSubscription = null;
  }

  void _syncAppContent(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    if (data == null) return;
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
    homeSubscriptionTitle =
        _contentText(data, 'homeSubscriptionTitle', homeSubscriptionTitle);
    homeSubscriptionSubtitle = _contentText(
        data, 'homeSubscriptionSubtitle', homeSubscriptionSubtitle);
    homeSubscriptionAction =
        _contentText(data, 'homeSubscriptionAction', homeSubscriptionAction);
    homeSubscriptionMessage =
        _contentText(data, 'homeSubscriptionMessage', homeSubscriptionMessage);
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

  @override
  void dispose() {
    _authSubscription?.cancel();
    _contentSubscription?.cancel();
    _cancelUserStreams();
    super.dispose();
  }

  void _seedData() {
    contracts.addAll(<ContractRecord>[
      ContractRecord(
        id: 'EJ-2024-00123',
        requestNumber: 'REQ-2024-00123',
        type: ContractType.residential,
        role: UserRole.lessor,
        title: 'عقد سكني - شقة النرجس',
        property: 'الرياض - حي النرجس',
        lessorName: 'عبدالله العتيبي',
        tenantName: 'شركة الواحة العقارية',
        date: '2024/05/20',
        status: ContractStatus.awaitingAuthentication,
        totalFees: 350,
        timeline: _timelineFor(ContractStatus.awaitingAuthentication),
      ),
      ContractRecord(
        id: 'EJ-2024-00122',
        requestNumber: 'REQ-2024-00122',
        type: ContractType.commercial,
        role: UserRole.authorized,
        title: 'عقد تجاري - معرض الرياض',
        property: 'طريق الملك فهد - الرياض',
        lessorName: 'شركة الرواد',
        tenantName: 'مؤسسة الخليج',
        date: '2024/05/18',
        status: ContractStatus.awaitingAuthentication,
        totalFees: 450,
        timeline: _timelineFor(ContractStatus.awaitingAuthentication),
      ),
      ContractRecord(
        id: 'EJ-2024-00115',
        requestNumber: 'REQ-2024-00115',
        type: ContractType.residential,
        role: UserRole.lessor,
        title: 'عقد سكني - شقة النخيل',
        property: 'الرياض - حي النخيل',
        lessorName: 'محمد العتيبي',
        tenantName: 'سالم الدوسري',
        date: '2024/05/16',
        status: ContractStatus.underReview,
        totalFees: 275,
        timeline: _timelineFor(ContractStatus.underReview),
      ),
      ContractRecord(
        id: 'EJ-2024-00102',
        requestNumber: 'REQ-2024-00102',
        type: ContractType.residential,
        role: UserRole.tenant,
        title: 'عقد سكني - فيلا الياسمين',
        property: 'الرياض - حي الياسمين',
        lessorName: 'محمد العتيبي',
        tenantName: 'خالد الشهري',
        date: '2024/05/10',
        status: ContractStatus.authenticated,
        totalFees: 275,
        timeline: _timelineFor(ContractStatus.authenticated),
      ),
      ContractRecord(
        id: 'EJ-2024-00098',
        requestNumber: 'REQ-2024-00098',
        type: ContractType.commercial,
        role: UserRole.authorized,
        title: 'عقد تجاري - مكتب العليا',
        property: 'العليا - طريق التخصصي',
        lessorName: 'شركة الاستثمارات الحديثة',
        tenantName: 'مؤسسة الإبداع',
        date: '2024/05/07',
        status: ContractStatus.underReview,
        totalFees: 350,
        timeline: _timelineFor(ContractStatus.underReview),
      ),
      ContractRecord(
        id: 'EJ-2024-00085',
        requestNumber: 'REQ-2024-00085',
        type: ContractType.residential,
        role: UserRole.tenant,
        title: 'عقد سكني - شقة الروضة',
        property: 'الرياض - حي الروضة',
        lessorName: 'محمد العتيبي',
        tenantName: 'ناصر القحطاني',
        date: '2024/05/01',
        status: ContractStatus.authenticated,
        totalFees: 275,
        timeline: _timelineFor(ContractStatus.authenticated),
      ),
    ]);

    properties.addAll(const <PropertyRecord>[
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
          UnitRecord(
            number: '101',
            name: 'شقة 101',
            type: 'شقة',
            floor: 'الأول',
            area: '145 م²',
            status: 'متاحة',
          ),
          UnitRecord(
            number: '202',
            name: 'شقة 202',
            type: 'شقة',
            floor: 'الثاني',
            area: '132 م²',
            status: 'مؤجرة',
          ),
        ],
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
          UnitRecord(
            number: '1',
            name: 'الفيلا الرئيسية',
            type: 'فيلا',
            floor: 'أرضي + أول',
            area: '420 م²',
            status: 'متاحة',
          ),
        ],
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
          UnitRecord(
            number: '8A',
            name: 'مكتب 8A',
            type: 'مكتب إداري',
            floor: 'الثامن',
            area: '96 م²',
            status: 'متاح',
          ),
        ],
      ),
    ]);

    notifications.addAll(<NotificationItem>[
      NotificationItem(
        title: 'العقد بانتظار التوثيق',
        body:
            'تم إدخال عقد شقة النرجس في منصة إيجار وهو بانتظار توثيق الأطراف.',
        time: 'منذ 12 دقيقة',
        icon: Icons.schedule_rounded,
        color: const Color(0xFFE99015),
      ),
      NotificationItem(
        title: 'تم استلام طلبك',
        body: 'استلم فريقنا طلب عقد شقة النخيل وسيتم مراجعته خلال وقت قصير.',
        time: 'منذ ساعتين',
        icon: Icons.inventory_2_outlined,
        color: const Color(0xFF2F73E0),
      ),
      NotificationItem(
        title: 'تم توثيق العقد',
        body: 'تم توثيق عقد فيلا الياسمين بنجاح ويمكنك تحميل النسخة النهائية.',
        time: 'أمس',
        icon: Icons.verified_outlined,
        color: const Color(0xFF16875E),
        read: true,
      ),
      NotificationItem(
        title: 'تذكير بانتهاء الاشتراك',
        body: 'يتبقى 12 يومًا على تجديد باقة احترافية.',
        time: 'قبل 3 أيام',
        icon: Icons.workspace_premium_outlined,
        color: const Color(0xFFD4A53B),
        read: true,
      ),
    ]);

    transactions.addAll(const <WalletTransaction>[
      WalletTransaction(
        title: 'رسوم عقد شقة النرجس',
        reference: 'PAY-2024-08912',
        date: '2024/05/20',
        amount: 350,
      ),
      WalletTransaction(
        title: 'اشتراك الباقة الاحترافية',
        reference: 'SUB-2024-00318',
        date: '2024/05/01',
        amount: 99,
      ),
      WalletTransaction(
        title: 'استرداد رسوم طلب ملغي',
        reference: 'REF-2024-00012',
        date: '2024/04/24',
        amount: 125,
        incoming: true,
      ),
    ]);
  }

  static List<StatusTimelineItem> _timelineFor(ContractStatus status) {
    final currentIndex = switch (status) {
      ContractStatus.draft => -1,
      ContractStatus.awaitingPayment => -1,
      ContractStatus.underReview => 0,
      ContractStatus.missingData => 0,
      ContractStatus.readyForEjar => 0,
      ContractStatus.enteredInEjar => 1,
      ContractStatus.awaitingAuthentication => 2,
      ContractStatus.authenticated => 3,
      ContractStatus.rejected => 0,
    };

    final labels = <({String title, String subtitle, String time})>[
      (
        title: 'قيد المراجعة',
        subtitle: 'جارٍ مراجعة بيانات الطلب والمرفقات',
        time: '11:15 ص',
      ),
      (
        title: 'تم الإدخال في إيجار',
        subtitle: 'تم إدخال بيانات العقد في منصة إيجار',
        time: '12:05 م',
      ),
      (
        title: 'بانتظار التوثيق',
        subtitle: 'في انتظار توثيق العقد من الأطراف',
        time: '12:45 م',
      ),
      (
        title: 'موثق',
        subtitle: 'تم توثيق العقد بنجاح',
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
      .where((contract) =>
          contract.status == ContractStatus.awaitingAuthentication)
      .length;
  int get completedContracts => contracts
      .where((contract) => contract.status == ContractStatus.authenticated)
      .length;
  int get underReviewContracts => contracts
      .where((contract) => contract.status == ContractStatus.underReview)
      .length;
  int get availableUnits => properties.fold<int>(
        0,
        (total, property) =>
            total +
            property.units.where((unit) => unit.status.contains('متاح')).length,
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
    userName = name?.trim().isNotEmpty == true ? name!.trim() : userName;
    userPhone = phone?.trim().isNotEmpty == true ? phone!.trim() : userPhone;
    userEmail = email?.trim().isNotEmpty == true ? email!.trim() : userEmail;
    loggedIn = true;
    accountBlocked = false;
    final user = FirebaseBootstrap.initialized
        ? FirebaseAuth.instance.currentUser
        : null;
    if (user != null) unawaited(_bindFirebaseUser(user));
    notifyListeners();
  }

  void logout() {
    try {
      unawaited(FirebaseAuth.instance.signOut());
    } catch (_) {
      // Firebase may be unavailable in lightweight widget tests.
    }
    loggedIn = false;
    accountBlocked = false;
    subscriptionActive = false;
    mainNavigationIndex = 0;
    _cancelUserStreams();
    notifyListeners();
  }

  void activateSubscription(SubscriptionPlan plan) {
    selectedPlan = plan;
    subscriptionActive = true;
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
    notifyListeners();
  }

  void toggleEmailNotifications(bool value) {
    emailNotificationsEnabled = value;
    notifyListeners();
  }

  void toggleSmsNotifications(bool value) {
    smsNotificationsEnabled = value;
    notifyListeners();
  }

  void markAllNotificationsRead() {
    for (final item in notifications) {
      item.read = true;
    }
    notifyListeners();
  }

  void markNotificationRead(NotificationItem item) {
    item.read = true;
    notifyListeners();
  }

  Future<ContractRecord> submitContract(ContractDraft draft) async {
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
          status: ContractStatus.underReview,
        );
        mainNavigationIndex = 1;
        notifyListeners();
        return record;
      } catch (_) {
        // Keep the app usable if Firestore is temporarily unavailable.
      }
    }
    return _submitContractLocally(draft);
  }

  ContractRecord _submitContractLocally(ContractDraft draft) {
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
      role: draft.role,
      title: draft.title,
      property: draft.property.displayAddress,
      lessorName: draft.lessor.displayName,
      tenantName: draft.tenant.displayName,
      date: date,
      status: ContractStatus.underReview,
      totalFees: draft.totalPayable,
      timeline: _timelineFor(ContractStatus.underReview),
    );
    contracts.insert(0, record);
    if (draft.property.buildingName.trim().isNotEmpty ||
        draft.property.unitNumber.trim().isNotEmpty) {
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
        ),
      );
    }
    transactions.insert(
      0,
      WalletTransaction(
        title: 'رسوم ${draft.type.label}',
        reference: 'PAY-${now.year}-${serial.toString().padLeft(5, '0')}',
        date: date,
        amount: draft.totalPayable,
      ),
    );
    notifications.insert(
      0,
      NotificationItem(
        title: 'تم استلام طلب العقد',
        body: 'تم استلام طلب ${draft.title} وسيتم مراجعته من فريق إيجارز برو.',
        time: 'الآن',
        icon: Icons.inventory_2_outlined,
        color: const Color(0xFF2F73E0),
      ),
    );
    mainNavigationIndex = 1;
    notifyListeners();
    return record;
  }

  Future<ContractRecord> saveDraft(ContractDraft draft) async {
    final user = FirebaseBootstrap.initialized
        ? FirebaseAuth.instance.currentUser
        : null;
    final repository = _repository;
    if (repository != null && user != null) {
      try {
        return await repository.submitContract(
          uid: user.uid,
          customerName: userName,
          customerPhone: userPhone,
          customerEmail: userEmail,
          draft: draft,
          status: ContractStatus.draft,
        );
      } catch (_) {
        // Fall back to local draft storage for offline continuity.
      }
    }
    return _saveDraftLocally(draft);
  }

  ContractRecord _saveDraftLocally(ContractDraft draft) {
    final now = DateTime.now();
    final serial = contracts.length + 124;
    final id = 'DR-${now.year}-${serial.toString().padLeft(5, '0')}';
    final request = 'DRAFT-${now.year}-${serial.toString().padLeft(5, '0')}';
    final date =
        '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';

    final record = ContractRecord(
      id: id,
      requestNumber: request,
      type: draft.type,
      role: draft.role,
      title: draft.title,
      property: draft.property.displayAddress,
      lessorName: draft.lessor.displayName,
      tenantName: draft.tenant.displayName,
      date: date,
      status: ContractStatus.draft,
      totalFees: 0,
      timeline: <StatusTimelineItem>[
        StatusTimelineItem(
          title: 'تم حفظ المسودة',
          subtitle: 'لم يتم إرسال الطلب للمراجعة بعد',
          date: date,
          time:
              '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
          current: true,
        ),
      ],
    );
    contracts.insert(0, record);
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
