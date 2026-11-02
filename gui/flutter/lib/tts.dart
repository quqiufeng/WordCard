import 'dart:io';

import 'package:flutter/foundation.dart';

/// TTS 客户端：调用 StaticPy 原生 `wc_voice say`，不再依赖 Python 常驻服务。
final class TtsService {
  TtsService._();

  static final TtsService instance = TtsService._();

  final ValueNotifier<String?> busy = ValueNotifier<String?>(null);

  Process? _proc;
  String? _root;
  String? _binary;

  String? _findRoot() {
    for (final c in ['.', '/opt/WordCard']) {
      if (File('$c/native/staticpy/voice/wc_voice').existsSync()) return c;
    }
    return null;
  }

  Future<void> start() async {
    _root ??= _findRoot();
    if (_root == null) return;
    _binary ??= '$_root/native/staticpy/voice/wc_voice';
  }

  void speak(String text, {int? sid}) {
    final t = text.trim();
    if (t.isEmpty) return;
    busy.value = t;
    _run(t, sid ?? 3);
  }

  Future<void> _run(String text, int sid) async {
    await start();
    final bin = _binary;
    if (bin == null) {
      busy.value = null;
      return;
    }
    final old = _proc;
    _proc = null;
    old?.kill();
    try {
      final p = await Process.start(
        bin,
        ['say', text, '$sid'],
        environment: {
          ...Platform.environment,
          'LD_LIBRARY_PATH':
              '$_root/native/staticpy/voice:$_root/voice/libs',
        },
      );
      _proc = p;
      p.stdout.drain<void>();
      p.stderr.drain<void>();
      await p.exitCode;
      if (identical(_proc, p)) {
        _proc = null;
        if (busy.value == text) busy.value = null;
      }
    } catch (_) {
      if (busy.value == text) busy.value = null;
    }
  }

  void stop() {
    _proc?.kill();
    _proc = null;
    busy.value = null;
  }
}
