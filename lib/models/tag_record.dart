import 'package:cloud_firestore/cloud_firestore.dart';

class TagRecord {
  TagRecord({
    required this.id,
    required this.category,
    required this.itemName,
    required this.itemNameLower,
    required this.makingType,
    required this.makingCharge,
    required this.grossWeight,
    required this.lessWeight,
    required this.netWeight,
    required this.lessCategories,
    required this.additionalTypes,
    required this.inventoryPending,
    required this.inventoryAdded,
    this.inventoryQueued = false,
    required this.createdAt,
    required this.returnPurity,
    required this.rawData,
  });

  final String id;
  final String category;
  final String itemName;
  final String itemNameLower;
  final String makingType;
  final String makingCharge;
  final String grossWeight;
  final String lessWeight;
  final String netWeight;
  final List<Map<String, dynamic>> lessCategories;
  final List<Map<String, dynamic>> additionalTypes;
  final bool inventoryPending;
  final bool inventoryAdded;
  final bool inventoryQueued;
  final Timestamp? createdAt;
  final String returnPurity;
  final Map<String, dynamic> rawData;

  static List<Map<String, dynamic>> _parseEntries(dynamic raw) {
    if (raw is! List) {
      return const <Map<String, dynamic>>[];
    }
    final result = <Map<String, dynamic>>[];
    for (final entry in raw) {
      if (entry is Map) {
        result.add(Map<String, dynamic>.from(entry));
      }
    }
    return result;
  }

  factory TagRecord.fromMap(String id, Map<String, dynamic> data) {
    final normalized = Map<String, dynamic>.from(data);
    return TagRecord(
      id: id,
      category: normalized['category']?.toString() ?? '',
      itemName: normalized['itemName']?.toString() ?? '',
      itemNameLower: normalized['itemNameLower']?.toString().toLowerCase() ?? '',
      makingType: normalized['makingType']?.toString() ?? '',
      makingCharge: normalized['makingCharge']?.toString() ?? '',
      grossWeight: normalized['grossWeight']?.toString() ?? '',
      lessWeight: normalized['lessWeight']?.toString() ?? '',
      netWeight: normalized['netWeight']?.toString() ?? '',
      lessCategories: _parseEntries(normalized['lessCategories']),
      additionalTypes: _parseEntries(normalized['additionalTypes']),
      inventoryPending: normalized['inventoryPending'] == true,
      inventoryAdded: normalized['inventoryAdded'] == true,
      inventoryQueued: normalized['inventoryQueued'] == true,
      createdAt: normalized['createdAt'] is Timestamp
          ? normalized['createdAt'] as Timestamp
          : null,
      returnPurity: normalized['returnPurity']?.toString() ?? '',
      rawData: normalized,
    );
  }

  factory TagRecord.fromSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return TagRecord.fromMap(doc.id, doc.data());
  }

  String _normalizeSearchText(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  bool _matchesTextSearch(String searchLower) {
    final indexed = itemNameLower.trim().toLowerCase();
    final fallback = itemName.trim().toLowerCase();
    final value = _normalizeSearchText(indexed.isNotEmpty ? indexed : fallback);
    if (value.isEmpty) {
      return false;
    }
    final tokens = _normalizeSearchText(searchLower)
        .split(' ')
        .where((token) => token.isNotEmpty)
        .toList();
    if (tokens.isEmpty) {
      return true;
    }
    return tokens.every((token) => value.contains(token));
  }

  bool _isWeightSearchQuery(String query) {
    final cleaned = query.trim().replaceAll(',', '');
    if (cleaned.isEmpty) {
      return false;
    }
    if (!RegExp(r'^\d*\.?\d*$').hasMatch(cleaned)) {
      return false;
    }
    return RegExp(r'\d').hasMatch(cleaned);
  }

  String _normalizeWeightValue(String value) {
    final cleaned = value.trim().toLowerCase().replaceAll(',', '');
    final match = RegExp(r'-?\d+(?:\.\d*)?').firstMatch(cleaned);
    return match?.group(0) ?? cleaned;
  }

  bool _matchesWeightSearch(String searchLower) {
    final normalizedSearch = searchLower.trim().replaceAll(',', '');
    final weightValues = <String>[grossWeight, lessWeight, netWeight]
        .map(_normalizeWeightValue)
        .where((v) => v.isNotEmpty)
        .toList();
    return weightValues.any((weight) => weight.startsWith(normalizedSearch));
  }

  bool matchesSearch(String searchLower) {
    if (searchLower.isEmpty) {
      return true;
    }
    if (_matchesTextSearch(searchLower)) {
      return true;
    }
    return _isWeightSearchQuery(searchLower) && _matchesWeightSearch(searchLower);
  }

  int get createdAtMillis => createdAt?.millisecondsSinceEpoch ?? 0;

  Map<String, dynamic> toEditData() => Map<String, dynamic>.from(rawData);
}
