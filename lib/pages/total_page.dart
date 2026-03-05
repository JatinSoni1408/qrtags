import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../utils/sales_notifier.dart';
import '../features/total/payment_entry_calculator.dart';
import '../utils/price_calculator.dart';
import '../utils/share_file_namer.dart';

enum _TakeawayMode { maxItems, maxWeight }

class TotalPage extends StatefulWidget {
  const TotalPage({super.key});

  @override
  State<TotalPage> createState() => _TotalPageState();
}

class _TotalPageState extends State<TotalPage> {
  static const String _oldItemsKey = 'old_items';
  static const String _draftDiscountKey = 'total_draft_discount';
  static const String _draftPaymentEntriesKey = 'total_draft_payment_entries';
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

  final TextEditingController _discountController = TextEditingController();
  final List<_PaymentEntryDraft> _paymentEntries = <_PaymentEntryDraft>[];
  final FlutterTts _flutterTts = FlutterTts();
  Uint8List? _cachedShreeHeaderBytes;
  bool _finishingTransaction = false;
  _TakeawayMode? _activeTakeawayMode;
  bool _isSpeakingAmount = false;
  bool _amountSpeechMuted = false;

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

  String _formatIndianInput(String value) {
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
    });
    unawaited(_saveDraft());
  }

  Future<void> _saveDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encodedEntries = _paymentEntries.map((entry) {
        return jsonEncode({
          'date': entry.date.toIso8601String(),
          'mode': entry.mode,
          'amount': entry.amountController.text,
        });
      }).toList();
      await prefs.setString(_draftDiscountKey, _discountController.text);
      await prefs.setStringList(_draftPaymentEntriesKey, encodedEntries);
    } catch (_) {
      // ignore draft save errors
    }
  }

  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftDiscountKey);
      await prefs.remove(_draftPaymentEntriesKey);
    } catch (_) {
      // ignore
    }
  }

  Future<void> _loadDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final discount = prefs.getString(_draftDiscountKey) ?? '';
      final entryRaw = prefs.getStringList(_draftPaymentEntriesKey) ?? [];
      final loadedEntries = <_PaymentEntryDraft>[];
      for (final raw in entryRaw) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is! Map<String, dynamic>) {
            continue;
          }
          final parsedDate = DateTime.tryParse(
            decoded['date']?.toString() ?? '',
          );
          final mode = decoded['mode']?.toString().trim() ?? '';
          final amount = decoded['amount']?.toString() ?? '';
          if (parsedDate == null || mode.isEmpty) {
            continue;
          }
          loadedEntries.add(
            _PaymentEntryDraft(date: parsedDate, mode: mode, amount: amount),
          );
        } catch (_) {
          // ignore malformed row
        }
      }
      if (!mounted) {
        for (final entry in loadedEntries) {
          entry.dispose();
        }
        return;
      }
      setState(() {
        _discountController.text = discount;
        for (final entry in _paymentEntries) {
          entry.dispose();
        }
        _paymentEntries
          ..clear()
          ..addAll(
            loadedEntries.isEmpty
                ? <_PaymentEntryDraft>[
                    _PaymentEntryDraft(date: DateTime.now(), mode: 'Cash'),
                  ]
                : loadedEntries,
          );
      });
    } catch (_) {
      // ignore draft load errors
    }
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

  String _twoDigitWord(int value) {
    const underTwenty = <String>[
      'zero',
      'one',
      'two',
      'three',
      'four',
      'five',
      'six',
      'seven',
      'eight',
      'nine',
      'ten',
      'eleven',
      'twelve',
      'thirteen',
      'fourteen',
      'fifteen',
      'sixteen',
      'seventeen',
      'eighteen',
      'nineteen',
    ];
    const tens = <String>[
      '',
      '',
      'twenty',
      'thirty',
      'forty',
      'fifty',
      'sixty',
      'seventy',
      'eighty',
      'ninety',
    ];
    if (value < 20) {
      return underTwenty[value];
    }
    final ten = value ~/ 10;
    final unit = value % 10;
    if (unit == 0) {
      return tens[ten];
    }
    return '${tens[ten]} ${underTwenty[unit]}';
  }

  String _threeDigitWord(int value) {
    if (value <= 0) {
      return '';
    }
    final hundred = value ~/ 100;
    final rem = value % 100;
    if (hundred == 0) {
      return _twoDigitWord(rem);
    }
    if (rem == 0) {
      return '${_twoDigitWord(hundred)} hundred';
    }
    return '${_twoDigitWord(hundred)} hundred and ${_twoDigitWord(rem)}';
  }

  String _numberToIndianWords(int value) {
    if (value <= 0) {
      return 'zero';
    }
    final parts = <String>[];
    int remaining = value;

    final crore = remaining ~/ 10000000;
    remaining %= 10000000;
    if (crore > 0) {
      parts.add('${_threeDigitWord(crore)} crore');
    }

    final lakh = remaining ~/ 100000;
    remaining %= 100000;
    if (lakh > 0) {
      parts.add('${_threeDigitWord(lakh)} lakh');
    }

    final thousand = remaining ~/ 1000;
    remaining %= 1000;
    if (thousand > 0) {
      parts.add('${_threeDigitWord(thousand)} thousand');
    }

    if (remaining > 0) {
      parts.add(_threeDigitWord(remaining));
    }

    return parts.join(' ').trim();
  }

  Future<void> _speakDueAmount({
    required double diff,
    required bool hindi,
  }) async {
    final normalized = _normalizeMoneyDelta(diff);
    final wholeRupees = normalized.abs().floor();
    final amountText = wholeRupees.toString();
    final amountWordsEnglish = _numberToIndianWords(wholeRupees);
    final text = normalized == 0
        ? (hindi ? 'लेनदेन पूरा हो गया है।' : 'Transaction settled.')
        : normalized > 0
        ? (hindi
              ? 'बाकी राशि $amountText रुपये है।'
              : 'Due amount is $amountWordsEnglish.')
        : (hindi
              ? 'वापसी राशि $amountText रुपये है।'
              : 'Refund amount is $amountWordsEnglish.');
    try {
      await _flutterTts.stop();
      await _flutterTts.setVolume(1.0);
      if (mounted) {
        setState(() {
          _isSpeakingAmount = true;
          _amountSpeechMuted = false;
        });
      }
      await _flutterTts.setLanguage(hindi ? 'hi-IN' : 'en-IN');
      await _flutterTts.setSpeechRate(0.55);
      await _flutterTts.setPitch(1.0);
      await _flutterTts.speak(text);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to announce amount')),
      );
    } finally {
      try {
        await _flutterTts.setVolume(1.0);
      } catch (_) {
        // ignore
      }
      if (mounted) {
        setState(() {
          _isSpeakingAmount = false;
          _amountSpeechMuted = false;
        });
      }
    }
  }

  Future<void> _muteCurrentAmountSpeech() async {
    if (!_isSpeakingAmount) {
      return;
    }
    try {
      await _flutterTts.setVolume(0.0);
      if (!mounted) {
        return;
      }
      setState(() {
        _amountSpeechMuted = true;
      });
    } catch (_) {
      await _flutterTts.stop();
      if (!mounted) {
        return;
      }
      setState(() {
        _isSpeakingAmount = false;
        _amountSpeechMuted = false;
      });
    }
  }

  bool _isBetterTakeawayState(
    _KnapsackState candidate,
    _KnapsackState current,
    _TakeawayMode mode,
  ) {
    if (mode == _TakeawayMode.maxWeight) {
      if (candidate.weightMilliGrams != current.weightMilliGrams) {
        return candidate.weightMilliGrams > current.weightMilliGrams;
      }
      if (candidate.count != current.count) {
        return candidate.count > current.count;
      }
      return candidate.spentAmount < current.spentAmount;
    }
    if (candidate.count != current.count) {
      return candidate.count > current.count;
    }
    if (candidate.weightMilliGrams != current.weightMilliGrams) {
      return candidate.weightMilliGrams > current.weightMilliGrams;
    }
    return candidate.spentAmount < current.spentAmount;
  }

  _TakeawaySuggestion? _computeTakeawaySuggestion({
    required List<_SelectedItemView> items,
    required double budget,
    required _TakeawayMode mode,
  }) {
    if (budget <= 0 || items.isEmpty) {
      return null;
    }

    const maxBudgetUnits = 60000;
    final unit = math.max(1, (budget / maxBudgetUnits).ceil());
    final budgetUnits = (budget / unit).floor();
    if (budgetUnits <= 0) {
      return null;
    }

    final candidateItemIndexes = <int>[];
    final candidateCostUnits = <int>[];
    final candidateWeightsMilli = <int>[];
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final amount = item.amount;
      if (amount <= 0 || amount > budget + 0.0001) {
        continue;
      }
      final costUnits = (amount / unit).ceil();
      if (costUnits <= 0 || costUnits > budgetUnits) {
        continue;
      }
      candidateItemIndexes.add(i);
      candidateCostUnits.add(costUnits);
      candidateWeightsMilli.add((item.weightValue * 1000).round());
    }

    if (candidateItemIndexes.isEmpty) {
      return null;
    }

    final dp = List<_KnapsackState?>.filled(budgetUnits + 1, null);
    dp[0] = const _KnapsackState(
      count: 0,
      weightMilliGrams: 0,
      spentAmount: 0,
      itemIndex: null,
      previous: null,
    );

    for (int i = 0; i < candidateItemIndexes.length; i++) {
      final itemIndex = candidateItemIndexes[i];
      final item = items[itemIndex];
      final costUnits = candidateCostUnits[i];
      final weightMilli = candidateWeightsMilli[i];

      for (int spend = budgetUnits; spend >= costUnits; spend--) {
        final previous = dp[spend - costUnits];
        if (previous == null) {
          continue;
        }
        final candidateSpend = previous.spentAmount + item.amount;
        if (candidateSpend > budget + 0.0001) {
          continue;
        }
        final candidate = _KnapsackState(
          count: previous.count + 1,
          weightMilliGrams: previous.weightMilliGrams + weightMilli,
          spentAmount: candidateSpend,
          itemIndex: itemIndex,
          previous: previous,
        );
        final current = dp[spend];
        if (current == null || _isBetterTakeawayState(candidate, current, mode)) {
          dp[spend] = candidate;
        }
      }
    }

    _KnapsackState? best;
    for (final state in dp) {
      if (state == null || state.count == 0) {
        continue;
      }
      if (best == null || _isBetterTakeawayState(state, best, mode)) {
        best = state;
      }
    }
    if (best == null) {
      return null;
    }

    final selectedIndexes = <int>[];
    _KnapsackState? cursor = best;
    while (cursor != null && cursor.itemIndex != null) {
      selectedIndexes.add(cursor.itemIndex!);
      cursor = cursor.previous;
    }
    final selectedItems = selectedIndexes.reversed
        .map((index) => items[index])
        .toList();

    return _TakeawaySuggestion(
      mode: mode,
      budget: budget,
      selectedItems: selectedItems,
      totalAmount: best.spentAmount,
      totalWeight: best.weightMilliGrams / 1000.0,
      budgetUnit: unit,
    );
  }

  Widget _buildTakeawaySuggestionPanel({
    required List<_SelectedItemView> items,
    required double budget,
    required ThemeData theme,
  }) {
    if (_activeTakeawayMode == null) {
      return const SizedBox.shrink();
    }
    if (budget <= 0) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Enter payment amounts first to suggest takeaway items.',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    final suggestion = _computeTakeawaySuggestion(
      items: items,
      budget: budget,
      mode: _activeTakeawayMode!,
    );
    if (suggestion == null || suggestion.selectedItems.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'No scanned item fits within the received amount.',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              suggestion.mode == _TakeawayMode.maxItems
                  ? 'Suggested for Max Items'
                  : 'Suggested for Max Weight',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Items: ${suggestion.selectedItems.length} | '
              'Weight: ${suggestion.totalWeight.toStringAsFixed(3)} g | '
              'Amount: ${PriceCalculator.formatIndianAmount(suggestion.totalAmount)}',
            ),
            const SizedBox(height: 2),
            Text(
              'Leftover: ${PriceCalculator.formatIndianAmount(suggestion.leftover)}',
            ),
            if (suggestion.budgetUnit > 1)
              Text(
                'Optimizer step size: ₹${suggestion.budgetUnit}',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const Divider(height: 16),
            ...suggestion.selectedItems.map((item) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.category.isNotEmpty
                            ? '${item.title} (${item.category})'
                            : item.title,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${item.weightValue.toStringAsFixed(3)} g',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      PriceCalculator.formatIndianAmount(item.amount),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _discountController.text = '';
    _paymentEntries.add(_PaymentEntryDraft(date: DateTime.now(), mode: 'Cash'));
    unawaited(_flutterTts.awaitSpeakCompletion(true));
    unawaited(_loadDraft());
  }

  @override
  void dispose() {
    unawaited(_flutterTts.stop());
    for (final entry in _paymentEntries) {
      entry.dispose();
    }
    _discountController.dispose();
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
                                final index = entry.key + 1;
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
                                      Text(
                                        'QR $index',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF5A3027),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
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
                                        const _VibrateText(
                                          'Ask customer for ID',
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

  Future<_TotalsData> _loadTotals() async {
    final prefs = await SharedPreferences.getInstance();
    final selectedRaw = prefs.getStringList('selected_items') ?? <String>[];
    final selectedGst = prefs.getStringList('selected_items_gst') ?? <String>[];

    double parseNum(String v) {
      final cleaned = v.replaceAll(',', '').replaceAll('%', '').trim();
      return double.tryParse(cleaned) ?? 0.0;
    }

    List<Map<String, dynamic>> collectAdditionals(Map<String, dynamic> data) {
      final additionalTypes = (data['additionalTypes'] as List? ?? const []);
      final values = <Map<String, dynamic>>[];
      for (final item in additionalTypes) {
        if (item is Map) {
          final type = item['type']?.toString().trim() ?? '';
          final value = parseNum(item['value']?.toString() ?? '0');
          if (value != 0 && type.isNotEmpty) {
            values.add({'type': type, 'value': value});
          }
        }
      }
      return values;
    }

    double getBhav(String? category) {
      if (category == 'Gold22kt') {
        return prefs.getDouble('rate_gold22') ?? 0.0;
      }
      if (category == 'Gold18kt') {
        return prefs.getDouble('rate_gold18') ?? 0.0;
      }
      if (category == 'Silver') {
        return prefs.getDouble('rate_silver') ?? 0.0;
      }
      return 0.0;
    }

    double getReturnBhavValue(String? option) {
      if (option == 'Gold24kt') {
        return prefs.getDouble('rate_gold24') ?? 0.0;
      }
      if (option == 'Gold22kt') {
        return (prefs.getDouble('rate_gold22') ?? 0.0) - 300;
      }
      if (option == 'Gold18kt') {
        return (prefs.getDouble('rate_gold18') ?? 0.0) - 300;
      }
      if (option == 'Silver') {
        return prefs.getDouble('rate_silver') ?? 0.0;
      }
      return 0.0;
    }

    String formatReturnBhavText(String? option, double value) {
      return PriceCalculator.formatIndianAmount(value);
    }

    String selectedIdentity(String raw) {
      final parsed = _tryParseJson(raw);
      final id = parsed?['id']?.toString().trim() ?? '';
      if (id.isNotEmpty) {
        return 'id:$id';
      }
      return 'raw:${raw.trim()}';
    }

    final seen = <String>{};
    final uniqueSelected = <String>[];
    final uniqueGst = <String>[];
    for (int i = 0; i < selectedRaw.length; i++) {
      final raw = selectedRaw[i];
      final identity = selectedIdentity(raw);
      if (seen.add(identity)) {
        uniqueSelected.add(raw);
        uniqueGst.add(i < selectedGst.length ? selectedGst[i] : '1');
      }
    }

    final selectedItems = <_SelectedItemView>[];
    double selectedTotal = 0.0;
    double selectedGstTotal = 0.0;

    for (int i = 0; i < uniqueSelected.length; i++) {
      final raw = uniqueSelected[i];
      final parsed = _tryParseJson(raw);
      if (parsed == null) {
        continue;
      }
      final huidMandatory = _hasHuid(parsed);
      final gstEnabled = huidMandatory
          ? true
          : (i < uniqueGst.length ? uniqueGst[i] == '1' : true);
      final breakdown = await PriceCalculator.calculateBreakdown(
        parsed,
        gstEnabledOverride: gstEnabled,
      );
      final isManualEntry = parsed['entrySource']?.toString() == 'manual';
      final rawItemName = parsed['itemName']?.toString() ?? '';
      final itemName = rawItemName.isNotEmpty ? rawItemName : 'Item';
      final category = parsed['category']?.toString();
      final makingType = parsed['makingType']?.toString() ?? '';
      final grossWeightValue = parseNum(
        parsed['grossWeight']?.toString() ?? '0',
      );
      final lessWeightValue = parseNum(parsed['lessWeight']?.toString() ?? '0');
      final netWeightValue = parseNum(parsed['netWeight']?.toString() ?? '0');
      final netWeight = netWeightValue.toStringAsFixed(3);
      final makingCharge = parseNum(parsed['makingCharge']?.toString() ?? '0');
      final bhav = getBhav(category);
      final bhavText = PriceCalculator.formatIndianAmount(bhav);
      final additionalValues = collectAdditionals(parsed);
      final additionalTotal = additionalValues.fold<double>(
        0.0,
        (sum, v) => sum + (v['value'] as double),
      );
      final additionalBreakup = <String, double>{};
      for (final item in additionalValues) {
        final type = item['type'] as String;
        final value = item['value'] as double;
        additionalBreakup[type] = (additionalBreakup[type] ?? 0.0) + value;
      }
      final additionalText = additionalTotal > 0
          ? ' + ${PriceCalculator.formatIndianAmount(additionalTotal)}'
          : '';
      final gstText = gstEnabled && makingType != 'FixRate' ? ' + 3%' : '';
      String formula;
      String formulaExtras = '';
      if (makingType == 'Percentage') {
        formula =
            '$bhavText + ${makingCharge.toStringAsFixed(0)}% * '
            '$netWeight$gstText$additionalText';
      } else if (makingType == 'PerGram') {
        formula =
            '$bhavText + ${makingCharge.toStringAsFixed(2)} * '
            '$netWeight$gstText$additionalText';
      } else if (makingType == 'FixRate') {
        formula = '';
      } else if (makingType == 'TotalMaking') {
        formula =
            '$bhavText * $netWeight + '
            '${makingCharge.toStringAsFixed(2)}$gstText$additionalText';
      } else {
        formula = '$netWeight ${makingCharge.toStringAsFixed(2)}$gstText';
        formulaExtras = netWeight;
      }
      selectedTotal += breakdown.total;
      selectedGstTotal += breakdown.gst;
      selectedItems.add(
        _SelectedItemView(
          title: itemName,
          amount: breakdown.total,
          formula: formula,
          formulaExtras: formulaExtras,
          weightToken: netWeight,
          category: category ?? '',
          weightValue: netWeightValue,
          grossWeight: grossWeightValue,
          lessWeight: lessWeightValue,
          rate: bhav,
          makingType: makingType,
          makingCharge: makingCharge,
          baseAmount: breakdown.base,
          gstAmount: breakdown.gst,
          additionalAmount: breakdown.additional,
          additionalBreakup: additionalBreakup,
          gstDisplay: gstEnabled ? '3%' : '-',
          isManualEntry: isManualEntry,
        ),
      );
    }

    final oldRaw = prefs.getStringList(_oldItemsKey) ?? <String>[];
    final oldItems = <_OldItemView>[];
    double oldTotal = 0.0;
    for (final raw in oldRaw) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final name = decoded['itemName']?.toString() ?? 'Item';
          final amount = (decoded['amount'] as num?)?.toDouble() ?? 0.0;
          final grossWeightValue = parseNum(
            decoded['grossWeight']?.toString() ?? '0',
          );
          double lessWeightValue = parseNum(
            decoded['lessWeight']?.toString() ?? '0',
          );
          if (lessWeightValue == 0.0) {
            final lessEntries = decoded['lessEntries'];
            if (lessEntries is List) {
              double sum = 0.0;
              for (final entry in lessEntries) {
                if (entry is Map) {
                  sum += parseNum(entry['value']?.toString() ?? '0');
                }
              }
              lessWeightValue = sum;
            }
          }
          final netWeightValue = parseNum(
            decoded['netWeight']?.toString() ?? '0',
          );
          final netWeightText = netWeightValue.toStringAsFixed(3);
          final returnBhav = decoded['returnBhav']?.toString();
          final oldCategory = returnBhav ?? '';
          final returnBhavValue = getReturnBhavValue(returnBhav);
          final returnBhavText = formatReturnBhavText(
            returnBhav,
            returnBhavValue,
          );
          final tanchRaw = decoded['tanch']?.toString() ?? '';
          final hasTanch = tanchRaw.trim().isNotEmpty;
          final tanchValue = parseNum(tanchRaw);
          String formulaPrefix;
          String formulaRate = returnBhavText;
          switch (returnBhav) {
            case 'Silver':
              formulaPrefix =
                  '($netWeightText * ${tanchValue.toStringAsFixed(2)}) * ';
              break;
            case 'Gold22kt':
              formulaPrefix = '$netWeightText * ';
              break;
            case 'Gold18kt':
              formulaPrefix =
                  '($netWeightText * ${tanchValue.toStringAsFixed(2)}) * ';
              break;
            case 'Gold24kt':
              formulaPrefix =
                  '($netWeightText * ${tanchValue.toStringAsFixed(2)}) * ';
              break;
            default:
              if (hasTanch) {
                formulaPrefix =
                    '($netWeightText * ${tanchValue.toStringAsFixed(2)}) * ';
              } else {
                formulaPrefix = '$netWeightText * ';
              }
          }
          oldTotal += amount;
          oldItems.add(
            _OldItemView(
              title: name,
              amount: amount,
              grossWeight: grossWeightValue,
              lessWeight: lessWeightValue,
              netWeight: netWeightValue,
              category: oldCategory,
              formulaPrefix: formulaPrefix,
              formulaRate: formulaRate,
            ),
          );
        }
      } catch (_) {
        // ignore
      }
    }

    return _TotalsData(
      selectedItems: selectedItems,
      oldItems: oldItems,
      selectedRawSnapshot: uniqueSelected,
      selectedTotal: selectedTotal,
      selectedGstTotal: selectedGstTotal,
      oldTotal: oldTotal,
      selectedCount: selectedItems.length,
      discountEnabled: prefs.getBool('discount_enabled') ?? false,
    );
  }

  bool _hasHuid(Map<String, dynamic> data) {
    final v = data['huid']?.toString().trim() ?? '';
    return v.isNotEmpty;
  }

  Map<String, dynamic>? _tryParseJson(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // ignore
    }
    return null;
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
    final effectivePageFormat = pageFormat ?? _billPageFormat;
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
    final invoiceNo =
        'INV-${now.year}${_twoDigits(now.month)}${_twoDigits(now.day)}-${_twoDigits(now.hour)}${_twoDigits(now.minute)}${_twoDigits(now.second)}';
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

    doc.addPage(
      pw.Page(
        pageFormat: effectivePageFormat,
        margin: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 16),
        build: (context) {
          final contentWidth = effectivePageFormat.width - 20;
          final contentHeight = effectivePageFormat.height - 32;
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
            body: PdfPreview(
              useActions: true,
              allowPrinting: false,
              allowSharing: false,
              initialPageFormat: _billPageFormat,
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
                        format: _billPageFormat,
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
                    } catch (_) {
                      if (!actionContext.mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(actionContext).showSnackBar(
                        const SnackBar(content: Text('Failed to print bill')),
                      );
                    }
                  },
                ),
                PdfPreviewAction(
                  icon: const Icon(Icons.share),
                  onPressed: (actionContext, build, pageFormat) async {
                    try {
                      final bytes = await build(pageFormat);
                      final filename =
                          'Bill-${DateTime.now().millisecondsSinceEpoch}.pdf';
                      await Printing.sharePdf(bytes: bytes, filename: filename);
                    } catch (_) {
                      if (!actionContext.mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(actionContext).showSnackBar(
                        const SnackBar(content: Text('Failed to share bill')),
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
          );
        },
      ),
    );
  }

  Future<void> _finishTransaction(
    _TotalsData data,
    double cashReceived,
    double upiReceived,
    double discount,
  ) async {
    if (_finishingTransaction) {
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
      final existingSales = prefs.getStringList('sales_items') ?? <String>[];
      final existingSalesGst =
          prefs.getStringList('sales_items_gst') ?? <String>[];
      final existingSalesIds =
          prefs.getStringList('sales_item_ids') ?? <String>[];
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

      await prefs.setStringList('sales_items', updatedSales);
      await prefs.setStringList('sales_items_gst', updatedSalesGst);
      await prefs.setStringList('sales_item_ids', salesIds.toList());
      await _clearDraft();
      SalesNotifier.notify();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Transaction finished')));
      }
    } catch (_) {
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
    return StreamBuilder<int>(
      stream: Stream<int>.periodic(const Duration(seconds: 1), (v) => v),
      builder: (context, _) {
        return FutureBuilder<_TotalsData>(
          future: _loadTotals(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final data = snapshot.data!;
            final paymentEntryCash = _paymentTotalForModes({'Cash'});
            final paymentEntryUpi = _paymentTotalForModes({'UPI', 'Banking'});
            final cashReceived = paymentEntryCash;
            final upiReceived = paymentEntryUpi;
            final rawDiscount = _parseAmount(_discountController.text);
            final discount = data.discountEnabled ? rawDiscount : 0.0;
            final netPayable = data.selectedTotal - data.oldTotal - discount;
            final totalReceived = cashReceived + upiReceived;
            final diff = _normalizeMoneyDelta(netPayable - totalReceived);
            final isSettled = diff == 0.0;
            final dueLabel = diff < 0 ? 'Refund Amount' : 'Due Amount';
            final dueAmount = diff.abs();
            final dueText =
                '${diff < 0 ? '-' : ''}${PriceCalculator.formatIndianAmount(dueAmount)}';
            final dueColor = diff < 0
                ? Colors.red
                : (diff == 0 ? Colors.blueGrey : Colors.green);
            final canGenerateQr = diff > 0;
            final theme = Theme.of(context);

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
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
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Payment Entries',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
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
                                child: Column(
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
                                          onPressed: _paymentEntries.length == 1
                                              ? null
                                              : () =>
                                                    _removePaymentEntry(index),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: InkWell(
                                            onTap: () =>
                                                _pickPaymentDate(index),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            child: InputDecorator(
                                              decoration: const InputDecoration(
                                                labelText: 'Date',
                                              ),
                                              child: Text(
                                                _formatDate(paymentEntry.date),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child:
                                              DropdownButtonFormField<String>(
                                                initialValue: paymentEntry.mode,
                                                decoration:
                                                    const InputDecoration(
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
                                                    _enforceUpiLimit(
                                                      paymentEntry,
                                                    );
                                                  });
                                                  unawaited(_saveDraft());
                                                },
                                              ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: paymentEntry.amountController,
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
                                        final formatted = _formatIndianInput(
                                          value,
                                        );
                                        if (formatted != value) {
                                          paymentEntry
                                              .amountController
                                              .value = TextEditingValue(
                                            text: formatted,
                                            selection: TextSelection.collapsed(
                                              offset: formatted.length,
                                            ),
                                          );
                                        }
                                        _enforceUpiLimit(paymentEntry);
                                        setState(() {});
                                        unawaited(_saveDraft());
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _clearPaymentEntries,
                                  icon: const Icon(Icons.clear_all),
                                  label: const Text('Clear Entries'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _addPaymentEntry,
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add Entry'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          if (data.discountEnabled) ...[
                            TextField(
                              controller: _discountController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Discount',
                              ),
                              onChanged: (value) {
                                final formatted = _formatIndianInput(value);
                                if (formatted != value) {
                                  _discountController.value = TextEditingValue(
                                    text: formatted,
                                    selection: TextSelection.collapsed(
                                      offset: formatted.length,
                                    ),
                                  );
                                }
                                setState(() {});
                                unawaited(_saveDraft());
                              },
                            ),
                            const SizedBox(height: 8),
                          ],
                          Text(
                            'Selected Total: ${PriceCalculator.formatIndianAmount(data.selectedTotal)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Old Total: ${PriceCalculator.formatIndianAmount(data.oldTotal)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Net Payable: ${PriceCalculator.formatIndianAmount(netPayable)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Center(
                                  child: isSettled
                                      ? Text(
                                          'Transaction Settled',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: dueColor,
                                            fontSize: 22,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        )
                                      : _VibrateText(
                                          '$dueLabel: $dueText',
                                          color: dueColor,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                          textAlign: TextAlign.center,
                                        ),
                                ),
                              ),
                              const SizedBox(width: 8),
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
                                child: const Text('हिं'),
                              ),
                              const SizedBox(width: 6),
                              OutlinedButton.icon(
                                onPressed: _isSpeakingAmount
                                    ? () => unawaited(_muteCurrentAmountSpeech())
                                    : null,
                                icon: Icon(
                                  _amountSpeechMuted
                                      ? Icons.volume_off
                                      : Icons.volume_mute,
                                ),
                                label: Text(
                                  _amountSpeechMuted ? 'Muted' : 'Mute',
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
                                    icon: const Icon(Icons.format_list_numbered),
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
                          ElevatedButton.icon(
                            onPressed: _finishingTransaction
                                ? null
                                : () => _finishTransaction(
                                    data,
                                    cashReceived,
                                    upiReceived,
                                    discount,
                                  ),
                            icon: _finishingTransaction
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.check_circle),
                            label: const Text('Finish Transaction'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () => _previewTotalsPdf(
                              data,
                              cashReceived,
                              upiReceived,
                              discount,
                            ),
                            icon: const Icon(Icons.visibility),
                            label: const Text('Preview Bill'),
                          ),
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
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'Amount',
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ...data.oldItems.map((item) {
                      final isDark =
                          Theme.of(context).brightness == Brightness.dark;
                      final titleColor = isDark ? Colors.white : Colors.black87;
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
            );
          },
        );
      },
    );
  }
}

class _TakeawaySuggestion {
  const _TakeawaySuggestion({
    required this.mode,
    required this.budget,
    required this.selectedItems,
    required this.totalAmount,
    required this.totalWeight,
    required this.budgetUnit,
  });

  final _TakeawayMode mode;
  final double budget;
  final List<_SelectedItemView> selectedItems;
  final double totalAmount;
  final double totalWeight;
  final int budgetUnit;

  double get leftover => math.max(0, budget - totalAmount);
}

class _KnapsackState {
  const _KnapsackState({
    required this.count,
    required this.weightMilliGrams,
    required this.spentAmount,
    required this.itemIndex,
    required this.previous,
  });

  final int count;
  final int weightMilliGrams;
  final double spentAmount;
  final int? itemIndex;
  final _KnapsackState? previous;
}

class _TotalsData {
  _TotalsData({
    required this.selectedItems,
    required this.oldItems,
    required this.selectedRawSnapshot,
    required this.selectedTotal,
    required this.selectedGstTotal,
    required this.oldTotal,
    required this.selectedCount,
    required this.discountEnabled,
  });

  final List<_SelectedItemView> selectedItems;
  final List<_OldItemView> oldItems;
  final List<String> selectedRawSnapshot;
  final double selectedTotal;
  final double selectedGstTotal;
  final double oldTotal;
  final int selectedCount;
  final bool discountEnabled;
}

class _PaymentEntryDraft {
  _PaymentEntryDraft({
    required this.date,
    required this.mode,
    String amount = '',
  }) : amountController = TextEditingController(text: amount);

  DateTime date;
  String mode;
  final TextEditingController amountController;

  void dispose() {
    amountController.dispose();
  }
}

class _PaymentEntryPdfRow {
  const _PaymentEntryPdfRow({
    required this.date,
    required this.mode,
    required this.amount,
  });

  final DateTime date;
  final String mode;
  final double amount;
}

List<Widget> _buildSelectedSections(
  BuildContext context,
  List<_SelectedItemView> items,
) {
  List<_SelectedItemView> filterBy(String category) {
    if (category == 'Other') {
      return items
          .where(
            (i) =>
                i.category != 'Gold22kt' &&
                i.category != 'Gold18kt' &&
                i.category != 'Silver',
          )
          .toList();
    }
    return items.where((i) => i.category == category).toList();
  }

  List<Widget> section(String category, List<_SelectedItemView> list) {
    if (list.isEmpty) {
      return [];
    }
    list.sort((a, b) => b.weightValue.compareTo(a.weightValue));
    final palette = _totalItemColors(context, category);
    return [
      Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: palette.headingBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${_totalSectionLabel(category)} Items',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: palette.headingText,
                ),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      ...list.map(
        (item) => Card(
          margin: const EdgeInsets.only(bottom: 10),
          color: palette.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: palette.borderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.category.isNotEmpty
                            ? '${item.title} (${item.category})'
                            : item.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: palette.contentText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      PriceCalculator.formatIndianAmount(item.amount),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: palette.amountText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (item.formula.isNotEmpty)
                  _FormulaText(
                    formula: item.formula,
                    formulaExtras: item.formulaExtras,
                    weightToken: item.weightToken,
                  ),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  return [
    ...section('Gold22kt', filterBy('Gold22kt')),
    ...section('Gold18kt', filterBy('Gold18kt')),
    ...section('Silver', filterBy('Silver')),
    ...section('Other', filterBy('Other')),
  ];
}

String _totalSectionLabel(String category) {
  switch (category) {
    case 'Gold22kt':
      return 'Gold 22kt';
    case 'Gold18kt':
      return 'Gold 18kt';
    default:
      return category;
  }
}

_TotalItemPalette _totalItemColors(BuildContext context, String category) {
  final colorScheme = Theme.of(context).colorScheme;
  final isDark = colorScheme.brightness == Brightness.dark;
  if (category == 'Gold22kt') {
    return isDark
        ? const _TotalItemPalette(
            cardBg: Color(0xFF3A3217),
            headingBg: Color(0xFFE7CF7A),
            headingText: Color(0xFF2E2400),
            amountText: Color(0xFFFFE8A1),
            contentText: Color(0xFFF6EDCC),
            borderColor: Color(0xFFE7CB68),
          )
        : const _TotalItemPalette(
            cardBg: Color(0xFFF0F0DB),
            headingBg: Color(0xFFFFE39B),
            headingText: Color(0xFF5B4300),
            amountText: Color(0xFF8C6400),
            contentText: Color(0xFF322400),
            borderColor: Color(0xFFB38F00),
          );
  }
  if (category == 'Gold18kt') {
    return isDark
        ? const _TotalItemPalette(
            cardBg: Color(0xFF3A301A),
            headingBg: Color(0xFFFFD79A),
            headingText: Color(0xFF4A2B00),
            amountText: Color(0xFFFFE0B3),
            contentText: Color(0xFFF8E6C7),
            borderColor: Color(0xFFD6B777),
          )
        : const _TotalItemPalette(
            cardBg: Color(0xFFE1D9BC),
            headingBg: Color(0xFFFFD6A0),
            headingText: Color(0xFF6A3F00),
            amountText: Color(0xFF955500),
            contentText: Color(0xFF3B2A00),
            borderColor: Color(0xFF9E8130),
          );
  }
  if (category == 'Silver') {
    return isDark
        ? const _TotalItemPalette(
            cardBg: Color(0xFF2F343B),
            headingBg: Color(0xFF8AB2D9),
            headingText: Color(0xFF102738),
            amountText: Color(0xFFCDE3F8),
            contentText: Color(0xFFE2E7EE),
            borderColor: Color(0xFFB8C0CB),
          )
        : const _TotalItemPalette(
            cardBg: Color(0xFFE1E2E4),
            headingBg: Color(0xFFC3D8EE),
            headingText: Color(0xFF1A3C5A),
            amountText: Color(0xFF2A5B86),
            contentText: Color(0xFF1C2530),
            borderColor: Color(0xFF8C8C8C),
          );
  }
  return _TotalItemPalette(
    cardBg: isDark
        ? colorScheme.surfaceContainerHigh
        : colorScheme.surfaceContainerHighest,
    headingBg: isDark
        ? colorScheme.secondaryContainer
        : colorScheme.tertiaryContainer,
    headingText: isDark
        ? colorScheme.onSecondaryContainer
        : colorScheme.onTertiaryContainer,
    amountText: isDark ? colorScheme.primary : colorScheme.primary,
    contentText: isDark ? colorScheme.onSurface : colorScheme.onSurface,
    borderColor: isDark ? colorScheme.outline : colorScheme.primary,
  );
}

class _TotalItemPalette {
  const _TotalItemPalette({
    required this.cardBg,
    required this.headingBg,
    required this.headingText,
    required this.amountText,
    required this.contentText,
    required this.borderColor,
  });

  final Color cardBg;
  final Color headingBg;
  final Color headingText;
  final Color amountText;
  final Color contentText;
  final Color borderColor;
}

class _SelectedItemView {
  _SelectedItemView({
    required this.title,
    required this.amount,
    required this.formula,
    required this.formulaExtras,
    required this.weightToken,
    required this.category,
    required this.weightValue,
    required this.grossWeight,
    required this.lessWeight,
    required this.rate,
    required this.makingType,
    required this.makingCharge,
    required this.baseAmount,
    required this.gstAmount,
    required this.additionalAmount,
    required this.additionalBreakup,
    required this.gstDisplay,
    required this.isManualEntry,
  });

  final String title;
  final double amount;
  final String formula;
  final String formulaExtras;
  final String? weightToken;
  final String category;
  final double weightValue;
  final double grossWeight;
  final double lessWeight;
  final double rate;
  final String makingType;
  final double makingCharge;
  final double baseAmount;
  final double gstAmount;
  final double additionalAmount;
  final Map<String, double> additionalBreakup;
  final String gstDisplay;
  final bool isManualEntry;

  String get formulaDisplay {
    final text = formula.trim();
    return text.isEmpty ? '-' : text;
  }

  String get categoryDisplay {
    final text = category.trim();
    return text.isEmpty ? '-' : text;
  }
}

class _OldItemView {
  _OldItemView({
    required this.title,
    required this.amount,
    required this.grossWeight,
    required this.lessWeight,
    required this.netWeight,
    required this.category,
    required this.formulaPrefix,
    required this.formulaRate,
  });

  final String title;
  final double amount;
  final double grossWeight;
  final double lessWeight;
  final double netWeight;
  final String category;
  final String formulaPrefix;
  final String formulaRate;

  String get categoryDisplay {
    final text = category.trim();
    return text.isEmpty ? '-' : text;
  }

  String get formulaText => '$formulaPrefix$formulaRate';
}

class _QrCenterBadgeStyle {
  const _QrCenterBadgeStyle({
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
  });

  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
}

class _VibrateText extends StatefulWidget {
  const _VibrateText(
    this.text, {
    this.color = Colors.red,
    this.fontSize = 14,
    this.fontWeight = FontWeight.bold,
    this.textAlign = TextAlign.start,
  });

  final String text;
  final Color color;
  final double fontSize;
  final FontWeight fontWeight;
  final TextAlign textAlign;

  @override
  State<_VibrateText> createState() => _VibrateTextState();
}

class _VibrateTextState extends State<_VibrateText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    )..repeat(reverse: true);
    _offset = Tween<double>(
      begin: -1.5,
      end: 1.5,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _offset,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_offset.value, 0),
          child: child,
        );
      },
      child: Text(
        widget.text,
        textAlign: widget.textAlign,
        style: TextStyle(
          color: widget.color,
          fontWeight: widget.fontWeight,
          fontSize: widget.fontSize,
        ),
      ),
    );
  }
}

class _FormulaText extends StatelessWidget {
  const _FormulaText({
    required this.formula,
    required this.formulaExtras,
    required this.weightToken,
  });

  final String formula;
  final String formulaExtras;
  final String? weightToken;

  @override
  Widget build(BuildContext context) {
    final token = weightToken ?? '';
    if (token.isNotEmpty && !formula.contains(token)) {
      return RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(text: formula),
            TextSpan(
              text: ' $token',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }
    if (token.isEmpty) {
      return RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [TextSpan(text: formula)],
        ),
      );
    }

    final start = formula.indexOf(token);
    if (start == -1) {
      return RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [TextSpan(text: formula)],
        ),
      );
    }

    final before = formula.substring(0, start);
    final after = formula.substring(start + token.length);

    return RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: [
          TextSpan(text: before),
          TextSpan(
            text: token,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: after),
        ],
      ),
    );
  }
}

