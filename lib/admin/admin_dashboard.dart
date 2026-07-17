import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/firebase_bootstrap.dart';
import '../core/firebase_repository.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

class AdminDashboardApp extends StatelessWidget {
  const AdminDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'لوحة عقود برو',
      locale: const Locale('ar'),
      supportedLocales: const <Locale>[Locale('ar'), Locale('en')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const AdminGate(),
    );
  }
}

class AdminGate extends StatefulWidget {
  const AdminGate({super.key});

  @override
  State<AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends State<AdminGate> {
  User? _user;
  bool _loading = true;
  String? _authError;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(Duration.zero, _loadCurrentUser);
  }

  Future<void> _loadCurrentUser() async {
    try {
      await FirebaseBootstrap.ready;
      if (!FirebaseBootstrap.initialized) {
        if (!mounted) return;
        setState(() {
          _authError = FirebaseBootstrap.error?.toString() ??
              'Firebase لم يكتمل تهيئته في هذه الجلسة.';
          _loading = false;
        });
        return;
      }
      final user = FirebaseAuth.instance.currentUser;
      if (!mounted) return;
      setState(() {
        _user = user;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _authError = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const _AdminLoading();
    }
    if (_authError != null) {
      return _AdminAuthError(message: _authError!);
    }
    final user = _user;
    if (user == null) {
      return _AdminLoginScreen(
        onSignedIn: (user) => setState(() => _user = user),
      );
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('adminUsers')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _AdminLoading();
        }
        final data = snapshot.data?.data();
        final active = data?['active'] == true;
        if (!active) {
          return _AdminNoPermission(uid: user.uid);
        }
        return AdminDashboard(user: user, adminData: data ?? {});
      },
    );
  }
}

class AdminDashboard extends StatefulWidget {
  final User user;
  final Map<String, dynamic> adminData;

  const AdminDashboard({
    super.key,
    required this.user,
    required this.adminData,
  });

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final FirebaseRepository _repository = FirebaseRepository();
  int _index = 0;
  String _contractQuery = '';
  String _contractStatus = 'all';
  String _userQuery = '';
  ContractRecord? _selectedContract;

  static const List<_AdminDestination> _destinations = <_AdminDestination>[
    _AdminDestination('نظرة عامة', Icons.space_dashboard_outlined),
    _AdminDestination('الطلبات', Icons.fact_check_outlined),
    _AdminDestination('المستخدمون', Icons.people_outline_rounded),
    _AdminDestination('المحتوى', Icons.tune_rounded),
    _AdminDestination('التقارير', Icons.bar_chart_rounded),
    _AdminDestination('الإعدادات', Icons.admin_panel_settings_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('contracts')
          .orderBy('updatedAt', descending: true)
          .limit(300)
          .snapshots(),
      builder: (context, contractsSnapshot) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .orderBy('createdAt', descending: true)
              .limit(300)
              .snapshots(),
          builder: (context, usersSnapshot) {
            final contracts = contractsSnapshot.data?.docs
                    .map(_repository.contractFromDoc)
                    .toList() ??
                <ContractRecord>[];
            final users = usersSnapshot.data?.docs ?? const [];
            final loading =
                contractsSnapshot.connectionState == ConnectionState.waiting ||
                    usersSnapshot.connectionState == ConnectionState.waiting;

            return LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 980;
                return Scaffold(
                  backgroundColor: context.ejarzTheme.background,
                  appBar: wide
                      ? null
                      : AppBar(
                          title: const Text('لوحة عقود برو'),
                          actions: <Widget>[
                            IconButton(
                              onPressed: () => FirebaseAuth.instance.signOut(),
                              icon: const Icon(Icons.logout_rounded),
                            ),
                          ],
                        ),
                  bottomNavigationBar: wide
                      ? null
                      : NavigationBar(
                          height: 58,
                          selectedIndex: _index,
                          onDestinationSelected: (value) =>
                              setState(() => _index = value),
                          destinations: <NavigationDestination>[
                            for (final item in _destinations.take(4))
                              NavigationDestination(
                                icon: Icon(item.icon),
                                label: item.label,
                              ),
                          ],
                        ),
                  body: Row(
                    children: <Widget>[
                      if (wide)
                        _AdminSidebar(
                          selectedIndex: _index,
                          destinations: _destinations,
                          onSelected: (value) => setState(() => _index = value),
                          onLogout: () => FirebaseAuth.instance.signOut(),
                          adminName: _cleanAdminName(
                            widget.adminData['name'] as String?,
                          ),
                        ),
                      Expanded(
                        child: SafeArea(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              wide ? 18 : 12,
                              wide ? 14 : 10,
                              wide ? 18 : 12,
                              wide ? 14 : 74,
                            ),
                            child: loading
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : _buildSection(contracts, users, wide),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildSection(
    List<ContractRecord> contracts,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
    bool wide,
  ) {
    return switch (_index) {
      0 => _OverviewSection(contracts: contracts, users: users),
      1 => _ContractsSection(
          contracts: contracts,
          query: _contractQuery,
          statusFilter: _contractStatus,
          selected: _selectedContract,
          wide: wide,
          onQueryChanged: (value) => setState(() => _contractQuery = value),
          onStatusChanged: (value) =>
              setState(() => _contractStatus = value ?? 'all'),
          onSelected: (contract) =>
              setState(() => _selectedContract = contract),
          onChangeStatus: _changeContractStatus,
          onAddMissing: _addMissingRequirement,
          onUploadPdf: _uploadFinalPdf,
        ),
      2 => _UsersSection(
          users: users,
          query: _userQuery,
          onQueryChanged: (value) => setState(() => _userQuery = value),
          onToggleBlock: _toggleUserBlock,
        ),
      3 => const _ContentSection(),
      4 => _ReportsSection(contracts: contracts, users: users),
      _ => _SettingsSection(adminUid: widget.user.uid),
    };
  }

  Future<void> _changeContractStatus(
    ContractRecord contract,
    ContractStatus status,
  ) async {
    final note = await _askText(
      title: 'ملاحظة تظهر للعميل',
      label: 'اكتب ملاحظة مختصرة أو اتركها فارغة',
      multiline: true,
    );
    if (note == null || !mounted) return;
    await _repository.updateContractStatus(
      contractId: contract.id,
      status: status,
      adminUid: widget.user.uid,
      customerNote: note,
    );
    if (mounted) showAppSnackBar(context, 'تم تحديث حالة الطلب');
  }

  Future<void> _addMissingRequirement(ContractRecord contract) async {
    final title =
        await _askText(title: 'عنوان النقص', label: 'مثال: صورة الصك');
    if (title == null || title.trim().isEmpty) return;
    final description = await _askText(
      title: 'وصف النقص للعميل',
      label: 'اكتب المطلوب من العميل بوضوح',
      multiline: true,
    );
    if (description == null || description.trim().isEmpty) return;
    await _repository.addMissingRequirement(
      contractId: contract.id,
      uid: contract.uid,
      title: title.trim(),
      description: description.trim(),
      type: 'field',
      fieldPath: '',
      adminUid: widget.user.uid,
    );
    if (mounted) showAppSnackBar(context, 'تم إرسال النقص للعميل');
  }

  Future<void> _uploadFinalPdf(ContractRecord contract) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['pdf'],
      withData: true,
    );
    final file = result?.files.single;
    final Uint8List? bytes = file?.bytes;
    if (file == null || bytes == null) return;
    await _repository.attachFinalPdf(
      contractId: contract.id,
      uid: contract.uid,
      fileName: file.name,
      bytes: bytes,
      adminUid: widget.user.uid,
    );
    if (mounted) showAppSnackBar(context, 'تم رفع العقد النهائي وإشعار العميل');
  }

  Future<void> _toggleUserBlock(
    QueryDocumentSnapshot<Map<String, dynamic>> userDoc,
  ) async {
    final data = userDoc.data();
    final blocked = data['status'] == 'blocked';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(blocked ? 'فك حظر المستخدم؟' : 'حظر المستخدم؟'),
        content: Text(
          blocked
              ? 'سيتمكن المستخدم من الدخول للتطبيق مرة أخرى.'
              : 'سيتم منع المستخدم من استخدام التطبيق حتى فك الحظر.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(blocked ? 'فك الحظر' : 'حظر'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await FirebaseFirestore.instance.collection('users').doc(userDoc.id).set(
      <String, Object?>{
        'status': blocked ? 'active' : 'blocked',
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await FirebaseFirestore.instance.collection('auditLogs').add(
      <String, Object?>{
        'adminUid': widget.user.uid,
        'action': blocked ? 'unblockUser' : 'blockUser',
        'targetType': 'user',
        'targetId': userDoc.id,
        'createdAt': FieldValue.serverTimestamp(),
      },
    );
  }

  Future<String?> _askText({
    required String title,
    required String label,
    bool multiline = false,
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          minLines: multiline ? 3 : 1,
          maxLines: multiline ? 5 : 1,
          decoration: InputDecoration(labelText: label),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}

class _OverviewSection extends StatelessWidget {
  final List<ContractRecord> contracts;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> users;

  const _OverviewSection({required this.contracts, required this.users});

  @override
  Widget build(BuildContext context) {
    final completed = contracts
        .where((item) => item.status == ContractStatus.authenticated)
        .length;
    final missing = contracts
        .where((item) => item.status == ContractStatus.missingData)
        .length;
    final processing = contracts
        .where((item) => item.status == ContractStatus.processing)
        .length;
    final revenue = contracts.fold<double>(
      0,
      (total, item) => total + item.totalFees,
    );
    return _AdminSectionShell(
      title: 'مركز قيادة عقود برو',
      subtitle: 'رؤية فورية لحركة المستخدمين والعقود والتشغيل.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 900
              ? 4
              : constraints.maxWidth >= 560
                  ? 2
                  : 1;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _AdminMetric(
                width: _tileWidth(constraints.maxWidth, columns),
                label: 'إجمالي المستخدمين',
                value: '${users.length}',
                icon: Icons.people_outline_rounded,
                color: AppColors.primary,
              ),
              _AdminMetric(
                width: _tileWidth(constraints.maxWidth, columns),
                label: 'قيد المعالجة',
                value: '$processing',
                icon: Icons.miscellaneous_services_outlined,
                color: AppColors.blue,
              ),
              _AdminMetric(
                width: _tileWidth(constraints.maxWidth, columns),
                label: 'نواقص مطلوبة',
                value: '$missing',
                icon: Icons.error_outline_rounded,
                color: AppColors.red,
              ),
              _AdminMetric(
                width: _tileWidth(constraints.maxWidth, columns),
                label: 'مكتملة',
                value: '$completed',
                icon: Icons.verified_outlined,
                color: AppColors.success,
              ),
              _AdminMetric(
                width: _tileWidth(constraints.maxWidth, columns),
                label: 'إجمالي الرسوم',
                value: '${revenue.toStringAsFixed(0)} ر.س',
                icon: Icons.payments_outlined,
                color: AppColors.orange,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ContractsSection extends StatelessWidget {
  final List<ContractRecord> contracts;
  final String query;
  final String statusFilter;
  final ContractRecord? selected;
  final bool wide;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<ContractRecord> onSelected;
  final Future<void> Function(ContractRecord, ContractStatus) onChangeStatus;
  final Future<void> Function(ContractRecord) onAddMissing;
  final Future<void> Function(ContractRecord) onUploadPdf;

  const _ContractsSection({
    required this.contracts,
    required this.query,
    required this.statusFilter,
    required this.selected,
    required this.wide,
    required this.onQueryChanged,
    required this.onStatusChanged,
    required this.onSelected,
    required this.onChangeStatus,
    required this.onAddMissing,
    required this.onUploadPdf,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = query.trim().toLowerCase();
    final filtered = contracts.where((contract) {
      final matchesStatus =
          statusFilter == 'all' || contract.status.name == statusFilter;
      final matchesQuery = normalized.isEmpty ||
          contract.requestNumber.toLowerCase().contains(normalized) ||
          contract.title.toLowerCase().contains(normalized) ||
          contract.property.toLowerCase().contains(normalized) ||
          contract.lessorName.toLowerCase().contains(normalized) ||
          contract.tenantName.toLowerCase().contains(normalized);
      return matchesStatus && matchesQuery;
    }).toList();
    final current = selected ?? (filtered.isEmpty ? null : filtered.first);

    final list = Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                onChanged: onQueryChanged,
                decoration: const InputDecoration(
                  hintText: 'بحث برقم الطلب أو العميل أو العقار',
                  suffixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 176,
              child: DropdownButtonFormField<String>(
                initialValue: statusFilter,
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem(
                      value: 'all', child: Text('كل الحالات')),
                  for (final status in ContractStatus.values)
                    DropdownMenuItem(
                      value: status.name,
                      child: Text(status.label),
                    ),
                ],
                onChanged: onStatusChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (filtered.isEmpty)
          const EmptyState(
            icon: Icons.search_off_rounded,
            title: 'لا توجد طلبات',
            subtitle: 'غيّر البحث أو الفلتر لعرض الطلبات.',
          )
        else
          for (final contract in filtered)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _AdminContractTile(
                contract: contract,
                selected: current?.id == contract.id,
                onTap: () => onSelected(contract),
              ),
            ),
      ],
    );

    final detail = current == null
        ? const SizedBox.shrink()
        : _AdminContractDetail(
            contract: current,
            onChangeStatus: (status) => onChangeStatus(current, status),
            onAddMissing: () => onAddMissing(current),
            onUploadPdf: () => onUploadPdf(current),
          );

    return _AdminSectionShell(
      title: 'مركز عمليات العقود',
      subtitle: 'مراجعة الطلبات، النواقص، الحالات، وإصدار PDF النهائي.',
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(flex: 5, child: list),
                const SizedBox(width: 12),
                Expanded(flex: 4, child: detail),
              ],
            )
          : Column(
              children: <Widget>[
                list,
                const SizedBox(height: 10),
                detail,
              ],
            ),
    );
  }
}

class _AdminContractDetail extends StatelessWidget {
  final ContractRecord contract;
  final ValueChanged<ContractStatus> onChangeStatus;
  final VoidCallback onAddMissing;
  final VoidCallback onUploadPdf;

  const _AdminContractDetail({
    required this.contract,
    required this.onChangeStatus,
    required this.onAddMissing,
    required this.onUploadPdf,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(contract.status.icon, color: contract.status.color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  contract.requestNumber,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              StatusChip(status: contract.status, compact: true),
            ],
          ),
          const SizedBox(height: 8),
          _MiniLine('العقد', contract.title),
          _MiniLine('العقار', contract.property),
          _MiniLine('المؤجر', contract.lessorName),
          _MiniLine('المستأجر', contract.tenantName),
          if (contract.customerVisibleNote.isNotEmpty)
            _MiniLine('ملاحظة العميل', contract.customerVisibleNote),
          if (contract.finalPdfUrl.isNotEmpty)
            _MiniLine('ملف العقد', contract.finalPdfFileName),
          const SizedBox(height: 10),
          DropdownButtonFormField<ContractStatus>(
            initialValue: contract.status,
            decoration: const InputDecoration(labelText: 'تغيير الحالة'),
            items: <DropdownMenuItem<ContractStatus>>[
              for (final status in ContractStatus.values)
                DropdownMenuItem(value: status, child: Text(status.label)),
            ],
            onChanged: (value) {
              if (value != null) onChangeStatus(value);
            },
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.icon(
                onPressed: onAddMissing,
                icon: const Icon(Icons.rule_rounded),
                label: const Text('إضافة نقص'),
              ),
              OutlinedButton.icon(
                onPressed: onUploadPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('رفع PDF نهائي'),
              ),
            ],
          ),
          if (contract.missingRequirements.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              'النواقص',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            for (final item in contract.missingRequirements)
              _MiniLine(item.title, item.description),
          ],
        ],
      ),
    );
  }
}

class _UsersSection extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> users;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<QueryDocumentSnapshot<Map<String, dynamic>>> onToggleBlock;

  const _UsersSection({
    required this.users,
    required this.query,
    required this.onQueryChanged,
    required this.onToggleBlock,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = query.trim().toLowerCase();
    final filtered = users.where((doc) {
      final data = doc.data();
      return normalized.isEmpty ||
          doc.id.toLowerCase().contains(normalized) ||
          ((data['phone'] as String?) ?? '')
              .toLowerCase()
              .contains(normalized) ||
          ((data['name'] as String?) ?? '').toLowerCase().contains(normalized);
    }).toList();
    return _AdminSectionShell(
      title: 'إدارة المستخدمين',
      subtitle: 'بحث، مراجعة، حظر، ومتابعة حسابات العملاء.',
      child: Column(
        children: <Widget>[
          TextField(
            onChanged: onQueryChanged,
            decoration: const InputDecoration(
              hintText: 'ابحث باسم العميل أو الجوال أو UID',
              suffixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 10),
          if (filtered.isEmpty)
            const EmptyState(
              icon: Icons.people_outline_rounded,
              title: 'لا يوجد مستخدمون',
              subtitle: 'سيظهر المستخدمون هنا بعد تسجيل الدخول في التطبيق.',
            )
          else
            for (final user in filtered)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _AdminUserTile(user: user, onToggleBlock: onToggleBlock),
              ),
        ],
      ),
    );
  }
}

class _ContentSection extends StatefulWidget {
  const _ContentSection();

  @override
  State<_ContentSection> createState() => _ContentSectionState();
}

class _ContentSectionState extends State<_ContentSection> {
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{
    for (final field in _contentFields) field.key: TextEditingController(),
  };
  bool _loaded = false;
  bool _maintenance = false;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _loadContent(Map<String, dynamic> data) {
    for (final field in _contentFields) {
      _controllers[field.key]?.text =
          (data[field.key] as String?) ?? field.defaultValue;
    }
    _maintenance = (data['maintenanceMode'] as bool?) ?? false;
    _loaded = true;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('appContent')
          .doc('config')
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? <String, dynamic>{};
        if (!_loaded && snapshot.hasData) {
          _loadContent(data);
        }
        return _AdminSectionShell(
          title: 'مركز المحتوى والنصوص',
          subtitle:
              'تعديل نصوص الصفحة الرئيسية والخدمات والرسائل التي يقرأها التطبيق من Firestore.',
          child: AppCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: <Widget>[
                for (final field in _contentFields) ...<Widget>[
                  TextField(
                    controller: _controllers[field.key],
                    minLines: field.minLines,
                    maxLines: field.maxLines,
                    decoration: InputDecoration(labelText: field.label),
                  ),
                  const SizedBox(height: 10),
                ],
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _maintenance,
                  title: const Text('وضع الصيانة'),
                  onChanged: (value) => setState(() => _maintenance = value),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: () async {
                      final payload = <String, Object?>{
                        for (final field in _contentFields)
                          field.key: _controllers[field.key]?.text.trim() ?? '',
                        'maintenanceMode': _maintenance,
                        'updatedAt': FieldValue.serverTimestamp(),
                      };
                      await FirebaseFirestore.instance
                          .collection('appContent')
                          .doc('config')
                          .set(payload, SetOptions(merge: true));
                      if (context.mounted) {
                        showAppSnackBar(context, 'تم حفظ المحتوى');
                      }
                    },
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('حفظ'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ContentFieldSpec {
  final String key;
  final String label;
  final String defaultValue;
  final int minLines;
  final int maxLines;

  const _ContentFieldSpec({
    required this.key,
    required this.label,
    required this.defaultValue,
    this.minLines = 1,
    this.maxLines = 1,
  });
}

const List<_ContentFieldSpec> _contentFields = <_ContentFieldSpec>[
  _ContentFieldSpec(
    key: 'homeGreetingPrefix',
    label: 'كلمة الترحيب قبل اسم العميل',
    defaultValue: 'مرحبًا',
  ),
  _ContentFieldSpec(
    key: 'homeWelcome',
    label: 'النص أسفل اسم العميل',
    defaultValue: 'مرحبًا بك في عقود برو',
    minLines: 2,
    maxLines: 3,
  ),
  _ContentFieldSpec(
    key: 'homeHeroTitle',
    label: 'عنوان البانر الرئيسي',
    defaultValue: 'إنشاء عقد جديد',
  ),
  _ContentFieldSpec(
    key: 'homeHeroSubtitle',
    label: 'وصف البانر الرئيسي',
    defaultValue: 'أنشئ طلب عقد احترافيًا في دقائق\nوأرسله للمراجعة والتوثيق.',
    minLines: 2,
    maxLines: 3,
  ),
  _ContentFieldSpec(
    key: 'homeHeroButtonText',
    label: 'زر البانر الرئيسي',
    defaultValue: 'إنشاء عقد جديد',
  ),
  _ContentFieldSpec(
    key: 'homeServicesTitle',
    label: 'عنوان قسم الخدمات',
    defaultValue: 'خدماتنا',
  ),
  _ContentFieldSpec(
    key: 'homeServicesAction',
    label: 'زر قسم الخدمات',
    defaultValue: 'عرض الكل',
  ),
  _ContentFieldSpec(
    key: 'serviceResidentialTitle',
    label: 'اسم خدمة العقد السكني',
    defaultValue: 'عقد سكني',
  ),
  _ContentFieldSpec(
    key: 'serviceResidentialSubtitle',
    label: 'وصف خدمة العقد السكني',
    defaultValue: 'إنشاء عقد سكني',
  ),
  _ContentFieldSpec(
    key: 'serviceCommercialTitle',
    label: 'اسم خدمة العقد التجاري',
    defaultValue: 'عقد تجاري',
  ),
  _ContentFieldSpec(
    key: 'serviceCommercialSubtitle',
    label: 'وصف خدمة العقد التجاري',
    defaultValue: 'إنشاء عقد تجاري',
  ),
  _ContentFieldSpec(
    key: 'serviceRenewalTitle',
    label: 'اسم خدمة تجديد العقد',
    defaultValue: 'تجديد عقد',
  ),
  _ContentFieldSpec(
    key: 'serviceRenewalSubtitle',
    label: 'وصف خدمة تجديد العقد',
    defaultValue: 'تجديد عقد قائم',
  ),
  _ContentFieldSpec(
    key: 'serviceRenewalMessage',
    label: 'رسالة الضغط على تجديد عقد',
    defaultValue: 'خدمة تجديد العقد جاهزة ضمن نموذج إنشاء العقد.',
    minLines: 2,
    maxLines: 3,
  ),
  _ContentFieldSpec(
    key: 'serviceHandoverTitle',
    label: 'اسم خدمة الاستلام والتسليم',
    defaultValue: 'استلام وتسليم',
  ),
  _ContentFieldSpec(
    key: 'serviceHandoverSubtitle',
    label: 'وصف خدمة الاستلام والتسليم',
    defaultValue: 'محضر استلام وتسليم',
  ),
  _ContentFieldSpec(
    key: 'serviceHandoverMessage',
    label: 'رسالة الضغط على الاستلام والتسليم',
    defaultValue: 'سيتم فتح نموذج الاستلام والتسليم.',
    minLines: 2,
    maxLines: 3,
  ),
  _ContentFieldSpec(
    key: 'homePropertiesTitle',
    label: 'عنوان قسم العقارات',
    defaultValue: 'العقارات المضافة مؤخرًا',
  ),
  _ContentFieldSpec(
    key: 'homePropertiesAction',
    label: 'زر قسم العقارات',
    defaultValue: 'عقاراتي',
  ),
  _ContentFieldSpec(
    key: 'homeEmptyPropertiesTitle',
    label: 'عنوان عدم وجود عقارات',
    defaultValue: 'لا توجد عقارات محفوظة',
  ),
  _ContentFieldSpec(
    key: 'homeEmptyPropertiesSubtitle',
    label: 'وصف عدم وجود عقارات',
    defaultValue: 'أضف عقاراتك ووحداتك لتسريع إنشاء العقود.',
    minLines: 2,
    maxLines: 3,
  ),
  _ContentFieldSpec(
    key: 'homeEmptyPropertiesAction',
    label: 'زر عدم وجود عقارات',
    defaultValue: 'إضافة عقار',
  ),
  _ContentFieldSpec(
    key: 'homeContractsTitle',
    label: 'عنوان قسم آخر الطلبات',
    defaultValue: 'آخر الطلبات',
  ),
  _ContentFieldSpec(
    key: 'homeContractsAction',
    label: 'زر قسم آخر الطلبات',
    defaultValue: 'عرض الكل',
  ),
  _ContentFieldSpec(
    key: 'homeEmptyContractsTitle',
    label: 'عنوان عدم وجود عقود',
    defaultValue: 'لا توجد عقود بعد',
  ),
  _ContentFieldSpec(
    key: 'homeEmptyContractsSubtitle',
    label: 'وصف عدم وجود عقود',
    defaultValue: 'ابدأ بإنشاء أول عقد لك من التطبيق.',
    minLines: 2,
    maxLines: 3,
  ),
  _ContentFieldSpec(
    key: 'homeEmptyContractsAction',
    label: 'زر عدم وجود عقود',
    defaultValue: 'إنشاء عقد',
  ),
  _ContentFieldSpec(
    key: 'supportInfo',
    label: 'نص الدعم العام',
    defaultValue: 'فريق الدعم جاهز لمساعدتك في طلبات العقود والتوثيق.',
    minLines: 2,
    maxLines: 4,
  ),
];

class _ReportsSection extends StatelessWidget {
  final List<ContractRecord> contracts;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> users;

  const _ReportsSection({required this.contracts, required this.users});

  @override
  Widget build(BuildContext context) {
    final byStatus = <ContractStatus, int>{
      for (final status in ContractStatus.values)
        status: contracts.where((item) => item.status == status).length,
    };
    return _AdminSectionShell(
      title: 'التقارير',
      subtitle: 'مؤشرات تشغيلية قابلة للتوسع للتصدير والفلاتر التاريخية.',
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: <Widget>[
            _MiniLine('إجمالي المستخدمين', '${users.length}'),
            _MiniLine('إجمالي العقود', '${contracts.length}'),
            for (final entry in byStatus.entries)
              _MiniLine(entry.key.label, '${entry.value}'),
          ],
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String adminUid;

  const _SettingsSection({required this.adminUid});

  @override
  Widget build(BuildContext context) {
    return _AdminSectionShell(
      title: 'إعدادات الأدمن',
      subtitle: 'الأدوار والصلاحيات وسجل التدقيق.',
      child: Column(
        children: <Widget>[
          AppCard(
            padding: const EdgeInsets.all(12),
            child: _MiniLine('معرف المدير الحالي', adminUid),
          ),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('auditLogs')
                .orderBy('createdAt', descending: true)
                .limit(30)
                .snapshots(),
            builder: (context, snapshot) {
              final logs = snapshot.data?.docs ?? const [];
              return AppCard(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('آخر عمليات التدقيق',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (logs.isEmpty)
                      Text(
                        'لا توجد عمليات بعد.',
                        style: TextStyle(color: context.ejarzTheme.muted),
                      )
                    else
                      for (final log in logs)
                        _MiniLine(
                          (log.data()['action'] as String?) ?? 'عملية',
                          (log.data()['targetId'] as String?) ?? '',
                        ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AdminSectionShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _AdminSectionShell({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(color: context.ejarzTheme.muted),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _AdminSidebar extends StatelessWidget {
  final int selectedIndex;
  final List<_AdminDestination> destinations;
  final ValueChanged<int> onSelected;
  final VoidCallback onLogout;
  final String adminName;

  const _AdminSidebar({
    required this.selectedIndex,
    required this.destinations,
    required this.onSelected,
    required this.onLogout,
    required this.adminName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.ejarzTheme.surface,
        border: Border(left: BorderSide(color: context.ejarzTheme.border)),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.apartment_rounded, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'عقود برو',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              adminName,
              style: TextStyle(color: context.ejarzTheme.muted),
            ),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < destinations.length; i++)
            _AdminNavItem(
              item: destinations[i],
              selected: selectedIndex == i,
              onTap: () => onSelected(i),
            ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: onLogout,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('خروج'),
          ),
        ],
      ),
    );
  }
}

class _AdminNavItem extends StatelessWidget {
  final _AdminDestination item;
  final bool selected;
  final VoidCallback onTap;

  const _AdminNavItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? AppColors.primaryLight : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: <Widget>[
                Icon(
                  item.icon,
                  color: selected ? AppColors.primary : context.ejarzTheme.text,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      color: selected
                          ? AppColors.primary
                          : context.ejarzTheme.text,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminMetric extends StatelessWidget {
  final double width;
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _AdminMetric({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.ejarzTheme.muted,
                      fontSize: context.sp(11.5),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: context.sp(20),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminContractTile extends StatelessWidget {
  final ContractRecord contract;
  final bool selected;
  final VoidCallback onTap;

  const _AdminContractTile({
    required this.contract,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(10),
      border: selected ? Border.all(color: AppColors.primary) : null,
      child: Row(
        children: <Widget>[
          Icon(contract.status.icon, color: contract.status.color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  contract.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  '${contract.requestNumber} • ${contract.property}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.ejarzTheme.muted,
                    fontSize: context.sp(11),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusChip(status: contract.status, compact: true),
        ],
      ),
    );
  }
}

class _AdminUserTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> user;
  final ValueChanged<QueryDocumentSnapshot<Map<String, dynamic>>> onToggleBlock;

  const _AdminUserTile({required this.user, required this.onToggleBlock});

  @override
  Widget build(BuildContext context) {
    final data = user.data();
    final blocked = data['status'] == 'blocked';
    return AppCard(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            backgroundColor: blocked ? AppColors.red : AppColors.primary,
            child: Icon(
              blocked ? Icons.block_rounded : Icons.person_outline_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  ((data['name'] as String?)?.trim().isNotEmpty ?? false)
                      ? data['name'] as String
                      : 'عميل بدون اسم',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  (data['phone'] as String?) ?? user.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.ejarzTheme.muted,
                    fontSize: context.sp(11),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => onToggleBlock(user),
            child: Text(blocked ? 'فك الحظر' : 'حظر'),
          ),
        ],
      ),
    );
  }
}

class _MiniLine extends StatelessWidget {
  final String label;
  final String value;

  const _MiniLine(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 112,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.ejarzTheme.muted,
                fontSize: context.sp(11.3),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _AdminAccessMessage extends StatelessWidget {
  const _AdminAccessMessage();

  @override
  Widget build(BuildContext context) {
    return const _AdminCenteredMessage(
      icon: Icons.login_rounded,
      title: 'يلزم تسجيل الدخول',
      body:
          'افتح اللوحة بعد تسجيل الدخول بحساب Firebase مضاف في adminUsers. يمكن استخدام نفس جلسة Firebase الحالية أو إضافة شاشة دخول إدارية لاحقًا.',
    );
  }
}

class _AdminLoginScreen extends StatefulWidget {
  final ValueChanged<User> onSignedIn;

  const _AdminLoginScreen({required this.onSignedIn});

  @override
  State<_AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<_AdminLoginScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.length < 6) {
      setState(() => _error = 'أدخل بريد المدير وكلمة مرور صحيحة.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw FirebaseAuthException(code: 'missing-user');
      }
      widget.onSignedIn(user);
    } on FirebaseAuthException catch (error) {
      setState(() {
        _error = switch (error.code) {
          'user-not-found' ||
          'wrong-password' ||
          'invalid-credential' =>
            'بيانات الدخول غير صحيحة.',
          'too-many-requests' => 'تم إيقاف المحاولات مؤقتًا، حاول لاحقًا.',
          'operation-not-allowed' =>
            'فعّل Email/Password من Firebase Authentication أولًا.',
          _ => error.message ?? 'تعذر تسجيل الدخول.'
        };
      });
    } catch (error) {
      setState(() => _error = 'تعذر تسجيل الدخول: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ResponsiveContent(
          maxWidth: 440,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Icon(
                Icons.admin_panel_settings_outlined,
                size: 54,
                color: AppColors.primary,
              ),
              const SizedBox(height: 14),
              Text(
                'دخول لوحة التحكم',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'استخدم حساب مدير مفعّل في Firebase ثم تحقق الصلاحيات من adminUsers.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.ejarzTheme.muted, height: 1.5),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'البريد الإلكتروني',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _password,
                obscureText: true,
                onSubmitted: (_) => _loading ? null : _signIn(),
                decoration: const InputDecoration(
                  labelText: 'كلمة المرور',
                  prefixIcon: Icon(Icons.lock_outline_rounded),
                ),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.red,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loading ? null : _signIn,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login_rounded),
                label: const Text('دخول'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminAuthError extends StatelessWidget {
  final String message;

  const _AdminAuthError({required this.message});

  @override
  Widget build(BuildContext context) {
    return _AdminCenteredMessage(
      icon: Icons.error_outline_rounded,
      title: 'تعذر تجهيز دخول لوحة التحكم',
      body:
          'تحقق من إعدادات Firebase Auth للويب ثم أعد فتح اللوحة. التفاصيل التقنية: $message',
    );
  }
}

class _AdminNoPermission extends StatelessWidget {
  final String uid;

  const _AdminNoPermission({required this.uid});

  @override
  Widget build(BuildContext context) {
    return _AdminCenteredMessage(
      icon: Icons.admin_panel_settings_outlined,
      title: 'لا توجد صلاحية للوحة التحكم',
      body:
          'أضف مستند adminUsers/$uid بقيمة active=true ودور owner أو manager ثم أعد فتح اللوحة.',
    );
  }
}

class _AdminLoading extends StatelessWidget {
  const _AdminLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _AdminCenteredMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _AdminCenteredMessage({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ResponsiveContent(
          maxWidth: 520,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 52, color: AppColors.primary),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.ejarzTheme.muted, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminDestination {
  final String label;
  final IconData icon;

  const _AdminDestination(this.label, this.icon);
}

double _tileWidth(double maxWidth, int columns) {
  final gaps = (columns - 1) * 10;
  return (maxWidth - gaps) / columns;
}

String _cleanAdminName(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty ||
      text.contains('?') ||
      text.contains('�') ||
      text.contains('Ø') ||
      text.contains('Ù')) {
    return 'مدير النظام';
  }
  return text;
}
