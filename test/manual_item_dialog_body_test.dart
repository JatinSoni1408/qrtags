import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qrtags/widgets/manual_item_dialog_body.dart';

void main() {
  testWidgets('shows loading indicator when loading is true', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ManualItemDialogBody(
            loading: true,
            usingFallbackMasterData: false,
            child: Text('form'),
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('form'), findsNothing);
  });

  testWidgets('shows fallback warning and child when loaded', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ManualItemDialogBody(
            loading: false,
            usingFallbackMasterData: true,
            child: Text('form'),
          ),
        ),
      ),
    );

    expect(find.text('form'), findsOneWidget);
    expect(
      find.text('Using fallback master data. Sync may be unavailable.'),
      findsOneWidget,
    );
  });
}
