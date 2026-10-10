import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../state/study_session.dart';
import '../theme/app_theme.dart';

/// 闪卡：正面显示单词/问题，背面显示释义与解析。
///
/// 点击卡片任意处翻转；不硬编码尺寸，随窗口自适应。
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

  /// 点击英文段落/例句时回调（朗读）。
  final void Function(String text)? onSpeak;

  /// 是否正在生成翻译/助记（显示等待动画）。
  final bool loading;

  /// 正在朗读的文本（合成期间段落按钮显示等待动画）。
  final ValueListenable<String?>? speaking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final panel = AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: _panel(context, theme),
    );
    // 仅在正面绑定「点击翻转」；背面保留朗读图标/例句的可点击性。
    if (flipped) return panel;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onFlip, child: panel),
    );
  }

  Widget _panel(BuildContext context, ThemeData theme) {
    return DecoratedBox(
      key: ValueKey(flipped),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [ChinaColors.nenjulv, ChinaColors.cardBottom],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ChinaColors.qiuxiang, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 220),
          child: Center(
            child: SingleChildScrollView(
              child: flipped
                  ? _back(context, theme)
                  : _front(context, theme),
            ),
          ),
        ),
      ),
    );
  }

  Widget _front(BuildContext context, ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _modeBadge(theme),
        const SizedBox(height: 20),
        Text(
          card.question,
          textAlign: TextAlign.center,
          style: theme.textTheme.displaySmall?.copyWith(
            color: ChinaColors.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (card.hint.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            card.hint,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: ChinaColors.muted,
            ),
          ),
        ],
        const SizedBox(height: 24),
        Text(
          '点击卡片查看释义',
          style: theme.textTheme.bodySmall?.copyWith(color: ChinaColors.dim),
        ),
      ],
    );
  }

  Widget _back(BuildContext context, ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          card.question,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            color: ChinaColors.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          card.answer,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: ChinaColors.daiLan,
          ),
        ),
        if (card.explanation.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Divider(color: ChinaColors.border),
          const SizedBox(height: 8),
          ..._explanationLines(theme),
        ],
      ],
    );
  }

  /// 把 explanation 按行拆开：
  /// 【用法】高亮；【段落】整段一个朗读图标；例句行直接点读（无图标）；中文行作对照。
  /// 无标记（旧卡片）时，把连续的英文行合并为一段朗读。
  List<Widget> _explanationLines(ThemeData theme) {
    final cjk = RegExp(r'[\u4e00-\u9fff]');
    final latin = RegExp(r'[A-Za-z]');
    final lines = card.explanation
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    bool isEn(String s) => latin.hasMatch(s) && !cjk.hasMatch(s);
    final hasMarkers = card.explanation.contains('【段落】') ||
        card.explanation.contains('【例句】');
    final out = <Widget>[];

    if (!hasMarkers) {
      final buf = <String>[];
      void flush() {
        if (buf.isEmpty) return;
        out.add(_speakBlock(theme, buf.join(' ')));
        buf.clear();
      }

      for (final line in lines) {
        if (line.startsWith('【用法】')) {
          flush();
          out.add(_usageBox(theme, line.substring('【用法】'.length).trim()));
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
        out.add(_usageBox(theme, line.substring('【用法】'.length).trim()));
      } else if (line.startsWith('【段落】')) {
        seenPara = true;
        out.add(_speakBlock(theme, line.substring('【段落】'.length).trim()));
      } else if (line.startsWith('【例句】')) {
        out.add(Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 2),
          child: Text('例句',
              style: theme.textTheme.labelSmall?.copyWith(
                color: ChinaColors.dim,
                letterSpacing: 1,
              )),
        ));
      } else if (isEn(line) && onSpeak != null) {
        if (!seenPara) {
          seenPara = true;
          out.add(_speakBlock(theme, line));
        } else {
          out.add(_speakLine(theme, line));
        }
      } else {
        out.add(_zhLine(theme, line));
      }
    }
    if (loading) out.add(_loadingRow(theme));
    return out;
  }

  /// 翻译/助记生成中的等待动画。
  Widget _loadingRow(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text('翻译中…',
              style: theme.textTheme.bodySmall?.copyWith(
                color: ChinaColors.muted,
              )),
        ],
      ),
    );
  }

  Widget _usageBox(ThemeData theme, String text) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ChinaColors.shuangdi,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ChinaColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_outline,
              size: 16, color: ChinaColors.daiLan),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ChinaColors.daiLan,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 段落：整段一个朗读图标（点图标或整段文字都朗读整段）。
  Widget _speakBlock(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _speakButton(theme, text),
          const SizedBox(width: 2),
          Expanded(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onSpeak == null ? null : () => onSpeak!(text),
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    text,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: ChinaColors.ink,
                      height: 1.6,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 例句：直接点读，不带图标。
  Widget _speakLine(ThemeData theme, String text) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onSpeak!(text),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            text,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: ChinaColors.ink,
              height: 1.6,
            ),
          ),
        ),
      ),
    );
  }

  /// 段落朗读按钮：音频合成期间显示等待动画。
  Widget _speakButton(ThemeData theme, String text) {
    final button = IconButton(
      tooltip: '朗读整段',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      icon: const Icon(Icons.volume_up, size: 18, color: ChinaColors.daiLan),
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

  Widget _zhLine(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: ChinaColors.muted,
          height: 1.6,
        ),
      ),
    );
  }

  Widget _modeBadge(ThemeData theme) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ChinaColors.shuangdi,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: ChinaColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Text(
          card.modeName,
          style: theme.textTheme.labelMedium?.copyWith(
            color: ChinaColors.muted,
          ),
        ),
      ),
    );
  }
}
