import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/storage_keys.dart';
import '../widgets/settings_button.dart';

class BhavPage extends StatefulWidget {
  const BhavPage({super.key});

  @override
  State<BhavPage> createState() => _BhavPageState();
}

class _BhavPageState extends State<BhavPage>
    with SingleTickerProviderStateMixin {
  late final VoidCallback _ratesListener;
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  double _rateGold24 = 0.0;
  double _rateGold22 = 0.0;
  double _rateGold18 = 0.0;
  double _rateSilver = 0.0;
  DateTime? _rateUpdatedAt;
  AnimationController? _returnRateController;
  Animation<double>? _returnRateOffset;

  @override
  void initState() {
    super.initState();
    _ratesListener = _loadRates;
    SettingsButton.ratesVersion.addListener(_ratesListener);
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _now = DateTime.now();
      });
    });
    _loadRates();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _returnRateController?.dispose();
    SettingsButton.ratesVersion.removeListener(_ratesListener);
    super.dispose();
  }

  void _ensureReturnRateAnimation() {
    if (_returnRateController != null) {
      return;
    }
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    )..repeat(reverse: true);
    _returnRateController = controller;
    _returnRateOffset = Tween<double>(begin: -2.0, end: 2.0).animate(
      CurvedAnimation(parent: controller, curve: Curves.easeInOut),
    );
  }

  Future<void> _loadRates() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }
    final updatedAtMillis = prefs.getInt(StorageKeys.rateUpdatedAt);
    setState(() {
      _rateGold24 = prefs.getDouble(StorageKeys.rateGold24) ?? 0.0;
      _rateGold22 = prefs.getDouble(StorageKeys.rateGold22) ?? 0.0;
      _rateGold18 = prefs.getDouble(StorageKeys.rateGold18) ?? 0.0;
      _rateSilver = prefs.getDouble(StorageKeys.rateSilver) ?? 0.0;
      _rateUpdatedAt = updatedAtMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(updatedAtMillis);
    });
  }

  String _formatIndian(double value, {int decimals = 2}) {
    final isNegative = value < 0;
    final absValue = value.abs();
    final fixed = absValue.toStringAsFixed(decimals);
    final parts = fixed.split('.');
    final intPart = parts[0];
    final decPart = parts.length > 1 ? parts[1] : null;
    if (intPart.length <= 3) {
      if (decimals == 0 || decPart == null) {
        return '${isNegative ? '-' : ''}$intPart';
      }
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
    if (decimals == 0 || decPart == null) {
      return '${isNegative ? '-' : ''}${buffer.toString()},$last3';
    }
    return '${isNegative ? '-' : ''}${buffer.toString()},$last3.$decPart';
  }

  Widget _rateRow({
    required BuildContext context,
    required String label,
    required String value,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$value / Gram',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _returnRateRow({
    required String label,
    required String value,
  }) {
    _ensureReturnRateAnimation();
    return AnimatedBuilder(
      animation: _returnRateOffset ?? const AlwaysStoppedAnimation<double>(0),
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(
            (_returnRateOffset?.value ?? 0),
            0,
          ),
          child: child,
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.red,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$value / Gram',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sarafaHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(6),
      child: Image.asset(
        'assets/images/Sarafa Traders Committee.jpg',
        fit: BoxFit.contain,
      ),
    );
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');

  String _formatClock(DateTime value) {
    final date =
        '${_twoDigits(value.day)}/${_twoDigits(value.month)}/${value.year}';
    final time =
        '${_twoDigits(value.hour)}:${_twoDigits(value.minute)}:${_twoDigits(value.second)}';
    return '$date  $time';
  }

  String _formatUpdatedAt(DateTime? value) {
    if (value == null) {
      return 'Auto Updated: Not available';
    }
    return 'Auto Updated: ${_formatClock(value)}';
  }

  @override
  Widget build(BuildContext context) {
    final return22 = _rateGold22 - 300;
    final return18 = _rateGold18 - 300;
    final colorScheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: Colors.white,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: constraints.maxWidth - 24,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sarafaHeader(),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatClock(_now),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatUpdatedAt(_rateUpdatedAt),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    _rateRow(
                      context: context,
                      label: 'Gold24kt Rate (Approx)',
                      value: _formatIndian(_rateGold24, decimals: 0),
                    ),
                    const SizedBox(height: 6),
                    _rateRow(
                      context: context,
                      label: 'Gold22kt Rate',
                      value: _formatIndian(_rateGold22, decimals: 0),
                    ),
                    const SizedBox(height: 6),
                    _rateRow(
                      context: context,
                      label: 'Gold18kt Rate',
                      value: _formatIndian(_rateGold18, decimals: 0),
                    ),
                    const SizedBox(height: 6),
                    _rateRow(
                      context: context,
                      label: 'Silver Rate (Approx)',
                      value: _formatIndian(_rateSilver),
                    ),
                    const SizedBox(height: 6),
                    _returnRateRow(
                      label: 'Return Rate 22kt',
                      value: _formatIndian(return22, decimals: 0),
                    ),
                    const SizedBox(height: 6),
                    _returnRateRow(
                      label: 'Return Rate 18kt',
                      value: _formatIndian(return18, decimals: 0),
                    ),
                    const SizedBox(height: 12),
                    const Center(
                      child: Text(
                        'आपका दिन मंगलमय हो',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 5.76,
                          height: 5.76,
                          decoration: const BoxDecoration(
                            color: Colors.blueGrey,
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(
                          width: 300,
                          child: const Divider(height: 1, thickness: 2.0, color: Colors.blueGrey),
                        ),
                        Container(
                          width: 5.76,
                          height: 5.76,
                          decoration: const BoxDecoration(
                            color: Colors.blueGrey,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
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
}
