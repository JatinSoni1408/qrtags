import 'package:shared_preferences/shared_preferences.dart';

class ScanSelectionState {
  const ScanSelectionState({
    required this.items,
    required this.gstEnabledFlags,
  });

  final List<String> items;
  final List<bool> gstEnabledFlags;
}

class ScanSelectionStore {
  const ScanSelectionStore();

  static const String _selectedItemsKey = 'selected_items';
  static const String _selectedItemsGstKey = 'selected_items_gst';

  Future<ScanSelectionState> load() async {
    final prefs = await SharedPreferences.getInstance();
    final items = prefs.getStringList(_selectedItemsKey) ?? <String>[];
    final savedGst = prefs.getStringList(_selectedItemsGstKey) ?? <String>[];
    final gstEnabledFlags = List<bool>.generate(
      items.length,
      (index) => index < savedGst.length ? savedGst[index] == '1' : true,
    );
    return ScanSelectionState(items: items, gstEnabledFlags: gstEnabledFlags);
  }

  Future<void> save({
    required List<String> items,
    required List<bool> gstEnabledFlags,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_selectedItemsKey, items);
    await prefs.setStringList(
      _selectedItemsGstKey,
      gstEnabledFlags.map((enabled) => enabled ? '1' : '0').toList(),
    );
  }
}
