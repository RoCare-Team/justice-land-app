import 'package:flutter_legal_care/services/push_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the type decides the screen; a route from the server is ignored', () {
    expect(pushRoute({'type': 'message', 'route': '/lawyer/earnings'}), '/');
    expect(pushRoute({'type': 'offer', 'route': '/admin/users'}), '/services/all');
    expect(pushRoute({'type': 'message', 'route': 'https://evil.example/'}), '/');
  });

  test("a client's screens", () {
    expect(pushRoute({'type': 'message'}), '/');
    expect(pushRoute({'type': 'festival'}), '/');
    expect(pushRoute({'type': 'announcement'}), '/');
    expect(pushRoute({'type': 'offer'}), '/services/all');
    expect(pushRoute({'type': 'wallet'}), '/wallet');
    expect(pushRoute({'type': 'order_update'}), '/orders');
    expect(pushRoute({'type': 'consultation_update', 'consultationId': 'cns_7'}),
        '/consultation/cns_7/chat');
    expect(pushRoute({'type': 'chat_message'}), '/consultations');
    expect(pushRoute({'type': 'lawyer_account', 'reason': 'payout'}), '/');
    expect(pushRoute({'type': 'something_new'}), '/');
    expect(pushRoute({}), '/');
  });

  test("a lawyer's screens", () {
    String open(Map<String, dynamic> data) => pushRoute(data, lawyer: true);
    expect(open({'type': 'message'}), '/lawyer');
    expect(open({'type': 'festival'}), '/lawyer');
    expect(open({'type': 'offer'}), '/lawyer/plan');
    expect(open({'type': 'wallet'}), '/lawyer/earnings');
    expect(open({'type': 'order_update'}), '/lawyer');
    expect(open({'type': 'chat_message', 'consultationId': 'cns_7'}), '/consultation/cns_7/chat');
    expect(open({'type': 'consultation_update'}), '/lawyer/consultations');
    expect(open({'type': 'consultation_request'}), '/lawyer');
    expect(open({'type': 'lawyer_account', 'reason': 'plan_expiring'}), '/lawyer/plan');
    expect(open({'type': 'lawyer_account', 'reason': 'payout'}), '/lawyer/earnings');
    expect(open({'type': 'lawyer_account', 'reason': 'verified'}), '/lawyer/profile');
  });

  test('a blog opens its article, and only a plain slug', () {
    expect(pushRoute({'type': 'blog', 'slug': 'rti-guide'}), '/blogs/rti-guide');
    expect(pushRoute({'type': 'blog', 'slug': '../admin'}), '/blogs');
    expect(pushRoute({'type': 'blog'}), '/blogs');
  });
}
