import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('hi'),
  ];

  /// No description provided for @dueAmount.
  ///
  /// In en, this message translates to:
  /// **'Due Amount'**
  String get dueAmount;

  /// No description provided for @refundAmount.
  ///
  /// In en, this message translates to:
  /// **'Refund Amount'**
  String get refundAmount;

  /// No description provided for @transactionSettled.
  ///
  /// In en, this message translates to:
  /// **'Transaction Settled'**
  String get transactionSettled;

  /// No description provided for @hindiShort.
  ///
  /// In en, this message translates to:
  /// **'हिं'**
  String get hindiShort;

  /// No description provided for @unableAnnounceAmount.
  ///
  /// In en, this message translates to:
  /// **'Unable to announce amount'**
  String get unableAnnounceAmount;

  /// No description provided for @ttsTransactionSettled.
  ///
  /// In en, this message translates to:
  /// **'Transaction settled.'**
  String get ttsTransactionSettled;

  /// No description provided for @ttsDueAmountIs.
  ///
  /// In en, this message translates to:
  /// **'Due amount is {amountWords}.'**
  String ttsDueAmountIs(Object amountWords);

  /// No description provided for @ttsRefundAmountIs.
  ///
  /// In en, this message translates to:
  /// **'Refund amount is {amountWords}.'**
  String ttsRefundAmountIs(Object amountWords);

  /// No description provided for @pdfInvoiceNo.
  ///
  /// In en, this message translates to:
  /// **'Invoice No'**
  String get pdfInvoiceNo;

  /// No description provided for @pdfBillDateTime.
  ///
  /// In en, this message translates to:
  /// **'Bill Date & Time'**
  String get pdfBillDateTime;

  /// No description provided for @pdfCustomerDetails.
  ///
  /// In en, this message translates to:
  /// **'Customer Details'**
  String get pdfCustomerDetails;

  /// No description provided for @pdfCustomerName.
  ///
  /// In en, this message translates to:
  /// **'Customer Name'**
  String get pdfCustomerName;

  /// No description provided for @pdfCustomerMobile.
  ///
  /// In en, this message translates to:
  /// **'Customer Mobile'**
  String get pdfCustomerMobile;

  /// No description provided for @pdfQuickItemSummary.
  ///
  /// In en, this message translates to:
  /// **'Quick Item Summary'**
  String get pdfQuickItemSummary;

  /// No description provided for @pdfCategoryWeightSummary.
  ///
  /// In en, this message translates to:
  /// **'Category Weight Summary'**
  String get pdfCategoryWeightSummary;

  /// No description provided for @pdfItemWisePriceBreakup.
  ///
  /// In en, this message translates to:
  /// **'Item-wise Price Breakup'**
  String get pdfItemWisePriceBreakup;

  /// No description provided for @pdfSNo.
  ///
  /// In en, this message translates to:
  /// **'S.No'**
  String get pdfSNo;

  /// No description provided for @pdfItemName.
  ///
  /// In en, this message translates to:
  /// **'Item Name'**
  String get pdfItemName;

  /// No description provided for @pdfCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get pdfCategory;

  /// No description provided for @pdfGrossWt.
  ///
  /// In en, this message translates to:
  /// **'Gross Wt'**
  String get pdfGrossWt;

  /// No description provided for @pdfLessWt.
  ///
  /// In en, this message translates to:
  /// **'Less Wt'**
  String get pdfLessWt;

  /// No description provided for @pdfNetWt.
  ///
  /// In en, this message translates to:
  /// **'Net Wt'**
  String get pdfNetWt;

  /// No description provided for @pdfRate.
  ///
  /// In en, this message translates to:
  /// **'Rate'**
  String get pdfRate;

  /// No description provided for @pdfMaking.
  ///
  /// In en, this message translates to:
  /// **'Making'**
  String get pdfMaking;

  /// No description provided for @pdfGst.
  ///
  /// In en, this message translates to:
  /// **'GST'**
  String get pdfGst;

  /// No description provided for @pdfAdditional.
  ///
  /// In en, this message translates to:
  /// **'Additional'**
  String get pdfAdditional;

  /// No description provided for @pdfTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get pdfTotal;

  /// No description provided for @pdfOldItemsDetails.
  ///
  /// In en, this message translates to:
  /// **'Old Items Details'**
  String get pdfOldItemsDetails;

  /// No description provided for @pdfTotalsAndPaymentDetails.
  ///
  /// In en, this message translates to:
  /// **'Totals and Payment Details'**
  String get pdfTotalsAndPaymentDetails;

  /// No description provided for @pdfTotals.
  ///
  /// In en, this message translates to:
  /// **'Totals'**
  String get pdfTotals;

  /// No description provided for @pdfSubtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get pdfSubtotal;

  /// No description provided for @pdfOldGoldDeduction.
  ///
  /// In en, this message translates to:
  /// **'Old Gold Deduction'**
  String get pdfOldGoldDeduction;

  /// No description provided for @pdfDiscount.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get pdfDiscount;

  /// No description provided for @pdfGstTotal.
  ///
  /// In en, this message translates to:
  /// **'GST Total'**
  String get pdfGstTotal;

  /// No description provided for @pdfGrandTotalPayable.
  ///
  /// In en, this message translates to:
  /// **'Grand Total Payable'**
  String get pdfGrandTotalPayable;

  /// No description provided for @pdfPaymentDetails.
  ///
  /// In en, this message translates to:
  /// **'Payment Details'**
  String get pdfPaymentDetails;

  /// No description provided for @pdfTotalAmountReceived.
  ///
  /// In en, this message translates to:
  /// **'Total Amount Received'**
  String get pdfTotalAmountReceived;

  /// No description provided for @pdfTermsAndPolicies.
  ///
  /// In en, this message translates to:
  /// **'Terms & Policies'**
  String get pdfTermsAndPolicies;

  /// No description provided for @pdfPolicyLine1.
  ///
  /// In en, this message translates to:
  /// **'1. Exchange or buyback value is decided as per prevailing shop policy.'**
  String get pdfPolicyLine1;

  /// No description provided for @pdfPolicyLine2.
  ///
  /// In en, this message translates to:
  /// **'2. Please keep this bill for future exchange and service.'**
  String get pdfPolicyLine2;

  /// No description provided for @pdfSelectedItems.
  ///
  /// In en, this message translates to:
  /// **'Selected Items'**
  String get pdfSelectedItems;

  /// No description provided for @pdfOldItems.
  ///
  /// In en, this message translates to:
  /// **'Old Items'**
  String get pdfOldItems;

  /// No description provided for @pdfAdditionalTotal.
  ///
  /// In en, this message translates to:
  /// **'Additional Total'**
  String get pdfAdditionalTotal;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'hi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
