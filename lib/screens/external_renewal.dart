import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/app_controller.dart';
import '../core/contract_files.dart';
import '../core/contract_validators.dart';
import '../core/renewal_request.dart';
import '../core/runtime_config.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/service_unavailable.dart';
import 'contracts.dart';

class ExternalRenewalScreen extends StatefulWidget {
  final RenewalRequest? initialRequest;
  final Future<String> Function(String, Uint8List)? uploader;
  final Future<PlatformFile?> Function()? picker;
  const ExternalRenewalScreen(
      {super.key, this.initialRequest, this.uploader, this.picker});
  @override
  State<ExternalRenewalScreen> createState() => _ExternalRenewalScreenState();
}

class _ExternalRenewalScreenState extends State<ExternalRenewalScreen> {
  final _form = GlobalKey<FormState>();
  late final RenewalRequest _request =
      widget.initialRequest ?? RenewalRequest();
  bool _uploading = false, _sending = false, _submitted = false;
  String? _fileError;
  String? _error;
  bool get _busy => _uploading || _sending;

  Future<void> _pick() async {
    if (_busy) return;
    setState(() {
      _uploading = true;
      _fileError = null;
    });
    try {
      final result = widget.picker == null
          ? await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['pdf'],
              withData: true,
              allowMultiple: false)
          : null;
      final file =
          widget.picker != null ? await widget.picker!() : result?.files.single;
      if (file == null || !mounted) return;
      if (file.bytes == null || file.size > ContractFiles.maxBytes) {
        throw const FormatException(
            'تعذر قراءة الملف أو أن حجمه يتجاوز 10 ميجابايت.');
      }
      if (ContractFiles.contentType(file.name, file.bytes!) !=
          'application/pdf') {
        throw const FormatException('اختر عقد منصة إيجار بصيغة PDF.');
      }
      final url = await (widget.uploader ?? ContractFiles.upload)(
          file.name, file.bytes!);
      if (!mounted) return;
      setState(() {
        _request.fileName = file.name;
        _request.fileUrl = url;
        _request.sourceContractId = '';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _fileError = error is FormatException
            ? error.message
            : 'تعذر رفع الملف. تحقق من اتصالك وأعد المحاولة.');
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _send() async {
    if (_busy || _submitted) return;
    final valid = _form.currentState!.validate();
    setState(() {
      _fileError = _request.fileUrl.isEmpty
          ? 'أرفق عقد منصة إيجار قبل إرسال الطلب'
          : null;
      _error = null;
    });
    if (!valid || _fileError != null) return;
    FocusScope.of(context).unfocus();
    setState(() => _sending = true);
    try {
      _request.validate();
      final record = await AppScope.of(context).submitExternalRenewal(_request);
      if (!mounted) return;
      setState(() {
        _submitted = true;
        _sending = false;
      });
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
          builder: (_) => ContractDetailsScreen(contract: record)));
      showAppSnackBar(context, 'تم إرسال طلب التجديد بنجاح');
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is FirebaseFunctionsException
            ? error.message ?? 'تعذر إرسال الطلب. أعد المحاولة.'
            : error is FormatException
                ? error.message
                : 'تعذر إرسال الطلب. تحقق من الاتصال ثم أعد المحاولة؛ بياناتك محفوظة في هذه الشاشة.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AppRuntime.service('renewal')) return const ServiceUnavailable();
    final attached = _request.fileUrl.isNotEmpty;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: const DetailAppBar(title: 'تجديد عقد سابق'),
        bottomNavigationBar: SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Align(
                heightFactor: 1,
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: PrimaryButton(
                        label: _sending
                            ? 'جارٍ إرسال الطلب…'
                            : 'إرسال طلب التجديد',
                        onPressed: _busy ? null : _send)))),
        body: SafeArea(
            child: ResponsiveContent(
                maxWidth: 700,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Form(
                    key: _form,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: AbsorbPointer(
                        absorbing: _busy,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const AppPageHeader(
                                  title: 'عقدك السابق، بخطوات أسهل',
                                  subtitle:
                                      'أرفق عقد منصة إيجار وأدخل بيانات المستأجر. سنتولى مراجعة طلب التجديد ومتابعته معك.',
                                  icon: Icons.autorenew_rounded),
                              const SizedBox(height: 22),
                              _section(
                                  context,
                                  '1',
                                  'عقد منصة إيجار',
                                  'ارفع النسخة الكاملة والواضحة من العقد السابق.',
                                  [
                                    const SizedBox(height: 14),
                                    Material(
                                        color: attached
                                            ? AppColors.primary
                                                .withValues(alpha: .06)
                                            : Theme.of(context)
                                                .colorScheme
                                                .surface,
                                        borderRadius: BorderRadius.circular(18),
                                        child: InkWell(
                                            onTap: _pick,
                                            borderRadius:
                                                BorderRadius.circular(18),
                                            child: Container(
                                                padding:
                                                    const EdgeInsets.all(20),
                                                decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            18),
                                                    border: Border.all(
                                                        color: attached
                                                            ? AppColors.primary
                                                            : context.ejarzTheme
                                                                .border)),
                                                child: Column(children: [
                                                  Icon(
                                                      attached
                                                          ? Icons
                                                              .task_alt_rounded
                                                          : Icons
                                                              .upload_file_rounded,
                                                      size: 36,
                                                      color: AppColors.primary),
                                                  const SizedBox(height: 10),
                                                  Text(
                                                      _uploading
                                                          ? 'جارٍ رفع العقد…'
                                                          : attached
                                                              ? _request
                                                                  .fileName
                                                              : 'اضغط لاختيار عقد PDF',
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w800)),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                      attached
                                                          ? 'تم رفع الملف • اضغط لاستبداله'
                                                          : 'PDF فقط • حتى 10 ميجابايت',
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: TextStyle(
                                                          color: context
                                                              .ejarzTheme.muted,
                                                          fontSize: 12)),
                                                  if (_uploading) ...[
                                                    const SizedBox(height: 14),
                                                    const LinearProgressIndicator()
                                                  ],
                                                ])))),
                                    if (_fileError != null)
                                      Padding(
                                          padding:
                                              const EdgeInsets.only(top: 10),
                                          child: Text(_fileError!,
                                              style: TextStyle(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .error))),
                                  ]),
                              const SizedBox(height: 16),
                              _section(context, '2', 'بيانات المستأجر',
                                  'أدخل البيانات المطابقة للعقد المرفق.', [
                                const SizedBox(height: 16),
                                AppTextField(
                                    label: 'رقم هوية المستأجر',
                                    hint: 'الهوية الوطنية أو الإقامة',
                                    initialValue: _request.idNumber,
                                    keyboardType: TextInputType.number,
                                    icon: Icons.badge_outlined,
                                    required: true,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(10)
                                    ],
                                    validator: RenewalRequest.validateIdentity,
                                    onChanged: (v) => _request.idNumber = v),
                                DateField(
                                    label: 'تاريخ ميلاد المستأجر',
                                    value: _request.birthDate,
                                    required: true,
                                    firstDate: DateTime(1900),
                                    lastDate: adultBirthDateCutoff(),
                                    validator: validateAdultBirthDate,
                                    onChanged: (v) =>
                                        setState(() => _request.birthDate = v)),
                                AppTextField(
                                    label: 'رقم جوال المستأجر',
                                    hint: '05xxxxxxxx',
                                    initialValue: _request.mobile,
                                    keyboardType: TextInputType.phone,
                                    icon: Icons.phone_iphone_rounded,
                                    required: true,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(10)
                                    ],
                                    validator: RenewalRequest.validateMobile,
                                    onChanged: (v) => _request.mobile = v),
                              ]),
                              const SizedBox(height: 16),
                              const InfoBanner(
                                  text:
                                      'بعد الإرسال سيظهر الطلب في «عقودي» لمتابعة المراجعة وأي بيانات إضافية تحتاجها الإدارة.',
                                  icon: Icons.fact_check_outlined),
                              if (_error != null) ...[
                                const SizedBox(height: 12),
                                InfoBanner(
                                    text: _error!,
                                    icon: Icons.error_outline,
                                    color: Theme.of(context).colorScheme.error)
                              ],
                            ]))))),
      ),
    );
  }

  Widget _section(BuildContext context, String number, String title,
          String subtitle, List<Widget> children) =>
      AppCard(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(10)),
                  child: Text(number,
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w900))),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 10),
            Text(subtitle,
                style: TextStyle(color: context.ejarzTheme.muted, height: 1.6)),
            ...children,
          ]));
}
