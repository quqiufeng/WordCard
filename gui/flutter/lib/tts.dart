import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 常驻 TTS 客户端：懒启动 `tools/tts_server.py`（模型只加载一次），
/// 之后 [speak] 只需写入一行文本即可朗读。
final class TtsService {
  TtsService._();

  static final TtsService instance = TtsService._();

  /// 正在合成（即将播放）的文本；完成广播后置空。用于播放按钮的等待动画。
  final ValueNotifier<String?> busy = ValueNotifier<String?>(null);

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
      p.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onLine, onDone: () {
        if (identical(_proc, p)) _proc = null;
      });
      p.stderr.drain<void>();
      p.exitCode.then((_) {
        if (identical(_proc, p)) _proc = null;
      });
      _proc = p;
    } catch (_) {
      _proc = null;
    }
  }

  void _onLine(String line) {
    final i = line.indexOf('\t');
    if (i < 0) return;
    final tag = line.substring(0, i);
    final text = line.substring(i + 1);
    if ((tag == 'PLAY' || tag == 'OK') && busy.value == text) {
      busy.value = null;
    }
  }

  /// 朗读一段文本（英文单词/句子）；[sid] 可指定 Kokoro 音色（47=中文女声）。
  void speak(String text, {int? sid}) {
    final t = text.trim();
    if (t.isEmpty) return;
    busy.value = t;
    final payload = sid == null ? t : jsonEncode({'text': t, 'sid': sid});
    final p = _proc;
    if (p == null) {
      start().then((_) => _write(payload));
    } else {
      _write(payload);
    }
  }

  void _write(String payload) {
    try {
      _proc?.stdin.writeln(payload);
    } catch (_) {
      _proc = null;
      busy.value = null;
    }
  }

  void stop() {
    _proc?.kill();
    _proc = null;
    busy.value = null;
  }
}
