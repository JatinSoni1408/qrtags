part of '../total_page.dart';

extension _TotalPagePdfExtension on _TotalPageState {
  String _formatInvoiceNumber(DateTime now, int sequence) {
    final datePart =
        '${now.year}${_twoDigits(now.month)}${_twoDigits(now.day)}';
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
    final normalizedCustomerName = customerName.trim();
    final normalizedCustomerMobile = customerMobile.trim();
    final netPayable = data.selectedTotal - data.oldTotal - discount;
    final totalReceived = cashReceived + upiReceived;
    final diff = _normalizeMoneyDelta(netPayable - totalReceived);
    final dueLabel = diff < 0
        ? tr('Refund Amount', 'वापसी राशि')
        : tr('Due Amount', 'बकाया राशि');
    final dueValue = diff.abs();
    final dueText =
        '${diff < 0 ? '-' : ''}${PriceCalculator.formatIndianAmount(dueValue)}';
    final billDateShort =
        '${_twoDigits(now.day)}/${_twoDigits(now.month)}/${_twoDigits(now.year % 100)}';
    final hasGstApplied = data.selectedItems
        .any((item) => item.gstAmount.abs() > 0.000001);
    final billStatus = hasGstApplied ? 'PENDING' : '-';
    await _getOrCreateInvoiceNumber(now: now);
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

    String formatIndianNoDecimals(double value) {
      final isNegative = value < 0;
      final absValue = value.abs().round();
      final intPart = absValue.toString();
      if (intPart.length <= 3) {
        return '${isNegative ? '-' : ''}$intPart';
      }
      final last3 = intPart.substring(intPart.length - 3);
      final rest = intPart.substring(0, intPart.length - 3);
      final buffer = StringBuffer();
      for (int i = 0; i < rest.length; i++) {
        buffer.write(rest[i]);
        final posFromEnd = rest.length - i - 1;
        if (posFromEnd % 2 == 0 && posFromEnd != 0) {
          buffer.write(',');
        }
      }
      return '${isNegative ? '-' : ''}${buffer.toString()},$last3';
    }

    String formatRateText(_SelectedItemView item) {
      final normalizedCategory = item.category.trim().toLowerCase();
      if (normalizedCategory.contains('gold')) {
        return formatIndianNoDecimals(item.rate);
      }
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

    String formatReturnPurityText(_SelectedItemView item) {
      final normalizedCategory = item.category.trim().toLowerCase();
      if (normalizedCategory.contains('gold22kt')) {
        return '22kt';
      }
      if (normalizedCategory.contains('gold18kt')) {
        return '18kt';
      }
      return item.returnPurity;
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

    pw.Widget buildAdditionalTable() {
      if (additionalTypeTotals.isEmpty) {
        return pw.SizedBox.shrink();
      }

      pw.Widget cell(
        String text, {
        bool right = false,
        bool bold = false,
      }) {
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 6),
          child: pw.Align(
            alignment:
                right ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
            child: pw.Text(
              text,
              maxLines: 1,
              softWrap: false,
              overflow: pw.TextOverflow.clip,
              style: pw.TextStyle(
                fontSize: 9.3,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
        );
      }

      return pw.Table(
        border: pw.TableBorder.all(width: 0.6, color: PdfColors.black),
        columnWidths: {
          0: const pw.FlexColumnWidth(2.2),
          1: const pw.FlexColumnWidth(1.4),
          2: const pw.FlexColumnWidth(1.4),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey300),
            children: [
              cell(tr('Additional Name', 'अतिरिक्त नाम'), bold: true),
              cell(tr('Amount', 'राशि'), right: true, bold: true),
              cell(tr('Total', 'कुल'), right: true, bold: true),
            ],
          ),
          ...additionalTypeKeys.map(
            (type) => pw.TableRow(
              children: [
                cell(type),
                cell(
                  PriceCalculator.formatIndianAmount(
                    additionalTypeTotals[type] ?? 0.0,
                  ),
                  right: true,
                ),
                cell(''),
              ],
            ),
          ),
          pw.TableRow(
            children: [
              cell(tr('Total', 'कुल'), bold: true),
              cell('', right: true),
              cell(
                PriceCalculator.formatIndianAmount(totalAdditionalCharges),
                right: true,
                bold: true,
              ),
            ],
          ),
        ],
      );
    }

    final amountSummaryRows = <pw.Widget>[
      if (additionalTypeTotals.isNotEmpty) buildAdditionalTable(),
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
                    maxLines: 1,
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
                    maxLines: 1,
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
                    maxLines: 1,
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
                    maxLines: 1,
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
                    child: pw.Text(category, maxLines: 1, style: labelStyle),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: pw.Text(
                      totals[0].toStringAsFixed(3),
                      maxLines: 1,
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
                      maxLines: 1,
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
                      maxLines: 1,
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
    const pagesToGenerate = 1;
    for (var i = 0; i < pagesToGenerate; i++) {
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
                      pw.Stack(
                        alignment: pw.Alignment.center,
                        children: [
                          pw.Center(
                            child: pw.Text(
                              'ESTIMATED',
                              style: sectionStyle.copyWith(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 12.2,
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                          pw.Positioned(
                            right: 0,
                            child: pw.Text(
                              'Date: $billDateShort',
                              style: valueStyle,
                              textAlign: pw.TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 6),
                      pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Expanded(
                            child: pw.Text(
                              normalizedCustomerName.isEmpty
                                  ? 'Name: ______________________________________'
                                  : 'Name: $normalizedCustomerName',
                              style: valueStyle,
                              textAlign: pw.TextAlign.left,
                            ),
                          ),
                          pw.SizedBox(width: 8),
                          pw.Expanded(
                            child: pw.Align(
                              alignment: pw.Alignment.centerRight,
                              child: pw.Text(
                                normalizedCustomerMobile.isEmpty
                                    ? 'Mobile: ______________________'
                                    : 'Mobile: $normalizedCustomerMobile',
                                style: valueStyle,
                                textAlign: pw.TextAlign.right,
                              ),
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
                          if (amountSummaryRows.isNotEmpty) ...[
                            pw.Expanded(
                              flex: 1,
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text(
                                    tr('Additionals Summary', 'अतिरिक्त सारांश'),
                                    style: sectionStyle,
                                  ),
                                  pw.SizedBox(height: 6),
                                  ...amountSummaryRows,
                                ],
                              ),
                            ),
                            pw.SizedBox(width: 16),
                          ],
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
                              tr('Gross', 'ग्रॉस'),
                              tr('Less', 'कम'),
                              tr('Net', 'नेट'),
                              tr('Rate', 'रेट'),
                              tr('Making', 'मेकिंग'),
                               tr('Others', 'Others'),
                              tr('Additional', 'अतिरिक्त'),
                              tr('R%', 'R%'),
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
                            item.gstAmount > 0
                                ? PriceCalculator.formatIndianAmount(
                                    item.gstAmount,
                                  )
                                : '-',
                            PriceCalculator.formatIndianAmount(
                              item.additionalAmount,
                            ),
                            formatReturnPurityText(item),
                            PriceCalculator.formatIndianAmount(item.amount),
                          ];
                        }).toList(),
                        headerAlignments: const {
                          0: pw.Alignment.center,
                          3: pw.Alignment.centerRight,
                          4: pw.Alignment.centerRight,
                          5: pw.Alignment.centerRight,
                          6: pw.Alignment.centerRight,
                          7: pw.Alignment.centerRight,
                          8: pw.Alignment.center,
                          9: pw.Alignment.centerRight,
                          10: pw.Alignment.center,
                          11: pw.Alignment.centerRight,
                        },
                        cellAlignments: const {
                          0: pw.Alignment.center,
                          3: pw.Alignment.centerRight,
                          4: pw.Alignment.centerRight,
                          5: pw.Alignment.centerRight,
                          6: pw.Alignment.centerRight,
                          7: pw.Alignment.centerRight,
                          8: pw.Alignment.center,
                          9: pw.Alignment.centerRight,
                          10: pw.Alignment.center,
                          11: pw.Alignment.centerRight,
                        },
                        headerStyle: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 8.6,
                        ),
                        cellBuilder: (index, cell, rowNum) {
                          return pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 1,
                            ),
                            child: pw.FittedBox(
                              fit: pw.BoxFit.scaleDown,
                              alignment: pw.Alignment.centerLeft,
                              child: pw.Text(
                                cell.toString(),
                                maxLines: 1,
                                style: const pw.TextStyle(fontSize: 8.0),
                              ),
                            ),
                          );
                        },
                        border: pw.TableBorder.all(
                          color: PdfColors.black,
                          width: 0.6,
                        ),
                        headerDecoration: const pw.BoxDecoration(
                          color: PdfColors.grey300,
                        ),
                        columnWidths: {
                          0: const pw.FlexColumnWidth(0.8),
                          1: const pw.FlexColumnWidth(2.2),
                          2: const pw.FlexColumnWidth(1.4),
                          3: const pw.FlexColumnWidth(1.1),
                          4: const pw.FlexColumnWidth(1.0),
                          5: const pw.FlexColumnWidth(1.0),
                          6: const pw.FlexColumnWidth(1.4),
                          7: const pw.FlexColumnWidth(1.0),
                          8: const pw.FlexColumnWidth(1.1),
                          9: const pw.FlexColumnWidth(1.6),
                          10: const pw.FlexColumnWidth(0.8),
                          11: const pw.FlexColumnWidth(1.4),
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
                                  tr(
                                    'Old Items Deduction',
                                    'पुराना सोना कटौती',
                                  ),
                                  '-${PriceCalculator.formatIndianAmount(data.oldTotal)}',
                                ),
                                if (discount > 0)
                                  keyValue(
                                    tr('Discount', 'छूट'),
                                    '-${PriceCalculator.formatIndianAmount(discount)}',
                                  ),
                                keyValue(
                                  tr('Total Payable', 'देय कुल राशि'),
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
                                    'Total Amount',
                                    'कुल राशि',
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
                    if (billStatus == 'PENDING')
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 12),
                        child: pw.Center(
                          child: pw.Text(
                            'BILL PENDING',
                            style: sectionStyle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    }

    return doc.save();
  }

  Future<void> _previewTotalsPdf(
    _TotalsData data,
    double cashReceived,
    double upiReceived,
    double discount,
  ) async {
    if (!_validateCustomerDetails()) {
      return;
    }
    final paymentEntriesSnapshot = _buildPaymentEntryRowsForPdf();
    final customerName = _customerNameController.text.trim();
    final customerMobile = _customerMobileController.text.trim();
    String buildShareFileName() {
      final safeName = customerName
          .replaceAll(RegExp(r'[^A-Za-z0-9 ]'), '')
          .trim()
          .replaceAll(RegExp(r'\s+'), '_');
      final safeMobile = customerMobile.replaceAll(RegExp(r'[^0-9]'), '');
      if (safeName.isNotEmpty && safeMobile.isNotEmpty) {
        return '$safeName-$safeMobile.pdf';
      }
      if (safeName.isNotEmpty) {
        return '$safeName.pdf';
      }
      if (safeMobile.isNotEmpty) {
        return '$safeMobile.pdf';
      }
      final batch = ShareFileNamer.startBatch(prefix: 'bl', extension: 'pdf');
      return batch.nextName();
    }

    Future<void> shareBill({
      required BuildContext actionContext,
      required LayoutCallback build,
      required String shareText,
      String? subject,
    }) async {
      if (_printingBill || _sharingBill) {
        return;
      }
      _sharingBill = true;
      try {
        final bytes = await Future<Uint8List>.value(
          build(_TotalPageState._billPageFormat),
        ).timeout(const Duration(seconds: 25));
        final fileName = buildShareFileName();
        await Share.shareXFiles(
          [XFile.fromData(bytes, name: fileName, mimeType: 'application/pdf')],
          fileNameOverrides: [fileName],
          text: shareText,
          subject: subject,
        );
      } on TimeoutException {
        if (!actionContext.mounted) {
          return;
        }
        ScaffoldMessenger.of(actionContext).showSnackBar(
          const SnackBar(
            content: Text('Preparing bill took too long. Please retry.'),
          ),
        );
      } catch (error, stackTrace) {
        debugPrint('TotalPage: failed to share bill: $error');
        debugPrintStack(stackTrace: stackTrace);
        if (!actionContext.mounted) {
          return;
        }
        ScaffoldMessenger.of(
          actionContext,
        ).showSnackBar(const SnackBar(content: Text('Failed to share bill')));
      } finally {
        _sharingBill = false;
      }
    }

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
                      if (_printingBill || _sharingBill) {
                        return;
                      }
                      _printingBill = true;
                      try {
                        final bytes = await Future<Uint8List>.value(
                          build(_TotalPageState._billPageFormat),
                        ).timeout(const Duration(seconds: 25));
                        final didPrint = await Printing.layoutPdf(
                          onLayout: (_) async => bytes,
                          name: 'Bill',
                          format: _TotalPageState._billPageFormat,
                          dynamicLayout: true,
                          usePrinterSettings: true,
                        ).timeout(const Duration(seconds: 45));
                        if (!actionContext.mounted) {
                          return;
                        }
                        if (!didPrint) {
                          ScaffoldMessenger.of(actionContext).showSnackBar(
                            const SnackBar(content: Text('Print cancelled')),
                          );
                        }
                      } on TimeoutException {
                        if (!actionContext.mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(actionContext).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Printer is taking too long. Please retry.',
                            ),
                          ),
                        );
                      } catch (error, stackTrace) {
                        debugPrint('TotalPage: failed to print bill: $error');
                        debugPrintStack(stackTrace: stackTrace);
                        if (!actionContext.mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(actionContext).showSnackBar(
                          const SnackBar(content: Text('Failed to print bill')),
                        );
                      } finally {
                        _printingBill = false;
                      }
                    },
                  ),
                  PdfPreviewAction(
                    icon: const Icon(Icons.share),
                    onPressed: (actionContext, build, pageFormat) async {
                      await shareBill(
                        actionContext: actionContext,
                        build: build,
                        shareText: 'Bill',
                      );
                    },
                  ),
                ],
                build: (pageFormat) => _buildTotalsPdfBytes(
                  data,
                  cashReceived,
                  upiReceived,
                  discount,
                  paymentEntriesSnapshot,
                  customerName,
                  customerMobile,
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
