import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../constants/storage_keys.dart';
import '../l10n/app_localizations.dart';
import '../utils/sales_notifier.dart';
import '../utils/selection_notifier.dart';
import '../features/total/payment_entry_calculator.dart';
import '../features/total/total_customer_validator.dart';
import '../utils/price_calculator.dart';
import '../utils/share_file_namer.dart';

part 'total/total_models.dart';
part 'total/total_draft.dart';
part 'total/total_storage.dart';
part 'total/total_pdf.dart';
part 'total/total_sticky_bar.dart';
part 'total/total_takeaway.dart';
part 'total/total_tts.dart';
part 'total/total_widgets.dart';

class TotalPage extends StatefulWidget {
  const TotalPage({super.key, required this.canFinishTransaction});

  final bool canFinishTransaction;

  @override
  State<TotalPage> createState() => _TotalPageState();
}

class _TotalPageState extends State<TotalPage> {
  static const String _upiQrBase =
      'upi://pay?mode=02&pa=Q596211014@ybl&purpose=00&mc=0000&pn=PhonePeMerchant&orgid=180001';
  static final PdfPageFormat _billPageFormat = PdfPageFormat.a4;
  static const List<_QrCenterBadgeStyle> _qrCenterBadgeOptions = [
    _QrCenterBadgeStyle(
      icon: Icons.cruelty_free,
      iconColor: Color(0xFF6D4C41),
      backgroundColor: Color(0xFFFBEFE7),
    ),
    _QrCenterBadgeStyle(
      icon: Icons.local_florist,
      iconColor: Color(0xFFD84315),
      backgroundColor: Color(0xFFFFEFE6),
    ),
    _QrCenterBadgeStyle(
      icon: Icons.filter_vintage,
      iconColor: Color(0xFFAD1457),
      backgroundColor: Color(0xFFFFE9F1),
    ),
    _QrCenterBadgeStyle(
      icon: Icons.eco,
      iconColor: Color(0xFF2E7D32),
      backgroundColor: Color(0xFFEAF8EC),
    ),
    _QrCenterBadgeStyle(
      icon: Icons.pets,
      iconColor: Color(0xFF5D4037),
      backgroundColor: Color(0xFFF7EEE8),
    ),
    _QrCenterBadgeStyle(
      icon: Icons.spa,
      iconColor: Color(0xFF00695C),
      backgroundColor: Color(0xFFE4F6F2),
    ),
    _QrCenterBadgeStyle(
      icon: Icons.park,
      iconColor: Color(0xFF2E7D32),
      backgroundColor: Color(0xFFEAF6EA),
    ),
  ];

  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _customerMobileController =
      TextEditingController();
  final TextEditingController _discountController = TextEditingController();
  final FocusNode _discountFocusNode = FocusNode();
  final List<_PaymentEntryDraft> _paymentEntries = <_PaymentEntryDraft>[];
  final FlutterTts _flutterTts = FlutterTts();
  Uint8List? _cachedShreeHeaderBytes;
  String? _activeInvoiceNo;
  bool _finishingTransaction = false;
  bool _printingBill = false;
  bool _sharingBill = false;
  _TakeawayMode? _activeTakeawayMode;
  late Future<_TotalsData> _totalsFuture;

  double _parseAmount(String value) {
    final cleaned = value.replaceAll(',', '').trim();
    return double.tryParse(cleaned) ?? 0.0;
  }

  double _normalizeMoneyDelta(double value) {
    // Treat tiny floating-point residues as settled.
    if (value.abs() < 0.005) {
      return 0.0;
    }
    return value;
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');

  String? get _customerMobileError =>
      TotalCustomerValidator.validateMobile(_customerMobileController.text);

  bool _validateCustomerDetails({bool showError = true}) {
    final error = TotalCustomerValidator.validate(
      customerName: _customerNameController.text,
      customerMobile: _customerMobileController.text,
    );
    if (error != null && showError && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
    return error == null;
  }

  String _formatIndianCurrency(String value) {
    final cleaned = value.replaceAll(',', '').trim();
    if (cleaned.isEmpty) {
      return '';
    }
    final hasDecimalPoint = cleaned.contains('.');
    final parts = cleaned.split('.');
    final intPartRaw = parts[0].replaceAll(RegExp(r'[^0-9]'), '');
    final decPart = parts.length > 1
        ? parts.sublist(1).join().replaceAll(RegExp(r'[^0-9]'), '')
        : '';
    if (intPartRaw.isEmpty && !hasDecimalPoint) {
      return '';
    }
    String formatInt(String intPart) {
      if (intPart.length <= 3) {
        return intPart;
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
      return '${buffer.toString()},$last3';
    }

    final formattedInt = formatInt(intPartRaw.isEmpty ? '0' : intPartRaw);
    if (hasDecimalPoint && decPart.isEmpty) {
      return '$formattedInt.';
    }
    if (decPart.isNotEmpty) {
      return '$formattedInt.$decPart';
    }
    return formattedInt;
  }

  String _buildUpiQr(double amount, String note) {
    final normalized = amount.toStringAsFixed(2);
    final encodedNote = Uri.encodeComponent(note);
    return '$_upiQrBase&am=$normalized&tn=$encodedNote&cu=INR';
  }

  String _formatDate(DateTime value) {
    return '${_twoDigits(value.day)}/${_twoDigits(value.month)}/${value.year}';
  }

  Future<void> _pickPaymentDate(int index) async {
    if (index < 0 || index >= _paymentEntries.length) {
      return;
    }
    final now = DateTime.now();
    final initial = _paymentEntries[index].date;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _paymentEntries[index].date = picked;
    });
    unawaited(_saveDraft());
  }

  void _addPaymentEntry() {
    setState(() {
      _paymentEntries.add(
        _PaymentEntryDraft(
          date: DateTime.now(),
          mode: _paymentEntries.isEmpty ? 'Cash' : 'UPI',
        ),
      );
    });
    unawaited(_saveDraft());
  }

  void _removePaymentEntry(int index) {
    if (index < 0 || index >= _paymentEntries.length) {
      return;
    }
    setState(() {
      final removed = _paymentEntries.removeAt(index);
      removed.dispose();
    });
    unawaited(_saveDraft());
  }

  void _clearPaymentEntries() {
    setState(() {
      for (final entry in _paymentEntries) {
        entry.dispose();
      }
      _paymentEntries
        ..clear()
        ..add(_PaymentEntryDraft(date: DateTime.now(), mode: 'Cash'));
      _discountController.clear();
    });
    unawaited(_saveDraft());
  }

  List<_PaymentEntryPdfRow> _buildPaymentEntryRowsForPdf() {
    final rows = <_PaymentEntryPdfRow>[];
    for (final entry in _paymentEntries) {
      final amount = _parseAmount(entry.amountController.text);
      if (amount <= 0) {
        continue;
      }
      rows.add(
        _PaymentEntryPdfRow(date: entry.date, mode: entry.mode, amount: amount),
      );
    }
    rows.sort((a, b) {
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
    return rows;
  }

  double _paymentTotalForModes(Set<String> modes) {
    return PaymentEntryCalculator.sumByModes(
      _paymentEntries.map(
        (entry) => PaymentEntryValue(
          mode: entry.mode,
          amount: _parseAmount(entry.amountController.text),
        ),
      ),
      modes,
    );
  }

  bool _isUpiOnlyMode(String mode) {
    return PaymentEntryCalculator.isUpiOnlyMode(mode);
  }

  bool _isNonCashMode(String mode) {
    return PaymentEntryCalculator.isNonCashMode(mode);
  }

  void _enforceUpiLimit(_PaymentEntryDraft entry) {
    if (!_isUpiOnlyMode(entry.mode)) {
      return;
    }
    final parsed = _parseAmount(entry.amountController.text);
    if (parsed <= 100000) {
      return;
    }
    const capped = '100000.00';
    entry.amountController.value = const TextEditingValue(
      text: capped,
      selection: TextSelection.collapsed(offset: capped.length),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('UPI amount cannot exceed 100000.00 per entry'),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _discountController.text = '';
    _paymentEntries.add(_PaymentEntryDraft(date: DateTime.now(), mode: 'Cash'));
    _totalsFuture = _loadTotals();
    SelectionNotifier.version.addListener(_onSelectionVersionChanged);
    unawaited(_loadDraft());
  }

  void _onSelectionVersionChanged() {
    if (!mounted) {
      return;
    }
    setState(() {
      _totalsFuture = _loadTotals();
    });
  }

  @override
  void dispose() {
    SelectionNotifier.version.removeListener(_onSelectionVersionChanged);
    unawaited(_flutterTts.stop());
    for (final entry in _paymentEntries) {
      entry.dispose();
    }
    _customerNameController.dispose();
    _customerMobileController.dispose();
    _discountController.dispose();
    _discountFocusNode.dispose();
    super.dispose();
  }

  String _buildSplitShareText(List<double> splits, [String note = '']) {
    final buffer = StringBuffer();
    buffer.writeln('Split Payment QR List');
    buffer.writeln('Total parts: ${splits.length}');
    if (note.isNotEmpty) {
      buffer.writeln('Items: $note');
    }
    for (int i = 0; i < splits.length; i++) {
      final amt = splits[i];
      buffer.writeln('QR ${i + 1}: ${PriceCalculator.formatIndianAmount(amt)}');
      buffer.writeln(_buildUpiQr(amt, note));
    }
    return buffer.toString().trim();
  }

  List<_QrCenterBadgeStyle> _buildRandomQrCenterStyles(int count) {
    if (count <= 0) {
      return const <_QrCenterBadgeStyle>[];
    }
    final random = math.Random();
    final pool = List<_QrCenterBadgeStyle>.from(_qrCenterBadgeOptions)
      ..shuffle(random);
    final styles = <_QrCenterBadgeStyle>[];
    while (styles.length < count) {
      final index = styles.length % pool.length;
      if (index == 0 && styles.isNotEmpty) {
        pool.shuffle(random);
      }
      styles.add(pool[index]);
    }
    return styles;
  }

  Future<Uint8List?> _buildQrPng(
    String data,
    int sizePx, {
    int borderPx = 0,
    required _QrCenterBadgeStyle badgeStyle,
  }) async {
    final totalSize = sizePx + (borderPx * 2);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, totalSize.toDouble(), totalSize.toDouble()),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, totalSize.toDouble(), totalSize.toDouble()),
      Paint()..color = Colors.white,
    );

    final qrPainter = QrPainter(
      data: data,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.H,
      gapless: true,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: Colors.black,
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: Colors.black,
      ),
    );
    final qrByteData = await qrPainter.toImageData(sizePx.toDouble());
    if (qrByteData == null) {
      return null;
    }

    final codec = await ui.instantiateImageCodec(
      qrByteData.buffer.asUint8List(),
    );
    final frame = await codec.getNextFrame();
    canvas.drawImage(
      frame.image,
      Offset(borderPx.toDouble(), borderPx.toDouble()),
      Paint(),
    );
    final badgeSize = sizePx * 0.13;
    final badgeCenter = Offset(
      borderPx + (sizePx / 2),
      borderPx + (sizePx / 2),
    );
    final badgeRect = Rect.fromCenter(
      center: badgeCenter,
      width: badgeSize,
      height: badgeSize,
    );
    final badgeRRect = RRect.fromRectAndRadius(
      badgeRect,
      Radius.circular(badgeSize * 0.22),
    );
    canvas.drawRRect(
      badgeRRect,
      Paint()
        ..color = badgeStyle.backgroundColor
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      badgeRRect,
      Paint()
        ..color = const Color(0xFFE5E7EB)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(badgeStyle.icon.codePoint),
        style: TextStyle(
          color: badgeStyle.iconColor,
          fontSize: badgeSize * 0.62,
          fontFamily: badgeStyle.icon.fontFamily,
          package: badgeStyle.icon.fontPackage,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    iconPainter.paint(
      canvas,
      Offset(
        badgeCenter.dx - (iconPainter.width / 2),
        badgeCenter.dy - (iconPainter.height / 2),
      ),
    );

    final image = await recorder.endRecording().toImage(totalSize, totalSize);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<Uint8List?> _buildShreeHeaderPng() async {
    const text = '\u0936\u094d\u0930\u0940';
    const horizontalPadding = 12.0;
    const verticalPadding = 4.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final painter = TextPainter(
      text: const TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.black,
          fontSize: 42,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    painter.layout();
    final width = (painter.width + (horizontalPadding * 2)).ceil();
    final height = (painter.height + (verticalPadding * 2)).ceil();
    painter.paint(canvas, const Offset(horizontalPadding, verticalPadding));
    final image = await recorder.endRecording().toImage(width, height);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<Uint8List?> _getShreeHeaderBytes() async {
    final cached = _cachedShreeHeaderBytes;
    if (cached != null) {
      return cached;
    }
    final built = await _buildShreeHeaderPng();
    _cachedShreeHeaderBytes = built;
    return built;
  }

  Future<void> _shareSplitQrImages(
    List<double> splits,
    String note, [
    List<_QrCenterBadgeStyle>? badgeStyles,
  ]) async {
    final effectiveStyles =
        badgeStyles ?? _buildRandomQrCenterStyles(splits.length);
    final files = <XFile>[];
    final fileNames = <String>[];
    final batch = ShareFileNamer.startBatch(prefix: 'pq', extension: 'png');
    for (int i = 0; i < splits.length; i++) {
      final amount = splits[i];
      final data = _buildUpiQr(amount, note);
      final bytes = await _buildQrPng(
        data,
        512,
        borderPx: 24,
        badgeStyle: effectiveStyles[i],
      );
      if (bytes == null) {
        continue;
      }
      final fileName = batch.nextName();
      files.add(XFile.fromData(bytes, name: fileName, mimeType: 'image/png'));
      fileNames.add(fileName);
    }

    if (files.isEmpty) {
      return;
    }

    final shareText = _buildSplitShareText(splits, note);
    await Share.shareXFiles(
      files,
      fileNameOverrides: fileNames,
      text: shareText,
    );
  }

  List<double> _splitAmounts(double amount) {
    final chunks = <double>[];
    double remaining = amount;
    while (remaining > 100000) {
      chunks.add(100000);
      remaining -= 100000;
    }
    if (remaining > 0) {
      chunks.add(double.parse(remaining.toStringAsFixed(2)));
    }
    return chunks;
  }

  void _showPaymentQr(double amount, String note) {
    showDialog<void>(
      context: context,
      builder: (context) {
        final splits = _splitAmounts(amount);
        final badgeStyles = _buildRandomQrCenterStyles(splits.length);
        final countdownEnd = DateTime.now().add(const Duration(minutes: 5));
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 18,
          ),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 430,
              maxHeight: MediaQuery.of(context).size.height * 0.88,
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFFF8EF),
                    Color(0xFFF9F3FF),
                    Color(0xFFEFFFFA),
                  ],
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 24,
                    offset: Offset(0, 12),
                  ),
                ],
                border: Border.all(color: Color(0xFFEBDCD3), width: 1.1),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: -18,
                    right: -10,
                    child: Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFF3E7D9).withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 24,
                    left: -16,
                    child: Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFCFEFE2).withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'QRTags Pay',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF5A3027),
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Scan to complete payment',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF6B4B42),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              children: splits.asMap().entries.map((entry) {
                                final badgeStyle = badgeStyles[entry.key];
                                final splitAmount = entry.value;
                                final showIdNote = splitAmount > 50000;
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 14),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.93),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: const Color(0xFFD9F0E6),
                                      width: 1.5,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x14000000),
                                        blurRadius: 10,
                                        offset: Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    children: [
                                      StreamBuilder<int>(
                                        stream: Stream.periodic(
                                          const Duration(seconds: 1),
                                          (_) => countdownEnd
                                              .difference(DateTime.now())
                                              .inSeconds,
                                        ),
                                        builder: (context, snapshot) {
                                          final remaining =
                                              (snapshot.data ?? 300).clamp(0, 300);
                                          final mins = remaining ~/ 60;
                                          final secs = remaining % 60;
                                          return Text(
                                            'Time left: ${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF0A8F5E),
                                            ),
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        PriceCalculator.formatIndianAmount(
                                          splitAmount,
                                        ),
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF243E35),
                                        ),
                                      ),
                                      if (showIdNote) ...[
                                        const SizedBox(height: 6),
                                        const Text(
                                          'Please share a valid government ID.\nYour info will be kept secure. Thank you!',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Colors.green,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 10),
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFDCF7ED),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Color(0x1A3FB89A),
                                              blurRadius: 9,
                                              offset: Offset(0, 5),
                                            ),
                                          ],
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            border: Border.all(
                                              color: const Color(0xFFECECEC),
                                              width: 1.2,
                                            ),
                                          ),
                                          child: SizedBox(
                                            width: 210,
                                            height: 210,
                                            child: Stack(
                                              alignment: Alignment.center,
                                              children: [
                                                QrImageView(
                                                  data: _buildUpiQr(
                                                    splitAmount,
                                                    note,
                                                  ),
                                                  size: 210,
                                                  backgroundColor: Colors.white,
                                                  errorCorrectionLevel:
                                                      QrErrorCorrectLevel.H,
                                                ),
                                                Container(
                                                  width: 66,
                                                  height: 66,
                                                  decoration: BoxDecoration(
                                                    color: badgeStyle
                                                        .backgroundColor,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                    border: Border.all(
                                                      color: const Color(
                                                        0xFFE5E7EB,
                                                      ),
                                                      width: 1.6,
                                                    ),
                                                  ),
                                                  child: Icon(
                                                    badgeStyle.icon,
                                                    color: badgeStyle.iconColor,
                                                    size: 40,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _shareSplitQrImages(
                                  splits,
                                  note,
                                  badgeStyles,
                                ),
                                icon: const Icon(Icons.share),
                                label: const Text('Share'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Close'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _finishTransaction(
    _TotalsData data,
    double cashReceived,
    double upiReceived,
    double discount,
  ) async {
    if (!widget.canFinishTransaction) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Only admins can finish transactions')),
        );
      }
      return;
    }
    if (_finishingTransaction) {
      return;
    }
    if (!_validateCustomerDetails()) {
      setState(() {});
      return;
    }
    final selectedRaw = List<String>.from(data.selectedRawSnapshot);
    if (selectedRaw.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No items to finish')));
      }
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }

    setState(() {
      _finishingTransaction = true;
    });

    final netPayable = data.selectedTotal - data.oldTotal - discount;
    final totalReceived = cashReceived + upiReceived;
    final due = _normalizeMoneyDelta(netPayable - totalReceived);
    final shouldContinue = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirm Finish Transaction'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Items: ${data.selectedCount}'),
              Text(
                'Net Payable: ${PriceCalculator.formatIndianAmount(netPayable)}',
              ),
              Text(
                'Received: ${PriceCalculator.formatIndianAmount(totalReceived)}',
              ),
              Text(
                '${due < 0 ? 'Refund' : 'Due'}: ${PriceCalculator.formatIndianAmount(due.abs())}',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Finish'),
            ),
          ],
        );
      },
    );
    if (shouldContinue != true) {
      if (mounted) {
        setState(() {
          _finishingTransaction = false;
        });
      }
      return;
    }

    try {
      final existingSales =
          prefs.getStringList(StorageKeys.salesItems) ?? <String>[];
      final existingSalesGst =
          prefs.getStringList(StorageKeys.salesItemsGst) ?? <String>[];
      final existingSalesIds =
          prefs.getStringList(StorageKeys.salesItemIds) ?? <String>[];
      final salesIds = existingSalesIds.toSet();

      final existingKeys = <String>{};
      for (final raw in existingSales) {
        final parsed = _tryParseJson(raw);
        final id = parsed?['id']?.toString();
        existingKeys.add(id ?? raw);
      }

      final updatedSales = List<String>.from(existingSales);
      final updatedSalesGst = List<String>.from(existingSalesGst);
      for (int i = 0; i < selectedRaw.length; i++) {
        final raw = selectedRaw[i];
        final parsed = _tryParseJson(raw);
        final id = parsed?['id']?.toString();
        final key = id ?? raw;
        if (existingKeys.add(key)) {
          updatedSales.add(raw);
          // updatedSalesGst.add(i < selectedGst.length ? selectedGst[i] : '1');
        }
        if (id != null && id.isNotEmpty) {
          salesIds.add(id);
        }
      }

      await prefs.setStringList(StorageKeys.salesItems, updatedSales);
      await prefs.setStringList(StorageKeys.salesItemsGst, updatedSalesGst);
      await prefs.setStringList(StorageKeys.salesItemIds, salesIds.toList());
      await _clearDraft();
      SalesNotifier.notify();
      if (mounted) {
        setState(() {
          _totalsFuture = _loadTotals();
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Transaction finished')));
      }
    } catch (error, stackTrace) {
      debugPrint('TotalPage: failed to finish transaction: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to finish transaction')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _finishingTransaction = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_TotalsData>(
      future: _totalsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data!;
        final paymentEntryCash = _paymentTotalForModes({'Cash'});
        final paymentEntryUpi = _paymentTotalForModes({'UPI', 'Banking'});
        final cashReceived = paymentEntryCash;
        final upiReceived = paymentEntryUpi;
        final l10n = AppLocalizations.of(context)!;
        final rawDiscount = _parseAmount(_discountController.text);
        final discount = data.discountEnabled ? rawDiscount : 0.0;
        final netPayable = data.selectedTotal - data.oldTotal - discount;
        final totalReceived = cashReceived + upiReceived;
        final diff = _normalizeMoneyDelta(netPayable - totalReceived);
        final isSettled = diff == 0.0;
        final dueLabel = diff < 0 ? l10n.refundAmount : l10n.dueAmount;
        final dueAmount = diff.abs();
        final dueText =
            '${diff < 0 ? '-' : ''}${PriceCalculator.formatIndianAmount(dueAmount)}';
        final dueColor = diff < 0
            ? Colors.red
            : (diff == 0 ? Colors.blueGrey : Colors.green);
        final canGenerateQr = diff > 0;
        final theme = Theme.of(context);

        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Customer Details',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _customerNameController,
                              decoration: const InputDecoration(
                                labelText: 'Customer Name (Optional)',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (value) {
                                setState(() {});
                                unawaited(_saveDraft());
                              },
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _customerMobileController,
                              keyboardType: TextInputType.phone,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(10),
                              ],
                              decoration: InputDecoration(
                                labelText: 'Mobile Number (Optional)',
                                border: const OutlineInputBorder(),
                                errorText: _customerMobileError,
                              ),
                              onChanged: (value) {
                                setState(() {});
                                unawaited(_saveDraft());
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Payment Entries',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _clearPaymentEntries,
                                  icon: const Icon(Icons.clear_all),
                                  label: const Text('Clear Entries'),
                                ),
                              ],
                            ),
                            Text(
                              'Add date, mode and amount for each payment.',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ..._paymentEntries.asMap().entries.map((entry) {
                              final index = entry.key;
                              final paymentEntry = entry.value;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outlineVariant,
                                    ),
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerLowest,
                                  ),
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final useStackedFields =
                                          constraints.maxWidth < 520;
                                      final dateField = InkWell(
                                        onTap: () => _pickPaymentDate(index),
                                        borderRadius: BorderRadius.circular(8),
                                        child: InputDecorator(
                                          decoration: const InputDecoration(
                                            labelText: 'Date',
                                          ),
                                          child: Text(
                                            _formatDate(paymentEntry.date),
                                          ),
                                        ),
                                      );
                                      final modeField =
                                          DropdownButtonFormField<String>(
                                            initialValue: paymentEntry.mode,
                                            decoration: const InputDecoration(
                                              labelText: 'Mode',
                                            ),
                                            items: const [
                                              DropdownMenuItem(
                                                value: 'Cash',
                                                child: Text('Cash'),
                                              ),
                                              DropdownMenuItem(
                                                value: 'UPI',
                                                child: Text('UPI'),
                                              ),
                                              DropdownMenuItem(
                                                value: 'Banking',
                                                child: Text('Banking'),
                                              ),
                                            ],
                                            onChanged: (value) {
                                              if (value == null) {
                                                return;
                                              }
                                              setState(() {
                                                paymentEntry.mode = value;
                                                _enforceUpiLimit(paymentEntry);
                                              });
                                              unawaited(_saveDraft());
                                            },
                                          );
                                      final amountField = Focus(
                                        onFocusChange: (hasFocus) {
                                          if (!hasFocus &&
                                              paymentEntry
                                                  .amountController
                                                  .text
                                                  .isNotEmpty) {
                                            final plainText = paymentEntry
                                                .amountController
                                                .text;
                                            final formatted =
                                                _formatIndianCurrency(
                                                  plainText,
                                                );
                                            if (formatted != plainText) {
                                              paymentEntry
                                                      .amountController
                                                      .text =
                                                  formatted;
                                            }
                                          } else if (hasFocus &&
                                              paymentEntry
                                                  .amountController
                                                  .text
                                                  .isNotEmpty) {
                                            final formattedText = paymentEntry
                                                .amountController
                                                .text;
                                            final plain = formattedText
                                                .replaceAll(',', '');
                                            if (plain != formattedText) {
                                              paymentEntry
                                                      .amountController
                                                      .text =
                                                  plain;
                                            }
                                          }
                                        },
                                        child: TextField(
                                          controller:
                                              paymentEntry.amountController,
                                          focusNode:
                                              paymentEntry.amountFocusNode,
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          decoration:
                                              const InputDecoration(
                                                labelText: 'Amount',
                                              ).copyWith(
                                                helperText:
                                                    paymentEntry.mode == 'UPI'
                                                    ? 'Max 100000.00'
                                                    : null,
                                              ),
                                          onChanged: (value) {
                                            _enforceUpiLimit(paymentEntry);
                                            setState(() {});
                                            unawaited(_saveDraft());
                                          },
                                        ),
                                      );

                                      return Column(
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                'Entry ${index + 1}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const Spacer(),
                                              IconButton(
                                                tooltip: 'Delete row',
                                                onPressed:
                                                    _paymentEntries.length == 1
                                                    ? null
                                                    : () => _removePaymentEntry(
                                                        index,
                                                      ),
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          if (useStackedFields) ...[
                                            dateField,
                                            const SizedBox(height: 8),
                                            modeField,
                                            const SizedBox(height: 8),
                                            amountField,
                                          ] else
                                            Row(
                                              children: [
                                                Expanded(child: dateField),
                                                const SizedBox(width: 8),
                                                Expanded(child: modeField),
                                                const SizedBox(width: 8),
                                                Expanded(child: amountField),
                                              ],
                                            ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              );
                            }),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: _addPaymentEntry,
                              icon: const Icon(Icons.add),
                              label: const Text('Add Entry'),
                            ),
                            const SizedBox(height: 4),
                            if (data.discountEnabled) ...[
                              Focus(
                                onFocusChange: (hasFocus) {
                                  if (!hasFocus &&
                                      _discountController.text.isNotEmpty) {
                                    final plainText = _discountController.text;
                                    final formatted = _formatIndianCurrency(
                                      plainText,
                                    );
                                    if (formatted != plainText) {
                                      _discountController.text = formatted;
                                    }
                                  } else if (hasFocus &&
                                      _discountController.text.isNotEmpty) {
                                    final formattedText =
                                        _discountController.text;
                                    final plain = formattedText.replaceAll(
                                      ',',
                                      '',
                                    );
                                    if (plain != formattedText) {
                                      _discountController.text = plain;
                                    }
                                  }
                                },
                                child: TextField(
                                  controller: _discountController,
                                  focusNode: _discountFocusNode,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    labelText: 'Discount',
                                  ),
                                  onChanged: (value) {
                                    setState(() {});
                                    unawaited(_saveDraft());
                                  },
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            Text(
                              'Selected Total: ${PriceCalculator.formatIndianAmount(data.selectedTotal)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Old Total: ${PriceCalculator.formatIndianAmount(data.oldTotal)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Net Payable: ${PriceCalculator.formatIndianAmount(netPayable)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                OutlinedButton(
                                  onPressed: () => unawaited(
                                    _speakDueAmount(diff: diff, hindi: false),
                                  ),
                                  child: const Text('EN'),
                                ),
                                const SizedBox(width: 6),
                                OutlinedButton(
                                  onPressed: () => unawaited(
                                    _speakDueAmount(diff: diff, hindi: true),
                                  ),
                                  child: Text(l10n.hindiShort),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Center(
                                    child: Text(
                                      isSettled
                                          ? l10n.transactionSettled
                                          : '$dueLabel: $dueText',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: dueColor,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (data.selectedItems.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                'Takeaway Optimizer (Budget = Received Amount)',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () {
                                        setState(() {
                                          _activeTakeawayMode =
                                              _TakeawayMode.maxItems;
                                        });
                                      },
                                      style: OutlinedButton.styleFrom(
                                        backgroundColor:
                                            _activeTakeawayMode ==
                                                _TakeawayMode.maxItems
                                            ? theme.colorScheme.primaryContainer
                                            : null,
                                      ),
                                      icon: const Icon(
                                        Icons.format_list_numbered,
                                      ),
                                      label: const Text('Max Items'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () {
                                        setState(() {
                                          _activeTakeawayMode =
                                              _TakeawayMode.maxWeight;
                                        });
                                      },
                                      style: OutlinedButton.styleFrom(
                                        backgroundColor:
                                            _activeTakeawayMode ==
                                                _TakeawayMode.maxWeight
                                            ? theme.colorScheme.primaryContainer
                                            : null,
                                      ),
                                      icon: const Icon(Icons.scale),
                                      label: const Text('Max Weight'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton(
                                    onPressed: _activeTakeawayMode == null
                                        ? null
                                        : () {
                                            setState(() {
                                              _activeTakeawayMode = null;
                                            });
                                          },
                                    child: const Text('Clear'),
                                  ),
                                ],
                              ),
                              _buildTakeawaySuggestionPanel(
                                items: data.selectedItems,
                                budget: totalReceived,
                                theme: theme,
                              ),
                            ],
                            const SizedBox(height: 12),
                            if (canGenerateQr)
                              OutlinedButton.icon(
                                onPressed: () => _showPaymentQr(
                                  diff,
                                  data.selectedCount.toString(),
                                ),
                                icon: const Icon(Icons.qr_code),
                                label: const Text('Generate Payment QR'),
                              ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (data.selectedItems.isNotEmpty) ...[
                      const Text(
                        'Selected Items',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._buildSelectedSections(context, data.selectedItems),
                    ],
                    const SizedBox(height: 12),
                    if (data.oldItems.isNotEmpty) ...[
                      const Text(
                        'Old Items',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Item',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              'Net Wt',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              'Amount',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ...data.oldItems.map((item) {
                        final isDark =
                            Theme.of(context).brightness == Brightness.dark;
                        final titleColor = isDark
                            ? Colors.white
                            : Colors.black87;
                        final amountColor = isDark
                            ? const Color(0xFFFF8A80)
                            : Colors.red.shade700;
                        final formulaBaseColor = isDark
                            ? Colors.white70
                            : Colors.black87;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.title,
                                        style: TextStyle(color: titleColor),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        item.netWeight.toStringAsFixed(3),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: titleColor),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        PriceCalculator.formatIndianAmount(
                                          item.amount,
                                        ),
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: amountColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                RichText(
                                  text: TextSpan(
                                    style: TextStyle(color: formulaBaseColor),
                                    children: [
                                      TextSpan(text: item.formulaPrefix),
                                      TextSpan(
                                        text: item.formulaRate,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: titleColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),
            _buildStickyTotalsBar(
              data: data,
              netPayable: netPayable,
              totalReceived: totalReceived,
              dueAmount: dueAmount,
              isRefund: diff < 0,
              dueColor: dueColor,
              cashReceived: cashReceived,
              upiReceived: upiReceived,
              discount: discount,
            ),
          ],
        );
      },
    );
  }
}
