import 'package:aqdak/core/runtime_config.dart';
import 'package:aqdak/core/contract_pricing.dart';
import 'package:aqdak/core/models.dart';
import 'package:aqdak/core/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    AppRuntime.config = {};
    AppRuntime.payments = {};
  });
  test('published prices affect new drafts and preserve submitted amounts', () {
    final submitted = ContractDraft()..frozenTotal = 299;
    AppRuntime.config = {
      'pricing': {
        'residentialFirstYear': 350,
        'residentialAdditionalYear': 150,
        'commercialFirstYear': 450,
        'commercialAdditionalYear': 410
      }
    };
    expect(ContractPrice.calculate(commercial: false, years: 2).total, 500);
    expect(ContractDraft().totalPayable, 350);
    expect(submitted.totalPayable, 299);
    expect(ContractDraft.copyOf(submitted).totalPayable, 299);
  });
  test('offline submissions retain the amount reviewed before a price change',
      () async {
    final controller = AppController();
    final draft = ContractDraft();
    final submitted = await controller.submitContract(draft);
    expect(submitted.pendingSync, isTrue);
    expect(submitted.totalFees, 299);
    AppRuntime.config = {
      'pricing': {'residentialFirstYear': 350}
    };
    expect(draft.totalPayable, 350);
    expect(submitted.draftData?.totalPayable, 299);
    controller.dispose();
  });
  test('runtime controls services and required attachments with safe defaults',
      () {
    expect(AppRuntime.service('support'), isTrue);
    AppRuntime.config = {
      'services': {'support': false, 'voice': false},
      'attachments': {'lessor_id': false},
      'loginTitle': 'أهلًا بك'
    };
    expect(AppRuntime.service('support'), isFalse);
    expect(AppRuntime.service('residential'), isTrue);
    expect(AppRuntime.attachment('lessor_id', true), isFalse);
    expect(AppRuntime.text('loginTitle', 'دخول'), 'أهلًا بك');
    expect(
        AppRuntime.text('missing', 'القيمة الافتراضية'), 'القيمة الافتراضية');
  });
}
