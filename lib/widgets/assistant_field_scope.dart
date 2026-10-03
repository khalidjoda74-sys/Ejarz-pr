import 'package:flutter/material.dart';
import '../core/assistant/contract_assistant_controller.dart';
import '../core/assistant/contract_field_catalog.dart';

class AssistantFieldScope extends InheritedWidget {
  final ContractAssistantController controller;
  final Map<String, GlobalKey> anchors;
  final int step, party;
  const AssistantFieldScope(
      {super.key,
      required super.child,
      required this.controller,
      required this.anchors,
      required this.step,
      required this.party});

  static AssistantFieldScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AssistantFieldScope>();
  ContractFieldSpec? resolve(String label) {
    final prefix = party == 0
        ? 'lessor.'
        : party == 1
            ? 'tenant.'
            : 'representative.';
    final normalized = switch (label) {
      'اسم المنشأة' => 'الاسم الكامل',
      'اسم البنك' => 'البنك',
      'رقم الوثيقة' => 'رقم وثيقة الملكية',
      'تاريخ الوثيقة' => 'تاريخ وثيقة الملكية',
      'عدد دورات المياه' => 'عدد دورات المياه',
      'المساحة بالمتر المربع' => 'مساحة الوحدة',
      _ => label,
    };
    return ContractFieldCatalog.fields
        .where((f) =>
            f.label == normalized &&
            f.step == step &&
            (step != 2 || f.path.startsWith(prefix)))
        .firstOrNull;
  }

  @override
  bool updateShouldNotify(AssistantFieldScope oldWidget) => true;
}

/// Only assistant changes replace a field's initialValue; manual typing never
/// changes this key, so cursor/IME composing state is retained.
class AssistantFieldDecoration extends StatelessWidget {
  final String label;
  final Widget child;
  const AssistantFieldDecoration(
      {super.key, required this.label, required this.child});
  @override
  Widget build(BuildContext context) {
    final scope = AssistantFieldScope.of(context);
    final field = scope?.resolve(label);
    if (scope == null || field == null) return child;
    final metadata = scope.controller.readDraft().assistantFields[field.path];
    final voiced = metadata?['source'] == 'voice' ||
        metadata?['source'] == 'assistantText';
    final pending = metadata?['status'] == 'needsConfirmation';
    final focused = scope.controller.focusedPath == field.path;
    return AnimatedContainer(
      key: scope.anchors.putIfAbsent(field.path, () => GlobalKey()),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: focused ? const Color(0xFF07836E) : Colors.transparent,
              width: 1.5),
          color: focused
              ? const Color(0xFF07836E).withValues(alpha: .05)
              : Colors.transparent),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        KeyedSubtree(
            key: ValueKey(
                '${field.path}:${scope.controller.fieldRevisions[field.path] ?? 0}'),
            child: child),
        if (voiced)
          Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                Icon(
                    pending
                        ? Icons.pending_outlined
                        : Icons.check_circle_rounded,
                    size: 14,
                    color: pending
                        ? Colors.orange.shade800
                        : const Color(0xFF07836E)),
                Text(
                    pending
                        ? 'أُدخل بالمساعد • بانتظار تأكيدك'
                        : 'أُدخل بالمساعد • مؤكد',
                    style: const TextStyle(fontSize: 11)),
                if (pending)
                  TextButton(
                      onPressed: () => scope.controller.confirm(field.path),
                      child: const Text('تأكيد')),
              ]),
      ]),
    );
  }
}
