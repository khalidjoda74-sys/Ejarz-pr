// lib/ui/widgets/app_menu_button.dart
import 'package:flutter/material.dart';

class AppMenuButton extends StatelessWidget {
  final Color? iconColor;
  const AppMenuButton({super.key, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.menu_rounded),
      color: iconColor ?? Colors.white,
      onPressed: () => Scaffold.of(context).openDrawer(),
      tooltip: 'القائمة',
    );
  }
}
