import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/firebase_bootstrap.dart';
import '../core/admin_contract_session.dart';
import '../core/app_controller.dart';
import '../core/theme.dart';
import '../core/saudi_reference_data.dart';
import 'create_contract.dart';

class AdminContractApp extends StatefulWidget {
  final String uid, draftId;
  const AdminContractApp({super.key, required this.uid, this.draftId = ''});
  @override
  State<AdminContractApp> createState() => _AdminContractAppState();
}

class _AdminContractAppState extends State<AdminContractApp> {
  AdminContractSession? session;
  String? error;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await FirebaseBootstrap.ready;
      final user = await FirebaseAuth.instance.authStateChanges().first;
      if (user == null) {
        throw StateError('سجّل دخول المسؤول في لوحة التحكم ثم أعد فتح المحرر.');
      }
      final current =
          AdminContractSession(widget.uid, user.uid, widget.draftId);
      session?.dispose();
      session = current;
      await current.load();
      await SaudiReferenceCatalog.load();
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  void dispose() {
    session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate
        ],
        theme: AppTheme.light(),
        debugShowCheckedModeBanner: false,
        home: loading
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : error != null
                ? Scaffold(
                    body: Center(
                        child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(error!),
                                  const SizedBox(height: 16),
                                  FilledButton(
                                      onPressed: _load,
                                      child: const Text('إعادة المحاولة'))
                                ]))))
                : AppScope(
                    controller: session!,
                    child: CreateContractScreen(
                        adminSession: session,
                        initialDraft: session!.initialDraft,
                        renewalMode: session!.initialDraft?.renewal ?? false,
                        draftId: session!.contractId,
                        initialStep: session!.initialProgress.lastStep)),
      );
}
