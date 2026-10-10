import 'dart:convert';
import 'dart:io';

import 'ffi/wordcard.dart';

final class _Def {
  const _Def(this.ph, this.pos, this.def);
  final String ph;
  final String pos;
  final String def;
}

/// 粘贴单词表 → 记忆任务。
/// 支持每行：`word` 或 `word 释义`（释义含中文则直接采用）；纯英文走 ECDICT/LLM 查词。
final class PasteImporter {
  PasteImporter(this.engine);

  final WordCardEngine engine;
  static final _cjk = RegExp(r'[\u4e00-\u9fff]');

  static String? _root() {
    for (final c in ['.', '/opt/WordCard']) {
      if (File('$c/tools/define_words.py').existsSync()) return c;
    }
    return null;
  }

  Future<int> import(
    String name,
    String text, {
    void Function(int done, int total)? onProgress,
  }) async {
    final words = <String>[];
    final provided = <String, String>{};
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      String w = line;
      String rest = '';
      final m = RegExp(r'^([^\s]+)\s+(.*)$').firstMatch(line);
      if (m != null) {
        w = m.group(1)!;
        rest = m.group(2)!.trim();
      }
      if (w.isEmpty || words.contains(w)) continue;
      words.add(w);
      if (rest.isNotEmpty && _cjk.hasMatch(rest)) provided[w] = rest;
    }
    if (words.isEmpty) return 0;

    final toLookup = words.where((w) => !provided.containsKey(w)).toList();
    final defs = await _lookup(toLookup);

    var added = 0;
    var done = 0;
    for (final w in words) {
      done++;
      if (engine.hasItem(w)) {
        onProgress?.call(done, words.length);
        continue;
      }
      final d = defs[w];
      final ans = provided[w] ??
          (d != null && d.def.isNotEmpty
              ? (d.pos.isEmpty ? d.def : '${d.pos} ${d.def}')
              : '');
      final id = engine.addItem(
        question: w,
        answer: ans,
        hint: d?.ph ?? '',
        category: 1,
        tags: 'custom:$name',
      );
      if (id != 0) added++;
      if (done % 20 == 0) {
        onProgress?.call(done, words.length);
        await Future<void>.delayed(Duration.zero);
      }
    }
    engine.save();
    onProgress?.call(words.length, words.length);
    return added;
  }

  Future<Map<String, _Def>> _lookup(List<String> words) async {
    final out = <String, _Def>{};
    if (words.isEmpty) return out;
    final root = _root();
    if (root == null) return out;
    final proc = await Process.start(
      'python3',
      ['$root/tools/define_words.py'],
      workingDirectory: root,
    );
    proc.stdin.write(words.join('\n'));
    await proc.stdin.flush();
    await proc.stdin.close();
    proc.stderr.drain<void>();
    final lines =
        proc.stdout.transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final d = json.decode(line) as Map<String, dynamic>;
        out['${d['w']}'] = _Def(
            '${d['ph'] ?? ''}', '${d['p'] ?? ''}', '${d['d'] ?? ''}');
      } catch (_) {}
    }
    await proc.exitCode;
    return out;
  }
}
