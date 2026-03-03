import 'package:flutter_test/flutter_test.dart';

import 'package:qrtags/utils/share_file_namer.dart';

void main() {
  test('nextName follows {prefix}{token}_{nn}.{ext} format', () {
    final batch = ShareFileNamer.startBatch(prefix: 'pq', extension: 'png');
    final first = batch.nextName();

    expect(
      first,
      matches(RegExp(r'^[a-z]{2}[a-z0-9]{3}_[0-9]{2}\.[a-z0-9]+$')),
    );
  });

  test('counter increments deterministically within one batch', () {
    final batch = ShareFileNamer.startBatch(prefix: 'tb', extension: 'pdf');
    expect(batch.nextName(), matches(RegExp(r'^tb[a-z0-9]{3}_01\.pdf$')));
    expect(batch.nextName(), matches(RegExp(r'^tb[a-z0-9]{3}_02\.pdf$')));
    expect(batch.nextName(), matches(RegExp(r'^tb[a-z0-9]{3}_03\.pdf$')));
  });

  test('names are unique within a batch', () {
    final batch = ShareFileNamer.startBatch(prefix: 'gq', extension: 'png');
    final names = <String>{};
    for (int i = 0; i < 5; i++) {
      names.add(batch.nextName());
    }
    expect(names.length, 5);
  });

  test('different batches produce practically unique tokens', () {
    final seenTokens = <String>{};
    for (int i = 0; i < 8; i++) {
      final batch = ShareFileNamer.startBatch(prefix: 'ia', extension: 'pdf');
      final name = batch.nextName();
      final token = RegExp(
        r'^ia([a-z0-9]{3})_01\.pdf$',
      ).firstMatch(name)!.group(1)!;
      seenTokens.add(token);
    }
    expect(seenTokens.length > 1, isTrue);
  });

  test('generated filenames remain short', () {
    final batch = ShareFileNamer.startBatch(prefix: 'ns', extension: 'pdf');
    final name = batch.nextName();
    expect(name.length <= 12, isTrue);
  });

  test('sanitizes prefix and extension', () {
    final batch = ShareFileNamer.startBatch(prefix: 'N*', extension: '.P-D-F');
    expect(batch.nextName(), matches(RegExp(r'^nx[a-z0-9]{3}_01\.pdf$')));
  });
}
