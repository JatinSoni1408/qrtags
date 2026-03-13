part of '../total_page.dart';

extension _TotalPageStorageExtension on _TotalPageState {
  Future<_TotalsData> _loadTotals() async {
    final prefs = await SharedPreferences.getInstance();
    final selectedRaw =
        prefs.getStringList(StorageKeys.selectedItems) ?? <String>[];
    final selectedGst =
        prefs.getStringList(StorageKeys.selectedItemsGst) ?? <String>[];

    double parseNum(String v) {
      final cleaned = v.replaceAll(',', '').replaceAll('%', '').trim();
      return double.tryParse(cleaned) ?? 0.0;
    }

    List<Map<String, dynamic>> collectAdditionals(Map<String, dynamic> data) {
      final additionalTypes = (data['additionalTypes'] as List? ?? const []);
      final values = <Map<String, dynamic>>[];
      for (final item in additionalTypes) {
        if (item is Map) {
          final type = item['type']?.toString().trim() ?? '';
          final value = parseNum(item['value']?.toString() ?? '0');
          if (value != 0 && type.isNotEmpty) {
            values.add({'type': type, 'value': value});
          }
        }
      }
      return values;
    }

    double getBhav(String? category) {
      if (category == 'Gold22kt') {
        return prefs.getDouble(StorageKeys.rateGold22) ?? 0.0;
      }
      if (category == 'Gold18kt') {
        return prefs.getDouble(StorageKeys.rateGold18) ?? 0.0;
      }
      if (category == 'Silver') {
        return prefs.getDouble(StorageKeys.rateSilver) ?? 0.0;
      }
      return 0.0;
    }

    double getReturnBhavValue(String? option) {
      if (option == 'Gold24kt') {
        return prefs.getDouble(StorageKeys.rateGold24) ?? 0.0;
      }
      if (option == 'Gold22kt') {
        return (prefs.getDouble(StorageKeys.rateGold22) ?? 0.0) - 300;
      }
      if (option == 'Gold18kt') {
        return (prefs.getDouble(StorageKeys.rateGold18) ?? 0.0) - 300;
      }
      if (option == 'Silver') {
        return prefs.getDouble(StorageKeys.rateSilver) ?? 0.0;
      }
      return 0.0;
    }

    String formatReturnBhavText(String? option, double value) {
      return PriceCalculator.formatIndianAmount(value);
    }

    String selectedIdentity(String raw) {
      final parsed = _tryParseJson(raw);
      final id = parsed?['id']?.toString().trim() ?? '';
      if (id.isNotEmpty) {
        return 'id:$id';
      }
      return 'raw:${raw.trim()}';
    }

    final seen = <String>{};
    final uniqueSelected = <String>[];
    final uniqueGst = <String>[];
    for (int i = 0; i < selectedRaw.length; i++) {
      final raw = selectedRaw[i];
      final identity = selectedIdentity(raw);
      if (seen.add(identity)) {
        uniqueSelected.add(raw);
        uniqueGst.add(i < selectedGst.length ? selectedGst[i] : '1');
      }
    }

    final selectedItems = <_SelectedItemView>[];
    double selectedTotal = 0.0;
    double selectedGstTotal = 0.0;

    for (int i = 0; i < uniqueSelected.length; i++) {
      final raw = uniqueSelected[i];
      final parsed = _tryParseJson(raw);
      if (parsed == null) {
        continue;
      }
      final huidMandatory = _hasHuid(parsed);
      final gstEnabled = huidMandatory
          ? true
          : (i < uniqueGst.length ? uniqueGst[i] == '1' : true);
      final breakdown = await PriceCalculator.calculateBreakdown(
        parsed,
        gstEnabledOverride: gstEnabled,
      );
      final isManualEntry = parsed['entrySource']?.toString() == 'manual';
      final rawItemName = parsed['itemName']?.toString() ?? '';
      final itemName = rawItemName.isNotEmpty ? rawItemName : 'Item';
      final category = parsed['category']?.toString();
      final makingType = parsed['makingType']?.toString() ?? '';
      final grossWeightValue = parseNum(
        parsed['grossWeight']?.toString() ?? '0',
      );
      final lessWeightValue = parseNum(parsed['lessWeight']?.toString() ?? '0');
      final netWeightValue = parseNum(parsed['netWeight']?.toString() ?? '0');
      final netWeight = netWeightValue.toStringAsFixed(3);
      final makingCharge = parseNum(parsed['makingCharge']?.toString() ?? '0');
      final bhav = getBhav(category);
      final bhavText = PriceCalculator.formatIndianAmount(bhav);
      final additionalValues = collectAdditionals(parsed);
      final additionalTotal = additionalValues.fold<double>(
        0.0,
        (sum, v) => sum + (v['value'] as double),
      );
      final additionalBreakup = <String, double>{};
      for (final item in additionalValues) {
        final type = item['type'] as String;
        final value = item['value'] as double;
        additionalBreakup[type] = (additionalBreakup[type] ?? 0.0) + value;
      }
      final additionalText = additionalTotal > 0
          ? ' + ${PriceCalculator.formatIndianAmount(additionalTotal)}'
          : '';
      final gstText = gstEnabled && makingType != 'FixRate' ? ' + 3%' : '';
      String formula;
      String formulaExtras = '';
      if (makingType == 'Percentage') {
        formula =
            '$bhavText + ${makingCharge.toStringAsFixed(0)}% * '
            '$netWeight$gstText$additionalText';
      } else if (makingType == 'PerGram') {
        formula =
            '$bhavText + ${makingCharge.toStringAsFixed(2)} * '
            '$netWeight$gstText$additionalText';
      } else if (makingType == 'FixRate') {
        formula = '';
      } else if (makingType == 'TotalMaking') {
        formula =
            '$bhavText * $netWeight + '
            '${makingCharge.toStringAsFixed(2)}$gstText$additionalText';
      } else {
        formula = '$netWeight ${makingCharge.toStringAsFixed(2)}$gstText';
        formulaExtras = netWeight;
      }
      selectedTotal += breakdown.total;
      selectedGstTotal += breakdown.gst;
      selectedItems.add(
        _SelectedItemView(
          title: itemName,
          amount: breakdown.total,
          formula: formula,
          formulaExtras: formulaExtras,
          weightToken: netWeight,
          category: category ?? '',
          weightValue: netWeightValue,
          grossWeight: grossWeightValue,
          lessWeight: lessWeightValue,
          rate: bhav,
          makingType: makingType,
          makingCharge: makingCharge,
          baseAmount: breakdown.base,
          gstAmount: breakdown.gst,
          additionalAmount: breakdown.additional,
          additionalBreakup: additionalBreakup,
          gstDisplay: gstEnabled ? '3%' : '-',
          isManualEntry: isManualEntry,
          returnPurity: parsed['returnPurity']?.toString() ?? '',
        ),
      );
    }

    final oldRaw = prefs.getStringList(StorageKeys.oldItems) ?? <String>[];
    final oldItems = <_OldItemView>[];
    double oldTotal = 0.0;
    for (final raw in oldRaw) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final name = decoded['itemName']?.toString() ?? 'Item';
          final amount = (decoded['amount'] as num?)?.toDouble() ?? 0.0;
          final grossWeightValue = parseNum(
            decoded['grossWeight']?.toString() ?? '0',
          );
          double lessWeightValue = parseNum(
            decoded['lessWeight']?.toString() ?? '0',
          );
          if (lessWeightValue == 0.0) {
            final lessEntries = decoded['lessEntries'];
            if (lessEntries is List) {
              double sum = 0.0;
              for (final entry in lessEntries) {
                if (entry is Map) {
                  sum += parseNum(entry['value']?.toString() ?? '0');
                }
              }
              lessWeightValue = sum;
            }
          }
          final netWeightValue = parseNum(
            decoded['netWeight']?.toString() ?? '0',
          );
          final netWeightText = netWeightValue.toStringAsFixed(3);
          final returnBhav = decoded['returnBhav']?.toString();
          final oldCategory = returnBhav ?? '';
          final returnBhavValue = getReturnBhavValue(returnBhav);
          final returnBhavText = formatReturnBhavText(
            returnBhav,
            returnBhavValue,
          );
          final tanchRaw = decoded['tanch']?.toString() ?? '';
          final hasTanch = tanchRaw.trim().isNotEmpty;
          final tanchValue = parseNum(tanchRaw);
          String formulaPrefix;
          String formulaRate = returnBhavText;
          switch (returnBhav) {
            case 'Silver':
              formulaPrefix =
                  '($netWeightText * ${tanchValue.toStringAsFixed(2)}) * ';
              break;
            case 'Gold22kt':
              formulaPrefix = '$netWeightText * ';
              break;
            case 'Gold18kt':
              formulaPrefix =
                  '($netWeightText * ${tanchValue.toStringAsFixed(2)}) * ';
              break;
            case 'Gold24kt':
              formulaPrefix =
                  '($netWeightText * ${tanchValue.toStringAsFixed(2)}) * ';
              break;
            default:
              if (hasTanch) {
                formulaPrefix =
                    '($netWeightText * ${tanchValue.toStringAsFixed(2)}) * ';
              } else {
                formulaPrefix = '$netWeightText * ';
              }
          }
          oldTotal += amount;
          oldItems.add(
            _OldItemView(
              title: name,
              amount: amount,
              grossWeight: grossWeightValue,
              lessWeight: lessWeightValue,
              netWeight: netWeightValue,
              category: oldCategory,
              formulaPrefix: formulaPrefix,
              formulaRate: formulaRate,
            ),
          );
        }
      } catch (error, stackTrace) {
        debugPrint('TotalPage: failed to parse old item entry: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }

    return _TotalsData(
      selectedItems: selectedItems,
      oldItems: oldItems,
      selectedRawSnapshot: uniqueSelected,
      selectedTotal: selectedTotal,
      selectedGstTotal: selectedGstTotal,
      oldTotal: oldTotal,
      selectedCount: selectedItems.length,
      discountEnabled: prefs.getBool(StorageKeys.discountEnabled) ?? false,
    );
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

  Map<String, dynamic>? _tryParseJson(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (error, stackTrace) {
      debugPrint('TotalPage: failed to parse JSON payload: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    return null;
  }
}
