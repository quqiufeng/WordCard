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
  });

  final ActiveCard card;
  final bool flipped;
  final VoidCallback onFlip;

  /// 点击英文段落/例句时回调（朗读）。
  final void Function(String text)? onSpeak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onFlip,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _panel(context, theme),
        ),
      ),
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

  /// 把 explanation 按行拆开：英文行可点朗读，中文行作对照。
  List<Widget> _explanationLines(ThemeData theme) {
    final cjk = RegExp(r'[\u4e00-\u9fff]');
    final latin = RegExp(r'[A-Za-z]');
    final lines = card.explanation
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return [
      for (final line in lines)
        if (latin.hasMatch(line) && !cjk.hasMatch(line) && onSpeak != null)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => onSpeak!(line),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 4, right: 6),
                      child: Icon(Icons.volume_up_outlined,
                          size: 16, color: ChinaColors.dim),
                    ),
                    Expanded(
                      child: Text(
                        line,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: ChinaColors.ink,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              line,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ChinaColors.muted,
                height: 1.6,
              ),
            ),
          ),
    ];
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
