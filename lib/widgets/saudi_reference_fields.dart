import 'package:flutter/material.dart';

import '../core/saudi_reference_data.dart';
import '../core/theme.dart';
import 'common.dart';

class SaudiLocationFields extends StatefulWidget {
  final String city;
  final String district;
  final ValueChanged<String> onCityChanged;
  final ValueChanged<String> onDistrictChanged;
  final SaudiReferenceCatalog? catalog;

  const SaudiLocationFields({
    super.key,
    required this.city,
    required this.district,
    required this.onCityChanged,
    required this.onDistrictChanged,
    this.catalog,
  });

  @override
  State<SaudiLocationFields> createState() => _SaudiLocationFieldsState();
}

class _SaudiLocationFieldsState extends State<SaudiLocationFields> {
  late final Future<SaudiReferenceCatalog> _catalogFuture =
      SaudiReferenceCatalog.load();
  int? _selectedCityId;

  SaudiCity? _selectedCity(SaudiReferenceCatalog catalog) {
    final selected = catalog.cityById(_selectedCityId);
    if (selected != null &&
        normalizeSaudiLocation(selected.name) ==
            normalizeSaudiLocation(widget.city)) {
      return selected;
    }
    return catalog.resolveCity(
      widget.city,
      districtName: widget.district,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SaudiReferenceCatalog>(
      future: widget.catalog == null ? _catalogFuture : null,
      initialData: widget.catalog,
      builder: (context, snapshot) {
        final catalog = snapshot.data;
        final city = catalog == null ? null : _selectedCity(catalog);
        final districts = city == null
            ? const <SaudiDistrict>[]
            : catalog!.districtsForCity(city.id);
        return FieldGrid(
          children: <Widget>[
            _LookupFormField(
              label: 'المدينة',
              value: widget.city,
              hint: snapshot.hasError ? 'تعذر تحميل المدن' : 'اختر المدينة',
              icon: Icons.location_city_outlined,
              loading: catalog == null && !snapshot.hasError,
              required: true,
              onTap: catalog == null ? null : () => _pickCity(catalog),
            ),
            _LookupFormField(
              label: 'الحي',
              value: widget.district,
              hint: city == null
                  ? 'اختر المدينة أولًا'
                  : districts.isEmpty
                      ? 'أدخل اسم الحي'
                      : 'اختر الحي',
              icon: Icons.location_on_outlined,
              loading: catalog == null && !snapshot.hasError,
              required: true,
              onTap: catalog == null || city == null
                  ? null
                  : () => _pickDistrict(city, districts),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickCity(SaudiReferenceCatalog catalog) async {
    final currentCity = _selectedCity(catalog);
    final result = await _showSearchPicker<SaudiCity>(
      context: context,
      title: 'اختر المدينة',
      searchHint: 'ابحث باسم المدينة أو المنطقة',
      currentValue: currentCity,
      options: catalog.cities
          .map(
            (city) => _SearchOption<SaudiCity>(
              value: city,
              title: city.name,
              subtitle: saudiRegionNames[city.regionId],
              searchText:
                  '${city.name} ${saudiRegionNames[city.regionId] ?? ''}',
            ),
          )
          .toList(growable: false),
    );
    final selected = result?.value;
    if (!mounted || selected == null) return;

    final districtStillMatches = catalog.districtsForCity(selected.id).any(
          (district) =>
              normalizeSaudiLocation(district.name) ==
              normalizeSaudiLocation(widget.district),
        );
    setState(() => _selectedCityId = selected.id);
    widget.onCityChanged(selected.name);
    if (!districtStillMatches && widget.district.trim().isNotEmpty) {
      widget.onDistrictChanged('');
    }
  }

  Future<void> _pickDistrict(
    SaudiCity city,
    List<SaudiDistrict> districts,
  ) async {
    if (districts.isEmpty) {
      final manual = await _showManualValueDialog(
        context,
        title: 'إدخال الحي',
        initialValue: widget.district,
      );
      if (manual != null) widget.onDistrictChanged(manual);
      return;
    }

    SaudiDistrict? current;
    for (final district in districts) {
      if (normalizeSaudiLocation(district.name) ==
          normalizeSaudiLocation(widget.district)) {
        current = district;
        break;
      }
    }
    final result = await _showSearchPicker<SaudiDistrict>(
      context: context,
      title: 'أحياء ${city.name}',
      searchHint: 'ابح باسم الحي',
      currentValue: current,
      allowManual: true,
      options: districts
          .map(
            (district) => _SearchOption<SaudiDistrict>(
              value: district,
              title: district.name,
              searchText: district.name,
            ),
          )
          .toList(growable: false),
    );
    if (!mounted || result == null) return;
    if (result.manual) {
      final manual = await _showManualValueDialog(
        context,
        title: 'إدخال حي غير مدرج',
        initialValue: widget.district,
      );
      if (manual != null) widget.onDistrictChanged(manual);
      return;
    }
    if (result.value != null) {
      widget.onDistrictChanged(result.value!.name);
    }
  }
}

class SaudiBankField extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const SaudiBankField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _LookupFormField(
      label: 'اسم البنك',
      value: value,
      hint: 'اختر البنك',
      icon: Icons.account_balance_outlined,
      required: true,
      onTap: () async {
        final result = await _showSearchPicker<String>(
          context: context,
          title: 'اختر البنك',
          searchHint: 'ابح باسم البنك',
          currentValue: value,
          allowManual: true,
          options: saudiLicensedBanks
              .map(
                (bank) => _SearchOption<String>(
                  value: bank,
                  title: bank,
                  searchText: bank,
                ),
              )
              .toList(growable: false),
        );
        if (!context.mounted || result == null) return;
        if (result.manual) {
          final manual = await _showManualValueDialog(
            context,
            title: 'إدخال اسم بنك آخر',
            initialValue: value,
          );
          if (manual != null) onChanged(manual);
          return;
        }
        if (result.value != null) onChanged(result.value!);
      },
    );
  }
}

class _LookupFormField extends StatelessWidget {
  final String label;
  final String value;
  final String hint;
  final IconData icon;
  final VoidCallback? onTap;
  final bool required;
  final bool loading;

  const _LookupFormField({
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    required this.onTap,
    this.required = false,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      key: ValueKey<String>('$label::$value::$loading'),
      initialValue: value,
      validator:
          required && value.trim().isEmpty ? (_) => 'هذا الحقل مطلوب' : null,
      builder: (field) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          RichText(
            text: TextSpan(
              style: TextStyle(
                color: context.ejarzTheme.text,
                fontSize: context.sp(12.3),
                fontWeight: FontWeight.w700,
              ),
              children: <InlineSpan>[
                TextSpan(text: label),
                if (required)
                  const TextSpan(
                    text: ' *',
                    style: TextStyle(color: AppColors.red),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: InputDecorator(
              isEmpty: value.trim().isEmpty,
              decoration: InputDecoration(
                errorText: field.errorText,
                suffixIcon: loading
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : Icon(icon, size: 19),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      value.trim().isEmpty ? hint : value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: value.trim().isEmpty
                            ? context.ejarzTheme.muted
                            : context.ejarzTheme.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: onTap == null
                        ? context.ejarzTheme.border
                        : context.ejarzTheme.muted,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchOption<T> {
  final T value;
  final String title;
  final String? subtitle;
  final String searchText;

  const _SearchOption({
    required this.value,
    required this.title,
    required this.searchText,
    this.subtitle,
  });
}

class _PickerResult<T> {
  final T? value;
  final bool manual;

  const _PickerResult.value(this.value) : manual = false;

  const _PickerResult.manual()
      : value = null,
        manual = true;
}

Future<_PickerResult<T>?> _showSearchPicker<T>({
  required BuildContext context,
  required String title,
  required String searchHint,
  required List<_SearchOption<T>> options,
  T? currentValue,
  bool allowManual = false,
}) {
  return showModalBottomSheet<_PickerResult<T>>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.9,
      child: _SearchPickerSheet<T>(
        title: title,
        searchHint: searchHint,
        options: options,
        currentValue: currentValue,
        allowManual: allowManual,
      ),
    ),
  );
}

class _SearchPickerSheet<T> extends StatefulWidget {
  final String title;
  final String searchHint;
  final List<_SearchOption<T>> options;
  final T? currentValue;
  final bool allowManual;

  const _SearchPickerSheet({
    required this.title,
    required this.searchHint,
    required this.options,
    required this.currentValue,
    required this.allowManual,
  });

  @override
  State<_SearchPickerSheet<T>> createState() => _SearchPickerSheetState<T>();
}

class _SearchPickerSheetState<T> extends State<_SearchPickerSheet<T>> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = normalizeSaudiLocation(_query);
    final filtered = query.isEmpty
        ? widget.options
        : widget.options
            .where(
              (option) =>
                  normalizeSaudiLocation(option.searchText).contains(query),
            )
            .toList(growable: false);
    return Material(
      color: context.ejarzTheme.background,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          const SizedBox(height: 10),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: context.ejarzTheme.border,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      color: context.ejarzTheme.text,
                      fontSize: context.sp(18),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'إغلاق',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: widget.searchHint,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'مسح البحث',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${filtered.length} نتيجة',
                style: TextStyle(
                  color: context.ejarzTheme.muted,
                  fontSize: context.sp(11.5),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'لا توجد نتائج مطابقة',
                      style: TextStyle(color: context.ejarzTheme.muted),
                    ),
                  )
                : ListView.separated(
                    key: ValueKey<String>('lookup-results-$query'),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: context.ejarzTheme.border,
                    ),
                    itemBuilder: (context, index) {
                      final option = filtered[index];
                      final selected = option.value == widget.currentValue;
                      return ListTile(
                        selected: selected,
                        selectedTileColor:
                            AppColors.primary.withValues(alpha: 0.08),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        title: Text(
                          option.title,
                          style: TextStyle(
                            color: selected
                                ? AppColors.primaryDark
                                : context.ejarzTheme.text,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        subtitle: option.subtitle == null
                            ? null
                            : Text(
                                option.subtitle!,
                                style: TextStyle(
                                  color: context.ejarzTheme.muted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                        trailing: selected
                            ? const Icon(
                                Icons.check_circle_rounded,
                                color: AppColors.primary,
                              )
                            : null,
                        onTap: () => Navigator.pop(
                          context,
                          _PickerResult<T>.value(option.value),
                        ),
                      );
                    },
                  ),
          ),
          if (widget.allowManual)
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(
                    context,
                    _PickerResult<T>.manual(),
                  ),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('إدخال قيمة غير مدرجة'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<String?> _showManualValueDialog(
  BuildContext context, {
  required String title,
  required String initialValue,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _ManualValueDialog(
      title: title,
      initialValue: initialValue,
    ),
  );
}

class _ManualValueDialog extends StatefulWidget {
  final String title;
  final String initialValue;

  const _ManualValueDialog({
    required this.title,
    required this.initialValue,
  });

  @override
  State<_ManualValueDialog> createState() => _ManualValueDialogState();
}

class _ManualValueDialogState extends State<_ManualValueDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: 'اكتب الاسم'),
          validator: (value) {
            final cleaned = value?.trim() ?? '';
            if (cleaned.length < 2) return 'أدخل اسمًا صحيحًا';
            return null;
          },
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('اعتماد'),
        ),
      ],
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(context, _controller.text.trim());
  }
}
