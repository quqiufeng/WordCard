#!/usr/bin/env python3
"""voice_chat_server.py — 英语口语对话服务（本地 ASR/TTS + 独立 opencode 大脑）。

大脑：tmux wordcard-brain（opencode serve :4098 + tui），与 my-agent 的 4097 分开。
学习者的英文通过 /tui/append-prompt + /tui/submit-prompt 送入当前 TUI 会话
（不再直接 POST 到 /session/{id}/message），AI 回复从会话消息读回，
再经本地 say.sh 播到小音响。

App 通过 stdin/stdout JSON Lines 驱动：
  {"cmd":"start","topic":"绿色能源技术转让","ai_first":true}
  {"cmd":"stop"} / {"cmd":"user_text","text":"...","speak":true}
  {"cmd":"ai_open"} / {"cmd":"replay"} / {"cmd":"status"}

事件：
  {"event":"ready","scenarios":[...]}
  {"event":"state","state":"listening|thinking|speaking|idle|error","text":"..."}
  {"event":"user","en":"...","zh":"..."}
  {"event":"assistant","en":"...","zh":"...","opening":false}
  {"event":"error","message":"..."}
  {"event":"end"}

语音链路复用 voice/agent（从 /opt/my-agent 复制）：
  listen/listen --once --no-forward  → SenseVoice ASR
  voice/agent/say.sh                → Kokoro TTS → 小音响
"""

import json
import os
import queue
import re
import shutil
import subprocess
import sys
import threading
import time
import traceback
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

import translate  # noqa: E402

VOICE_DIR = os.path.join(ROOT, 'voice', 'agent')
SAY = os.path.join(VOICE_DIR, 'say.sh')
LISTEN = os.path.join(VOICE_DIR, 'listen', 'listen')
DEEPSEEK_HELPER = os.path.join(ROOT, 'tools', 'deepseek_chat.py')
BRAIN_URL = (os.environ.get('WC_BRAIN_URL') or 'http://127.0.0.1:4098').rstrip('/')

SCENARIO_DESC = ('a friendly one-on-one English speaking lesson with a foreign tutor, '
                 'using everyday and current-affairs topics')

SYSTEM = """You are a friendly foreign English tutor (外教) giving a one-on-one bilingual
speaking lesson. Scenario: {scenario}. Both sides speak English; every English message must
be shown with a faithful Chinese translation.

Requested topic from the learner: {requested}
Current topic: {topic}

Rules:
- Be warm, encouraging and conversational — like a real foreign tutor, not a formal diplomat.
- Choose topics from real life and current affairs: daily life, work, study, travel, food,
  health, technology, environment, culture, recent news, personal experiences, etc.
- If the learner provided a requested topic, use it as the conversation topic.
- If the learner did not provide a topic, choose a concrete, interesting default topic
  yourself and return it in the "topic" field. Do not ask the learner to choose a topic.
- When opening, introduce the chosen topic naturally in the first sentence.
- Keep the same topic unless the learner changes it. Speak natural, everyday English.
- Keep each reply to 1-3 sentences; ask open follow-up questions to get the learner talking.
- Do not correct grammar explicitly; model natural English and rephrase gently if useful.
- If the learner's message is unclear, politely ask them to repeat.
- Output ONLY one JSON object, with exactly these keys:
  {{"user_zh":"faithful Chinese translation of the learner's last English message (empty if none)","en":"your English reply","zh":"faithful Chinese translation of your reply","topic":"the conversation topic in Chinese (return it when you choose/confirm it)"}}
- No markdown, no code fence, no extra text.

The learner is practicing spoken English. Be friendly, patient and encouraging.
"""


def emit(obj):
    try:
        print(json.dumps(obj, ensure_ascii=False), flush=True)
    except Exception:
        pass


def _brain_http(method, path, body=None, timeout=180):
    data = json.dumps(body, ensure_ascii=False).encode() if body is not None else None
    req = urllib.request.Request(BRAIN_URL + path, data=data, method=method,
                                 headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        raw = r.read().decode('utf-8', 'replace')
    return json.loads(raw) if raw.strip() else {}


def _brain_health():
    try:
        d = _brain_http('GET', '/global/health', timeout=3)
        return bool(d.get('healthy'))
    except Exception:
        return False


def _brain_ensure():
    if _brain_health():
        return True
    script = os.path.join(ROOT, 'tools', 'wordcard_brain.sh')
    if os.path.exists(script):
        try:
            subprocess.run([script], timeout=70, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL)
        except Exception:
            pass
    for _ in range(20):
        if _brain_health():
            return True
        time.sleep(0.5)
    return False


def _strip_fence(s):
    s = s.strip()
    if s.startswith('```'):
        s = re.sub(r'^```[a-zA-Z]*\s*', '', s)
        s = re.sub(r'\s*```$', '', s)
    return s.strip()


def _parse_reply(raw):
    raw = _strip_fence(raw)
    try:
        d = json.loads(raw)
    except Exception:
        m = re.search(r'\{[\s\S]*\}', raw)
        d = json.loads(m.group(0)) if m else None
    if not isinstance(d, dict):
        raise ValueError('not a JSON object')
    return {
        'user_zh': str(d.get('user_zh') or '').strip(),
        'en': str(d.get('en') or '').strip(),
        'zh': str(d.get('zh') or '').strip(),
        'topic': str(d.get('topic') or '').strip(),
    }


class VoiceChat:
    def __init__(self):
        self.lock = threading.Lock()
        self.stop_evt = threading.Event()
        self.thread = None
        self.listener = None
        self.speaker = None
        self.pending = queue.Queue()
        self.pending_ai_open = threading.Event()
        self.pending_replay = threading.Event()
        self.history = []
        self.requested_topic = ''
        self.topic = ''
        self._use_systemd = False
        self.brain_sid = ''
        self.brain_turns = 0
        self.active = False
        self.last_ai = ''
        self.messages = 0

    # ── 对外命令 ─────────────────────────────────────────
    def start(self, topic, ai_first):
        self.stop()
        topic = (topic or '').strip()
        self.requested_topic = topic
        self.topic = topic
        self.history = []
        self.last_ai = ''
        self.messages = 0
        self.brain_turns = 0
        self.stop_evt.clear()
        self.pending_ai_open.clear()
        self.pending_replay.clear()
        self.active = True
        self.thread = threading.Thread(
            target=self._run, args=(bool(ai_first),), daemon=True)
        self.thread.start()

    def stop(self):
        self.active = False
        self.stop_evt.set()
        self._kill_proc('listener')
        self._kill_proc('speaker')
        t = self.thread
        if t and t.is_alive() and t is not threading.current_thread():
            t.join(timeout=2)
        self.thread = None

    def _kill_proc(self, name):
        with self.lock:
            p = getattr(self, name)
            setattr(self, name, None)
        if p and p.poll() is None:
            try:
                p.terminate()
            except Exception:
                pass
            try:
                p.wait(timeout=2)
            except Exception:
                try:
                    p.kill()
                except Exception:
                    pass

    # ── 会话主循环 ───────────────────────────────────────
    def _run(self, ai_first):
        try:
            self.brain_sid = ''
            brain_ok = _brain_ensure()
            if brain_ok:
                self.brain_sid = self._brain_session()
            if not brain_ok and not translate.deepseek_available():
                emit({'event': 'error',
                      'message': 'opencode 大脑与 DeepSeek API 均不可用'})
                emit({'event': 'state', 'state': 'idle'})
                return
            if ai_first:
                self._ai_opening()
            while not self.stop_evt.is_set():
                if self.pending_ai_open.is_set():
                    self.pending_ai_open.clear()
                    self._ai_opening()
                    continue
                if self.pending_replay.is_set():
                    self.pending_replay.clear()
                    if self.last_ai:
                        self._speak(self.last_ai)
                    continue
                text = None
                try:
                    text = self.pending.get_nowait()
                except queue.Empty:
                    pass
                if not text:
                    emit({'event': 'state', 'state': 'listening',
                          'text': '在听你说…'})
                    text = self._listen_once()
                if self.stop_evt.is_set():
                    break
                if not text:
                    # 打字输入可能在监听期间注入；优先处理它
                    try:
                        text = self.pending.get_nowait()
                    except queue.Empty:
                        text = None
                if not text:
                    emit({'event': 'state', 'state': 'idle',
                          'text': '没听清，可以再说一次或打字'})
                    # 继续监听，不结束会话
                    time.sleep(0.3)
                    continue
                self._user_turn(text)
        except Exception as e:
            emit({'event': 'error', 'message': f'{e}'})
            traceback.print_exc(file=sys.stderr)
        finally:
            self.active = False
            self._kill_proc('listener')
            self._kill_proc('speaker')
            emit({'event': 'state', 'state': 'ended', 'text': '对话结束'})
            emit({'event': 'end'})

    def _brain_session(self):
        """在 opencode serve 里新建一个口语陪练会话，并让 TUI 切过去。"""
        title = f'WordCard 口语陪练 {time.strftime("%m-%d %H:%M")}'
        body = {
            'title': title,
            'model': {'providerID': 'deepseek', 'id': 'deepseek-flash'},
        }
        sid = ''
        for path in (f'/session?directory={urllib.parse.quote(ROOT)}', '/session'):
            try:
                resp = _brain_http('POST', path, body, timeout=30)
                sid = str(resp.get('id') or '')
                if sid:
                    break
            except Exception:
                continue
        if not sid:
            return ''
        try:
            _brain_http('POST', '/tui/select-session', {'sessionID': sid}, timeout=5)
        except Exception:
            pass
        return sid

    def _brain_messages(self):
        return _brain_http('GET', f'/session/{self.brain_sid}/message',
                           timeout=30) or []

    def _brain_ask(self, messages, opening=False):
        """把学习者英文通过 TUI 端口送入当前会话，再读回 AI 回复。

           POST /tui/append-prompt + POST /tui/submit-prompt  （不再直接
           POST /session/{id}/message 发用户文本；会话消息只读回）
        """
        if not self.brain_sid:
            raise RuntimeError('no brain session')
        system = messages[0]['content']
        user_part = messages[-1]['content']
        if self.brain_turns == 0:
            prompt = system + '\n\n' + user_part
        else:
            prompt = ('[Continue the same bilingual tutor conversation. '
                      'Reply in the same JSON format.]\n'
                      'Learner: ' + user_part)
        before = self._brain_messages()
        before_ids = {m.get('info', {}).get('id') for m in before}
        # 选中会话后 TUI 需要一点时间切换；太快 append 会丢 prompt。
        submitted = False
        for attempt in range(2):
            _brain_http('POST', '/tui/select-session',
                        {'sessionID': self.brain_sid}, timeout=5)
            time.sleep(0.8)
            _brain_http('POST', '/tui/append-prompt', {'text': prompt}, timeout=10)
            time.sleep(0.25)
            _brain_http('POST', '/tui/submit-prompt', {}, timeout=10)
            # 先确认 prompt 进了会话（有新 user/assistant 即可），否则重投一次
            t0 = time.time()
            while time.time() - t0 < 6:
                msgs = self._brain_messages()
                changed = [m for m in msgs
                           if (m.get('info') or {}).get('id') not in before_ids]
                if changed:
                    submitted = True
                    break
                time.sleep(0.5)
            if submitted:
                break
        self.brain_turns += 1
        if not submitted:
            raise RuntimeError('TUI 没有接收到 prompt')
        deadline = time.time() + 150
        while time.time() < deadline:
            msgs = self._brain_messages()
            for m in reversed(msgs):
                info = m.get('info') or {}
                if info.get('role') != 'assistant':
                    continue
                if info.get('id') in before_ids:
                    continue
                texts = [p.get('text') for p in (m.get('parts') or [])
                         if p.get('type') == 'text' and p.get('text')]
                if not texts:
                    continue
                done = bool((info.get('time') or {}).get('completed')) or info.get('finish') is not None
                if done:
                    return texts[-1]
            time.sleep(1)
        raise RuntimeError('opencode TUI 没有返回 AI 回复')

    def _ai_opening(self):
        emit({'event': 'state', 'state': 'thinking', 'text': '外教正在想开场…'})
        messages = self._messages('', opening=True)
        reply = self._ask(messages, opening=True)
        self.last_ai = reply['en']
        if self.requested_topic:
            self.topic = self.requested_topic
        elif reply.get('topic'):
            self.topic = reply['topic']
        emit({'event': 'assistant', 'en': reply['en'], 'zh': reply['zh'],
              'topic': self.topic, 'opening': True})
        self.history.append(['', reply['en']])
        self._speak(reply['en'])

    def _user_turn(self, text):
        emit({'event': 'state', 'state': 'thinking', 'text': '外教正在回应…'})
        messages = self._messages(text, opening=False)
        reply = self._ask(messages, user_text=text)
        if reply.get('topic') and not self.topic:
            self.topic = reply['topic']
        if not reply['user_zh'] and text:
            try:
                reply['user_zh'] = translate.translate(text)
            except Exception:
                reply['user_zh'] = ''
        emit({'event': 'user', 'en': text, 'zh': reply['user_zh']})
        self.history.append([text, reply['en']])
        self.history = self.history[-8:]
        self.last_ai = reply['en']
        self.messages += 1
        emit({'event': 'assistant', 'en': reply['en'], 'zh': reply['zh'],
              'topic': self.topic})
        self._speak(reply['en'])

    def _messages(self, user_text, opening=False):
        system = SYSTEM.format(
            scenario=SCENARIO_DESC,
            requested=self.requested_topic or '(none — choose a concrete default topic)',
            topic=self.topic or '(not set yet)')
        msgs = [{'role': 'system', 'content': system}]
        for u, a in self.history[-8:]:
            if u:
                msgs.append({'role': 'user', 'content': u})
            if a:
                msgs.append({'role': 'assistant', 'content': a})
        if opening:
            extra = ('Open the bilingual English lesson like a friendly foreign tutor. '
                     'If a requested topic was provided, use it; otherwise choose a concrete '
                     'everyday/current-affairs topic and announce it. Return the topic in '
                     'the "topic" field. Do not translate anything yet; user_zh should be empty.')
            if self.history:
                extra += (' The conversation already has some history; propose a natural '
                          'new direction or a fresh angle on the existing topic.')
            msgs.append({'role': 'user', 'content': extra})
        elif user_text:
            msgs.append({'role': 'user', 'content': user_text})
        return msgs

    def _helper_call(self, payload, via_systemd=False):
        if via_systemd:
            if not shutil.which('systemd-run'):
                raise RuntimeError('systemd-run not found')
            cmd = ['systemd-run', '--user', '--pipe', '--wait', '--collect',
                   '--quiet', sys.executable, DEEPSEEK_HELPER]
        else:
            cmd = [sys.executable, DEEPSEEK_HELPER]
        p = subprocess.run(cmd, input=payload, text=True,
                           capture_output=True, timeout=180, cwd=ROOT)
        if p.returncode != 0:
            raise RuntimeError((p.stderr or p.stdout or 'helper failed').strip()[-500:])
        resp = json.loads(p.stdout)
        if not resp.get('ok'):
            raise RuntimeError(str(resp.get('error') or 'DeepSeek error'))
        return str(resp.get('text') or '')

    def _deepseek_raw(self, messages, temperature, json_mode):
        payload = json.dumps({
            'messages': messages,
            'max_tokens': 500,
            'temperature': temperature,
            'json_mode': json_mode,
        }, ensure_ascii=False)
        if self._use_systemd:
            return self._helper_call(payload, via_systemd=True)
        try:
            return self._helper_call(payload)
        except Exception as e:  # noqa: BLE001
            low = str(e).lower()
            if any(k in low for k in ('connection refused', 'urlopen', 'timed out',
                                      'connection reset')):
                # 当前 Clash/透明代理对 App 进程网络的限制：换 systemd 用户 scope 出网
                self._use_systemd = True
                return self._helper_call(payload, via_systemd=True)
            raise

    def _ask(self, messages, user_text='', opening=False):
        last_err = ''
        if self.brain_sid:
            try:
                raw = self._brain_ask(messages, opening=opening)
                r = _parse_reply(raw)
                if not r['en']:
                    raise ValueError('empty en')
                if not r['zh']:
                    r['zh'] = translate.translate(r['en'])
                return r
            except Exception as e:  # noqa: BLE001
                last_err = f'brain: {e}'
        for attempt in range(5):
            try:
                raw = self._deepseek_raw(
                    messages,
                    temperature=0.9 if opening else 0.75,
                    json_mode=(attempt < 2))
                try:
                    r = _parse_reply(raw)
                    if not r['en']:
                        raise ValueError('empty en')
                    if not r['zh']:
                        r['zh'] = translate.translate(r['en'])
                    return r
                except Exception:
                    en = _strip_fence(raw).strip()
                    if en:
                        return {'user_zh': '', 'en': en,
                                'zh': translate.translate(en), 'topic': ''}
                    last_err = 'empty response'
            except Exception as e:  # noqa: BLE001
                last_err = str(e)
            low = last_err.lower()
            if 'connection refused' in low or 'timed out' in low or 'urlopen' in low:
                time.sleep(1.0 + attempt * 1.5)
            else:
                time.sleep(0.6)
        # 网络/接口抖动：给一句自然的兜底，保持对话不中断
        return {'user_zh': '',
                'en': "Sorry, I had a brief connection hiccup — could you say that again?",
                'zh': '抱歉，刚才网络有点小问题——你能再说一遍吗？',
                'topic': ''}

    # ── 语音 ─────────────────────────────────────────────
    def _speak(self, text):
        text = (text or '').strip()
        if not text:
            return
        emit({'event': 'state', 'state': 'speaking', 'text': '外教正在说话…'})
        if os.environ.get('WC_TTS_MUTE') == '1':
            time.sleep(min(1.5, 0.08 * len(text)))
            return
        env = os.environ.copy()
        env['KOKORO_SID'] = os.environ.get('KOKORO_SID_EN', '3')
        env.setdefault('TTS_OUT', '/tmp/wordcard_voice_tts.wav')
        try:
            p = subprocess.Popen([SAY, text], env=env,
                                 stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL)
            with self.lock:
                self.speaker = p
            while p.poll() is None and not self.stop_evt.is_set():
                time.sleep(0.05)
            if p.poll() is None:
                p.terminate()
            with self.lock:
                if self.speaker is p:
                    self.speaker = None
        except Exception as e:
            emit({'event': 'error', 'message': f'TTS 失败: {e}'})

    def _listen_once(self):
        if self.stop_evt.is_set():
            return None
        env = os.environ.copy()
        env.update({
            'VOICE_ALWAYS': '1',
            'VOICE_WAKE': '',
            'SENSEVOICE_LANG': os.environ.get('WC_ASR_LANG', 'en'),
            'VOICE_SILENCE_MS': os.environ.get('WC_ASR_SILENCE_MS', '1000'),
            'VOICE_MAX_SEG_MS': os.environ.get('WC_ASR_MAX_SEG_MS', '9000'),
            'VOICE_MIC_DEV': os.environ.get('VOICE_MIC_DEV', 'plughw:2,0'),
        })
        started = time.time()
        try:
            p = subprocess.Popen([LISTEN, '--once', '--no-forward'],
                                 env=env, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, text=True)
            with self.lock:
                self.listener = p
            while p.poll() is None and not self.stop_evt.is_set():
                time.sleep(0.05)
            if p.poll() is None:
                p.terminate()
            out = p.stdout.read() if p.stdout else ''
            err = p.stderr.read() if p.stderr else ''
            try:
                p.wait(timeout=1)
            except Exception:
                p.kill()
            with self.lock:
                if self.listener is p:
                    self.listener = None
            if self.stop_evt.is_set():
                return None
            best = ''
            for line in out.splitlines():
                m = re.match(r'\s*\[识别\]\s*(.+)', line)
                if m:
                    best = m.group(1).strip()
            if best:
                return best
            # 麦克风打不开等启动失败：不要无限重启
            if time.time() - started < 2 and err.strip():
                msg = err.strip().splitlines()[-1]
                emit({'event': 'error', 'message': f'麦克风/ASR: {msg}'})
                self.stop_evt.set()
            return None
        except Exception as e:
            emit({'event': 'error', 'message': f'ASR 失败: {e}'})
            return None


def main():
    chat = VoiceChat()
    emit({'event': 'ready', 'backend': 'deepseek'})
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except Exception:
            continue
        cmd = req.get('cmd')
        if cmd == 'start':
            chat.start(req.get('topic') or req.get('scenario') or '',
                       req.get('ai_first', True))
        elif cmd == 'stop':
            chat.stop()
        elif cmd == 'user_text':
            text = str(req.get('text') or '').strip()
            if text:
                chat.pending.put(text)
                chat._kill_proc('listener')
        elif cmd == 'ai_open':
            if chat.active:
                chat.pending_ai_open.set()
                chat._kill_proc('listener')
        elif cmd == 'replay':
            if chat.active and chat.last_ai:
                chat.pending_replay.set()
                chat._kill_proc('listener')
        elif cmd == 'status':
            emit({'event': 'status', 'active': chat.active,
                  'topic': chat.topic, 'requested_topic': chat.requested_topic,
                  'messages': chat.messages, 'ai_backend': 'deepseek'})
        elif cmd == 'ping':
            emit({'event': 'pong'})
    chat.stop()


if __name__ == '__main__':
    main()
