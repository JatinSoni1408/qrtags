import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/price_calculator.dart';
import '../utils/selection_notifier.dart';

class SelectedPage extends StatefulWidget {
  const SelectedPage({super.key, required this.selectedVersion});

  final ValueListenable<int> selectedVersion;

  @override
  State<SelectedPage> createState() => _SelectedPageState();
}

class _SelectedPageState extends State<SelectedPage> {
  List<String> _items = [];
  double _total = 0.0;
  double _gstTotal = 0.0;
  late final VoidCallback _versionListener;
  List<bool> _gstEnabledByItem = [];

  @override
  void initState() {
    super.initState();
    _versionListener = () {
      _loadItems();
    };
    widget.selectedVersion.addListener(_versionListener);
    _loadItems();
  }

  @override
  void didUpdateWidget(covariant SelectedPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedVersion != widget.selectedVersion) {
      oldWidget.selectedVersion.removeListener(_versionListener);
      widget.selectedVersion.addListener(_versionListener);
    }
  }

  @override
  void dispose() {
    widget.selectedVersion.removeListener(_versionListener);
    super.dispose();
  }

  Future<void> _loadItems() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }
    setState(() {
      _items = prefs.getStringList('selected_items') ?? <String>[];
    });
    final savedGst = prefs.getStringList('selected_items_gst') ?? <String>[];
    _gstEnabledByItem = List<bool>.generate(
      _items.length,
      (i) => i < savedGst.length ? savedGst[i] == '1' : true,
    );
    await _recalculateTotal();
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

  Future<void> _recalculateTotal() async {
    double sum = 0.0;
    double gstSum = 0.0;
    for (int index = 0; index < _items.length; index++) {
      final raw = _items[index];
      final parsed = _tryParseJson(raw);
      if (parsed != null) {
        final huidMandatory = _hasHuid(parsed);
        final gstEnabled = huidMandatory
            ? true
            : (index >= 0 && index < _gstEnabledByItem.length
                  ? _gstEnabledByItem[index]
                  : true);
        final breakdown = await PriceCalculator.calculateBreakdown(
          parsed,
          gstEnabledOverride: gstEnabled,
        );
        sum += breakdown.total;
        gstSum += breakdown.gst;
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _total = sum;
      _gstTotal = gstSum;
    });
  }

  Future<void> _removeItem(int index) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _items.removeAt(index);
      if (index < _gstEnabledByItem.length) {
        _gstEnabledByItem.removeAt(index);
      }
    });
    await prefs.setStringList('selected_items', _items);
    await prefs.setStringList(
      'selected_items_gst',
      _gstEnabledByItem.map((e) => e ? '1' : '0').toList(),
    );
    SelectionNotifier.notify();
    await _recalculateTotal();
  }

  Future<void> _clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _items.clear();
      _gstEnabledByItem.clear();
      _total = 0.0;
      _gstTotal = 0.0;
    });
    await prefs.remove('selected_items');
    await prefs.remove('selected_items_gst');
    SelectionNotifier.notify();
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

  Widget _buildCollapsedHeader(Map<String, dynamic> data, bool gstEnabled) {
    return FutureBuilder<PriceBreakdown>(
      future: PriceCalculator.calculateBreakdown(
        data,
        gstEnabledOverride: gstEnabled,
      ),
      builder: (context, snapshot) {
        final amountText = snapshot.hasData
            ? PriceCalculator.formatIndianAmount(snapshot.data!.total)
            : '...';
        double parse(dynamic v) {
          if (v == null) return 0.0;
          if (v is num) return v.toDouble();
          final cleaned = v.toString().replaceAll(',', '').trim();
          return double.tryParse(cleaned) ?? 0.0;
        }

        final itemName = data['itemName']?.toString() ?? '-';
        final netWeight = parse(data['netWeight']).toStringAsFixed(3);
        return RichText(
          text: TextSpan(
            style: const TextStyle(fontWeight: FontWeight.bold),
            children: [
              TextSpan(text: '$itemName  $netWeight  '),
              TextSpan(text: amountText),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, size: 80),
            const SizedBox(height: 16),
            const Text('Selected Items'),
            const SizedBox(height: 32),
            const Text('No items selected yet'),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              const Text(
                'Selected Items',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              TextButton(
                onPressed: _items.isEmpty ? null : _clearAll,
                child: const Text('Clear All'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: _items.length,
            onReorder: (oldIndex, newIndex) async {
              if (newIndex > oldIndex) {
                newIndex -= 1;
              }
              setState(() {
                final item = _items.removeAt(oldIndex);
                _items.insert(newIndex, item);
                if (oldIndex < _gstEnabledByItem.length) {
                  final gstFlag = _gstEnabledByItem.removeAt(oldIndex);
                  _gstEnabledByItem.insert(newIndex, gstFlag);
                }
              });
              final prefs = await SharedPreferences.getInstance();
              await prefs.setStringList('selected_items', _items);
              await prefs.setStringList(
                'selected_items_gst',
                _gstEnabledByItem.map((e) => e ? '1' : '0').toList(),
              );
              SelectionNotifier.notify();
              await _recalculateTotal();
            },
            itemBuilder: (context, index) {
              final raw = _items[index];
              final parsed = _tryParseJson(raw);
              final huidMandatory = parsed != null ? _hasHuid(parsed) : false;
              final gstEnabled = huidMandatory
                  ? true
                  : (_gstEnabledByItem.length > index
                        ? _gstEnabledByItem[index]
                        : true);
              final makingType = parsed?['makingType']?.toString() ?? '';
              final showGst = makingType != 'FixRate';
              return Card(
                key: ValueKey('selected_$index'),
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: parsed != null
                      ? ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: _buildCollapsedHeader(parsed, gstEnabled),
                          children: [
                            ...parsed.entries.map(
                              (e) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Text('${e.key}: ${e.value}'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (gstEnabled && showGst)
                              FutureBuilder<PriceBreakdown>(
                                future: PriceCalculator.calculateBreakdown(
                                  parsed,
                                  gstEnabledOverride: gstEnabled,
                                ),
                                builder: (context, snapshot) {
                                  final gstAmt = snapshot.hasData
                                      ? PriceCalculator.formatIndianAmount(
                                          snapshot.data!.gst,
                                        )
                                      : '...';
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      const Text('GST %: 3%'),
                                      Text('GST Amount: $gstAmt'),
                                    ],
                                  );
                                },
                              ),
                            if (!huidMandatory && showGst)
                              SwitchListTile(
                                title: const Text('GST Enabled'),
                                value: gstEnabled,
                                onChanged: (value) async {
                                  setState(() {
                                    if (_gstEnabledByItem.length <= index) {
                                      _gstEnabledByItem = List<bool>.generate(
                                        _items.length,
                                        (_) => true,
                                      );
                                    }
                                    _gstEnabledByItem[index] = value;
                                  });
                                  final prefs =
                                      await SharedPreferences.getInstance();
                                  await prefs.setStringList(
                                    'selected_items_gst',
                                    _gstEnabledByItem
                                        .map((e) => e ? '1' : '0')
                                        .toList(),
                                  );
                                  SelectionNotifier.notify();
                                  await _recalculateTotal();
                                },
                              ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () => _removeItem(index),
                                icon: const Icon(Icons.delete, size: 18),
                                label: const Text('Remove'),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(raw),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () => _removeItem(index),
                                icon: const Icon(Icons.delete, size: 18),
                                label: const Text('Remove'),
                              ),
                            ),
                          ],
                        ),
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
              Text(
                'S:${_items.length}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 12),
              Text(
                'GST ${PriceCalculator.formatIndianAmount(_gstTotal)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              const Text(
                'Total',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Text(
                PriceCalculator.formatIndianAmount(_total),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
