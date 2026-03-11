import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/selection_notifier.dart';
import '../widgets/settings_button.dart';

class OldPage extends StatefulWidget {
  const OldPage({super.key});

  @override
  State<OldPage> createState() => _OldPageState();
}

class _OldPageState extends State<OldPage> {
  static const String _oldItemsKey = 'old_items';

  final TextEditingController _grossWeightController = TextEditingController();
  final TextEditingController _itemNameController = TextEditingController();
  final TextEditingController _lessWeightController = TextEditingController();
  final TextEditingController _autoNetWeightController =
      TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  String? _selectedTanch;
  String? _selectedReturnBhav;
  double _computedAmount = 0.0;
  int? _editingIndex;
  final List<_OldItem> _items = [];
  late final VoidCallback _ratesListener;

  final List<String> _tanchOptions = [
    '.91',
    '.90',
    '.89',
    '.88',
    '.87',
    '.86',
    '.85',
    '.84',
    '.83',
    '.82',
    '.81',
    '.80',
    '.79',
    '.78',
    '.77',
    '.76',
    '.75',
    '.74',
    '.73',
    '.72',
    '.71',
    '.70',
    '.69',
    '.68',
    '.67',
    '.66',
    '.65',
    '.64',
    '.63',
    '.62',
    '.61',
    '.60',
    '.59',
    '.58',
    '.57',
    '.56',
    '.55',
    '.54',
    '.53',
    '.52',
    '.51',
    '.50',
    '.49',
    '.48',
    '.47',
    '.46',
    '.45',
    '.44',
    '.43',
    '.42',
    '.41',
    '.40',
    '.39',
    '.38',
    '.37',
    '.36',
    '.35',
    '.34',
    '.33',
    '.32',
    '.31',
    '.30',
  ];
  final List<String> _returnBhavOptions = [
    'Gold24kt',
    'Gold22kt',
    'Gold18kt',
    'Silver',
  ];

  double _rateGold24 = 0;
  double _rateGold22 = 0;
  double _rateGold18 = 0;
  double _rateSilver = 0;

  Future<void> _loadRates() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }
    setState(() {
      _rateGold24 = prefs.getDouble('rate_gold24') ?? 0;
      _rateGold22 = prefs.getDouble('rate_gold22') ?? 0;
      _rateGold18 = prefs.getDouble('rate_gold18') ?? 0;
      _rateSilver = prefs.getDouble('rate_silver') ?? 0;
    });
    _updateAmount();
    _refreshItemsWithLatestRates();
  }

  @override
  void initState() {
    super.initState();
    _grossWeightController.addListener(_updateNetWeight);
    _lessWeightController.text = '0.000';
    _ratesListener = () async {
      await _loadRates();
      _refreshItemsWithLatestRates();
    };
    SettingsButton.ratesVersion.addListener(_ratesListener);
    _loadRates();
    _loadItems();
  }

  @override
  void dispose() {
    SettingsButton.ratesVersion.removeListener(_ratesListener);
    _grossWeightController.dispose();
    _itemNameController.dispose();
    _lessWeightController.dispose();
    _autoNetWeightController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _updateNetWeight() {
    final gross = double.tryParse(_grossWeightController.text.trim()) ?? 0;
    final lessTotal = double.tryParse(_lessWeightController.text.trim()) ?? 0;
    final net = gross - lessTotal;
    _autoNetWeightController.text = net.toStringAsFixed(3);
    _updateAmount();
  }

  bool _usesTanch(String? returnBhav) =>
      returnBhav != null &&
      returnBhav != 'Gold22kt' &&
      returnBhav != 'Gold18kt';

  double _calculateOldAmount({
    required double netWeight,
    required String? returnBhav,
    required String? tanch,
  }) {
    final returnValue = returnBhav == null ? 0.0 : _returnBhavValue(returnBhav);
    if (!_usesTanch(returnBhav)) {
      return netWeight * returnValue;
    }
    final tanchValue = double.tryParse(tanch ?? '') ?? 0.0;
    return netWeight * returnValue * tanchValue;
  }

  void _updateAmount() {
    final net = double.tryParse(_autoNetWeightController.text.trim()) ?? 0;
    final returnBhav = _selectedReturnBhav;
    final tanch = _usesTanch(returnBhav) ? _selectedTanch : null;
    _computedAmount = _calculateOldAmount(
      netWeight: net,
      returnBhav: returnBhav,
      tanch: tanch,
    );
    _amountController.text = _formatIndianAmount(_computedAmount);
  }

  void _refreshItemsWithLatestRates() {
    if (_items.isEmpty) {
      return;
    }
    setState(() {
      for (int i = 0; i < _items.length; i++) {
        final item = _items[i];
        final normalizedTanch = _usesTanch(item.returnBhav) ? item.tanch : null;
        final amount = _calculateOldAmount(
          netWeight: item.netWeight,
          returnBhav: item.returnBhav,
          tanch: normalizedTanch,
        );
        _items[i] = _OldItem(
          itemName: item.itemName,
          grossWeight: item.grossWeight,
          lessWeight: item.lessWeight,
          netWeight: item.netWeight,
          tanch: normalizedTanch,
          returnBhav: item.returnBhav,
          amount: amount,
        );
      }
    });
    _saveItems();
  }

  void _resetForm() {
    setState(() {
      _itemNameController.text = '';
      _grossWeightController.text = '';
      _lessWeightController.text = '0.000';
      _autoNetWeightController.text = '';
      _amountController.text = '';
      _selectedTanch = null;
      _selectedReturnBhav = null;
      _computedAmount = 0.0;
      _editingIndex = null;
    });
  }

  void _addOrUpdateItem({BuildContext? dialogContext}) {
    final itemName = _itemNameController.text.trim();
    final grossText = _grossWeightController.text.trim();
    final lessText = _lessWeightController.text.trim();
    final gross = double.tryParse(grossText);
    final less = double.tryParse(lessText);
    if (_selectedReturnBhav == null || _selectedReturnBhav!.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Return Bhav is required')));
      return;
    }
    if (_selectedReturnBhav == 'Gold18kt') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gold18kt Return Bhav is disabled for now'),
        ),
      );
      return;
    }
    if (gross == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Gross Weight is required')));
      return;
    }
    if (less == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Less Weight is required (0.000 allowed)'),
        ),
      );
      return;
    }
    if (less >= gross) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Less Weight must be less than Gross Weight'),
        ),
      );
      return;
    }
    final returnBhav = _selectedReturnBhav;
    if (_usesTanch(returnBhav) &&
        (_selectedTanch == null || _selectedTanch!.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tanch is required for this Return Bhav')),
      );
      return;
    }
    final tanch = _usesTanch(returnBhav) ? _selectedTanch : null;
    _lessWeightController.text = less.toStringAsFixed(3);
    _lessWeightController.selection = TextSelection.collapsed(
      offset: _lessWeightController.text.length,
    );
    _updateNetWeight();
    final net = double.tryParse(_autoNetWeightController.text.trim()) ?? 0;
    final amount = _calculateOldAmount(
      netWeight: net,
      returnBhav: returnBhav,
      tanch: tanch,
    );
    _computedAmount = amount;
    _amountController.text = _formatIndianAmount(_computedAmount);

    final item = _OldItem(
      itemName: itemName,
      grossWeight: gross,
      lessWeight: less,
      netWeight: net,
      tanch: tanch,
      returnBhav: returnBhav,
      amount: amount,
    );

    setState(() {
      if (_editingIndex != null && _editingIndex! < _items.length) {
        _items[_editingIndex!] = item;
      } else {
        _items.add(item);
      }
    });

    _saveItems();
    _resetForm();
    dialogContext != null ? Navigator.of(dialogContext).pop() : null;
  }

  void _startEditItem(int index) {
    final item = _items[index];
    setState(() {
      _editingIndex = index;
      _itemNameController.text = item.itemName;
      _grossWeightController.text = item.grossWeight.toString();
      _lessWeightController.text = item.lessWeight.toStringAsFixed(3);
      _selectedTanch = _usesTanch(item.returnBhav) ? item.tanch : null;
      _selectedReturnBhav = item.returnBhav;
      _computedAmount = item.amount;
      _amountController.text = _formatIndianAmount(_computedAmount);
    });
    _updateNetWeight();
    _showEntryDialog(isEditing: true);
  }

  void _deleteItem(int index) {
    setState(() {
      _items.removeAt(index);
    });
    _saveItems();
  }

  Future<void> _clearAllItems() async {
    if (_items.isEmpty) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _items.clear();
    });
    _resetForm();
    await _saveItems();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('All old items cleared')));
  }

  Future<void> _saveItems() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = _items.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_oldItemsKey, encoded);
    SelectionNotifier.notify();
  }

  Future<void> _loadItems() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_oldItemsKey) ?? <String>[];
    final loaded = <_OldItem>[];
    for (final item in raw) {
      try {
        final decoded = jsonDecode(item);
        if (decoded is Map<String, dynamic>) {
          loaded.add(_OldItem.fromJson(decoded));
        }
      } catch (_) {
        // ignore
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _items
        ..clear()
        ..addAll(loaded);
    });
  }

  Future<void> _showEntryDialog({bool isEditing = false}) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final tanchEnabled = _usesTanch(_selectedReturnBhav);
            return AlertDialog(
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              contentPadding:
                  const EdgeInsets.fromLTRB(16, 10, 16, 16),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Old Item Entry',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isEditing
                        ? 'Update existing item'
                        : 'Add old purchase details',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 540),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: TextField(
                              controller: _itemNameController,
                              decoration: const InputDecoration(
                                labelText: 'Item Name',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedReturnBhav,
                              isExpanded: true,
                              items: _returnBhavOptions.map((b) {
                                final disabled = b == 'Gold18kt';
                                return DropdownMenuItem<String>(
                                  value: b,
                                  enabled: !disabled,
                                  child: Text(
                                    '$b ${_formatIndianForReturnBhav(b)}${disabled ? ' (Disabled)' : ''}',
                                    overflow: TextOverflow.ellipsis,
                                    style: disabled
                                        ? TextStyle(
                                            color:
                                                Theme.of(context).disabledColor,
                                          )
                                        : null,
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedReturnBhav = value;
                                  if (!_usesTanch(value)) {
                                    _selectedTanch = null;
                                  }
                                });
                                _updateAmount();
                                setDialogState(() {});
                              },
                              decoration: const InputDecoration(
                                labelText: 'Return Bhav',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _sectionHeader(
                        context,
                        'Weights',
                        subtitle: 'Net weight is auto-calculated',
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _grossWeightController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Gross Weight',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _lessWeightController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              onTap: () {
                                _lessWeightController.selection = TextSelection(
                                  baseOffset: 0,
                                  extentOffset:
                                      _lessWeightController.text.length,
                                );
                              },
                              onChanged: (_) {
                                _updateNetWeight();
                                setDialogState(() {});
                              },
                              onEditingComplete: () {
                                final value = double.tryParse(
                                          _lessWeightController.text.trim(),
                                        ) ??
                                        0.0;
                                _lessWeightController.text =
                                    value.toStringAsFixed(3);
                                _lessWeightController.selection =
                                    TextSelection.collapsed(
                                  offset: _lessWeightController.text.length,
                                );
                                _updateNetWeight();
                                setDialogState(() {});
                              },
                              decoration: const InputDecoration(
                                labelText: 'Less Weight',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _autoNetWeightController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              readOnly: true,
                              decoration: const InputDecoration(
                                labelText: 'Net Weight',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedTanch,
                              isExpanded: true,
                              items: _tanchOptions
                                  .map(
                                    (p) => DropdownMenuItem<String>(
                                      value: p,
                                      child: Text(p),
                                    ),
                                  )
                                  .toList(),
                              onChanged: tanchEnabled
                                  ? (value) {
                                      setState(() {
                                        _selectedTanch = value;
                                      });
                                      _updateAmount();
                                      setDialogState(() {});
                                    }
                                  : null,
                              decoration: const InputDecoration(
                                labelText: 'Tanch',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _amountController,
                              readOnly: true,
                              decoration: const InputDecoration(
                                labelText: 'Amount',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        tanchEnabled
                            ? 'Tanch is required for selected Return Bhav.'
                            : 'Tanch is auto-disabled for Gold22kt/Gold18kt.',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Close'),
                ),
                ElevatedButton(
                  onPressed: () => _addOrUpdateItem(
                    dialogContext: dialogContext,
                  ),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  double _returnBhavValue(String option) {
    switch (option) {
      case 'Gold24kt':
        return _rateGold24;
      case 'Gold22kt':
        return _rateGold22 - 300;
      case 'Gold18kt':
        return _rateGold18 - 300;
      case 'Silver':
        return _rateSilver;
      default:
        return 0;
    }
  }

  String _formatIndianNoDecimals(double value) {
    final isNegative = value < 0;
    final absValue = value.abs().round();
    final intPart = absValue.toString();
    if (intPart.length <= 3) {
      return '${isNegative ? '-' : ''}$intPart';
    }
    final last3 = intPart.substring(intPart.length - 3);
    final rest = intPart.substring(0, intPart.length - 3);
    final buffer = StringBuffer();
    for (int i = 0; i < rest.length; i++) {
      buffer.write(rest[i]);
      final posFromEnd = rest.length - i - 1;
      if (posFromEnd % 2 == 0 && posFromEnd != 0) {
        buffer.write(',');
      }
    }
    return '${isNegative ? '-' : ''}${buffer.toString()},$last3';
  }

  String _formatIndianForReturnBhav(String option) {
    final value = _returnBhavValue(option);
    if (option == 'Silver') {
      return _formatIndianAmount(value, decimals: 2);
    }
    return _formatIndianNoDecimals(value);
  }

  String _formatIndianAmount(double value, {int decimals = 2}) {
    final isNegative = value < 0;
    final absValue = value.abs();
    final fixed = absValue.toStringAsFixed(decimals);
    final parts = fixed.split('.');
    final intPart = parts[0];
    if (intPart.length <= 3) {
      return '${isNegative ? '-' : ''}$fixed';
    }
    final last3 = intPart.substring(intPart.length - 3);
    final rest = intPart.substring(0, intPart.length - 3);
    final buffer = StringBuffer();
    for (int i = 0; i < rest.length; i++) {
      buffer.write(rest[i]);
      final posFromEnd = rest.length - i - 1;
      if (posFromEnd % 2 == 0 && posFromEnd != 0) {
        buffer.write(',');
      }
    }
    final grouped = '${buffer.toString()},$last3';
    return decimals > 0
        ? '${isNegative ? '-' : ''}$grouped.${parts[1]}'
        : '${isNegative ? '-' : ''}$grouped';
  }

  double _lessTotalForItem(_OldItem item) => item.lessWeight;

  String _formatWeight(double value) {
    return value.toStringAsFixed(3);
  }

  String _oldItemFormulaRate(_OldItem item) {
    final option = item.returnBhav;
    if (option == null || option.isEmpty) {
      return '0';
    }
    final value = _returnBhavValue(option);
    if (option == 'Silver') {
      return _formatIndianAmount(value);
    }
    return value.toStringAsFixed(0);
  }

  String _oldItemFormulaPrefix(_OldItem item) {
    final netWeightText = _formatWeight(item.netWeight);
    final tanchRaw = item.tanch ?? '';
    final hasTanch = tanchRaw.trim().isNotEmpty;
    final tanchValue = double.tryParse(tanchRaw) ?? 0.0;
    switch (item.returnBhav) {
      case 'Silver':
        return '($netWeightText * ${tanchValue.toStringAsFixed(2)}) * ';
      case 'Gold22kt':
      case 'Gold18kt':
        return '$netWeightText * ';
      case 'Gold24kt':
        return '($netWeightText * ${tanchValue.toStringAsFixed(2)}) * ';
      default:
        if (hasTanch) {
          return '($netWeightText * ${tanchValue.toStringAsFixed(2)}) * ';
        }
        return '$netWeightText * ';
    }
  }

  Widget _sectionHeader(
    BuildContext context,
    String title, {
    String? subtitle,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 4,
          height: subtitle == null ? 18 : 28,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              if (subtitle != null && subtitle.isNotEmpty)
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metricChip(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
    );
  }

  Widget _summaryTile(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final totalGross = _items.fold<double>(
      0.0,
      (sum, item) => sum + item.grossWeight,
    );
    final totalNet = _items.fold<double>(
      0.0,
      (sum, item) => sum + item.netWeight,
    );
    final totalLess = _items.fold<double>(
      0.0,
      (sum, item) => sum + _lessTotalForItem(item),
    );
    final totalAmount = _items.fold<double>(
      0.0,
      (sum, item) => sum + item.amount,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () {
                    _resetForm();
                    _showEntryDialog(isEditing: false);
                  },
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Add Old Item Details'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: _items.isEmpty ? null : _clearAllItems,
                  icon: const Icon(Icons.clear_all),
                  label: const Text('Clear All'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_items.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _sectionHeader(
                              context,
                              'Items (${_items.length})',
                              subtitle:
                                  'Total ${_formatIndianAmount(totalAmount)}',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ..._items.asMap().entries.map(
                        (entry) => Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: scheme.outlineVariant),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        entry.value.itemName.isEmpty
                                            ? 'Item'
                                            : entry.value.itemName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _formatIndianAmount(entry.value.amount),
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFB91C1C),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _metricChip(
                                      context,
                                      'Gross',
                                      _formatWeight(entry.value.grossWeight),
                                    ),
                                    _metricChip(
                                      context,
                                      'Less',
                                      _formatWeight(entry.value.lessWeight),
                                    ),
                                    _metricChip(
                                      context,
                                      'Net',
                                      _formatWeight(entry.value.netWeight),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Return Bhav: ${entry.value.returnBhav ?? '-'} (${_oldItemFormulaRate(entry.value)})',
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: RichText(
                                    text: TextSpan(
                                      style: DefaultTextStyle.of(context).style,
                                      children: [
                                        TextSpan(
                                          text: _oldItemFormulaPrefix(
                                            entry.value,
                                          ),
                                        ),
                                        TextSpan(
                                          text: _oldItemFormulaRate(
                                            entry.value,
                                          ),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton.icon(
                                      onPressed: () =>
                                          _startEditItem(entry.key),
                                      icon: const Icon(Icons.edit, size: 18),
                                      label: const Text('Edit'),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton.icon(
                                      onPressed: () => _deleteItem(entry.key),
                                      icon: const Icon(Icons.delete, size: 18),
                                      label: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 80),
                    ],
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Center(
                      child: Text(
                        'No old items yet.\nTap "Add Old Item Details" to begin.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
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
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _summaryTile(
                      context,
                      'Gross',
                      _formatWeight(totalGross),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _summaryTile(
                      context,
                      'Less',
                      _formatWeight(totalLess),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _summaryTile(
                      context,
                      'Net',
                      _formatWeight(totalNet),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Amount ${_formatIndianAmount(totalAmount)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: scheme.onPrimaryContainer,
                    fontSize: 15,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OldItem {
  _OldItem({
    required this.itemName,
    required this.grossWeight,
    required this.lessWeight,
    required this.netWeight,
    required this.tanch,
    required this.returnBhav,
    required this.amount,
  });

  final String itemName;
  final double grossWeight;
  final double lessWeight;
  final double netWeight;
  final String? tanch;
  final String? returnBhav;
  final double amount;

  Map<String, dynamic> toJson() => {
    'itemName': itemName,
    'grossWeight': grossWeight,
    'lessWeight': lessWeight,
    'netWeight': netWeight,
    'tanch': tanch,
    'returnBhav': returnBhav,
    'amount': amount,
  };

  factory _OldItem.fromJson(Map<String, dynamic> json) {
    double lessWeight = (json['lessWeight'] as num?)?.toDouble() ?? 0.0;
    if (lessWeight == 0.0) {
      final lessRaw = json['lessEntries'];
      if (lessRaw is List) {
        double sum = 0.0;
        for (final entry in lessRaw) {
          if (entry is Map) {
            final value = entry['value']?.toString() ?? '';
            sum += double.tryParse(value) ?? 0.0;
          }
        }
        lessWeight = sum;
      }
    }
    return _OldItem(
      itemName: json['itemName']?.toString() ?? '',
      grossWeight: (json['grossWeight'] as num?)?.toDouble() ?? 0.0,
      lessWeight: lessWeight,
      netWeight: (json['netWeight'] as num?)?.toDouble() ?? 0.0,
      tanch: json['tanch']?.toString(),
      returnBhav: json['returnBhav']?.toString(),
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
