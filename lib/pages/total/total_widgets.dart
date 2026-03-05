part of '../total_page.dart';

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
                textAlign: TextAlign.center,
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

class _VibrateText extends StatefulWidget {
  const _VibrateText(this.text);

  final String text;

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
        style: const TextStyle(
          color: Colors.red,
          fontWeight: FontWeight.bold,
          fontSize: 14,
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
