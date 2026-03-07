import 'package:flutter/material.dart';

class SharedItemFormLayout extends StatelessWidget {
  const SharedItemFormLayout({
    super.key,
    required this.primarySection,
    required this.makingSection,
    this.returnPuritySection,
    required this.lessSection,
    required this.weightSection,
    required this.additionalSection,
    this.footerSection,
  });

  final Widget primarySection;
  final Widget makingSection;
  final Widget? returnPuritySection;
  final Widget lessSection;
  final Widget weightSection;
  final Widget additionalSection;
  final Widget? footerSection;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        primarySection,
        const SizedBox(height: 16),
        makingSection,
        if (returnPuritySection != null) ...[
          const SizedBox(height: 16),
          returnPuritySection!,
        ],
        const SizedBox(height: 16),
        lessSection,
        const SizedBox(height: 12),
        weightSection,
        const SizedBox(height: 16),
        additionalSection,
        if (footerSection != null) ...[
          const SizedBox(height: 20),
          footerSection!,
        ],
      ],
    );
  }
}

class SharedFormSectionHeader extends StatelessWidget {
  const SharedFormSectionHeader({
    super.key,
    required this.title,
    required this.onAdd,
    this.addLabel = 'Add',
  });

  final String title;
  final VoidCallback onAdd;
  final String addLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: Text(addLabel),
        ),
      ],
    );
  }
}

class SharedFormEntryCard extends StatelessWidget {
  const SharedFormEntryCard({
    super.key,
    required this.title,
    required this.onDelete,
    required this.child,
    this.padding = const EdgeInsets.all(10),
  });

  final String title;
  final VoidCallback onDelete;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
