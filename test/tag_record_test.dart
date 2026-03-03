import 'package:flutter_test/flutter_test.dart';

import 'package:qrtags/models/tag_record.dart';

void main() {
  TagRecord sampleRecord() {
    return TagRecord.fromMap('tag-1', {
      'category': 'Gold22kt',
      'itemName': 'Sample Ring',
      'itemNameLower': 'sample ring',
      'makingType': 'PerGram',
      'makingCharge': '100',
      'grossWeight': '12.300',
      'lessWeight': '0.200',
      'netWeight': '12.100',
      'lessCategories': const <Map<String, dynamic>>[],
      'additionalTypes': const <Map<String, dynamic>>[],
      'inventoryPending': false,
      'inventoryAdded': true,
    });
  }

  test('matchesSearch supports tokenized text search', () {
    final record = sampleRecord();
    expect(record.matchesSearch('sample'), isTrue);
    expect(record.matchesSearch('sample ring'), isTrue);
    expect(record.matchesSearch('gold chain'), isFalse);
  });

  test('matchesSearch supports numeric weight prefix search', () {
    final record = sampleRecord();
    expect(record.matchesSearch('12.1'), isTrue);
    expect(record.matchesSearch('0.2'), isTrue);
    expect(record.matchesSearch('99.9'), isFalse);
  });
}
