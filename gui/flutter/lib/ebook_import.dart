import 'dart:convert';
import 'dart:io';

import 'ffi/wordcard.dart';

/// 电子书解析结果中的一个词条。
final class BookWord {
  const BookWord(this.word, this.context, this.definition, this.pos);
  final String word;
  final String context;
  final String definition; // 中文释义（LLM 生成，可能为空）
  final String pos; // 词性
}

/// 电子书解析结果。
final class BookExtract {
  const BookExtract({
    required this.title,
    required this.author,
    required this.words,
  });

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

  /// 调用 Python 解析电子书（可选 LLM 释义），返回词条（不含 DB 写入）。
  /// [onStage] 回调解析/释义阶段文本。
  Future<BookExtract> extract(
    String bookPath, {
    int max = 200,
    bool define = true,
    void Function(String stage)? onStage,
  }) async {
    final root = _root();
    if (root == null) throw StateError('未找到 tools/ebook_extract.py');
    final tmp = File('${Directory.systemTemp.path}/wordcard_extract_'
        '${DateTime.now().microsecondsSinceEpoch}.json');
    try {
      final proc = await Process.start(
        'python3',
        [
          '$root/tools/ebook_extract.py',
          bookPath,
          '--max', '$max',
          '--out', tmp.path,
          if (define) '--define',
        ],
        workingDirectory: root,
      );
      final errors = <String>[];
      proc.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.startsWith('DEFINE ')) {
          onStage?.call('生成释义 ${line.substring(7)}');
        } else if (line.startsWith('STAGE ')) {
          onStage?.call(line.substring(6));
        } else if (line.trim().isNotEmpty) {
          errors.add(line);
        }
      });
      proc.stdout.drain<void>();
      final code = await proc.exitCode;
      if (code != 0 || !tmp.existsSync()) {
        throw StateError('解析失败: ${errors.join('\n')}');
      }
      final data = json.decode(tmp.readAsStringSync()) as Map<String, dynamic>;
      final words = (data['words'] as List)
          .map((e) => BookWord(
                '${e['w']}',
                '${e['ctx'] ?? ''}',
                '${e['d'] ?? ''}',
                '${e['p'] ?? ''}',
              ))
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
      final answer = w.definition.isEmpty
          ? ''
          : (w.pos.isEmpty ? w.definition : '${w.pos} ${w.definition}');
      final id = engine.addItem(
        question: w.word,
        answer: answer,
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
