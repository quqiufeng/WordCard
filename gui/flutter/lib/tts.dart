import 'dart:io';

/// 常驻 TTS 客户端：懒启动 `tools/tts_server.py`（模型只加载一次），
/// 之后 [speak] 只需写入一行文本即可朗读。
final class TtsService {
  TtsService._();

  static final TtsService instance = TtsService._();

  Process? _proc;
  String? _root;

  String? _findRoot() {
    for (final c in ['.', '/opt/WordCard']) {
      if (File('$c/tools/tts_server.py').existsSync()) return c;
    }
    return null;
  }

  /// 预启动守护进程（加载模型）。
  Future<void> start() async {
    if (_proc != null) return;
    _root ??= _findRoot();
    if (_root == null) return;
    try {
      final p = await Process.start(
        'python3',
        ['$_root/tools/tts_server.py'],
        workingDirectory: _root,
      );
      p.stdout.drain<void>();
      p.stderr.drain<void>();
      p.exitCode.then((_) {
        if (identical(_proc, p)) _proc = null;
      });
      _proc = p;
    } catch (_) {
      _proc = null;
    }
  }

  /// 朗读一段文本（英文单词/句子）。
  void speak(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    final p = _proc;
    if (p == null) {
      start().then((_) => speak(t));
      return;
    }
    try {
      p.stdin.writeln(t);
    } catch (_) {
      _proc = null;
    }
  }

  void stop() {
    _proc?.kill();
    _proc = null;
  }
}
