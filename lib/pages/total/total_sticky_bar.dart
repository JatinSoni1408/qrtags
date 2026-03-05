part of '../total_page.dart';

extension _TotalPageStickyBarExtension on _TotalPageState {
  Widget _buildStickyMetric({
    required String label,
    required String value,
    Color? valueColor,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: valueColor ?? theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildStickyTotalsBar({
    required _TotalsData data,
    required double netPayable,
    required double totalReceived,
    required double dueAmount,
    required bool isRefund,
    required Color dueColor,
    required double cashReceived,
    required double upiReceived,
    required double discount,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final dueLabel = isRefund ? l10n.refundAmount : l10n.dueAmount;
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildStickyMetric(
                    label: 'Net Payable',
                    value: PriceCalculator.formatIndianAmount(netPayable),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStickyMetric(
                    label: 'Received',
                    value: PriceCalculator.formatIndianAmount(totalReceived),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStickyMetric(
                    label: dueLabel,
                    value: PriceCalculator.formatIndianAmount(dueAmount),
                    valueColor: dueColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
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
          ],
        ),
      ),
    );
  }
}
