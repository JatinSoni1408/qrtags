import 'package:flutter/material.dart';

class ManualItemDialogBody extends StatelessWidget {
  const ManualItemDialogBody({
    super.key,
    required this.loading,
    required this.usingFallbackMasterData,
    required this.child,
  });

  final bool loading;
  final bool usingFallbackMasterData;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: MediaQuery.of(context).size.width > 900
          ? 820
          : MediaQuery.of(context).size.width * 0.92,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.78,
        ),
        child: loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            : Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (usingFallbackMasterData)
                        Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7E3),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE6C16A)),
                          ),
                          child: const Text(
                            'Using fallback master data. Sync may be unavailable.',
                            style: TextStyle(
                              color: Color(0xFF7A5A16),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      child,
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
