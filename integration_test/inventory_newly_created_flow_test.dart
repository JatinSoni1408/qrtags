import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qrtags/data/tag_repository.dart';
import 'package:qrtags/pages/inventory_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'newly created item can be moved to inventory and shows as added',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('tags').doc('tag_1').set({
        'category': 'Gold24kt',
        'itemName': 'Sample Ring',
        'itemNameLower': 'sample ring',
        'makingType': 'PCS',
        'makingCharge': '100',
        'grossWeight': '12.500',
        'lessWeight': '0.000',
        'netWeight': '12.500',
        'lessCategories': const <Map<String, dynamic>>[],
        'additionalTypes': const <Map<String, dynamic>>[],
        'inventoryPending': true,
        'inventoryAdded': false,
        'createdAt': Timestamp.now(),
      });

      final repository = TagRepository(firestore: firestore);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InventoryPage(
              onEditTag: (_) {},
              tagRepository: repository,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'Newly Created'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Select items'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Move Selected'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'Inventory'));
      await tester.pumpAndSettle();

      const title = 'Gold24kt | Sample Ring';
      final titleFinder = find.text(title);
      expect(titleFinder, findsOneWidget);

      final titleText = tester.widget<Text>(titleFinder);
      expect(titleText.style?.color, Colors.green.shade700);

      final movedDoc = await firestore.collection('tags').doc('tag_1').get();
      expect(movedDoc.data()?['inventoryPending'], isFalse);
      expect(movedDoc.data()?['inventoryAdded'], isTrue);
    },
  );
}
