import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../state/study_session.dart';
import '../theme/app_theme.dart';
import '../theme/fonts.dart';

/// 闪卡：正面单词，背面释义 + 段落/例句 + 用法。
///
/// 排版遵循 Kami 规范：暖米纸感底、单一油墨蓝强调、衬线（霞鹜文楷）、
/// 大量留白、细线分隔、无渐变与阴影。
class FlashCard extends StatelessWidget {
  const FlashCard({
    super.key,
    required this.card,
    required this.flipped,
    required this.onFlip,
    this.onSpeak,
    this.loading = false,
    this.speaking,
  });

  final ActiveCard card;
  final bool flipped;
  final VoidCallback onFlip;
  final void Function(String text)? onSpeak;
  final bool loading;
  final ValueListenable<String?>? speaking;

  @override
  Widget build(BuildContext context) {
    final panel = AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: _panel(context),
    );
    if (flipped) return panel;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onFlip, child: panel),
    );
  }

  Widget _panel(BuildContext context) {
    return Container(
      key: ValueKey(flipped),
      constraints: const BoxConstraints(minHeight: 240),
      decoration: BoxDecoration(
        color: Kami.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Kami.hairline),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 36),
      child: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: flipped ? _back(context) : _front(context),
          ),
        ),
      ),
    );
  }

  TextStyle _serif(double size, FontWeight w, Color c) => TextStyle(
      fontFamily: AppFonts.tsangerJinKai,
      fontSize: size,
      fontWeight: w,
      color: c,
      height: 1.6);

  Widget _front(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          card.modeName,
          style: theme.textTheme.labelSmall?.copyWith(
            color: Kami.muted,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 28),
        Text(
          card.question,
          textAlign: TextAlign.center,
          style: _serif(46, FontWeight.w500, Kami.ink),
        ),
        if (card.hint.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            card.hint,
            textAlign: TextAlign.center,
            style: _serif(16, FontWeight.w400, Kami.muted),
          ),
        ],
        const SizedBox(height: 40),
        Text('点击卡片查看释义',
            style: theme.textTheme.labelSmall?.copyWith(color: Kami.faint)),
      ],
    );
  }

  Widget _back(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          card.question,
          textAlign: TextAlign.center,
          style: _serif(26, FontWeight.w500, Kami.inkBlue),
        ),
        const SizedBox(height: 14),
        Text(
          card.answer,
          textAlign: TextAlign.center,
          style: _serif(24, FontWeight.w500, Kami.ink),
        ),
        if (card.explanation.isNotEmpty) ...[
          const SizedBox(height: 28),
          const Divider(color: Kami.hairline, height: 1),
          const SizedBox(height: 20),
          ..._explanationLines(theme),
        ],
      ],
    );
  }

  List<Widget> _explanationLines(ThemeData theme) {
    final cjk = RegExp(r'[\u4e00-\u9fff]');
    final latin = RegExp(r'[A-Za-z]');
    bool isEn(String s) => latin.hasMatch(s) && !cjk.hasMatch(s);
    final lines = card.explanation
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final hasMarkers = card.explanation.contains('【段落】') ||
        card.explanation.contains('【例句】');
    final out = <Widget>[];

    if (!hasMarkers) {
      final buf = <String>[];
      void flush() {
        if (buf.isEmpty) return;
        out.add(_paragraph(theme, buf.join(' ')));
        buf.clear();
      }

      for (final line in lines) {
        if (line.startsWith('【用法】')) {
          flush();
          out.add(_usage(theme, line.substring('【用法】'.length).trim()));
        } else if (onSpeak != null && isEn(line)) {
          buf.add(line);
        } else {
          flush();
          out.add(_zhLine(theme, line));
        }
      }
      flush();
      if (loading) out.add(_loadingRow(theme));
      return out;
    }

    var seenPara = false;
    for (final line in lines) {
      if (line.startsWith('【用法】')) {
        out.add(_usage(theme, line.substring('【用法】'.length).trim()));
      } else if (line.startsWith('【段落】')) {
        seenPara = true;
        out.add(_paragraph(theme, line.substring('【段落】'.length).trim()));
      } else if (line.startsWith('【例句】')) {
        out.add(Padding(
          padding: const EdgeInsets.only(top: 22, bottom: 6),
          child: Text('例句',
              style: theme.textTheme.labelSmall?.copyWith(
                color: Kami.faint,
                letterSpacing: 3,
              )),
        ));
      } else if (isEn(line) && onSpeak != null) {
        if (!seenPara) {
          seenPara = true;
          out.add(_paragraph(theme, line));
        } else {
          out.add(_sentence(theme, line));
        }
      } else {
        out.add(_zhLine(theme, line));
      }
    }
    if (loading) out.add(_loadingRow(theme));
    return out;
  }

  /// 段落：段首一个朗读图标；目标词以油墨蓝强调。
  Widget _paragraph(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _speakButton(text),
          const SizedBox(width: 6),
          Expanded(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onSpeak == null ? null : () => onSpeak!(text),
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: RichText(text: _enSpan(text)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 例句：直接点读，无图标。
  Widget _sentence(ThemeData theme, String text) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onSpeak == null ? null : () => onSpeak!(text),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: RichText(text: _enSpan(text)),
        ),
      ),
    );
  }

  Widget _zhLine(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: RichText(text: _zhSpan(text)),
    );
  }

  Widget _usage(ThemeData theme, String text) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: const BoxDecoration(
        color: Kami.tint,
        border: Border(left: BorderSide(color: Kami.inkBlue, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('用法  ',
              style: theme.textTheme.labelSmall?.copyWith(
                color: Kami.inkBlue,
                letterSpacing: 2,
              )),
          Expanded(
            child: Text(
              text,
              style: _serif(15, FontWeight.w400, Kami.ink),
            ),
          ),
        ],
      ),
    );
  }

  Widget _speakButton(String text) {
    final button = IconButton(
      tooltip: '朗读整段',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      icon: const Icon(Icons.volume_up, size: 18, color: Kami.inkBlue),
      onPressed: onSpeak == null ? null : () => onSpeak!(text),
    );
    final speaking = this.speaking;
    if (speaking == null) return button;
    return ValueListenableBuilder<String?>(
      valueListenable: speaking,
      builder: (_, playing, __) => playing == text
          ? const SizedBox(
              width: 30,
              height: 30,
              child: Padding(
                padding: EdgeInsets.all(7),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : button,
    );
  }

  Widget _loadingRow(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text('翻译中…',
              style: theme.textTheme.bodySmall?.copyWith(color: Kami.muted)),
        ],
      ),
    );
  }

  /// 英文文本：目标词（含简单变形）用油墨蓝强调。
  TextSpan _enSpan(String text) {
    const base = TextStyle(
        fontFamily: AppFonts.tsangerJinKai, fontSize: 17, color: Kami.ink,
        height: 1.8);
    final word = card.question.trim();
    if (word.isEmpty) return TextSpan(text: text, style: base);
    final re =
        RegExp(r'\b' + RegExp.escape(word) + r'\w*', caseSensitive: false);
    final children = <TextSpan>[];
    var last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) {
        children.add(TextSpan(text: text.substring(last, m.start)));
      }
      children.add(TextSpan(
        text: m.group(0),
        style: const TextStyle(
            color: Kami.inkBlue, fontWeight: FontWeight.w500),
      ));
      last = m.end;
    }
    if (last < text.length) {
      children.add(TextSpan(text: text.substring(last)));
    }
    return TextSpan(style: base, children: children);
  }

  /// 中文文本：释义词命中处用油墨蓝强调。
  TextSpan _zhSpan(String text) {
    const base = TextStyle(
        fontFamily: AppFonts.tsangerJinKai, fontSize: 15, color: Kami.muted,
        height: 1.7);
    text = text.replaceAll('【', '').replaceAll('】', '');
    final terms = _glossTerms();
    if (terms.isEmpty) return TextSpan(text: text, style: base);
    final re = RegExp(terms.map(RegExp.escape).join('|'));
    final children = <TextSpan>[];
    var last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) {
        children.add(TextSpan(text: text.substring(last, m.start)));
      }
      children.add(TextSpan(
        text: m.group(0),
        style: const TextStyle(color: Kami.inkBlue, fontWeight: FontWeight.w500),
      ));
      last = m.end;
    }
    if (last < text.length) {
      children.add(TextSpan(text: text.substring(last)));
    }
    return TextSpan(style: base, children: children);
  }

  List<String> _glossTerms() {
    final a = card.answer
        .replaceAll(RegExp(r'[A-Za-z\.\[\]\(\)]'), ' ')
        .replaceAll('【', ' ')
        .replaceAll('】', ' ');
    final terms = <String>[];
    for (final t in a.split(RegExp(r'[,，;；、/\s]+'))) {
      final s = t.trim();
      if (s.length >= 2 && !terms.contains(s)) terms.add(s);
    }
    terms.sort((x, y) => y.length.compareTo(x.length));
    return terms;
  }
}
