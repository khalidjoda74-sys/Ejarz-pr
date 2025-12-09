import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DisabledAccountGuard extends StatefulWidget {
  final Widget child;
  const DisabledAccountGuard({super.key, required this.child});

  @override
  State<DisabledAccountGuard> createState() => _DisabledAccountGuardState();
}

class _DisabledAccountGuardState extends State<DisabledAccountGuard> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  bool _handledOnce = false;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _sub = FirebaseFirestore.instance
          .doc('users/${user.uid}')
          .snapshots()
          .listen((snap) async {
        final m = snap.data() ?? {};
        final blocked = (m['blocked'] == true) || (m['disabled'] == true);
        if (blocked && !_handledOnce) {
          _handledOnce = true;
          final msg = (m['block_message'] as String?) ??
              'عذرًا، تم إيقافك من استخدام التطبيق. إذا كنت تعتقد أن هذا عن طريق الخطأ، يُرجى التواصل مع الإدارة.';

          if (mounted) {
            await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => AlertDialog(
                title: const Text('تم إيقاف الحساب'),
                content: Text(msg, textAlign: TextAlign.right),
                actions: [
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('حسنًا'),
                  ),
                ],
              ),
            );
          }

          // تسجيل خروج وإرجاع المستخدم لصفحة الدخول
          await FirebaseAuth.instance.signOut();
        }
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
