part of '../total_page.dart';

extension _TotalPageDraftExtension on _TotalPageState {
  Future<void> _saveDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encodedEntries = _paymentEntries.map((entry) {
        return jsonEncode({
          'date': entry.date.toIso8601String(),
          'mode': entry.mode,
          'amount': entry.amountController.text,
        });
      }).toList();
      await prefs.setString(
        StorageKeys.totalDraftDiscount,
        _discountController.text,
      );
      await prefs.setBool(
        StorageKeys.totalDraftGPercentEnabled,
        _gPercentEnabled,
      );
      await prefs.setDouble(
        StorageKeys.totalDraftGPercentAmount,
        _gPercentLockedAmount,
      );
      await prefs.setStringList(
        StorageKeys.totalDraftPaymentEntries,
        encodedEntries,
      );
    } catch (error, stackTrace) {
      debugPrint('TotalPage: failed to save draft: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(StorageKeys.totalDraftDiscount);
      await prefs.remove(StorageKeys.totalDraftPaymentEntries);
      await prefs.remove(StorageKeys.totalDraftGPercentEnabled);
      await prefs.remove(StorageKeys.totalDraftGPercentAmount);
      await prefs.remove(StorageKeys.totalDraftInvoiceNo);
      _activeInvoiceNo = null;
    } catch (error, stackTrace) {
      debugPrint('TotalPage: failed to clear draft: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _loadDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final discount = prefs.getString(StorageKeys.totalDraftDiscount) ?? '';
      final gPercentEnabled =
          prefs.getBool(StorageKeys.totalDraftGPercentEnabled) ?? false;
      final gPercentAmount =
          prefs.getDouble(StorageKeys.totalDraftGPercentAmount) ?? 0.0;
      final entryRaw =
          prefs.getStringList(StorageKeys.totalDraftPaymentEntries) ?? [];
      final loadedEntries = <_PaymentEntryDraft>[];
      for (final raw in entryRaw) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is! Map<String, dynamic>) {
            continue;
          }
          final parsedDate = DateTime.tryParse(
            decoded['date']?.toString() ?? '',
          );
          final mode = decoded['mode']?.toString().trim() ?? '';
          final amount = decoded['amount']?.toString() ?? '';
          if (parsedDate == null || mode.isEmpty) {
            continue;
          }
          loadedEntries.add(
            _PaymentEntryDraft(date: parsedDate, mode: mode, amount: amount),
          );
        } catch (error, stackTrace) {
          debugPrint('TotalPage: invalid draft payment row: $error');
          debugPrintStack(stackTrace: stackTrace);
        }
      }
      if (!mounted) {
        for (final entry in loadedEntries) {
          entry.dispose();
        }
        return;
      }
      // ignore: invalid_use_of_protected_member
      setState(() {
        _discountController.text = discount;
        _gPercentEnabled = gPercentEnabled;
        _gPercentLockedAmount = gPercentAmount;
        for (final entry in _paymentEntries) {
          entry.dispose();
        }
        _paymentEntries
          ..clear()
          ..addAll(
            loadedEntries.isEmpty
                ? <_PaymentEntryDraft>[
                    _PaymentEntryDraft(date: DateTime.now(), mode: 'Cash'),
                  ]
                : loadedEntries,
          );
      });
    } catch (error, stackTrace) {
      debugPrint('TotalPage: failed to load draft: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
