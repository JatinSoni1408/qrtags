import 'package:flutter_test/flutter_test.dart';

import 'package:qrtags/features/selection/selected_items_state.dart';

void main() {
  test(
    'dedupeWithGstFlags preserves first occurrence and matching gst flag',
    () {
      final entries = SelectedItemsState.dedupeWithGstFlags(
        items: const <String>[
          '{"id":"A","itemName":"Ring"}',
          '{"id":"A","itemName":"Ring duplicate"}',
          '{"id":"B","itemName":"Chain"}',
        ],
        gstFlags: const <String>['0', '1', '1'],
      );

      expect(entries.length, 2);
      expect(entries[0].raw.contains('"id":"A"'), isTrue);
      expect(entries[0].gstEnabled, isFalse);
      expect(entries[1].raw.contains('"id":"B"'), isTrue);
      expect(entries[1].gstEnabled, isTrue);
    },
  );
}
