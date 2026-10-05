import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../core/admin_contract_session.dart';
import '../core/models.dart';
import 'common.dart';

class AdminContractFeePanel extends StatefulWidget {
  final AdminContractSession session;
  final ContractDraft draft;
  final VoidCallback onChanged;
  const AdminContractFeePanel(
      {super.key,
      required this.session,
      required this.draft,
      required this.onChanged});
  @override
  State<AdminContractFeePanel> createState() => _AdminContractFeePanelState();
}

class _AdminContractFeePanelState extends State<AdminContractFeePanel> {
  bool uploading = false;
  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return AppCard(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle(
          title: 'الإرسال وتسوية الرسوم',
          icon: Icons.admin_panel_settings_outlined),
      const SizedBox(height: 12),
      Text('العميل: ${s.userName} • ${s.userPhone}'),
      Text('رسوم الخدمة: ${widget.draft.totalPayable.toStringAsFixed(2)} ريال'),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'طريقة تسوية الرسوم'),
          initialValue: s.mode,
          items: [
            const DropdownMenuItem(
                value: 'customer', child: Text('العميل يدفع — بانتظار الدفع')),
            if (s.canWaive)
              const DropdownMenuItem(
                  value: 'waived',
                  child: Text('تنفيذ مباشر — إعفاء من الرسوم')),
            if (s.canRecordExternal)
              const DropdownMenuItem(
                  value: 'external',
                  child: Text('تنفيذ مباشر — سداد خارج التطبيق')),
          ],
          onChanged: (value) {
            s.mode = value ?? 'customer';
            s.acknowledged = false;
            widget.onChanged();
          }),
      if (s.mode != 'customer') ...[
        const SizedBox(height: 12),
        AppTextField(
            label: s.mode == 'waived' ? 'سبب الإعفاء' : 'ملاحظة التحصيل',
            hint: 'أدخل التفاصيل',
            initialValue: s.reason,
            required: true,
            maxLines: 2,
            onChanged: (v) {
              s.reason = v;
              s.acknowledged = false;
              widget.onChanged();
            },
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'هذا الحقل مطلوب' : null),
        Text(s.mode == 'waived'
            ? 'لن يُطالب العميل بالدفع، ولن يُسجل الإعفاء كإيراد.'
            : 'سيُسجل كامل المبلغ كسداد فعلي ويصدر إثبات السداد.'),
      ],
      if (s.mode == 'external') ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'طريقة التحصيل'),
            initialValue: s.method,
            items: const [
              DropdownMenuItem(
                  value: 'bankTransfer', child: Text('تحويل بنكي')),
              DropdownMenuItem(value: 'cash', child: Text('نقدًا'))
            ],
            onChanged: (v) {
              s.method = v ?? 'bankTransfer';
              s.acknowledged = false;
              widget.onChanged();
            }),
        const SizedBox(height: 12),
        AppTextField(
            label: 'مرجع التحصيل',
            hint: 'رقم التحويل أو مرجع الإيصال',
            initialValue: s.reference,
            required: true,
            onChanged: (v) {
              s.reference = v;
              s.acknowledged = false;
              widget.onChanged();
            },
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'هذا الحقل مطلوب' : null),
        if (s.method == 'bankTransfer')
          OutlinedButton.icon(
              onPressed: uploading
                  ? null
                  : () async {
                      final selected = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
                          withData: true);
                      if (selected == null ||
                          selected.files.single.bytes == null) {
                        return;
                      }
                      setState(() => uploading = true);
                      try {
                        final file = selected.files.single;
                        s.proofUrl = await s.upload(file.name, file.bytes!,
                            draft: widget.draft);
                        s.proofName = file.name;
                        s.acknowledged = false;
                        widget.onChanged();
                      } catch (e) {
                        if (context.mounted) showAppSnackBar(context, '$e');
                      } finally {
                        if (mounted) setState(() => uploading = false);
                      }
                    },
              icon: const Icon(Icons.upload_file),
              label: Text(uploading
                  ? 'جارٍ رفع الإثبات…'
                  : s.proofName.isEmpty
                      ? 'رفع إثبات التحويل البنكي'
                      : s.proofName)),
      ],
      const SizedBox(height: 12),
      ToggleCard(
          title: 'أقر بإعداد وإرسال الطلب نيابةً عن العميل',
          subtitle:
              'راجعت البيانات والمرفقات والشروط وطريقة تسوية الرسوم، ويُسجل الإقرار باسمي كمسؤول.',
          value: s.acknowledged,
          icon: Icons.verified_user_outlined,
          onChanged: (v) {
            s.acknowledged = v;
            widget.onChanged();
          }),
      const SizedBox(height: 12),
      Text(s.mode == 'customer'
          ? 'سيظهر الطلب للعميل بانتظار الدفع.'
          : 'سيظهر الطلب للعميل قيد المعالجة دون مرحلة دفع.'),
    ]));
  }
}
