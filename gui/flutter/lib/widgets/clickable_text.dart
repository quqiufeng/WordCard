import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 可点词文本：把英文段落切成普通文本 + 单词 TextSpan，
/// 点击单词回调 [onWordTap]（用于查词/加入任务）。
class ClickableText extends StatefulWidget {
  const ClickableText(
    this.text, {
    super.key,
    this.style,
    required this.onWordTap,
    this.textAlign = TextAlign.start,
  });

  final String text;
  final TextStyle? style;
  final void Function(String word) onWordTap;
  final TextAlign textAlign;

  @override
  State<ClickableText> createState() => _ClickableTextState();
}

class _ClickableTextState extends State<ClickableText> {
  static final _wordRe = RegExp(r"[A-Za-z][A-Za-z'’\-]*");

  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final spans = <InlineSpan>[];
    final text = widget.text;
    var last = 0;
    for (final m in _wordRe.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      final word = m.group(0)!;
      final rec = TapGestureRecognizer()..onTap = () => widget.onWordTap(word);
      _recognizers.add(rec);
      spans.add(TextSpan(
        text: word,
        recognizer: rec,
        mouseCursor: SystemMouseCursors.click,
      ));
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }
    return Text.rich(
      TextSpan(style: widget.style, children: spans),
      textAlign: widget.textAlign,
    );
  }
}
