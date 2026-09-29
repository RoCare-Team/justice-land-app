import 'package:flutter_legal_care/services/push_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses an allowed route the server sends', () {
    expect(pushRoute({'type': 'offer', 'route': '/services/property-dispute'}),
        '/services/property-dispute');
    expect(pushRoute({'type': 'message', 'route': '/lawyer/requests?tab=missed'}),
        '/lawyer/requests?tab=missed');
  });

  test('ignores a route that is not an app screen', () {
    expect(pushRoute({'type': 'offer', 'route': '/admin/users'}), '/services/all');
    expect(pushRoute({'type': 'message', 'route': 'https://evil.example/'}), '/');
    expect(pushRoute({'type': 'message', 'route': '/consultation/../admin/chat'}), '/');
  });

  test('falls back to the default for its type', () {
    expect(pushRoute({'type': 'consultation_update', 'consultationId': 'cns_7'}),
        '/consultation/cns_7/chat');
    expect(pushRoute({'type': 'chat_message'}), '/consultations');
    expect(pushRoute({'type': 'order_update'}), '/orders');
    expect(pushRoute({'type': 'wallet'}), '/wallet');
    expect(pushRoute({'type': 'blog', 'slug': 'rti-guide'}), '/blogs/rti-guide');
    expect(pushRoute({'type': 'lawyer_account', 'reason': 'plan_expiring'}), '/lawyer/plan');
    expect(pushRoute({'type': 'lawyer_account', 'reason': 'payout'}), '/lawyer/earnings');
    expect(pushRoute({'type': 'festival'}), '/');
    expect(pushRoute({'type': 'something_new'}), '/');
    expect(pushRoute({}), '/');
  });
}
