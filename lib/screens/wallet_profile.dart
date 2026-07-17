import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'contracts.dart';
import 'create_contract.dart';

Widget _accountBottomNavigation(BuildContext context) {
  final controller = AppScope.of(context);
  return EjarzBottomNavigation(
    currentIndex: controller.mainNavigationIndex,
    onSelect: (index) {
      final navigator = Navigator.of(context);
      navigator.popUntil((route) => route.isFirst);
      controller.setNavigationIndex(index);
    },
    onCreate: () {
      final navigator = Navigator.of(context);
      navigator.popUntil((route) => route.isFirst);
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const CreateContractScreen(),
        ),
      );
    },
  );
}

class PropertiesScreen extends StatelessWidget {
  final VoidCallback onMenu;
  final VoidCallback onNotifications;

  const PropertiesScreen({
    super.key,
    required this.onMenu,
    required this.onNotifications,
  });

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return SafeArea(
      child: ResponsiveContent(
        maxWidth: 760,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            BrandHeader(
              onMenu: onMenu,
              onNotifications: onNotifications,
              showMenu: false,
              showNotification: false,
              showLogo: false,
            ),
            const SizedBox(height: 14),
            AppPageHeader(
              title: 'عقاراتي',
              subtitle: 'إدارة العقارات والوحدات المرتبطة بعقودك.',
              icon: Icons.apartment_outlined,
              action: IconButton.filledTonal(
                tooltip: 'إضافة عقار',
                onPressed: () => _showAddProperty(context),
                icon: const Icon(Icons.add_rounded),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: StatCard(
                    title: 'العقارات',
                    value: '${controller.properties.length}',
                    subtitle: 'عقار محفوظ',
                    icon: Icons.apartment_outlined,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatCard(
                    title: 'الوحدات',
                    value:
                        '${controller.properties.fold<int>(0, (total, item) => total + item.units.length)}',
                    subtitle: 'وحدة',
                    icon: Icons.home_work_outlined,
                    color: AppColors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatCard(
                    title: 'المتاح',
                    value: '${controller.availableUnits}',
                    subtitle: 'وحدة',
                    icon: Icons.check_circle_outline_rounded,
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SectionTitle(
              title: 'قائمة العقارات والوحدات',
              action: '${controller.properties.length} عقار',
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < controller.properties.length; i++) ...<Widget>[
              _ManagedPropertyCard(property: controller.properties[i]),
              if (i < controller.properties.length - 1)
                const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }

  void _showAddProperty(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _PropertyEditorSheet(),
    );
  }
}

class _PropertyEditorSheet extends StatefulWidget {
  final PropertyRecord? existing;

  const _PropertyEditorSheet({this.existing});

  @override
  State<_PropertyEditorSheet> createState() => _PropertyEditorSheetState();
}

class _PropertyEditorSheetState extends State<_PropertyEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _city;
  late final TextEditingController _district;
  late final TextEditingController _floors;
  late final TextEditingController _totalUnits;
  late final TextEditingController _unitNumber;
  late final TextEditingController _unitArea;
  String _propertyType = 'عمارة';
  String _usage = 'سكن عوائل';
  String _unitType = 'شقة';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final firstUnit =
        existing?.units.isNotEmpty == true ? existing!.units.first : null;
    _title = TextEditingController(text: existing?.title ?? '');
    _city = TextEditingController(text: existing?.city ?? 'الرياض');
    _district = TextEditingController(text: existing?.district ?? '');
    _floors = TextEditingController(text: existing?.floors.toString() ?? '1');
    _totalUnits =
        TextEditingController(text: existing?.totalUnits.toString() ?? '1');
    _unitNumber = TextEditingController(text: firstUnit?.number ?? '');
    _unitArea = TextEditingController(
        text: firstUnit?.area.replaceAll(' م²', '') ?? '');
    _propertyType =
        existing?.type.trim().isNotEmpty == true ? existing!.type : 'عمارة';
    _usage = existing?.usage.trim().isNotEmpty == true
        ? existing!.usage
        : 'سكن عوائل';
    _unitType =
        firstUnit?.type.trim().isNotEmpty == true ? firstUnit!.type : 'شقة';
  }

  @override
  void dispose() {
    _title.dispose();
    _city.dispose();
    _district.dispose();
    _floors.dispose();
    _totalUnits.dispose();
    _unitNumber.dispose();
    _unitArea.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        child: ResponsiveContent(
          maxWidth: 640,
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                AppPageHeader(
                  title: widget.existing == null ? 'إضافة عقار' : 'تعديل عقار',
                  subtitle: 'احفظ بيانات العقار والوحدة لاستخدامها في العقود.',
                  icon: Icons.add_home_work_outlined,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: 'اسم العقار',
                  hint: 'مثال: عمارة الياسمين',
                  controller: _title,
                  icon: Icons.apartment_outlined,
                  required: true,
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: AppTextField(
                        label: 'المدينة',
                        hint: 'الرياض',
                        controller: _city,
                        icon: Icons.location_city_outlined,
                        required: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppTextField(
                        label: 'الحي',
                        hint: 'العليا',
                        controller: _district,
                        icon: Icons.location_on_outlined,
                        required: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: AppDropdownField(
                        label: 'نوع العقار',
                        value: _propertyType,
                        items: const <String>[
                          'عمارة',
                          'برج',
                          'أرض',
                          'شقة',
                          'فيلا'
                        ],
                        icon: Icons.home_work_outlined,
                        onChanged: (value) => setState(
                            () => _propertyType = value ?? _propertyType),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppDropdownField(
                        label: 'الاستخدام',
                        value: _usage,
                        items: const <String>[
                          'سكن عوائل',
                          'سكن أفراد',
                          'سكن جماعي',
                          'تجاري'
                        ],
                        icon: Icons.category_outlined,
                        onChanged: (value) =>
                            setState(() => _usage = value ?? _usage),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: AppTextField(
                        label: 'عدد الأدوار',
                        hint: '1',
                        controller: _floors,
                        keyboardType: TextInputType.number,
                        icon: Icons.layers_outlined,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppTextField(
                        label: 'إجمالي الوحدات',
                        hint: '1',
                        controller: _totalUnits,
                        keyboardType: TextInputType.number,
                        icon: Icons.numbers_outlined,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: AppTextField(
                        label: 'رقم الوحدة',
                        hint: '12',
                        controller: _unitNumber,
                        icon: Icons.tag_outlined,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppDropdownField(
                        label: 'نوع الوحدة',
                        value: _unitType,
                        items: const <String>[
                          'شقة',
                          'استديو',
                          'دور',
                          'فيلا',
                          'محل',
                          'مستودع',
                          'مكتب إداري'
                        ],
                        icon: Icons.meeting_room_outlined,
                        onChanged: (value) =>
                            setState(() => _unitType = value ?? _unitType),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                AppTextField(
                  label: 'مساحة الوحدة',
                  hint: '120',
                  controller: _unitArea,
                  keyboardType: TextInputType.number,
                  icon: Icons.square_foot_outlined,
                ),
                const SizedBox(height: 14),
                PrimaryButton(
                  label: _saving ? 'جاري الحفظ...' : 'حفظ العقار',
                  icon: Icons.save_outlined,
                  loading: _saving,
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty ||
        _city.text.trim().isEmpty ||
        _district.text.trim().isEmpty) {
      showAppSnackBar(context, 'أدخل اسم العقار والمدينة والحي');
      return;
    }
    setState(() => _saving = true);
    final data = PropertyData()
      ..buildingName = _title.text.trim()
      ..city = _city.text.trim()
      ..district = _district.text.trim()
      ..propertyType = _propertyType
      ..propertyUsage = _usage
      ..floorsCount = _floors.text.trim().isEmpty ? '1' : _floors.text.trim()
      ..unitsPerFloor = '1'
      ..totalUnits =
          _totalUnits.text.trim().isEmpty ? '1' : _totalUnits.text.trim()
      ..unitNumber = _unitNumber.text.trim()
      ..unitName = _unitType
      ..unitType = _unitType
      ..floor = '1'
      ..area = _unitArea.text.trim()
      ..roomsCount = _unitType == 'شقة' ? '3' : '0'
      ..bathroomsCount = '1'
      ..hallsCount = '1'
      ..electricityMeter = 'غير محدد'
      ..waterMeter = 'غير محدد';
    try {
      final controller = AppScope.of(context, listen: false);
      final saved = await controller.saveProperty(
        data,
        existing: widget.existing,
      );
      final savedLocally = controller.isPropertyPendingSync(saved.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      showAppSnackBar(
        context,
        savedLocally
            ? 'تم حفظ العقار محليًا وستتم مزامنته عند عودة الاتصال'
            : 'تم حفظ العقار بنجاح',
      );
    } catch (_) {
      if (mounted) showAppSnackBar(context, 'تعذر حفظ العقار الآن');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _ManagedPropertyCard extends StatelessWidget {
  final PropertyRecord property;

  const _ManagedPropertyCard({required this.property});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      onTap: () => _showDetails(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.apartment_rounded,
                    color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      property.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${property.location} • ${property.type} • ${property.usage}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.ejarzTheme.muted,
                        fontSize: context.sp(11.5),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'عرض التفاصيل',
                onPressed: () => _showDetails(context),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              _PropertyMeta(label: '${property.floors} أدوار'),
              _PropertyMeta(label: '${property.totalUnits} وحدة'),
              _PropertyMeta(label: property.usage),
            ],
          ),
          const SizedBox(height: 10),
          for (final unit in property.units.take(2)) _UnitPreview(unit: unit),
        ],
      ),
    );
  }

  void _showDetails(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ResponsiveContent(
          maxWidth: 640,
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AppPageHeader(
                title: property.title,
                subtitle: '${property.location} • ${property.type}',
                icon: Icons.apartment_outlined,
              ),
              const SizedBox(height: 12),
              const SectionTitle(title: 'الوحدات المرتبطة'),
              const SizedBox(height: 8),
              for (final unit in property.units) _UnitPreview(unit: unit),
              const SizedBox(height: 12),
              SecondaryButton(
                label: 'تعديل العقار',
                icon: Icons.edit_outlined,
                onPressed: () {
                  Navigator.of(context).pop();
                  showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    isScrollControlled: true,
                    builder: (_) => _PropertyEditorSheet(existing: property),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PropertyMeta extends StatelessWidget {
  final String label;

  const _PropertyMeta({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: context.ejarzTheme.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.ejarzTheme.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: context.ejarzTheme.muted,
          fontSize: context.sp(10.8),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _UnitPreview extends StatelessWidget {
  final UnitRecord unit;

  const _UnitPreview({required this.unit});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: <Widget>[
          const Icon(Icons.home_work_outlined,
              color: AppColors.primary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${unit.name} • ${unit.type} • ${unit.floor}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            unit.status,
            style: TextStyle(
              color: unit.status.contains('متاح')
                  ? AppColors.success
                  : context.ejarzTheme.muted,
              fontSize: context.sp(11),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletStandaloneScreen extends StatelessWidget {
  const _WalletStandaloneScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: _accountBottomNavigation(context),
      body: WalletScreen(
        onMenu: () => Navigator.of(context).pop(),
        onNotifications: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const NotificationsScreen(),
          ),
        ),
      ),
    );
  }
}

class WalletScreen extends StatelessWidget {
  final VoidCallback onMenu;
  final VoidCallback onNotifications;

  const WalletScreen({
    super.key,
    required this.onMenu,
    required this.onNotifications,
  });

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final totalSpent = controller.transactions
        .where((item) => !item.incoming)
        .fold<double>(0, (sum, item) => sum + item.amount);

    return SafeArea(
      child: ResponsiveContent(
        maxWidth: 760,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            BrandHeader(
              onMenu: onMenu,
              onNotifications: onNotifications,
              showMenu: true,
              menuIcon: Icons.arrow_back_rounded,
              showNotification: false,
              showLogo: false,
            ),
            const SizedBox(height: 14),
            const AppPageHeader(
              title: 'المحفظة والمدفوعات',
              subtitle: 'راجع المدفوعات والفواتير وطرق الدفع المحفوظة.',
              icon: Icons.account_balance_wallet_outlined,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: <Color>[Color(0xFF0B8062), Color(0xFF005E49)],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.24),
                    blurRadius: 26,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.account_balance_wallet_outlined,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'إجمالي المدفوعات',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${totalSpent.toStringAsFixed(2)} ر.س',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: context.sp(27),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${controller.transactions.length} عمليات مسجلة',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: context.sp(12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _WalletAction(
                          icon: Icons.receipt_long_outlined,
                          label: 'الفواتير',
                          onTap: () => showAppSnackBar(
                            context,
                            'تم تجهيز قائمة الفواتير.',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _WalletAction(
                          icon: Icons.credit_card_outlined,
                          label: 'طرق الدفع',
                          onTap: () => showModalBottomSheet<void>(
                            context: context,
                            showDragHandle: true,
                            builder: (_) => const _PaymentMethodsSheet(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const SectionTitle(
              title: 'طريقة الدفع الرئيسية',
              icon: Icons.credit_card_rounded,
            ),
            const SizedBox(height: 10),
            AppCard(
              padding: const EdgeInsets.all(15),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 54,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.credit_card_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'بطاقة مدى',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '•••• •••• •••• 8432',
                          style: TextStyle(
                            color: context.ejarzTheme.muted,
                            fontSize: context.sp(12),
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'افتراضية',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SectionTitle(
              title: 'آخر العمليات',
              icon: Icons.history_rounded,
              action: 'عرض الطلبات',
              onAction: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const _PaidContractsScreen(),
                ),
              ),
            ),
            const SizedBox(height: 10),
            for (var i = 0;
                i < controller.transactions.length;
                i++) ...<Widget>[
              _TransactionTile(
                transaction: controller.transactions[i],
                contract: _contractForTransaction(
                  controller,
                  controller.transactions[i],
                ),
              ),
              if (i != controller.transactions.length - 1)
                const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _WalletAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _WalletAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final WalletTransaction transaction;
  final ContractRecord? contract;

  const _TransactionTile({required this.transaction, this.contract});

  @override
  Widget build(BuildContext context) {
    final color = transaction.incoming ? AppColors.success : AppColors.text;
    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: contract == null
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ContractDetailsScreen(contract: contract!),
                ),
              ),
      child: Row(
        children: <Widget>[
          Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: transaction.incoming
                  ? AppColors.primaryLight
                  : context.ejarzTheme.background,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              transaction.incoming
                  ? Icons.south_west_rounded
                  : Icons.north_east_rounded,
              color: transaction.incoming
                  ? AppColors.success
                  : context.ejarzTheme.muted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  transaction.title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '${transaction.reference} • ${transaction.date}',
                  style: TextStyle(
                    color: context.ejarzTheme.muted,
                    fontSize: context.sp(11),
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${transaction.incoming ? '+' : '-'}${transaction.amount.toStringAsFixed(2)} ر.س',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: context.sp(13.5),
            ),
          ),
          if (contract != null) ...<Widget>[
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_left_rounded,
              color: context.ejarzTheme.muted,
            ),
          ],
        ],
      ),
    );
  }
}

ContractRecord? _contractForTransaction(
  AppController controller,
  WalletTransaction transaction,
) {
  final transactionContractId = _safeTransactionContractId(transaction);
  for (final contract in controller.contracts) {
    if (transactionContractId.isNotEmpty &&
        contract.id == transactionContractId) {
      return contract;
    }
    if (contract.paymentId.isNotEmpty &&
        transaction.reference.startsWith(contract.paymentId)) {
      return contract;
    }
    if (transaction.reference
        .contains(contract.id.replaceFirst('EJ-DEMO-', ''))) {
      return contract;
    }
  }
  return null;
}

String _safeTransactionContractId(WalletTransaction transaction) {
  try {
    return transaction.contractId;
  } catch (_) {
    return '';
  }
}

class _PaidContractsScreen extends StatelessWidget {
  const _PaidContractsScreen();

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final paidContracts = controller.contracts
        .where(
          (contract) =>
              contract.paymentStatus == 'paid' ||
              contract.paymentId.isNotEmpty ||
              contract.isDemoPayment,
        )
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('طلبات تم الدفع لها')),
      bottomNavigationBar: _accountBottomNavigation(context),
      body: SafeArea(
        child: ResponsiveContent(
          maxWidth: 760,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const AppPageHeader(
                title: 'طلبات تم الدفع لها',
                subtitle: 'العقود المرتبطة بعمليات الدفع المسجلة في المحفظة.',
                icon: Icons.receipt_long_outlined,
              ),
              const SizedBox(height: 12),
              if (paidContracts.isEmpty)
                const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'لا توجد طلبات مدفوعة',
                  subtitle: 'ستظهر هنا العقود التي اكتمل دفع رسومها.',
                )
              else
                for (var i = 0; i < paidContracts.length; i++) ...<Widget>[
                  _PaidContractTile(contract: paidContracts[i]),
                  if (i != paidContracts.length - 1) const SizedBox(height: 10),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PaidContractTile extends StatelessWidget {
  final ContractRecord contract;

  const _PaidContractTile({required this.contract});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ContractDetailsScreen(contract: contract),
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.description_outlined,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  contract.title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  '${contract.requestNumber} • ${contract.date}',
                  style: TextStyle(
                    color: context.ejarzTheme.muted,
                    fontSize: context.sp(11.5),
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${contract.totalFees.toStringAsFixed(2)} ر.س',
            style: TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w900,
              fontSize: context.sp(13),
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_left_rounded, color: context.ejarzTheme.muted),
        ],
      ),
    );
  }
}

class _PaymentMethodsSheet extends StatelessWidget {
  const _PaymentMethodsSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'طرق الدفع',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 15),
            const _SimpleMethod(
              icon: Icons.credit_card_rounded,
              title: 'بطاقة مدى •••• 8432',
              subtitle: 'الطريقة الافتراضية',
              selected: true,
            ),
            const SizedBox(height: 10),
            const _SimpleMethod(
              icon: Icons.phone_iphone_rounded,
              title: 'Apple Pay',
              subtitle: 'جاهز للاستخدام',
            ),
            const SizedBox(height: 16),
            SecondaryButton(
              label: 'إضافة بطاقة جديدة',
              icon: Icons.add_card_rounded,
              onPressed: () => showAppSnackBar(
                context,
                'الدفع الإلكتروني غير مفعل في هذه النسخة التجريبية. سيتم تفعيل طرق الدفع بعد ربط مزود دفع حقيقي.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SimpleMethod extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;

  const _SimpleMethod({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(13),
      shadows: const <BoxShadow>[],
      border: Border.all(
        color: selected ? AppColors.primary : context.ejarzTheme.border,
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: context.ejarzTheme.muted,
                    fontSize: context.sp(11.5),
                  ),
                ),
              ],
            ),
          ),
          if (selected)
            const Icon(Icons.check_circle_rounded, color: AppColors.primary),
        ],
      ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  final VoidCallback onMenu;
  final VoidCallback onNotifications;

  const ProfileScreen({
    super.key,
    required this.onMenu,
    required this.onNotifications,
  });

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return SafeArea(
      child: ResponsiveContent(
        maxWidth: 720,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            BrandHeader(
              onMenu: onMenu,
              onNotifications: onNotifications,
              showMenu: false,
              showNotification: false,
              showLogo: false,
            ),
            const SizedBox(height: 14),
            const AppPageHeader(
              title: 'حسابي',
              subtitle: 'أدر بيانات الحساب والمدفوعات وإعدادات التطبيق.',
              icon: Icons.person_outline_rounded,
            ),
            const SizedBox(height: 12),
            AppCard(
              padding: const EdgeInsets.all(13),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 54,
                    height: 54,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryLight,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        controller.userName.trim().isEmpty
                            ? 'م'
                            : controller.userName.trim()[0],
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: context.sp(22),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          controller.userName,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          controller.userPhone,
                          style: TextStyle(
                            color: context.ejarzTheme.muted,
                            fontSize: context.sp(12),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          controller.userEmail,
                          style: TextStyle(
                            color: context.ejarzTheme.muted,
                            fontSize: context.sp(11.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const EditProfileScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            AppCard(
              padding: const EdgeInsets.all(16),
              color: AppColors.primaryLight.withValues(alpha: 0.75),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.18),
              ),
              shadows: const <BoxShadow>[],
              child: Row(
                children: <Widget>[
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.payments_outlined,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'رسوم العقود فقط',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'الدفع حسب رسوم كل عقد فقط. تظهر الرسوم قبل الإرسال والدفع.',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const _WalletStandaloneScreen(),
                      ),
                    ),
                    child: const Text('المدفوعات'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const SectionTitle(title: 'الحساب والخدمات'),
            const SizedBox(height: 10),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: <Widget>[
                  _ProfileRow(
                    icon: Icons.business_outlined,
                    title: 'العقارات المحفوظة',
                    subtitle: 'إدارة بيانات عقاراتك ووحداتك',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SavedPropertiesScreen(),
                      ),
                    ),
                  ),
                  const Divider(),
                  _ProfileRow(
                    icon: Icons.people_outline_rounded,
                    title: 'الأطراف المحفوظة',
                    subtitle: 'بيانات المؤجرين والمستأجرين',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SavedPartiesScreen(),
                      ),
                    ),
                  ),
                  const Divider(),
                  _ProfileRow(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'المحفظة والمدفوعات',
                    subtitle: 'الفواتير وطرق الدفع وسجل العمليات',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const _WalletStandaloneScreen(),
                      ),
                    ),
                  ),
                  const Divider(),
                  _ProfileRow(
                    icon: Icons.notifications_none_rounded,
                    title: 'الإشعارات',
                    subtitle:
                        '${controller.unreadNotifications} إشعارات غير مقروءة',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const NotificationsScreen(),
                      ),
                    ),
                  ),
                  const Divider(),
                  _ProfileRow(
                    icon: Icons.settings_outlined,
                    title: 'الإعدادات',
                    subtitle: 'الأمان والتنبيهات ومظهر التطبيق',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SettingsScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: <Widget>[
                  _ProfileRow(
                    icon: Icons.support_agent_rounded,
                    title: 'الدعم الفني',
                    subtitle: 'تواصل معنا أو راجع الأسئلة الشائعة',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SupportScreen(),
                      ),
                    ),
                  ),
                  const Divider(),
                  _ProfileRow(
                    icon: Icons.policy_outlined,
                    title: 'الشروط والسياسات',
                    subtitle: 'الشروط والأحكام وسياسة الخصوصية',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const LegalScreen(),
                      ),
                    ),
                  ),
                  const Divider(),
                  _ProfileRow(
                    icon: Icons.info_outline_rounded,
                    title: 'عن عقود برو',
                    subtitle: 'الإصدار 1.0.0',
                    onTap: () => showAboutDialog(
                      context: context,
                      applicationName: 'عقود برو',
                      applicationVersion: '1.0.0',
                      applicationLegalese: 'جميع الحقوق محفوظة',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () => _confirmLogout(context),
              icon: const Icon(Icons.logout_rounded, color: AppColors.red),
              label: const Text(
                'تسجيل الخروج',
                style: TextStyle(color: AppColors.red),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text('هل تريد تسجيل الخروج من حسابك؟'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              AppScope.of(context, listen: false).logout();
            },
            child: const Text('تسجيل الخروج'),
          ),
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ProfileRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: context.ejarzTheme.muted,
                      fontSize: context.sp(11.5),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_back_ios_new_rounded,
                size: 15, color: context.ejarzTheme.muted),
          ],
        ),
      ),
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late String _name;
  late String _phone;
  late String _email;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppScope.of(context);
    _name = controller.userName;
    _phone = controller.userPhone;
    _email = controller.userEmail;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final controller = AppScope.of(context, listen: false);
    controller.updateProfile(
      name: _name,
      phone: controller.userPhone,
      email: _email,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تعديل الملف الشخصي')),
      bottomNavigationBar: _accountBottomNavigation(context),
      body: SafeArea(
        child: ResponsiveContent(
          maxWidth: 560,
          child: Form(
            key: _formKey,
            child: Column(
              children: <Widget>[
                AppTextField(
                  label: 'الاسم الكامل',
                  hint: 'الاسم الكامل',
                  initialValue: _name,
                  icon: Icons.person_outline_rounded,
                  required: true,
                  onChanged: (value) => _name = value,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'أدخل الاسم'
                      : null,
                ),
                const SizedBox(height: 15),
                AppTextField(
                  label: 'رقم الجوال',
                  hint: '05xxxxxxxx',
                  initialValue: _phone,
                  icon: Icons.phone_android_rounded,
                  enabled: false,
                  readOnly: true,
                  onChanged: (_) {},
                ),
                const SizedBox(height: 6),
                Text(
                  'رقم الجوال مرتبط بتسجيل الدخول ولا يمكن تغييره من الملف الشخصي.',
                  style: TextStyle(
                    color: context.ejarzTheme.muted,
                    fontSize: context.sp(11.5),
                  ),
                ),
                const SizedBox(height: 15),
                AppTextField(
                  label: 'البريد الإلكتروني',
                  hint: 'name@example.com',
                  initialValue: _email,
                  icon: Icons.email_outlined,
                  required: true,
                  onChanged: (value) => _email = value,
                  validator: (value) => value == null || !value.contains('@')
                      ? 'أدخل بريدًا صحيحًا'
                      : null,
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: 'حفظ التعديلات',
                  icon: Icons.save_outlined,
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإشعارات'),
        actions: <Widget>[
          TextButton(
            onPressed: () => controller.markAllNotificationsRead(),
            child: const Text('تحديد الكل كمقروء'),
          ),
        ],
      ),
      bottomNavigationBar: _accountBottomNavigation(context),
      body: SafeArea(
        child: ResponsiveContent(
          maxWidth: 700,
          child: Column(
            children: <Widget>[
              if (controller.notifications.isEmpty)
                const EmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: 'لا توجد إشعارات',
                  subtitle: 'ستظهر هنا تحديثات العقود والمدفوعات والنواقص.',
                )
              else
                for (var i = 0;
                    i < controller.notifications.length;
                    i++) ...<Widget>[
                  _NotificationTile(item: controller.notifications[i]),
                  if (i != controller.notifications.length - 1)
                    const SizedBox(height: 10),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final NotificationItem item;

  const _NotificationTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () async {
        final controller = AppScope.of(context, listen: false);
        await controller.markNotificationRead(item);
        if (!context.mounted) return;
        if (item.actionType == 'supportTicket') {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const SupportScreen(),
            ),
          );
          return;
        }
        if (item.actionType != 'contractDetails' ||
            item.contractId.trim().isEmpty) {
          return;
        }
        final contract = await controller.contractById(item.contractId);
        if (!context.mounted) return;
        if (contract == null) {
          showAppSnackBar(context, 'تعذر فتح تفاصيل العقد الآن');
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ContractDetailsScreen(contract: contract),
          ),
        );
      },
      padding: const EdgeInsets.all(14),
      color: item.read ? null : item.color.withValues(alpha: 0.035),
      border: Border.all(
        color: item.read
            ? context.ejarzTheme.border
            : item.color.withValues(alpha: 0.32),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(item.icon, color: item.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        item.title,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    if (!item.read)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: item.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  item.body,
                  style: TextStyle(
                    color: context.ejarzTheme.muted,
                    fontSize: context.sp(12),
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.time,
                  style: TextStyle(
                    color: context.ejarzTheme.muted,
                    fontSize: context.sp(10.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      bottomNavigationBar: _accountBottomNavigation(context),
      body: SafeArea(
        child: ResponsiveContent(
          maxWidth: 700,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SectionTitle(title: 'الأمان'),
              const SizedBox(height: 10),
              ToggleCard(
                title: 'الدخول بالبصمة',
                subtitle: 'استخدم بصمة الجهاز لتسجيل الدخول بسرعة',
                value: controller.biometricEnabled,
                icon: Icons.fingerprint_rounded,
                onChanged: controller.toggleBiometric,
              ),
              const SizedBox(height: 10),
              AppCard(
                onTap: () => showAppSnackBar(
                  context,
                  'سيتم إرسال رمز تحقق لتغيير كلمة المرور.',
                ),
                padding: const EdgeInsets.all(14),
                child: const Row(
                  children: <Widget>[
                    Icon(Icons.lock_reset_rounded, color: AppColors.primary),
                    SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        'تغيير كلمة المرور',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Icon(Icons.arrow_back_ios_new_rounded, size: 15),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const SectionTitle(title: 'التنبيهات'),
              const SizedBox(height: 10),
              ToggleCard(
                title: 'إشعارات التطبيق',
                subtitle: 'حالات العقود والتنبيهات المهمة',
                value: controller.pushNotificationsEnabled,
                icon: Icons.notifications_active_outlined,
                onChanged: controller.togglePushNotifications,
              ),
              const SizedBox(height: 14),
              const SectionTitle(title: 'المظهر'),
              const SizedBox(height: 10),
              ToggleCard(
                title: 'الوضع الداكن',
                subtitle: 'استخدم ألوانًا داكنة ومريحة في الإضاءة المنخفضة',
                value: controller.darkMode,
                icon: Icons.dark_mode_outlined,
                onChanged: controller.toggleDarkMode,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SupportScreen extends StatefulWidget {
  final String? initialTicketId;

  const SupportScreen({super.key, this.initialTicketId});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final TextEditingController _subject = TextEditingController();
  final TextEditingController _message = TextEditingController();
  String _priority = 'عادية';
  bool _sending = false;
  bool _openedInitialTicket = false;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final initialTicketId = widget.initialTicketId;
    if (!_openedInitialTicket && initialTicketId != null) {
      final matches = controller.supportTickets
          .where((ticket) => ticket.id == initialTicketId)
          .toList();
      if (matches.isNotEmpty) {
        _openedInitialTicket = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showTicketDetails(context, matches.first);
        });
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text('الدعم الفني')),
      bottomNavigationBar: _accountBottomNavigation(context),
      body: SafeArea(
        child: ResponsiveContent(
          maxWidth: 700,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: <Color>[Color(0xFF0B8062), Color(0xFF005E49)],
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: const Icon(
                        Icons.support_agent_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text(
                            'نحن هنا لمساعدتك',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'متوسط وقت الرد أقل من 10 دقائق.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.78),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SectionTitle(
                title: 'الدعم',
                action: '${controller.supportTickets.length} تذاكر',
              ),
              const SizedBox(height: 10),
              if (controller.supportTickets.isEmpty)
                const InfoBanner(
                  text: 'لا توجد تذاكر دعم حتى الآن.',
                  icon: Icons.support_agent_rounded,
                )
              else
                for (final ticket
                    in controller.supportTickets.take(3)) ...<Widget>[
                  _SupportTicketCard(
                    ticket: ticket,
                    onTap: () => _showTicketDetails(context, ticket),
                  ),
                  const SizedBox(height: 8),
                ],
              const SizedBox(height: 14),
              const SectionTitle(title: 'تواصل معنا'),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _SupportMethod(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: 'محادثة',
                      onTap: () => showAppSnackBar(
                        context,
                        'تم بدء محادثة دعم جديدة.',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SupportMethod(
                      icon: Icons.call_outlined,
                      title: 'اتصال',
                      onTap: () => showAppSnackBar(
                        context,
                        'سيتم إظهار رقم الدعم بعد ربط بيانات الشركة.',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SupportMethod(
                      icon: Icons.email_outlined,
                      title: 'بريد',
                      onTap: () => showAppSnackBar(
                        context,
                        'تم نسخ بريد الدعم.',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const SectionTitle(title: 'إرسال طلب دعم'),
              const SizedBox(height: 10),
              AppTextField(
                label: 'الموضوع',
                hint: 'مثال: استفسار عن حالة عقد',
                controller: _subject,
                icon: Icons.subject_rounded,
                required: true,
              ),
              const SizedBox(height: 10),
              AppTextField(
                label: 'رسالتك',
                hint: 'اشرح المشكلة أو الاستفسار بالتفصيل',
                controller: _message,
                icon: Icons.edit_note_rounded,
                maxLines: 5,
                required: true,
              ),
              const SizedBox(height: 10),
              AppDropdownField(
                label: 'الأولوية',
                value: _priority,
                items: const <String>['عادية', 'عالية'],
                icon: Icons.flag_outlined,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _priority = value);
                },
              ),
              const SizedBox(height: 14),
              PrimaryButton(
                label: _sending ? 'جاري الإرسال...' : 'إرسال الطلب',
                icon: Icons.send_rounded,
                loading: _sending,
                onPressed: () async {
                  final subject = _subject.text.trim();
                  final message = _message.text.trim();
                  if (subject.isEmpty) {
                    showAppSnackBar(context, 'اكتب موضوع الطلب أولًا');
                    return;
                  }
                  if (message.isEmpty) {
                    showAppSnackBar(context, 'اكتب رسالتك أولًا');
                    return;
                  }
                  setState(() => _sending = true);
                  try {
                    await AppScope.of(context, listen: false)
                        .createSupportTicket(
                      subject: subject,
                      message: message,
                      priority: _priority == 'عالية' ? 'high' : 'normal',
                    );
                    _subject.clear();
                    _message.clear();
                    if (context.mounted) {
                      showAppSnackBar(context, 'تم إرسال طلب الدعم بنجاح');
                    }
                  } catch (_) {
                    if (context.mounted) {
                      showAppSnackBar(context, 'تعذر إرسال طلب الدعم الآن');
                    }
                  } finally {
                    if (context.mounted) {
                      setState(() => _sending = false);
                    }
                  }
                },
              ),
              const SizedBox(height: 14),
              const SectionTitle(title: 'الأسئلة الشائعة'),
              const SizedBox(height: 10),
              const _FaqTile(
                question: 'كم يستغرق إصدار العقد؟',
                answer:
                    'يعتمد الوقت على اكتمال البيانات والمرفقات، ويظهر تقدم الطلب داخل التطبيق في كل مرحلة.',
              ),
              const _FaqTile(
                question: 'ماذا يحدث إذا كانت البيانات ناقصة؟',
                answer:
                    'يتحول الطلب إلى حالة ناقص بيانات، وستصلك ملاحظة واضحة بالحقول أو المستندات المطلوب استكمالها.',
              ),
              const _FaqTile(
                question: 'متى أستطيع تحميل العقد؟',
                answer:
                    'بعد توثيق العقد من الأطراف نرفع النسخة النهائية داخل صفحة تفاصيل العقد.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTicketDetails(BuildContext context, SupportTicketRecord ticket) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ResponsiveContent(
          maxWidth: 620,
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AppPageHeader(
                title: ticket.subject,
                subtitle: ticket.statusLabel,
                icon: Icons.support_agent_rounded,
              ),
              const SizedBox(height: 10),
              if (ticket.message.trim().isNotEmpty)
                InfoBanner(
                  text: ticket.message,
                  icon: Icons.chat_bubble_outline_rounded,
                ),
              const SizedBox(height: 12),
              const SectionTitle(title: 'ردود الدعم'),
              const SizedBox(height: 8),
              if (ticket.replies.isEmpty)
                Text(
                  'لا توجد ردود بعد.',
                  style: TextStyle(color: context.ejarzTheme.muted),
                )
              else
                for (final reply in ticket.replies) ...<Widget>[
                  AppCard(
                    shadows: const <BoxShadow>[],
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          reply.createdByName,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 5),
                        Text(reply.message),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SupportTicketCard extends StatelessWidget {
  final SupportTicketRecord ticket;
  final VoidCallback onTap;

  const _SupportTicketCard({required this.ticket, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final high = ticket.priority == 'high';
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: high
                  ? AppColors.red.withValues(alpha: 0.10)
                  : AppColors.primaryLight,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              Icons.support_agent_rounded,
              color: high ? AppColors.red : AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  ticket.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  ticket.statusLabel,
                  style: TextStyle(
                    color: context.ejarzTheme.muted,
                    fontSize: context.sp(11.5),
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_left_rounded),
        ],
      ),
    );
  }
}

class _SupportMethod extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _SupportMethod({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Column(
        children: <Widget>[
          Icon(icon, color: AppColors.primary, size: 27),
          const SizedBox(height: 8),
          Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: context.sp(12.5))),
        ],
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  final String question;
  final String answer;

  const _FaqTile({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      shadows: const <BoxShadow>[],
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          question,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: <Widget>[
          Text(
            answer,
            style: TextStyle(
              color: context.ejarzTheme.muted,
              height: 1.65,
            ),
          ),
        ],
      ),
    );
  }
}

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  Future<void> _open(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      showAppSnackBar(context, 'تعذر فتح الرابط الآن');
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('الشروط والسياسات')),
      bottomNavigationBar: _accountBottomNavigation(context),
      body: SafeArea(
        child: ResponsiveContent(
          maxWidth: 760,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const _LegalSection(
                title: 'الشروط والأحكام',
                body:
                    'يعمل تطبيق عقود برو كوسيط لتجهيز ومراجعة بيانات طلب عقد الإيجار، ثم استخدام البيانات والمرفقات التي يزودنا بها العميل لإدخال الطلب في منصة إيجار ومتابعته حتى استخراج العقد. تظهر عمولة عقود برو والرسوم الرسمية بوضوح قبل تأكيد الطلب أو الدفع.',
              ),
              const SizedBox(height: 8),
              _LegalLinkTile(
                title: 'فتح شروط الاستخدام',
                url: controller.legalTermsUrl,
                icon: Icons.policy_outlined,
                onTap: _open,
              ),
              const SizedBox(height: 14),
              const _LegalSection(
                title: 'سياسة الخصوصية',
                body:
                    'نجمع ونعالج البيانات اللازمة لتنفيذ الخدمة مثل بيانات الحساب، أطراف العقد، العقار، الوحدة، المرفقات، بيانات الدفع، وطلبات الدعم. تُستخدم هذه البيانات لمراجعة الطلب وإدخاله في منصة إيجار واستخراج العقد ومتابعة حالته، ولا تستخدم خارج نطاق تقديم الخدمة والالتزامات النظامية.',
              ),
              const SizedBox(height: 8),
              _LegalLinkTile(
                title: 'فتح سياسة الخصوصية',
                url: controller.legalPrivacyUrl,
                icon: Icons.privacy_tip_outlined,
                onTap: _open,
              ),
              const SizedBox(height: 14),
              const _LegalSection(
                title: 'سياسة الدفع والاسترداد',
                body:
                    'تظهر الرسوم بالتفصيل قبل تأكيد الدفع. في حال تعذر تنفيذ الخدمة لأسباب تعود إلى مقدم الخدمة تتم معالجة الاسترداد وفق حالة الطلب وطريقة الدفع. أما الرسوم الرسمية التي تم سدادها لجهة خارجية فتخضع لسياسة الجهة ذات العلاقة.',
              ),
              const SizedBox(height: 8),
              _LegalLinkTile(
                title: 'فتح سياسة الدفع والاسترداد',
                url: controller.legalRefundUrl,
                icon: Icons.payments_outlined,
                onTap: _open,
              ),
              const SizedBox(height: 14),
              _LegalLinkTile(
                title: 'طلب حذف الحساب والبيانات',
                url: controller.legalAccountDeletionUrl,
                icon: Icons.delete_outline_rounded,
                onTap: _open,
              ),
              const SizedBox(height: 14),
              const InfoBanner(
                text:
                    'للاستفسارات المتعلقة بالشروط أو الخصوصية تواصل معنا عبر البريد: Info@aqoodpro.sa',
                icon: Icons.email_outlined,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegalLinkTile extends StatelessWidget {
  final String title;
  final String url;
  final IconData icon;
  final Future<void> Function(BuildContext context, String url) onTap;

  const _LegalLinkTile({
    required this.title,
    required this.url,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => onTap(context, url),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      shadows: const <BoxShadow>[],
      child: Row(
        children: <Widget>[
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(
                  url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    color: context.ejarzTheme.muted,
                    fontSize: context.sp(10.8),
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.open_in_new_rounded,
              color: context.ejarzTheme.muted, size: 18),
        ],
      ),
    );
  }
}

class _LegalSection extends StatelessWidget {
  final String title;
  final String body;

  const _LegalSection({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Text(
            body,
            style: TextStyle(
              color: context.ejarzTheme.muted,
              height: 1.8,
              fontSize: context.sp(13),
            ),
          ),
        ],
      ),
    );
  }
}

class SavedPropertiesScreen extends StatelessWidget {
  const SavedPropertiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('العقارات المحفوظة')),
      bottomNavigationBar: _accountBottomNavigation(context),
      body: SafeArea(
        child: ResponsiveContent(
          maxWidth: 700,
          child: Column(
            children: <Widget>[
              for (var i = 0;
                  i < controller.properties.length;
                  i++) ...<Widget>[
                _ManagedPropertyCard(property: controller.properties[i]),
                if (i < controller.properties.length - 1)
                  const SizedBox(height: 10),
              ],
              const SizedBox(height: 16),
              SecondaryButton(
                label: 'إضافة عقار',
                icon: Icons.add_home_work_outlined,
                onPressed: () => showAppSnackBar(
                  context,
                  'يمكن إضافة العقار تلقائيًا أثناء إنشاء عقد جديد.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SavedPartiesScreen extends StatelessWidget {
  const SavedPartiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الأطراف المحفوظة')),
      bottomNavigationBar: _accountBottomNavigation(context),
      body: SafeArea(
        child: ResponsiveContent(
          maxWidth: 700,
          child: Column(
            children: <Widget>[
              const _SavedParty(
                name: 'عبدالله العتيبي',
                type: 'مؤجر • هوية وطنية',
                mobile: '0500000001',
              ),
              const SizedBox(height: 10),
              const _SavedParty(
                name: 'شركة الواحة العقارية',
                type: 'مستأجر • منشأة',
                mobile: '0110000000',
              ),
              const SizedBox(height: 16),
              SecondaryButton(
                label: 'إضافة طرف',
                icon: Icons.person_add_alt_1_rounded,
                onPressed: () => showAppSnackBar(
                  context,
                  'يمكن حفظ الطرف أثناء تعبئة نموذج العقد.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SavedParty extends StatelessWidget {
  final String name;
  final String type;
  final String mobile;

  const _SavedParty({
    required this.name,
    required this.type,
    required this.mobile,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: <Widget>[
          const CircleAvatar(
            backgroundColor: AppColors.primaryLight,
            foregroundColor: AppColors.primary,
            child: Icon(Icons.person_outline_rounded),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(name, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(
                  '$type • $mobile',
                  style: TextStyle(
                    color: context.ejarzTheme.muted,
                    fontSize: context.sp(11.5),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
              onPressed: () {}, icon: const Icon(Icons.more_vert_rounded)),
        ],
      ),
    );
  }
}
