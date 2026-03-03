import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qrtags/models/edit_tag_request.dart';
import 'package:qrtags/pages/generate_page.dart';
import 'package:qrtags/pages/scan_page.dart';

TextField _findTextFieldByLabel(WidgetTester tester, String label) {
  final finder = find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );
  return tester.widget<TextField>(finder.first);
}

Future<void> _seedGenerateCollections(FirebaseFirestore firestore) async {
  await firestore.collection('categories').doc('gold22kt').set({
    'name': 'Gold22kt',
    'nameLower': 'gold22kt',
  });
  await firestore.collection('making_types_gold').doc('fixrate').set({
    'name': 'FixRate',
    'nameLower': 'fixrate',
  });
  await firestore.collection('making_types_silver').doc('pergram').set({
    'name': 'PerGram',
    'nameLower': 'pergram',
  });
  await firestore.collection('less_categories').doc('stones').set({
    'name': 'Stones',
    'nameLower': 'stones',
  });
  await firestore.collection('additional_types').doc('polishing').set({
    'name': 'Polishing',
    'nameLower': 'polishing',
  });
  await firestore.collection('item_names').doc('ring').set({
    'name': 'Ring',
    'nameLower': 'ring',
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const audioChannel = MethodChannel('xyz.luan/audioplayers');

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioChannel, (call) async {
          return null;
        });
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioChannel, null);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('Generate form recalculates less/net weights', (tester) async {
    final fakeStore = FakeFirebaseFirestore();
    await _seedGenerateCollections(fakeStore);
    final editRequest = ValueNotifier<EditTagRequest?>(null);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GeneratePage(editRequest: editRequest, firestore: fakeStore),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Gross Weight',
      ),
      '10',
    );
    await tester.enterText(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is TextField && widget.decoration?.labelText == 'Value',
          )
          .first,
      '2',
    );
    await tester.pumpAndSettle();

    expect(
      _findTextFieldByLabel(tester, 'Less Weight').controller?.text,
      '2.000',
    );
    expect(
      _findTextFieldByLabel(tester, 'Net Weight').controller?.text,
      '8.000',
    );
    expect(find.text('Create Tag'), findsOneWidget);
  });

  testWidgets('Scan manual item dialog adds an item', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'categories': <String>['Gold22kt'],
      'making_types_gold': <String>['FixRate'],
      'making_types_silver': <String>['PerGram'],
      'less_categories': <String>['Stones'],
      'additional_types': <String>['Polishing'],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScanPage(
            onSelectedAdded: () {},
            onShowTotal: () {},
            firestore: FakeFirebaseFirestore(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Manual Calculator'), findsOneWidget);

    await tester.tap(find.text('Manual Calculator'));
    await tester.pumpAndSettle();

    await tester.tap(
      find
          .byWidgetPredicate(
            (widget) => widget is DropdownButtonFormField<String>,
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gold22kt').last);
    await tester.pumpAndSettle();

    await tester.tap(
      find
          .byWidgetPredicate(
            (widget) => widget is DropdownButtonFormField<String>,
          )
          .at(1),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('FixRate').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Item Name',
      ),
      'Manual Ring',
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Making Charge',
      ),
      '100',
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Gross Weight',
      ),
      '5',
    );
    await tester.tap(find.text('Add To Scan'));
    await tester.pumpAndSettle();

    expect(find.text('Ring'), findsOneWidget);
  });
}
