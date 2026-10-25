import 'dart:async';

import 'package:flutter/material.dart';

import '../automation/automation.dart';
import '../theme/app_theme.dart';
import '../theme/fonts.dart';
import '../tts.dart';
import '../voice_chat_service.dart';

/// 「口语」页：英语口语对话（本地 ASR/TTS + 可切 LLM）。
///
/// 语料来自 `tools/voice_chat_server.py`：本地 SenseVoice 识别、Kokoro 朗读，
/// 对话由 DeepSeek（有 key 时）或本地 LLM 生成；双方英文都自动带中文译文。
class SpeechPage extends StatefulWidget {
  const SpeechPage({super.key});

  @override
  State<SpeechPage> createState() => _SpeechPageState();
}

class _SpeechPageState extends State<SpeechPage> {
  late final VoiceChatService _service;
  final ScrollController _scroll = ScrollController();
  final TextEditingController _topic = TextEditingController();
  final TextEditingController _text = TextEditingController();

  bool _aiFirst = true;
  bool _showStart = true;

  @override
  void initState() {
    super.initState();
    _service = VoiceChatService(onUpdate: _onUpdate);
    TtsService.instance.start();
    TtsService.instance.busy.addListener(_onTtsBusy);
    _registerAutomation();
  }

  @override
  void dispose() {
    TtsService.instance.busy.removeListener(_onTtsBusy);
    unawaited(_service.dispose());
    _scroll.dispose();
    _topic.dispose();
    _text.dispose();
    super.dispose();
  }

  void _registerAutomation() {
    final a = Automation.instance;
    a.registerFn('speech.start', (args) {
      if (!mounted) return false;
      final topic = '${args['topic'] ?? args['scenario'] ?? ''}';
      final aiFirst = args['ai_first'] as bool? ?? true;
      startConversation(topic: topic, aiFirst: aiFirst);
      return true;
    });
    a.registerFn('speech.stop', (_) {
      if (!mounted) return false;
      _service.stop();
      return true;
    });
    a.registerFn('speech.userText', (args) {
      if (!mounted) return false;
      final text = '${args['text'] ?? ''}';
      _service.sendText(text);
      return true;
    });
    a.registerFn('speech.aiOpen', (_) {
      if (!mounted) return false;
      _service.aiOpen();
      return true;
    });
    a.registerFn('speech.replay', (_) {
      if (!mounted) return false;
      _service.replay();
      return true;
    });
    a.registerFn('speech.play', (args) {
      if (!mounted) return false;
      final text = '${args['text'] ?? ''}'.trim();
      final sid = (args['sid'] as num?)?.toInt() ?? 3;
      if (text.isEmpty) return false;
      TtsService.instance.speak(text, sid: sid);
      return true;
    });
    a.registerFn('speech.state', (_) => _service.state());
  }

  void _onTtsBusy() {
    if (mounted) setState(() {});
  }

  void _onUpdate() {
    if (!mounted) return;
    setState(() {});
    Automation.instance.updateState(_service.state());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> startConversation({
    required String topic,
    required bool aiFirst,
  }) async {
    if (!mounted) return;
    setState(() {
      _aiFirst = aiFirst;
      _showStart = false;
    });
    await _service.start(topic: topic, aiFirst: aiFirst);
  }

  void _newConversation() {
    _service.stop();
    setState(() {
      _showStart = true;
    });
  }

  void _sendText() {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _text.clear();
    _service.sendText(t);
  }

  @override
  Widget build(BuildContext context) {
    if (_showStart) return _start(context);
    return _conversation(context);
  }

  // ── 开始界面 ───────────────────────────────────────────
  Widget _start(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.record_voice_over_outlined,
                  size: 30, color: Kami.inkBlue),
              const SizedBox(height: 10),
              const Text(
                '英语口语 · 外教陪练',
                style: TextStyle(
                    fontFamily: AppFonts.tsangerJinKai,
                    fontSize: 28,
                    fontWeight: FontWeight.w500,
                    color: Kami.ink),
              ),
              const SizedBox(height: 8),
              Text(
                '和外教用英语聊一个贴近生活或时事的话题。输入主题，或留空让外教给一个默认主题；'
                '双方英文都会自动附上中文译文。',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: Kami.muted, height: 1.7),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Kami.surface,
                  border: Border.all(color: Kami.hairline),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('对话主题',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: Kami.muted)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _topic,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                        hintText: '例如：最近看的一部电影 / 周末计划 / 人工智能对工作的影响 / 旅行经历',
                        helperText: '留空则由外教（DeepSeek）选一个具体主题',
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _aiFirst,
                      title: const Text('让外教先开场'),
                      subtitle: Text(
                        _aiFirst ? '外教先说第一句，然后你接话' : '你先说第一句',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Kami.muted),
                      ),
                      onChanged: (v) => setState(() => _aiFirst = v),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Kami.inkBlue,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => startConversation(
                              topic: _topic.text.trim(), aiFirst: _aiFirst),
                          icon: const Icon(Icons.mic, size: 18),
                          label: const Text('开始对话'),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '本地识别/朗读 · DeepSeek 生成',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Kami.faint),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '提示：点击开始后，看到「在听你说…」直接说英语即可，停顿会自动结束这一轮；'
                '外教说话时麦克风暂停，避免回声。也可以打字作为备用输入。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: Kami.faint, height: 1.7),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 对话界面 ───────────────────────────────────────────
  Widget _conversation(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
          child: Row(
            children: [
              const Icon(Icons.record_voice_over_outlined,
                  size: 20, color: Kami.inkBlue),
              const SizedBox(width: 8),
              const Text(
                '英语口语 · 外教陪练',
                style: TextStyle(
                    fontFamily: AppFonts.tsangerJinKai,
                    fontSize: 19,
                    fontWeight: FontWeight.w500,
                    color: Kami.ink),
              ),
              const SizedBox(width: 10),
              if (_service.topic.isNotEmpty) ...[
                Flexible(
                  child: Text(
                    '话题：${_service.topic}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        theme.textTheme.bodySmall?.copyWith(color: Kami.muted),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              if (_service.backend.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Kami.tint,
                    border: Border.all(color: Kami.hairline),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _service.backend == 'deepseek' ? 'DeepSeek' : '本地 LLM',
                    style:
                        theme.textTheme.labelSmall?.copyWith(color: Kami.muted),
                  ),
                ),
              const Spacer(),
              TextButton.icon(
                onPressed: _service.aiOpen,
                icon: const Icon(Icons.lightbulb_outline, size: 16),
                label: const Text('外教先说'),
              ),
              TextButton.icon(
                onPressed: _newConversation,
                icon: const Icon(Icons.add_comment_outlined, size: 16),
                label: const Text('新对话'),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Kami.hairline),
        Expanded(
          child: _service.messages.isEmpty
              ? Center(
                  child: Text(
                      _service.status.isEmpty ? '准备中…' : _service.status,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Kami.muted)),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  itemCount: _service.messages.length,
                  itemBuilder: (context, i) => _bubble(_service.messages[i]),
                ),
        ),
        _composer(context),
      ],
    );
  }

  Widget _bubble(SpeechMessage m) {
    final theme = Theme.of(context);
    final isUser = m.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 700),
        margin: const EdgeInsets.symmetric(vertical: 7),
        padding: const EdgeInsets.fromLTRB(15, 11, 15, 12),
        decoration: BoxDecoration(
          color: isUser ? Kami.tint : Kami.surface,
          border: Border.all(color: Kami.hairline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(isUser ? '你' : '外教',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: isUser ? Kami.inkBlue : Kami.faint)),
                if (m.opening) ...[
                  const SizedBox(width: 6),
                  Text('外教开场',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: Kami.faint)),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => TtsService.instance.speak(m.en, sid: 3),
                      child: Text(
                        m.en,
                        style: const TextStyle(
                            fontFamily: AppFonts.tsangerJinKai,
                            fontSize: 17.5,
                            height: 1.65,
                            color: Kami.ink),
                      ),
                    ),
                  ),
                ),
                _playButton(m.en, 3),
              ],
            ),
            if (m.zh.isNotEmpty) ...[
              const SizedBox(height: 2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => TtsService.instance.speak(m.zh, sid: 47),
                        child: Text(
                          m.zh,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: AppFonts.tsangerJinKai,
                            fontSize: 14.5,
                            height: 1.7,
                            color: Kami.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                  _playButton(m.zh, 47, small: true),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _playButton(String text, int sid, {bool small = false}) {
    final busy = TtsService.instance.busy.value == text;
    return IconButton(
      tooltip: busy ? '播放中…' : '播放这句',
      visualDensity: VisualDensity.compact,
      constraints: BoxConstraints(minWidth: small ? 26 : 30, minHeight: 26),
      padding: EdgeInsets.zero,
      icon: busy
          ? const SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 1.5))
          : Icon(Icons.volume_up_outlined,
              size: small ? 15 : 17, color: Kami.faint),
      onPressed: busy ? null : () => TtsService.instance.speak(text, sid: sid),
    );
  }

  Widget _composer(BuildContext context) {
    final theme = Theme.of(context);
    final active = _service.active;
    return Container(
      decoration: const BoxDecoration(
        color: Kami.parchment,
        border: Border(top: BorderSide(color: Kami.hairline)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      child: Column(
        children: [
          Row(
            children: [
              _statusIcon(),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _service.status.isEmpty
                      ? (active ? '准备中…' : '对话已结束')
                      : _service.status,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _service.error != null ? Kami.error : Kami.muted,
                  ),
                ),
              ),
              if (active)
                TextButton.icon(
                  onPressed: _service.replay,
                  icon: const Icon(Icons.volume_up_outlined, size: 16),
                  label: const Text('重听'),
                ),
              if (active)
                TextButton.icon(
                  onPressed: _service.stop,
                  icon: const Icon(Icons.stop_circle_outlined, size: 16),
                  label: const Text('结束'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  enabled: active,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendText(),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: active ? '也可以打字（英文或中文）…' : '对话已结束',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: '发送',
                onPressed: active ? _sendText : null,
                icon: const Icon(Icons.send, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusIcon() {
    switch (_service.statusState) {
      case 'listening':
        return const Icon(Icons.mic, size: 18, color: Kami.inkBlue);
      case 'thinking':
        return const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 1.8));
      case 'speaking':
        return const Icon(Icons.volume_up, size: 18, color: Kami.inkBlue);
      case 'error':
        return const Icon(Icons.error_outline, size: 18, color: Kami.error);
      case 'ended':
        return const Icon(Icons.stop_circle_outlined,
            size: 18, color: Kami.faint);
      default:
        return const Icon(Icons.mic_off_outlined, size: 18, color: Kami.faint);
    }
  }
}
