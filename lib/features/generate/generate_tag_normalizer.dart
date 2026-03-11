import 'dart:convert';

class GenerateTagNormalizer {
  const GenerateTagNormalizer._();

  static String normalizedText(dynamic value) => value?.toString().trim() ?? '';

  static bool normalizedBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    final normalized = normalizedText(value).toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    return normalized != 'false' &&
        normalized != '0' &&
        normalized != 'no' &&
        normalized != 'off';
  }

  static List<String> normalizedLessEntries(dynamic raw) {
    if (raw is! List) {
      return const <String>[];
    }
    return raw
        .whereType<Map>()
        .map((entry) {
          final category = normalizedText(entry['category']);
          final value = normalizedText(entry['value']);
          return '$category|$value';
        })
        .where((line) => line != '|')
        .toList()
      ..sort();
  }

  static List<String> normalizedAdditionalEntries(dynamic raw) {
    if (raw is! List) {
      return const <String>[];
    }
    return raw
        .whereType<Map>()
        .map((entry) {
          final type = normalizedText(entry['type']);
          final value = normalizedText(entry['value']);
          return '$type|$value';
        })
        .where((line) => line != '|')
        .toList()
      ..sort();
  }

  static Map<String, dynamic> normalizedTagData(Map<String, dynamic> data) {
    return <String, dynamic>{
      'category': normalizedText(data['category']),
      'itemName': normalizedText(data['itemName']),
      'itemNameLower': normalizedText(data['itemNameLower']),
      'location': normalizedText(data['location']),
      'makingType': normalizedText(data['makingType']),
      'makingCharge': normalizedText(data['makingCharge']),
      'grossWeight': normalizedText(data['grossWeight']),
      'lessWeight': normalizedText(data['lessWeight']),
      'netWeight': normalizedText(data['netWeight']),
      'huid': normalizedBool(data['huid']),
      'lessCategories': normalizedLessEntries(data['lessCategories']),
      'additionalTypes': normalizedAdditionalEntries(data['additionalTypes']),
    };
  }

  static bool isUnchanged(
    Map<String, dynamic> original,
    Map<String, dynamic> next,
  ) {
    return jsonEncode(normalizedTagData(original)) ==
        jsonEncode(normalizedTagData(next));
  }
}
