// lib/ui/widgets/app_bottom_nav.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const AppBottomNav(
      {super.key, required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      // قاعدة سوداء خلف الـ glass فقط بارتفاع عنصر الـ BottomNav
      color: const Color(0xFF0F172A),
      child: SafeArea(
        top: false, // نتجاهل الحافة العلوية هنا
        child: Padding(
          // ✅ لا نترك فراغاً أسود فوق الزجاجي
          padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18.r),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                decoration: BoxDecoration(
                  // طبقة زجاجية خفيفة فوق الأسود
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withOpacity(0.10),
                      Colors.white.withOpacity(0.06),
                    ],
                  ),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.20),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Theme(
                  data: Theme.of(context).copyWith(
                    splashColor: Colors.white.withOpacity(0.08),
                    highlightColor: Colors.transparent,
                  ),
                  child: BottomNavigationBar(
                    type: BottomNavigationBarType.fixed,
                    backgroundColor: Colors.transparent, // يترك الزجاج ظاهر
                    elevation: 0,
                    currentIndex: currentIndex,
                    selectedItemColor: const Color(0xFF5EEAD4),
                    unselectedItemColor: const Color(0xFFCBD5E1),
                    selectedLabelStyle: GoogleFonts.cairo(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.sp,
                    ),
                    unselectedLabelStyle: GoogleFonts.cairo(
                      fontWeight: FontWeight.w600,
                      fontSize: 12.sp,
                    ),
                    onTap: onTap,
                    items: const [
                      BottomNavigationBarItem(
                        icon: Icon(Icons.home_rounded),
                        label: 'الرئيسية',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.apartment_rounded),
                        label: 'العقارات',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.people_alt_rounded),
                        label: 'العملاء',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.assignment_turned_in_rounded),
                        label: 'العقود',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
