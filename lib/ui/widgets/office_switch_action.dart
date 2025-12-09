import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../screens/office/office.dart'; // OfficeHomePage + OfficeRuntime

/// ويدجت تُستخدم داخل AppBar.actions.
/// - إن كان المستخدم "مكتب" ➜ تظهر أيقونة التبديل وتفتح لوحة المكتب.
/// - غير ذلك ➜ تعرض الجرس الافتراضي (وتستدعي onBellTap).
class OfficeOrBellAction extends StatefulWidget {
  final VoidCallback onBellTap; // ماذا يحدث عند الضغط على الجرس لغير المكتب (يفتح شاشة الإشعارات مثلاً)
  final EdgeInsetsGeometry padding;

  const OfficeOrBellAction({
    super.key,
    required this.onBellTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 8),
  });

  @override
  State<OfficeOrBellAction> createState() => _OfficeOrBellActionState();
}

class _OfficeOrBellActionState extends State<OfficeOrBellAction> {
  bool? _isOffice; // null أثناء الفحص الأول

  @override
  void initState() {
    super.initState();
    _checkOfficeRole();
  }

  Future<void> _checkOfficeRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isOffice = false);
      return;
    }

    bool office = false;

    // 1) فحص الـ Custom Claims
    try {
      final claims = (await user.getIdTokenResult(true)).claims ?? {};
      if (claims['office'] == true || claims['role'] == 'office') {
        office = true;
      }
    } catch (_) {}

    // 2) احتياطي من Firestore
    if (!office) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        final data = doc.data() ?? {};
        if (data['isOffice'] == true || data['role'] == 'office') {
          office = true;
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() => _isOffice = office);
  }

  @override
  Widget build(BuildContext context) {
    // أثناء الفحص الأول، نعرض الجرس مؤقتًا لتجنب القفزة
    final showSwitch = _isOffice == true;

    return Padding(
      padding: widget.padding,
      child: IconButton(
        tooltip: showSwitch ? 'تبديل العميل' : 'الإشعارات',
        icon: Icon(showSwitch ? Icons.switch_account_rounded : Icons.notifications_none_rounded),
        onPressed: showSwitch
            ? () {
                // تفريغ أي اختيار عميل سابق
                OfficeRuntime.clear();

                // فتح لوحة المكتب لاختيار/تبديل العميل
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const OfficeHomePage()),
                );
              }
            : widget.onBellTap,
      ),
    );
  }
}
