import 'dart:convert';
import 'dart:io';

import 'ffi/wordcard.dart';

/// 电子书解析结果中的一个词条。
final class BookWord {
  const BookWord(this.word, this.context);
  final String word;
  final String context;
}

/// 电子书解析结果。
final class BookExtract {
  const BookExtract({required this.title, required this.author, required this.words});
  final String title;
  final String author;
  final List<BookWord> words;
}

/// 电子书导入：解析**复用**现有 Python 管道（`tools/ebook_extract.py`），
/// Flutter 端只负责选文件、调脚本、把词条经 FFI 写入同一 DB。
final class EbookImporter {
  EbookImporter(this.engine);

  final WordCardEngine engine;

  static String? _root() {
    const candidates = ['.', '/opt/WordCard'];
    for (final c in candidates) {
      if (File('$c/tools/ebook_extract.py').existsSync()) return c;
    }
    return null;
  }

  /// 用 zenity 选择电子书文件；取消返回 null。
  Future<String?> pickFile() async {
    final r = await Process.run('zenity', [
      '--file-selection',
      '--title=选择电子书',
      '--file-filter=电子书 | *.epub *.mobi *.azw3 *.pdf *.md *.txt',
      '--file-filter=所有文件 | *',
    ]);
    if (r.exitCode != 0) return null;
    final path = (r.stdout as String).trim();
    return path.isEmpty ? null : path;
  }

  /// 调用 Python 解析电子书，返回词条（不含 DB 写入）。
  Future<BookExtract> extract(String bookPath, {int max = 200}) async {
    final root = _root();
    if (root == null) throw StateError('未找到 tools/ebook_extract.py');
    final tmp = File('${Directory.systemTemp.path}/wordcard_extract_'
        '${DateTime.now().microsecondsSinceEpoch}.json');
    try {
      final r = await Process.run(
        'python3',
        ['$root/tools/ebook_extract.py', bookPath, '--max', '$max',
         '--out', tmp.path],
        workingDirectory: root,
      );
      if (r.exitCode != 0 || !tmp.existsSync()) {
        throw StateError('解析失败: ${(r.stderr as String).trim()}');
      }
      final data = json.decode(tmp.readAsStringSync()) as Map<String, dynamic>;
      final words = (data['words'] as List)
          .map((e) => BookWord('${e['w']}', '${e['ctx'] ?? ''}'))
          .toList(growable: false);
      return BookExtract(
        title: '${data['title'] ?? ''}',
        author: '${data['author'] ?? ''}',
        words: words,
      );
    } finally {
      if (tmp.existsSync()) tmp.deleteSync();
    }
  }

  /// 把解析出的词条写入 DB（已存在则跳过）。返回新增条数。
  Future<int> importWords(
    BookExtract extract, {
    void Function(int done, int total)? onProgress,
  }) async {
    final total = extract.words.length;
    var added = 0;
    var done = 0;
    for (final w in extract.words) {
      done++;
      if (engine.hasItem(w.word)) continue;
      final id = engine.addItem(
        question: w.word,
        explanation: w.context,
        category: 1,
        tags: 'book:${extract.title}',
      );
      if (id != 0) added++;
      if (done % 100 == 0) {
        onProgress?.call(done, total);
        await Future<void>.delayed(Duration.zero);
      }
    }
    engine.save();
    onProgress?.call(total, total);
    return added;
  }
}
