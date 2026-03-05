part of '../total_page.dart';

enum _TakeawayMode { maxItems, maxWeight }

class _TakeawaySuggestion {
  const _TakeawaySuggestion({
    required this.mode,
    required this.budget,
    required this.selectedItems,
    required this.totalAmount,
    required this.totalWeight,
    required this.budgetUnit,
  });

  final _TakeawayMode mode;
  final double budget;
  final List<_SelectedItemView> selectedItems;
  final double totalAmount;
  final double totalWeight;
  final int budgetUnit;

  double get leftover => math.max(0, budget - totalAmount);
}

class _KnapsackState {
  const _KnapsackState({
    required this.count,
    required this.weightMilliGrams,
    required this.spentAmount,
    required this.itemIndex,
    required this.previous,
  });

  final int count;
  final int weightMilliGrams;
  final double spentAmount;
  final int? itemIndex;
  final _KnapsackState? previous;
}

class _TotalsData {
  _TotalsData({
    required this.selectedItems,
    required this.oldItems,
    required this.selectedRawSnapshot,
    required this.selectedTotal,
    required this.selectedGstTotal,
    required this.oldTotal,
    required this.selectedCount,
    required this.discountEnabled,
  });

  final List<_SelectedItemView> selectedItems;
  final List<_OldItemView> oldItems;
  final List<String> selectedRawSnapshot;
  final double selectedTotal;
  final double selectedGstTotal;
  final double oldTotal;
  final int selectedCount;
  final bool discountEnabled;
}

class _PaymentEntryDraft {
  _PaymentEntryDraft({
    required this.date,
    required this.mode,
    String amount = '',
  }) : amountController = TextEditingController(text: amount);

  DateTime date;
  String mode;
  final TextEditingController amountController;

  void dispose() {
    amountController.dispose();
  }
}

class _PaymentEntryPdfRow {
  const _PaymentEntryPdfRow({
    required this.date,
    required this.mode,
    required this.amount,
  });

  final DateTime date;
  final String mode;
  final double amount;
}

class _TotalItemPalette {
  const _TotalItemPalette({
    required this.cardBg,
    required this.headingBg,
    required this.headingText,
    required this.amountText,
    required this.contentText,
    required this.borderColor,
  });

  final Color cardBg;
  final Color headingBg;
  final Color headingText;
  final Color amountText;
  final Color contentText;
  final Color borderColor;
}

class _SelectedItemView {
  _SelectedItemView({
    required this.title,
    required this.amount,
    required this.formula,
    required this.formulaExtras,
    required this.weightToken,
    required this.category,
    required this.weightValue,
    required this.grossWeight,
    required this.lessWeight,
    required this.rate,
    required this.makingType,
    required this.makingCharge,
    required this.baseAmount,
    required this.gstAmount,
    required this.additionalAmount,
    required this.additionalBreakup,
    required this.gstDisplay,
    required this.isManualEntry,
  });

  final String title;
  final double amount;
  final String formula;
  final String formulaExtras;
  final String? weightToken;
  final String category;
  final double weightValue;
  final double grossWeight;
  final double lessWeight;
  final double rate;
  final String makingType;
  final double makingCharge;
  final double baseAmount;
  final double gstAmount;
  final double additionalAmount;
  final Map<String, double> additionalBreakup;
  final String gstDisplay;
  final bool isManualEntry;

  String get formulaDisplay {
    final text = formula.trim();
    return text.isEmpty ? '-' : text;
  }

  String get categoryDisplay {
    final text = category.trim();
    return text.isEmpty ? '-' : text;
  }
}

class _OldItemView {
  _OldItemView({
    required this.title,
    required this.amount,
    required this.grossWeight,
    required this.lessWeight,
    required this.netWeight,
    required this.category,
    required this.formulaPrefix,
    required this.formulaRate,
  });

  final String title;
  final double amount;
  final double grossWeight;
  final double lessWeight;
  final double netWeight;
  final String category;
  final String formulaPrefix;
  final String formulaRate;

  String get categoryDisplay {
    final text = category.trim();
    return text.isEmpty ? '-' : text;
  }

  String get formulaText => '$formulaPrefix$formulaRate';
}

class _QrCenterBadgeStyle {
  const _QrCenterBadgeStyle({
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
  });

  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
}
