import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qrtags/utils/price_calculator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'rate_gold22': 5000.0,
      'rate_gold18': 4200.0,
      'rate_silver': 90.0,
      'gst_enabled': true,
    });
  });

  test('calculateBreakdown applies per-gram math and GST', () async {
    final breakdown = await PriceCalculator.calculateBreakdown({
      'category': 'Gold22kt',
      'makingType': 'PerGram',
      'makingCharge': '100',
      'netWeight': '2',
      'additionalTypes': const <Map<String, dynamic>>[],
    });

    expect(breakdown.base, 10200.0);
    expect(breakdown.gst, 306.0);
    expect(breakdown.total, 10506.0);
  });

  test('fix-rate bypasses GST even when global GST is enabled', () async {
    final breakdown = await PriceCalculator.calculateBreakdown({
      'category': 'Gold22kt',
      'makingType': 'FixRate',
      'makingCharge': '2500',
      'netWeight': '1',
      'additionalTypes': const <Map<String, dynamic>>[],
    });

    expect(breakdown.base, 2500.0);
    expect(breakdown.gst, 0.0);
    expect(breakdown.total, 2500.0);
  });

  test('formatIndianAmount formats grouped currency', () {
    expect(PriceCalculator.formatIndianAmount(1234567.8), '12,34,567.80');
  });
}
