import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class PriceCalculator {
  static const double _gstRate = 0.03;

  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) {
      final cleaned =
          v.replaceAll('%', '').replaceAll(',', '').trim();
      return double.tryParse(cleaned) ?? 0.0;
    }
    return double.tryParse(v.toString()) ?? 0.0;
  }

  static List<Map<String, dynamic>> _listOfMap(
    Map<String, dynamic> data,
    String key,
  ) {
    final raw = data[key];
    if (raw is List) {
      return raw.whereType<Map<String, dynamic>>().toList();
    }
    return const [];
  }

  static Future<double> _categoryRate(String? category) async {
    final prefs = await SharedPreferences.getInstance();
    switch (category) {
      case 'Gold22kt':
        return prefs.getDouble('rate_gold22') ?? 0;
      case 'Gold18kt':
        return prefs.getDouble('rate_gold18') ?? 0;
      case 'Silver':
        return prefs.getDouble('rate_silver') ?? 0;
      default:
        return 0;
    }
  }

  static Future<double> calculateTotal(Map<String, dynamic> data) async {
    final breakdown = await calculateBreakdown(data);
    return breakdown.total;
  }

  static Future<PriceBreakdown> calculateBreakdown(
    Map<String, dynamic> data, {
    bool? gstEnabledOverride,
  }) async {
    final category = data['category']?.toString();
    final makingType = data['makingType']?.toString();
    final makingCharge = _toDouble(data['makingCharge']);
    final netWeight = _toDouble(data['netWeight']);

    final additionalList = _listOfMap(data, 'additionalTypes');
    final additionalTotal = additionalList.fold<double>(
      0.0,
      (sum, e) => sum + _toDouble(e['value']),
    );

    final rate = await _categoryRate(category);
    final prefs = await SharedPreferences.getInstance();
    final isFixRate = makingType == 'FixRate';
    final gstEnabled = isFixRate
        ? false
        : (gstEnabledOverride ?? (prefs.getBool('gst_enabled') ?? true));

    double base = 0.0;
    switch (makingType) {
      case 'FixRate':
        base = makingCharge;
        break;
      case 'PerGram':
        base = (rate + makingCharge) * netWeight;
        break;
      case 'Percentage':
        base = (rate + (rate * (makingCharge / 100))) * netWeight;
        break;
      case 'TotalMaking':
        base = (rate * netWeight) + makingCharge;
        break;
      default:
        base = (rate * netWeight) + makingCharge;
        break;
    }

    final gst = gstEnabled ? base * _gstRate : 0.0;
    final total = max(0.0, base + gst + additionalTotal);
    return PriceBreakdown(
      base: base,
      gst: gst,
      additional: additionalTotal,
      total: total,
    );
  }

  static String buildCollapsedTitle(
    Map<String, dynamic> data,
    String amountText,
  ) {
    final itemName = data['itemName']?.toString() ?? '-';
    final netWeight = _toDouble(data['netWeight']);
    return '$itemName  ${netWeight.toStringAsFixed(3)}  $amountText';
  }

  static String formatIndianAmount(double value) {
    final isNegative = value < 0;
    final absValue = value.abs();
    final raw = absValue.toStringAsFixed(2);
    final parts = raw.split('.');
    final intPart = parts[0];
    final decPart = parts.length > 1 ? parts[1] : '00';
    if (intPart.length <= 3) {
      return '${isNegative ? '-' : ''}$intPart.$decPart';
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
    return '${isNegative ? '-' : ''}${buffer.toString()},$last3.$decPart';
  }
}

class PriceBreakdown {
  PriceBreakdown({
    required this.base,
    required this.gst,
    required this.additional,
    double? total,
  }) : total = total ?? max(0, base + gst + additional);

  final double base;
  final double gst;
  final double additional;
  final double total;
}
