import 'dart:io';

import 'package:flutter/foundation.dart';

import 'native_paths.dart';

/// TTS 客户端：调用 StaticPy 原生 `wc_voice`，并按文本缓存 wav。
final class TtsService {
  TtsService._();

  static final TtsService instance = TtsService._();

  final ValueNotifier<String?> busy = ValueNotifier<String?>(null);

  Process? _proc;
  String? _root;
  String? _binary;

  String? _findRoot() =>
      NativePaths.findFile('native/staticpy/voice/wc_voice');

  Future<void> start() async {
    _root ??= _findRoot();
    if (_root == null) return;
    _binary ??= '$_root/native/staticpy/voice/wc_voice';
  }

  String _hash(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16);
  }

  String _cachePath(String text, int sid) {
    final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    final dir = Directory('$home/.cache/wordcard/tts')..createSync(recursive: true);
    return '${dir.path}/${_hash('$sid:$text')}.wav';
  }

  Map<String, String> _env() => {
        ...Platform.environment,
        'LD_LIBRARY_PATH':
            '$_root/native/staticpy/voice:$_root/voice/libs',
      };

  void speak(String text, {int? sid}) {
    final t = text.trim();
    if (t.isEmpty) return;
    busy.value = t;
    _run(t, sid ?? 3);
  }

  Future<int> _exec(List<String> args) async {
    final p = await Process.start(_binary!, args, environment: _env());
    _proc = p;
    p.stdout.drain<void>();
    p.stderr.drain<void>();
    final code = await p.exitCode;
    if (identical(_proc, p)) _proc = null;
    return code;
  }

  Future<void> _run(String text, int sid) async {
    await start();
    if (_binary == null) {
      busy.value = null;
      return;
    }
    final old = _proc;
    _proc = null;
    old?.kill();
    try {
      final wav = _cachePath(text, sid);
      if (!File(wav).existsSync()) {
        final code = await _exec(['tts', text, wav, '$sid']);
        if (code != 0 || !File(wav).existsSync()) {
          await _exec(['say', text, '$sid']);
          return;
        }
      }
      await _exec(['play', wav]);
    } catch (_) {
    } finally {
      if (busy.value == text) busy.value = null;
    }
  }

  void stop() {
    _proc?.kill();
    _proc = null;
    busy.value = null;
  }
}
