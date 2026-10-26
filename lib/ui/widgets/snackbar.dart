// ignore_for_file: constant_identifier_names

import 'package:flutter/material.dart';

enum SanckBarSize { BIG, MEDIUM, SMALL }

SnackBar snackbar(BuildContext context, String text,
    {SanckBarSize size = SanckBarSize.MEDIUM,
    Duration duration = const Duration(seconds: 1),
    bool top = false}) {
  final cs = Theme.of(context).colorScheme;
  final scrWidth = MediaQuery.of(context).size.width;
  final hrMargin = size == SanckBarSize.BIG
      ? (scrWidth - 300) / 2
      : size == SanckBarSize.MEDIUM
          ? (scrWidth - 200) / 2
          : (scrWidth - 100) / 2;
  return SnackBar(
    backgroundColor: Colors.transparent,
    content: Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withOpacity(0.08), width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
          ),
        ),
      ),
    ),
    margin: EdgeInsets.only(
        bottom: top ? MediaQuery.of(context).size.height * 0.8 : 100,
        left: hrMargin,
        right: hrMargin),
    behavior: SnackBarBehavior.floating,
    duration: duration,
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  );
}
