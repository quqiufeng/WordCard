import 'dart:convert';
import 'dart:io';

import 'ffi/wordcard.dart';

/// 一个考试词表（CET4/CET6/考研/托福/雅思/GRE/高考）。
final class WordlistInfo {
  const WordlistInfo({
    required this.name,
    required this.title,
    required this.count,
  });

  final String name;
  final String title;
  final int count;
}

/// 读取 `data/wordlists/` 下的词表并通过 FFI 导入 DB。
///
/// 数据由 `tools/build_wordlists.py` 从 ECDICT 生成，TSV 为单行 5 列:
/// word \t phonetic \t pos \t translation \t tag
final class WordlistService {
  WordlistService(this.engine);

  final WordCardEngine engine;

  static Directory? _resolveDir() {
    const candidates = ['data/wordlists', '/opt/WordCard/data/wordlists'];
    for (final c in candidates) {
      final d = Directory(c);
      if (d.existsSync()) return d;
    }
    return null;
  }

  /// 可用词表列表；数据缺失时返回空。
  List<WordlistInfo> list() {
    final dir = _resolveDir();
    if (dir == null) return const [];
    final mf = File('${dir.path}/manifest.json');
    if (!mf.existsSync()) return const [];
    final map = json.decode(mf.readAsStringSync()) as Map<String, dynamic>;
    return map.entries
        .map((e) => WordlistInfo(
              name: e.key,
              title: '${e.value['title'] ?? e.key}',
              count: (e.value['count'] ?? 0) as int,
            ))
        .toList(growable: false);
  }

  /// 导入词表，返回新增条数（已存在的词会被跳过）。
  /// [onProgress] 回调 (已处理, 总数)。
  Future<int> import(
    String name, {
    void Function(int done, int total)? onProgress,
  }) async {
    final dir = _resolveDir();
    if (dir == null) throw StateError('未找到 data/wordlists 目录');
    final file = File('${dir.path}/$name.tsv');
    if (!file.existsSync()) throw StateError('词表文件不存在: $name.tsv');

    final lines = await file.readAsLines();
    final total = lines.length;
    var added = 0;
    var done = 0;
    for (final line in lines) {
      done++;
      if (line.isEmpty) continue;
      final f = line.split('\t');
      if (f.length < 4 || f[0].isEmpty) continue;
      final word = f[0];
      if (engine.hasItem(word)) continue;
      final id = engine.addItem(
        question: word,
        answer: f[3],
        hint: f[1],
        category: 1,
        tags: 'dict:$name',
      );
      if (id != 0) added++;
      if (done % 200 == 0) {
        onProgress?.call(done, total);
        await Future<void>.delayed(Duration.zero); // 让出 UI 线程
      }
    }
    engine.save();
    onProgress?.call(total, total);
    return added;
  }
}
