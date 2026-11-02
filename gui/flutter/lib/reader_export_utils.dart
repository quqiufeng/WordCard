String cleanCardText(String s) {
  return s
      .replaceAllMapped(
        RegExp(r'\[([^\]]*)\]\([^)]*\)'),
        (m) => m.group(1) ?? '',
      )
      .replaceAll(RegExp(r'[*_`#]+'), '')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

List<String> splitSentences(String text) => RegExp(
        r'[^。！？!?\.]*[。！？!?\.]+|[^。！？!?\.]+$')
    .allMatches(text)
    .map((m) => m.group(0)?.trim() ?? '')
    .where((s) => s.isNotEmpty)
    .toList(growable: false);

List<String> splitChineseContent(String text, {int target = 1000}) {
  final chunks = <String>[];
  final buf = StringBuffer();
  var size = 0;

  void flush() {
    final t = buf.toString().trim();
    if (t.isNotEmpty) chunks.add(t);
    buf.clear();
    size = 0;
  }

  void append(String s) {
    if (s.trim().isEmpty) return;
    if (size > 0 && size + s.length > target) flush();
    buf.write(s.trim());
    buf.write('\n\n');
    size += s.length;
  }

  for (final p in text.split(RegExp(r'\n{2,}'))) {
    final t = p.trim();
    if (t.isEmpty) continue;
    if (t.length <= target) {
      append(t);
      continue;
    }
    final sentences = splitSentences(t);
    if (sentences.isEmpty) {
      for (var i = 0; i < t.length; i += target) {
        append(t.substring(i, i + target > t.length ? t.length : i + target));
      }
    } else {
      for (final s in sentences) {
        if (s.length > target) {
          for (var i = 0; i < s.length; i += target) {
            append(s.substring(
                i, i + target > s.length ? s.length : i + target));
          }
        } else {
          append(s);
        }
      }
    }
  }
  flush();
  return chunks;
}
