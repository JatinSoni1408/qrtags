class PaymentEntryCalculator {
  const PaymentEntryCalculator._();

  static double sumByModes(
    Iterable<PaymentEntryValue> entries,
    Set<String> modes,
  ) {
    final normalizedModes = modes
        .map((mode) => mode.trim().toLowerCase())
        .toSet();
    double sum = 0.0;
    for (final entry in entries) {
      if (!normalizedModes.contains(entry.mode.trim().toLowerCase())) {
        continue;
      }
      sum += entry.amount;
    }
    return sum;
  }

  static bool isUpiOnlyMode(String mode) {
    return mode.trim().toLowerCase() == 'upi';
  }

  static bool isNonCashMode(String mode) {
    final normalized = mode.trim().toLowerCase();
    return normalized == 'upi' || normalized == 'banking';
  }
}

class PaymentEntryValue {
  const PaymentEntryValue({required this.mode, required this.amount});

  final String mode;
  final double amount;
}
