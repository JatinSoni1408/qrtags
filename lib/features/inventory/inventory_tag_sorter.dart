import '../../models/tag_record.dart';

class InventoryTagSorter {
  const InventoryTagSorter._();

  static int compareByCategoryItemAndWeight(TagRecord a, TagRecord b) {
    final categoryCompare = _normalizedSortText(
      a.category,
    ).compareTo(_normalizedSortText(b.category));
    if (categoryCompare != 0) {
      return categoryCompare;
    }

    final aItem = a.itemNameLower.trim().isNotEmpty
        ? a.itemNameLower.trim()
        : _normalizedSortText(a.itemName);
    final bItem = b.itemNameLower.trim().isNotEmpty
        ? b.itemNameLower.trim()
        : _normalizedSortText(b.itemName);
    final itemCompare = aItem.compareTo(bItem);
    if (itemCompare != 0) {
      return itemCompare;
    }

    final weightCompare = _weightSortValue(
      a.netWeight,
    ).compareTo(_weightSortValue(b.netWeight));
    if (weightCompare != 0) {
      return weightCompare;
    }
    return a.id.compareTo(b.id);
  }

  static String _normalizedSortText(String value) => value.trim().toLowerCase();

  static double _weightSortValue(String value) {
    final normalized = value.trim().replaceAll(',', '');
    final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(normalized);
    if (match == null) {
      return double.infinity;
    }
    return double.tryParse(match.group(0) ?? '') ?? double.infinity;
  }
}
