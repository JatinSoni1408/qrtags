import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qrtags/widgets/shared_item_form_layout.dart';

void main() {
  testWidgets('SharedItemFormLayout renders sections in order', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SharedItemFormLayout(
            primarySection: const Text('primary'),
            makingSection: const Text('making'),
            lessSection: const Text('less'),
            weightSection: const Text('weight'),
            additionalSection: const Text('additional'),
            footerSection: const Text('footer'),
          ),
        ),
      ),
    );

    expect(find.text('primary'), findsOneWidget);
    expect(find.text('making'), findsOneWidget);
    expect(find.text('less'), findsOneWidget);
    expect(find.text('weight'), findsOneWidget);
    expect(find.text('additional'), findsOneWidget);
    expect(find.text('footer'), findsOneWidget);
  });

  testWidgets('SharedFormSectionHeader triggers add action', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SharedFormSectionHeader(
            title: 'Less Categories',
            onAdd: () {
              tapped = true;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Add'));
    await tester.pump();

    expect(find.text('Less Categories'), findsOneWidget);
    expect(tapped, isTrue);
  });

  testWidgets('SharedFormEntryCard shows child and supports delete action', (
    tester,
  ) async {
    var deleted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SharedFormEntryCard(
            title: 'Less Entry 1',
            onDelete: () {
              deleted = true;
            },
            child: const Text('entry fields'),
          ),
        ),
      ),
    );

    expect(find.text('Less Entry 1'), findsOneWidget);
    expect(find.text('entry fields'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();

    expect(deleted, isTrue);
  });
}
