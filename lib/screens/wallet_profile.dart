import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_controller.dart';
import '../core/demo_config.dart';
import '../core/models.dart';
import '../core/property_management.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'contracts.dart';
import 'create_contract.dart';
import 'pricing.dart';

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
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const _PropertyEditorScreen(),
      ),
    );
  }
}

class _PropertyEditorScreen extends StatefulWidget {
  final PropertyRecord? existing;
  final PropertyRecord? parent;
  final UnitRecord? unit;

  const _PropertyEditorScreen({this.existing, this.parent, this.unit});

  @override
  State<_PropertyEditorScreen> createState() => _PropertyEditorScreenState();
}

class _PropertyEditorScreenState extends State<_PropertyEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  final _ownershipNumberKey = GlobalKey();
  final _ownershipDateKey = GlobalKey();
  final _streetKey = GlobalKey();
  final _buildingNumberKey = GlobalKey();
  final _additionalNumberKey = GlobalKey();
  final _postalCodeKey = GlobalKey();
  final _cityKey = GlobalKey();
  final _districtKey = GlobalKey();
  final _floorsKey = GlobalKey();
  final _totalUnitsKey = GlobalKey();
  final _unitsPerFloorKey = GlobalKey();
  final _unitNumberKey = GlobalKey();
  final _unitNameKey = GlobalKey();
  final _floorKey = GlobalKey();
  final _unitAreaKey = GlobalKey();
  final _roomsCountKey = GlobalKey();
  final _bathroomsCountKey = GlobalKey();
  final _hallsCountKey = GlobalKey();
  final _electricityMeterKey = GlobalKey();
  final _waterMeterKey = GlobalKey();
  final _acKey = GlobalKey<FormFieldState<bool>>();
  late final TextEditingController _title;
  late final TextEditingController _city;
  late final TextEditingController _district;
  late final TextEditingController _street;
  late final TextEditingController _buildingNumber;
  late final TextEditingController _additionalNumber;
  late final TextEditingController _postalCode;
  late final TextEditingController _ownershipNumber;
  late final TextEditingController _ownershipDate;
  late final TextEditingController _floors;
  late final TextEditingController _unitsPerFloor;
  late final TextEditingController _totalUnits;
  late final TextEditingController _unitNumber;
  late final TextEditingController _unitName;
  late final TextEditingController _floor;
  late final TextEditingController _unitArea;
  late final TextEditingController _roomsCount;
  late final TextEditingController _bathroomsCount;
  late final TextEditingController _hallsCount;
  late final TextEditingController _electricityMeter;
  late final TextEditingController _waterMeter;
  late final TextEditingController _gasMeter;
  late final TextEditingController _notes;
  String _ownershipType = 'صك إلكتروني';
  String _propertyType = 'عمارة';
  String _usage = 'سكن عوائل';
  String _unitType = 'شقة';
  String _furnishingStatus = 'غير مؤثثة';
  bool _maidRoom = false;
  bool _kitchen = true;
  bool _storage = false;
  bool _majlis = false;
  bool _acWindow = false;
  bool _acSplit = true;
  bool _acCentral = false;
  bool _privateParking = false;
  bool _saving = false;
  String _rentalMode = 'whole';
  final _batchCount = TextEditingController(text: '1');
  final List<_UnitIdentity> _batch = [];

  bool get _editingUnit => widget.parent != null;
  bool get _isBuilding => _propertyType == 'عمارة' || _propertyType == 'برج';
  bool get _separateBuilding =>
      !_editingUnit && _isBuilding && _rentalMode == 'units';
  bool get _multiple =>
      _editingUnit && widget.unit == null && _batch.length > 1;
  int get _unitLimit => (widget.parent?.remainingUnits ?? 1).clamp(0, 50);

  @override
  void initState() {
    super.initState();
    final existing = widget.parent ?? widget.existing;
    final data = widget.parent == null
        ? existing?.data
        : (widget.unit ?? UnitRecord.fromData(PropertyData()))
            .detailsFor(widget.parent!);
    final firstUnit =
        existing?.units.isNotEmpty == true ? existing!.units.first : null;
    _title = TextEditingController(
      text: _prefer(data?.buildingName, existing?.title ?? ''),
    );
    _city = TextEditingController(
      text: _prefer(data?.city, existing?.city ?? 'الرياض'),
    );
    _district = TextEditingController(
      text: _prefer(data?.district, existing?.district ?? ''),
    );
    _street = TextEditingController(text: data?.street ?? '');
    _buildingNumber = TextEditingController(text: data?.buildingNumber ?? '');
    _additionalNumber =
        TextEditingController(text: data?.additionalNumber ?? '');
    _postalCode = TextEditingController(text: data?.postalCode ?? '');
    _ownershipNumber =
        TextEditingController(text: data?.ownershipDocumentNumber ?? '');
    _ownershipDate =
        TextEditingController(text: data?.ownershipDocumentDate ?? '');
    _floors = TextEditingController(
      text: _prefer(data?.floorsCount, existing?.floors.toString() ?? '1'),
    );
    _unitsPerFloor = TextEditingController(
      text: data?.unitsPerFloor ?? '',
    );
    _totalUnits = TextEditingController(
        text:
            _prefer(data?.totalUnits, existing?.totalUnits.toString() ?? '1'));
    _unitNumber = TextEditingController(
      text: _prefer(data?.unitNumber, firstUnit?.number ?? ''),
    );
    _unitName = TextEditingController(
      text: _prefer(data?.unitName, firstUnit?.name ?? ''),
    );
    _floor = TextEditingController(
      text: _prefer(data?.floor, firstUnit?.floor ?? ''),
    );
    _unitArea = TextEditingController(
      text: _prefer(data?.area, firstUnit?.area.replaceAll(' م²', '') ?? ''),
    );
    _roomsCount = TextEditingController(text: _prefer(data?.roomsCount, '3'));
    _bathroomsCount =
        TextEditingController(text: _prefer(data?.bathroomsCount, '1'));
    _hallsCount = TextEditingController(text: _prefer(data?.hallsCount, '1'));
    _electricityMeter =
        TextEditingController(text: data?.electricityMeter ?? '');
    _waterMeter = TextEditingController(text: data?.waterMeter ?? '');
    _gasMeter = TextEditingController(text: data?.gasMeter ?? '');
    _notes = TextEditingController(text: data?.notes ?? '');
    _ownershipType = _prefer(data?.ownershipDocumentType, 'صك إلكتروني');
    _propertyType = _prefer(data?.propertyType, existing?.type ?? 'عمارة');
    _usage = _prefer(data?.propertyUsage, existing?.usage ?? 'سكن عوائل');
    _unitType = _prefer(data?.unitType, firstUnit?.type ?? 'شقة');
    _furnishingStatus = _prefer(data?.furnishingStatus, 'غير مؤثثة');
    _maidRoom = data?.maidRoom ?? false;
    _kitchen = data?.kitchen ?? true;
    _storage = data?.storage ?? false;
    _majlis = data?.majlis ?? false;
    _acWindow = data?.acWindow ?? false;
    _acSplit = data?.acSplit ?? true;
    _acCentral = data?.acCentral ?? false;
    _privateParking = data?.privateParking ?? false;
    _rentalMode = existing?.managesUnits == true ? 'units' : 'whole';
    if (_editingUnit && widget.unit == null) {
      _unitNumber.text = _nextUnitNumber(1);
      _unitName.text = '$_unitType ${_unitNumber.text}';
      _floor.text = '0';
    }
  }

  @override
  void dispose() {
    _batchCount.dispose();
    for (final identity in _batch) {
      identity.dispose();
    }
    _scrollController.dispose();
    _title.dispose();
    _city.dispose();
    _district.dispose();
    _street.dispose();
    _buildingNumber.dispose();
    _additionalNumber.dispose();
    _postalCode.dispose();
    _ownershipNumber.dispose();
    _ownershipDate.dispose();
    _floors.dispose();
    _unitsPerFloor.dispose();
    _totalUnits.dispose();
    _unitNumber.dispose();
    _unitName.dispose();
    _floor.dispose();
    _unitArea.dispose();
    _roomsCount.dispose();
    _bathroomsCount.dispose();
    _hallsCount.dispose();
    _electricityMeter.dispose();
    _waterMeter.dispose();
    _gasMeter.dispose();
    _notes.dispose();
    super.dispose();
  }

  String _prefer(String? value, String fallback) {
    final text = value?.trim() ?? '';
    return text.isEmpty || text == '-' ? fallback : text;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(_editingUnit
            ? (widget.unit == null ? 'إضافة وحدات' : 'تعديل الوحدة')
            : widget.existing == null
                ? 'إضافة عقار'
                : 'تعديل العقار'),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: ResponsiveContent(
                  maxWidth: 700,
                  padding: EdgeInsets.zero,
                  scrollable: false,
                  child: Form(
                    key: _formKey,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          if (!_editingUnit) ...<Widget>[
                            const SectionTitle(
                                title: 'نوع العقار',
                                icon: Icons.apartment_outlined),
                            const SizedBox(height: 10),
                            AppDropdownField(
                              label: 'نوع العقار',
                              value: _propertyType,
                              items: const [
                                'عمارة',
                                'برج',
                                'أرض',
                                'شقة',
                                'فيلا'
                              ],
                              icon: Icons.home_work_outlined,
                              onChanged: widget.existing?.managesUnits ==
                                          true &&
                                      widget.existing!.units.isNotEmpty
                                  ? null
                                  : (value) {
                                      if (widget.existing?.units.isNotEmpty ==
                                              true &&
                                          widget.existing!.managesUnits) {
                                        showAppSnackBar(context,
                                            'العقار مرتبط بوحدات؛ يمكن تعديل بياناته مع الحفاظ على نوعه.');
                                        return;
                                      }
                                      setState(() {
                                        _propertyType = value!;
                                      });
                                    },
                            ),
                            if (_isBuilding) ...<Widget>[
                              const SizedBox(height: 10),
                              AppDropdownField(
                                label: 'طريقة تأجير العمارة',
                                value: _rentalMode == 'units'
                                    ? 'وحدات مستقلة'
                                    : 'عمارة كاملة',
                                items: const ['عمارة كاملة', 'وحدات مستقلة'],
                                icon: Icons.account_tree_outlined,
                                onChanged: widget.existing?.units.isNotEmpty ==
                                        true
                                    ? null
                                    : (value) {
                                        if (widget.existing?.units.isNotEmpty ==
                                                true &&
                                            widget.existing!.managesUnits) {
                                          showAppSnackBar(context,
                                              'العمارة مرتبطة بوحدات مستقلة ولا يمكن تحويلها إلى عمارة كاملة.');
                                          return;
                                        }
                                        setState(() => _rentalMode =
                                            value == 'وحدات مستقلة'
                                                ? 'units'
                                                : 'whole');
                                      },
                              ),
                              const SizedBox(height: 10),
                              InfoBanner(
                                  text: _separateBuilding
                                      ? 'احفظ العمارة وعدد وحداتها، ثم أضف الوحدات ومواصفاتها من تفاصيل العمارة.'
                                      : 'سيُحفظ العقار كاملًا كوحدة واحدة قابلة للاختيار عند إنشاء العقد.'),
                              if (widget.existing?.units.isNotEmpty == true)
                                const Padding(
                                    padding: EdgeInsets.only(top: 8),
                                    child: Text(
                                        'طريقة التأجير ثابتة بعد تسجيل الوحدات للحفاظ على ارتباط بياناتها.')),
                            ],
                            const SizedBox(height: 16),
                          ],
                          if (_editingUnit) ...<Widget>[
                            AppPageHeader(
                                title: widget.parent!.title,
                                subtitle:
                                    'مسجل ${widget.parent!.units.length} من ${widget.parent!.totalUnits} وحدة • ${widget.parent!.floors} أدوار',
                                icon: Icons.apartment_outlined),
                            const SizedBox(height: 12),
                            if (widget.unit == null) ...<Widget>[
                              AppTextField(
                                  label: 'عدد الوحدات المراد إضافتها',
                                  hint: 'مثال: 5',
                                  controller: _batchCount,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly
                                  ],
                                  required: true,
                                  icon: Icons.library_add_outlined,
                                  validator: (v) => _integerValidator(v,
                                      min: 1, max: _unitLimit),
                                  onChanged: _updateBatch),
                              const SizedBox(height: 8),
                              InfoBanner(
                                  text:
                                      'أضف من 1 إلى $_unitLimit وحدة في هذه الدفعة. أدخل المواصفات المشتركة مرة واحدة، ثم راجع رقم ودور وعدادات كل وحدة قبل الحفظ.'),
                              const SizedBox(height: 14),
                            ],
                          ],
                          if (!_editingUnit) ...<Widget>[
                            Text(
                              'احفظ بيانات العقار والوحدة لاستخدامها لاحقًا في العقود.',
                              style: TextStyle(
                                color: context.ejarzTheme.muted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const SectionTitle(
                              title: 'بيانات الملكية',
                              icon: Icons.verified_outlined,
                            ),
                            const SizedBox(height: 10),
                            FieldGrid(
                              children: <Widget>[
                                AppDropdownField(
                                  label: 'نوع الإثبات',
                                  value: _ownershipType,
                                  items: const <String>[
                                    'صك إلكتروني',
                                    'تسجيل عيني'
                                  ],
                                  icon: Icons.fact_check_outlined,
                                  required: true,
                                  onChanged: (value) => setState(() =>
                                      _ownershipType = value ?? _ownershipType),
                                ),
                                AppTextField(
                                  key: _ownershipNumberKey,
                                  label: 'رقم الوثيقة',
                                  hint: 'أدخل رقم الوثيقة',
                                  controller: _ownershipNumber,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: <TextInputFormatter>[
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(20),
                                  ],
                                  icon: Icons.description_outlined,
                                  required: true,
                                  validator: _ownershipNumberValidator,
                                ),
                                AppTextField(
                                  key: _ownershipDateKey,
                                  label: 'تاريخ الوثيقة',
                                  hint: 'YYYY/MM/DD',
                                  controller: _ownershipDate,
                                  keyboardType: TextInputType.datetime,
                                  icon: Icons.date_range_outlined,
                                  required: true,
                                  validator: _ownershipDateValidator,
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            const SectionTitle(
                              title: 'بيانات العقار والعنوان',
                              icon: Icons.business_outlined,
                            ),
                            const SizedBox(height: 10),
                            AppTextField(
                              label: 'اسم العقار',
                              hint: 'مثال: عمارة الياسمين',
                              controller: _title,
                              icon: Icons.apartment_outlined,
                            ),
                            const SizedBox(height: 10),
                            FieldGrid(
                              children: <Widget>[
                                AppTextField(
                                  key: _streetKey,
                                  label: 'الشارع',
                                  hint: 'اسم الشارع',
                                  controller: _street,
                                  icon: Icons.signpost_outlined,
                                  required: true,
                                  validator: _requiredValidator,
                                ),
                                AppTextField(
                                  key: _buildingNumberKey,
                                  label: 'رقم المبنى',
                                  hint: '4 أرقام',
                                  controller: _buildingNumber,
                                  keyboardType: TextInputType.number,
                                  icon: Icons.numbers_rounded,
                                  required: true,
                                  validator: (value) =>
                                      _fixedDigitsValidator(value, 4),
                                ),
                                AppTextField(
                                  key: _additionalNumberKey,
                                  label: 'الرقم الإضافي',
                                  hint: '4 أرقام',
                                  controller: _additionalNumber,
                                  keyboardType: TextInputType.number,
                                  icon: Icons.add_box_outlined,
                                  required: true,
                                  validator: (value) =>
                                      _fixedDigitsValidator(value, 4),
                                ),
                                AppTextField(
                                  key: _postalCodeKey,
                                  label: 'الرمز البريدي',
                                  hint: '5 أرقام',
                                  controller: _postalCode,
                                  keyboardType: TextInputType.number,
                                  icon: Icons.markunread_mailbox_outlined,
                                  required: true,
                                  validator: (value) =>
                                      _fixedDigitsValidator(value, 5),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: AppTextField(
                                    key: _cityKey,
                                    label: 'المدينة',
                                    hint: 'الرياض',
                                    controller: _city,
                                    icon: Icons.location_city_outlined,
                                    required: true,
                                    validator: _requiredValidator,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: AppTextField(
                                    key: _districtKey,
                                    label: 'الحي',
                                    hint: 'العليا',
                                    controller: _district,
                                    icon: Icons.location_on_outlined,
                                    required: true,
                                    validator: _requiredValidator,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: <Widget>[
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
                                    onChanged: (value) => setState(
                                        () => _usage = value ?? _usage),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: AppTextField(
                                    key: _floorsKey,
                                    label: 'عدد الأدوار',
                                    hint: '1',
                                    controller: _floors,
                                    keyboardType: TextInputType.number,
                                    icon: Icons.layers_outlined,
                                    required: true,
                                    validator: (value) => _integerValidator(
                                      value,
                                      min: 1,
                                      max: 200,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (_separateBuilding)
                                  Expanded(
                                    child: AppTextField(
                                      key: _totalUnitsKey,
                                      label: 'إجمالي الوحدات',
                                      hint: '1',
                                      controller: _totalUnits,
                                      keyboardType: TextInputType.number,
                                      icon: Icons.numbers_outlined,
                                      required: true,
                                      validator: (value) => _integerValidator(
                                          value,
                                          min: widget.existing?.units.length
                                                  .clamp(1, 9999) ??
                                              1,
                                          max: 9999),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (_separateBuilding)
                              AppTextField(
                                key: _unitsPerFloorKey,
                                label: 'عدد الوحدات في الدور (اختياري)',
                                hint:
                                    'اتركه فارغًا إذا اختلف العدد بين الأدوار',
                                controller: _unitsPerFloor,
                                keyboardType: TextInputType.number,
                                icon: Icons.grid_view_outlined,
                                validator: (value) =>
                                    value?.trim().isEmpty == true
                                        ? null
                                        : _integerValidator(
                                            value,
                                            min: 1,
                                            max: 200,
                                          ),
                              ),
                            const SizedBox(height: 8),
                            const InfoBanner(
                                text:
                                    'عدد الأدوار يشمل الدور الأرضي. يبدأ ترقيم أدوار الوحدات من 0 للأرضي.'),
                          ],
                          if (!_separateBuilding) ...<Widget>[
                            const SizedBox(height: 14),
                            const SectionTitle(
                              title: 'بيانات الوحدة',
                              icon: Icons.home_outlined,
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: <Widget>[
                                if (!_multiple)
                                  Expanded(
                                    child: AppTextField(
                                      key: _unitNumberKey,
                                      label: 'رقم الوحدة',
                                      hint: '12',
                                      controller: _unitNumber,
                                      icon: Icons.tag_outlined,
                                      required: true,
                                      validator: _requiredValidator,
                                    ),
                                  ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: AppDropdownField(
                                    label: 'نوع الوحدة',
                                    value: _unitType,
                                    items: <String>[
                                      if (_isBuilding && !_editingUnit)
                                        _propertyType,
                                      'شقة',
                                      'استديو',
                                      'دور',
                                      'فيلا',
                                      'محل',
                                      'مستودع',
                                      'مكتب إداري'
                                    ],
                                    icon: Icons.meeting_room_outlined,
                                    onChanged: (value) => setState(
                                        () => _unitType = value ?? _unitType),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            FieldGrid(
                              children: <Widget>[
                                if (!_multiple)
                                  AppTextField(
                                    key: _unitNameKey,
                                    label: 'اسم الوحدة',
                                    hint: 'شقة 12',
                                    controller: _unitName,
                                    icon: Icons.drive_file_rename_outline,
                                    required: true,
                                    validator: _requiredValidator,
                                  ),
                                if (!_multiple)
                                  AppTextField(
                                    key: _floorKey,
                                    label: 'رقم الدور',
                                    hint: '1',
                                    controller: _floor,
                                    icon: Icons.layers_outlined,
                                    required: true,
                                    validator: _editingUnit
                                        ? (v) => _integerValidator(v,
                                            min: 0,
                                            max: widget.parent!.floors - 1)
                                        : _requiredValidator,
                                  ),
                                AppDropdownField(
                                  label: 'حالة التأثيث',
                                  value: _furnishingStatus,
                                  items: const <String>[
                                    'غير مؤثثة',
                                    'مؤثثة بأثاث جديد',
                                    'مؤثثة بأثاث مستخدم',
                                  ],
                                  icon: Icons.chair_outlined,
                                  onChanged: (value) => setState(() =>
                                      _furnishingStatus =
                                          value ?? _furnishingStatus),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            AppTextField(
                              key: _unitAreaKey,
                              label: 'مساحة الوحدة (م²)',
                              hint: '120',
                              controller: _unitArea,
                              keyboardType: TextInputType.number,
                              icon: Icons.square_foot_outlined,
                              required: true,
                              validator: _positiveNumberValidator,
                            ),
                            const SizedBox(height: 10),
                            FieldGrid(
                              children: <Widget>[
                                AppTextField(
                                  key: _roomsCountKey,
                                  label: 'عدد الغرف',
                                  hint: '3',
                                  controller: _roomsCount,
                                  keyboardType: TextInputType.number,
                                  icon: Icons.bed_outlined,
                                  required: true,
                                  validator: (value) => _integerValidator(
                                    value,
                                    min: 1,
                                    max: 50,
                                  ),
                                ),
                                AppTextField(
                                  key: _bathroomsCountKey,
                                  label: 'دورات المياه',
                                  hint: '1',
                                  controller: _bathroomsCount,
                                  keyboardType: TextInputType.number,
                                  icon: Icons.bathtub_outlined,
                                  required: true,
                                  validator: (value) => _integerValidator(
                                    value,
                                    min: 1,
                                    max: 50,
                                  ),
                                ),
                                AppTextField(
                                  key: _hallsCountKey,
                                  label: 'الصالات',
                                  hint: '1',
                                  controller: _hallsCount,
                                  keyboardType: TextInputType.number,
                                  icon: Icons.weekend_outlined,
                                  required: true,
                                  validator: (value) => _integerValidator(
                                    value,
                                    min: 0,
                                    max: 50,
                                  ),
                                ),
                                if (!_multiple)
                                  AppTextField(
                                    key: _electricityMeterKey,
                                    label: 'رقم عداد الكهرباء',
                                    hint: 'أدخل رقم العداد',
                                    controller: _electricityMeter,
                                    keyboardType: TextInputType.number,
                                    icon: Icons.bolt_outlined,
                                    required: !_editingUnit,
                                    validator: (value) => _editingUnit &&
                                            (value?.trim().isEmpty ?? true)
                                        ? null
                                        : _integerValidator(value, min: 1),
                                  ),
                                if (!_multiple)
                                  AppTextField(
                                    key: _waterMeterKey,
                                    label: 'رقم عداد المياه',
                                    hint: 'أدخل رقم العداد',
                                    controller: _waterMeter,
                                    keyboardType: TextInputType.number,
                                    icon: Icons.water_drop_outlined,
                                    required: !_editingUnit,
                                    validator: (value) => _editingUnit &&
                                            (value?.trim().isEmpty ?? true)
                                        ? null
                                        : _integerValidator(value, min: 1),
                                  ),
                                if (!_multiple)
                                  AppTextField(
                                    label: 'رقم عداد الغاز',
                                    hint: 'إن وجد',
                                    controller: _gasMeter,
                                    keyboardType: TextInputType.number,
                                    icon: Icons.local_fire_department_outlined,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            const SectionTitle(
                              title: 'مرافق الوحدة',
                              icon: Icons.widgets_outlined,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: <Widget>[
                                _featureChip(
                                    'غرفة خادمة',
                                    _maidRoom,
                                    (value) =>
                                        setState(() => _maidRoom = value)),
                                _featureChip(
                                    'مطبخ',
                                    _kitchen,
                                    (value) =>
                                        setState(() => _kitchen = value)),
                                _featureChip(
                                    'مخزن',
                                    _storage,
                                    (value) =>
                                        setState(() => _storage = value)),
                                _featureChip('مجلس', _majlis,
                                    (value) => setState(() => _majlis = value)),
                                _featureChip(
                                    'موقف خاص',
                                    _privateParking,
                                    (value) => setState(
                                        () => _privateParking = value)),
                              ],
                            ),
                            const SizedBox(height: 14),
                            const SectionTitle(
                              title: 'التكييف',
                              icon: Icons.ac_unit_rounded,
                            ),
                            const SizedBox(height: 8),
                            FormField<bool>(
                              key: _acKey,
                              initialValue: _hasAirConditioning,
                              builder: (field) => Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: <Widget>[
                                      _featureChip('شباك', _acWindow, (value) {
                                        setState(() => _acWindow = value);
                                        field.didChange(_hasAirConditioning);
                                      }),
                                      _featureChip('سبليت', _acSplit, (value) {
                                        setState(() => _acSplit = value);
                                        field.didChange(_hasAirConditioning);
                                      }),
                                      _featureChip('مركزي', _acCentral,
                                          (value) {
                                        setState(() => _acCentral = value);
                                        field.didChange(_hasAirConditioning);
                                      }),
                                    ],
                                  ),
                                  if (field.hasError) ...<Widget>[
                                    const SizedBox(height: 6),
                                    Text(
                                      field.errorText!,
                                      style: TextStyle(
                                        color:
                                            Theme.of(context).colorScheme.error,
                                        fontSize: context.sp(11.5),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            AppTextField(
                              label: 'ملاحظات على الوحدة',
                              hint: 'أي تفاصيل إضافية مهمة',
                              controller: _notes,
                              icon: Icons.notes_rounded,
                              maxLines: 3,
                            ),
                            if (_multiple) ...<Widget>[
                              const SizedBox(height: 18),
                              const SectionTitle(
                                  title:
                                      'مراجعة أرقام الوحدات والأدوار والعدادات',
                                  icon: Icons.fact_check_outlined),
                              const SizedBox(height: 10),
                              for (var i = 0; i < _batch.length; i++)
                                _identityCard(_batch[i], i),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: context.ejarzTheme.surface,
                border: Border(
                  top: BorderSide(color: context.ejarzTheme.border),
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: SizedBox(
                      width: double.infinity,
                      child: PrimaryButton(
                        label: _saving
                            ? 'جاري الحفظ...'
                            : _editingUnit
                                ? (widget.unit != null
                                    ? 'حفظ الوحدة'
                                    : _multiple
                                        ? 'إضافة ${_batch.length} وحدات'
                                        : 'إضافة الوحدة')
                                : 'حفظ العقار',
                        icon: Icons.save_outlined,
                        loading: _saving,
                        onPressed: _save,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _featureChip(
    String label,
    bool selected,
    ValueChanged<bool> onSelected,
  ) {
    return FilterChip(
      selected: selected,
      showCheckmark: false,
      backgroundColor: context.ejarzTheme.surface,
      selectedColor: AppColors.primary.withValues(alpha: 0.12),
      label: Text(
        label,
        style: TextStyle(
          color: selected ? AppColors.primaryDark : context.ejarzTheme.text,
          fontWeight: FontWeight.w800,
        ),
      ),
      avatar: Icon(
        selected ? Icons.check_circle_rounded : Icons.circle_outlined,
        size: 18,
        color: selected ? AppColors.primary : context.ejarzTheme.muted,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.72)
            : context.ejarzTheme.border,
        width: selected ? 1.4 : 1,
      ),
      onSelected: onSelected,
    );
  }

  String _nextUnitNumber(int ordinal) {
    final used = (widget.parent?.units ?? <UnitRecord>[])
        .map((u) => normalizedUnitNumber(u.number))
        .toSet();
    var number = 1;
    var remaining = ordinal;
    while (true) {
      if (!used.contains('$number') && --remaining == 0) return '$number';
      number++;
    }
  }

  void _updateBatch(String value) {
    final count = int.tryParse(value);
    if (count == null || count < 1 || count > _unitLimit) return;
    setState(() {
      while (_batch.length < count) {
        final number = _nextUnitNumber(_batch.length + 1);
        _batch.add(_UnitIdentity(number: number, name: '$_unitType $number'));
      }
      while (_batch.length > count) {
        _batch.removeLast().dispose();
      }
    });
  }

  Widget _identityCard(_UnitIdentity identity, int index) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: AppCard(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              Text('الوحدة ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              FieldGrid(children: [
                AppTextField(
                    label: 'رقم الوحدة',
                    hint: 'رقم فريد داخل العمارة',
                    controller: identity.number,
                    required: true,
                    validator: _requiredValidator,
                    icon: Icons.tag_outlined),
                AppTextField(
                    label: 'اسم الوحدة',
                    hint: 'اسم واضح للوحدة',
                    controller: identity.name,
                    required: true,
                    validator: _requiredValidator,
                    icon: Icons.home_outlined),
                AppTextField(
                    label: 'رقم الدور',
                    hint: '0 للأرضي',
                    controller: identity.floor,
                    required: true,
                    keyboardType: TextInputType.number,
                    icon: Icons.layers_outlined,
                    validator: (v) => _integerValidator(v,
                        min: 0, max: widget.parent!.floors - 1)),
                AppTextField(
                    label: 'عداد الكهرباء (اختياري)',
                    hint: 'إن وجد',
                    controller: identity.electricity,
                    keyboardType: TextInputType.number,
                    icon: Icons.bolt_outlined),
                AppTextField(
                    label: 'عداد المياه (اختياري)',
                    hint: 'إن وجد',
                    controller: identity.water,
                    keyboardType: TextInputType.number,
                    icon: Icons.water_drop_outlined),
                AppTextField(
                    label: 'عداد الغاز (اختياري)',
                    hint: 'إن وجد',
                    controller: identity.gas,
                    keyboardType: TextInputType.number,
                    icon: Icons.local_fire_department_outlined),
              ]),
            ])),
      );

  Future<void> _save() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToFirstInvalidField();
      });
      showAppSnackBar(
        context,
        'راجع الحقول الموضحة وأكمل بيانات العقار المطلوبة.',
      );
      return;
    }
    setState(() => _saving = true);
    final data = PropertyData()
      ..rentalMode = _rentalMode
      ..ownershipDocumentType = _ownershipType
      ..ownershipDocumentNumber = _ownershipNumber.text.trim()
      ..ownershipDocumentDate = _ownershipDate.text.trim()
      ..buildingName = _title.text.trim()
      ..city = _city.text.trim()
      ..district = _district.text.trim()
      ..street = _street.text.trim()
      ..buildingNumber = _buildingNumber.text.trim()
      ..additionalNumber = _additionalNumber.text.trim()
      ..postalCode = _postalCode.text.trim()
      ..propertyType = _propertyType
      ..propertyUsage = _usage
      ..floorsCount = _floors.text.trim().isEmpty ? '1' : _floors.text.trim()
      ..unitsPerFloor = _unitsPerFloor.text.trim()
      ..totalUnits =
          _totalUnits.text.trim().isEmpty ? '1' : _totalUnits.text.trim()
      ..unitNumber = _unitNumber.text.trim()
      ..unitName = _unitName.text.trim()
      ..unitType = _unitType
      ..floor = _floor.text.trim()
      ..area = _unitArea.text.trim()
      ..roomsCount = _roomsCount.text.trim()
      ..bathroomsCount = _bathroomsCount.text.trim()
      ..hallsCount = _hallsCount.text.trim()
      ..furnishingStatus = _furnishingStatus
      ..maidRoom = _maidRoom
      ..kitchen = _kitchen
      ..storage = _storage
      ..majlis = _majlis
      ..privateParking = _privateParking
      ..acWindow = _acWindow
      ..acSplit = _acSplit
      ..acCentral = _acCentral
      ..electricityMeter = _electricityMeter.text.trim()
      ..waterMeter = _waterMeter.text.trim()
      ..gasMeter = _gasMeter.text.trim()
      ..notes = _notes.text.trim();
    if (_separateBuilding) {
      data.unitNumber = '';
      data.unitName = '';
    } else if (!_editingUnit) {
      data.totalUnits = '1';
      data.rentalMode = 'whole';
      if (_isBuilding) data.unitType = _propertyType;
    }
    try {
      final controller = AppScope.of(context, listen: false);
      final parent = widget.parent;
      List<UnitRecord>? unitEdits;
      PropertyData propertyData = data;
      if (parent != null) {
        final current = controller.properties
            .firstWhere((p) => p.id == parent.id, orElse: () => parent);
        propertyData = PropertyData.copyOf(current.data ?? data)
          ..rentalMode = 'units';
        final status = widget.unit?.status ?? 'متاحة';
        unitEdits = _multiple
            ? _batch.map((identity) {
                final unit = PropertyData.copyOf(data)
                  ..unitNumber = identity.number.text.trim()
                  ..unitName = identity.name.text.trim()
                  ..floor = identity.floor.text.trim()
                  ..electricityMeter = identity.electricity.text.trim()
                  ..waterMeter = identity.water.text.trim()
                  ..gasMeter = identity.gas.text.trim();
                return UnitRecord.fromData(unit, status: status);
              }).toList()
            : [UnitRecord.fromData(data, status: status)];
      }
      final saved = await controller.saveProperty(
        propertyData,
        existing: parent ?? widget.existing,
        unitEdits: unitEdits,
        replacingNumber: widget.unit?.number ?? '',
      );
      final savedLocally = controller.isPropertyPendingSync(saved.id);
      if (!mounted) return;
      if (widget.existing == null && parent == null) {
        Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
            builder: (_) => _PropertyDetailsScreen(initialProperty: saved)));
      } else {
        Navigator.of(context).pop();
      }
      showAppSnackBar(
        context,
        savedLocally
            ? 'تم حفظ العقار محليًا وستتم مزامنته عند عودة الاتصال'
            : parent != null
                ? 'تم حفظ ${unitEdits!.length} وحدة بنجاح'
                : 'تم حفظ العقار بنجاح',
      );
    } catch (error) {
      if (mounted) {
        showAppSnackBar(
            context,
            error is StateError
                ? error.message.toString()
                : 'تعذر حفظ العقار الآن');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool get _hasAirConditioning => _acWindow || _acSplit || _acCentral;

  String? _requiredValidator(String? value) {
    return (value?.trim().isEmpty ?? true) ? 'هذا الحقل مطلوب' : null;
  }

  String? _ownershipNumberValidator(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'هذا الحقل مطلوب';
    if (RegExp(r'^\d{8,20}$').hasMatch(text)) return null;
    return 'أدخل رقم وثيقة صحيحًا من 8 إلى 20 رقمًا';
  }

  String? _ownershipDateValidator(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'هذا الحقل مطلوب';
    final date = _parsePropertyDate(text);
    if (date == null) return 'أدخل التاريخ بالصيغة YYYY/MM/DD';
    if (date.isAfter(DateTime.now())) {
      return 'لا يمكن أن يكون التاريخ مستقبليًا';
    }
    return null;
  }

  String? _fixedDigitsValidator(String? value, int length) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'هذا الحقل مطلوب';
    if (_fixedDigits(text, length) == null) {
      return 'يجب أن يتكون من $length أرقام';
    }
    return null;
  }

  String? _integerValidator(
    String? value, {
    required int min,
    int? max,
  }) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'هذا الحقل مطلوب';
    if (_positiveInt(text, min: min, max: max) == null) {
      if (max != null) return 'أدخل عددًا صحيحًا من $min إلى $max';
      return 'أدخل رقمًا صحيحًا لا يقل عن $min';
    }
    return null;
  }

  String? _positiveNumberValidator(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'هذا الحقل مطلوب';
    return _positiveNumber(text) == null ? 'أدخل رقمًا أكبر من صفر' : null;
  }

  void _scrollToFirstInvalidField() {
    final key = _firstInvalidFieldKey();
    final fieldContext = key?.currentContext;
    if (fieldContext == null) return;
    Scrollable.ensureVisible(
      fieldContext,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: 0.15,
    );
  }

  GlobalKey? _firstInvalidFieldKey() {
    final ownershipDate = _parsePropertyDate(_ownershipDate.text);
    final fields = <MapEntry<GlobalKey, bool>>[
      MapEntry(
        _ownershipNumberKey,
        _ownershipNumberValidator(_ownershipNumber.text) != null,
      ),
      MapEntry(
        _ownershipDateKey,
        _ownershipDate.text.trim().isEmpty ||
            ownershipDate == null ||
            ownershipDate.isAfter(DateTime.now()),
      ),
      MapEntry(_streetKey, _street.text.trim().isEmpty),
      MapEntry(
          _buildingNumberKey, _fixedDigits(_buildingNumber.text, 4) == null),
      MapEntry(
        _additionalNumberKey,
        _fixedDigits(_additionalNumber.text, 4) == null,
      ),
      MapEntry(_postalCodeKey, _fixedDigits(_postalCode.text, 5) == null),
      MapEntry(_cityKey, _city.text.trim().isEmpty),
      MapEntry(_districtKey, _district.text.trim().isEmpty),
      MapEntry(
          _floorsKey, _positiveInt(_floors.text, min: 1, max: 200) == null),
      MapEntry(
        _totalUnitsKey,
        _positiveInt(_totalUnits.text, min: 1, max: 9999) == null,
      ),
      MapEntry(
        _unitsPerFloorKey,
        _unitsPerFloor.text.trim().isNotEmpty &&
            _positiveInt(_unitsPerFloor.text, min: 1, max: 200) == null,
      ),
      MapEntry(_unitNumberKey, _unitNumber.text.trim().isEmpty),
      MapEntry(_unitNameKey, _unitName.text.trim().isEmpty),
      MapEntry(_floorKey, _floor.text.trim().isEmpty),
      MapEntry(_unitAreaKey, _positiveNumber(_unitArea.text) == null),
      MapEntry(
        _roomsCountKey,
        _positiveInt(_roomsCount.text, min: 1, max: 50) == null,
      ),
      MapEntry(
        _bathroomsCountKey,
        _positiveInt(_bathroomsCount.text, min: 1, max: 50) == null,
      ),
      MapEntry(
        _hallsCountKey,
        _positiveInt(_hallsCount.text, min: 0, max: 50) == null,
      ),
      MapEntry(
        _electricityMeterKey,
        _positiveInt(_electricityMeter.text, min: 1) == null,
      ),
      MapEntry(
        _waterMeterKey,
        _positiveInt(_waterMeter.text, min: 1) == null,
      ),
      MapEntry(_acKey, !_hasAirConditioning),
    ];
    for (final field in fields) {
      if (field.value && field.key.currentContext != null) return field.key;
    }
    return null;
  }

  int? _positiveInt(String value, {required int min, int? max}) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed < min || (max != null && parsed > max)) {
      return null;
    }
    return parsed;
  }

  int? _fixedDigits(String value, int length) {
    final text = value.trim();
    return RegExp('^\\d{$length}\$').hasMatch(text) ? int.parse(text) : null;
  }

  double? _positiveNumber(String value) {
    final parsed = double.tryParse(value.trim().replaceAll(',', ''));
    return parsed != null && parsed > 0 ? parsed : null;
  }

  DateTime? _parsePropertyDate(String value) {
    final parts = value.trim().replaceAll('-', '/').split('/');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }
}

class _UnitIdentity {
  final TextEditingController number;
  final TextEditingController name;
  final floor = TextEditingController(text: '0');
  final electricity = TextEditingController();
  final water = TextEditingController();
  final gas = TextEditingController();
  _UnitIdentity({required String number, required String name})
      : number = TextEditingController(text: number),
        name = TextEditingController(text: name);
  void dispose() {
    for (final field in [number, name, floor, electricity, water, gas]) {
      field.dispose();
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _PropertyDetailsScreen(initialProperty: property),
      ),
    );
  }
}

class _PropertyDetailsScreen extends StatelessWidget {
  final PropertyRecord initialProperty;

  const _PropertyDetailsScreen({required this.initialProperty});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    var property = initialProperty;
    for (final item in controller.properties) {
      if (item.id == initialProperty.id) {
        property = item;
        break;
      }
    }
    final details = property.data;

    return Scaffold(
      appBar: const DetailAppBar(title: 'تفاصيل العقار'),
      bottomNavigationBar: _accountBottomNavigation(context),
      body: SafeArea(
        child: ResponsiveContent(
          maxWidth: 700,
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AppPageHeader(
                title: property.title,
                subtitle: '${property.location} • ${property.type}',
                icon: Icons.apartment_outlined,
              ),
              if (property.managesUnits) ...<Widget>[
                const SizedBox(height: 14),
                AppCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      Text(
                          'وحدات العمارة: ${property.units.length} من ${property.totalUnits}',
                          style: const TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                          value: property.totalUnits == 0
                              ? 0
                              : property.units.length / property.totalUnits),
                      const SizedBox(height: 10),
                      Text(property.remainingUnits > 0
                          ? 'يمكنك إضافة ${property.remainingUnits} وحدة أخرى، منفردة أو كمجموعة متطابقة.'
                          : 'اكتملت إضافة جميع الوحدات. يمكنك عرض أو تعديل كل وحدة أدناه.'),
                      if (property.remainingUnits > 0) ...[
                        const SizedBox(height: 12),
                        PrimaryButton(
                            label: 'إضافة وحدات للعمارة',
                            icon: Icons.add_home_outlined,
                            onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                    builder: (_) => _PropertyEditorScreen(
                                        parent: property)))),
                      ],
                    ])),
                const SizedBox(height: 12),
                for (final unit in property.units)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (_) => _UnitDetailsScreen(
                                    propertyId: property.id,
                                    initialUnit: unit))),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _UnitPreview(unit: unit),
                              const SizedBox(height: 6),
                              Text(
                                  'رقم ${unit.number} • ${unit.area.replaceAll(' م²', '')} م²',
                                  style: TextStyle(
                                      color: context.ejarzTheme.muted)),
                              if (unit.data != null)
                                Text(
                                    '${unit.data!.roomsCount} غرف • ${unit.data!.hallsCount} صالات • ${unit.data!.bathroomsCount} دورات مياه'),
                            ])),
                  ),
              ],
              const SizedBox(height: 14),
              const SectionTitle(
                title: 'بيانات العقار',
                icon: Icons.business_outlined,
              ),
              const SizedBox(height: 8),
              _propertyDetailsCard(<Widget>[
                _PropertyDetailLine(label: 'اسم العقار', value: property.title),
                _PropertyDetailLine(
                  label: 'مصدر العقار',
                  value: details == null ? '-' : _dash(details.propertySource),
                ),
                _PropertyDetailLine(label: 'نوع العقار', value: property.type),
                _PropertyDetailLine(label: 'الاستخدام', value: property.usage),
                _PropertyDetailLine(
                  label: 'عدد الأدوار',
                  value: '${property.floors}',
                ),
                _PropertyDetailLine(
                  label: 'الوحدات في الدور',
                  value: details == null ? '-' : _dash(details.unitsPerFloor),
                ),
                _PropertyDetailLine(
                  label: 'إجمالي الوحدات',
                  value: '${property.totalUnits}',
                ),
              ]),
              const SizedBox(height: 14),
              const SectionTitle(
                title: 'بيانات الملكية',
                icon: Icons.verified_outlined,
              ),
              const SizedBox(height: 8),
              _propertyDetailsCard(<Widget>[
                _PropertyDetailLine(
                  label: 'نوع الإثبات',
                  value: details == null
                      ? '-'
                      : _dash(details.ownershipDocumentType),
                ),
                _PropertyDetailLine(
                  label: 'رقم الوثيقة',
                  value: details == null
                      ? '-'
                      : _dash(details.ownershipDocumentNumber),
                ),
                _PropertyDetailLine(
                  label: 'تاريخ الوثيقة',
                  value: details == null
                      ? '-'
                      : _dash(details.ownershipDocumentDate),
                ),
              ]),
              const SizedBox(height: 14),
              const SectionTitle(
                title: 'العنوان الوطني',
                icon: Icons.location_on_outlined,
              ),
              const SizedBox(height: 8),
              _propertyDetailsCard(<Widget>[
                _PropertyDetailLine(
                  label: 'المدينة',
                  value: details == null ? property.city : _dash(details.city),
                ),
                _PropertyDetailLine(
                  label: 'الحي',
                  value: details == null
                      ? property.district
                      : _dash(details.district),
                ),
                _PropertyDetailLine(
                  label: 'الشارع',
                  value: details == null ? '-' : _dash(details.street),
                ),
                _PropertyDetailLine(
                  label: 'رقم المبنى',
                  value: details == null ? '-' : _dash(details.buildingNumber),
                ),
                _PropertyDetailLine(
                  label: 'الرقم الإضافي',
                  value:
                      details == null ? '-' : _dash(details.additionalNumber),
                ),
                _PropertyDetailLine(
                  label: 'الرمز البريدي',
                  value: details == null ? '-' : _dash(details.postalCode),
                ),
              ]),
              const SizedBox(height: 14),
              if (!property.managesUnits) ...<Widget>[
                const SectionTitle(
                  title: 'بيانات الوحدة',
                  icon: Icons.home_outlined,
                ),
                const SizedBox(height: 8),
                _propertyDetailsCard(<Widget>[
                  _PropertyDetailLine(
                    label: 'رقم الوحدة',
                    value: details == null ? '-' : _dash(details.unitNumber),
                  ),
                  _PropertyDetailLine(
                    label: 'اسم الوحدة',
                    value: details == null ? '-' : _dash(details.unitName),
                  ),
                  _PropertyDetailLine(
                    label: 'نوع الوحدة',
                    value: details == null ? '-' : _dash(details.unitType),
                  ),
                  _PropertyDetailLine(
                    label: 'الدور',
                    value: details == null ? '-' : _dash(details.floor),
                  ),
                  _PropertyDetailLine(
                    label: 'المساحة',
                    value: details == null ? '-' : '${_dash(details.area)} م²',
                  ),
                  _PropertyDetailLine(
                    label: 'حالة التأثيث',
                    value:
                        details == null ? '-' : _dash(details.furnishingStatus),
                  ),
                  _PropertyDetailLine(
                    label: 'عدد الغرف',
                    value: details == null ? '-' : _dash(details.roomsCount),
                  ),
                  _PropertyDetailLine(
                    label: 'دورات المياه',
                    value:
                        details == null ? '-' : _dash(details.bathroomsCount),
                  ),
                  _PropertyDetailLine(
                    label: 'الصالات',
                    value: details == null ? '-' : _dash(details.hallsCount),
                  ),
                ]),
                const SizedBox(height: 14),
                const SectionTitle(
                  title: 'المرافق والعدادات',
                  icon: Icons.tune_outlined,
                ),
                const SizedBox(height: 8),
                _propertyDetailsCard(<Widget>[
                  _PropertyDetailLine(
                    label: 'المطبخ',
                    value: details == null ? '-' : _yesNo(details.kitchen),
                  ),
                  _PropertyDetailLine(
                    label: 'غرفة خادمة',
                    value: details == null ? '-' : _yesNo(details.maidRoom),
                  ),
                  _PropertyDetailLine(
                    label: 'مخزن',
                    value: details == null ? '-' : _yesNo(details.storage),
                  ),
                  _PropertyDetailLine(
                    label: 'مجلس',
                    value: details == null ? '-' : _yesNo(details.majlis),
                  ),
                  _PropertyDetailLine(
                    label: 'موقف خاص',
                    value:
                        details == null ? '-' : _yesNo(details.privateParking),
                  ),
                  _PropertyDetailLine(
                    label: 'تكييف شباك',
                    value: details == null ? '-' : _yesNo(details.acWindow),
                  ),
                  _PropertyDetailLine(
                    label: 'تكييف سبليت',
                    value: details == null ? '-' : _yesNo(details.acSplit),
                  ),
                  _PropertyDetailLine(
                    label: 'تكييف مركزي',
                    value: details == null ? '-' : _yesNo(details.acCentral),
                  ),
                  _PropertyDetailLine(
                    label: 'عداد الكهرباء',
                    value:
                        details == null ? '-' : _dash(details.electricityMeter),
                  ),
                  _PropertyDetailLine(
                    label: 'عداد المياه',
                    value: details == null ? '-' : _dash(details.waterMeter),
                  ),
                  _PropertyDetailLine(
                    label: 'عداد الغاز',
                    value: details == null ? '-' : _dash(details.gasMeter),
                  ),
                  _PropertyDetailLine(
                    label: 'الملاحظات',
                    value: details == null ? '-' : _dash(details.notes),
                  ),
                ]),
              ],
              if (!property.managesUnits &&
                  property.units.isNotEmpty) ...<Widget>[
                const SizedBox(height: 14),
                const SectionTitle(title: 'الوحدات المرتبطة'),
                const SizedBox(height: 8),
                for (final unit in property.units) _UnitPreview(unit: unit),
              ],
              const SizedBox(height: 16),
              SecondaryButton(
                label: 'تعديل العقار',
                icon: Icons.edit_outlined,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _PropertyEditorScreen(existing: property),
                  ),
                ),
              ),
              const SizedBox(height: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _propertyDetailsCard(List<Widget> children) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      shadows: const <BoxShadow>[],
      child: Column(children: children),
    );
  }

  String _dash(String value) {
    final text = value.trim();
    return text.isEmpty ? '-' : text;
  }

  String _yesNo(bool value) => value ? 'نعم' : 'لا';
}

class _UnitDetailsScreen extends StatelessWidget {
  final String propertyId;
  final UnitRecord initialUnit;
  const _UnitDetailsScreen(
      {required this.propertyId, required this.initialUnit});

  @override
  Widget build(BuildContext context) {
    final property =
        AppScope.of(context).properties.firstWhere((p) => p.id == propertyId);
    final unit = property.units.firstWhere(
        (u) => u.number == initialUnit.number,
        orElse: () => initialUnit);
    final data = unit.detailsFor(property);
    final features = <String, bool>{
      'مطبخ': data.kitchen,
      'مجلس': data.majlis,
      'غرفة خادمة': data.maidRoom,
      'مخزن': data.storage,
      'موقف خاص': data.privateParking,
      'تكييف شباك': data.acWindow,
      'تكييف سبليت': data.acSplit,
      'تكييف مركزي': data.acCentral,
    };
    final values = <String, String>{
      'العمارة': property.title,
      'العنوان': data.displayAddress,
      'رقم الوحدة': unit.number,
      'اسم الوحدة': unit.name,
      'نوع الوحدة': unit.type,
      'رقم الدور': unit.floor,
      'المساحة': '${data.area} م²',
      'عدد الغرف': data.roomsCount,
      'الصالات': data.hallsCount,
      'دورات المياه': data.bathroomsCount,
      'التأثيث': data.furnishingStatus,
      for (final feature in features.entries)
        feature.key: feature.value ? 'نعم' : 'لا',
      'عداد الكهرباء': data.electricityMeter,
      'عداد المياه': data.waterMeter,
      'عداد الغاز': data.gasMeter,
      'الملاحظات': data.notes,
    };
    return Scaffold(
      appBar: AppBar(title: Text('تفاصيل ${unit.name}')),
      body: SafeArea(
          child: ResponsiveContent(
              maxWidth: 700,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppPageHeader(
                      title: unit.name,
                      subtitle: property.title,
                      icon: Icons.home_work_outlined),
                  const SizedBox(height: 14),
                  AppCard(
                      child: Column(children: [
                    for (final entry in values.entries)
                      _PropertyDetailLine(
                          label: entry.key,
                          value: entry.value.trim().isEmpty
                              ? 'غير مضاف'
                              : entry.value)
                  ])),
                  const SizedBox(height: 16),
                  SecondaryButton(
                      label: 'تعديل بيانات الوحدة',
                      icon: Icons.edit_outlined,
                      onPressed: () => Navigator.of(context).pushReplacement(
                          MaterialPageRoute<void>(
                              builder: (_) => _PropertyEditorScreen(
                                  parent: property, unit: unit)))),
                  if (unit.isAvailable) ...[
                    const SizedBox(height: 10),
                    PrimaryButton(
                        label: 'إنشاء عقد لهذه الوحدة',
                        icon: Icons.note_add_outlined,
                        onPressed: () {
                          final draft = createContractDraftForType(
                              property.usage.contains('تجاري')
                                  ? ContractType.commercial
                                  : ContractType.residential)
                            ..property = data;
                          Navigator.of(context).push(MaterialPageRoute<void>(
                              builder: (_) => CreateContractScreen(
                                  initialDraft: draft, initialStep: 0)));
                        }),
                  ],
                ],
              ))),
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

class _PropertyDetailLine extends StatelessWidget {
  final String label;
  final String value;

  const _PropertyDetailLine({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: TextStyle(
                color: context.ejarzTheme.muted,
                fontSize: context.sp(11.5),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
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
            unit.isAvailable ? 'متاحة' : unit.status,
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

class WalletStandaloneScreen extends StatelessWidget {
  const WalletStandaloneScreen({super.key});

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
              menuIcon: Icons.arrow_forward_rounded,
              placeMenuAtStart: true,
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
                        builder: (_) => const WalletStandaloneScreen(),
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
                        builder: (_) => const WalletStandaloneScreen(),
                      ),
                    ),
                  ),
                  const Divider(),
                  _ProfileRow(
                      icon: Icons.receipt_long_outlined,
                      title: 'أسعار العقود',
                      subtitle: 'السكني والتجاري • شاملة رسوم إيجار',
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => const PricingScreen()))),
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
        if (item.actionType == 'payments') {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const WalletStandaloneScreen(),
            ),
          );
          return;
        }
        if (item.actionType == 'profile') {
          Navigator.of(context).popUntil((route) => route.isFirst);
          controller.setNavigationIndex(3);
          return;
        }
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
  final String initialSubject;
  final String initialMessage;
  final String initialPriority;

  const SupportScreen({
    super.key,
    this.initialTicketId,
    this.initialSubject = '',
    this.initialMessage = '',
    this.initialPriority = 'عادية',
  });

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  late final TextEditingController _subject;
  late final TextEditingController _message;
  late String _priority;
  bool _sending = false;
  bool _openedInitialTicket = false;

  @override
  void initState() {
    super.initState();
    _subject = TextEditingController(text: widget.initialSubject);
    _message = TextEditingController(text: widget.initialMessage);
    _priority = widget.initialPriority == 'عالية' ? 'عالية' : 'عادية';
  }

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
                  if (kEjarzDemoMode) {
                    await _showDemoSupportNotice(context);
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

  Future<void> _showDemoSupportNotice(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.support_agent_rounded,
                color: AppColors.primary,
                size: 38,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'الدعم الفني غير متاح في النسخة التجريبية',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              'هذه الواجهة مخصصة لاستعراض تجربة إرسال طلبات الدعم. لن يتم إرسال أو حفظ هذا الطلب حاليًا، وسيتم تفعيل الخدمة في النسخة التشغيلية.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.ejarzTheme.muted,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 18),
            PrimaryButton(
              label: 'حسنًا، فهمت',
              icon: Icons.check_rounded,
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
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

class LegalScreen extends StatefulWidget {
  const LegalScreen({super.key});

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  bool _deletingAccount = false;

  Future<void> _open(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      showAppSnackBar(context, 'تعذر فتح الرابط الآن');
    }
  }

  Future<void> _requestAccountDeletion(BuildContext context) async {
    if (_deletingAccount) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _AccountDeletionConfirmationDialog(),
    );
    if (confirmed != true || !context.mounted) return;

    final controller = AppScope.of(context, listen: false);
    setState(() => _deletingAccount = true);
    try {
      await controller.deleteOwnAccount();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.check_circle_rounded,
              color: AppColors.primary, size: 42),
          title: const Text('تم حذف الحساب'),
          content: const Text(
            kEjarzDemoMode
                ? 'اكتمل حذف حساب التجربة وبياناته التجريبية. سيتم الآن تسجيل خروجك، ويمكنك بدء تجربة جديدة لاحقًا.'
                : 'اكتمل حذف حسابك والبيانات المرتبطة به من الخدمة. سيتم الآن تسجيل خروجك.',
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('تم'),
            ),
          ],
        ),
      );
      await controller.completeDeletedAccountSignOut();
    } catch (error) {
      if (!context.mounted) return;
      showAppSnackBar(
        context,
        'تعذر إكمال حذف الحساب الآن. لم يُغلق الحساب ويمكنك إعادة المحاولة.',
      );
    } finally {
      if (mounted) setState(() => _deletingAccount = false);
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
              _LegalActionTile(
                title: _deletingAccount
                    ? 'جارٍ حذف الحساب والبيانات...'
                    : 'حذف الحساب والبيانات نهائيًا',
                subtitle: _deletingAccount
                    ? 'يرجى عدم إغلاق التطبيق حتى اكتمال العملية'
                    : kEjarzDemoMode
                        ? 'يحذف حساب التجربة الحالي وبياناته التجريبية فقط'
                        : 'حذف مباشر وآمن من داخل التطبيق بعد التأكيد',
                icon: Icons.delete_outline_rounded,
                loading: _deletingAccount,
                onTap: _requestAccountDeletion,
              ),
              const SizedBox(height: 8),
              _LegalLinkTile(
                title: 'فتح صفحة حذف الحساب',
                url: controller.legalAccountDeletionUrl,
                icon: Icons.open_in_new_rounded,
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

class _AccountDeletionConfirmationDialog extends StatefulWidget {
  const _AccountDeletionConfirmationDialog();

  @override
  State<_AccountDeletionConfirmationDialog> createState() =>
      _AccountDeletionConfirmationDialogState();
}

class _AccountDeletionConfirmationDialogState
    extends State<_AccountDeletionConfirmationDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _canDelete = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('حذف الحساب نهائيًا'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              kEjarzDemoMode
                  ? 'سيُحذف حساب التجربة الحالي وكل العقود والعقارات والمرفقات والبيانات التجريبية المرتبطة به. يمكنك بدء تجربة جديدة بعد تسجيل الدخول مرة أخرى.'
                  : 'سيُحذف حسابك وملفك الشخصي وعقودك وعقاراتك ومرفقاتك وإشعاراتك وطلبات الدعم وبيانات الدفع المرتبطة بالحساب. لا يمكن التراجع عن هذا الإجراء.',
            ),
            const SizedBox(height: 14),
            const Text('للتأكيد اكتب كلمة: حذف'),
            const SizedBox(height: 7),
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(hintText: 'حذف'),
              onChanged: (value) {
                setState(() => _canDelete = value.trim() == 'حذف');
              },
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _canDelete ? () => Navigator.of(context).pop(true) : null,
          style: FilledButton.styleFrom(backgroundColor: AppColors.red),
          child: const Text('حذف نهائي'),
        ),
      ],
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

class _LegalActionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool loading;
  final Future<void> Function(BuildContext context) onTap;

  const _LegalActionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.loading = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: loading ? null : () => onTap(context),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      shadows: const <BoxShadow>[],
      child: Row(
        children: <Widget>[
          if (loading)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            )
          else
            Icon(icon, color: AppColors.red, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: context.ejarzTheme.muted,
                    fontSize: context.sp(10.8),
                  ),
                ),
              ],
            ),
          ),
          if (!loading)
            Icon(Icons.chevron_left_rounded,
                color: context.ejarzTheme.muted, size: 20),
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
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const _PropertyEditorScreen(),
                  ),
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
