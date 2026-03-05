part of '../total_page.dart';

extension _TotalPagePdfExtension on _TotalPageState {
  String _formatInvoiceNumber(DateTime now, int sequence) {
    final datePart = '${now.year}${_twoDigits(now.month)}${_twoDigits(now.day)}';
    final sequencePart = sequence.toString().padLeft(4, '0');
    return 'INV-$datePart-$sequencePart';
  }

  String _fallbackInvoiceNumber(DateTime now) {
    return 'INV-${now.year}${_twoDigits(now.month)}${_twoDigits(now.day)}-${_twoDigits(now.hour)}${_twoDigits(now.minute)}${_twoDigits(now.second)}';
  }

  Future<String> _getOrCreateInvoiceNumber({DateTime? now}) async {
    final dateTime = now ?? DateTime.now();
    if (_activeInvoiceNo != null && _activeInvoiceNo!.trim().isNotEmpty) {
      return _activeInvoiceNo!;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedDraft = prefs.getString(StorageKeys.totalDraftInvoiceNo);
      if (storedDraft != null && storedDraft.trim().isNotEmpty) {
        _activeInvoiceNo = storedDraft;
        return storedDraft;
      }
      final next = (prefs.getInt(StorageKeys.totalInvoiceCounter) ?? 0) + 1;
      final invoiceNo = _formatInvoiceNumber(dateTime, next);
      await prefs.setInt(StorageKeys.totalInvoiceCounter, next);
      await prefs.setString(StorageKeys.totalDraftInvoiceNo, invoiceNo);
      _activeInvoiceNo = invoiceNo;
      return invoiceNo;
    } catch (error, stackTrace) {
      debugPrint('TotalPage: failed to fetch invoice sequence: $error');
      debugPrintStack(stackTrace: stackTrace);
      final fallback = _fallbackInvoiceNumber(dateTime);
      _activeInvoiceNo = fallback;
      return fallback;
    }
  }

  Future<Uint8List> _buildTotalsPdfBytes(
    _TotalsData data,
    double cashReceived,
    double upiReceived,
    double discount,
    List<_PaymentEntryPdfRow> paymentEntries,
    String customerName,
    String customerMobile,
    PdfPageFormat? pageFormat,
  ) async {
    final doc = pw.Document();
    final effectivePageFormat = pageFormat ?? _TotalPageState._billPageFormat;
    String tr(String english, String hindi) => english;
    final now = DateTime.now();
    final netPayable = data.selectedTotal - data.oldTotal - discount;
    final totalReceived = cashReceived + upiReceived;
    final diff = _normalizeMoneyDelta(netPayable - totalReceived);
    final dueLabel = diff < 0
        ? tr('Refund Amount', 'वापसी राशि')
        : tr('Due Amount', 'बकाया राशि');
    final dueValue = diff.abs();
    final dueText =
        '${diff < 0 ? '-' : ''}${PriceCalculator.formatIndianAmount(dueValue)}';
    final billDate =
        '${_twoDigits(now.day)}/${_twoDigits(now.month)}/${now.year}';
    final billTime =
        '${_twoDigits(now.hour)}:${_twoDigits(now.minute)}:${_twoDigits(now.second)}';
    final invoiceNo = await _getOrCreateInvoiceNumber(now: now);
    final sectionStyle = pw.TextStyle(
      fontSize: 11,
      fontWeight: pw.FontWeight.bold,
      letterSpacing: 0.4,
    );
    final labelStyle = const pw.TextStyle(fontSize: 9.5);
    final valueStyle = pw.TextStyle(
      fontSize: 9.8,
      fontWeight: pw.FontWeight.bold,
    );
    final shreeHeaderBytes = await _getShreeHeaderBytes();
    final shreeHeaderImage = shreeHeaderBytes == null
        ? null
        : pw.MemoryImage(shreeHeaderBytes);

    pw.Widget sectionTitle(String text) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(top: 12, bottom: 6),
        padding: const pw.EdgeInsets.only(bottom: 3),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(color: PdfColors.black, width: 0.8),
          ),
        ),
        child: pw.Text(text.toUpperCase(), style: sectionStyle),
      );
    }

    pw.Widget keyValueWidget(String label, pw.Widget valueWidget) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(flex: 5, child: pw.Text(label, style: labelStyle)),
            pw.SizedBox(width: 8),
            pw.Expanded(
              flex: 4,
              child: pw.Align(
                alignment: pw.Alignment.centerRight,
                child: valueWidget,
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget keyValue(String label, String value, {bool emphasize = false}) {
      return keyValueWidget(
        label,
        pw.Text(
          value,
          textAlign: pw.TextAlign.right,
          style: emphasize
              ? pw.TextStyle(fontSize: 10.3, fontWeight: pw.FontWeight.bold)
              : valueStyle,
        ),
      );
    }

    pw.Widget borderedBlock(List<pw.Widget> children) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.black, width: 0.8),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Column(children: children),
      );
    }

    String formatRateText(_SelectedItemView item) {
      return PriceCalculator.formatIndianAmount(item.rate);
    }

    String formatMakingText(_SelectedItemView item) {
      if (item.makingType == 'Percentage') {
        return '${item.makingCharge.toStringAsFixed(2)}%';
      }
      if (item.makingType == 'PerGram') {
        return '${PriceCalculator.formatIndianAmount(item.makingCharge)}/g';
      }
      if (item.makingType == 'FixRate') {
        return 'Fix Rate';
      }
      if (item.makingType == 'TotalMaking') {
        return 'T:${PriceCalculator.formatIndianAmount(item.makingCharge)}';
      }
      return PriceCalculator.formatIndianAmount(item.makingCharge);
    }

    final additionalTypeTotals = <String, double>{};
    for (final item in data.selectedItems) {
      for (final entry in item.additionalBreakup.entries) {
        additionalTypeTotals[entry.key] =
            (additionalTypeTotals[entry.key] ?? 0.0) + entry.value;
      }
    }
    final additionalTypeKeys = additionalTypeTotals.keys.toList()..sort();
    final totalAdditionalCharges = additionalTypeTotals.values.fold<double>(
      0.0,
      (sum, value) => sum + value,
    );

    final amountSummaryRows = <pw.Widget>[
      keyValue(tr('Selected Items', 'चयनित आइटम'), '${data.selectedCount}'),
      keyValue(tr('Old Items', 'पुराने आइटम'), '${data.oldItems.length}'),
      if (additionalTypeTotals.isNotEmpty)
        keyValue(
          tr('Additional Total', 'अतिरिक्त कुल'),
          PriceCalculator.formatIndianAmount(totalAdditionalCharges),
        ),
      ...additionalTypeKeys.map((type) {
        return keyValue(
          '  - $type',
          PriceCalculator.formatIndianAmount(additionalTypeTotals[type] ?? 0.0),
        );
      }),
    ];

    final categoryWeightTotals = <String, List<double>>{};
    for (final item in data.selectedItems) {
      final category = item.category.trim().isEmpty ? 'Other' : item.category;
      final bucket = categoryWeightTotals.putIfAbsent(
        category,
        () => <double>[0.0, 0.0, 0.0],
      );
      bucket[0] += item.grossWeight;
      bucket[1] += item.lessWeight;
      bucket[2] += item.weightValue;
    }
    const preferredCategoryOrder = <String>['Gold22kt', 'Gold18kt', 'Silver'];
    final otherCategories =
        categoryWeightTotals.keys
            .where((key) => !preferredCategoryOrder.contains(key))
            .toList()
          ..sort();
    final orderedCategories = <String>[
      ...preferredCategoryOrder.where(categoryWeightTotals.containsKey),
      ...otherCategories,
    ];

    final categoryWeightRows = <pw.Widget>[
      if (orderedCategories.isNotEmpty)
        pw.Table(
          border: const pw.TableBorder(
            bottom: pw.BorderSide(color: PdfColors.black, width: 1.1),
            verticalInside: pw.BorderSide(color: PdfColors.grey500, width: 0.4),
            horizontalInside: pw.BorderSide(
              color: PdfColors.grey500,
              width: 0.4,
            ),
          ),
          columnWidths: const {
            0: pw.FlexColumnWidth(1.8),
            1: pw.FlexColumnWidth(1.4),
            2: pw.FlexColumnWidth(1.4),
            3: pw.FlexColumnWidth(1.4),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey300),
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: pw.Text(
                    'Category',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: pw.Text(
                    'Gross',
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: pw.Text(
                    'Less',
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: pw.Text(
                    'Net',
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
              ],
            ),
            ...orderedCategories.map((category) {
              final totals = categoryWeightTotals[category]!;
              return pw.TableRow(
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: pw.Text(category, style: labelStyle),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: pw.Text(
                      totals[0].toStringAsFixed(3),
                      textAlign: pw.TextAlign.right,
                      style: labelStyle,
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: pw.Text(
                      totals[1].toStringAsFixed(3),
                      textAlign: pw.TextAlign.right,
                      style: labelStyle,
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: pw.Text(
                      totals[2].toStringAsFixed(3),
                      textAlign: pw.TextAlign.right,
                      style: labelStyle,
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      if (orderedCategories.isEmpty) pw.Text('-', style: labelStyle),
    ];
    final paymentEntryRowsForPdf = paymentEntries.toList()
      ..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        if (byDate != 0) {
          return byDate;
        }
        final byMode = a.mode.compareTo(b.mode);
        if (byMode != 0) {
          return byMode;
        }
        return b.amount.compareTo(a.amount);
      });
    final paymentGridRows = paymentEntryRowsForPdf.map((row) {
      final isCash = row.mode.trim().toLowerCase() == 'cash';
      final isUpi = _isNonCashMode(row.mode);
      return [
        '${_twoDigits(row.date.day)}/${_twoDigits(row.date.month)}/${row.date.year}',
        row.mode,
        isCash ? PriceCalculator.formatIndianAmount(row.amount) : '-',
        isUpi ? PriceCalculator.formatIndianAmount(row.amount) : '-',
      ];
    }).toList();
    final categoryRank = <String, int>{
      for (var i = 0; i < orderedCategories.length; i++)
        orderedCategories[i]: i,
    };
    final selectedItemsForBreakup = data.selectedItems.toList()
      ..sort((a, b) {
        final aCategory = a.category.trim().isEmpty ? 'Other' : a.category;
        final bCategory = b.category.trim().isEmpty ? 'Other' : b.category;
        final aRank = categoryRank[aCategory] ?? orderedCategories.length;
        final bRank = categoryRank[bCategory] ?? orderedCategories.length;
        final byCategory = aRank.compareTo(bRank);
        if (byCategory != 0) {
          return byCategory;
        }
        final byWeight = b.weightValue.compareTo(a.weightValue);
        if (byWeight != 0) {
          return byWeight;
        }
        return a.title.compareTo(b.title);
      });

    // Extra left margin keeps text safe from 2-hole/4-hole punchers.
    const pdfLeftPunchMargin = 46.0;
    const pdfRightMargin = 24.0;
    const pdfTopMargin = 24.0;
    const pdfBottomMargin = 24.0;
    doc.addPage(
      pw.Page(
        pageFormat: effectivePageFormat,
        margin: const pw.EdgeInsets.fromLTRB(
          pdfLeftPunchMargin,
          pdfTopMargin,
          pdfRightMargin,
          pdfBottomMargin,
        ),
        build: (context) {
          final contentWidth =
              effectivePageFormat.width - pdfLeftPunchMargin - pdfRightMargin;
          final contentHeight =
              effectivePageFormat.height - pdfTopMargin - pdfBottomMargin;
          return pw.SizedBox(
            width: contentWidth,
            height: contentHeight,
            child: pw.FittedBox(
              fit: pw.BoxFit.scaleDown,
              alignment: pw.Alignment.topCenter,
              child: pw.SizedBox(
                width: contentWidth,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Center(
                      child: shreeHeaderImage == null
                          ? pw.Text(
                              'Shree',
                              style: pw.TextStyle(
                                fontSize: 5,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            )
                          : pw.Image(
                              shreeHeaderImage,
                              width: 35,
                              fit: pw.BoxFit.contain,
                            ),
                    ),
                    pw.SizedBox(height: 8),
                    borderedBlock([
                      pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Expanded(
                            flex: 1,
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.RichText(
                                  text: pw.TextSpan(
                                    children: [
                                      pw.TextSpan(
                                        text: 'ESTIMATED ',
                                        style: sectionStyle.copyWith(
                                          fontWeight: pw.FontWeight.bold,
                                          fontSize: 12.2,
                                        ),
                                      ),
                                      pw.TextSpan(
                                        text: 'Details',
                                        style: sectionStyle,
                                      ),
                                    ],
                                  ),
                                ),
                                pw.SizedBox(height: 6),
                                keyValue(
                                  tr('Invoice No', 'इनवॉइस नं.'),
                                  invoiceNo,
                                ),
                                keyValue(
                                  tr('Bill Date & Time', 'बिल दिनांक व समय'),
                                  '$billDate $billTime',
                                ),
                              ],
                            ),
                          ),
                          pw.SizedBox(width: 16),
                          pw.Expanded(
                            flex: 1,
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  tr('Customer Details', 'ग्राहक विवरण'),
                                  style: sectionStyle,
                                ),
                                pw.SizedBox(height: 6),
                                keyValue(
                                  tr('Customer Name', 'ग्राहक नाम'),
                                  customerName.isEmpty
                                      ? '________________'
                                      : customerName,
                                ),
                                keyValueWidget(
                                  tr('Customer Mobile', 'मोबाइल नंबर'),
                                  customerMobile.isEmpty
                                      ? pw.Text(
                                          '________________',
                                          textAlign: pw.TextAlign.right,
                                          style: valueStyle,
                                        )
                                      : pw.Text(
                                          customerMobile,
                                          textAlign: pw.TextAlign.right,
                                          style: valueStyle,
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ]),
                    pw.SizedBox(height: 8),
                    borderedBlock([
                      pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Expanded(
                            flex: 1,
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  tr(
                                    'Quick Item Summary',
                                    'त्वरित आइटम सारांश',
                                  ),
                                  style: sectionStyle,
                                ),
                                pw.SizedBox(height: 6),
                                ...amountSummaryRows,
                              ],
                            ),
                          ),
                          pw.SizedBox(width: 16),
                          pw.Expanded(
                            flex: 1,
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  tr(
                                    'Category Weight Summary',
                                    'श्रेणी वजन सारांश',
                                  ),
                                  style: sectionStyle,
                                ),
                                pw.SizedBox(height: 6),
                                ...categoryWeightRows,
                              ],
                            ),
                          ),
                        ],
                      ),
                    ]),
                    if (data.selectedItems.isNotEmpty) ...[
                      sectionTitle(
                        tr(
                          'Item-wise Price Breakup',
                          'आइटम अनुसार मूल्य विवरण',
                        ),
                      ),
                      pw.TableHelper.fromTextArray(
                        headers:
                            <String>[
                              tr('S.No', 'क्र.सं.'),
                              tr('Item Name', 'आइटम नाम'),
                              tr('Category', 'श्रेणी'),
                              tr('Gross Wt', 'ग्रॉस वज़न'),
                              tr('Less Wt', 'कम वज़न'),
                              tr('Net Wt', 'नेट वज़न'),
                              tr('Rate', 'रेट'),
                              tr('Making', 'मेकिंग'),
                              tr('GST', 'जीएसटी'),
                              tr('Additional', 'अतिरिक्त'),
                              tr('Total', 'कुल'),
                            ].map((text) {
                              return pw.Center(
                                child: pw.FittedBox(
                                  fit: pw.BoxFit.scaleDown,
                                  child: pw.Text(
                                    text,
                                    style: pw.TextStyle(
                                      fontWeight: pw.FontWeight.bold,
                                      fontSize: 9.2,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                        data: selectedItemsForBreakup.asMap().entries.map((
                          entry,
                        ) {
                          final index = entry.key + 1;
                          final item = entry.value;
                          return [
                            '$index',
                            item.title,
                            item.categoryDisplay,
                            item.grossWeight.toStringAsFixed(3),
                            item.lessWeight.toStringAsFixed(3),
                            item.weightValue.toStringAsFixed(3),
                            formatRateText(item),
                            formatMakingText(item),
                            item.gstDisplay,
                            PriceCalculator.formatIndianAmount(
                              item.additionalAmount,
                            ),
                            PriceCalculator.formatIndianAmount(item.amount),
                          ];
                        }).toList(),
                        headerAlignments: const {
                          9: pw.Alignment.centerRight,
                          10: pw.Alignment.center,
                        },
                        cellAlignments: const {
                          9: pw.Alignment.centerRight,
                          10: pw.Alignment.centerRight,
                        },
                        headerStyle: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 9.2,
                        ),
                        cellStyle: const pw.TextStyle(fontSize: 8.8),
                        cellBuilder: (index, cell, rowNum) {
                          if (index == 10) {
                            return pw.FittedBox(
                              fit: pw.BoxFit.scaleDown,
                              alignment: pw.Alignment.centerRight,
                              child: pw.Text(
                                cell.toString(),
                                style: const pw.TextStyle(fontSize: 8.8),
                              ),
                            );
                          }
                          return null;
                        },
                        border: pw.TableBorder.all(
                          color: PdfColors.black,
                          width: 0.6,
                        ),
                        headerDecoration: const pw.BoxDecoration(
                          color: PdfColors.grey300,
                        ),
                        columnWidths: {
                          0: const pw.FlexColumnWidth(1),
                          1: const pw.FlexColumnWidth(2.8),
                          2: const pw.FlexColumnWidth(1.6),
                          3: const pw.FlexColumnWidth(1.3),
                          4: const pw.FlexColumnWidth(1.2),
                          5: const pw.FlexColumnWidth(1.2),
                          6: const pw.FlexColumnWidth(1.3),
                          7: const pw.FlexColumnWidth(1.8),
                          8: const pw.FlexColumnWidth(0.9),
                          9: const pw.FlexColumnWidth(1.4),
                          10: const pw.FlexColumnWidth(2.0),
                        },
                      ),
                    ],
                    if (data.oldItems.isNotEmpty) ...[
                      sectionTitle(
                        tr('Old Items Details', 'पुराने आइटम विवरण'),
                      ),
                      pw.TableHelper.fromTextArray(
                        headers: const [
                          'S.No',
                          'Item Name',
                          'Gross Wt',
                          'Less Wt',
                          'Net Wt',
                          'Calculation',
                          'Total',
                        ],
                        data: data.oldItems.asMap().entries.map((entry) {
                          final index = entry.key + 1;
                          final item = entry.value;
                          return [
                            '$index',
                            item.title,
                            item.grossWeight.toStringAsFixed(3),
                            item.lessWeight.toStringAsFixed(3),
                            item.netWeight.toStringAsFixed(3),
                            item.formulaText,
                            PriceCalculator.formatIndianAmount(item.amount),
                          ];
                        }).toList(),
                        headerAlignments: const {6: pw.Alignment.centerRight},
                        cellAlignments: const {6: pw.Alignment.centerRight},
                        headerStyle: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 9.2,
                        ),
                        cellStyle: const pw.TextStyle(fontSize: 8.8),
                        border: pw.TableBorder.all(
                          color: PdfColors.black,
                          width: 0.6,
                        ),
                        headerDecoration: const pw.BoxDecoration(
                          color: PdfColors.grey300,
                        ),
                        columnWidths: {
                          0: const pw.FlexColumnWidth(1),
                          1: const pw.FlexColumnWidth(2.3),
                          2: const pw.FlexColumnWidth(1.2),
                          3: const pw.FlexColumnWidth(1.2),
                          4: const pw.FlexColumnWidth(1.2),
                          5: const pw.FlexColumnWidth(2.8),
                          6: const pw.FlexColumnWidth(1.7),
                        },
                      ),
                    ],
                    sectionTitle(
                      tr('Totals and Payment Details', 'कुल और भुगतान विवरण'),
                    ),
                    borderedBlock([
                      pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Expanded(
                            flex: 1,
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  tr('Totals', 'कुल'),
                                  style: sectionStyle,
                                ),
                                pw.SizedBox(height: 6),
                                keyValue(
                                  tr('Subtotal', 'उप-योग'),
                                  PriceCalculator.formatIndianAmount(
                                    data.selectedTotal,
                                  ),
                                ),
                                keyValue(
                                  tr('Old Gold Deduction', 'पुराना सोना कटौती'),
                                  '-${PriceCalculator.formatIndianAmount(data.oldTotal)}',
                                ),
                                if (discount > 0)
                                  keyValue(
                                    tr('Discount', 'छूट'),
                                    '-${PriceCalculator.formatIndianAmount(discount)}',
                                  ),
                                keyValue(
                                  tr('GST Total', 'जीएसटी कुल'),
                                  PriceCalculator.formatIndianAmount(
                                    data.selectedGstTotal,
                                  ),
                                ),
                                keyValue(
                                  tr('Grand Total Payable', 'देय कुल राशि'),
                                  PriceCalculator.formatIndianAmount(
                                    netPayable,
                                  ),
                                  emphasize: true,
                                ),
                                keyValue(dueLabel, dueText, emphasize: true),
                              ],
                            ),
                          ),
                          pw.SizedBox(width: 16),
                          pw.Expanded(
                            flex: 1,
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  tr('Payment Details', 'भुगतान विवरण'),
                                  style: sectionStyle,
                                ),
                                pw.SizedBox(height: 6),
                                if (paymentGridRows.isNotEmpty)
                                  pw.Table(
                                    border: pw.TableBorder.all(
                                      color: PdfColors.grey500,
                                      width: 0.5,
                                    ),
                                    columnWidths: const {
                                      0: pw.FlexColumnWidth(1.55),
                                      1: pw.FlexColumnWidth(1.05),
                                      2: pw.FlexColumnWidth(1.2),
                                      3: pw.FlexColumnWidth(1.2),
                                    },
                                    children: [
                                      ...paymentGridRows.map((row) {
                                        return pw.TableRow(
                                          children: [
                                            pw.Padding(
                                              padding:
                                                  const pw.EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                    vertical: 3,
                                                  ),
                                              child: pw.Text(
                                                row[0],
                                                style: labelStyle,
                                              ),
                                            ),
                                            pw.Padding(
                                              padding:
                                                  const pw.EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                    vertical: 3,
                                                  ),
                                              child: pw.Text(
                                                row[1],
                                                style: labelStyle,
                                              ),
                                            ),
                                            pw.Padding(
                                              padding:
                                                  const pw.EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                    vertical: 3,
                                                  ),
                                              child: pw.Text(
                                                row[2],
                                                textAlign: pw.TextAlign.right,
                                                style: labelStyle,
                                              ),
                                            ),
                                            pw.Padding(
                                              padding:
                                                  const pw.EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                    vertical: 3,
                                                  ),
                                              child: pw.Text(
                                                row[3],
                                                textAlign: pw.TextAlign.right,
                                                style: labelStyle,
                                              ),
                                            ),
                                          ],
                                        );
                                      }),
                                      pw.TableRow(
                                        decoration: const pw.BoxDecoration(
                                          color: PdfColors.grey300,
                                        ),
                                        children: [
                                          pw.SizedBox(),
                                          pw.Padding(
                                            padding:
                                                const pw.EdgeInsets.symmetric(
                                                  horizontal: 4,
                                                  vertical: 3,
                                                ),
                                            child: pw.Text(
                                              tr('Total', 'कुल'),
                                              style: pw.TextStyle(
                                                fontWeight: pw.FontWeight.bold,
                                                fontSize: 9,
                                              ),
                                            ),
                                          ),
                                          pw.Padding(
                                            padding:
                                                const pw.EdgeInsets.symmetric(
                                                  horizontal: 4,
                                                  vertical: 3,
                                                ),
                                            child: pw.Text(
                                              PriceCalculator.formatIndianAmount(
                                                cashReceived,
                                              ),
                                              textAlign: pw.TextAlign.right,
                                              style: pw.TextStyle(
                                                fontWeight: pw.FontWeight.bold,
                                                fontSize: 9,
                                              ),
                                            ),
                                          ),
                                          pw.Padding(
                                            padding:
                                                const pw.EdgeInsets.symmetric(
                                                  horizontal: 4,
                                                  vertical: 3,
                                                ),
                                            child: pw.Text(
                                              PriceCalculator.formatIndianAmount(
                                                upiReceived,
                                              ),
                                              textAlign: pw.TextAlign.right,
                                              style: pw.TextStyle(
                                                fontWeight: pw.FontWeight.bold,
                                                fontSize: 9,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  )
                                else
                                  pw.Text('-', style: labelStyle),
                                pw.SizedBox(height: 5),
                                keyValue(
                                  tr(
                                    'Total Amount Received',
                                    'प्राप्त कुल राशि',
                                  ),
                                  PriceCalculator.formatIndianAmount(
                                    totalReceived,
                                  ),
                                  emphasize: true,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ]),
                    sectionTitle(tr('Terms & Policies', 'नियम व शर्तें')),
                    pw.Text(
                      tr(
                        '1. Exchange or buyback value is decided as per prevailing shop policy.',
                        '1. एक्सचेंज या बायबैक मूल्य दुकान की वर्तमान नीति के अनुसार तय होगा।',
                      ),
                      style: labelStyle,
                    ),
                    pw.Text(
                      tr(
                        '2. Please keep this bill for future exchange and service.',
                        '2. कृपया भविष्य के एक्सचेंज और सेवा हेतु यह बिल संभालकर रखें।',
                      ),
                      style: labelStyle,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    return doc.save();
  }


  Future<void> _previewTotalsPdf(
    _TotalsData data,
    double cashReceived,
    double upiReceived,
    double discount,
  ) async {
    final paymentEntriesSnapshot = _buildPaymentEntryRowsForPdf();
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) {
          return Scaffold(
            appBar: AppBar(title: const Text('Bill Preview')),
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: PdfPreview(
                useActions: true,
                allowPrinting: false,
                allowSharing: false,
                initialPageFormat: _TotalPageState._billPageFormat,
                dynamicLayout: false,
                canChangePageFormat: false,
                canChangeOrientation: false,
                canDebug: false,
                maxPageWidth: 1600,
                actions: [
                  PdfPreviewAction(
                    icon: const Icon(Icons.print),
                    onPressed: (actionContext, build, pageFormat) async {
                      try {
                        final didPrint = await Printing.layoutPdf(
                          onLayout: (pageFormat) => build(pageFormat),
                          name: 'Bill',
                          format: _TotalPageState._billPageFormat,
                          dynamicLayout: true,
                          usePrinterSettings: true,
                        );
                        if (!actionContext.mounted) {
                          return;
                        }
                        if (!didPrint) {
                          ScaffoldMessenger.of(actionContext).showSnackBar(
                            const SnackBar(content: Text('Print cancelled')),
                          );
                        }
                      } catch (error, stackTrace) {
                        debugPrint('TotalPage: failed to print bill: $error');
                        debugPrintStack(stackTrace: stackTrace);
                        if (!actionContext.mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(actionContext).showSnackBar(
                          const SnackBar(content: Text('Failed to print bill')),
                        );
                      }
                    },
                  ),
                ],
                build: (pageFormat) => _buildTotalsPdfBytes(
                  data,
                  cashReceived,
                  upiReceived,
                  discount,
                  paymentEntriesSnapshot,
                  '',
                  '',
                  pageFormat,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
