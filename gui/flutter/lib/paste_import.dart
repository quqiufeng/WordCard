import 'dart:convert';
import 'dart:io';

import 'ffi/wordcard.dart';
import 'native_paths.dart';

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

  static String? _root() =>
      NativePaths.findFile('native/staticpy/define/wc_define');

  Future<int> import(
    String name,
    String text, {
    void Function(int done, int total)? onProgress,
  }) async {
    final words = <String>[];
    final provided = <String, String>{};
    for (final raw in text.split('\n')) {
      var line = raw.trim();
      if (line.isEmpty) continue;
      // 去掉序号前缀：1. / 1、 / (1)
      line = line.replaceFirst(RegExp(r'^[\(\[]?\d+[\)\].、:：]?\s*'), '');
      // 按首个中文字符切分：左英文(可含空格的词组)，右中文释义
      final idx = line.indexOf(_cjk);
      String en, zh;
      if (idx > 0) {
        en = line.substring(0, idx).trim();
        zh = line.substring(idx).trim();
      } else if (idx == 0) {
        continue; // 中文开头，跳过
      } else {
        en = line;
        zh = '';
      }
      en = en.replaceAll(RegExp(r'[\s\t:：,，;；\-–—]+$'), '').trim();
      if (en.isEmpty || words.contains(en)) continue;
      words.add(en);
      if (zh.isNotEmpty) provided[en] = zh;
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
    if (words.isEmpty) return {};
    return await _lookupNative(words) ?? {};
  }

  Future<Map<String, _Def>?> _lookupNative(List<String> words) async {
    final root = _root();
    if (root == null) return null;
    final bin = File('$root/native/staticpy/define/wc_define');
    if (!bin.existsSync()) return null;
    try {
      final env = Map<String, String>.from(Platform.environment);
      env['LD_LIBRARY_PATH'] = [
        '$root/native/staticpy/define',
        '$root/native/staticpy/translate',
        env['LD_LIBRARY_PATH'] ?? '',
      ].where((e) => e.isNotEmpty).join(':');
      final proc = await Process.start(
        bin.path,
        words,
        workingDirectory: root,
        environment: env,
      );
      proc.stdin.write(words.join('\n'));
      await proc.stdin.flush();
      await proc.stdin.close();
      proc.stderr.drain<void>();
      final out = <String, _Def>{};
      var idx = 0;
      await for (final line
          in proc.stdout.transform(utf8.decoder).transform(const LineSplitter())) {
        if (idx >= words.length) break;
        final w = words[idx++];
        final text = line.trim();
        if (text.isEmpty) continue;
        final p = text.split('\t');
        out[w] = p.length >= 4
            ? _Def(p[1], p[2], p[3])
            : _Def('', '', text);
      }
      final code = await proc.exitCode;
      if (code != 0) return null;
      return out.length == words.length ? out : null;
    } catch (_) {
      return null;
    }
  }

}
