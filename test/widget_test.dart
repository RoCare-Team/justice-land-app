// Smoke tests for the pure helpers. The app root itself needs a live
// ApiClient (cookie jar on disk), so it is not pumped here.

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_legal_care/core/utils/formatters.dart';
import 'package:flutter_legal_care/core/utils/validators.dart';

void main() {
  group('Fmt', () {
    test('money renders rupees in the Indian grouping', () {
      expect(Fmt.money(1500), '₹1,500');
      expect(Fmt.money(null), '₹0');
    });

    test('clock pads minutes and seconds', () {
      expect(Fmt.clock(const Duration(minutes: 3, seconds: 7)), '03:07');
    });
  });

  group('Validators', () {
    test('accepts a real Indian mobile number', () {
      expect(Validators.isMobile('9876543210'), isTrue);
      expect(Validators.isMobile('1234567890'), isFalse);
    });

    test('checks email shape', () {
      expect(Validators.isEmail('a@b.co'), isTrue);
      expect(Validators.isEmail('nope'), isFalse);
    });
  });
}
