import 'package:flutter/material.dart';

// ✅ عدّل مسار الاستيراد حسب مكان AppMenuButton عندك
import '../ui/widgets/app_menu_button.dart';

Widget darvooLeading(BuildContext context, {Color iconColor = Colors.white}) {
  final nav = Navigator.of(context);

  // لو فيه صفحة قبلها => رجوع
  if (nav.canPop()) {
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;

    return IconButton(
      tooltip: 'رجوع',
      onPressed: () => nav.maybePop(),
      icon: Icon(
        isIOS ? Icons.arrow_back_ios_new_rounded : Icons.arrow_back_rounded,
        color: iconColor,
      ),
    );
  }

  // لو هذه صفحة رئيسية => قائمة (Drawer)
  return AppMenuButton(iconColor: iconColor);
}
