import 'package:flutter_test/flutter_test.dart';

import 'package:qrtags/features/total/payment_entry_calculator.dart';

void main() {
  test('sumByModes aggregates only matching modes', () {
    final entries = <PaymentEntryValue>[
      const PaymentEntryValue(mode: 'Cash', amount: 1000),
      const PaymentEntryValue(mode: 'UPI', amount: 2500.5),
      const PaymentEntryValue(mode: 'Banking', amount: 500),
      const PaymentEntryValue(mode: 'cash', amount: 250),
    ];

    final cashOnly = PaymentEntryCalculator.sumByModes(entries, {'Cash'});
    final upiAndBank = PaymentEntryCalculator.sumByModes(entries, {
      'UPI',
      'Banking',
    });

    expect(cashOnly, 1250);
    expect(upiAndBank, 3000.5);
  });

  test('isUpiOnlyMode matches only UPI', () {
    expect(PaymentEntryCalculator.isUpiOnlyMode('UPI'), isTrue);
    expect(PaymentEntryCalculator.isUpiOnlyMode(' upi '), isTrue);
    expect(PaymentEntryCalculator.isUpiOnlyMode('Banking'), isFalse);
    expect(PaymentEntryCalculator.isUpiOnlyMode('Cash'), isFalse);
  });

  test('isNonCashMode matches UPI and Banking', () {
    expect(PaymentEntryCalculator.isNonCashMode('UPI'), isTrue);
    expect(PaymentEntryCalculator.isNonCashMode('banking'), isTrue);
    expect(PaymentEntryCalculator.isNonCashMode('Cash'), isFalse);
  });
}
