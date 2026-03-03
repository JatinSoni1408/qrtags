import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/selection/selected_items_state.dart';
import '../utils/price_calculator.dart';
import '../utils/sales_notifier.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  Future<void> _resetSales() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Reset Sales'),
          content: const Text(
            'This will clear all sales items and mark inventory items as unsold.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('sales_items');
    await prefs.remove('sales_items_gst');
    await prefs.remove('sales_item_ids');
    SalesNotifier.notify();
    if (!mounted) {
      return;
    }
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Sales reset completed')));
  }

  Future<_SalesData> _loadSales() async {
    final prefs = await SharedPreferences.getInstance();
    final salesRaw = prefs.getStringList('sales_items') ?? <String>[];
    final salesGstFlags = prefs.getStringList('sales_items_gst') ?? <String>[];
    final entries = SelectedItemsState.dedupeWithGstFlags(
      items: salesRaw,
      gstFlags: salesGstFlags,
    );

    double parseNum(String v) {
      final cleaned = v.replaceAll(',', '').replaceAll('%', '').trim();
      return double.tryParse(cleaned) ?? 0.0;
    }

    final items = <_SaleItemView>[];
    double total = 0.0;
    for (final entry in entries) {
      final raw = entry.raw;
      final parsed = _tryParseJson(raw);
      if (parsed == null) {
        continue;
      }
      final gstEnabled = _hasHuid(parsed) ? true : entry.gstEnabled;
      final breakdown = await PriceCalculator.calculateBreakdown(
        parsed,
        gstEnabledOverride: gstEnabled,
      );
      final rawItemName = parsed['itemName']?.toString() ?? '';
      final itemName = rawItemName.isNotEmpty ? rawItemName : 'Item';
      final category = parsed['category']?.toString() ?? '-';
      final netWeightValue = parseNum(parsed['netWeight']?.toString() ?? '0');
      total += breakdown.total;
      items.add(
        _SaleItemView(
          title: itemName,
          category: category,
          netWeight: netWeightValue,
          amount: breakdown.total,
        ),
      );
    }

    return _SalesData(items: items, total: total);
  }

  bool _hasHuid(Map<String, dynamic> data) {
    final v = data['huid']?.toString().trim() ?? '';
    return v.isNotEmpty;
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

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: SalesNotifier.version,
      builder: (context, value, child) {
        return FutureBuilder<_SalesData>(
          future: _loadSales(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final data = snapshot.data!;
            if (data.items.isEmpty) {
              return const Center(child: Text('No sales yet'));
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Sales (${data.items.length})',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _resetSales,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reset'),
                      ),
                    ],
                  ),
                  Text(
                    'Total: ${PriceCalculator.formatIndianAmount(data.total)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ...data.items.map(
                    (item) => Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        title: Text(item.title),
                        subtitle: Text(
                          'Category: ${item.category} | Net: ${item.netWeight.toStringAsFixed(3)}',
                        ),
                        trailing: Text(
                          PriceCalculator.formatIndianAmount(item.amount),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _SalesData {
  _SalesData({required this.items, required this.total});

  final List<_SaleItemView> items;
  final double total;
}

class _SaleItemView {
  _SaleItemView({
    required this.title,
    required this.category,
    required this.netWeight,
    required this.amount,
  });

  final String title;
  final String category;
  final double netWeight;
  final double amount;
}
