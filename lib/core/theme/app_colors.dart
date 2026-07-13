import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  static const Color primaryDarkGreen = Color(0xFF0F4A35);
  static const Color primaryGreen = Color(0xFF1F6B4A);
  static const Color background = Color(0xFFF8F4EC);
  static const Color cardWhite = Color(0xFFFFFFFF);
  static const Color gold = Color(0xFFD6B46A);
  static const Color borderBeige = Color(0xFFE8DDC8);
  static const Color textDark = Color(0xFF1F2D2A);
  static const Color textGray = Color(0xFF7A817C);
  static const Color red = Color(0xFFD94F4F);
  static const Color warningGold = Color(0xFFD9A441);

  static const Color green900 = primaryDarkGreen;
  static const Color green700 = primaryGreen;
  static const Color green500 = primaryGreen;
  static const Color cream = background;
  static const Color card = cardWhite;
  static const Color amber = warningGold;
  static const Color ink = textDark;
  static const Color muted = textGray;
  static const Color border = borderBeige;

  static const Color goldLight = borderBeige;
  static const Color softGreen = background;
  static const Color softRed = background;
  static const Color softAmber = background;
  static const Color glass = cardWhite;

  static const LinearGradient headerGradient = LinearGradient(
    colors: [primaryDarkGreen, primaryGreen],
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
  );

  static const LinearGradient cardGlow = LinearGradient(
    colors: [cardWhite, background],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}
