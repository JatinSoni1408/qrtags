// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get dueAmount => 'Due Amount';

  @override
  String get refundAmount => 'Refund Amount';

  @override
  String get transactionSettled => 'Transaction Settled';

  @override
  String get hindiShort => 'हिं';

  @override
  String get unableAnnounceAmount => 'Unable to announce amount';

  @override
  String get ttsTransactionSettled => 'Transaction settled.';

  @override
  String ttsDueAmountIs(Object amountWords) {
    return 'Due amount is $amountWords.';
  }

  @override
  String ttsRefundAmountIs(Object amountWords) {
    return 'Refund amount is $amountWords.';
  }

  @override
  String get pdfInvoiceNo => 'Invoice No';

  @override
  String get pdfBillDateTime => 'Bill Date & Time';

  @override
  String get pdfCustomerDetails => 'Customer Details';

  @override
  String get pdfCustomerName => 'Customer Name';

  @override
  String get pdfCustomerMobile => 'Customer Mobile';

  @override
  String get pdfQuickItemSummary => 'Quick Item Summary';

  @override
  String get pdfCategoryWeightSummary => 'Category Weight Summary';

  @override
  String get pdfItemWisePriceBreakup => 'Item-wise Price Breakup';

  @override
  String get pdfSNo => 'S.No';

  @override
  String get pdfItemName => 'Item Name';

  @override
  String get pdfCategory => 'Category';

  @override
  String get pdfGrossWt => 'Gross Wt';

  @override
  String get pdfLessWt => 'Less Wt';

  @override
  String get pdfNetWt => 'Net Wt';

  @override
  String get pdfRate => 'Rate';

  @override
  String get pdfMaking => 'Making';

  @override
  String get pdfGst => 'GST';

  @override
  String get pdfAdditional => 'Additional';

  @override
  String get pdfTotal => 'Total';

  @override
  String get pdfOldItemsDetails => 'Old Items Details';

  @override
  String get pdfTotalsAndPaymentDetails => 'Totals and Payment Details';

  @override
  String get pdfTotals => 'Totals';

  @override
  String get pdfSubtotal => 'Subtotal';

  @override
  String get pdfOldGoldDeduction => 'Old Gold Deduction';

  @override
  String get pdfDiscount => 'Discount';

  @override
  String get pdfGstTotal => 'GST Total';

  @override
  String get pdfGrandTotalPayable => 'Grand Total Payable';

  @override
  String get pdfPaymentDetails => 'Payment Details';

  @override
  String get pdfTotalAmountReceived => 'Total Amount Received';

  @override
  String get pdfTermsAndPolicies => 'Terms & Policies';

  @override
  String get pdfPolicyLine1 =>
      '1. Exchange or buyback value is decided as per prevailing shop policy.';

  @override
  String get pdfPolicyLine2 =>
      '2. Please keep this bill for future exchange and service.';

  @override
  String get pdfSelectedItems => 'Selected Items';

  @override
  String get pdfOldItems => 'Old Items';

  @override
  String get pdfAdditionalTotal => 'Additional Total';
}
