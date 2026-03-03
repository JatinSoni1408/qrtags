import 'dart:convert';

class SelectedItemEntry {
  const SelectedItemEntry({required this.raw, required this.gstEnabled});

  final String raw;
  final bool gstEnabled;
}

class SelectedItemsState {
  const SelectedItemsState._();

  static List<SelectedItemEntry> dedupeWithGstFlags({
    required List<String> items,
    required List<String> gstFlags,
  }) {
    final seen = <String>{};
    final result = <SelectedItemEntry>[];
    for (int index = 0; index < items.length; index++) {
      final raw = items[index];
      final identity = _identity(raw);
      if (!seen.add(identity)) {
        continue;
      }
      result.add(
        SelectedItemEntry(
          raw: raw,
          gstEnabled: index < gstFlags.length ? gstFlags[index] == '1' : true,
        ),
      );
    }
    return result;
  }

  static String identity(String raw) => _identity(raw);

  static String _identity(String raw) {
    final text = raw.trim();
    final parsed = _tryParseJson(text);
    final id = parsed?['id']?.toString().trim() ?? '';
    if (id.isNotEmpty) {
      return 'id:$id';
    }
    return 'raw:$text';
  }

  static Map<String, dynamic>? _tryParseJson(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // ignore malformed payloads
    }
    return null;
  }
}
