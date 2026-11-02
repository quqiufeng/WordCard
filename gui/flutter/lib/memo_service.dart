import 'dart:async';
import 'dart:io';

import 'llama_service.dart';
import 'native_paths.dart';

/// 一次查词结果（ECDICT 优先，未收录由本地 LLM 兜底）。
final class WordDef {
  const WordDef({
    required this.word,
    required this.phonetic,
    required this.pos,
    required this.def,
    required this.en,
    this.base = '',
  });

  final String word;
  final String phonetic;
  final String pos;
  final String def;
  final String en;
  final String base;

  String get display => pos.isEmpty ? def : '$pos $def';
}

/// 查词/翻译/助记服务：直接调用 StaticPy 原生二进制，不再依赖 Python。
final class MemoService {
  MemoService._();

  static final MemoService instance = MemoService._();

  String? _root;

  String? _findRoot() =>
      NativePaths.findFile('native/staticpy/define/wc_define');

  Future<String?> _ensureRoot() async {
    _root ??= _findRoot();
    return _root;
  }

  Map<String, String> _env(String root) => {
        ...Platform.environment,
        'LD_LIBRARY_PATH':
            '$root/native/staticpy/define:$root/native/staticpy/translate',
      };

  Future<void> start() async {
    await _ensureRoot();
  }

  Future<void> request(
      String word, String context, void Function(String memo) onMemo) async {
    final w = word.trim();
    if (w.isEmpty) return;
    final root = await _ensureRoot();
    if (root == null || !await LlamaService.instance.ensure()) {
      onMemo('');
      return;
    }
    final out = File(
        '${Directory.systemTemp.path}/wordcard_memo_${DateTime.now().microsecondsSinceEpoch}.txt');
    try {
      final ctx = context.length > 200 ? context.substring(0, 200) : context;
      final prompt =
          '用中文为英语单词“$w”写一句简短的用法/场景助记，只输出助记。上下文：$ctx';
      final r = await Process.run(
        '$root/native/staticpy/translate/wc_translate',
        [prompt, out.path],
        environment: _env(root),
      ).timeout(const Duration(seconds: 90));
      final memo = r.exitCode == 0 && out.existsSync()
          ? out.readAsStringSync().trim()
          : '';
      onMemo(memo);
    } catch (_) {
      onMemo('');
    } finally {
      if (out.existsSync()) out.deleteSync();
    }
  }

  Future<void> translateText(String text, void Function(String zh) onZh,
      {String? word}) async {
    if (text.trim().isEmpty) return;
    final root = await _ensureRoot();
    if (root == null || !await LlamaService.instance.ensure()) {
      onZh('');
      return;
    }
    final out = File(
        '${Directory.systemTemp.path}/wordcard_tr_${DateTime.now().microsecondsSinceEpoch}.txt');
    try {
      final r = await Process.run(
        '$root/native/staticpy/translate/wc_translate',
        [text, out.path],
        environment: _env(root),
      ).timeout(const Duration(seconds: 90));
      final zh = r.exitCode == 0 && out.existsSync()
          ? out.readAsStringSync().trim()
          : '';
      onZh(zh);
    } catch (_) {
      onZh('');
    } finally {
      if (out.existsSync()) out.deleteSync();
    }
  }

  Future<void> lookup(
      String word, void Function(WordDef def) onDef) async {
    final w = word.trim();
    if (w.isEmpty) return;
    final root = await _ensureRoot();
    if (root == null) {
      onDef(WordDef(word: w, phonetic: '', pos: '', def: '', en: ''));
      return;
    }
    try {
      final r = await Process.run(
        '$root/native/staticpy/define/wc_define',
        [w, '--dict', '$root/data/wordlists/cet4.tsv'],
        environment: _env(root),
      ).timeout(const Duration(seconds: 20));
      final line = r.exitCode == 0 ? (r.stdout as String).trim() : '';
      final parts = line.split('\t');
      if (parts.length >= 2) {
        final def = parts.length >= 4 ? parts[3] : parts.sublist(1).join(' ');
        onDef(WordDef(
          word: parts[0],
          phonetic: parts[1],
          pos: '',
          def: def,
          en: '',
        ));
      } else {
        onDef(WordDef(word: w, phonetic: '', pos: '', def: '', en: ''));
      }
    } catch (_) {
      onDef(WordDef(word: w, phonetic: '', pos: '', def: '', en: ''));
    }
  }
}
