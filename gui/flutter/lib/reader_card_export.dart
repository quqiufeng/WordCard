import 'dart:async';
import 'dart:io';

import 'memo_service.dart';
import 'native_paths.dart';
import 'reader_export_utils.dart';
import 'reader_library.dart';

final class CardExportResult {
  const CardExportResult({
    required this.files,
    required this.chinese,
    this.words = 0,
    this.examples = 0,
  });

  final List<String> files;
  final bool chinese;
  final int words;
  final int examples;

  String get message {
    if (chinese) {
      return files.length == 1
          ? '已导出中文卡片：${files.first}'
          : '已导出 ${files.length} 张中文卡片：${files.first} …';
    }
    return '已导出：${files.first}（词汇 $words 条'
        '${examples > 0 ? '，双语例句 $examples 条' : ''}）';
  }

  Map<String, dynamic> toJson() => {
        'files': files,
        'chinese': chinese,
        'words': words,
        'examples': examples,
      };
}

class _ExportWord {
  const _ExportWord(this.word, this.definition, this.context);
  final String word;
  final String definition;
  final String context;
}

/// 阅读页卡片导出：中文正文单独排版，双语页提取词汇与例句。
final class ReaderCardExporter {
  ReaderCardExporter({
    required this.bookTitle,
    required this.chapterTitle,
    required this.paragraphs,
    required this.translations,
  });

  final String bookTitle;
  final String chapterTitle;
  final List<ReaderParagraph> paragraphs;
  final List<String?> translations;

  String get _title {
    final name = bookTitle.trim();
    if (name.length <= 12) return name;
    return '${name.substring(0, 12)}…';
  }

  String? get _root =>
      NativePaths.findFile('native/staticpy/card_txt/wc_card_txt');

  Map<String, String> _loadDictionary(String root) {
    final out = <String, String>{};
    final f = File('$root/data/wordlists/cet4.tsv');
    if (!f.existsSync()) return out;
    for (final line in f.readAsLinesSync()) {
      final p = line.split('\t');
      if (p.length < 4) continue;
      final pos = p[2].trim();
      final def = p[3].trim();
      if (def.isEmpty) continue;
      out[p[0].toLowerCase()] = pos.isEmpty ? def : '$pos $def';
    }
    return out;
  }

  Future<String> _translate(String text) async {
    final c = Completer<String>();
    MemoService.instance.translateText(text, (zh) {
      if (!c.isCompleted) c.complete(zh.trim());
    });
    try {
      return await c.future.timeout(const Duration(seconds: 60));
    } catch (_) {
      return '';
    }
  }

  Future<int> _measure(String root, String title, File content) async {
    try {
      final r = await Process.run(
        '$root/native/staticpy/card_cn/wc_card_cn',
        ['measure', title, content.path],
        workingDirectory: root,
        environment: {
          ...Platform.environment,
          'LD_LIBRARY_PATH':
              '$root/native/staticpy/card_cn:$root/src:${Platform.environment['LD_LIBRARY_PATH'] ?? ''}',
        },
      );
      if (r.exitCode != 0) return 0;
      return int.tryParse((r.stdout as String).trim()) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<List<String>> _fitChinese(
      String root, String title, String text, File scratch) async {
    // Small units let us pack pages by actual rendered height instead of
    // leaving a half-empty fixed-size canvas.
    final units = splitChineseContent(text, target: 250);
    final pages = <String>[];
    var page = '';

    Future<bool> fits(String candidate) async {
      scratch.writeAsStringSync(candidate);
      return await _measure(root, title, scratch) <= 1140;
    }

    for (final unit in units) {
      if (page.isEmpty) {
        page = unit;
        continue;
      }
      final candidate = '$page\n\n$unit';
      if (await fits(candidate)) {
        page = candidate;
      } else {
        pages.add(page);
        page = unit;
      }
    }
    if (page.isNotEmpty) pages.add(page);
    return pages;
  }

  void _removeOldShards(String home, String hash) {
    final re = RegExp('^${RegExp.escape(hash)}(?:_\\d+)?\\.png\$');
    try {
      for (final e in Directory(home).listSync()) {
        if (e is File && re.hasMatch(e.path.split('/').last)) {
          try {
            e.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<List<_ExportWord>> _words(String root, String pageText) async {
    final dict = _loadDictionary(root);
    final base =
        '${Directory.systemTemp.path}/wordcard_words_${DateTime.now().microsecondsSinceEpoch}';
    final textFile = File('$base.txt');
    final outFile = File('$base.tsv');
    textFile.writeAsStringSync(pageText);
    try {
      final r = await Process.run(
        '$root/native/staticpy/text/wc_text',
        [
          '--file',
          '$root/src/wordpick/en_freq.tsv',
          textFile.path,
          outFile.path,
          '12',
        ],
        workingDirectory: root,
        environment: {
          ...Platform.environment,
          'LD_LIBRARY_PATH': '$root/native/staticpy/text:$root/src',
        },
      );
      if (r.exitCode != 0 || !outFile.existsSync()) return const [];
      final out = <_ExportWord>[];
      for (final line in outFile.readAsLinesSync()) {
        final p = line.split('\t');
        if (p.length < 6) continue;
        final word = p[0].trim();
        if (word.isEmpty) continue;
        out.add(_ExportWord(
          word,
          dict[word.toLowerCase()] ?? '',
          cleanCardText(p.sublist(5).join('\t')),
        ));
      }
      return out;
    } catch (_) {
      return const [];
    } finally {
      if (outFile.existsSync()) outFile.deleteSync();
      if (textFile.existsSync()) textFile.deleteSync();
    }
  }

  Future<String> _hash(File f) async {
    try {
      final r = await Process.run('sha256sum', [f.path]);
      final h = (r.stdout as String).trim().split(RegExp(r'\s+')).first;
      if (h.length >= 16) return h.substring(0, 16);
      if (h.isNotEmpty) return h;
    } catch (_) {}
    return DateTime.now().microsecondsSinceEpoch.toRadixString(16);
  }

  String _exampleTranslation(String context, int idx) {
    if (idx < 0 || idx >= translations.length) return '';
    final full = translations[idx]?.trim() ?? '';
    if (full.isEmpty) return '';
    final en = splitSentences(paragraphs[idx].text);
    final zh = splitSentences(full);
    final pos = en.indexWhere((s) => s.trim() == context.trim());
    if (pos >= 0 && pos < zh.length && en.length == zh.length) {
      return zh[pos];
    }
    return full;
  }

  String _nearestChinese(int index) {
    if (index < 0) return '';
    for (var d = 1; d <= 3; d++) {
      final a = index - d;
      final b = index + d;
      if (a >= 0 && paragraphs[a].isChinese) return paragraphs[a].text;
      if (b < paragraphs.length && paragraphs[b].isChinese) {
        return paragraphs[b].text;
      }
    }
    return '';
  }

  Future<CardExportResult> export() async {
    final root = _root;
    if (root == null) throw StateError('未找到 wc_card_txt');
    final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    final input = File(
        '${Directory.systemTemp.path}/wordcard_export_${DateTime.now().microsecondsSinceEpoch}.txt');
    final md = File('${input.path}.md');
    try {
      final content = paragraphs
          .where((p) => p.text.trim().isNotEmpty)
          .toList(growable: false);
      var cjkCount = 0;
      var latinCount = 0;
      var chineseParagraphs = 0;
      for (final p in content) {
        cjkCount += RegExp(r'[\u4e00-\u9fff]').allMatches(p.text).length;
        latinCount += RegExp(r'[A-Za-z]').allMatches(p.text).length;
        if (p.isChinese) chineseParagraphs++;
      }
      final allChinese = content.isNotEmpty &&
          cjkCount > 0 &&
          cjkCount > latinCount * 2 &&
          chineseParagraphs >= (content.length * 0.6).ceil();
      if (allChinese) {
        final full = StringBuffer();
        for (final p in paragraphs) {
          final t = cleanCardText(p.text);
          if (t.isEmpty ||
              !RegExp(r'[\u4e00-\u9fffA-Za-z0-9]').hasMatch(t)) {
            continue;
          }
          full.writeln(t);
          full.writeln();
        }
        final text = full.toString().trim();
        final chunks = await _fitChinese(root, _title, text, input);
        if (chunks.isEmpty) chunks.add(text);
        input.writeAsStringSync(text);
        final hash = await _hash(input);
        _removeOldShards(home, hash);
        final names = <String>[];
        for (var i = 0; i < chunks.length; i++) {
          input.writeAsStringSync(chunks[i]);
          final png = chunks.length == 1
              ? '$home/$hash.png'
              : '$home/${hash}_${i + 1}.png';
          final title = chunks.length == 1
              ? _title
              : '$_title · ${i + 1}/${chunks.length}';
          final r = await Process.run(
            '$root/native/staticpy/card_cn/wc_card_cn',
            [title, input.path, png, '1200'],
            workingDirectory: root,
            environment: {
              ...Platform.environment,
              'LD_LIBRARY_PATH':
                  '$root/native/staticpy/card_cn:$root/src:${Platform.environment['LD_LIBRARY_PATH'] ?? ''}',
            },
          );
          if (r.exitCode != 0) {
            throw StateError((r.stderr as String).trim());
          }
          names.add(png);
        }
        return CardExportResult(files: names, chinese: true);
      }

      final pageText = paragraphs.map((p) => p.text).join('\n\n');
      final words = await _words(root, pageText);
      final hasChinesePage = paragraphs.any((p) => p.isChinese);
      final buf = StringBuffer();
      buf.writeln('TITLE: $_title');
      buf.writeln('---');
      var translated = 0;
      buf.writeln('EN-CH:');
      for (final w in words) {
        if (w.context.isEmpty) continue;
        buf.writeln(w.context);
        final idx = paragraphs.indexWhere((p) => p.text.contains(w.context));
        var zh = _exampleTranslation(w.context, idx);
        if (zh.isEmpty) {
          final near = hasChinesePage ? _nearestChinese(idx) : '';
          zh = near.isNotEmpty ? near : await _translate(w.context);
        }
        if (zh.isNotEmpty) {
          buf.writeln(zh);
          translated++;
        }
        buf.writeln();
      }
      buf.writeln('---');
      buf.writeln('VOCABULARY:');
      for (final w in words) {
        buf.writeln(
            '${w.word}|${w.definition.isEmpty ? '（词典未收录）' : w.definition}');
      }
      buf.writeln('---');
      buf.writeln('SENTENCES:');
      input.writeAsStringSync(buf.toString());

      final hash = await _hash(input);
      final png = '$home/$hash.png';
      final r = await Process.run(
        '$root/native/staticpy/card_txt/wc_card_txt',
        [input.path, png, md.path, ''],
        workingDirectory: root,
        environment: {
          ...Platform.environment,
          'LD_LIBRARY_PATH':
              '$root/native/staticpy/card_txt:$root/src:${Platform.environment['LD_LIBRARY_PATH'] ?? ''}',
        },
      );
      if (r.exitCode != 0) {
        throw StateError((r.stderr as String).trim());
      }
      return CardExportResult(
        files: [png],
        chinese: false,
        words: words.length,
        examples: translated,
      );
    } finally {
      if (input.existsSync()) input.deleteSync();
      if (md.existsSync()) md.deleteSync();
    }
  }
}
