import 'package:flutter/material.dart';

import '../reader_library.dart';
import '../theme/app_theme.dart';
import 'clickable_text.dart';

class ReaderParagraphView extends StatelessWidget {
  const ReaderParagraphView({
    super.key,
    required this.paragraph,
    required this.translation,
    required this.loading,
    required this.isToc,
    required this.fontFamily,
    required this.fontSize,
    required this.onWordTap,
    required this.onTranslate,
    required this.onSpeak,
  });

  final ReaderParagraph paragraph;
  final String? translation;
  final bool loading;
  final bool isToc;
  final String fontFamily;
  final double fontSize;
  final void Function(String word) onWordTap;
  final VoidCallback onTranslate;
  final VoidCallback onSpeak;

  @override
  Widget build(BuildContext context) {
    if (isToc) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(28, 2, 20, 2),
        child: Text(
          paragraph.text,
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: fontSize * 0.88,
            height: 1.45,
            color: Kami.ink,
          ),
        ),
      );
    }
    if (paragraph.heading) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(28, 22, 28, 6),
        child: Text(
          paragraph.text,
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: 21,
            fontWeight: FontWeight.w500,
            height: 1.4,
            color: Kami.ink,
          ),
        ),
      );
    }

    final zh = translation;
    final canTranslate = !paragraph.isChinese;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClickableText(
                  paragraph.text,
                  onWordTap: onWordTap,
                  style: TextStyle(
                    fontFamily: fontFamily,
                    fontSize: fontSize,
                    height: 1.8,
                    color: Kami.ink,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Column(
                children: [
                  if (canTranslate)
                    _iconAction(
                      tooltip: loading ? '翻译中…' : '翻译本段',
                      icon: loading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child:
                                  CircularProgressIndicator(strokeWidth: 1.6))
                          : Icon(
                              zh == null
                                  ? Icons.translate_outlined
                                  : Icons.translate,
                              size: 18,
                              color: zh == null ? Kami.faint : Kami.inkBlue,
                            ),
                      color: zh == null ? Kami.faint : Kami.inkBlue,
                      onTap: loading ? null : onTranslate,
                    ),
                  if (!paragraph.isChinese)
                    _iconAction(
                      tooltip: '朗读本段',
                      icon: const Icon(Icons.volume_up_outlined,
                          size: 18, color: Kami.faint),
                      color: Kami.faint,
                      onTap: onSpeak,
                    ),
                ],
              ),
            ],
          ),
          if (zh != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8, right: 42),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: Color(0x661B365D), width: 2),
                ),
              ),
              child: Text(
                zh,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontFamily: fontFamily,
                      fontSize: fontSize,
                      height: 1.8,
                      color: Kami.muted,
                    ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _iconAction({
    required String tooltip,
    required Widget icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return IconButton(
      tooltip: tooltip,
      icon: icon,
      color: color,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      padding: EdgeInsets.zero,
      onPressed: onTap,
    );
  }
}
