import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qrtags/pages/sales_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sales total respects stored gst flags', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'rate_gold22': 5000.0,
      'gst_enabled': true,
      'sales_items': <String>[
        '{"id":"A","category":"Gold22kt","itemName":"Ring","makingType":"PerGram","makingCharge":"0","netWeight":"1"}',
      ],
      'sales_items_gst': <String>['0'],
    });

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SalesPage())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Total: 5,000.00'), findsOneWidget);
  });
}
