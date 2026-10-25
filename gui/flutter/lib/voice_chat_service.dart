import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 一条口语对话消息（英文 + 中文译文）。
final class SpeechMessage {
  SpeechMessage({
    required this.isUser,
    required this.en,
    required this.zh,
    this.opening = false,
    this.topic = '',
  });

  final bool isUser;
  String en;
  String zh;
  final bool opening;
  final String topic;
}

/// 口语对话服务：懒启动 `tools/voice_chat_server.py`，
/// 本地 ASR/TTS + 可切 LLM（默认 DeepSeek，有 key 时）。
final class VoiceChatService {
  VoiceChatService({required this.onUpdate});

  final void Function() onUpdate;

  final List<SpeechMessage> messages = [];
  String status = '';
  String statusState = 'idle';
  String requestedTopic = '';
  String topic = '';
  String backend = '';
  bool active = false;
  String? error;

  Process? _proc;
  String? _root;
  final List<String> _stderr = [];

  String? _findRoot() {
    for (final c in ['.', '/opt/WordCard']) {
      if (File('$c/tools/voice_chat_server.py').existsSync()) return c;
    }
    return null;
  }

  Future<void> _ensure() async {
    if (_proc != null) return;
    _root ??= _findRoot();
    if (_root == null) throw StateError('未找到 tools/voice_chat_server.py');
    final p = await Process.start(
      'python3',
      ['$_root/tools/voice_chat_server.py'],
      workingDirectory: _root,
    );
    _proc = p;
    p.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((l) {
      _stderr.add(l);
      if (_stderr.length > 60) _stderr.removeAt(0);
    });
    p.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine, onDone: () {
      if (identical(_proc, p)) {
        _proc = null;
        active = false;
        if (status.isEmpty) status = '服务已退出';
        onUpdate();
      }
    });
    p.exitCode.then((_) {
      if (identical(_proc, p)) _proc = null;
    });
  }

  void _onLine(String line) {
    if (line.trim().isEmpty) return;
    Map<String, dynamic> d;
    try {
      d = json.decode(line) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch ('${d['event']}') {
      case 'ready':
        backend = '${d['backend'] ?? ''}';
        break;
      case 'state':
        statusState = '${d['state'] ?? ''}';
        status = '${d['text'] ?? ''}';
        if (statusState == 'ended') active = false;
        break;
      case 'user':
        messages.add(SpeechMessage(
          isUser: true,
          en: '${d['en'] ?? ''}',
          zh: '${d['zh'] ?? ''}',
        ));
        break;
      case 'assistant':
        final t = '${d['topic'] ?? ''}';
        if (t.isNotEmpty) topic = t;
        messages.add(SpeechMessage(
          isUser: false,
          en: '${d['en'] ?? ''}',
          zh: '${d['zh'] ?? ''}',
          opening: d['opening'] == true,
          topic: t,
        ));
        break;
      case 'error':
        error = '${d['message'] ?? '未知错误'}';
        active = false;
        status = error!;
        statusState = 'error';
        break;
      case 'end':
        active = false;
        break;
    }
    onUpdate();
  }

  void _send(Map<String, dynamic> m) {
    try {
      _proc?.stdin.writeln(json.encode(m));
    } catch (_) {
      _proc = null;
    }
  }

  Future<void> start({
    required String topic,
    required bool aiFirst,
  }) async {
    await _ensure();
    messages.clear();
    error = null;
    requestedTopic = topic.trim();
    this.topic = requestedTopic;
    active = true;
    statusState = 'thinking';
    status = aiFirst ? '外教正在准备开场…' : '正在打开麦克风…';
    onUpdate();
    _send({'cmd': 'start', 'topic': requestedTopic, 'ai_first': aiFirst});
  }

  void stop() {
    _send({'cmd': 'stop'});
    active = false;
    statusState = 'ended';
    status = '对话结束';
    onUpdate();
  }

  void sendText(String text) {
    final t = text.trim();
    if (t.isEmpty || !active) return;
    error = null;
    statusState = 'thinking';
    status = '外教正在回应…';
    onUpdate();
    _send({'cmd': 'user_text', 'text': t});
  }

  void aiOpen() {
    if (!active) return;
    _send({'cmd': 'ai_open'});
  }

  void replay() {
    if (!active) return;
    _send({'cmd': 'replay'});
  }

  Map<String, dynamic> state() => {
        'page': 'speech',
        'active': active,
        'status': status,
        'state': statusState,
        'requestedTopic': requestedTopic,
        'topic': topic,
        'backend': backend,
        'error': error,
        'messages': [
          for (final m in messages)
            {'role': m.isUser ? 'user' : 'assistant', 'en': m.en, 'zh': m.zh},
        ],
      };

  Future<void> dispose() async {
    _send({'cmd': 'stop'});
    await Future<void>.delayed(const Duration(milliseconds: 80));
    try {
      await _proc?.stdin.close();
    } catch (_) {}
    _proc?.kill();
    _proc = null;
    active = false;
  }
}
