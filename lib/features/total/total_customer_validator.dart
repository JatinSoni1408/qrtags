class TotalCustomerValidator {
  const TotalCustomerValidator._();

  static String? validate({
    required String customerName,
    required String customerMobile,
  }) {
    final name = customerName.trim();
    final mobileDigits = customerMobile.replaceAll(RegExp(r'[^0-9]'), '');
    if (name.isEmpty) {
      return 'Please enter customer name';
    }
    if (mobileDigits.length != 10) {
      return 'Please enter a valid 10-digit mobile number';
    }
    if (!RegExp(r'^[6-9][0-9]{9}$').hasMatch(mobileDigits)) {
      return 'Mobile number must start with 6, 7, 8, or 9';
    }
    return null;
  }
}
