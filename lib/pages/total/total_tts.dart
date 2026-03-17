part of '../total_page.dart';

extension _TotalPageTtsExtension on _TotalPageState {
  Future<void> _setPreferredLanguage(List<String> languageCodes) async {
    for (final code in languageCodes) {
      final result = await _flutterTts.setLanguage(code);
      if (result is int) {
        if (result == 1) {
          return;
        }
        continue;
      }
      // Some platforms do not return numeric status but still succeed.
      return;
    }
  }

  String _buildHindiTtsText({
    required double normalized,
    required String amountText,
  }) {
    if (normalized == 0) {
      return 'लेनदेन पूरा हो गया है।';
    }
    if (normalized > 0) {
      return 'बाकी राशि $amountText रुपये है।';
    }
    return 'वापसी राशि $amountText रुपये है।';
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
    final l10n = AppLocalizations.of(context)!;
    final normalized = _normalizeMoneyDelta(diff);
    final wholeRupees = normalized.abs().floor();
    final amountText = wholeRupees.toString();
    final amountWordsEnglish = _numberToIndianWords(wholeRupees);
    final text = hindi
        ? _buildHindiTtsText(normalized: normalized, amountText: amountText)
        : normalized == 0
        ? l10n.ttsTransactionSettled
        : normalized > 0
        ? l10n.ttsDueAmountIs(amountWordsEnglish)
        : l10n.ttsRefundAmountIs(amountWordsEnglish);
    try {
      await _flutterTts.stop();
      await _setPreferredLanguage(
        hindi ? const ['hi-IN', 'hi'] : const ['en-IN', 'en-US', 'en'],
      );
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setPitch(1.0);
      await _flutterTts.speak(text);
    } catch (error, stackTrace) {
      debugPrint('TotalPage: failed to announce due amount: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.unableAnnounceAmount)));
    }
  }
}
