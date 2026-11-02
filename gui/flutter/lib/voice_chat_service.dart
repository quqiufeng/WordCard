import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'llama_service.dart';
import 'memo_service.dart';
import 'native_paths.dart';
import 'tts.dart';

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

/// 口语对话服务：本地 llama-server 生成英文回复，wc_voice 做 TTS。
final class VoiceChatService {
  VoiceChatService({required this.onUpdate});

  final void Function() onUpdate;

  final List<SpeechMessage> messages = [];
  String status = '';
  String statusState = 'idle';
  String requestedTopic = '';
  String topic = '';
  String backend = 'local';
  bool active = false;
  String? error;
  bool _busy = false;

  String get _url =>
      Platform.environment['WC_LLM_URL'] ?? 'http://127.0.0.1:8081';

  String get _model =>
      Platform.environment['WC_CHAT_MODEL'] ??
      Platform.environment['DEEPSEEK_MODEL'] ??
      'deepseek-flash';

  String _systemPrompt() {
    final t = topic.isEmpty ? 'daily life' : topic;
    return 'You are a friendly English conversation tutor for a Chinese learner. '
        'Topic: $t. Reply in English only, in 1-2 natural sentences, and end '
        'with a short follow-up question. Do not translate.';
  }

  Future<String> _chat(String userText, {bool includeUser = true}) async {
    final recent = messages.length > 12
        ? messages.sublist(messages.length - 12)
        : messages;
    final history = [
      for (final m in recent)
        {'role': m.isUser ? 'user' : 'assistant', 'content': m.en},
    ];
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3);
    try {
      final req = await client.postUrl(
          Uri.parse('$_url/v1/chat/completions'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'model': _model,
        'temperature': 0.7,
        'messages': [
          {'role': 'system', 'content': _systemPrompt()},
          ...history,
          if (includeUser) {'role': 'user', 'content': userText},
        ],
      }));
      final res = await req.close().timeout(const Duration(seconds: 120));
      final body = await utf8.decoder.bind(res).join();
      final doc = jsonDecode(body) as Map<String, dynamic>;
      final choices = doc['choices'] as List?;
      final first = choices?.isNotEmpty == true ? choices!.first : null;
      final msg = first is Map ? first['message'] : null;
      final content = msg is Map ? '${msg['content'] ?? ''}' : '';
      return content.trim();
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _translate(String en) async {
    if (en.trim().isEmpty) return '';
    final c = Completer<String>();
    MemoService.instance.translateText(en, (zh) {
      if (!c.isCompleted) c.complete(zh.trim());
    });
    try {
      return await c.future.timeout(const Duration(seconds: 45));
    } catch (_) {
      return '';
    }
  }

  void _update() => onUpdate();

  Future<void> _ensureReady() async {
    if (!await LlamaService.instance.ensure()) {
      throw StateError('本地模型未就绪');
    }
  }

  Future<void> start({
    required String topic,
    required bool aiFirst,
  }) async {
    messages.clear();
    error = null;
    requestedTopic = topic.trim();
    this.topic = requestedTopic.isEmpty ? 'daily life' : requestedTopic;
    active = true;
    statusState = 'thinking';
    status = aiFirst ? '外教正在准备开场…' : '输入英文开始对话';
    _update();
    try {
      await _ensureReady();
      if (aiFirst) await aiOpen();
    } catch (e) {
      error = '$e';
      active = false;
      status = error!;
      statusState = 'error';
      _update();
    }
  }

  Future<void> aiOpen() async {
    if (!active || _busy) return;
    _busy = true;
    statusState = 'thinking';
    status = '外教正在回应…';
    _update();
    try {
      final en = await _chat(
          'Start the conversation now with a short greeting and a question.');
      if (en.isEmpty) throw StateError('模型没有返回内容');
      final zh = await _translate(en);
      messages.add(SpeechMessage(
        isUser: false,
        en: en,
        zh: zh,
        opening: true,
        topic: topic,
      ));
      TtsService.instance.speak(en);
      status = '输入英文继续对话';
      statusState = 'listening';
    } catch (e) {
      error = '$e';
      status = error!;
      statusState = 'error';
    } finally {
      _busy = false;
      _update();
    }
  }

  Future<void> sendText(String text) async {
    final t = text.trim();
    if (t.isEmpty || !active || _busy) return;
    messages.add(SpeechMessage(isUser: true, en: t, zh: ''));
    _busy = true;
    error = null;
    statusState = 'thinking';
    status = '外教正在回应…';
    _update();
    try {
      final en = await _chat(t, includeUser: false);
      if (en.isEmpty) throw StateError('模型没有返回内容');
      final zh = await _translate(en);
      messages.add(SpeechMessage(
        isUser: false,
        en: en,
        zh: zh,
        topic: topic,
      ));
      TtsService.instance.speak(en);
      status = '输入英文继续对话';
      statusState = 'listening';
    } catch (e) {
      error = '$e';
      status = error!;
      statusState = 'error';
    } finally {
      _busy = false;
      _update();
    }
  }

  Future<void> listen() async {
    if (!active || _busy) return;
    final root = NativePaths.findFile('native/staticpy/voice/wc_voice');
    if (root == null) {
      error = '未找到 wc_voice';
      statusState = 'error';
      status = error!;
      _update();
      return;
    }
    _busy = true;
    statusState = 'listening';
    status = '正在录音（4 秒）…';
    _update();
    final wav = File(
        '${Directory.systemTemp.path}/wordcard_mic_${DateTime.now().microsecondsSinceEpoch}.wav');
    try {
      final env = {
        ...Platform.environment,
        'LD_LIBRARY_PATH': '$root/native/staticpy/voice:$root/voice/libs',
      };
      final bin = '$root/native/staticpy/voice/wc_voice';
      final rec = await Process.run(
        bin,
        [
          'record',
          wav.path,
          '4',
          '16000',
          Platform.environment['WC_MIC_DEVICE'] ?? 'default',
        ],
        environment: env,
      ).timeout(const Duration(seconds: 20));
      if (rec.exitCode != 0 || !wav.existsSync()) {
        throw StateError('录音失败');
      }
      status = '识别中…';
      _update();
      final asr = await Process.run(
        bin,
        ['asr', wav.path, 'en'],
        environment: env,
      ).timeout(const Duration(seconds: 60));
      final text = (asr.stdout as String).trim();
      _busy = false;
      if (text.isEmpty) {
        status = '没听清，再说一次';
        statusState = 'listening';
        _update();
        return;
      }
      await sendText(text);
    } catch (e) {
      error = '$e';
      status = error!;
      statusState = 'error';
      _busy = false;
      _update();
    } finally {
      if (wav.existsSync()) wav.deleteSync();
    }
  }

  void replay() {
    final last = messages.lastWhere(
      (m) => !m.isUser,
      orElse: () => SpeechMessage(isUser: false, en: '', zh: ''),
    );
    if (last.en.isNotEmpty) TtsService.instance.speak(last.en);
  }

  void stop() {
    active = false;
    _busy = false;
    statusState = 'ended';
    status = '对话结束';
    _update();
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
    stop();
  }
}
