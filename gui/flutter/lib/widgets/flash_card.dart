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
  });

  final ActiveCard card;
  final bool flipped;
  final VoidCallback onFlip;

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
          Text(
            card.explanation,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: ChinaColors.ink,
              height: 1.6,
            ),
          ),
        ],
      ],
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
