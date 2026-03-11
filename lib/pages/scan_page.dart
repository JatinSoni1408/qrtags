import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../features/scan/scan_selection_store.dart';
import '../utils/selection_notifier.dart';
import '../widgets/settings_button.dart';
import '../widgets/manual_item_dialog_body.dart';
import '../widgets/shared_item_form_layout.dart';
import '../utils/price_calculator.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({
    super.key,
    required this.onSelectedAdded,
    required this.onShowTotal,
    this.firestore,
  });

  final VoidCallback onSelectedAdded;
  final VoidCallback onShowTotal;
  final FirebaseFirestore? firestore;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  static const ScanSelectionStore _selectionStore = ScanSelectionStore();
  late final FirebaseFirestore _firestore;
  late final AudioPlayer _audioPlayer;
  bool _isScanning = false;
  final List<String> _scannedResults = [];
  final List<bool> _gstEnabledByItem = [];
  double _totalAmount = 0.0;
  double _totalGst = 0.0;
  final Map<String, double> _totalByGroup = {
    'Gold22kt': 0.0,
    'Gold18kt': 0.0,
    'Silver': 0.0,
    'Other': 0.0,
  };
  bool _globalGstEnabled = true;
  bool _makingEnabled = false;
  Timer? _recalcDebounceTimer;
  _ScanSortMode _sortMode = _ScanSortMode.newestFirst;

  @override
  void initState() {
    super.initState();
    _firestore = widget.firestore ?? FirebaseFirestore.instance;
    _audioPlayer = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
    _loadGlobalGst();
    unawaited(_syncSelectedListsFromScanned());
    SettingsButton.ratesVersion.addListener(_handleRatesUpdated);
  }

  @override
  void dispose() {
    _recalcDebounceTimer?.cancel();
    SettingsButton.ratesVersion.removeListener(_handleRatesUpdated);
    _audioPlayer.dispose();
    super.dispose();
  }

  void _handleRatesUpdated() {
    _loadGlobalGst();
  }

  Future<void> _loadGlobalGst() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('gst_enabled') ?? true;
    final makingEnabled = prefs.getBool('making_enabled') ?? false;
    if (!mounted) {
      return;
    }
    setState(() {
      _globalGstEnabled = enabled;
      _makingEnabled = makingEnabled;
      if (!_globalGstEnabled) {
        for (int i = 0; i < _gstEnabledByItem.length; i++) {
          _gstEnabledByItem[i] = true;
        }
      }
    });
    _scheduleRecalculateTotals();
  }

  void _scheduleRecalculateTotals({
    Duration delay = const Duration(milliseconds: 140),
  }) {
    _recalcDebounceTimer?.cancel();
    _recalcDebounceTimer = Timer(delay, () {
      if (!mounted) {
        return;
      }
      unawaited(_recalculateTotals());
    });
  }

  Future<void> _playSendSound() async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(
        AssetSource('sounds/universfield-new-notification-09-352705.mp3'),
        volume: 1.0,
      );
    } catch (_) {
      // ignore playback errors
    }
  }

  Future<void> _scanWithCamera() async {
    if (_isScanning) {
      return;
    }
    setState(() {
      _isScanning = true;
    });
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (context) => const _LiveQrScannerPage()),
    );
    if (!mounted) {
      return;
    }
    if (result != null && result.isNotEmpty) {
      final resolved = await _resolvePayload(result);
      await _handleScanned(resolved);
    }
    setState(() {
      _isScanning = false;
    });
  }

  Future<String> _resolvePayload(String value) async {
    final text = value;
    if (text.startsWith('QR1:')) {
      final id = text.substring(4);
      final data = await _fetchRemoteRecord(id);
      if (data != null) {
        return jsonEncode(data);
      }
    }
    return text;
  }

  Future<Map<String, dynamic>?> _fetchRemoteRecord(String id) async {
    try {
      final doc = await _firestore.collection('tags').doc(id).get();
      if (!doc.exists) {
        return null;
      }
      final data = doc.data();
      if (data == null) {
        return null;
      }
      final cleaned = _sanitizeFirestoreData(Map<String, dynamic>.from(data));
      cleaned['id'] = id;
      cleaned.remove('createdAt');
      cleaned.remove('updatedAt');
      return cleaned;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _sanitizeFirestoreData(Map<String, dynamic> data) {
    final cleaned = <String, dynamic>{};
    for (final entry in data.entries) {
      final value = entry.value;
      if (value is Timestamp) {
        continue;
      } else if (value is Map<String, dynamic>) {
        cleaned[entry.key] = _sanitizeFirestoreData(value);
      } else if (value is Map) {
        cleaned[entry.key] = _sanitizeFirestoreData(
          value.cast<String, dynamic>(),
        );
      } else if (value is List) {
        cleaned[entry.key] = value
            .map((item) {
              if (item is Map<String, dynamic>) {
                return _sanitizeFirestoreData(item);
              }
              if (item is Map) {
                return _sanitizeFirestoreData(item.cast<String, dynamic>());
              }
              if (item is Timestamp) {
                return null;
              }
              return item;
            })
            .where((e) => e != null)
            .toList();
      } else {
        cleaned[entry.key] = value;
      }
    }
    return cleaned;
  }

  Map<String, dynamic>? _tryParseJson(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  bool _hasHuid(Map<String, dynamic> data) {
    final raw = data['huid'];
    if (raw is bool) {
      return raw;
    }
    final normalized = raw?.toString().trim().toLowerCase() ?? '';
    if (normalized.isEmpty) {
      return false;
    }
    return normalized != 'false' &&
        normalized != '0' &&
        normalized != 'no' &&
        normalized != 'off';
  }

  String _payloadIdentity(String payload) {
    final raw = payload.trim();
    if (raw.startsWith('QR1:')) {
      final id = raw.substring(4).trim();
      if (id.isNotEmpty) {
        return 'id:$id';
      }
    }
    final parsed = _tryParseJson(raw);
    final id = parsed?['id']?.toString().trim() ?? '';
    if (id.isNotEmpty) {
      return 'id:$id';
    }
    return 'raw:$raw';
  }

  void _upsertScannedPayload(String payload) {
    final identity = _payloadIdentity(payload);
    final parsed = _tryParseJson(payload);
    final huidMandatory = parsed != null ? _hasHuid(parsed) : false;
    bool gstEnabled = true;
    for (int i = _scannedResults.length - 1; i >= 0; i--) {
      if (_payloadIdentity(_scannedResults[i]) == identity) {
        if (i < _gstEnabledByItem.length) {
          gstEnabled = _gstEnabledByItem[i];
          _gstEnabledByItem.removeAt(i);
        }
        _scannedResults.removeAt(i);
      }
    }
    _scannedResults.insert(0, payload);
    _gstEnabledByItem.insert(0, huidMandatory ? true : gstEnabled);
  }

  Future<void> _handleScannedBatch(List<String> payloads) async {
    if (payloads.isEmpty) {
      return;
    }
    setState(() {
      for (final payload in payloads) {
        _upsertScannedPayload(payload);
      }
    });
    await _playSendSound();
    await _persistSelectedLists();
    await _recalculateTotals();
  }

  Future<void> _handleScanned(String payload) async {
    await _handleScannedBatch([payload]);
  }

  Future<void> _recalculateTotals() async {
    double sum = 0.0;
    double gstSum = 0.0;
    double gold22Sum = 0.0;
    double gold18Sum = 0.0;
    double silverSum = 0.0;
    double otherSum = 0.0;
    for (int i = 0; i < _scannedResults.length; i++) {
      final item = _scannedResults[i];
      final parsed = _tryParseJson(item);
      if (parsed == null) {
        continue;
      }
      final category = parsed['category']?.toString() ?? '';
      final huidMandatory = _hasHuid(parsed);
      final gstEnabled = huidMandatory
          ? true
          : (_globalGstEnabled
                ? (i < _gstEnabledByItem.length ? _gstEnabledByItem[i] : true)
                : true);
      final breakdown = await PriceCalculator.calculateBreakdown(
        parsed,
        gstEnabledOverride: gstEnabled,
      );
      sum += breakdown.total;
      gstSum += breakdown.gst;
      if (category == 'Gold22kt') {
        gold22Sum += breakdown.total;
      } else if (category == 'Gold18kt') {
        gold18Sum += breakdown.total;
      } else if (category == 'Silver') {
        silverSum += breakdown.total;
      } else {
        otherSum += breakdown.total;
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _totalAmount = sum;
      _totalGst = gstSum;
      _totalByGroup['Gold22kt'] = gold22Sum;
      _totalByGroup['Gold18kt'] = gold18Sum;
      _totalByGroup['Silver'] = silverSum;
      _totalByGroup['Other'] = otherSum;
    });
  }

  Future<void> _syncSelectedListsFromScanned() async {
    if (_scannedResults.isNotEmpty) {
      return;
    }
    final saved = await _selectionStore.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _scannedResults
        ..clear()
        ..addAll(saved.items);
      _gstEnabledByItem
        ..clear()
        ..addAll(saved.gstEnabledFlags);
      for (int i = 0; i < _scannedResults.length; i++) {
        final parsed = _tryParseJson(_scannedResults[i]);
        if (parsed == null || !_hasHuid(parsed)) {
          continue;
        }
        if (i < _gstEnabledByItem.length) {
          _gstEnabledByItem[i] = true;
        } else {
          _gstEnabledByItem.add(true);
        }
      }
    });
    await _recalculateTotals();
  }

  Future<void> _updateMakingCharge(int index, String value) async {
    if (index < 0 || index >= _scannedResults.length) {
      return;
    }
    final parsed = _tryParseJson(_scannedResults[index]);
    if (parsed == null) {
      return;
    }
    parsed['makingCharge'] = value.trim();
    setState(() {
      _scannedResults[index] = jsonEncode(parsed);
    });
    await _persistSelectedLists();
    _scheduleRecalculateTotals();
  }

  Future<void> _resetScannedItems() async {
    setState(() {
      _scannedResults.clear();
      _gstEnabledByItem.clear();
    });
    await _persistSelectedLists();
    await _recalculateTotals();
  }

  List<MapEntry<int, String>> _sortEntries(List<MapEntry<int, String>> list) {
    final sorted = List<MapEntry<int, String>>.from(list);
    switch (_sortMode) {
      case _ScanSortMode.newestFirst:
        sorted.sort((a, b) => a.key.compareTo(b.key));
      case _ScanSortMode.oldestFirst:
        sorted.sort((a, b) => b.key.compareTo(a.key));
      case _ScanSortMode.nameAsc:
        sorted.sort((a, b) {
          final aName =
              _tryParseJson(a.value)?['itemName']?.toString().toLowerCase() ??
              '';
          final bName =
              _tryParseJson(b.value)?['itemName']?.toString().toLowerCase() ??
              '';
          return aName.compareTo(bName);
        });
    }
    return sorted;
  }

  Future<void> _removeWithUndo(int index) async {
    if (index < 0 || index >= _scannedResults.length) {
      return;
    }
    final removedRaw = _scannedResults[index];
    final removedGst = index < _gstEnabledByItem.length
        ? _gstEnabledByItem[index]
        : true;
    setState(() {
      _scannedResults.removeAt(index);
      if (_gstEnabledByItem.length > index) {
        _gstEnabledByItem.removeAt(index);
      }
    });
    await _persistSelectedLists();
    _scheduleRecalculateTotals();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Item removed'),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.fixed,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            if (!mounted) {
              return;
            }
            setState(() {
              final restoreIndex = index.clamp(0, _scannedResults.length);
              _scannedResults.insert(restoreIndex, removedRaw);
              _gstEnabledByItem.insert(restoreIndex, removedGst);
            });
            _persistSelectedLists();
            _scheduleRecalculateTotals();
          },
        ),
      ),
    );
    // Auto-dismiss after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
    });
  }

  Future<void> _showManualCalculator() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _ManualItemDialog(firestore: _firestore),
    );
    if (result == null) {
      return;
    }
    if (_isDuplicateManualEntry(result)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Duplicate manual item not added')),
        );
      }
      return;
    }
    await _handleScanned(jsonEncode(result));
  }

  Future<void> _editManualItem(int index, Map<String, dynamic> existing) async {
    if (index < 0 || index >= _scannedResults.length) {
      return;
    }
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) =>
          _ManualItemDialog(initialData: existing, firestore: _firestore),
    );
    if (result == null) {
      return;
    }
    if (_isDuplicateManualEntry(result, ignoreId: existing['id']?.toString())) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Duplicate manual item not saved')),
        );
      }
      return;
    }
    setState(() {
      _scannedResults[index] = jsonEncode(result);
    });
    await _persistSelectedLists();
    await _recalculateTotals();
  }

  bool _isDuplicateManualEntry(
    Map<String, dynamic> candidate, {
    String? ignoreId,
  }) {
    String norm(dynamic v) => (v?.toString() ?? '').trim().toLowerCase();
    final candidateId = norm(candidate['id']);
    final itemName = norm(candidate['itemName']);
    final category = norm(candidate['category']);
    final makingType = norm(candidate['makingType']);
    final makingCharge = norm(candidate['makingCharge']);
    final netWeight = norm(candidate['netWeight']);
    if (itemName.isEmpty || category.isEmpty || netWeight.isEmpty) {
      return false;
    }
    for (final raw in _scannedResults) {
      final parsed = _tryParseJson(raw);
      if (parsed == null || parsed['entrySource']?.toString() != 'manual') {
        continue;
      }
      final parsedId = norm(parsed['id']);
      if (ignoreId != null && parsedId == ignoreId.trim().toLowerCase()) {
        continue;
      }
      if (candidateId.isNotEmpty && parsedId == candidateId) {
        continue;
      }
      if (norm(parsed['itemName']) == itemName &&
          norm(parsed['category']) == category &&
          norm(parsed['makingType']) == makingType &&
          norm(parsed['makingCharge']) == makingCharge &&
          norm(parsed['netWeight']) == netWeight) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<_ScanSortMode>(
                          initialValue: _sortMode,
                          decoration: const InputDecoration(labelText: 'Sort'),
                          items: const [
                            DropdownMenuItem(
                              value: _ScanSortMode.newestFirst,
                              child: Text('Newest First'),
                            ),
                            DropdownMenuItem(
                              value: _ScanSortMode.oldestFirst,
                              child: Text('Oldest First'),
                            ),
                            DropdownMenuItem(
                              value: _ScanSortMode.nameAsc,
                              child: Text('Name A-Z'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setState(() {
                              _sortMode = value;
                            });
                          },
                        ),
                      ),
                      if (_scannedResults.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _resetScannedItems,
                          icon: const Icon(Icons.restart_alt),
                          label: const Text('Reset'),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_scannedResults.isNotEmpty) ...[
                    ..._buildGroupedItems(),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isScanning ? null : _scanWithCamera,
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Scan QR'),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _showManualCalculator,
                        icon: const Icon(Icons.edit_note),
                        label: const Text('Add New Item Manually'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: const [
                BoxShadow(
                  blurRadius: 6,
                  color: Colors.black12,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Items: ${_scannedResults.length}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  'GST: ${PriceCalculator.formatIndianAmount(_totalGst)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 12),
                Text(
                  'Total: ${PriceCalculator.formatIndianAmount(_totalAmount)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGroupedItems() {
    final groups = <String, List<MapEntry<int, String>>>{
      'Gold22kt': [],
      'Gold18kt': [],
      'Silver': [],
      'Other': [],
    };
    for (final entry in _scannedResults.asMap().entries) {
      final parsed = _tryParseJson(entry.value);
      final category = parsed?['category']?.toString() ?? '';
      if (category == 'Gold22kt') {
        groups['Gold22kt']!.add(entry);
      } else if (category == 'Gold18kt') {
        groups['Gold18kt']!.add(entry);
      } else if (category == 'Silver') {
        groups['Silver']!.add(entry);
      } else {
        groups['Other']!.add(entry);
      }
    }

    List<Widget> buildSection(String title, List<MapEntry<int, String>> list) {
      if (list.isEmpty) {
        return [];
      }
      final orderedList = _sortEntries(list);
      final total = _totalByGroup[title] ?? 0.0;
      return [
        Row(
          children: [
            Expanded(
              child: Text(
                '${_sectionLabel(title)} Items',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Text(
              PriceCalculator.formatIndianAmount(total),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...orderedList.map((entry) {
          final index = entry.key;
          final value = entry.value;
          final itemParsed = _tryParseJson(value);
          final huidMandatory = itemParsed != null
              ? _hasHuid(itemParsed)
              : false;
          final itemGstEnabled = huidMandatory
              ? true
              : (_gstEnabledByItem.length > index
                    ? _gstEnabledByItem[index]
                    : true);
          final isManualEntry =
              itemParsed?['entrySource']?.toString() == 'manual';
          final colors = _scanItemColors(context, itemParsed);
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: colors.cardColor,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: itemParsed != null
                        ? _ScanResultCard(
                            data: itemParsed,
                            headingBgColor: colors.headingBgColor,
                            headingTextColor: colors.headingTextColor,
                            amountTextColor: colors.amountTextColor,
                            gstEnabled: itemGstEnabled,
                            canEditGst: _globalGstEnabled && !huidMandatory,
                            canEditMaking: _makingEnabled,
                            onMakingChanged: (value) {
                              _updateMakingCharge(index, value);
                            },
                            onGstChanged: (enabled) {
                              if (!_globalGstEnabled || huidMandatory) {
                                return;
                              }
                              setState(() {
                                if (_gstEnabledByItem.length <= index) {
                                  _gstEnabledByItem.addAll(
                                    List<bool>.filled(
                                      (_scannedResults.length -
                                          _gstEnabledByItem.length),
                                      true,
                                    ),
                                  );
                                }
                                _gstEnabledByItem[index] = enabled;
                              });
                              _persistSelectedLists();
                              _scheduleRecalculateTotals();
                            },
                          )
                        : Text(value),
                  ),
                  if (isManualEntry && itemParsed != null)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          tooltip: 'Edit manual item',
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          onPressed: () {
                            _editManualItem(index, itemParsed);
                          },
                        ),
                        const SizedBox(height: 2),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          tooltip: 'Remove',
                          icon: const Icon(Icons.delete, size: 20),
                          onPressed: () {
                            _removeWithUndo(index);
                          },
                        ),
                      ],
                    )
                  else
                    IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.delete),
                      onPressed: () {
                        _removeWithUndo(index);
                      },
                    ),
                ],
              ),
            ),
          );
        }),
      ];
    }

    return [
      ...buildSection('Gold22kt', groups['Gold22kt']!),
      ...buildSection('Gold18kt', groups['Gold18kt']!),
      ...buildSection('Silver', groups['Silver']!),
      ...buildSection('Other', groups['Other']!),
    ];
  }

  String _sectionLabel(String key) {
    switch (key) {
      case 'Gold22kt':
        return 'Gold 22kt';
      case 'Gold18kt':
        return 'Gold 18kt';
      default:
        return key;
    }
  }

  _ScanItemColors _scanItemColors(
    BuildContext context,
    Map<String, dynamic>? item,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isManual = item?['entrySource']?.toString() == 'manual';
    final category = item?['category']?.toString() ?? '';

    if (isManual) {
      if (category == 'Gold22kt') {
        return isDark
            ? const _ScanItemColors(
                cardColor: Color(0xFF523B00),
                headingBgColor: Color(0xFFFFD25F),
                headingTextColor: Color(0xFF3A2600),
                amountTextColor: Color(0xFFFFE39A),
              )
            : const _ScanItemColors(
                cardColor: Color(0xFFFFF2C7),
                headingBgColor: Color(0xFFFFCF52),
                headingTextColor: Color(0xFF6B4500),
                amountTextColor: Color(0xFF8A5C00),
              );
      }
      if (category == 'Gold18kt') {
        return isDark
            ? const _ScanItemColors(
                cardColor: Color(0xFF5A2F10),
                headingBgColor: Color(0xFFFFB987),
                headingTextColor: Color(0xFF4B1F00),
                amountTextColor: Color(0xFFFFD0AA),
              )
            : const _ScanItemColors(
                cardColor: Color(0xFFFFE4CD),
                headingBgColor: Color(0xFFFFB67B),
                headingTextColor: Color(0xFF7A3400),
                amountTextColor: Color(0xFF9E4600),
              );
      }
      if (category == 'Silver') {
        return isDark
            ? const _ScanItemColors(
                cardColor: Color(0xFF2C2F4A),
                headingBgColor: Color(0xFFAAB4FF),
                headingTextColor: Color(0xFF1A1E45),
                amountTextColor: Color(0xFFD7DCFF),
              )
            : const _ScanItemColors(
                cardColor: Color(0xFFECEEFD),
                headingBgColor: Color(0xFFB9C5FF),
                headingTextColor: Color(0xFF2A3678),
                amountTextColor: Color(0xFF3D4D97),
              );
      }
      return isDark
          ? const _ScanItemColors(
              cardColor: Color(0xFF2E3E45),
              headingBgColor: Color(0xFF97CDD9),
              headingTextColor: Color(0xFF18323C),
              amountTextColor: Color(0xFFC9EAF0),
            )
          : const _ScanItemColors(
              cardColor: Color(0xFFE9F7FA),
              headingBgColor: Color(0xFF9FD9E6),
              headingTextColor: Color(0xFF1D4F5C),
              amountTextColor: Color(0xFF2B6A78),
            );
    }

    if (category == 'Gold22kt') {
      return isDark
          ? const _ScanItemColors(
              cardColor: Color(0xFF3F3300),
              headingBgColor: Color(0xFFE7CF7A),
              headingTextColor: Color(0xFF2E2400),
              amountTextColor: Color(0xFFFFE8A1),
            )
          : const _ScanItemColors(
              cardColor: Color(0xFFFFF8E1),
              headingBgColor: Color(0xFFFFE39B),
              headingTextColor: Color(0xFF5B4300),
              amountTextColor: Color(0xFF8C6400),
            );
    }

    if (category == 'Gold18kt') {
      return isDark
          ? const _ScanItemColors(
              cardColor: Color(0xFF4A350B),
              headingBgColor: Color(0xFFFFD79A),
              headingTextColor: Color(0xFF4A2B00),
              amountTextColor: Color(0xFFFFE0B3),
            )
          : const _ScanItemColors(
              cardColor: Color(0xFFFFF0D9),
              headingBgColor: Color(0xFFFFD6A0),
              headingTextColor: Color(0xFF6A3F00),
              amountTextColor: Color(0xFF955500),
            );
    }

    if (category == 'Silver') {
      return isDark
          ? const _ScanItemColors(
              cardColor: Color(0xFF1F3347),
              headingBgColor: Color(0xFF8AB2D9),
              headingTextColor: Color(0xFF102738),
              amountTextColor: Color(0xFFCDE3F8),
            )
          : const _ScanItemColors(
              cardColor: Color(0xFFF0F5FB),
              headingBgColor: Color(0xFFC3D8EE),
              headingTextColor: Color(0xFF1A3C5A),
              amountTextColor: Color(0xFF2A5B86),
            );
    }

    return isDark
        ? const _ScanItemColors(
            cardColor: Color(0xFF243A2A),
            headingBgColor: Color(0xFF8FC39A),
            headingTextColor: Color(0xFF13351E),
            amountTextColor: Color(0xFFC6EED0),
          )
        : const _ScanItemColors(
            cardColor: Color(0xFFEFF8EF),
            headingBgColor: Color(0xFFC2E7C8),
            headingTextColor: Color(0xFF1C5A28),
            amountTextColor: Color(0xFF2F7B3D),
          );
  }

  Future<void> _persistSelectedLists() async {
    await _selectionStore.save(
      items: _scannedResults,
      gstEnabledFlags: _gstEnabledByItem,
    );
    SelectionNotifier.notify();
    widget.onSelectedAdded();
  }
}

class _LiveQrScannerPage extends StatefulWidget {
  const _LiveQrScannerPage();

  @override
  State<_LiveQrScannerPage> createState() => _LiveQrScannerPageState();
}

class _ManualItemDialog extends StatefulWidget {
  const _ManualItemDialog({this.initialData, required this.firestore});

  final Map<String, dynamic>? initialData;
  final FirebaseFirestore firestore;

  @override
  State<_ManualItemDialog> createState() => _ManualItemDialogState();
}

class _ManualItemDialogState extends State<_ManualItemDialog> {
  static const String _lessCategoriesCollection = 'less_categories';
  static const String _additionalTypesCollection = 'additional_types';
  static const List<String> _defaultCategories = [
    'Gold22kt',
    'Gold18kt',
    'Silver',
  ];
  static const List<String> _defaultMakingTypesGold = [
    'FixRate',
    'Percentage',
    'TotalMaking',
  ];
  static const List<String> _defaultMakingTypesSilver = [
    'PerGram',
    'TotalMaking',
    'FixRate',
  ];
  static const List<String> _defaultLessCategories = [
    'Stones',
    'Meena',
    'Kundan',
  ];
  static const List<String> _defaultAdditionalTypes = [
    'Stone Settings',
    'Kundan Work',
    'Meenakari',
    'Frosting',
    'Gheru',
    'Sandblasting',
    'Polishing',
    'Brushing',
  ];
  static const List<String> _returnPurityOptions = [
    '50%',
    '60%',
    '70%',
    '80%',
    '92%',
  ];

  final TextEditingController _itemNameController = TextEditingController();
  final TextEditingController _makingChargeController = TextEditingController();
  final TextEditingController _grossWeightController = TextEditingController();
  final TextEditingController _lessWeightController = TextEditingController();
  final TextEditingController _netWeightController = TextEditingController();

  final List<_ManualLessEntryDraft> _lessEntries = [_ManualLessEntryDraft()];
  final List<_ManualAdditionalEntryDraft> _additionalEntries = [
    _ManualAdditionalEntryDraft(),
  ];
  late final FirebaseFirestore _firestore;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _lessCategoriesSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _additionalTypesSub;
  bool _seedingLessCategories = false;
  bool _seedingAdditionalTypes = false;

  List<String> _categories = List<String>.from(_defaultCategories);
  List<String> _makingTypesGold = List<String>.from(_defaultMakingTypesGold);
  List<String> _makingTypesSilver = List<String>.from(
    _defaultMakingTypesSilver,
  );
  List<String> _lessCategories = List<String>.from(_defaultLessCategories);
  List<String> _additionalTypes = List<String>.from(_defaultAdditionalTypes);

  String? _selectedCategory;
  String? _selectedMakingType;
  String? _selectedReturnPurity;
  bool _loading = true;
  bool _submitted = false;
  bool _usingFallbackMasterData = false;

  String _normalizeLessCategory(String value) => value.trim();

  String _lessCategoryDocId(String value) => value.trim().toLowerCase();

  CollectionReference<Map<String, dynamic>> get _lessCategoriesRef =>
      _firestore.collection(_lessCategoriesCollection);

  String _normalizeAdditionalType(String value) => value.trim();

  String _additionalTypeDocId(String value) => value.trim().toLowerCase();

  CollectionReference<Map<String, dynamic>> get _additionalTypesRef =>
      _firestore.collection(_additionalTypesCollection);

  void _sortList(List<String> values) {
    values.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  @override
  void initState() {
    super.initState();
    _firestore = widget.firestore;
    _grossWeightController.addListener(_recalculateWeights);
    for (final entry in _lessEntries) {
      entry.valueController.addListener(_recalculateWeights);
    }
    _loadMasterData();
  }

  @override
  void dispose() {
    _lessCategoriesSub?.cancel();
    _additionalTypesSub?.cancel();
    _itemNameController.dispose();
    _makingChargeController.dispose();
    _grossWeightController.dispose();
    _lessWeightController.dispose();
    _netWeightController.dispose();
    for (final entry in _lessEntries) {
      entry.dispose();
    }
    for (final entry in _additionalEntries) {
      entry.dispose();
    }
    super.dispose();
  }

  Future<void> _loadMasterData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final categories = prefs.getStringList('categories');
      final makingGold = prefs.getStringList('making_types_gold');
      final makingSilver = prefs.getStringList('making_types_silver');
      final lessCategories = prefs.getStringList('less_categories');
      final additionalTypes = prefs.getStringList('additional_types');

      setState(() {
        _usingFallbackMasterData =
            categories == null ||
            categories.isEmpty ||
            makingGold == null ||
            makingGold.isEmpty ||
            makingSilver == null ||
            makingSilver.isEmpty ||
            lessCategories == null ||
            lessCategories.isEmpty ||
            additionalTypes == null ||
            additionalTypes.isEmpty;
        _categories = (categories == null || categories.isEmpty)
            ? List<String>.from(_defaultCategories)
            : categories;
        _makingTypesGold = (makingGold == null || makingGold.isEmpty)
            ? List<String>.from(_defaultMakingTypesGold)
            : makingGold;
        _makingTypesSilver = (makingSilver == null || makingSilver.isEmpty)
            ? List<String>.from(_defaultMakingTypesSilver)
            : makingSilver;
        _lessCategories = (lessCategories == null || lessCategories.isEmpty)
            ? List<String>.from(_defaultLessCategories)
            : lessCategories;
        _additionalTypes = (additionalTypes == null || additionalTypes.isEmpty)
            ? List<String>.from(_defaultAdditionalTypes)
            : additionalTypes;
        _selectedCategory = null;
        _selectedMakingType = null;
        _applyInitialDataIfAny();
        _loading = false;
      });
      _startLessCategoriesSync();
      _startAdditionalTypesSync();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _usingFallbackMasterData = true;
        _selectedCategory = null;
        _selectedMakingType = null;
        _applyInitialDataIfAny();
        _loading = false;
      });
      _startLessCategoriesSync();
      _startAdditionalTypesSync();
    }
  }

  void _startLessCategoriesSync() {
    _lessCategoriesSub?.cancel();
    _lessCategoriesSub = _lessCategoriesRef
        .orderBy('nameLower')
        .snapshots()
        .listen((snapshot) async {
          final names = snapshot.docs
              .map((doc) => doc.data()['name']?.toString().trim())
              .whereType<String>()
              .where((name) => name.isNotEmpty)
              .toList();

          if (names.isEmpty) {
            await _seedLessCategoriesIfEmpty();
            return;
          }

          _sortList(names);
          if (!mounted) {
            return;
          }
          setState(() {
            _lessCategories = names;
          });
          await _saveLessCategoriesToPrefs();
        });
    _seedLessCategoriesIfEmpty();
  }

  Future<void> _seedLessCategoriesIfEmpty() async {
    if (_seedingLessCategories) {
      return;
    }
    _seedingLessCategories = true;
    try {
      final existing = await _lessCategoriesRef.limit(1).get();
      if (existing.docs.isNotEmpty) {
        return;
      }
      final seedSource = _lessCategories.isNotEmpty
          ? _lessCategories
          : _defaultLessCategories;
      final unique = <String>{};
      final batch = _firestore.batch();
      for (final name in seedSource) {
        final normalized = _normalizeLessCategory(name);
        if (normalized.isEmpty) {
          continue;
        }
        final docId = _lessCategoryDocId(normalized);
        if (!unique.add(docId)) {
          continue;
        }
        batch.set(_lessCategoriesRef.doc(docId), {
          'name': normalized,
          'nameLower': docId,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      if (unique.isNotEmpty) {
        await batch.commit();
      }
    } catch (_) {
      // ignore seeding failures
    } finally {
      _seedingLessCategories = false;
    }
  }

  Future<void> _saveLessCategoriesToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('less_categories', _lessCategories);
  }

  void _startAdditionalTypesSync() {
    _additionalTypesSub?.cancel();
    _additionalTypesSub = _additionalTypesRef
        .orderBy('nameLower')
        .snapshots()
        .listen((snapshot) async {
          final names = snapshot.docs
              .map((doc) => doc.data()['name']?.toString().trim())
              .whereType<String>()
              .where((name) => name.isNotEmpty)
              .toList();

          if (names.isEmpty) {
            await _seedAdditionalTypesIfEmpty();
            return;
          }

          _sortList(names);
          if (!mounted) {
            return;
          }
          setState(() {
            _additionalTypes = names;
          });
          await _saveAdditionalTypesToPrefs();
        });
    _seedAdditionalTypesIfEmpty();
  }

  Future<void> _seedAdditionalTypesIfEmpty() async {
    if (_seedingAdditionalTypes) {
      return;
    }
    _seedingAdditionalTypes = true;
    try {
      final existing = await _additionalTypesRef.limit(1).get();
      if (existing.docs.isNotEmpty) {
        return;
      }
      final seedSource = _additionalTypes.isNotEmpty
          ? _additionalTypes
          : _defaultAdditionalTypes;
      final unique = <String>{};
      final batch = _firestore.batch();
      for (final name in seedSource) {
        final normalized = _normalizeAdditionalType(name);
        if (normalized.isEmpty) {
          continue;
        }
        final docId = _additionalTypeDocId(normalized);
        if (!unique.add(docId)) {
          continue;
        }
        batch.set(_additionalTypesRef.doc(docId), {
          'name': normalized,
          'nameLower': docId,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      if (unique.isNotEmpty) {
        await batch.commit();
      }
    } catch (_) {
      // ignore seeding failures
    } finally {
      _seedingAdditionalTypes = false;
    }
  }

  Future<void> _saveAdditionalTypesToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('additional_types', _additionalTypes);
  }

  void _applyInitialDataIfAny() {
    final data = widget.initialData;
    if (data == null) {
      return;
    }
    final category = data['category']?.toString().trim();
    if (category != null &&
        category.isNotEmpty &&
        _categories.contains(category)) {
      _selectedCategory = category;
    }
    final making = data['makingType']?.toString().trim();
    final makingList = _makingTypesForCategory(_selectedCategory);
    if (making != null && making.isNotEmpty && makingList.contains(making)) {
      _selectedMakingType = making;
    }
    final returnPurity = data['returnPurity']?.toString().trim();
    if (returnPurity != null &&
        returnPurity.isNotEmpty &&
        _returnPurityOptions.contains(returnPurity)) {
      _selectedReturnPurity = returnPurity;
    }
    _itemNameController.text = data['itemName']?.toString() ?? '';
    _makingChargeController.text = data['makingCharge']?.toString() ?? '';
    _grossWeightController.text = data['grossWeight']?.toString() ?? '';

    for (final entry in _lessEntries) {
      entry.dispose();
    }
    _lessEntries.clear();
    final lessRaw = data['lessCategories'];
    if (lessRaw is List && lessRaw.isNotEmpty) {
      for (final item in lessRaw) {
        if (item is! Map) {
          continue;
        }
        final entry = _ManualLessEntryDraft();
        entry.category = item['category']?.toString();
        entry.valueController.text = item['value']?.toString() ?? '';
        entry.valueController.addListener(_recalculateWeights);
        _lessEntries.add(entry);
      }
    }
    if (_lessEntries.isEmpty) {
      final entry = _ManualLessEntryDraft();
      entry.valueController.addListener(_recalculateWeights);
      _lessEntries.add(entry);
    }

    for (final entry in _additionalEntries) {
      entry.dispose();
    }
    _additionalEntries.clear();
    final additionalRaw = data['additionalTypes'];
    if (additionalRaw is List && additionalRaw.isNotEmpty) {
      for (final item in additionalRaw) {
        if (item is! Map) {
          continue;
        }
        final entry = _ManualAdditionalEntryDraft();
        entry.type = item['type']?.toString();
        entry.valueController.text = item['value']?.toString() ?? '';
        _additionalEntries.add(entry);
      }
    }
    if (_additionalEntries.isEmpty) {
      _additionalEntries.add(_ManualAdditionalEntryDraft());
    }

    _recalculateWeights();
  }

  List<String> _makingTypesForCategory(String? category) {
    if (category == 'Silver') {
      return _makingTypesSilver;
    }
    return _makingTypesGold;
  }

  double _parseNum(String value) {
    final cleaned = value.replaceAll(',', '').trim();
    return double.tryParse(cleaned) ?? 0.0;
  }

  String? _requiredFieldError(String value) {
    if (!_submitted) {
      return null;
    }
    return value.trim().isEmpty ? 'Required' : null;
  }

  String? _positiveNumberError(String value, {bool allowZero = false}) {
    if (!_submitted) {
      return null;
    }
    if (value.trim().isEmpty) {
      return 'Required';
    }
    final parsed = _parseNum(value);
    if (allowZero ? parsed < 0 : parsed <= 0) {
      return allowZero ? 'Must be >= 0' : 'Must be > 0';
    }
    return null;
  }

  void _recalculateWeights() {
    final gross = _parseNum(_grossWeightController.text);
    double less = 0;
    for (final entry in _lessEntries) {
      less += _parseNum(entry.valueController.text);
    }
    final net = gross - less;
    _lessWeightController.text = less.toStringAsFixed(3);
    _netWeightController.text = (net < 0 ? 0 : net).toStringAsFixed(3);
    if (mounted) {
      setState(() {});
    }
  }

  void _addLessEntry() {
    setState(() {
      final entry = _ManualLessEntryDraft();
      entry.valueController.addListener(_recalculateWeights);
      _lessEntries.add(entry);
    });
  }

  void _removeLessEntry(int index) {
    if (_lessEntries.length <= 1) {
      return;
    }
    setState(() {
      final entry = _lessEntries.removeAt(index);
      entry.dispose();
    });
    _recalculateWeights();
  }

  void _addAdditionalEntry() {
    setState(() {
      _additionalEntries.add(_ManualAdditionalEntryDraft());
    });
  }

  void _removeAdditionalEntry(int index) {
    if (_additionalEntries.length <= 1) {
      return;
    }
    setState(() {
      final entry = _additionalEntries.removeAt(index);
      entry.dispose();
    });
  }

  Future<void> _addToScan() async {
    setState(() {
      _submitted = true;
    });
    final missingFields = <String>[];
    if ((_selectedCategory ?? '').trim().isEmpty) {
      missingFields.add('Category');
    }
    if (_itemNameController.text.trim().isEmpty) {
      missingFields.add('Item Name');
    }
    if ((_selectedMakingType ?? '').trim().isEmpty) {
      missingFields.add('Making Type');
    }
    if (_selectedCategory == 'Silver' &&
        (_selectedReturnPurity ?? '').trim().isEmpty) {
      missingFields.add('Return Purity');
    }
    if (_makingChargeController.text.trim().isEmpty) {
      missingFields.add('Making Charge');
    }
    if (_grossWeightController.text.trim().isEmpty) {
      missingFields.add('Gross Weight');
    }
    if (_parseNum(_grossWeightController.text) <= 0) {
      missingFields.add('Gross Weight > 0');
    }
    if (_parseNum(_netWeightController.text) <= 0) {
      missingFields.add('Net Weight > 0');
    }
    if (_parseNum(_makingChargeController.text) < 0) {
      missingFields.add('Making Charge >= 0');
    }
    for (final entry in _lessEntries) {
      final hasCategory = (entry.category ?? '').trim().isNotEmpty;
      final hasValue = entry.valueController.text.trim().isNotEmpty;
      if (hasCategory && !hasValue) {
        missingFields.add('Less category value');
        break;
      }
    }
    for (final entry in _additionalEntries) {
      final hasType = (entry.type ?? '').trim().isNotEmpty;
      final hasValue = entry.valueController.text.trim().isNotEmpty;
      if (hasType && !hasValue) {
        missingFields.add('Additional type value');
        break;
      }
    }
    if (missingFields.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please fill: ${missingFields.join(', ')}')),
      );
      return;
    }

    final lessEntries = _lessEntries
        .where(
          (entry) =>
              (entry.category ?? '').trim().isNotEmpty ||
              entry.valueController.text.trim().isNotEmpty,
        )
        .map(
          (entry) => <String, dynamic>{
            'category': (entry.category ?? '').trim(),
            'value': entry.valueController.text.trim(),
          },
        )
        .toList();

    final additionalEntries = _additionalEntries
        .where(
          (entry) =>
              (entry.type ?? '').trim().isNotEmpty ||
              entry.valueController.text.trim().isNotEmpty,
        )
        .map(
          (entry) => <String, dynamic>{
            'type': (entry.type ?? '').trim(),
            'value': entry.valueController.text.trim(),
          },
        )
        .toList();

    final payload = <String, dynamic>{
      'id':
          widget.initialData?['id']?.toString() ??
          'manual_${DateTime.now().microsecondsSinceEpoch}',
      'entrySource': 'manual',
      'category': _selectedCategory,
      'itemName': _itemNameController.text.trim(),
      'itemNameLower': _itemNameController.text.trim().toLowerCase(),
      'makingType': _selectedMakingType,
      'makingCharge': _makingChargeController.text.trim(),
      'grossWeight': _grossWeightController.text.trim(),
      'lessWeight': _lessWeightController.text.trim(),
      'netWeight': _netWeightController.text.trim(),
      'returnPurity': (_selectedReturnPurity ?? '').trim(),
      'lessCategories': lessEntries,
      'additionalTypes': additionalEntries,
    };

    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(payload);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialData != null;
    return AlertDialog(
      title: Text(isEditing ? 'Edit Manual Item' : 'Manual Item Creator'),
      content: ManualItemDialogBody(
        loading: _loading,
        usingFallbackMasterData: _usingFallbackMasterData,
        child: SharedItemFormLayout(
          primarySection: Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: _selectedCategory,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Category')
                    .copyWith(
                      errorText:
                          _submitted && (_selectedCategory ?? '').trim().isEmpty
                          ? 'Required'
                          : null,
                    ),
                items: _categories
                    .map(
                      (value) => DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _selectedCategory = value;
                    _selectedMakingType = null;
                    if (_selectedCategory != 'Silver') {
                      _selectedReturnPurity = null;
                    }
                  });
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _itemNameController,
                decoration: const InputDecoration(labelText: 'Item Name')
                    .copyWith(
                      errorText: _requiredFieldError(_itemNameController.text),
                    ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _selectedMakingType,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Making Type')
                    .copyWith(
                      errorText:
                          _submitted &&
                              (_selectedMakingType ?? '').trim().isEmpty
                          ? 'Required'
                          : null,
                    ),
                items: _makingTypesForCategory(_selectedCategory)
                    .map(
                      (value) => DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _selectedMakingType = value;
                  });
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _makingChargeController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: _selectedMakingType == 'Percentage'
                      ? 'Making Charge %'
                      : 'Making Charge',
                  suffixText: _selectedMakingType == 'Percentage' ? '%' : null,
                  errorText: _positiveNumberError(
                    _makingChargeController.text,
                    allowZero: true,
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _grossWeightController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Gross Weight')
                    .copyWith(
                      errorText: _positiveNumberError(
                        _grossWeightController.text,
                      ),
                    ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _lessWeightController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Less Weight',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _netWeightController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Net Weight',
                      ),
                    ),
                  ),
                ],
              ),
              if (_selectedCategory == 'Silver') ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _selectedReturnPurity,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(
                        labelText: 'Return Purity (R%)',
                      ).copyWith(
                        errorText:
                            _submitted &&
                                (_selectedReturnPurity ?? '').trim().isEmpty
                            ? 'Required for Silver items'
                            : null,
                      ),
                  items: _returnPurityOptions
                      .map(
                        (value) => DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedReturnPurity = value;
                    });
                  },
                ),
              ],
              const SizedBox(height: 8),
              SharedFormSectionHeader(
                title: 'Less Categories',
                onAdd: _addLessEntry,
              ),
              ..._lessEntries.asMap().entries.map((entry) {
                final index = entry.key;
                final lessEntry = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SharedFormEntryCard(
                    title: 'Less Entry ${index + 1}',
                    onDelete: () => _removeLessEntry(index),
                    child: Column(
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: lessEntry.category,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Category',
                          ),
                          items: _lessCategories
                              .map(
                                (value) => DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              lessEntry.category = value;
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: lessEntry.valueController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(labelText: 'Value')
                              .copyWith(
                                errorText:
                                    _submitted &&
                                        (lessEntry.category ?? '')
                                            .trim()
                                            .isNotEmpty &&
                                        lessEntry.valueController.text
                                            .trim()
                                            .isEmpty
                                    ? 'Required'
                                    : null,
                              ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
              SharedFormSectionHeader(
                title: 'Additional Types',
                onAdd: _addAdditionalEntry,
              ),
              ..._additionalEntries.asMap().entries.map((entry) {
                final index = entry.key;
                final additionalEntry = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SharedFormEntryCard(
                    title: 'Additional Entry ${index + 1}',
                    onDelete: () => _removeAdditionalEntry(index),
                    child: Column(
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: additionalEntry.type,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Type'),
                          items: _additionalTypes
                              .map(
                                (value) => DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              additionalEntry.type = value;
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: additionalEntry.valueController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(labelText: 'Value')
                              .copyWith(
                                errorText:
                                    _submitted &&
                                        (additionalEntry.type ?? '')
                                            .trim()
                                            .isNotEmpty &&
                                        additionalEntry.valueController.text
                                            .trim()
                                            .isEmpty
                                    ? 'Required'
                                    : null,
                              ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
          makingSection: const SizedBox.shrink(),
          lessSection: const SizedBox.shrink(),
          weightSection: const SizedBox.shrink(),
          additionalSection: const SizedBox.shrink(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _addToScan,
          icon: const Icon(Icons.add_task),
          label: Text(isEditing ? 'Save Changes' : 'Add To Scan'),
        ),
      ],
    );
  }
}

class _ManualLessEntryDraft {
  String? category;
  final TextEditingController valueController = TextEditingController();

  void dispose() {
    valueController.dispose();
  }
}

class _ManualAdditionalEntryDraft {
  String? type;
  final TextEditingController valueController = TextEditingController();

  void dispose() {
    valueController.dispose();
  }
}

enum _ScanSortMode { newestFirst, oldestFirst, nameAsc }

class _ScanItemColors {
  const _ScanItemColors({
    required this.cardColor,
    required this.headingBgColor,
    required this.headingTextColor,
    required this.amountTextColor,
  });

  final Color cardColor;
  final Color headingBgColor;
  final Color headingTextColor;
  final Color amountTextColor;
}

class _LiveQrScannerPageState extends State<_LiveQrScannerPage> {
  late final MobileScannerController _scannerController;
  bool _found = false;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(
      formats: [BarcodeFormat.qrCode],
    );
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Widget _buildTorchAction() {
    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: _scannerController,
      builder: (context, state, _) {
        final torchState = state.torchState;
        final canToggle =
            state.isInitialized &&
            state.isRunning &&
            torchState != TorchState.unavailable;

        final IconData icon = switch (torchState) {
          TorchState.on => Icons.flash_on,
          TorchState.off => Icons.flash_off,
          TorchState.auto => Icons.flash_auto,
          TorchState.unavailable => Icons.no_flash,
        };

        return IconButton(
          tooltip: canToggle ? 'Toggle flash' : 'Flash unavailable',
          onPressed: canToggle
              ? () async {
                  await _scannerController.toggleTorch();
                }
              : null,
          icon: Icon(icon),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR'),
        actions: [_buildTorchAction()],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final scanSize = size.shortestSide * 0.7;
          final left = (size.width - scanSize) / 2;
          final top = (size.height - scanSize) / 2;
          final scanWindow = Rect.fromLTWH(left, top, scanSize, scanSize);

          return Stack(
            children: [
              MobileScanner(
                controller: _scannerController,
                scanWindow: scanWindow,
                onDetect: (capture) {
                  if (_found) {
                    return;
                  }
                  if (capture.barcodes.isEmpty) {
                    return;
                  }
                  final value = capture.barcodes.first.rawValue ?? '';
                  if (value.isEmpty) {
                    return;
                  }
                  _found = true;
                  Navigator.of(context).pop(value);
                },
              ),
              _ScannerOverlay(scanWindow: scanWindow),
            ],
          );
        },
      ),
    );
  }
}

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay({required this.scanWindow});

  final Rect scanWindow;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _OverlayPainter(scanWindow: scanWindow),
            ),
          ),
          Positioned.fromRect(
            rect: scanWindow,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter({required this.scanWindow});

  final Rect scanWindow;

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Paint()..color = Colors.black.withValues(alpha: 0.5);
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectXY(scanWindow, 12, 12))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, overlay);
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter oldDelegate) {
    return oldDelegate.scanWindow != scanWindow;
  }
}

class _ScanResultCard extends StatefulWidget {
  const _ScanResultCard({
    required this.data,
    required this.headingBgColor,
    required this.headingTextColor,
    required this.amountTextColor,
    required this.gstEnabled,
    required this.canEditGst,
    required this.canEditMaking,
    required this.onMakingChanged,
    required this.onGstChanged,
  });

  final Map<String, dynamic> data;
  final Color headingBgColor;
  final Color headingTextColor;
  final Color amountTextColor;
  final bool gstEnabled;
  final bool canEditGst;
  final bool canEditMaking;
  final ValueChanged<String> onMakingChanged;
  final ValueChanged<bool> onGstChanged;

  @override
  State<_ScanResultCard> createState() => _ScanResultCardState();
}

class _ScanResultCardState extends State<_ScanResultCard> {
  bool _expanded = false;
  Future<PriceBreakdown>? _breakdownFuture;
  late final TextEditingController _makingController;
  late final FocusNode _makingFocus;

  static final TextInputFormatter _percentageFormatter =
      TextInputFormatter.withFunction((oldValue, newValue) {
        if (RegExp(r'^\d*\.?\d*$').hasMatch(newValue.text)) {
          return newValue;
        }
        return oldValue;
      });

  String _headlineName(Map<String, dynamic> data) {
    final rawName = data['itemName']?.toString().trim() ?? '';
    if (rawName.isEmpty) {
      return 'Item';
    }
    final isManual = data['entrySource']?.toString() == 'manual';
    if (!isManual) {
      return rawName;
    }
    final withoutManual = rawName
        .replaceAll(RegExp(r'\bmanual\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return withoutManual.isEmpty ? 'Item' : withoutManual;
  }

  String _editableMakingCharge(Map<String, dynamic> data) {
    final makingType = data['makingType']?.toString() ?? '';
    final raw = data['makingCharge']?.toString() ?? '';
    if (makingType == 'Percentage') {
      return raw.replaceAll('%', '').trim();
    }
    return raw;
  }

  String _displayMakingCharge(String makingType, String makingCharge) {
    if (makingType != 'Percentage') {
      return makingCharge;
    }
    final cleaned = makingCharge.replaceAll('%', '').trim();
    if (cleaned.isEmpty || cleaned == '-') {
      return '-';
    }
    return '$cleaned%';
  }

  @override
  void initState() {
    super.initState();
    _makingController = TextEditingController(
      text: _editableMakingCharge(widget.data),
    );
    _makingFocus = FocusNode();
    _breakdownFuture = PriceCalculator.calculateBreakdown(
      widget.data,
      gstEnabledOverride: widget.gstEnabled,
    );
  }

  @override
  void didUpdateWidget(covariant _ScanResultCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      final nextText = _editableMakingCharge(widget.data);
      if (nextText != _makingController.text && !_makingFocus.hasFocus) {
        _makingController.text = nextText;
      }
      _breakdownFuture = PriceCalculator.calculateBreakdown(
        widget.data,
        gstEnabledOverride: widget.gstEnabled,
      );
    } else if (oldWidget.gstEnabled != widget.gstEnabled) {
      _breakdownFuture = PriceCalculator.calculateBreakdown(
        widget.data,
        gstEnabledOverride: widget.gstEnabled,
      );
    }
  }

  @override
  void dispose() {
    _makingController.dispose();
    _makingFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () {
            setState(() {
              _expanded = !_expanded;
            });
          },
          child: FutureBuilder<double>(
            future: _breakdownFuture?.then((b) => b.total),
            builder: (context, snapshot) {
              final amountText = snapshot.hasData
                  ? PriceCalculator.formatIndianAmount(snapshot.data!)
                  : '...';
              final itemName = _headlineName(widget.data);
              final rawWeight =
                  widget.data['netWeight']?.toString().trim() ?? '';
              final weightText = rawWeight.isEmpty ? '-' : rawWeight;
              return Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: widget.headingBgColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            itemName,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: widget.headingTextColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Wt: $weightText',
                                textAlign: TextAlign.left,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                amountText,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: widget.amountTextColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black87,
                  ),
                ],
              );
            },
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 8),
          _buildDetailSection(),
          const SizedBox(height: 8),
          FutureBuilder<PriceBreakdown>(
            future: _breakdownFuture,
            builder: (context, snapshot) {
              final breakdown = snapshot.data;
              if (breakdown == null) {
                return const Text('Total: ...');
              }
              final makingType = widget.data['makingType']?.toString() ?? '';
              final showGst = makingType != 'FixRate';
              final gstText = PriceCalculator.formatIndianAmount(breakdown.gst);
              final totalText = PriceCalculator.formatIndianAmount(
                breakdown.total,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showGst) ...[
                    Row(
                      children: [
                        const Expanded(child: Text('GST: 3%')),
                        Switch(
                          value: widget.gstEnabled,
                          onChanged: widget.canEditGst
                              ? widget.onGstChanged
                              : null,
                        ),
                      ],
                    ),
                    if (widget.gstEnabled)
                      Text('GST Amount: $gstText')
                    else
                      Text(
                        'GST Amount: ${PriceCalculator.formatIndianAmount(0)}',
                      ),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    'Total: $totalText',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildDetailSection() {
    final category = widget.data['category']?.toString() ?? '-';
    final gross = widget.data['grossWeight']?.toString() ?? '-';
    final less = widget.data['lessWeight']?.toString() ?? '-';
    final net = widget.data['netWeight']?.toString() ?? '-';
    final makingType = widget.data['makingType']?.toString() ?? '-';
    final makingCharge = widget.data['makingCharge']?.toString() ?? '-';
    final displayMakingCharge = _displayMakingCharge(makingType, makingCharge);
    final lessCategories = (widget.data['lessCategories'] as List? ?? const []);
    final additionalTypes =
        (widget.data['additionalTypes'] as List? ?? const []);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Category: $category'),
        const SizedBox(height: 6),
        if (lessCategories.isNotEmpty) ...[
          const Text('Less Categories'),
          const SizedBox(height: 4),
          ...lessCategories.map((item) {
            if (item is Map) {
              final cat = item['category']?.toString() ?? '-';
              final val = item['value']?.toString() ?? '-';
              return Text('$cat: $val');
            }
            return const SizedBox.shrink();
          }),
          const SizedBox(height: 6),
        ],
        Row(
          children: [
            Expanded(child: Text('Gross: $gross')),
            Expanded(child: Text('Less: $less')),
            Expanded(child: Text('Net: $net')),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: Text('Making: $makingType')),
            Expanded(
              child: Text(
                'Charge: $displayMakingCharge',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        if (widget.canEditMaking) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _makingController,
            focusNode: _makingFocus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: makingType == 'Percentage'
                ? <TextInputFormatter>[_percentageFormatter]
                : null,
            decoration: InputDecoration(
              labelText: makingType == 'Percentage'
                  ? 'Making Charge %'
                  : 'Making Charge',
              suffixText: makingType == 'Percentage' ? '%' : null,
            ),
            onChanged: (value) {
              widget.onMakingChanged(
                makingType == 'Percentage'
                    ? value.replaceAll('%', '').trim()
                    : value,
              );
            },
          ),
        ],
        if (additionalTypes.isNotEmpty) ...[
          const SizedBox(height: 6),
          const Text('Additional Types'),
          const SizedBox(height: 4),
          ...additionalTypes.map((item) {
            if (item is Map) {
              final type = item['type']?.toString() ?? '-';
              final val = item['value']?.toString() ?? '-';
              return Text('$type: $val');
            }
            return const SizedBox.shrink();
          }),
        ],
      ],
    );
  }
}
