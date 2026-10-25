import 'dart:convert';
import 'dart:io';

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

/// 按需「用法/场景」助记服务客户端。
///
/// 懒启动 `tools/memo_server.py`（本地 LLM 常驻），复习到无 memo 的词时
/// [request] 一行，得到结果后回调，用于写回卡片。阅读页的段落翻译与
/// 点词查词也复用同一个常驻进程。
final class MemoService {
  MemoService._();

  static final MemoService instance = MemoService._();

  Process? _proc;
  String? _root;
  final Map<String, void Function(String memo)> _pending = {};
  final Map<String, void Function(String zh)> _pendingText = {};
  final Map<String, void Function(WordDef def)> _pendingLookup = {};

  String? _findRoot() {
    for (final c in ['.', '/opt/WordCard']) {
      if (File('$c/tools/memo_server.py').existsSync()) return c;
    }
    return null;
  }

  Future<void> start() async {
    if (_proc != null) return;
    _root ??= _findRoot();
    if (_root == null) return;
    try {
      final p = await Process.start('python3', ['$_root/tools/memo_server.py'],
          workingDirectory: _root);
      p.stderr.drain<void>();
      p.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onLine, onDone: () {
        if (identical(_proc, p)) _proc = null;
      });
      p.exitCode.then((_) {
        if (identical(_proc, p)) _proc = null;
      });
      _proc = p;
    } catch (_) {
      _proc = null;
    }
  }

  void _onLine(String line) {
    if (line.trim().isEmpty) return;
    try {
      final d = json.decode(line) as Map<String, dynamic>;
      if (d.containsKey('lookup')) {
        final w = '${d['lookup']}';
        final cb =
            _pendingLookup.remove(w) ?? _pendingLookup.remove(w.toLowerCase());
        cb?.call(WordDef(
          word: w,
          phonetic: '${d['ph'] ?? ''}',
          pos: '${d['p'] ?? ''}',
          def: '${d['d'] ?? ''}',
          en: '${d['en'] ?? ''}',
          base: '${d['base'] ?? ''}',
        ));
      } else if (d.containsKey('zh')) {
        _pendingText.remove('${d['t']}')?.call('${d['zh'] ?? ''}');
      } else {
        _pending.remove('${d['w']}')?.call('${d['memo'] ?? ''}');
      }
    } catch (_) {}
  }

  /// 请求某词的助记；[context] 为短语境（可空）。
  void request(String word, String context, void Function(String memo) onMemo) {
    if (word.trim().isEmpty) return;
    _pending[word] = onMemo;
    final p = _proc;
    if (p == null) {
      start().then((_) => _send({'w': word, 'ctx': context}));
    } else {
      _send({'w': word, 'ctx': context});
    }
  }

  /// 翻译一段文本（英文→中文）；[word] 用于把对应中文用【】标出。
  void translateText(String text, void Function(String zh) onZh,
      {String? word}) {
    if (text.trim().isEmpty) return;
    _pendingText[text] = onZh;
    final p = _proc;
    final req = <String, dynamic>{
      't': text,
      if (word != null && word.isNotEmpty) 'w': word,
    };
    if (p == null) {
      start().then((_) => _send(req));
    } else {
      _send(req);
    }
  }

  /// 查词（阅读页点词）：ECDICT → 词形还原 → 本地 LLM 兜底。
  void lookup(String word, void Function(WordDef def) onDef) {
    final w = word.trim();
    if (w.isEmpty) return;
    _pendingLookup[w] = onDef;
    final p = _proc;
    final req = <String, dynamic>{'lookup': w};
    if (p == null) {
      start().then((_) => _send(req));
    } else {
      _send(req);
    }
  }

  void _send(Map<String, dynamic> req) {
    try {
      if (req['ctx'] is String && (req['ctx'] as String).length > 200) {
        req['ctx'] = (req['ctx'] as String).substring(0, 200);
      }
      _proc?.stdin.writeln(jsonEncode(req));
    } catch (_) {
      _proc = null;
    }
  }
}
