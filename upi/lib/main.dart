import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const UpiApp());
}

class UpiApp extends StatelessWidget {
  const UpiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'upi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0C5DFF)),
      ),
      home: const UpiHomePage(),
    );
  }
}

class UpiHomePage extends StatefulWidget {
  const UpiHomePage({super.key});

  @override
  State<UpiHomePage> createState() => _UpiHomePageState();
}

class _UpiHomePageState extends State<UpiHomePage> {
  static const String _upiQrBase =
      'upi://pay?mode=02&pa=Q596211014@ybl&purpose=00&mc=0000&pn=PhonePeMerchant&orgid=180001';

  static const List<_CenterBadgeStyle> _badgeOptions = [
    _CenterBadgeStyle(
      icon: Icons.local_florist,
      iconColor: Color(0xFFAD1457),
      backgroundColor: Color(0xFFFFEDF6),
    ),
    _CenterBadgeStyle(
      icon: Icons.eco,
      iconColor: Color(0xFF2E7D32),
      backgroundColor: Color(0xFFEAF8EC),
    ),
    _CenterBadgeStyle(
      icon: Icons.spa,
      iconColor: Color(0xFF00695C),
      backgroundColor: Color(0xFFE4F6F2),
    ),
    _CenterBadgeStyle(
      icon: Icons.park,
      iconColor: Color(0xFF2E7D32),
      backgroundColor: Color(0xFFEAF6EA),
    ),
    _CenterBadgeStyle(
      icon: Icons.pets,
      iconColor: Color(0xFF6D4C41),
      backgroundColor: Color(0xFFFBEFE7),
    ),
    _CenterBadgeStyle(
      icon: Icons.cruelty_free,
      iconColor: Color(0xFF5D4037),
      backgroundColor: Color(0xFFF7EEE8),
    ),
  ];

  final TextEditingController _amountController = TextEditingController();
  bool _sharing = false;

  List<double> _generatedSplits = const <double>[];
  List<_CenterBadgeStyle> _generatedStyles = const <_CenterBadgeStyle>[];

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  String _buildUpiQr(double amount) {
    final normalized = amount.toStringAsFixed(2);
    return '$_upiQrBase&am=$normalized&cu=INR';
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

  List<_CenterBadgeStyle> _buildRandomStyles(int count) {
    if (count <= 0) {
      return const <_CenterBadgeStyle>[];
    }
    final random = math.Random();
    final pool = List<_CenterBadgeStyle>.from(_badgeOptions)..shuffle(random);
    final styles = <_CenterBadgeStyle>[];
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
    _CenterBadgeStyle badgeStyle,
    int sizePx, {
    int borderPx = 0,
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
        ..strokeWidth = 1.4,
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

  Future<void> _shareQrs() async {
    if (_generatedSplits.isEmpty || _generatedStyles.length != _generatedSplits.length) {
      return;
    }
    setState(() {
      _sharing = true;
    });
    try {
      final files = <XFile>[];
      final buffer = StringBuffer();
      buffer.writeln('UPI QR List');
      buffer.writeln('Total parts: ${_generatedSplits.length}');
      for (int i = 0; i < _generatedSplits.length; i++) {
        final amount = _generatedSplits[i];
        final data = _buildUpiQr(amount);
        final bytes = await _buildQrPng(
          data,
          _generatedStyles[i],
          512,
          borderPx: 24,
        );
        if (bytes != null) {
          files.add(
            XFile.fromData(
              bytes,
              name: 'upi_qr_${i + 1}.png',
              mimeType: 'image/png',
            ),
          );
        }
        buffer.writeln('QR ${i + 1}: ${amount.toStringAsFixed(2)}');
        buffer.writeln(data);
      }
      if (files.isNotEmpty) {
        await Share.shareXFiles(files, text: buffer.toString().trim());
      }
    } finally {
      if (mounted) {
        setState(() {
          _sharing = false;
        });
      }
    }
  }

  void _applyAmount(double amount) {
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount')),
      );
      return;
    }
    final splits = _splitAmounts(amount);
    setState(() {
      _amountController.text = amount.toString();
      _generatedSplits = splits;
      _generatedStyles = _buildRandomStyles(splits.length);
    });
  }

  Future<void> _openAmountSettings() async {
    final settingsAmountController = TextEditingController(
      text: _amountController.text.trim(),
    );
    final enteredValue = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Settings',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: settingsAmountController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixIcon: Icon(Icons.currency_rupee),
                ),
                onSubmitted: (value) => Navigator.pop(context, value.trim()),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () =>
                    Navigator.pop(context, settingsAmountController.text.trim()),
                icon: const Icon(Icons.check),
                label: const Text('Save and Back'),
              ),
            ],
          ),
        );
      },
    );
    settingsAmountController.dispose();

    if (enteredValue == null) {
      return;
    }

    if (!mounted) {
      return;
    }

    final amount = double.tryParse(enteredValue);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid float amount in settings')),
      );
      return;
    }
    _applyAmount(amount);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: GestureDetector(
          onLongPress: _openAmountSettings,
          child: IconButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Long press settings to enter amount'),
                ),
              );
            },
            icon: const Icon(Icons.settings),
            tooltip: 'Long press for settings',
          ),
        ),
        actions: [
          if (_generatedSplits.isNotEmpty)
            IconButton(
              onPressed: _sharing ? null : _shareQrs,
              icon: _sharing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.share),
              tooltip: 'Share all QRs',
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _generatedSplits.isEmpty
              ? const Center(
                  child: Text(
                    'Long press the settings button to enter amount',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  itemCount: _generatedSplits.length,
                  itemBuilder: (context, index) {
                    final splitAmount = _generatedSplits[index];
                    final badgeStyle = _generatedStyles[index];
                    final showIdNote = splitAmount > 50000;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Text(
                              'QR ${index + 1} - ${splitAmount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            if (showIdNote)
                              const Padding(
                                padding: EdgeInsets.only(top: 4),
                                child: Text(
                                  'Ask customer for ID',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: 220,
                              height: 220,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  QrImageView(
                                    data: _buildUpiQr(splitAmount),
                                    size: 220,
                                    backgroundColor: Colors.white,
                                    errorCorrectionLevel: QrErrorCorrectLevel.H,
                                  ),
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      color: badgeStyle.backgroundColor,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFFE5E7EB),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Icon(
                                      badgeStyle.icon,
                                      color: badgeStyle.iconColor,
                                      size: 38,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _CenterBadgeStyle {
  const _CenterBadgeStyle({
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
  });

  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
}
