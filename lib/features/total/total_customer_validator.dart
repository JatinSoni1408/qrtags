class TotalCustomerValidator {
  const TotalCustomerValidator._();

  static String? validate({
    required String customerName,
    required String customerMobile,
  }) {
    // Customer details are optional. Validate mobile only when provided.
    final _ = customerName.trim();
    final mobileError = validateMobile(customerMobile);
    if (mobileError != null) {
      return mobileError;
    }
    return null;
  }

  static String? validateMobile(String customerMobile) {
    final raw = customerMobile.trim();
    if (raw.isEmpty) {
      return null;
    }
    final digitsOnly = raw.replaceAll(RegExp(r'[^0-9]'), '');
    final normalized = digitsOnly.startsWith('91') && digitsOnly.length == 12
        ? digitsOnly.substring(2)
        : digitsOnly;
    final isValidIndianMobile = RegExp(r'^[6-9][0-9]{9}$').hasMatch(normalized);
    if (!isValidIndianMobile) {
      return 'Enter a valid mobile number';
    }
    return null;
  }
}
