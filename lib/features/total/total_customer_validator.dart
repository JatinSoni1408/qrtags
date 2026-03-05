class TotalCustomerValidator {
  const TotalCustomerValidator._();

  static String? validate({
    required String customerName,
    required String customerMobile,
  }) {
    // Customer details are optional on the total page.
    final _ =
        customerName.trim().isNotEmpty || customerMobile.trim().isNotEmpty;
    return null;
  }
}
