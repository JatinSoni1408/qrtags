part of '../total_page.dart';

extension _TotalPageTakeawayExtension on _TotalPageState {
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
}
