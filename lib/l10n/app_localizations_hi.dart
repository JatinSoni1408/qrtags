// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get dueAmount => 'बकाया राशि';

  @override
  String get refundAmount => 'वापसी राशि';

  @override
  String get transactionSettled => 'लेनदेन पूरा हो गया है';

  @override
  String get hindiShort => 'हिं';

  @override
  String get unableAnnounceAmount => 'राशि सुनाई नहीं जा सकी';

  @override
  String get ttsTransactionSettled => 'लेनदेन पूरा हो गया है।';

  @override
  String ttsDueAmountIs(Object amountWords) {
    return 'बाकी राशि $amountWords रुपये है।';
  }

  @override
  String ttsRefundAmountIs(Object amountWords) {
    return 'वापसी राशि $amountWords रुपये है।';
  }

  @override
  String get pdfInvoiceNo => 'इनवॉइस नं.';

  @override
  String get pdfBillDateTime => 'बिल दिनांक व समय';

  @override
  String get pdfCustomerDetails => 'ग्राहक विवरण';

  @override
  String get pdfCustomerName => 'ग्राहक नाम';

  @override
  String get pdfCustomerMobile => 'मोबाइल नंबर';

  @override
  String get pdfQuickItemSummary => 'त्वरित आइटम सारांश';

  @override
  String get pdfCategoryWeightSummary => 'श्रेणी वजन सारांश';

  @override
  String get pdfItemWisePriceBreakup => 'आइटम अनुसार मूल्य विवरण';

  @override
  String get pdfSNo => 'क्र.सं.';

  @override
  String get pdfItemName => 'आइटम नाम';

  @override
  String get pdfCategory => 'श्रेणी';

  @override
  String get pdfGrossWt => 'ग्रॉस वज़न';

  @override
  String get pdfLessWt => 'कम वज़न';

  @override
  String get pdfNetWt => 'नेट वज़न';

  @override
  String get pdfRate => 'रेट';

  @override
  String get pdfMaking => 'मेकिंग';

  @override
  String get pdfGst => 'जीएसटी';

  @override
  String get pdfAdditional => 'अतिरिक्त';

  @override
  String get pdfTotal => 'कुल';

  @override
  String get pdfOldItemsDetails => 'पुराने आइटम विवरण';

  @override
  String get pdfTotalsAndPaymentDetails => 'कुल और भुगतान विवरण';

  @override
  String get pdfTotals => 'कुल';

  @override
  String get pdfSubtotal => 'उप-योग';

  @override
  String get pdfOldGoldDeduction => 'पुराना सोना कटौती';

  @override
  String get pdfDiscount => 'छूट';

  @override
  String get pdfGstTotal => 'जीएसटी कुल';

  @override
  String get pdfGrandTotalPayable => 'देय कुल राशि';

  @override
  String get pdfPaymentDetails => 'भुगतान विवरण';

  @override
  String get pdfTotalAmountReceived => 'प्राप्त कुल राशि';

  @override
  String get pdfTermsAndPolicies => 'नियम व शर्तें';

  @override
  String get pdfPolicyLine1 =>
      '1. एक्सचेंज या बायबैक मूल्य दुकान की वर्तमान नीति के अनुसार तय होगा।';

  @override
  String get pdfPolicyLine2 =>
      '2. कृपया भविष्य के एक्सचेंज और सेवा हेतु यह बिल संभालकर रखें।';

  @override
  String get pdfSelectedItems => 'चयनित आइटम';

  @override
  String get pdfOldItems => 'पुराने आइटम';

  @override
  String get pdfAdditionalTotal => 'अतिरिक्त कुल';
}
