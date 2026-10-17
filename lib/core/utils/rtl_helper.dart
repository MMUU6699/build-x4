import 'package:flutter/widgets.dart';

final RegExp _rtlCharRegex = RegExp(
  r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]',
);

/// Returns true if the text is predominantly RTL or starts with an RTL letter.
bool isRtlText(String text) {
  final trimmed = text.trimLeft();
  if (trimmed.isEmpty) return false;
  for (final rune in trimmed.runes) {
    final char = String.fromCharCode(rune);
    if (RegExp(r'[\p{L}]', unicode: true).hasMatch(char)) {
      return _rtlCharRegex.hasMatch(char);
    }
  }
  return _rtlCharRegex.hasMatch(trimmed);
}

TextDirection resolveTextDirection(
  String text, {
  TextDirection fallback = TextDirection.ltr,
}) {
  if (text.trim().isEmpty) return fallback;
  return isRtlText(text) ? TextDirection.rtl : TextDirection.ltr;
}
