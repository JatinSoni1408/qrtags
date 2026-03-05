import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsButton extends StatelessWidget {
  const SettingsButton({
    super.key,
    this.tooltip = 'Settings',
    this.color = Colors.black,
    this.padding = const EdgeInsets.only(right: 12),
  });

  static final ValueNotifier<int> ratesVersion = ValueNotifier<int>(0);

  static const String _rateGold24Key = 'rate_gold24';
  static const String _rateGold22Key = 'rate_gold22';
  static const String _rateGold18Key = 'rate_gold18';
  static const String _rateSilverKey = 'rate_silver';
  static const String _configCollection = 'app_config';
  static const String _ratesDocId = 'rates';
  static const String _updatedByUidKey = 'updatedByUid';
  static const String _updatedByEmailKey = 'updatedByEmail';

  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _ratesSyncSub;
  static String? _syncUserId;
  static bool _syncCanSeedRemote = false;

  final String tooltip;
  final Color color;
  final EdgeInsetsGeometry padding;

  static double _parseRate(String value) =>
      double.tryParse(value.replaceAll(',', '').trim()) ?? 0.0;

  static String _formatRateInput(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final isNegative = trimmed.startsWith('-');
    final unsigned = isNegative ? trimmed.substring(1) : trimmed;
    final hasDot = unsigned.contains('.');
    final parts = unsigned.split('.');
    final integerDigits = parts.first.replaceAll(RegExp(r'[^0-9]'), '');
    final decimalDigits = hasDot
        ? parts.skip(1).join('').replaceAll(RegExp(r'[^0-9]'), '')
        : '';
    final groupedInt = _groupIndianDigits(integerDigits);
    final sign = isNegative ? '-' : '';
    if (!hasDot) {
      return '$sign$groupedInt';
    }
    return '$sign$groupedInt.$decimalDigits';
  }

  static String _groupIndianDigits(String digits) {
    if (digits.isEmpty) {
      return '';
    }
    if (digits.length <= 3) {
      return digits;
    }
    final last3 = digits.substring(digits.length - 3);
    final rest = digits.substring(0, digits.length - 3);
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

  static double _toDouble(dynamic value, {double fallback = 0.0}) {
    if (value == null) {
      return fallback;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      final parsed = double.tryParse(value.trim());
      return parsed ?? fallback;
    }
    final parsed = double.tryParse(value.toString());
    return parsed ?? fallback;
  }

  static void startRatesSync({
    required String userId,
    required String userEmail,
    required bool canSeedRemote,
  }) {
    if (_syncUserId == userId &&
        _syncCanSeedRemote == canSeedRemote &&
        _ratesSyncSub != null) {
      return;
    }
    _syncUserId = userId;
    _syncCanSeedRemote = canSeedRemote;
    unawaited(
      _startRatesSyncInternal(
        userId: userId,
        userEmail: userEmail,
        canSeedRemote: canSeedRemote,
      ),
    );
  }

  static Future<void> _startRatesSyncInternal({
    required String userId,
    required String userEmail,
    required bool canSeedRemote,
  }) async {
    await _ratesSyncSub?.cancel();
    _ratesSyncSub = null;
    final prefs = await SharedPreferences.getInstance();
    final ratesRef = FirebaseFirestore.instance
        .collection(_configCollection)
        .doc(_ratesDocId);

    final initial = await ratesRef.get();
    if (!initial.exists && canSeedRemote) {
      await ratesRef.set({
        _rateGold24Key: prefs.getDouble(_rateGold24Key) ?? 0.0,
        _rateGold22Key: prefs.getDouble(_rateGold22Key) ?? 0.0,
        _rateGold18Key: prefs.getDouble(_rateGold18Key) ?? 0.0,
        _rateSilverKey: prefs.getDouble(_rateSilverKey) ?? 0.0,
        _updatedByUidKey: userId,
        _updatedByEmailKey: userEmail,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    _ratesSyncSub = ratesRef.snapshots().listen((snapshot) async {
      if (!snapshot.exists) {
        return;
      }
      final data = snapshot.data();
      if (data == null) {
        return;
      }
      final localPrefs = await SharedPreferences.getInstance();
      final current24 = localPrefs.getDouble(_rateGold24Key) ?? 0.0;
      final current22 = localPrefs.getDouble(_rateGold22Key) ?? 0.0;
      final current18 = localPrefs.getDouble(_rateGold18Key) ?? 0.0;
      final currentSilver = localPrefs.getDouble(_rateSilverKey) ?? 0.0;

      final next24 = _toDouble(data[_rateGold24Key], fallback: current24);
      final next22 = _toDouble(data[_rateGold22Key], fallback: current22);
      final next18 = _toDouble(data[_rateGold18Key], fallback: current18);
      final nextSilver = _toDouble(
        data[_rateSilverKey],
        fallback: currentSilver,
      );

      bool changed = false;
      if ((current24 - next24).abs() > 0.000001) {
        await localPrefs.setDouble(_rateGold24Key, next24);
        changed = true;
      }
      if ((current22 - next22).abs() > 0.000001) {
        await localPrefs.setDouble(_rateGold22Key, next22);
        changed = true;
      }
      if ((current18 - next18).abs() > 0.000001) {
        await localPrefs.setDouble(_rateGold18Key, next18);
        changed = true;
      }
      if ((currentSilver - nextSilver).abs() > 0.000001) {
        await localPrefs.setDouble(_rateSilverKey, nextSilver);
        changed = true;
      }
      if (changed) {
        ratesVersion.value++;
      }
    });
  }

  static Future<void> stopRatesSync() async {
    await _ratesSyncSub?.cancel();
    _ratesSyncSub = null;
    _syncUserId = null;
    _syncCanSeedRemote = false;
  }

  static String _formatIndian(double value) {
    final isNegative = value < 0;
    final absValue = value.abs();
    final raw = absValue.toStringAsFixed(2);
    final parts = raw.split('.');
    final intPart = parts[0];
    final decPart = parts.length > 1 ? parts[1] : '00';
    if (intPart.length <= 3) {
      return '${isNegative ? '-' : ''}$intPart.$decPart';
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
    return '${isNegative ? '-' : ''}${buffer.toString()},$last3.$decPart';
  }

  static Future<void> openRateSettings(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (!context.mounted) {
      return;
    }

    final controller24 = TextEditingController(
      text: _formatRateInput((prefs.getDouble(_rateGold24Key) ?? 0).toString()),
    );
    final controller22 = TextEditingController(
      text: _formatRateInput((prefs.getDouble(_rateGold22Key) ?? 0).toString()),
    );
    final controller18 = TextEditingController(
      text: _formatRateInput((prefs.getDouble(_rateGold18Key) ?? 0).toString()),
    );
    final controllerSilver = TextEditingController(
      text: _formatRateInput((prefs.getDouble(_rateSilverKey) ?? 0).toString()),
    );

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final rate22 = _parseRate(controller22.text);
            final rate18 = _parseRate(controller18.text);
            final return22 = rate22 - 300;
            final return18 = rate18 - 300;
            return AlertDialog(
              title: const Text('Gram Rates'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: controller24,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: const [_IndianRateInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Gold24kt rate',
                      ),
                      onChanged: (_) => setModalState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller22,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: const [_IndianRateInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Gold22kt rate',
                      ),
                      onChanged: (_) => setModalState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller18,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: const [_IndianRateInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Gold18kt rate',
                      ),
                      onChanged: (_) => setModalState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controllerSilver,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: const [_IndianRateInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Silver rate',
                      ),
                      onChanged: (_) => setModalState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _ReturnRateText(
                        text: 'Return Rate 22kt ${_formatIndian(return22)}',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _ReturnRateText(
                        text: 'Return Rate 18kt ${_formatIndian(return18)}',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final rate24 = _parseRate(controller24.text);
                    final rate22 = _parseRate(controller22.text);
                    final rate18 = _parseRate(controller18.text);
                    final rateSilver = _parseRate(controllerSilver.text);
                    await prefs.setDouble(_rateGold24Key, rate24);
                    await prefs.setDouble(_rateGold22Key, rate22);
                    await prefs.setDouble(_rateGold18Key, rate18);
                    await prefs.setDouble(_rateSilverKey, rateSilver);
                    final user = FirebaseAuth.instance.currentUser;
                    await FirebaseFirestore.instance
                        .collection(_configCollection)
                        .doc(_ratesDocId)
                        .set({
                          _rateGold24Key: rate24,
                          _rateGold22Key: rate22,
                          _rateGold18Key: rate18,
                          _rateSilverKey: rateSilver,
                          _updatedByUidKey: user?.uid ?? '',
                          _updatedByEmailKey: user?.email ?? '',
                          'updatedAt': FieldValue.serverTimestamp(),
                        }, SetOptions(merge: true));
                    ratesVersion.value++;
                    if (!context.mounted) {
                      return;
                    }
                    Navigator.of(context).pop();
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: IconButton(
        icon: const Icon(Icons.settings),
        iconSize: 21,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        color: color,
        tooltip: tooltip,
        onPressed: () => openRateSettings(context),
      ),
    );
  }
}

class _IndianRateInputFormatter extends TextInputFormatter {
  const _IndianRateInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = SettingsButton._formatRateInput(newValue.text);
    final selectionFromRight =
        newValue.text.length - newValue.selection.extentOffset;
    final nextOffset = formatted.length - selectionFromRight;
    final clampedOffset = nextOffset.clamp(0, formatted.length);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: clampedOffset),
    );
  }
}

class _ReturnRateText extends StatefulWidget {
  const _ReturnRateText({required this.text});

  final String text;

  @override
  State<_ReturnRateText> createState() => _ReturnRateTextState();
}

class _ReturnRateTextState extends State<_ReturnRateText>
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
        style: const TextStyle(
          color: Colors.red,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }
}
