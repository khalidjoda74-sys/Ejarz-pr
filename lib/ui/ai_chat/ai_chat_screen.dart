import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import '../../data/services/app_architecture_registry.dart';
import '../../screens/office/office.dart';
import '../contracts_screen.dart' as contracts_ui;
import '../home_screen.dart';
import '../invoices_screen.dart';
import '../maintenance_screen.dart';
import '../notifications_screen.dart';
import '../properties_screen.dart';
import '../reports_screen.dart';
import '../tenants_screen.dart';
import '../../widgets/custom_confirm_dialog.dart';
import 'ai_chat_service.dart';
import 'ai_chat_executor.dart';
import 'ai_chat_permissions.dart';
import 'ai_chat_tools.dart';
import 'core/ai_openai_config.dart';

class AiChatScreen extends StatefulWidget {
  final bool isOfficeMode;
  const AiChatScreen({super.key, this.isOfficeMode = false});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen>
    with TickerProviderStateMixin {
  AiChatService? _service;
  AiChatExecutor? _executor;
  AiChatScope? _chatScope;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  bool _loading = true;
  bool _sending = false;
  ChatUserRole _role = ChatUserRole.viewOnly;
  String _userName = '';
  int? _streamingAssistantIndex;
  Future<void>? _historyRestoreFuture;
  final List<_ChatAttachment> _pendingChatAttachments = <_ChatAttachment>[];
  bool _uploadingChatAttachments = false;
  _ChatCollectionSession? _collectionSession;

  bool get _isOfficeSession => _effectiveScope.usesOfficeModeForArchitecture;

  AiChatScope get _effectiveScope =>
      _chatScope ??
      (widget.isOfficeMode
          ? AiChatScope.officeGlobal(
              officeUid: _resolveUserId(),
              officeName: _resolveUserName(),
            )
          : AiChatScope.ownerSelf(
              ownerUid: _resolveUserId(),
              ownerName: _resolveUserName(),
            ));

  final List<_UiMessage> _messages = [];

  bool get _showTypingIndicator =>
      _sending && _streamingAssistantIndex == null;

  static const Map<String, String> _toolArgLabels = {
    'query': 'البحث',
    'clientType': 'نوع العميل',
    'fullName': 'الاسم الكامل',
    'nationalId': 'رقم الهوية',
    'phone': 'رقم الجوال',
    'email': 'البريد الإلكتروني',
    'nationality': 'الجنسية',
    'companyName': 'اسم الشركة',
    'companyCommercialRegister': 'السجل التجاري',
    'companyTaxNumber': 'الرقم الضريبي',
    'companyRepresentativeName': 'ممثل الشركة',
    'companyRepresentativePhone': 'جوال ممثل الشركة',
    'serviceSpecialization': 'التخصص',
    'attachmentPaths': 'المرفقات',
    'propertyName': 'العقار',
    'buildingName': 'المبنى',
    'tenantName': 'العميل',
    'clientName': 'العميل',
    'contractSerialNo': 'رقم العقد',
    'invoiceSerialNo': 'رقم الفاتورة',
    'voucherSerialNo': 'رقم السند',
    'origin': 'النوع',
    'amount': 'المبلغ',
    'fromDate': 'من تاريخ',
    'toDate': 'إلى تاريخ',
    'dueDate': 'تاريخ الاستحقاق',
    'startDate': 'تاريخ البداية',
    'endDate': 'تاريخ النهاية',
    'rentAmount': 'قيمة الإيجار',
    'totalAmount': 'إجمالي العقد',
    'reason': 'السبب',
    'screen': 'الشاشة',
    'title': 'العنوان',
    'description': 'الوصف',
    'note': 'الملاحظة',
    'status': 'الحالة',
    'ownerQuery': 'المالك',
    'propertyQuery': 'العقار',
    'contractQuery': 'العقد',
    'direction': 'اتجاه السند',
    'operation': 'نوع الحركة',
    'voucherState': 'حالة السند',
    'voucherSource': 'مصدر السند',
    'voucherDate': 'تاريخ السند',
    'ledgerLimit': 'عدد حركات الدفتر',
    'limit': 'عدد النتائج',
    'value': 'القيمة',
    'modeLabel': 'نوع العمولة',
    'categoryLabel': 'نوع التسوية',
    'includeDraft': 'تضمين المسودات',
    'includeCancelled': 'تضمين الملغية',
    'serviceType': 'نوع الخدمة',
    'provider': 'مقدم الخدمة',
    'nextDueDate': 'تاريخ الدورة القادمة',
    'kind': 'نوع الإشعار',
    'notificationRef': 'مرجع الإشعار',
    'includeDismissed': 'تضمين المقروءة',
    'type': 'النوع',
    'rentalMode': 'نمط التأجير',
    'totalUnits': 'عدد الوحدات',
    'furnished': 'المفروشات',
    'documentType': 'نوع الوثيقة',
    'documentNumber': 'رقم الوثيقة',
    'documentDate': 'تاريخ الوثيقة',
    'documentAttachmentPaths': 'مرفقات الوثيقة',
    'dailyCheckoutHour': 'ساعة الخروج',
    'priority': 'الأولوية',
    'notes': 'الملاحظات',
  };

  static const Map<String, String> _assistantTextReplacements = {
    'clientType': 'نوع العميل',
    'clientTypeLabel': 'نوع العميل',
    'paymentCycle': 'دورة السداد',
    'attachmentPaths': 'المرفقات',
    'documentAttachmentPaths': 'مرفقات الوثيقة',
    'requiredFields': 'الحقول الإلزامية',
    'requiredFieldsByType': 'الحقول الإلزامية',
    'missingFields': 'الحقول الناقصة',
    'validationError': 'سبب التعذر',
    'entryOptions': 'خيارات الإضافة',
    'chatCollectionMode': 'طريقة الجمع',
    'chatAttachmentSupport': 'دعم المرفقات',
    'currentInvoice': 'الدفعة الحالية',
    'nextUnpaidInvoice': 'الدفعة القادمة غير المسددة',
    'lastPaidInvoice': 'آخر دفعة مسددة',
    'overdueInvoicesCount': 'عدد الدفعات المتأخرة',
    'paymentActionHint': 'توضيح السداد',
    'serviceProvider': 'مقدم خدمة',
    'appliedFilters': 'الفلاتر المطبقة',
    'commissionRule': 'قاعدة عمولة المكتب',
    'ledger': 'الدفتر',
    'propertyBreakdowns': 'تفصيل العقارات',
    'bankAccounts': 'الحسابات البنكية',
    'accounts': 'الحسابات البنكية',
    'owner': 'المالك',
    'preview': 'المعاينة',
    'topOwnerByPayout': 'أعلى مالك جاهز للتحويل',
    'rentCollected': 'الإيجارات المحصلة',
    'officeCommissions': 'عمولات المكتب',
    'ownerExpenses': 'المصروفات المحملة على المالك',
    'ownerAdjustments': 'خصومات/تسويات المالك',
    'previousTransfers': 'التحويلات السابقة',
    'currentBalance': 'الرصيد الحالي',
    'readyForPayout': 'الجاهز للتحويل',
    'commissionRevenue': 'إيرادات عمولة المكتب',
    'officeExpenses': 'مصروفات المكتب',
    'officeWithdrawals': 'تحويلات المكتب',
    'netProfit': 'صافي ربح المكتب',
    'receiptVouchers': 'سندات القبض',
    'paymentVouchers': 'سندات الصرف',
    'contractNo': 'رقم العقد',
    'operationLabel': 'نوع الحركة',
    'sourceLabel': 'مصدر الحركة',
    'stateLabel': 'حالة السند',
    'directionLabel': 'اتجاه السند',
    'voucherStateLabel': 'حالة القيد',
    'paymentMethod': 'طريقة الدفع',
    'date': 'التاريخ',
    'voucherDate': 'تاريخ السند',
    'note': 'الملاحظة',
    'modeLabel': 'نوع العمولة',
    'categoryLabel': 'نوع التسوية',
    'credit': 'دائن',
    'debit': 'مدين',
    'balanceAfter': 'الرصيد بعد الحركة',
    'linkedProperties': 'العقارات المرتبطة',
    'previousBalance': 'الرصيد السابق',
    'receipts': 'سندات القبض',
    'payments': 'سندات الصرف',
    'receiptAmount': 'إجمالي القبض',
    'paymentAmount': 'إجمالي الصرف',
    'tenant': 'مستأجر',
    'company': 'شركة',
    'monthly': 'شهري',
    'quarterly': 'ربع سنوي',
    'semiAnnual': 'نصف سنوي',
    'annual': 'سنوي',
    'daily': 'يومي',
    'wholeBuilding': 'كامل المبنى',
    'perUnit': 'لكل وحدة',
    'open': 'مفتوحة',
    'inProgress': 'قيد التنفيذ',
    'completed': 'مكتملة',
    'canceled': 'ملغية',
    'cancelled': 'ملغية',
    'high': 'عالية',
    'medium': 'متوسطة',
    'low': 'منخفضة',
    'urgent': 'عاجلة',
    'cash': 'نقدًا',
    'bankTransfer': 'تحويل بنكي',
    'check': 'شيك',
    'revenue': 'قبض',
    'expense': 'صرف',
    'draft': 'مسودة',
    'posted': 'معتمد',
    'reversed': 'معكوس',
    'typeLabel': 'نوع العقار',
    'structureKind': 'نوع البنية',
    'structureLabel': 'التصنيف',
    'managementMode': 'نمط إدارة العمارة',
    'managementModeLabel': 'نمط إدارة العمارة',
    'configuredUnits': 'الوحدات المهيأة',
    'registeredUnits': 'الوحدات المضافة',
    'occupiedUnits': 'الوحدات المشغولة',
    'vacantUnits': 'الوحدات المتاحة',
    'childUnitsCount': 'عدد الوحدات المضافة',
    'semanticGuidance': 'توضيح المعنى',
    'semanticSummary': 'الملخص التفسيري',
    'propertyTypeBreakdown': 'تفصيل أنواع العقارات',
    'buildingsPreview': 'معاينة العمائر',
    'topLevelProperties': 'العقارات الرئيسية',
    'occupiedTopLevelProperties': 'العقارات الرئيسية المشغولة',
    'vacantTopLevelProperties': 'العقارات الرئيسية المتاحة',
    'buildings': 'العمائر',
    'standaloneProperties': 'العقارات المستقلة',
    'registeredBuildingUnits': 'الوحدات المضافة',
    'configuredBuildingUnits': 'الوحدات المهيأة',
    'occupiedBuildingUnits': 'الوحدات المشغولة',
    'vacantBuildingUnits': 'الوحدات المتاحة',
    'totalContracts': 'إجمالي العقود',
    'activeContracts': 'العقود النشطة',
    'endedContracts': 'العقود المنتهية',
    'terminatedContracts': 'العقود المنهية',
    'expiringContracts': 'العقود القريبة من الانتهاء',
    'remainingContractAmount': 'المتبقي في العقود',
    'totalInstallments': 'إجمالي الدفعات',
    'paidInstallments': 'الدفعات المسددة',
    'unpaidInstallments': 'الدفعات غير المسددة',
    'canceledInstallments': 'الدفعات الملغاة',
    'overdueInstallments': 'الدفعات المتأخرة',
    'upcomingInstallments': 'الدفعات القادمة',
    'remainingTotal': 'إجمالي المتبقي',
    'invoiceHistorySummary': 'ملخص الدفعات',
    'invoiceHistoryPreview': 'معاينة الدفعات',
    'installmentsSummary': 'ملخص الدفعات',
    'expiringSoon': 'قريب الانتهاء',
    'clientSummary': 'ملخص العملاء',
    'userSummary': 'ملخص مستخدمي المكتب',
    'portfolioSummary': 'ملخص المحفظة',
    'totalClients': 'إجمالي العملاء',
    'activeClients': 'العملاء النشطون',
    'blockedClients': 'العملاء الموقوفون',
    'withSubscription': 'العملاء ذوو الاشتراك',
    'pendingSyncClients': 'العملاء المعلّقون للمزامنة',
    'totalUsers': 'إجمالي المستخدمين',
    'activeUsers': 'المستخدمون النشطون',
    'blockedUsers': 'المستخدمون الموقوفون',
    'fullPermissionUsers': 'مستخدمو الصلاحية الكاملة',
    'viewPermissionUsers': 'مستخدمو صلاحية المشاهدة',
    'clientsWithWorkspaceData': 'العملاء الذين تتوفر لهم بيانات تشغيلية',
    'clientsWithoutWorkspaceData': 'العملاء الذين لا تتوفر لهم بيانات تشغيلية',
    'workspaceSummary': 'ملخص مساحة العمل',
    'workspaceDataAvailable': 'توفر البيانات التشغيلية',
    'workspaceDataMessage': 'حالة البيانات التشغيلية',
    'propertiesPreview': 'معاينة العقارات',
    'contractsPreview': 'معاينة العقود',
    'clientPortfolioPreview': 'معاينة محافظ العملاء',
    'latestClientsPreview': 'أحدث العملاء',
    'latestUsersPreview': 'أحدث مستخدمي المكتب',
    'quickActions': 'إجراءات سريعة',
    'badgeCount': 'عدد التنبيهات',
    'officeSubscriptionAlerts': 'تنبيهات اشتراك المكتب',
    'clientSubscriptionAlerts': 'تنبيهات اشتراكات العملاء',
    'alerts': 'التنبيهات',
    'apartment': 'شقة',
    'villa': 'فيلا',
    'building': 'عمارة',
    'land': 'أرض',
    'office': 'مكتب',
    'shop': 'محل',
    'warehouse': 'مستودع',
    'property': 'عقار',
    'unit': 'وحدة',
    'whole_building': 'تأجير كامل العمارة',
    'units': 'إدارة بالوحدات',
  };

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _userName = _resolveUserName();
    final resolved = await Future.wait<Object?>([
      AiChatPermissions.resolveRole(),
      _resolveChatScope(),
    ]);
    _role = resolved[0] as ChatUserRole;
    _chatScope = resolved[1] as AiChatScope;
    _executor = AiChatExecutor(
      userRole: _role,
      chatScope: _effectiveScope,
      onNavigate: (route) async {
        return _openRouteFromChat(route);
      },
    );
    _service = AiChatService(
      userRole: _role,
      userName: _userName,
      userId: _resolveUserId(),
      isOfficeMode: _isOfficeSession,
      chatScope: _effectiveScope,
    );
    if (!mounted) return;

    setState(() {
      _syncMessagesFromService();
      _loading = false;
    });
    _scrollToBottom();
    final restoreFuture = _restoreHistoryAfterOpen();
    _historyRestoreFuture = restoreFuture;
    unawaited(restoreFuture);

    /*
      setState(() => _loading = false);
      // رسالة ترحيب
      _addAssistantMessage('مرحباً $_userName! أنا مساعد دارفو الذكي. كيف أقدر أساعدك اليوم؟');
    */
  }

  Future<void> _restoreHistoryAfterOpen() async {
    final service = _service;
    if (service == null) {
      _historyRestoreFuture = null;
      return;
    }

    try {
      final restored = await service.restoreHistory();
      if (!restored) {
        service.addLocalAssistantMessage(_buildScopedWelcomeMessage());
      }

      if (!mounted) return;

      setState(_syncMessagesFromService);
      _scrollToBottom();
    } finally {
      _historyRestoreFuture = null;
    }
  }

  String _resolveUserName() {
    try {
      final user = FirebaseAuth.instance.currentUser;
      return user?.displayName ?? user?.email?.split('@').first ?? 'المستخدم';
    } catch (_) {
      return 'المستخدم';
    }
  }

  String _resolveUserId() {
    try {
      final user = FirebaseAuth.instance.currentUser;
      return user?.uid ?? user?.email ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<AiChatScope> _resolveChatScope() async {
    if (widget.isOfficeMode) {
      return AiChatScope.officeGlobal(
        officeUid: _resolveUserId(),
        officeName: _resolveUserName(),
      );
    }

    try {
      final session = Hive.isBoxOpen('sessionBox')
          ? Hive.box('sessionBox')
          : await Hive.openBox('sessionBox');
      final isImpersonation = session.get('officeImpersonation') == true;
      final isOfficeClient = session.get('isOfficeClient') == true;
      final workspaceOwnerUid =
          (session.get('workspaceOwnerUid') ?? '').toString().trim();
      final workspaceOwnerName =
          (session.get('workspaceOwnerName') ?? '').toString().trim();

      if (isImpersonation && workspaceOwnerUid.isNotEmpty) {
        return AiChatScope.officeClient(
          clientUid: workspaceOwnerUid,
          clientName: workspaceOwnerName,
        );
      }

      if (isOfficeClient) {
        return AiChatScope.officeClient(
          clientUid: _resolveUserId(),
          clientName: _resolveUserName(),
        );
      }
    } catch (_) {}

    return AiChatScope.ownerSelf(
      ownerUid: _resolveUserId(),
      ownerName: _resolveUserName(),
    );
  }

  String _buildScopedWelcomeMessage() {
    return 'مرحبًا $_userName! أنا مساعد دارفو الذكي. ${_effectiveScope.welcomeLabel}. كيف أقدر أساعدك اليوم؟';
  }

  String _buildWelcomeMessage() {
    return 'مرحبًا $_userName! أنا مساعد دارفو الذكي. كيف أقدر أساعدك اليوم؟';
  }

  Route<void>? _buildNavigationRoute(String target) {
    final normalizedTarget =
        AppArchitectureRegistry.normalizeScreenKey(target);
    Widget? screen;
    switch (normalizedTarget) {
      case 'home':
        screen = _isOfficeSession ? const OfficeHomePage() : const HomeScreen();
        break;
      case 'office':
        screen = const OfficeHomePage();
        break;
      case 'properties':
        screen = const PropertiesScreen();
        break;
      case 'properties_new':
        screen = const AddOrEditPropertyScreen();
        break;
      case 'tenants':
        screen = const TenantsScreen();
        break;
      case 'tenants_new':
        screen = const AddOrEditTenantScreen();
        break;
      case 'contracts':
        screen = const contracts_ui.ContractsScreen();
        break;
      case 'contracts_new':
        screen = const contracts_ui.AddContractScreen();
        break;
      case 'invoices':
        screen = const InvoicesScreen();
        break;
      case 'maintenance':
        screen = const MaintenanceScreen();
        break;
      case 'maintenance_new':
        screen = const AddOrEditMaintenanceScreen();
        break;
      case 'reports':
        screen = const ReportsScreen();
        break;
      case 'notifications':
        screen = const NotificationsScreen();
        break;
      default:
        return null;
    }

    return MaterialPageRoute<void>(builder: (_) => screen!);
  }

  void _syncMessagesFromService() {
    final service = _service;
    if (service == null) return;

    _messages
      ..clear()
      ..addAll(
        service.visibleMessages
            .map(
              (message) => _UiMessage(
                role: message.role,
                text: message.role == 'assistant'
                    ? _normalizeAssistantText(message.content ?? '')
                    : (message.content ?? ''),
              ),
            )
            .toList(growable: false),
      );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _addAssistantMessage(String text) {
    _messages.add(_UiMessage(role: 'assistant', text: text));
    _scrollToBottom();
  }

  void _clearStreamingAssistantDraft() {
    final index = _streamingAssistantIndex;
    if (index == null) return;
    if (index >= 0 && index < _messages.length) {
      _messages.removeAt(index);
    }
    _streamingAssistantIndex = null;
  }

  void _updateStreamingAssistantText(String text) {
    if (!mounted) return;
    final value = _normalizeAssistantText(text.trimRight());
    if (value.isEmpty) return;

    setState(() {
      if (_streamingAssistantIndex == null) {
        _messages.add(_UiMessage(role: 'assistant', text: value));
        _streamingAssistantIndex = _messages.length - 1;
      } else if (_streamingAssistantIndex! < _messages.length) {
        _messages[_streamingAssistantIndex!] =
            _UiMessage(role: 'assistant', text: value);
      }
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Map<String, dynamic> _toolArguments(Map<String, dynamic> call) {
    final fn = (call['function'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final rawArgs = fn['arguments'];
    if (rawArgs is String) {
      try {
        return jsonDecode(rawArgs) as Map<String, dynamic>;
      } catch (_) {
        return <String, dynamic>{};
      }
    }
    if (rawArgs is Map<String, dynamic>) return rawArgs;
    if (rawArgs is Map) return rawArgs.cast<String, dynamic>();
    return <String, dynamic>{};
  }

  Map<String, dynamic>? _decodeExecutorPayload(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
    return null;
  }

  void _showChatSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: GoogleFonts.cairo())),
    );
  }

  String _sanitizeAttachmentFileName(String name) {
    final trimmed = name.trim();
    final sanitized = trimmed.replaceAll(RegExp(r'[<>:"/\\|?*]+'), '_');
    return sanitized.isEmpty ? 'attachment' : sanitized;
  }

  Future<_ChatAttachment?> _saveChatAttachmentLocally(PlatformFile file) async {
    final directory = await getApplicationDocumentsDirectory();
    final attachmentsDir = Directory(
      '${directory.path}${Platform.pathSeparator}ai_chat_attachments',
    );
    if (!await attachmentsDir.exists()) {
      await attachmentsDir.create(recursive: true);
    }

    final fileName =
        '${DateTime.now().microsecondsSinceEpoch}_${_sanitizeAttachmentFileName(file.name)}';
    final savedPath =
        '${attachmentsDir.path}${Platform.pathSeparator}$fileName';
    final savedFile = File(savedPath);

    final sourcePath = (file.path ?? '').trim();
    if (sourcePath.isNotEmpty) {
      await File(sourcePath).copy(savedPath);
      return _ChatAttachment(path: savedPath, name: file.name);
    }
    if (file.bytes != null) {
      await savedFile.writeAsBytes(file.bytes!, flush: true);
      return _ChatAttachment(path: savedPath, name: file.name);
    }
    return null;
  }

  Future<void> _pickChatAttachments() async {
    if (_sending || _uploadingChatAttachments) return;
    if (_pendingChatAttachments.length >= 3) {
      _showChatSnack('الحد الأقصى للمرفقات هو 3 ملفات.');
      return;
    }

    setState(() => _uploadingChatAttachments = true);
    try {
      final remainingSlots = 3 - _pendingChatAttachments.length;
      final picked = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;

      final selected = picked.files.take(remainingSlots).toList(growable: false);
      final savedAttachments = <_ChatAttachment>[];
      for (final file in selected) {
        final saved = await _saveChatAttachmentLocally(file);
        if (saved == null) continue;
        final exists = _pendingChatAttachments.any(
              (attachment) => attachment.path == saved.path,
            ) ||
            savedAttachments.any((attachment) => attachment.name == saved.name);
        if (!exists) {
          savedAttachments.add(saved);
        }
      }

      if (!mounted) return;
      setState(() {
        _pendingChatAttachments.addAll(savedAttachments);
      });

      if (picked.files.length > remainingSlots) {
        _showChatSnack('تمت إضافة أول $remainingSlots ملفات فقط لأن الحد الأقصى 3.');
      } else if (savedAttachments.isNotEmpty) {
        _showChatSnack('تمت إضافة ${savedAttachments.length} مرفق/مرفقات إلى الرسالة.');
      }
    } catch (_) {
      _showChatSnack('تعذر رفع المرفقات من هذه الشاشة حاليًا.');
    } finally {
      if (mounted) {
        setState(() => _uploadingChatAttachments = false);
      }
    }
  }

  void _removeChatAttachment(String path) {
    setState(() {
      _pendingChatAttachments.removeWhere((attachment) => attachment.path == path);
    });
  }

  String _buildChatAttachmentContext() {
    if (_pendingChatAttachments.isEmpty) return '';
    final names = _pendingChatAttachments
        .map((attachment) => attachment.name.trim())
        .where((name) => name.isNotEmpty)
        .join('، ');
    return 'يوجد في هذه الرسالة ${_pendingChatAttachments.length} مرفقات جاهزة للاستخدام عند الحاجة في حقول المرفقات. أسماء الملفات: $names. الحد الأقصى المدعوم 3 ملفات.';
  }

  bool _toolAcceptsAttachments(String toolName) {
    switch (toolName) {
      case 'add_tenant':
      case 'add_client_record':
      case 'add_property':
      case 'edit_property':
      case 'create_contract':
      case 'create_manual_voucher':
      case 'create_maintenance_request':
        return true;
      default:
        return false;
    }
  }

  bool _hasNonEmptyPathList(dynamic value) {
    if (value is! Iterable) return false;
    return value.any((item) => item.toString().trim().isNotEmpty);
  }

  bool _toolWillUsePendingAttachments(
    String toolName,
    Map<String, dynamic> args,
  ) {
    if (!_toolAcceptsAttachments(toolName) || _pendingChatAttachments.isEmpty) {
      return false;
    }
    if (!_hasNonEmptyPathList(args['attachmentPaths'])) {
      return true;
    }
    if ((toolName == 'add_property' || toolName == 'edit_property') &&
        !_hasNonEmptyPathList(args['documentAttachmentPaths'])) {
      return true;
    }
    return false;
  }

  Map<String, dynamic> _mergePendingChatAttachmentsIntoArgs(
    String toolName,
    Map<String, dynamic> args,
  ) {
    if (!_toolAcceptsAttachments(toolName) || _pendingChatAttachments.isEmpty) {
      return args;
    }

    final mergedArgs = Map<String, dynamic>.from(args);
    final paths = _pendingChatAttachments
        .map((attachment) => attachment.path)
        .toList(growable: false);

    if (!_hasNonEmptyPathList(mergedArgs['attachmentPaths'])) {
      mergedArgs['attachmentPaths'] = paths;
    }
    if ((toolName == 'add_property' || toolName == 'edit_property') &&
        !_hasNonEmptyPathList(mergedArgs['documentAttachmentPaths'])) {
      mergedArgs['documentAttachmentPaths'] = paths;
    }
    return mergedArgs;
  }

  bool _toolResultSucceeded(String rawResult) {
    final payload = _decodeExecutorPayload(rawResult);
    if (payload == null) return false;
    return payload['success'] == true;
  }

  String _sanitizeToolResultForModel(String rawResult) {
    final payload = _decodeExecutorPayload(rawResult);
    if (payload == null) {
      return _normalizeAssistantText(rawResult);
    }
    final sanitized = _sanitizeToolPayloadValue(payload);
    if (sanitized is Map<String, dynamic>) {
      return jsonEncode(sanitized);
    }
    if (sanitized is Map) {
      return jsonEncode(sanitized.cast<String, dynamic>());
    }
    return _normalizeAssistantText(rawResult);
  }

  dynamic _sanitizeToolPayloadValue(dynamic value) {
    if (value is Map<String, dynamic>) {
      final output = <String, dynamic>{};
      value.forEach((key, entryValue) {
        if (_shouldHideToolPayloadKey(key)) return;
        final sanitizedValue = _sanitizeToolPayloadValue(entryValue);
        if (sanitizedValue == null) return;
        output[key] = sanitizedValue;
      });
      return output;
    }
    if (value is Map) {
      return _sanitizeToolPayloadValue(value.cast<String, dynamic>());
    }
    if (value is Iterable) {
      return value
          .map(_sanitizeToolPayloadValue)
          .where((item) => item != null)
          .toList(growable: false);
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return value;
      final exactReplacement = _assistantTextReplacements[trimmed];
      return exactReplacement ?? _normalizeAssistantText(value);
    }
    return value;
  }

  bool _shouldHideToolPayloadKey(String key) {
    const hiddenKeys = <String>{
      'id',
      'uid',
      'clientUid',
      'contractId',
      'invoiceId',
      'propertyId',
      'tenantId',
      'parentBuildingId',
      'attachmentPaths',
      'documentAttachmentPaths',
      'referenceId',
      'navigationAction',
      'route',
      'arguments',
      'requiredArgs',
      'requiredNavigationArgs',
    };
    final normalized = key.trim();
    if (hiddenKeys.contains(normalized)) return true;
    if (normalized.endsWith('Id') &&
        normalized != 'contractSerialNo' &&
        normalized != 'invoiceSerialNo') {
      return true;
    }
    return false;
  }

  String _replaceTechnicalToken(
    String text,
    String token,
    String replacement,
  ) {
    final pattern = RegExp(
      '(?<![A-Za-z0-9_])${RegExp.escape(token)}(?![A-Za-z0-9_])',
    );
    return text.replaceAllMapped(pattern, (_) => replacement);
  }

  String _normalizeAssistantText(String text) {
    var value = text.trimRight();
    if (value.isEmpty) return value;

    final hiddenPatterns = <RegExp>[
      RegExp(r'"(?:contractId|invoiceId|propertyId|tenantId|id)"\s*:\s*"[^"]*"\s*,?'),
      RegExp(r'"(?:contractId|invoiceId|propertyId|tenantId|id)"\s*:\s*[^,\n}\]]+\s*,?'),
      RegExp(r'\b(?:contractId|invoiceId|propertyId|tenantId|id)\s*[:=]\s*[\w-]+\b'),
      RegExp(r'"route"\s*:\s*"[^"]*"\s*,?'),
      RegExp(r'"arguments"\s*:\s*\{[^}]*\}\s*,?'),
      RegExp(r'"navigationAction"\s*:\s*\{[\s\S]*?\}\s*,?'),
    ];
    for (final pattern in hiddenPatterns) {
      value = value.replaceAll(pattern, '');
    }

    _assistantTextReplacements.forEach((token, replacement) {
      value = _replaceTechnicalToken(value, token, replacement);
    });

    value = value
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .replaceAll(RegExp(r'\{\s*,'), '{')
        .replaceAll(RegExp(r',\s*,+'), ',')
        .replaceAll(RegExp(r',\s*}'), '}')
        .replaceAll(RegExp(r',\s*]'), ']')
        .trim();
    return value;
  }

  String _navigationFailureResult(
    String rawResult,
    Map<String, dynamic> action,
  ) {
    final payload = _decodeExecutorPayload(rawResult) ?? <String, dynamic>{};
    return jsonEncode(<String, dynamic>{
      ...payload,
      'success': false,
      'error': 'تعذر فتح الشاشة المطلوبة من واجهة الدردشة الحالية.',
      'code': 'navigation_failed',
      if ((action['route'] ?? '').toString().trim().isNotEmpty)
        'route': (action['route'] ?? '').toString().trim(),
    });
  }

  Future<String> _handleExecutorSideEffects(String result) async {
    final payload = _decodeExecutorPayload(result);
    if (payload == null) return result;

    final action = payload['navigationAction'];
    if (action is Map<String, dynamic>) {
      final didNavigate = await _performNavigationAction(action);
      return didNavigate ? result : _navigationFailureResult(result, action);
    }
    if (action is Map) {
      final casted = action.cast<String, dynamic>();
      final didNavigate = await _performNavigationAction(casted);
      return didNavigate ? result : _navigationFailureResult(result, casted);
    }
    return result;
  }

  Future<bool> _performNavigationAction(Map<String, dynamic> action) async {
    if (!mounted) return false;
    final route = (action['route'] ?? '').toString().trim();
    if (route.isEmpty) return false;

    final rawArguments = action['arguments'];
    final arguments = rawArguments is Map<String, dynamic>
        ? rawArguments
        : rawArguments is Map
            ? rawArguments.cast<String, dynamic>()
            : null;

    return _openRouteFromChat(route, arguments: arguments);
  }

  Future<bool> _openRouteFromChat(
    String route, {
    Map<String, dynamic>? arguments,
  }) async {
    if (!mounted) return false;

    if (arguments != null && arguments.isNotEmpty) {
      try {
        unawaited(Navigator.of(context).pushNamed(route, arguments: arguments));
        return true;
      } catch (_) {
        return false;
      }
    }

    try {
      unawaited(Navigator.of(context).pushNamed(route, arguments: arguments));
      return true;
    } catch (_) {}

    final nextRoute = _buildNavigationRoute(route);
    if (nextRoute != null) {
      unawaited(Navigator.of(context).push(nextRoute));
      return true;
    }

    return false;
  }

  String _formatToolArgValue(dynamic value) {
    if (value == null) return '';
    if (value is Iterable) {
      final items = value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
      return items.join('، ');
    }
    final text = value.toString().trim();
    if (text.isEmpty) return '';
    if (text.length <= 80) return text;
    return '${text.substring(0, 80)}...';
  }

  String _buildToolCallSummary(String name, Map<String, dynamic> args) {
    final lines = <String>['- ${AiChatTools.actionLabel(name)}'];
    args.forEach((key, value) {
      final formattedValue = _formatToolArgValue(value);
      if (formattedValue.isEmpty) return;
      lines.add('${_toolArgLabels[key] ?? key}: $formattedValue');
    });
    return lines.join('\n');
  }

  Future<bool> _confirmWriteToolCalls(List<Map<String, dynamic>> calls) async {
    final summaries = calls.map((call) {
      final fn = (call['function'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final name = (fn['name'] ?? '').toString();
      return _buildToolCallSummary(name, _toolArguments(call));
    }).join('\n\n');

    return CustomConfirmDialog.show(
      context: context,
      title: 'تأكيد التنفيذ',
      message:
          'سيتم تنفيذ العمليات التالية:\n\n$summaries\n\nهل تريد المتابعة؟',
      confirmLabel: 'تنفيذ',
      cancelLabel: 'إلغاء',
      confirmColor: const Color(0xFF0F766E),
    );
  }

  static const Map<String, String> _guidedEntityLabels = <String, String>{
    'add_client_record': 'عميل',
    'add_property': 'عقار',
    'create_contract': 'عقد',
    'create_maintenance_request': 'طلب صيانة',
  };

  static const Map<String, String> _guidedScreenTools = <String, String>{
    'add_client_record': 'open_tenant_entry',
    'add_property': 'open_property_entry',
    'create_contract': 'open_contract_entry',
    'create_maintenance_request': 'open_maintenance_entry',
  };

  Future<bool> _handleLocalCollectionFlow({
    required String rawText,
    required String visibleUserText,
  }) async {
    final text = rawText.trim();

    if (_collectionSession == null) {
      final operation = _detectLocalAddOperation(text);
      if (operation == null) return false;
      final session = _createCollectionSession(operation, text);
      if (!mounted) return true;
      setState(() {
        _messages.add(_UiMessage(role: 'user', text: visibleUserText));
        _collectionSession = session;
        _messages.add(
          _UiMessage(
            role: 'assistant',
            text: _buildEntryChoicePrompt(session),
          ),
        );
      });
      _scrollToBottom();
      return true;
    }

    final session = _collectionSession!;
    if (!mounted) return true;
    setState(() {
      _messages.add(_UiMessage(role: 'user', text: visibleUserText));
    });
    _scrollToBottom();

    if (_isCancelCollectionText(text)) {
      setState(() {
        _collectionSession = null;
        _messages.add(
          const _UiMessage(
            role: 'assistant',
            text: 'تم إلغاء معالج الإضافة. إذا رغبت نبدأ من جديد أو أفتح لك الشاشة مباشرة.',
          ),
        );
      });
      _scrollToBottom();
      return true;
    }

    if (session.awaitingEntryChoice) {
      return _handleEntryChoiceResponse(session, text);
    }

    return _handleCollectionFieldResponse(session, text);
  }

  String? _detectLocalAddOperation(String text) {
    final value = text.trim().toLowerCase();
    if (value.isEmpty) return null;
    final hasAction = <String>[
      'اضف',
      'أضف',
      'إضافة',
      'اضافة',
      'انشئ',
      'أنشئ',
      'إنشاء',
      'انشاء',
      'سجل',
      'سجّل',
      'ابغى اضيف',
      'أبغى أضيف',
      'اريد اضافة',
      'أريد إضافة',
    ].any(value.contains);
    if (!hasAction || value.contains('كيف')) return null;

    if (_containsAny(value, <String>['صيانة', 'طلب صيانة', 'خدمة صيانة'])) {
      return 'create_maintenance_request';
    }
    if (_containsAny(value, <String>['عقد', 'عقد إيجار', 'عقد ايجار'])) {
      return 'create_contract';
    }
    if (_containsAny(value, <String>['عقار', 'شقة', 'شقه', 'فيلا', 'عمارة', 'عماره', 'مكتب', 'محل', 'مستودع', 'أرض', 'ارض'])) {
      return 'add_property';
    }
    if (_containsAny(value, <String>['عميل', 'مستأجر', 'مستاجر', 'شركة', 'شركه', 'مقدم خدمة', 'مزود خدمة', 'فني'])) {
      return 'add_client_record';
    }
    return null;
  }

  bool _containsAny(String text, List<String> patterns) {
    for (final pattern in patterns) {
      if (text.contains(pattern)) return true;
    }
    return false;
  }

  _ChatCollectionSession _createCollectionSession(
    String operation,
    String sourceText,
  ) {
    return _ChatCollectionSession(
      operation: operation,
      entityLabel: _guidedEntityLabels[operation] ?? 'عنصر',
      screenTool: _guidedScreenTools[operation] ?? '',
      awaitingEntryChoice: true,
      values: _seedCollectionValues(operation, sourceText),
      skippedFields: <String>{},
      lastPromptedField: null,
    );
  }

  Map<String, dynamic> _seedCollectionValues(
    String operation,
    String text,
  ) {
    final seeded = <String, dynamic>{};
    if (operation == 'add_client_record') {
      final clientType = _detectClientTypeHint(text);
      if ((clientType ?? '').isNotEmpty) {
        seeded['clientType'] = clientType;
      }
    }
    if (operation == 'add_property') {
      final propertyType = _detectPropertyTypeHint(text);
      if ((propertyType ?? '').isNotEmpty) {
        seeded['type'] = propertyType;
      }
    }
    if (operation == 'create_contract') {
      final term = _normalizeContractTerm(text);
      if ((term ?? '').isNotEmpty) {
        seeded['term'] = term;
      }
    }
    return seeded;
  }

  String? _detectClientTypeHint(String text) {
    final value = text.trim().toLowerCase();
    if (_containsAny(value, <String>['شركة', 'شركه'])) return 'company';
    if (_containsAny(value, <String>['مقدم خدمة', 'مزود خدمة', 'فني'])) {
      return 'serviceProvider';
    }
    return null;
  }

  String? _detectPropertyTypeHint(String text) {
    final value = text.trim().toLowerCase();
    if (_containsAny(value, <String>['شقة', 'شقه'])) return 'apartment';
    if (value.contains('فيلا')) return 'villa';
    if (_containsAny(value, <String>['عمارة', 'عماره'])) return 'building';
    if (_containsAny(value, <String>['أرض', 'ارض'])) return 'land';
    if (value.contains('مكتب')) return 'office';
    if (_containsAny(value, <String>['محل', 'متجر'])) return 'shop';
    if (value.contains('مستودع')) return 'warehouse';
    return null;
  }

  String _buildEntryChoicePrompt(_ChatCollectionSession session) {
    return 'هل تريدني أفتح لك شاشة إضافة ${session.entityLabel}؟ هذا أسرع.\n'
        'أم أضيفه معك من الدردشة سؤالًا سؤالًا؟\n'
        'اكتب: افتح الشاشة\n'
        'أو اكتب: من الدردشة';
  }

  bool _isScreenChoiceText(String text) {
    final value = text.trim().toLowerCase();
    return value == '1' ||
        value.contains('افتح الشاشة') ||
        value == 'الشاشة' ||
        value.contains('فتح الشاشة');
  }

  bool _isChatChoiceText(String text) {
    final value = text.trim().toLowerCase();
    return value == '2' ||
        value.contains('من الدردشة') ||
        value == 'الدردشة' ||
        value.contains('اسألني') ||
        value.contains('سؤال سؤال');
  }

  bool _isCancelCollectionText(String text) {
    final value = text.trim().toLowerCase();
    return value == 'إلغاء' ||
        value == 'الغاء' ||
        value == 'وقف' ||
        value == 'تراجع' ||
        value == 'إيقاف' ||
        value == 'ايقاف';
  }

  bool _isSkipOptionalText(String text) {
    final value = text.trim().toLowerCase();
    return value == 'لا أريده' ||
        value == 'لا اريده' ||
        value == 'تجاوزه' ||
        value == 'تخطي' ||
        value == 'لا' ||
        value == 'تجاوز';
  }

  Future<bool> _openCollectionEntryScreen(
    _ChatCollectionSession session,
  ) async {
    final toolName = session.screenTool;
    if (toolName.isEmpty) {
      if (!mounted) return true;
      setState(() {
        _collectionSession = null;
        _messages.add(
          const _UiMessage(
            role: 'assistant',
            text:
                'تعذر تحديد شاشة الإضافة المناسبة. يمكنك إعادة المحاولة من جديد.',
          ),
        );
      });
      _scrollToBottom();
      return true;
    }

    final result = await _executor!.executeCached(toolName, session.values);
    final handledResult = await _handleExecutorSideEffects(result);
    final responseText = _extractLocalExecutionMessage(handledResult);
    if (!mounted) return true;
    setState(() {
      _collectionSession = null;
      _messages.add(_UiMessage(role: 'assistant', text: responseText));
    });
    _scrollToBottom();
    return true;
  }

  Future<bool> _handleEntryChoiceResponse(
    _ChatCollectionSession session,
    String text,
  ) async {
    if (_isScreenChoiceText(text)) {
      return _openCollectionEntryScreen(session);
    }

    if (_isChatChoiceText(text)) {
      var nextSession = session.copyWith(awaitingEntryChoice: false);
      final nextField = _nextPendingCollectionField(nextSession);
      if (nextField == null) {
        return _executeCollectionSession(nextSession);
      }
      nextSession = nextSession.copyWith(lastPromptedField: nextField.field);
      if (!mounted) return true;
      setState(() {
        _collectionSession = nextSession;
        _messages.add(
          _UiMessage(
            role: 'assistant',
            text: _buildFieldQuestion(nextField),
          ),
        );
      });
      _scrollToBottom();
      return true;
    }

    if (!mounted) return true;
    setState(() {
      _messages.add(
        _UiMessage(
          role: 'assistant',
          text: 'اختر أحد الخيارين فقط:\nافتح الشاشة\nأو من الدردشة',
        ),
      );
    });
    _scrollToBottom();
    return true;
  }

  Future<bool> _handleCollectionFieldResponse(
    _ChatCollectionSession session,
    String text,
  ) async {
    if (_isScreenChoiceText(text)) {
      return _openCollectionEntryScreen(session);
    }

    final field = _nextPendingCollectionField(session);
    if (field == null) {
      return _executeCollectionSession(session);
    }

    final applied = _applyCollectionFieldAnswer(session, field, text);
    if (!applied.isValid) {
      if (!mounted) return true;
      setState(() {
        _messages.add(
          _UiMessage(role: 'assistant', text: applied.errorMessage!),
        );
      });
      _scrollToBottom();
      return true;
    }

    var nextSession = applied.session!;
    final nextField = _nextPendingCollectionField(nextSession);
    if (nextField == null) {
      return _executeCollectionSession(nextSession);
    }

    nextSession = nextSession.copyWith(lastPromptedField: nextField.field);
    if (!mounted) return true;
    setState(() {
      _collectionSession = nextSession;
      _messages.add(
        _UiMessage(role: 'assistant', text: _buildFieldQuestion(nextField)),
      );
    });
    _scrollToBottom();
    return true;
  }

  Future<bool> _executeCollectionSession(
    _ChatCollectionSession session,
  ) async {
    final args = _mergePendingChatAttachmentsIntoArgs(
      session.operation,
      Map<String, dynamic>.from(session.values),
    );
    final confirmed = await _confirmWriteToolCalls(<Map<String, dynamic>>[
      <String, dynamic>{
        'function': <String, dynamic>{
          'name': session.operation,
          'arguments': jsonEncode(args),
        },
      },
    ]);
    if (!confirmed) {
      if (!mounted) return true;
      setState(() {
        _messages.add(
          const _UiMessage(
            role: 'assistant',
            text: 'لم أنفذ العملية بعد. يمكنك تعديل إجابة سابقة، أو قول: افتح الشاشة.',
          ),
        );
      });
      _scrollToBottom();
      return true;
    }

    if (!mounted) return true;
    setState(() {
      _sending = true;
    });

    try {
      final usedPendingAttachments =
          _pendingChatAttachments.isNotEmpty &&
          _toolAcceptsAttachments(session.operation);
      final result = await _executor!.executeCached(session.operation, args);
      final handledResult = await _handleExecutorSideEffects(result);
      final payload = _decodeExecutorPayload(handledResult);
      final success = _toolResultSucceeded(handledResult);
      final nextField = success
          ? null
          : _firstCollectionFieldFromPayload(session, payload);

      if (!mounted) return true;
      setState(() {
        _sending = false;
        if (success) {
          if (usedPendingAttachments) {
            _pendingChatAttachments.clear();
          }
          _collectionSession = null;
          _messages.add(
            _UiMessage(
              role: 'assistant',
              text: _extractLocalExecutionMessage(handledResult),
            ),
          );
        } else {
          var updatedSession = session;
          if (nextField != null) {
            updatedSession =
                updatedSession.copyWith(lastPromptedField: nextField.field);
          }
          _collectionSession = updatedSession;
          _messages.add(
            _UiMessage(
              role: 'assistant',
              text: _buildLocalExecutionFailureMessage(
                payload,
                handledResult,
              ),
            ),
          );
          if (nextField != null) {
            _messages.add(
              _UiMessage(
                role: 'assistant',
                text: _buildFieldQuestion(nextField),
              ),
            );
          }
        }
      });
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return true;
      setState(() {
        _sending = false;
        _messages.add(
          const _UiMessage(
            role: 'assistant',
            text: 'حدث خطأ أثناء تنفيذ العملية. يمكنك المحاولة مرة أخرى أو اختيار فتح الشاشة.',
          ),
        );
      });
      _scrollToBottom();
    }
    return true;
  }

  _ChatFieldDescriptor? _firstCollectionFieldFromPayload(
    _ChatCollectionSession session,
    Map<String, dynamic>? payload,
  ) {
    final missingFields = payload?['missingFields'];
    if (missingFields is Iterable) {
      for (final item in missingFields) {
        final fieldName = item is Map<String, dynamic>
            ? (item['field'] ?? '').toString().trim()
            : item is Map
                ? (item['field'] ?? '').toString().trim()
                : '';
        if (fieldName.isEmpty) continue;
        final descriptor = _findCollectionFieldByName(session, fieldName);
        if (descriptor != null) {
          return descriptor;
        }
      }
    }
    return _nextPendingCollectionField(session);
  }

  String _extractLocalExecutionMessage(String rawResult) {
    final payload = _decodeExecutorPayload(rawResult);
    if (payload == null) return _normalizeAssistantText(rawResult);
    final message = (payload['message'] ?? payload['error'] ?? '').toString().trim();
    if (message.isNotEmpty) return _normalizeAssistantText(message);
    return _normalizeAssistantText(rawResult);
  }

  String _buildLocalExecutionFailureMessage(
    Map<String, dynamic>? payload,
    String rawResult,
  ) {
    final base = (payload?['validationError'] ??
            payload?['error'] ??
            'تعذر إكمال العملية بهذه البيانات.')
        .toString()
        .trim();
    if (base.isEmpty) {
      return _normalizeAssistantText(rawResult);
    }
    final needsScreenHint =
        payload?['requiresScreenCompletion'] == true ||
        (payload?['suggestedScreen'] ?? '').toString().trim().isNotEmpty ||
        payload?['entryOptions'] is Iterable;
    if (!needsScreenHint) {
      return _normalizeAssistantText(base);
    }
    return _normalizeAssistantText('$base\nيمكنك أيضًا قول: افتح الشاشة.');
  }

  _ChatFieldDescriptor? _nextPendingCollectionField(
    _ChatCollectionSession session,
  ) {
    final plan = _buildCollectionFieldPlan(session);
    for (final field in plan.where((item) => item.required)) {
      if (!_sessionHasAnswerForField(session, field)) return field;
    }
    for (final field in plan.where((item) => !item.required)) {
      if (!_sessionHasAnswerForField(session, field)) return field;
    }
    return null;
  }

  _ChatFieldDescriptor? _findCollectionFieldByName(
    _ChatCollectionSession session,
    String fieldName,
  ) {
    for (final field in _buildCollectionFieldPlan(session)) {
      if (field.field == fieldName) return field;
    }
    switch (fieldName) {
      case 'documentAttachmentPaths':
        return const _ChatFieldDescriptor(
          field: 'documentAttachmentPaths',
          label: 'مرفقات الوثيقة',
          prompt: 'ارفع مرفقات الوثيقة هنا في الدردشة الآن. الحد الأقصى 3 ملفات.',
          inputType: 'attachments',
          required: true,
        );
      case 'dailyCheckoutHour':
        return const _ChatFieldDescriptor(
          field: 'dailyCheckoutHour',
          label: 'ساعة الخروج',
          prompt: 'اكتب ساعة الخروج من 0 إلى 23.',
          inputType: 'number',
          required: true,
        );
      default:
        return null;
    }
  }

  bool _sessionHasAnswerForField(
    _ChatCollectionSession session,
    _ChatFieldDescriptor field,
  ) {
    if (session.skippedFields.contains(field.field)) return true;
    if (field.inputType == 'attachments') {
      return _hasNonEmptyPathList(session.values[field.field]) ||
          _pendingChatAttachments.isNotEmpty;
    }
    final value = session.values[field.field];
    if (value is String) return value.trim().isNotEmpty;
    return value != null;
  }

  List<_ChatFieldDescriptor> _buildCollectionFieldPlan(
    _ChatCollectionSession session,
  ) {
    switch (session.operation) {
      case 'add_client_record':
        return _buildClientCollectionFields(session.values);
      case 'add_property':
        return _buildPropertyCollectionFields(session.values);
      case 'create_contract':
        return _buildContractCollectionFields(session.values);
      case 'create_maintenance_request':
        return _buildMaintenanceCollectionFields();
      default:
        return const <_ChatFieldDescriptor>[];
    }
  }

  List<_ChatFieldDescriptor> _buildClientCollectionFields(
    Map<String, dynamic> values,
  ) {
    final clientType = (values['clientType'] ?? '').toString().trim();
    final fields = <_ChatFieldDescriptor>[
      const _ChatFieldDescriptor(
        field: 'clientType',
        label: 'نوع العميل',
        prompt: 'اكتب: مستأجر أو شركة أو مقدم خدمة.',
        inputType: 'clientType',
        required: true,
      ),
    ];
    switch (clientType) {
      case 'company':
        fields.addAll(const <_ChatFieldDescriptor>[
          _ChatFieldDescriptor(
            field: 'companyName',
            label: 'اسم الشركة',
            prompt: 'اكتب اسم الشركة.',
            inputType: 'text',
            required: true,
          ),
          _ChatFieldDescriptor(
            field: 'companyCommercialRegister',
            label: 'رقم السجل التجاري',
            prompt: 'اكتب رقم السجل التجاري.',
            inputType: 'text',
            required: true,
          ),
          _ChatFieldDescriptor(
            field: 'companyTaxNumber',
            label: 'الرقم الضريبي',
            prompt: 'اكتب الرقم الضريبي.',
            inputType: 'text',
            required: true,
          ),
          _ChatFieldDescriptor(
            field: 'companyRepresentativeName',
            label: 'اسم ممثل الشركة',
            prompt: 'اكتب اسم ممثل الشركة.',
            inputType: 'text',
            required: true,
          ),
          _ChatFieldDescriptor(
            field: 'companyRepresentativePhone',
            label: 'رقم جوال ممثل الشركة',
            prompt: 'اكتب رقم الجوال.',
            inputType: 'text',
            required: true,
          ),
          _ChatFieldDescriptor(
            field: 'attachmentPaths',
            label: 'المرفقات',
            prompt: 'ارفع المرفقات هنا في الدردشة الآن. الحد الأقصى 3 ملفات.',
            inputType: 'attachments',
            required: true,
          ),
        ]);
        break;
      case 'serviceProvider':
        fields.addAll(const <_ChatFieldDescriptor>[
          _ChatFieldDescriptor(
            field: 'fullName',
            label: 'الاسم الكامل',
            prompt: 'اكتب الاسم الكامل.',
            inputType: 'text',
            required: true,
          ),
          _ChatFieldDescriptor(
            field: 'phone',
            label: 'رقم الجوال',
            prompt: 'اكتب رقم الجوال.',
            inputType: 'text',
            required: true,
          ),
          _ChatFieldDescriptor(
            field: 'serviceSpecialization',
            label: 'التخصص أو الخدمة',
            prompt: 'اكتب التخصص أو نوع الخدمة.',
            inputType: 'text',
            required: true,
          ),
          _ChatFieldDescriptor(
            field: 'email',
            label: 'البريد الإلكتروني',
            prompt: 'اكتب البريد الإلكتروني إذا رغبت.',
            inputType: 'text',
            required: false,
          ),
        ]);
        break;
      case 'tenant':
        fields.addAll(const <_ChatFieldDescriptor>[
          _ChatFieldDescriptor(
            field: 'fullName',
            label: 'الاسم الكامل',
            prompt: 'اكتب الاسم الكامل.',
            inputType: 'text',
            required: true,
          ),
          _ChatFieldDescriptor(
            field: 'phone',
            label: 'رقم الجوال',
            prompt: 'اكتب رقم الجوال.',
            inputType: 'text',
            required: true,
          ),
          _ChatFieldDescriptor(
            field: 'nationalId',
            label: 'رقم الهوية',
            prompt: 'اكتب رقم الهوية.',
            inputType: 'text',
            required: true,
          ),
          _ChatFieldDescriptor(
            field: 'email',
            label: 'البريد الإلكتروني',
            prompt: 'اكتب البريد الإلكتروني إذا رغبت.',
            inputType: 'text',
            required: false,
          ),
          _ChatFieldDescriptor(
            field: 'nationality',
            label: 'الجنسية',
            prompt: 'اكتب الجنسية إذا رغبت.',
            inputType: 'text',
            required: false,
          ),
          _ChatFieldDescriptor(
            field: 'attachmentPaths',
            label: 'المرفقات',
            prompt: 'ارفع المرفقات هنا في الدردشة الآن. الحد الأقصى 3 ملفات.',
            inputType: 'attachments',
            required: true,
          ),
        ]);
        break;
      default:
        break;
    }
    return fields;
  }

  List<_ChatFieldDescriptor> _buildPropertyCollectionFields(
    Map<String, dynamic> values,
  ) {
    final propertyType = (values['type'] ?? '').toString().trim();
    final rentalMode = (values['rentalMode'] ?? '').toString().trim();
    final fields = <_ChatFieldDescriptor>[
      const _ChatFieldDescriptor(
        field: 'name',
        label: 'اسم العقار',
        prompt: 'اكتب اسم العقار.',
        inputType: 'text',
        required: true,
      ),
      const _ChatFieldDescriptor(
        field: 'type',
        label: 'نوع العقار',
        prompt: 'اكتب نوع العقار: شقة أو فيلا أو عمارة أو أرض أو مكتب أو محل أو مستودع.',
        inputType: 'propertyType',
        required: true,
      ),
      const _ChatFieldDescriptor(
        field: 'address',
        label: 'العنوان',
        prompt: 'اكتب عنوان العقار.',
        inputType: 'text',
        required: true,
      ),
      if (propertyType == 'building')
        const _ChatFieldDescriptor(
          field: 'rentalMode',
          label: 'نمط التأجير',
          prompt: 'اكتب: كامل المبنى أو لكل وحدة.',
          inputType: 'rentalMode',
          required: true,
        ),
      if (propertyType == 'building' && rentalMode == 'perUnit')
        const _ChatFieldDescriptor(
          field: 'totalUnits',
          label: 'عدد الوحدات',
          prompt: 'اكتب عدد الوحدات بالأرقام.',
          inputType: 'number',
          required: true,
        ),
      if (propertyType == 'apartment' || propertyType == 'villa')
        const _ChatFieldDescriptor(
          field: 'furnished',
          label: 'هل العقار مفروش',
          prompt: 'اكتب: نعم أو لا.',
          inputType: 'bool',
          required: true,
        ),
      const _ChatFieldDescriptor(
        field: 'documentType',
        label: 'نوع الوثيقة',
        prompt: 'اكتب نوع وثيقة العقار.',
        inputType: 'text',
        required: true,
      ),
      const _ChatFieldDescriptor(
        field: 'documentNumber',
        label: 'رقم الوثيقة',
        prompt: 'اكتب رقم وثيقة العقار.',
        inputType: 'text',
        required: true,
      ),
      const _ChatFieldDescriptor(
        field: 'documentDate',
        label: 'تاريخ الوثيقة',
        prompt: 'اكتب التاريخ بصيغة YYYY-MM-DD.',
        inputType: 'date',
        required: true,
      ),
      const _ChatFieldDescriptor(
        field: 'documentAttachmentPaths',
        label: 'مرفقات الوثيقة',
        prompt: 'ارفع مرفقات الوثيقة هنا في الدردشة الآن. الحد الأقصى 3 ملفات.',
        inputType: 'attachments',
        required: true,
      ),
      const _ChatFieldDescriptor(
        field: 'description',
        label: 'الوصف',
        prompt: 'اكتب وصفًا إضافيًا إذا رغبت.',
        inputType: 'text',
        required: false,
      ),
    ];
    return fields;
  }

  List<_ChatFieldDescriptor> _buildContractCollectionFields(
    Map<String, dynamic> values,
  ) {
    final term = (values['term'] ?? '').toString().trim();
    return <_ChatFieldDescriptor>[
      const _ChatFieldDescriptor(
        field: 'tenantName',
        label: 'العميل',
        prompt: 'اكتب اسم العميل كما هو في النظام.',
        inputType: 'text',
        required: true,
      ),
      const _ChatFieldDescriptor(
        field: 'propertyName',
        label: 'العقار',
        prompt: 'اكتب اسم العقار كما هو في النظام.',
        inputType: 'text',
        required: true,
      ),
      const _ChatFieldDescriptor(
        field: 'startDate',
        label: 'تاريخ البداية',
        prompt: 'اكتب التاريخ بصيغة YYYY-MM-DD.',
        inputType: 'date',
        required: true,
      ),
      const _ChatFieldDescriptor(
        field: 'endDate',
        label: 'تاريخ النهاية',
        prompt: 'اكتب التاريخ بصيغة YYYY-MM-DD.',
        inputType: 'date',
        required: true,
      ),
      const _ChatFieldDescriptor(
        field: 'rentAmount',
        label: 'قيمة الإيجار',
        prompt: 'اكتب مبلغ الإيجار بالأرقام.',
        inputType: 'number',
        required: true,
      ),
      const _ChatFieldDescriptor(
        field: 'totalAmount',
        label: 'إجمالي العقد',
        prompt: 'اكتب إجمالي مبلغ العقد بالأرقام.',
        inputType: 'number',
        required: true,
      ),
      const _ChatFieldDescriptor(
        field: 'term',
        label: 'مدة العقد',
        prompt: 'اكتب: يومي أو شهري أو ربع سنوي أو نصف سنوي أو سنوي.',
        inputType: 'contractTerm',
        required: false,
      ),
      if (term == 'daily')
        const _ChatFieldDescriptor(
          field: 'dailyCheckoutHour',
          label: 'ساعة الخروج',
          prompt: 'اكتب ساعة الخروج من 0 إلى 23.',
          inputType: 'number',
          required: true,
        ),
      const _ChatFieldDescriptor(
        field: 'paymentCycle',
        label: 'دورة السداد',
        prompt: 'اكتب: شهري أو ربع سنوي أو نصف سنوي أو سنوي.',
        inputType: 'paymentCycle',
        required: false,
      ),
      const _ChatFieldDescriptor(
        field: 'notes',
        label: 'ملاحظات',
        prompt: 'اكتب الملاحظات إذا رغبت.',
        inputType: 'text',
        required: false,
      ),
      const _ChatFieldDescriptor(
        field: 'attachmentPaths',
        label: 'مرفقات العقد',
        prompt: 'إذا لديك مرفقات ارفعها هنا في الدردشة الآن، أو قل: لا أريده.',
        inputType: 'attachments',
        required: false,
      ),
    ];
  }

  List<_ChatFieldDescriptor> _buildMaintenanceCollectionFields() {
    return const <_ChatFieldDescriptor>[
      _ChatFieldDescriptor(
        field: 'propertyName',
        label: 'العقار',
        prompt: 'اكتب اسم العقار كما هو في النظام.',
        inputType: 'text',
        required: true,
      ),
      _ChatFieldDescriptor(
        field: 'title',
        label: 'نوع الخدمة',
        prompt: 'اكتب عنوان طلب الصيانة أو نوع الخدمة.',
        inputType: 'text',
        required: true,
      ),
      _ChatFieldDescriptor(
        field: 'description',
        label: 'الوصف',
        prompt: 'اكتب وصف المشكلة إذا رغبت.',
        inputType: 'text',
        required: false,
      ),
      _ChatFieldDescriptor(
        field: 'priority',
        label: 'الأولوية',
        prompt: 'اكتب: منخفضة أو متوسطة أو عالية أو عاجلة.',
        inputType: 'priority',
        required: false,
      ),
      _ChatFieldDescriptor(
        field: 'scheduledDate',
        label: 'تاريخ الجدولة',
        prompt: 'اكتب التاريخ بصيغة YYYY-MM-DD إذا رغبت.',
        inputType: 'date',
        required: false,
      ),
      _ChatFieldDescriptor(
        field: 'executionDeadline',
        label: 'آخر موعد للتنفيذ',
        prompt: 'اكتب التاريخ بصيغة YYYY-MM-DD إذا رغبت.',
        inputType: 'date',
        required: false,
      ),
      _ChatFieldDescriptor(
        field: 'cost',
        label: 'التكلفة',
        prompt: 'اكتب التكلفة المتوقعة بالأرقام إذا رغبت.',
        inputType: 'number',
        required: false,
      ),
      _ChatFieldDescriptor(
        field: 'provider',
        label: 'مقدم الخدمة',
        prompt: 'اكتب اسم مقدم الخدمة إذا رغبت.',
        inputType: 'text',
        required: false,
      ),
      _ChatFieldDescriptor(
        field: 'attachmentPaths',
        label: 'المرفقات',
        prompt: 'إذا لديك مرفقات ارفعها هنا في الدردشة الآن، أو قل: لا أريده.',
        inputType: 'attachments',
        required: false,
      ),
    ];
  }

  String _buildFieldQuestion(_ChatFieldDescriptor field) {
    final marker = field.required ? 'إلزامي' : 'اختياري';
    final skipHint = field.required ? '' : '\nيمكنك قول: لا أريده';
    return '${field.label} ($marker)\n${field.prompt}$skipHint';
  }

  _CollectionAnswerResult _applyCollectionFieldAnswer(
    _ChatCollectionSession session,
    _ChatFieldDescriptor field,
    String text,
  ) {
    final values = Map<String, dynamic>.from(session.values);
    final skippedFields = Set<String>.from(session.skippedFields);

    if (!field.required && _isSkipOptionalText(text)) {
      skippedFields.add(field.field);
      values.remove(field.field);
      return _CollectionAnswerResult.valid(
        session.copyWith(values: values, skippedFields: skippedFields),
      );
    }

    if (field.inputType == 'attachments') {
      if (_pendingChatAttachments.isEmpty) {
        return _CollectionAnswerResult.invalid(
          'ارفع ${field.label} هنا في الدردشة أولًا. الحد الأقصى 3 ملفات.',
        );
      }
      final paths = _pendingChatAttachments
          .map((attachment) => attachment.path)
          .toList(growable: false);
      values[field.field] = paths;
      if (field.field == 'documentAttachmentPaths') {
        values['attachmentPaths'] = paths;
      }
      skippedFields.remove(field.field);
      return _CollectionAnswerResult.valid(
        session.copyWith(values: values, skippedFields: skippedFields),
      );
    }

    final parsed = _parseCollectionFieldValue(field, text);
    if (!parsed.isValid) {
      return _CollectionAnswerResult.invalid(parsed.errorMessage!);
    }
    values[field.field] = parsed.value;
    skippedFields.remove(field.field);
    return _CollectionAnswerResult.valid(
      session.copyWith(values: values, skippedFields: skippedFields),
    );
  }

  _FieldParseResult _parseCollectionFieldValue(
    _ChatFieldDescriptor field,
    String text,
  ) {
    final value = _normalizeArabicDigits(text.trim());
    if (value.isEmpty) {
      return _FieldParseResult.invalid('الرجاء كتابة الإجابة المطلوبة.');
    }

    switch (field.inputType) {
      case 'clientType':
        final clientType = _normalizeClientType(value);
        if (clientType == null) {
          return _FieldParseResult.invalid(
            'اكتب نوع العميل بهذه الصيغة: مستأجر أو شركة أو مقدم خدمة.',
          );
        }
        return _FieldParseResult.valid(clientType);
      case 'propertyType':
        final propertyType = _normalizePropertyType(value);
        if (propertyType == null) {
          return _FieldParseResult.invalid(
            'اكتب نوع العقار بهذه الصيغة: شقة أو فيلا أو عمارة أو أرض أو مكتب أو محل أو مستودع.',
          );
        }
        return _FieldParseResult.valid(propertyType);
      case 'rentalMode':
        final rentalMode = _normalizeRentalMode(value);
        if (rentalMode == null) {
          return _FieldParseResult.invalid(
            'اكتب: كامل المبنى أو لكل وحدة.',
          );
        }
        return _FieldParseResult.valid(rentalMode);
      case 'bool':
        final boolValue = _normalizeBooleanValue(value);
        if (boolValue == null) {
          return _FieldParseResult.invalid('اكتب: نعم أو لا.');
        }
        return _FieldParseResult.valid(boolValue);
      case 'date':
        final dateValue = _normalizeDateValue(value);
        if (dateValue == null) {
          return _FieldParseResult.invalid(
            'اكتب التاريخ بصيغة YYYY-MM-DD فقط.',
          );
        }
        return _FieldParseResult.valid(dateValue);
      case 'number':
        final numberValue = _normalizeNumberValue(value);
        if (numberValue == null) {
          return _FieldParseResult.invalid('اكتب الرقم فقط بصيغة صحيحة.');
        }
        return _FieldParseResult.valid(numberValue);
      case 'contractTerm':
        final termValue = _normalizeContractTerm(value);
        if (termValue == null) {
          return _FieldParseResult.invalid(
            'اكتب: يومي أو شهري أو ربع سنوي أو نصف سنوي أو سنوي.',
          );
        }
        return _FieldParseResult.valid(termValue);
      case 'paymentCycle':
        final cycleValue = _normalizePaymentCycle(value);
        if (cycleValue == null) {
          return _FieldParseResult.invalid(
            'اكتب: شهري أو ربع سنوي أو نصف سنوي أو سنوي.',
          );
        }
        return _FieldParseResult.valid(cycleValue);
      case 'priority':
        final priorityValue = _normalizePriorityValue(value);
        if (priorityValue == null) {
          return _FieldParseResult.invalid(
            'اكتب: منخفضة أو متوسطة أو عالية أو عاجلة.',
          );
        }
        return _FieldParseResult.valid(priorityValue);
      default:
        return _FieldParseResult.valid(value);
    }
  }

  String _normalizeArabicDigits(String text) {
    const arabicDigits = <String, String>{
      '٠': '0',
      '١': '1',
      '٢': '2',
      '٣': '3',
      '٤': '4',
      '٥': '5',
      '٦': '6',
      '٧': '7',
      '٨': '8',
      '٩': '9',
    };
    var value = text;
    arabicDigits.forEach((arabic, ascii) {
      value = value.replaceAll(arabic, ascii);
    });
    return value;
  }

  String? _normalizeClientType(String text) {
    final value = text.toLowerCase();
    if (_containsAny(value, <String>['مستأجر', 'مستاجر', 'عميل', 'tenant'])) {
      return 'tenant';
    }
    if (_containsAny(value, <String>['شركة', 'شركه', 'company'])) {
      return 'company';
    }
    if (_containsAny(value, <String>['مقدم خدمة', 'مزود خدمة', 'فني', 'serviceprovider', 'service provider'])) {
      return 'serviceProvider';
    }
    return null;
  }

  String? _normalizePropertyType(String text) {
    final value = text.toLowerCase();
    if (_containsAny(value, <String>['شقة', 'شقه', 'apartment'])) return 'apartment';
    if (_containsAny(value, <String>['فيلا', 'villa'])) return 'villa';
    if (_containsAny(value, <String>['عمارة', 'عماره', 'building'])) return 'building';
    if (_containsAny(value, <String>['أرض', 'ارض', 'land'])) return 'land';
    if (_containsAny(value, <String>['مكتب', 'office'])) return 'office';
    if (_containsAny(value, <String>['محل', 'shop', 'متجر'])) return 'shop';
    if (_containsAny(value, <String>['مستودع', 'warehouse'])) return 'warehouse';
    return null;
  }

  String? _normalizeRentalMode(String text) {
    final value = text.toLowerCase();
    if (_containsAny(value, <String>['كامل', 'كامل المبنى', 'كامل العقار', 'whole'])) {
      return 'wholeBuilding';
    }
    if (_containsAny(value, <String>['لكل وحدة', 'وحدات', 'وحدة وحدة', 'perunit', 'per unit'])) {
      return 'perUnit';
    }
    return null;
  }

  bool? _normalizeBooleanValue(String text) {
    final value = text.toLowerCase();
    if (_containsAny(value, <String>['نعم', 'ايوه', 'أيوه', 'yes', 'مفروش'])) {
      return true;
    }
    if (_containsAny(value, <String>['لا', 'ليس', 'no', 'غير مفروش'])) {
      return false;
    }
    return null;
  }

  String? _normalizeDateValue(String text) {
    final value = text.trim();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;
    try {
      DateTime.parse(value);
      return value;
    } catch (_) {
      return null;
    }
  }

  double? _normalizeNumberValue(String text) {
    final compact = text.replaceAll(',', '').replaceAll('،', ' ');
    final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(compact);
    if (match == null) return null;
    return double.tryParse(match.group(0)!);
  }

  String? _normalizeContractTerm(String text) {
    final value = text.toLowerCase();
    if (_containsAny(value, <String>['يومي', 'daily'])) return 'daily';
    if (_containsAny(value, <String>['ربع سنوي', 'quarterly'])) return 'quarterly';
    if (_containsAny(value, <String>['نصف سنوي', 'semiannual', 'semi annual'])) {
      return 'semiAnnual';
    }
    if (_containsAny(value, <String>['سنوي', 'annual'])) return 'annual';
    if (_containsAny(value, <String>['شهري', 'monthly'])) return 'monthly';
    return null;
  }

  String? _normalizePaymentCycle(String text) {
    final value = text.toLowerCase();
    if (_containsAny(value, <String>['ربع سنوي', 'quarterly'])) return 'quarterly';
    if (_containsAny(value, <String>['نصف سنوي', 'semiannual', 'semi annual'])) {
      return 'semiAnnual';
    }
    if (_containsAny(value, <String>['سنوي', 'annual'])) return 'annual';
    if (_containsAny(value, <String>['شهري', 'monthly'])) return 'monthly';
    return null;
  }

  String? _normalizePriorityValue(String text) {
    final value = text.toLowerCase();
    if (_containsAny(value, <String>['منخفض', 'منخفضة', 'low'])) return 'low';
    if (_containsAny(value, <String>['متوسط', 'متوسطة', 'medium'])) return 'medium';
    if (_containsAny(value, <String>['عالي', 'عالية', 'high'])) return 'high';
    if (_containsAny(value, <String>['عاجل', 'عاجلة', 'urgent'])) return 'urgent';
    return null;
  }

  String _toolCancelledResult(String name) {
    return jsonEncode({
      'error': 'تم إلغاء العملية من المستخدم قبل التنفيذ.',
      'code': 'cancelled_by_user',
      'tool': name,
    });
  }

  _LocalToolIntent? _detectLocalUtilityIntent(String rawText) {
    final value = _normalizeArabicDigits(rawText.trim().toLowerCase());
    if (value.isEmpty) return null;
    final asksCount = _containsAny(value, <String>[
      'كم',
      'عدد',
      'إجمالي',
      'اجمالي',
      'المجموع',
      'مجموع',
    ]);
    final mentionsProperties = _containsAny(value, <String>[
      'عقار',
      'عقارات',
      'عمارة',
      'عمائر',
      'وحدة',
      'وحدات',
      'فيلا',
      'أرض',
      'ارض',
    ]);
    final mentionsContracts =
        _containsAny(value, <String>['عقد', 'عقود', 'العقد', 'العقود']);
    final mentionsOfficeScope = _containsAny(value, <String>[
      'المكتب',
      'لوحة المكتب',
      'عملاء المكتب',
      'جميع العملاء',
      'كل العملاء',
    ]);
    final asksPropertyCount = asksCount && mentionsProperties;
    final asksContractCount = asksCount && mentionsContracts;
    final asksContractInstallments =
        mentionsContracts &&
        _containsAny(value, <String>[
          'دفعة',
          'دفعات',
          'قسط',
          'أقساط',
          'الاقساط',
          'مدفوع',
          'مسدد',
          'متبقي',
          'مستحق',
          'مستحقة',
          'مستحقات',
          'قادمة',
          'القادمة',
          'متأخر',
          'متأخرة',
          'متاخر',
          'متاخره',
          'سداد',
          'استحقاق',
        ]);
    final asksSpecificOfficeClientPortfolio =
        _isOfficeSession &&
        _containsAny(value, <String>['عميل', 'العميل']) &&
        _containsAny(value, <String>[
          'تقرير',
          'تفاصيل',
          'تفاصيله',
          'تقارير',
          'تقاريره',
          'عقارات',
          'عقاراته',
          'عقود',
          'عقوده',
          'محفظته',
          'حسابه',
          'ملفه',
        ]);

    final wantsNavigation = _containsAny(value, <String>[
      'افتح',
      'فتح',
      'روح',
      'انتقل',
      'اذهب',
      'وديني',
    ]);
    if (wantsNavigation) {
      final screen = _detectScreenKeyFromText(value);
      if (screen != null) {
        return _LocalToolIntent(
          toolName: 'navigate_to_screen',
          args: <String, dynamic>{'screen': screen},
          title: 'فتح الشاشة',
          isNavigation: true,
        );
      }
    }

    final wantsReport = _containsAny(value, <String>[
      'تقرير',
      'تقارير',
      'احصائية',
      'إحصائية',
      'ملخص مالي',
      'رصيد',
      'ارصدة',
      'أرصدة',
      'صافي',
    ]);
    final wantsReportBreakdown = _containsAny(value, <String>[
      'كيف',
      'ليش',
      'لماذا',
      'وش سبب',
      'ما سبب',
      'من وين',
      'من أين',
      'اشرح',
      'فسر',
      'وضح',
      'فصل',
      'تفصيل',
      'تفاصيل',
      'مصدر',
      'المصدر',
      'الايراد',
      'الإيراد',
      'الايرادات',
      'الإيرادات',
      'مصروف',
      'مصروفات',
      'منصرف',
      'منصرفات',
      'الدفتر',
      'قيد',
      'قيود',
      'حركة',
      'حركات',
      'سند',
      'سندات',
      'فاتورة',
      'فواتير',
      'دفعة',
      'دفعات',
      'تحصيل',
      'عمولة',
    ]);
    final wantsReportAction = _containsAny(value, <String>[
      'خصم',
      'تسوية',
      'تحويل',
      'سحب',
      'اضافة',
      'إضافة',
      'اضف',
      'أضف',
      'نفذ',
      'سو',
      'سوي',
      'اعمل',
      'أعمل',
    ]);
    final asksOutstandingSummary = _containsAny(value, <String>[
      'كم المستحق',
      'المستحقات',
      'المتأخرات',
      'متأخرات',
      'متاخرات',
    ]);

    if (asksContractInstallments || asksSpecificOfficeClientPortfolio) {
      return null;
    }

    if (_isOfficeSession &&
        (asksPropertyCount ||
            asksContractCount ||
            (mentionsOfficeScope &&
                _containsAny(value, <String>[
                  'إجمالي العقارات',
                  'اجمالي العقارات',
                  'إجمالي العقود',
                  'اجمالي العقود',
                ])))) {
      return const _LocalToolIntent(
        toolName: 'get_office_dashboard',
        args: <String, dynamic>{},
        title: 'ملخص لوحة المكتب',
      );
    }

    if (asksPropertyCount) {
      return const _LocalToolIntent(
        toolName: 'get_properties_summary',
        args: <String, dynamic>{},
        title: 'ملخص العقارات',
      );
    }

    if (asksContractCount) {
      return const _LocalToolIntent(
        toolName: 'get_contracts_report',
        args: <String, dynamic>{},
        title: 'ملخص العقود',
      );
    }

    if (wantsReportAction ||
        (wantsReportBreakdown && (wantsReport || asksOutstandingSummary))) {
      return null;
    }

    if (_isOfficeSession &&
        wantsReport &&
        _containsAny(value, <String>['عقار', 'عقارات', 'عقد', 'عقود', 'عميل', 'عملاء'])) {
      return const _LocalToolIntent(
        toolName: 'get_office_dashboard',
        args: <String, dynamic>{},
        title: 'ملخص لوحة المكتب',
      );
    }

    if (wantsReport && _containsAny(value, <String>['مالك', 'ملاك', 'المالك', 'الملاك'])) {
      return const _LocalToolIntent(
        toolName: 'get_owners_report',
        args: const <String, dynamic>{},
        title: 'تقرير الملاك',
      );
    }
    if (wantsReport && _containsAny(value, <String>['عقار', 'عقارات', 'عمارة', 'وحدة'])) {
      return const _LocalToolIntent(
        toolName: 'get_properties_report',
        args: const <String, dynamic>{},
        title: 'تقرير العقارات',
      );
    }
    if (wantsReport && _containsAny(value, <String>['عميل', 'عملاء', 'مستأجر', 'مستاجر', 'مستأجرين', 'مستاجرين'])) {
      return const _LocalToolIntent(
        toolName: 'get_clients_report',
        args: const <String, dynamic>{},
        title: 'تقرير العملاء',
      );
    }
    if (wantsReport && _containsAny(value, <String>['عقد', 'عقود'])) {
      return const _LocalToolIntent(
        toolName: 'get_contracts_report',
        args: const <String, dynamic>{},
        title: 'تقرير العقود',
      );
    }
    if (wantsReport && _containsAny(value, <String>['صيانة', 'صيانه', 'خدمة', 'خدمات'])) {
      return const _LocalToolIntent(
        toolName: 'get_services_report',
        args: const <String, dynamic>{},
        title: 'تقرير الخدمات والصيانة',
      );
    }
    if (wantsReport &&
        _containsAny(value, <String>['سند', 'سندات', 'فاتورة', 'فواتير', 'دفعة', 'دفعات', 'تحصيل'])) {
      return const _LocalToolIntent(
        toolName: 'get_invoices_report',
        args: const <String, dynamic>{},
        title: 'تقرير السندات والدفعات',
      );
    }
    if (wantsReport || asksOutstandingSummary) {
      return const _LocalToolIntent(
        toolName: 'get_financial_summary',
        args: const <String, dynamic>{},
        title: 'الملخص المالي',
      );
    }

    if (_containsAny(value, <String>['الرئيسية', 'لوحة', 'داشبورد', 'dashboard'])) {
      return _LocalToolIntent(
        toolName: _isOfficeSession ? 'get_office_dashboard' : 'get_home_dashboard',
        args: const <String, dynamic>{},
        title: _isOfficeSession ? 'ملخص لوحة المكتب' : 'ملخص الرئيسية',
      );
    }
    if (_containsAny(value, <String>['العقارات', 'قائمة العقارات', 'اعرض العقارات'])) {
      if (_isOfficeSession) {
        return const _LocalToolIntent(
          toolName: 'get_office_dashboard',
          args: <String, dynamic>{},
          title: 'ملخص لوحة المكتب',
        );
      }
      return const _LocalToolIntent(
        toolName: 'get_properties_list',
        args: const <String, dynamic>{},
        title: 'قائمة العقارات',
      );
    }
    if (_containsAny(value, <String>['العملاء', 'المستأجرين', 'المستاجرين', 'قائمة العملاء'])) {
      if (_isOfficeSession) {
        return const _LocalToolIntent(
          toolName: 'get_office_clients_list',
          args: <String, dynamic>{},
          title: 'قائمة عملاء المكتب',
        );
      }
      return const _LocalToolIntent(
        toolName: 'get_tenants_list',
        args: const <String, dynamic>{},
        title: 'قائمة العملاء',
      );
    }
    if (_containsAny(value, <String>['العقود', 'قائمة العقود'])) {
      if (asksContractInstallments) return null;
      if (_isOfficeSession) {
        return const _LocalToolIntent(
          toolName: 'get_office_dashboard',
          args: <String, dynamic>{},
          title: 'ملخص لوحة المكتب',
        );
      }
      return const _LocalToolIntent(
        toolName: 'get_contracts_list',
        args: const <String, dynamic>{},
        title: 'قائمة العقود',
      );
    }
    if (_containsAny(value, <String>['غير مدفوعة', 'غير مسددة', 'متأخرة', 'متاخره', 'متأخره', 'متاخرات', 'متأخرات'])) {
      return const _LocalToolIntent(
        toolName: 'get_unpaid_invoices',
        args: const <String, dynamic>{},
        title: 'السندات غير المسددة',
      );
    }
    if (_containsAny(value, <String>['السندات', 'الفواتير', 'الدفعات'])) {
      return const _LocalToolIntent(
        toolName: 'get_invoices_list',
        args: const <String, dynamic>{},
        title: 'قائمة السندات والدفعات',
      );
    }
    if (_containsAny(value, <String>['الصيانة', 'الصيانه', 'طلبات الصيانة', 'الخدمات'])) {
      return const _LocalToolIntent(
        toolName: 'get_maintenance_list',
        args: const <String, dynamic>{},
        title: 'قائمة الصيانة والخدمات',
      );
    }
    if (_containsAny(value, <String>['الإشعارات', 'اشعارات', 'التنبيهات', 'تنبيهات'])) {
      return const _LocalToolIntent(
        toolName: 'get_notifications',
        args: const <String, dynamic>{'limit': 15},
        title: 'الإشعارات',
      );
    }
    return null;
  }

  String? _detectScreenKeyFromText(String value) {
    if (_containsAny(value, <String>['الرئيسية', 'home'])) return 'home';
    if (_containsAny(value, <String>['المكتب', 'لوحة المكتب'])) return 'office';
    if (_containsAny(value, <String>['إضافة عقار', 'اضافة عقار', 'عقار جديد'])) return 'properties_new';
    if (_containsAny(value, <String>['العقارات', 'عقار'])) return 'properties';
    if (_containsAny(value, <String>['إضافة عميل', 'اضافة عميل', 'عميل جديد', 'مستأجر جديد', 'مستاجر جديد'])) return 'tenants_new';
    if (_containsAny(value, <String>['العملاء', 'المستأجرين', 'المستاجرين', 'مستأجر', 'مستاجر'])) return 'tenants';
    if (_containsAny(value, <String>['إضافة عقد', 'اضافة عقد', 'عقد جديد'])) return 'contracts_new';
    if (_containsAny(value, <String>['العقود', 'عقد'])) return 'contracts';
    if (_containsAny(value, <String>['السندات', 'الفواتير', 'دفعات', 'دفعة'])) return 'invoices';
    if (_containsAny(value, <String>['إضافة صيانة', 'اضافة صيانة', 'طلب صيانة جديد'])) return 'maintenance_new';
    if (_containsAny(value, <String>['الصيانة', 'الصيانه', 'الخدمات'])) return 'maintenance';
    if (_containsAny(value, <String>['التقارير', 'تقرير'])) return 'reports';
    if (_containsAny(value, <String>['الإشعارات', 'اشعارات', 'التنبيهات'])) return 'notifications';
    return null;
  }

  Future<bool> _handleLocalUtilityFlow({
    required String rawText,
    required String visibleUserText,
  }) async {
    final intent = _detectLocalUtilityIntent(rawText);
    if (intent == null || _executor == null) return false;

    _service?.addLocalUserMessage(visibleUserText);
    if (!mounted) return true;
    setState(() {
      _messages.add(_UiMessage(role: 'user', text: visibleUserText));
      _sending = true;
      _streamingAssistantIndex = null;
    });
    _scrollToBottom();

    try {
      final result = await _executor!.executeCached(intent.toolName, intent.args);
      final handledResult = await _handleExecutorSideEffects(result);
      final responseText = _formatLocalToolResponse(intent, handledResult);
      _service?.addLocalAssistantMessage(responseText);
      if (!mounted) return true;
      setState(() {
        _messages.add(_UiMessage(role: 'assistant', text: responseText));
        _sending = false;
      });
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return true;
      setState(() {
        _messages.add(
          const _UiMessage(
            role: 'assistant',
            text: 'تعذر تنفيذ الأمر محليًا الآن. جرّب فتح الشاشة المناسبة أو أعد صياغة الطلب.',
          ),
        );
        _sending = false;
      });
      _scrollToBottom();
    }
    return true;
  }

  String _formatLocalToolResponse(_LocalToolIntent intent, String rawResult) {
    final payload = _decodeExecutorPayload(rawResult);
    if (payload == null) {
      try {
        final decoded = jsonDecode(rawResult);
        return _normalizeAssistantText(
          '${intent.title}\n${_formatLocalPayloadValue(decoded)}',
        );
      } catch (_) {
        return _normalizeAssistantText(rawResult);
      }
    }

    final message = (payload['message'] ?? '').toString().trim();
    final error = (payload['error'] ?? '').toString().trim();
    if (error.isNotEmpty) return _normalizeAssistantText(error);
    if (intent.isNavigation && message.isNotEmpty) {
      return _normalizeAssistantText(message);
    }

    final sanitized = _sanitizeToolPayloadValue(payload);
    final formatted = _formatLocalPayloadValue(sanitized);
    if (message.isNotEmpty && formatted.trim().isEmpty) {
      return _normalizeAssistantText(message);
    }
    if (message.isNotEmpty && !formatted.contains(message)) {
      return _normalizeAssistantText('$message\n\n$formatted');
    }
    return _normalizeAssistantText('${intent.title}\n$formatted');
  }

  String _formatLocalPayloadValue(dynamic value, {int depth = 0}) {
    if (value == null) return '';
    if (value is String) return value.trim();
    if (value is num || value is bool) return value.toString();
    if (value is Iterable) {
      final items = value
          .map((item) => _formatLocalPayloadItem(item, depth: depth + 1))
          .where((line) => line.trim().isNotEmpty)
          .take(10)
          .toList(growable: false);
      if (items.isEmpty) return 'لا توجد بيانات مطابقة.';
      final suffix = value.length > 10 ? '\nويوجد المزيد. افتح الشاشة لمراجعة كل النتائج.' : '';
      return '${items.map((line) => '- $line').join('\n')}$suffix';
    }
    if (value is Map<String, dynamic>) {
      final lines = <String>[];
      final cards = value['cards'];
      if (cards is Iterable) {
        final cardLines = cards
            .map((card) => _formatLocalPayloadItem(card, depth: depth + 1))
            .where((line) => line.trim().isNotEmpty)
            .toList(growable: false);
        if (cardLines.isNotEmpty) lines.addAll(cardLines.map((line) => '- $line'));
      }

      final preferredKeys = <String>[
        'title',
        'name',
        'clientName',
        'fullName',
        'serialNo',
        'tenant',
        'tenantName',
        'property',
        'propertyName',
        'email',
        'phone',
        'status',
        'summary',
        'semanticSummary',
        'total',
        'count',
        'occupied',
        'vacant',
        'topLevelProperties',
        'occupiedTopLevelProperties',
        'vacantTopLevelProperties',
        'buildings',
        'standaloneProperties',
        'registeredBuildingUnits',
        'configuredBuildingUnits',
        'occupiedBuildingUnits',
        'vacantBuildingUnits',
        'propertyTypeBreakdown',
        'totalReceivables',
        'overduePayments',
        'revenues',
        'expenses',
        'net',
        'balance',
        'currentBalance',
        'previousBalance',
        'readyForPayout',
        'commissionRevenue',
        'officeExpenses',
        'officeWithdrawals',
        'netProfit',
        'rentCollected',
        'officeCommissions',
        'ownerExpenses',
        'ownerAdjustments',
        'previousTransfers',
        'remaining',
        'paidAmount',
        'amount',
        'totalContracts',
        'activeContracts',
        'endedContracts',
        'terminatedContracts',
        'expiringContracts',
        'remainingContractAmount',
        'totalInstallments',
        'paidInstallments',
        'unpaidInstallments',
        'canceledInstallments',
        'overdueInstallments',
        'upcomingInstallments',
        'remainingTotal',
        'invoiceHistorySummary',
        'installmentsSummary',
        'workspaceDataMessage',
        'workspaceSummary',
        'clientSummary',
        'userSummary',
        'notifications',
        'portfolioSummary',
      ];
      for (final key in preferredKeys) {
        if (!value.containsKey(key)) continue;
        final formatted = _formatLocalPayloadValue(value[key], depth: depth + 1);
        if (formatted.trim().isEmpty) continue;
        lines.add('${_localPayloadLabel(key)}: $formatted');
      }

      final listKeys = <String>[
        'items',
        'rows',
        'contracts',
        'properties',
        'clients',
        'owners',
        'invoices',
        'services',
        'notifications',
        'ledger',
        'propertyBreakdowns',
        'bankAccounts',
        'accounts',
        'buildingsPreview',
        'propertiesPreview',
        'contractsPreview',
        'invoiceHistoryPreview',
        'clientPortfolioPreview',
        'latestClientsPreview',
        'latestUsersPreview',
      ];
      for (final key in listKeys) {
        final entry = value[key];
        if (entry is Iterable && entry.isNotEmpty) {
          lines.add('${_localPayloadLabel(key)}:');
          lines.add(_formatLocalPayloadValue(entry, depth: depth + 1));
          break;
        }
      }

      if (lines.isEmpty) {
        value.forEach((key, entryValue) {
          if (_shouldHideToolPayloadKey(key)) return;
          final formatted = _formatLocalPayloadValue(entryValue, depth: depth + 1);
          if (formatted.trim().isEmpty) return;
          lines.add('${_localPayloadLabel(key)}: $formatted');
        });
      }
      return lines.take(16).join('\n');
    }
    if (value is Map) {
      return _formatLocalPayloadValue(value.cast<String, dynamic>(), depth: depth);
    }
    return value.toString();
  }

  String _formatLocalPayloadItem(dynamic item, {int depth = 0}) {
    if (item is Map<String, dynamic>) {
      final parts = <String>[];
      for (final key in <String>[
        'title',
        'name',
        'clientName',
        'fullName',
        'tenantName',
        'propertyName',
        'ownerName',
        'typeLabel',
        'structureLabel',
        'managementModeLabel',
        'voucherSerialNo',
        'serialNo',
        'contractNo',
        'date',
        'description',
        'status',
        'stateLabel',
        'voucherStateLabel',
        'operationLabel',
        'sourceLabel',
        'directionLabel',
        'formattedValue',
        'amount',
        'credit',
        'debit',
        'remaining',
        'balanceAfter',
        'dueDate',
        'configuredUnits',
        'registeredUnits',
        'occupiedUnits',
        'vacantUnits',
        'totalContracts',
        'activeContracts',
        'remainingContractAmount',
        'totalInstallments',
        'paidInstallments',
        'unpaidInstallments',
        'overdueInstallments',
        'semanticSummary',
        'paymentMethod',
        'note',
      ]) {
        final value = item[key];
        if (value == null) continue;
        final formatted = _formatLocalPayloadValue(value, depth: depth + 1).trim();
        if (formatted.isEmpty) continue;
        if (key == 'title' || key == 'name' || key == 'clientName' || key == 'fullName') {
          parts.insert(0, formatted);
        } else {
          parts.add('${_localPayloadLabel(key)}: $formatted');
        }
      }
      if (parts.isNotEmpty) return parts.join(' - ');
      return _formatLocalPayloadValue(item, depth: depth + 1);
    }
    if (item is Map) {
      return _formatLocalPayloadItem(item.cast<String, dynamic>(), depth: depth);
    }
    return _formatLocalPayloadValue(item, depth: depth + 1);
  }

  String _localPayloadLabel(String key) {
    const labels = <String, String>{
      'title': 'العنوان',
      'name': 'الاسم',
      'summary': 'الملخص',
      'total': 'الإجمالي',
      'count': 'العدد',
      'occupied': 'المشغول',
      'vacant': 'المتاح',
      'totalReceivables': 'إجمالي المستحقات',
      'overduePayments': 'الدفعات المتأخرة',
      'revenues': 'الإيرادات',
      'expenses': 'المصروفات',
      'net': 'الصافي',
      'balance': 'الرصيد',
      'remaining': 'المتبقي',
      'paidAmount': 'المدفوع',
      'amount': 'المبلغ',
      'items': 'العناصر',
      'rows': 'العناصر',
      'contracts': 'العقود',
      'properties': 'العقارات',
      'clients': 'العملاء',
      'owners': 'الملاك',
      'invoices': 'السندات',
      'services': 'الخدمات',
      'notifications': 'الإشعارات',
      'appliedFilters': 'الفلاتر المطبقة',
      'commissionRule': 'قاعدة عمولة المكتب',
      'owner': 'المالك',
      'preview': 'المعاينة',
      'ledger': 'الدفتر',
      'propertyBreakdowns': 'تفصيل العقارات',
      'bankAccounts': 'الحسابات البنكية',
      'accounts': 'الحسابات البنكية',
      'topOwnerByPayout': 'أعلى مالك جاهز للتحويل',
      'rentCollected': 'الإيجارات المحصلة',
      'officeCommissions': 'عمولات المكتب',
      'ownerExpenses': 'المصروفات المحملة على المالك',
      'ownerAdjustments': 'خصومات/تسويات المالك',
      'previousTransfers': 'التحويلات السابقة',
      'currentBalance': 'الرصيد الحالي',
      'readyForPayout': 'الجاهز للتحويل',
      'commissionRevenue': 'إيرادات عمولة المكتب',
      'officeExpenses': 'مصروفات المكتب',
      'officeWithdrawals': 'تحويلات المكتب',
      'netProfit': 'صافي ربح المكتب',
      'receiptVouchers': 'سندات القبض',
      'paymentVouchers': 'سندات الصرف',
      'receipts': 'سندات القبض',
      'payments': 'سندات الصرف',
      'receiptAmount': 'إجمالي القبض',
      'paymentAmount': 'إجمالي الصرف',
      'serialNo': 'الرقم',
      'voucherSerialNo': 'رقم السند',
      'contractNo': 'رقم العقد',
      'date': 'التاريخ',
      'voucherDate': 'تاريخ السند',
      'status': 'الحالة',
      'stateLabel': 'حالة السند',
      'voucherStateLabel': 'حالة القيد',
      'operationLabel': 'نوع الحركة',
      'sourceLabel': 'مصدر الحركة',
      'directionLabel': 'اتجاه السند',
      'formattedValue': 'القيمة',
      'paymentMethod': 'طريقة الدفع',
      'note': 'الملاحظة',
      'modeLabel': 'نوع العمولة',
      'categoryLabel': 'نوع التسوية',
      'credit': 'دائن',
      'debit': 'مدين',
      'balanceAfter': 'الرصيد بعد الحركة',
      'linkedProperties': 'العقارات المرتبطة',
      'previousBalance': 'الرصيد السابق',
      'dueDate': 'تاريخ الاستحقاق',
      'tenant': 'المستأجر',
      'tenantName': 'المستأجر',
      'property': 'العقار',
      'propertyName': 'العقار',
      'ownerName': 'المالك',
      'typeLabel': 'نوع العقار',
      'structureLabel': 'التصنيف',
      'managementModeLabel': 'نمط إدارة العمارة',
      'configuredUnits': 'الوحدات المهيأة',
      'registeredUnits': 'الوحدات المضافة',
      'occupiedUnits': 'الوحدات المشغولة',
      'vacantUnits': 'الوحدات المتاحة',
      'childUnitsCount': 'عدد الوحدات المضافة',
      'semanticGuidance': 'توضيح المعنى',
      'semanticSummary': 'الملخص التفسيري',
      'propertyTypeBreakdown': 'تفصيل أنواع العقارات',
      'buildingsPreview': 'معاينة العمائر',
      'topLevelProperties': 'العقارات الرئيسية',
      'occupiedTopLevelProperties': 'العقارات الرئيسية المشغولة',
      'vacantTopLevelProperties': 'العقارات الرئيسية المتاحة',
      'buildings': 'العمائر',
      'standaloneProperties': 'العقارات المستقلة',
      'registeredBuildingUnits': 'الوحدات المضافة',
      'configuredBuildingUnits': 'الوحدات المهيأة',
      'occupiedBuildingUnits': 'الوحدات المشغولة',
      'vacantBuildingUnits': 'الوحدات المتاحة',
      'totalContracts': 'إجمالي العقود',
      'activeContracts': 'العقود النشطة',
      'endedContracts': 'العقود المنتهية',
      'terminatedContracts': 'العقود المنهية',
      'expiringContracts': 'العقود القريبة من الانتهاء',
      'remainingContractAmount': 'المتبقي في العقود',
      'totalInstallments': 'إجمالي الدفعات',
      'paidInstallments': 'الدفعات المسددة',
      'unpaidInstallments': 'الدفعات غير المسددة',
      'canceledInstallments': 'الدفعات الملغاة',
      'overdueInstallments': 'الدفعات المتأخرة',
      'upcomingInstallments': 'الدفعات القادمة',
      'remainingTotal': 'إجمالي المتبقي',
      'invoiceHistorySummary': 'ملخص الدفعات',
      'invoiceHistoryPreview': 'معاينة الدفعات',
      'installmentsSummary': 'ملخص الدفعات',
      'clientSummary': 'ملخص العملاء',
      'userSummary': 'ملخص مستخدمي المكتب',
      'portfolioSummary': 'ملخص المحفظة',
      'totalClients': 'إجمالي العملاء',
      'activeClients': 'العملاء النشطون',
      'blockedClients': 'العملاء الموقوفون',
      'withSubscription': 'العملاء ذوو الاشتراك',
      'pendingSyncClients': 'العملاء المعلّقون للمزامنة',
      'totalUsers': 'إجمالي المستخدمين',
      'activeUsers': 'المستخدمون النشطون',
      'blockedUsers': 'المستخدمون الموقوفون',
      'fullPermissionUsers': 'مستخدمو الصلاحية الكاملة',
      'viewPermissionUsers': 'مستخدمو صلاحية المشاهدة',
      'clientsWithWorkspaceData': 'العملاء الذين تتوفر لهم بيانات تشغيلية',
      'clientsWithoutWorkspaceData': 'العملاء الذين لا تتوفر لهم بيانات تشغيلية',
      'workspaceSummary': 'ملخص مساحة العمل',
      'workspaceDataAvailable': 'توفر البيانات التشغيلية',
      'workspaceDataMessage': 'حالة البيانات التشغيلية',
      'propertiesPreview': 'معاينة العقارات',
      'contractsPreview': 'معاينة العقود',
      'clientPortfolioPreview': 'معاينة محافظ العملاء',
      'latestClientsPreview': 'أحدث العملاء',
      'latestUsersPreview': 'أحدث مستخدمي المكتب',
      'quickActions': 'إجراءات سريعة',
      'badgeCount': 'عدد التنبيهات',
      'officeSubscriptionAlerts': 'تنبيهات اشتراك المكتب',
      'clientSubscriptionAlerts': 'تنبيهات اشتراكات العملاء',
      'alerts': 'التنبيهات',
    };
    return labels[key] ?? _toolArgLabels[key] ?? key;
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    final attachmentOnlyMessage =
        text.isEmpty && _pendingChatAttachments.isNotEmpty;
    if ((!attachmentOnlyMessage && text.isEmpty) ||
        _sending ||
        _service == null ||
        _executor == null) {
      return;
    }
    final outboundText = attachmentOnlyMessage ? 'هذه هي المرفقات المطلوبة.' : text;
    final visibleUserText = attachmentOnlyMessage
        ? 'أرفقت ${_pendingChatAttachments.length} مرفق/مرفقات.'
        : text;

    final historyRestoreFuture = _historyRestoreFuture;
    if (historyRestoreFuture != null) {
      await historyRestoreFuture;
      if (!mounted || _sending || _service == null || _executor == null) {
        return;
      }
    }

    if (await _handleLocalCollectionFlow(
      rawText: text,
      visibleUserText: visibleUserText,
    )) {
      _controller.clear();
      return;
    }

    if (!attachmentOnlyMessage) {
      final handledLocally = await _handleLocalUtilityFlow(
        rawText: text,
        visibleUserText: visibleUserText,
      );
      if (handledLocally) {
        _controller.clear();
        return;
      }
    }

    _controller.clear();
    setState(() {
      _messages.add(_UiMessage(role: 'user', text: visibleUserText));
      _sending = true;
      _streamingAssistantIndex = null;
    });
    _scrollToBottom();

    try {
      final requestContext = _buildChatAttachmentContext();
      var response = await _service!.sendMessage(
        outboundText,
        requestContext: requestContext,
        onPartialText: _updateStreamingAssistantText,
      );

      // حلقة tool calls مع حد أقصى حتى لا يدخل الشات في دورة لا نهائية.
      var toolStepCount = 0;
      while (response == '__TOOL_CALLS__' &&
          toolStepCount < AiOpenAiConfig.maxToolSteps) {
        toolStepCount++;
        if (mounted) {
          setState(() {
            _clearStreamingAssistantDraft();
          });
        }

        final calls = _service!.getPendingToolCalls();
        if (calls == null || calls.isEmpty) break;

        final writeCalls = calls.where((call) {
          final fn = (call['function'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          final name = (fn['name'] ?? '').toString();
          return AiChatTools.isWriteTool(name);
        }).toList(growable: false);

        final confirmed =
            writeCalls.isEmpty ? true : await _confirmWriteToolCalls(writeCalls);

        for (final call in calls) {
          final fn = (call['function'] as Map).cast<String, dynamic>();
          final name = (fn['name'] ?? '').toString();
          final args = _toolArguments(call);
          final id = (call['id'] ?? '').toString();
          final isWrite = AiChatTools.isWriteTool(name);
          final usedPendingAttachments = _toolWillUsePendingAttachments(name, args);
          final mergedArgs = _mergePendingChatAttachmentsIntoArgs(name, args);

          final result = isWrite
              ? (confirmed
                  ? await _executor!.executeCached(name, mergedArgs)
                  : _toolCancelledResult(name))
              : await _executor!.executeCached(name, mergedArgs);

          final handledResult = await _handleExecutorSideEffects(result);
          _service!.addToolResult(id, _sanitizeToolResultForModel(handledResult));

          if (usedPendingAttachments && _toolResultSucceeded(handledResult) && mounted) {
            setState(() {
              _pendingChatAttachments.clear();
            });
          }
        }

        response = await _service!.continueAfterToolCalls(
          onPartialText: _updateStreamingAssistantText,
        );
      }

      if (response == '__TOOL_CALLS__') {
        response = 'نفذت الخطوات الممكنة، لكن الطلب يحتاج خطوة إضافية. أعد صياغة المطلوب أو افتح الشاشة المناسبة لإكمال العملية.';
      }

      if (mounted) {
        setState(() {
          if (_streamingAssistantIndex != null &&
              _streamingAssistantIndex! < _messages.length) {
            _messages[_streamingAssistantIndex!] =
                _UiMessage(
                  role: 'assistant',
                  text: _normalizeAssistantText(response),
                );
          } else {
            _messages.add(
              _UiMessage(
                role: 'assistant',
                text: _normalizeAssistantText(response),
              ),
            );
          }
          _streamingAssistantIndex = null;
          _sending = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          const errorMessage = 'حدث خطأ في الاتصال. حاول مرة أخرى.';
          if (_streamingAssistantIndex != null &&
              _streamingAssistantIndex! < _messages.length) {
            _messages[_streamingAssistantIndex!] =
                _UiMessage(role: 'assistant', text: errorMessage);
          } else {
            _messages.add(_UiMessage(
              role: 'assistant',
              text: errorMessage,
            ));
          }
          _streamingAssistantIndex = null;
          _sending = false;
        });
        _scrollToBottom();
      }
    }
  }

  Future<void> _confirmDeleteConversation() async {
    if (_service == null || _sending) return;

    final confirmed = await CustomConfirmDialog.show(
      context: context,
      title: 'حذف المحادثة',
      message: 'هل تريد حذف المحادثة؟ لن يمكنك التراجع بعد الحذف.',
      confirmLabel: 'حذف',
      cancelLabel: 'إلغاء',
      confirmColor: const Color(0xFFDC2626),
    );
    if (!confirmed || !mounted) return;

    await _service!.deleteConversation();
    if (!mounted) return;

    _controller.clear();
    _focusNode.unfocus();
    setState(() {
      _messages.clear();
      _pendingChatAttachments.clear();
      _collectionSession = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: _buildAppBar(),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _buildScopeBanner(),
                  Expanded(child: _buildMessagesList()),
                  _buildInputBar(),
                ],
              ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: const Color(0xFF0F766E),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.smart_toy_rounded,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'مساعد دارفو',
                style: GoogleFonts.cairo(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              Text(
                'متصل',
                style: GoogleFonts.cairo(
                  fontSize: 11,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded, color: Colors.white70),
          tooltip: 'مسح المحادثة',
          onPressed: _sending ? null : _confirmDeleteConversation, /*
            _service?.clearHistory();
            setState(() {
              _messages.clear();
              _addAssistantMessage(
                  'تم مسح المحادثة. كيف أقدر أساعدك؟');
            });
          */
        ),
      ],
    );
  }

  Widget _buildScopeBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFFE8EEF9),
      child: Row(
        children: [
          const Icon(
            Icons.account_tree_outlined,
            size: 18,
            color: Color(0xFF0F766E),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_effectiveScope.contextTitle} - ${_effectiveScope.contextSubtitle}',
              style: GoogleFonts.cairo(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1E3A8A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smart_toy_rounded,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'اسأل أي شيء عن عقاراتك',
              style: GoogleFonts.cairo(
                  fontSize: 16, color: Colors.grey.shade400),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      itemCount: _messages.length + (_showTypingIndicator ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == _messages.length) return _buildTypingIndicator();
        return _buildBubble(_messages[i]);
      },
    );
  }

  Widget _buildBubble(_UiMessage msg) {
    final isUser = msg.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF0F766E) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          msg.text,
          style: GoogleFonts.cairo(
            fontSize: 14,
            height: 1.5,
            color: isUser ? Colors.white : const Color(0xFF1F2937),
          ),
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dot(0),
            const SizedBox(width: 4),
            _dot(1),
            const SizedBox(width: 4),
            _dot(2),
          ],
        ),
      ),
    );
  }

  Widget _dot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 600 + index * 200),
      builder: (_, v, child) {
        return Opacity(
          opacity: (0.3 + 0.7 * ((v + index * 0.3) % 1.0)),
          child: child,
        );
      },
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Color(0xFF0F766E),
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  Widget _buildPendingAttachmentsBar() {
    if (_pendingChatAttachments.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _pendingChatAttachments.map((attachment) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFE0ECFF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.attach_file_rounded,
                    size: 16,
                    color: Color(0xFF0F766E),
                  ),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 170),
                    child: Text(
                      attachment.name,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1E3A8A),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => _removeChatAttachment(attachment.path),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: Color(0xFF1E3A8A),
                    ),
                  ),
                ],
              ),
            );
          }).toList(growable: false),
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPendingAttachmentsBar(),
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    textDirection: TextDirection.rtl,
                    maxLines: 4,
                    minLines: 1,
                    style: GoogleFonts.cairo(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'اكتب رسالتك...',
                      hintStyle:
                          GoogleFonts.cairo(fontSize: 14, color: Colors.grey),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: (_sending ||
                        _uploadingChatAttachments ||
                        _pendingChatAttachments.length >= 3)
                    ? null
                    : _pickChatAttachments,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: _uploadingChatAttachments
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          Icons.attach_file_rounded,
                          color: _pendingChatAttachments.length >= 3
                              ? Colors.grey
                              : const Color(0xFF1F2937),
                          size: 20,
                        ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _send,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0F766E), Color(0xFF22D3EE)],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F766E).withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.send_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UiMessage {
  final String role;
  final String text;
  const _UiMessage({required this.role, required this.text});
}

class _ChatAttachment {
  final String path;
  final String name;
  const _ChatAttachment({required this.path, required this.name});
}

class _ChatCollectionSession {
  final String operation;
  final String entityLabel;
  final String screenTool;
  final bool awaitingEntryChoice;
  final Map<String, dynamic> values;
  final Set<String> skippedFields;
  final String? lastPromptedField;

  const _ChatCollectionSession({
    required this.operation,
    required this.entityLabel,
    required this.screenTool,
    required this.awaitingEntryChoice,
    required this.values,
    required this.skippedFields,
    required this.lastPromptedField,
  });

  _ChatCollectionSession copyWith({
    String? operation,
    String? entityLabel,
    String? screenTool,
    bool? awaitingEntryChoice,
    Map<String, dynamic>? values,
    Set<String>? skippedFields,
    String? lastPromptedField,
  }) {
    return _ChatCollectionSession(
      operation: operation ?? this.operation,
      entityLabel: entityLabel ?? this.entityLabel,
      screenTool: screenTool ?? this.screenTool,
      awaitingEntryChoice: awaitingEntryChoice ?? this.awaitingEntryChoice,
      values: values ?? this.values,
      skippedFields: skippedFields ?? this.skippedFields,
      lastPromptedField: lastPromptedField ?? this.lastPromptedField,
    );
  }
}

class _ChatFieldDescriptor {
  final String field;
  final String label;
  final String prompt;
  final String inputType;
  final bool required;

  const _ChatFieldDescriptor({
    required this.field,
    required this.label,
    required this.prompt,
    required this.inputType,
    required this.required,
  });
}

class _CollectionAnswerResult {
  final _ChatCollectionSession? session;
  final String? errorMessage;

  const _CollectionAnswerResult.valid(this.session) : errorMessage = null;
  const _CollectionAnswerResult.invalid(this.errorMessage) : session = null;

  bool get isValid => session != null && errorMessage == null;
}

class _FieldParseResult {
  final dynamic value;
  final String? errorMessage;

  const _FieldParseResult.valid(this.value) : errorMessage = null;
  const _FieldParseResult.invalid(this.errorMessage) : value = null;

  bool get isValid => errorMessage == null;
}

class _LocalToolIntent {
  final String toolName;
  final Map<String, dynamic> args;
  final String title;
  final bool isNavigation;

  const _LocalToolIntent({
    required this.toolName,
    required this.args,
    required this.title,
    this.isNavigation = false,
  });
}
