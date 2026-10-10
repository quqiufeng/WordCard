import 'dart:convert';
import 'dart:io';

import 'ffi/wordcard.dart';

/// 电子书解析结果中的一个词条（含段落/例句对照）。
final class BookWord {
  BookWord({
    required this.word,
    required this.phonetic,
    required this.pos,
    required this.definition,
    required this.para,
    required this.sents,
  });

  final String word;
  final String phonetic;
  final String pos;
  final String definition; // 中文释义（ECDICT 词典）
  final String para; // 含该词的段落（英文）
  final List<String> sents; // 含该词的例句（英文）
  String paraZh = '';
  List<String> sentsZh = [];
  String memo = ''; // 一句话用法/场景描述（助记）
}

/// 电子书解析结果。
final class BookExtract {
  const BookExtract({
    required this.title,
    required this.author,
    required this.words,
    this.bilingualPath,
    this.materialPath,
  });

  final String title;
  final String author;
  final List<BookWord> words;
  final String? bilingualPath; // 词级对照 TSV
  final String? materialPath; // 含段落/例句的 JSONL 物料

  List<String> get undefinedWords =>
      words.where((w) => w.definition.isEmpty).map((w) => w.word).toList();
}

/// 电子书导入。
///
/// 策略（已定）：单词释义走本地 **ECDICT 词典**；
/// 段落/例句由本地 **LLM 异步翻译**（`tools/ebook_translate.py`）并动态回填。
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

  static String _slug(String path) {
    final base = path.split('/').last;
    final name =
        base.contains('.') ? base.substring(0, base.lastIndexOf('.')) : base;
    return name.replaceAll(RegExp(r'[^\w\u4e00-\u9fff-]+'), '_');
  }

  static String _truncUtf8(String s, int maxBytes) {
    final bytes = utf8.encode(s);
    if (bytes.length <= maxBytes) return s;
    return utf8.decode(bytes.sublist(0, maxBytes), allowMalformed: true);
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

  /// 解析电子书，生成词级对照 TSV + 含段落/例句的物料 JSONL。
  Future<BookExtract> extract(
    String bookPath, {
    int max = 200,
    void Function(String stage)? onStage,
  }) async {
    final root = _root();
    if (root == null) throw StateError('未找到 tools/ebook_extract.py');
    onStage?.call('解析中');
    final slug = _slug(bookPath);
    final dir = Directory('$root/data/books')..createSync(recursive: true);
    final bilingual = File('${dir.path}/$slug.tsv');
    final material = File('${dir.path}/$slug.jsonl');
    final tmp = File('${Directory.systemTemp.path}/wordcard_'
        '${DateTime.now().microsecondsSinceEpoch}.json');
    try {
      final r = await Process.run(
        'python3',
        [
          '$root/tools/ebook_extract.py',
          bookPath,
          '--max', '$max',
          '--bilingual', bilingual.path,
          '--material', material.path,
          '--out', tmp.path,
        ],
        workingDirectory: root,
      );
      if (r.exitCode != 0 || !tmp.existsSync()) {
        throw StateError('解析失败: ${(r.stderr as String).trim()}');
      }
      final data = json.decode(tmp.readAsStringSync()) as Map<String, dynamic>;
      final words = (data['words'] as List)
          .map((e) => BookWord(
                word: '${e['w']}',
                phonetic: '${e['ph'] ?? ''}',
                pos: '${e['p'] ?? ''}',
                definition: '${e['d'] ?? ''}',
                para: '${e['para'] ?? ''}',
                sents: (e['sents'] as List? ?? [])
                    .map((s) => '$s')
                    .toList(growable: false),
              ))
          .toList(growable: false);
      return BookExtract(
        title: '${data['title'] ?? ''}',
        author: '${data['author'] ?? ''}',
        words: words,
        bilingualPath: bilingual.path,
        materialPath: material.path,
      );
    } finally {
      if (tmp.existsSync()) tmp.deleteSync();
    }
  }

  String _answer(BookWord w) {
    if (w.definition.isEmpty) return '';
    return w.pos.isEmpty ? w.definition : '${w.pos} ${w.definition}';
  }

  /// 组装 explanation：段落原/译 + 例句原/译（有译文则成对）。
  String _explanation(BookWord w) {
    final parts = <String>[];
    if (w.memo.isNotEmpty) parts.add('【用法】${w.memo}');
    if (w.para.isNotEmpty) {
      parts.add(w.para);
      if (w.paraZh.isNotEmpty) parts.add(w.paraZh);
    }
    for (var i = 0; i < w.sents.length; i++) {
      parts.add(w.sents[i]);
      if (i < w.sentsZh.length && w.sentsZh[i].isNotEmpty) {
        parts.add(w.sentsZh[i]);
      }
    }
    return _truncUtf8(parts.join('\n'), 1000);
  }

  /// 写入词条（释义随 ECDICT 带入）。返回新增条数。
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
        answer: _answer(w),
        explanation: _explanation(w),
        hint: w.phonetic,
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

  /// 异步用 LLM 翻译段落/例句，逐条**动态回填** explanation。
  Future<int> translateAll(
    BookExtract extract, {
    void Function(int done, int total)? onProgress,
  }) async {
    final root = _root();
    final material = extract.materialPath;
    if (root == null || material == null || extract.words.isEmpty) return 0;
    final byWord = {for (final w in extract.words) w.word: w};
    var updated = 0;
    var done = 0;
    try {
      final proc = await Process.start(
        'python3',
        ['$root/tools/ebook_translate.py', '--material', material],
        workingDirectory: root,
      );
      proc.stderr.drain<void>();
      final lines = proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        if (line.trim().isEmpty) continue;
        done++;
        try {
          final d = json.decode(line) as Map<String, dynamic>;
          final w = byWord['${d['w']}'];
          if (w == null) continue;
          w.paraZh = '${d['para_zh'] ?? ''}';
          w.sentsZh = (d['sents_zh'] as List? ?? []).map((s) => '$s').toList();
          w.memo = '${d['memo'] ?? ''}';
          final id = engine.itemIdByQuestion(w.word);
          if (id != null && engine.updateItemExplanation(id, _explanation(w))) {
            updated++;
          }
        } catch (_) {
          // 跳过无法解析的行
        }
        onProgress?.call(done, extract.words.length);
      }
      await proc.exitCode;
      engine.save();
    } finally {
      // 物料文件由脚本原地补全，保留供下次加载
    }
    return updated;
  }
}
