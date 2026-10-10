import 'dart:convert';
import 'dart:io';

/// 按需「用法/场景」助记服务客户端。
///
/// 懒启动 `tools/memo_server.py`（本地 LLM 常驻），复习到无 memo 的词时
/// [request] 一行，得到结果后回调，用于写回卡片。
final class MemoService {
  MemoService._();

  static final MemoService instance = MemoService._();

  Process? _proc;
  String? _root;
  final Map<String, void Function(String memo)> _pending = {};

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
      final cb = _pending.remove('${d['w']}');
      cb?.call('${d['memo'] ?? ''}');
    } catch (_) {}
  }

  /// 请求某词的助记；[context] 为短语境（可空）。
  void request(String word, String context, void Function(String memo) onMemo) {
    if (word.trim().isEmpty) return;
    _pending[word] = onMemo;
    final p = _proc;
    if (p == null) {
      start().then((_) => _send(word, context));
    } else {
      _send(word, context);
    }
  }

  void _send(String word, String context) {
    try {
      _proc?.stdin.writeln(
          jsonEncode({'w': word, 'ctx': context.length > 200 ? context.substring(0, 200) : context}));
    } catch (_) {
      _proc = null;
    }
  }
}
