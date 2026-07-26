import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/auth/auth_guard.dart';
import '../../core/moderation/content_moderation.dart';
import '../../core/navigation/app_focus.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/premium_background.dart';
import '../../data/repositories/council_repository.dart';

const _saudiCities = <String>[
  'الرياض',
  'جدة',
  'مكة المكرمة',
  'المدينة المنورة',
  'الدمام',
  'الخبر',
  'الظهران',
  'الجبيل',
  'الهفوف',
  'المبرز',
  'القطيف',
  'حفر الباطن',
  'رأس تنورة',
  'سيهات',
  'صفوى',
  'الطائف',
  'بريدة',
  'عنيزة',
  'الرس',
  'حائل',
  'تبوك',
  'أبها',
  'خميس مشيط',
  'جازان',
  'نجران',
  'الباحة',
  'ينبع',
  'العلا',
  'سكاكا',
  'عرعر',
  'القريات',
  'رفحاء',
  'الخرج',
  'الدوادمي',
  'الزلفي',
  'المجمعة',
  'وادي الدواسر',
  'بيشة',
  'محايل عسير',
  'صبيا',
  'أبو عريش',
  'شرورة',
  'رابغ',
  'القنفذة',
  'الليث',
];

class CreateCouncilScreen extends StatefulWidget {
  const CreateCouncilScreen({
    super.key,
    this.onBack,
    this.onCreated,
  });

  final VoidCallback? onBack;
  final ValueChanged<String>? onCreated;

  @override
  State<CreateCouncilScreen> createState() => _CreateCouncilScreenState();
}

class _CreateCouncilScreenState extends State<CreateCouncilScreen> {
  final repo = CouncilRepository.instance;
  final titleController = TextEditingController();
  final descriptionController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final List<_SelectedCouncilImage> _selectedImages = [];
  String? category;
  String? city;
  String? _categoryErrorMessage;
  String? _cityErrorMessage;
  String? _titleErrorMessage;
  String? _detailsErrorMessage;
  bool allowComments = true;
  bool _creating = false;
  static const int _titleMaxLength = 33;
  static const int _detailsMaxLength = 3000;

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sizes = AppSizes.of(context);
    final categories = repo.categories.where((c) => c != 'الكل').toList();
    final titleHint = _titleHintForCategory(category);
    final detailsHint = _detailsHintForCategory(category);

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      body: PremiumBackground(
        showPattern: false,
        child: Column(
          children: [
            CustomGreenHeader(
              title: 'إضافة فرصة',
              showBack: true,
              onBack: widget.onBack,
            ),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  sizes.horizontalPadding,
                  12,
                  sizes.horizontalPadding,
                  18 + MediaQuery.viewPaddingOf(context).bottom,
                ),
                children: [
                  _FormSection(
                    children: [
                      const _FieldLabel('اختر التصنيف المناسب'),
                      const SizedBox(height: 6),
                      _CategorySelector(
                        items: categories,
                        selected: category,
                        onSelected: (value) => setState(() {
                          category = value;
                          _categoryErrorMessage = null;
                        }),
                      ),
                      if (_categoryErrorMessage != null) ...[
                        const SizedBox(height: 8),
                        _FieldError(message: _categoryErrorMessage!),
                      ],
                      const SizedBox(height: 11),
                      const _FieldLabel('عنوان الفرصة'),
                      const SizedBox(height: 6),
                      _CompactTextField(
                        controller: titleController,
                        hintText: titleHint,
                        maxLength: _titleMaxLength,
                        onChanged: (_) {
                          if (_titleErrorMessage != null) {
                            setState(() => _titleErrorMessage = null);
                          }
                        },
                      ),
                      if (_titleErrorMessage != null) ...[
                        const SizedBox(height: 8),
                        _FieldError(message: _titleErrorMessage!),
                      ],
                      const SizedBox(height: 11),
                      const _FieldLabel('تفاصيل الفرصة'),
                      const SizedBox(height: 6),
                      _CompactTextField(
                        controller: descriptionController,
                        hintText: detailsHint,
                        height: 118,
                        maxLines: 5,
                        maxLength: _detailsMaxLength,
                        onChanged: (_) {
                          if (_detailsErrorMessage != null) {
                            setState(() => _detailsErrorMessage = null);
                          }
                        },
                      ),
                      if (_detailsErrorMessage != null) ...[
                        const SizedBox(height: 8),
                        _FieldError(message: _detailsErrorMessage!),
                      ],
                      const SizedBox(height: 11),
                      const _FieldLabel('المدينة'),
                      const SizedBox(height: 6),
                      _CityDropdown(
                        value: city,
                        onChanged: (value) => setState(() {
                          city = value;
                          _cityErrorMessage = null;
                        }),
                      ),
                      if (_cityErrorMessage != null) ...[
                        const SizedBox(height: 8),
                        _FieldError(message: _cityErrorMessage!),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  _FormSection(
                    children: [
                      Row(
                        children: [
                          const _FieldLabel('صور الفرصة'),
                          const Spacer(),
                          Text(
                            '${_selectedImages.length}/10',
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textGray,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'اختياري، أضف حتى 10 صور توضّح الفرصة.',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textGray,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 9),
                      _ImagePickerSection(
                        images: _selectedImages,
                        onAdd: _pickImages,
                        onRemove: (index) => setState(() {
                          _selectedImages.removeAt(index);
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _FormSection(
                    children: [
                      _ToggleRow(
                        title: 'السماح بالتعليقات',
                        subtitle: allowComments
                            ? 'يمكن للجميع التعليق'
                            : 'رأي سريع بدون تعليقات',
                        value: allowComments,
                        onChanged: (value) => setState(() {
                          allowComments = value;
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _creating ? null : _createCouncil,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryDarkGreen,
                        foregroundColor: AppColors.cardWhite,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: AppTextStyles.button.copyWith(fontSize: 14),
                      ),
                      child: _creating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.cardWhite,
                              ),
                            )
                          : const Text('إضافة الفرصة'),
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

  Future<void> _pickImages() async {
    final remaining = 10 - _selectedImages.length;
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يمكن إضافة 10 صور كحد أقصى.')),
      );
      return;
    }

    dismissAppKeyboard();
    try {
      final pickedImages = await _imagePicker.pickMultiImage(
        maxWidth: 1800,
        imageQuality: 78,
      );
      if (pickedImages.isEmpty) return;

      final selected = <_SelectedCouncilImage>[];
      for (final file in pickedImages.take(remaining)) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          selected.add(_SelectedCouncilImage(file: file, bytes: bytes));
        }
      }

      if (!mounted || selected.isEmpty) return;
      setState(() {
        _selectedImages.addAll(selected);
      });

      if (pickedImages.length > remaining) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم اختيار أول 10 صور فقط.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر اختيار الصور. حاول مرة أخرى.')),
      );
    }
  }

  Future<void> _createCouncil() async {
    final selectedCategory = category;
    if (!_validateRequiredFields(selectedCategory)) return;

    await AuthGuard.requireAuth(context, () async {
      setState(() => _creating = true);
      try {
        final council = await repo.createCouncil(
          title: titleController.text,
          description: descriptionController.text,
          category: selectedCategory!,
          city: city!,
          isPrivate: false,
          allowComments: allowComments,
          imageFiles: _selectedImages
              .map((image) => image.file)
              .toList(growable: false),
        );
        if (!mounted) return;
        titleController.clear();
        descriptionController.clear();
        setState(() {
          category = null;
          city = null;
          _categoryErrorMessage = null;
          _cityErrorMessage = null;
          _titleErrorMessage = null;
          _detailsErrorMessage = null;
          _selectedImages.clear();
        });
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: const Text(
                  'تمت إضافة الفرصة بنجاح. يمكنك الآن متابعة التفاصيل والآراء.'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.primaryDarkGreen,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 88),
            ),
          );
        widget.onCreated?.call(council.id);
      } on ContentModerationException catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر إضافة الفرصة. تحقق من الاتصال وحاول مرة أخرى.'),
          ),
        );
      } finally {
        if (mounted) setState(() => _creating = false);
      }
    });
  }

  bool _validateRequiredFields(String? selectedCategory) {
    final titleEmpty = titleController.text.trim().isEmpty;
    final detailsEmpty = descriptionController.text.trim().isEmpty;
    final titleTooLong =
        titleController.text.trim().characters.length > _titleMaxLength;
    final detailsTooLong =
        descriptionController.text.trim().characters.length > _detailsMaxLength;
    final categoryEmpty = selectedCategory == null || selectedCategory.isEmpty;
    final cityEmpty = city == null || city!.isEmpty;

    if (!categoryEmpty &&
        !cityEmpty &&
        !titleEmpty &&
        !detailsEmpty &&
        !titleTooLong &&
        !detailsTooLong) {
      return true;
    }

    setState(() {
      _categoryErrorMessage =
          categoryEmpty ? 'اختر نوع الفرصة قبل الإضافة.' : null;
      _cityErrorMessage = cityEmpty ? 'اختر المدينة قبل إضافة الفرصة.' : null;
      _titleErrorMessage = titleEmpty
          ? 'اكتب عنوان الفرصة.'
          : titleTooLong
              ? 'عنوان الفرصة يجب ألا يتجاوز 33 حرفًا.'
              : null;
      _detailsErrorMessage = detailsEmpty
          ? 'اكتب تفاصيل الفرصة.'
          : detailsTooLong
              ? 'تفاصيل الفرصة يجب ألا تتجاوز 3000 حرف.'
              : null;
    });
    return false;
  }

  String _titleHintForCategory(String? category) {
    switch (category) {
      case 'فرص للتقبيل':
        return 'مثال: كوفي قائم للتقبيل في الرياض';
      case 'فرص مطلوبة':
        return 'مثال: أبحث عن مشروع مغسلة قائم في جدة';
      case 'فرص شراكة':
        return 'مثال: أبحث عن شريك ممول لتوسعة مطعم قائم';
      case 'تجارب السوق':
        return 'مثال: تجربتي مع افتتاح كوفي صغير في الدمام';
      default:
        return 'اختر التصنيف أولًا لعرض مثال مناسب';
    }
  }

  String _detailsHintForCategory(String? category) {
    switch (category) {
      case 'فرص للتقبيل':
        return 'اكتب تفاصيل الموقع، النشاط، سبب التقبيل، التجهيزات، الإيجار، والدخل إن وجد.';
      case 'فرص مطلوبة':
        return 'اكتب نوع الفرصة المطلوبة، المدينة، الميزانية التقريبية، والخبرة أو القطاع المناسب.';
      case 'فرص شراكة':
        return 'اكتب نوع الشريك المطلوب، دورك الحالي، المطلوب من الشريك، ونموذج العمل المتوقع.';
      case 'تجارب السوق':
        return 'اكتب التجربة بوضوح: ماذا حدث؟ ما النتيجة؟ وما النصيحة التي تفيد غيرك؟';
      default:
        return 'بعد اختيار التصنيف سيظهر مثال مناسب للتفاصيل المطلوبة.';
    }
  }
}

class _CityDropdown extends StatelessWidget {
  const _CityDropdown({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      onTap: dismissAppKeyboard,
      isExpanded: true,
      menuMaxHeight: 360,
      dropdownColor: AppColors.cardWhite,
      borderRadius: BorderRadius.circular(14),
      alignment: AlignmentDirectional.centerStart,
      icon: const Icon(
        Icons.keyboard_arrow_down_rounded,
        color: AppColors.primaryDarkGreen,
      ),
      hint: Text(
        'اختر المدينة',
        textAlign: TextAlign.right,
        style: AppTextStyles.caption.copyWith(
          color: AppColors.textGray,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      items: _saudiCities
          .map(
            (city) => DropdownMenuItem<String>(
              value: city,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                city,
                textAlign: TextAlign.right,
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textDark,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          )
          .toList(growable: false),
      onChanged: onChanged,
      decoration: InputDecoration(
        filled: true,
        fillColor: AppColors.cardWhite,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        prefixIcon: const Icon(
          Icons.location_city_rounded,
          size: 19,
          color: AppColors.primaryDarkGreen,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.borderBeige),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.borderBeige),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: AppColors.primaryDarkGreen, width: 1.2),
        ),
      ),
    );
  }
}

class _SelectedCouncilImage {
  const _SelectedCouncilImage({required this.file, required this.bytes});

  final XFile file;
  final Uint8List bytes;
}

class _ImagePickerSection extends StatelessWidget {
  const _ImagePickerSection({
    required this.images,
    required this.onAdd,
    required this.onRemove,
  });

  final List<_SelectedCouncilImage> images;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemSize = ((constraints.maxWidth - 32) / 5).clamp(54.0, 68.0);
        final tiles = <Widget>[
          for (var index = 0; index < images.length; index++)
            _PickedImageTile(
              image: images[index],
              size: itemSize,
              onRemove: () => onRemove(index),
            ),
          if (images.length < 10) _AddImageTile(size: itemSize, onTap: onAdd),
        ];

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: tiles,
        );
      },
    );
  }
}

class _PickedImageTile extends StatelessWidget {
  const _PickedImageTile({
    required this.image,
    required this.size,
    required this.onRemove,
  });

  final _SelectedCouncilImage image;
  final double size;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(
                image.bytes,
                fit: BoxFit.cover,
              ),
            ),
          ),
          PositionedDirectional(
            top: -5,
            end: -5,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: AppColors.red,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: AppColors.cardWhite,
                  size: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddImageTile extends StatelessWidget {
  const _AddImageTile({required this.size, required this.onTap});

  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderBeige),
        ),
        child: const Icon(
          Icons.add_photo_alternate_outlined,
          color: AppColors.primaryDarkGreen,
          size: 24,
        ),
      ),
    );
  }
}

class _FormSection extends StatelessWidget {
  const _FormSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderBeige),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F4A35),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.caption.copyWith(
        color: AppColors.textDark,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _CategorySelector extends StatelessWidget {
  const _CategorySelector({
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  final List<String> items;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items.map((item) {
            return SizedBox(
              width: itemWidth,
              child: _CategoryChoiceChip(
                label: item,
                selected: item == selected,
                onTap: () => onSelected(item),
              ),
            );
          }).toList(growable: false),
        );
      },
    );
  }
}

class _FieldError extends StatelessWidget {
  const _FieldError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      textAlign: TextAlign.right,
      style: AppTextStyles.caption.copyWith(
        color: AppColors.red,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _CompactTextField extends StatelessWidget {
  const _CompactTextField({
    required this.controller,
    required this.hintText,
    this.height = 48,
    this.maxLines = 1,
    this.maxLength,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final double height;
  final int maxLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        inputFormatters: [
          if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
        ],
        onChanged: onChanged,
        textAlign: TextAlign.right,
        textAlignVertical:
            maxLines > 1 ? TextAlignVertical.top : TextAlignVertical.center,
        style: AppTextStyles.body.copyWith(fontSize: 13),
        decoration: _inputDecoration(hintText),
      ),
    );
  }
}

InputDecoration _inputDecoration(String hintText) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: AppTextStyles.caption.copyWith(fontSize: 11),
    isDense: true,
    filled: true,
    fillColor: AppColors.cardWhite,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppColors.borderBeige),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppColors.borderBeige),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppColors.primaryGreen, width: 1.2),
    ),
  );
}

class _CategoryChoiceChip extends StatelessWidget {
  const _CategoryChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 34,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryDarkGreen : AppColors.cardWhite,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color:
                selected ? AppColors.primaryDarkGreen : AppColors.borderBeige,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppTextStyles.caption.copyWith(
            color: selected ? AppColors.cardWhite : AppColors.textDark,
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 50),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderBeige),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTextStyles.caption.copyWith(fontSize: 10.5),
                ),
              ],
            ),
          ),
          Transform.scale(
            scale: .82,
            child: Switch.adaptive(
              value: value,
              activeThumbColor: AppColors.primaryDarkGreen,
              activeTrackColor: AppColors.primaryGreen.withValues(alpha: .30),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
