import 'package:flutter_test/flutter_test.dart';
import 'package:aqood_pro/core/notification_service.dart';

void main() {
  tearDown(() {
    AppNotificationService.onNotificationTap = null;
  });

  test('pending notification tap is delivered once when navigation is ready', () {
    final received = <Map<String, dynamic>>[];
    AppNotificationService.deferNotificationTap(<String, dynamic>{
      'notificationId': 'notification-1',
      'actionType': 'contractDetails',
      'contractId': 'contract-1',
    });

    AppNotificationService.flushPendingNotificationTap();
    expect(received, isEmpty);

    AppNotificationService.onNotificationTap = received.add;
    AppNotificationService.flushPendingNotificationTap();
    AppNotificationService.flushPendingNotificationTap();

    expect(received, hasLength(1));
    expect(received.single['contractId'], 'contract-1');
  });
}
