import 'dart:async';
import 'dart:io';

/// 本地翻译/助记模型：按需启动 llama-server，供 wc_translate/wc_define 使用。
final class LlamaService {
  LlamaService._();

  static final LlamaService instance = LlamaService._();

  Process? _proc;
  Future<bool>? _starting;

  String get _url =>
      Platform.environment['WC_LLM_URL'] ?? 'http://127.0.0.1:8081';

  String get _bin =>
      Platform.environment['LLAMA_SERVER'] ??
      '/opt/llama.cpp/build/bin/llama-server';

  String? get _model {
    final explicit = Platform.environment['WC_LLM_MODEL'];
    if (explicit != null && explicit.isNotEmpty) return explicit;
    for (final m in [
      '/data/models/Hunyuan-MT-7B-Q4_K_M.gguf',
      '/data/models/image/Qwen3-4B-Instruct-2507-Q4_K_M.gguf',
    ]) {
      if (File(m).existsSync()) return m;
    }
    return null;
  }

  Future<bool> ensure() {
    if (_starting != null) return _starting!;
    final f = _ensure();
    _starting = f;
    return f.whenComplete(() => _starting = null);
  }

  Future<bool> _ensure() async {
    if (await _healthy()) return true;
    final model = _model;
    if (model == null || !File(_bin).existsSync()) return false;
    try {
      final log = File('/tmp/opencode/wordcard_llama.log').openWrite();
      final p = await Process.start(
        _bin,
        [
          '-m', model,
          '-ngl', '99',
          '-c', '4096',
          '--host', '127.0.0.1',
          '--port', '8081',
        ],
      );
      _proc = p;
      p.stdout.listen(log.write);
      p.stderr.listen(log.write);
      p.exitCode.then((_) {
        if (identical(_proc, p)) _proc = null;
      });
      for (var i = 0; i < 180; i++) {
        if (await _healthy()) return true;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      p.kill();
    } catch (_) {}
    return false;
  }

  Future<bool> _healthy() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 1);
    try {
      final uri = Uri.parse('$_url/health');
      final req = await client.getUrl(uri);
      final res = await req.close().timeout(const Duration(seconds: 2));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  void stop() {
    _proc?.kill();
    _proc = null;
  }
}
