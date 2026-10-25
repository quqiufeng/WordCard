"""translate — 翻译/释义（本地 llama-server 或 DeepSeek 在线 API）

后端选择（.env 或环境变量）:
    WC_TRANSLATE_BACKEND=local|deepseek   默认 local；deepseek=在线；auto=有 key 才在线
    DEEPSEEK_BASE_URL=https://api.deepseek.com
    DEEPSEEK_API_KEY=sk-...
    DEEPSEEK_MODEL=deepseek-flash

本地模式使用 /data/models 下的 GGUF 模型，零外部 API 依赖。
"""

import json, os, shutil, signal, subprocess, time, urllib.error, urllib.request
from urllib.parse import urlparse

_ROOT = os.path.dirname(os.path.abspath(__file__))


def _load_dotenv(path):
    """极简 .env 读取；已存在的真实环境变量优先。"""
    if not os.path.exists(path):
        return
    try:
        with open(path, encoding='utf-8') as f:
            for raw in f:
                line = raw.strip()
                if not line or line.startswith('#'):
                    continue
                if line.startswith('export '):
                    line = line[7:].lstrip()
                key, sep, val = line.partition('=')
                key = key.strip()
                if not sep or not key or key in os.environ:
                    continue
                val = val.strip()
                if len(val) >= 2 and val[0] == val[-1] and val[0] in ('"', "'"):
                    val = val[1:-1]
                os.environ[key] = val
    except Exception:
        pass


_load_dotenv(os.path.join(_ROOT, '.env'))

LLAMA_BIN = os.environ.get('LLAMA_SERVER', '/opt/llama.cpp/build/bin/llama-server')
# 翻译用小模型即可；按优先级选第一个存在的（WC_LLM_MODEL 可覆盖）
_MODEL_CANDIDATES = [
    os.environ.get('WC_LLM_MODEL'),
    '/data/models/Hunyuan-MT-7B-Q4_K_M.gguf',
    '/data/models/image/Qwen3-4B-Instruct-2507-Q4_K_M.gguf',
]
MODEL = next((m for m in _MODEL_CANDIDATES if m and os.path.exists(m)),
             '/data/models/image/Qwen3-4B-Instruct-2507-Q4_K_M.gguf')
URL = os.environ.get('WC_LLM_URL', 'http://127.0.0.1:8081')
DEEPSEEK_BASE = os.environ.get('DEEPSEEK_BASE_URL') or os.environ.get('DEEPSEEK_API_BASE') or 'https://api.deepseek.com'
DEEPSEEK_CHAT_URL = os.environ.get('DEEPSEEK_CHAT_URL') or ''
DEEPSEEK_MODEL = os.environ.get('DEEPSEEK_MODEL') or 'deepseek-flash'
DEEPSEEK_KEY = os.environ.get('DEEPSEEK_API_KEY') or os.environ.get('WC_DEEPSEEK_API_KEY') or ''
TERM_SCRIPT = os.path.join(_ROOT, 'tools', 'llama_terminal.sh')
PIDFILE = os.environ.get('WC_LLAMA_PIDFILE', '/tmp/wordcard_llama.pid')
_U = urlparse(URL)
HOST = _U.hostname or '127.0.0.1'
PORT = _U.port or 8081

_cache = {}

def _health():
    try:
        with urllib.request.urlopen(URL + '/health', timeout=2) as r:
            return b'"status":"ok"' in r.read()
    except Exception:
        return False

def _alive(pid):
    if not pid:
        return False
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False

def _read_pid():
    try:
        with open(PIDFILE) as f:
            return int((f.read() or '0').strip())
    except Exception:
        return 0

def _terminal():
    """优先 qterminal；可用 WC_TERMINAL 覆盖。"""
    term = os.environ.get('WC_TERMINAL')
    if term:
        return term
    # xterm 可用 -geometry/-T，启动的窗口更小更可控；可用 WC_TERMINAL 覆盖
    return shutil.which('xterm') or shutil.which('qterminal')

def _launch_terminal():
    """在终端窗口中前台启动 llama-server（用户可 Ctrl+C/关窗停止）。"""
    term = _terminal()
    if not term or not os.path.exists(TERM_SCRIPT):
        return False
    if not (os.environ.get('DISPLAY') or os.environ.get('WAYLAND_DISPLAY')):
        return False
    watch = os.environ.get('WC_LLM_WATCH_PID') or str(os.getppid())
    env = os.environ.copy()
    env.update({
        'LLAMA_SERVER': LLAMA_BIN,
        'WC_LLM_MODEL': MODEL,
        'WC_LLM_HOST': HOST,
        'WC_LLM_PORT': str(PORT),
        'WC_LLAMA_PIDFILE': PIDFILE,
    })
    base = os.path.basename(term)
    if 'qterminal' in base:
        cmd = [term, '-w', _ROOT, '-e', TERM_SCRIPT, watch]
    elif 'xterm' in base:
        cmd = [term, '-geometry', '120x20', '-T', 'llama-server · 翻译模型',
               '-e', TERM_SCRIPT, watch]
    else:
        cmd = [term, '-e', TERM_SCRIPT, watch]
    try:
        subprocess.Popen(
            cmd, env=env, stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True)
        return True
    except Exception:
        return False

def backend():
    """当前翻译后端：local（默认）/ deepseek / auto。"""
    b = (os.environ.get('WC_TRANSLATE_BACKEND') or '').strip().lower()
    if b in ('deepseek', 'api', 'online'):
        return 'deepseek'
    if b == 'auto':
        return 'deepseek' if DEEPSEEK_KEY else 'local'
    # 默认本地 LLM；DeepSeek 仅在显式设置时启用
    return 'local'


def chat_backend():
    """对话后端：默认有 DeepSeek key 就用在线，否则本地；可用 WC_CHAT_BACKEND 覆盖。"""
    b = (os.environ.get('WC_CHAT_BACKEND') or os.environ.get('WC_DIALOGUE_BACKEND') or '').strip().lower()
    if b in ('deepseek', 'api', 'online'):
        return 'deepseek'
    if b in ('local', 'llama'):
        return 'local'
    return 'deepseek' if DEEPSEEK_KEY else 'local'


def _deepseek_url():
    if DEEPSEEK_CHAT_URL:
        return DEEPSEEK_CHAT_URL
    base = DEEPSEEK_BASE.rstrip('/')
    if base.endswith('/chat/completions'):
        return base
    return base + '/chat/completions'


def ensure_server(timeout=180):
    """确保翻译模型在线；本地模式在终端窗口里启动，在线模式直接可用。"""
    if backend() == 'deepseek':
        return bool(DEEPSEEK_KEY)
    if _health():
        return True
    if not os.path.exists(LLAMA_BIN) or not os.path.exists(MODEL):
        return False

    pid = _read_pid()
    if not (pid and _alive(pid)):
        if not _launch_terminal():
            return False

    t0 = time.time()
    while time.time() - t0 < timeout:
        if _health():
            return True
        # 终端启动失败或进程已退出：不再空等
        if time.time() - t0 > 5 and not _alive(_read_pid()):
            return False
        time.sleep(1)
    return False

def stop_server():
    """停止终端里的 llama-server（关闭其终端/进程）。"""
    pid = _read_pid()
    if not pid or not _alive(pid):
        try:
            os.remove(PIDFILE)
        except OSError:
            pass
        return False
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        pass
    for _ in range(50):
        if not _alive(pid) and not _health():
            break
        time.sleep(0.1)
    if _alive(pid):
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass
    try:
        os.remove(PIDFILE)
    except OSError:
        pass
    return True

def server_status():
    pid = _read_pid()
    if backend() == 'deepseek':
        return {
            'backend': 'deepseek',
            'healthy': bool(DEEPSEEK_KEY),
            'configured': bool(DEEPSEEK_KEY),
            'url': _deepseek_url(),
            'model': DEEPSEEK_MODEL,
            'chat_backend': chat_backend(),
        }
    return {
        'backend': 'local',
        'healthy': _health(),
        'pid': pid,
        'running': _alive(pid),
        'url': URL,
        'model': MODEL,
        'terminal': _terminal() or '',
        'chat_backend': chat_backend(),
    }


def _chat_messages_deepseek(messages, max_tokens=400, temperature=0.2,
                            json_mode=False):
    if not DEEPSEEK_KEY:
        raise RuntimeError('DEEPSEEK_API_KEY 未配置（可写入 .env）')
    payload = {
        'model': DEEPSEEK_MODEL,
        'messages': messages,
        'temperature': temperature,
        'max_tokens': max_tokens,
        'thinking': {'type': 'disabled'},
        'stream': False,
    }
    if json_mode:
        payload['response_format'] = {'type': 'json_object'}
    req = urllib.request.Request(
        _deepseek_url(), data=json.dumps(payload).encode(),
        headers={
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + DEEPSEEK_KEY,
        })
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            d = json.load(r)
    except urllib.error.HTTPError as e:
        detail = e.read().decode('utf-8', 'replace')[:300]
        raise RuntimeError(f'DeepSeek HTTP {e.code}: {detail}') from e
    except urllib.error.URLError as e:
        raise RuntimeError(f'DeepSeek 连接失败: {e.reason}') from e
    try:
        return d['choices'][0]['message']['content'].strip()
    except (KeyError, IndexError, TypeError) as e:
        raise RuntimeError(f'DeepSeek 返回格式异常: {str(d)[:300]}') from e


def _chat_deepseek(prompt, system=None, max_tokens=400, temperature=0.2):
    msgs = []
    if system:
        msgs.append({'role': 'system', 'content': system})
    msgs.append({'role': 'user', 'content': prompt})
    return _chat_messages_deepseek(msgs, max_tokens, temperature)


def _chat_messages_local(messages, max_tokens=400, temperature=0.2):
    if not _health():
        ensure_server()
    payload = {
        'messages': messages,
        'temperature': temperature,
        'max_tokens': max_tokens,
    }
    req = urllib.request.Request(
        URL + '/v1/chat/completions', data=json.dumps(payload).encode(),
        headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=180) as r:
        d = json.load(r)
    try:
        return d['choices'][0]['message']['content'].strip()
    except (KeyError, IndexError, TypeError) as e:
        raise RuntimeError(f'本地 LLM 返回格式异常: {str(d)[:300]}') from e


def deepseek_available():
    return bool(DEEPSEEK_KEY)


def chat_available():
    if chat_backend() == 'deepseek':
        return bool(DEEPSEEK_KEY)
    return ensure_server() if not _health() else True


def chat_deepseek(messages, max_tokens=500, temperature=0.7, json_mode=False):
    """口语对话固定走 DeepSeek（AI 回复 + 话题生成）。"""
    return _chat_messages_deepseek(messages, max_tokens, temperature,
                                   json_mode=json_mode)


def chat(messages, max_tokens=500, temperature=0.7, json_mode=False):
    """通用对话（口语陪练用）。messages = [{role, content}, ...]"""
    if chat_backend() == 'deepseek':
        return _chat_messages_deepseek(messages, max_tokens, temperature,
                                       json_mode=json_mode)
    return _chat_messages_local(messages, max_tokens, temperature)


def _chat(prompt, system=None, max_tokens=400, temperature=0.2):
    if backend() == 'deepseek':
        return _chat_deepseek(prompt, system, max_tokens, temperature)
    msgs = []
    if system:
        msgs.append({'role': 'system', 'content': system})
    msgs.append({'role': 'user', 'content': prompt})
    body = json.dumps({'messages': msgs, 'temperature': temperature,
                       'max_tokens': max_tokens}).encode()
    req = urllib.request.Request(URL + '/v1/chat/completions', data=body,
                                 headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=180) as r:
        d = json.load(r)
    return d['choices'][0]['message']['content'].strip()


def available():
    if backend() == 'deepseek':
        return bool(DEEPSEEK_KEY)
    return ensure_server() if not _health() else True

def _think_prefix():
    # 本地 Qwen 用 /no_think 关闭思考；DeepSeek 用请求参数 thinking=disabled
    return '' if backend() == 'deepseek' else '/no_think '


def translate(text, system=None, highlight=None):
    """英译中，只返回中文。highlight=目标英文词时，把其对应中文用【】括出。"""
    key = ('t', text, highlight)
    if key in _cache:
        return _cache[key]
    if not text.strip():
        return ''
    instr = (_think_prefix() + 'Translate the following English into natural, fluent Chinese. '
             'Output ONLY the Chinese translation. Do NOT add explanations, '
             'parentheses, notes, alternatives, or any extra content; keep it '
             'concise and faithful to the source length.')
    if highlight:
        instr += (f' When translating, wrap the Chinese rendering of the word '
                  f'"{highlight}" in 【】 (keep the brackets).')
    out = _chat(instr + ':\n' + text,
                system=system or '你是专业英译中译者，只输出简洁忠实的中文译文，不加任何解释或补充说明。')
    _cache[key] = out
    return out

def define(word):
    """返回 (英文释义, 中文释义, 词性)"""
    key = ('d', word)
    if key in _cache:
        return _cache[key]
    prompt = (
        _think_prefix() + 'For the English word "%s", give a concise bilingual entry.\n'
        'Reply in EXACTLY this format, one line each, no extra text:\n'
        'POS: <part of speech, e.g. n. / v. / adj.>\n'
        'EN: <one-line English definition>\n'
        'ZH: <一行中文释义>' % word)
    out = _chat(prompt, max_tokens=200)
    pos = en = zh = ''
    for line in out.splitlines():
        line = line.strip()
        if line.startswith('POS:'): pos = line[4:].strip()
        elif line.startswith('EN:'): en = line[3:].strip()
        elif line.startswith('ZH:'): zh = line[3:].strip()
    if not zh:
        zh = out
    _cache[key] = (en, zh, pos)
    return (en, zh, pos)

if __name__ == '__main__':
    import sys
    if not available():
        print('LLM server unavailable', file=sys.stderr); sys.exit(1)
    txt = sys.argv[1] if len(sys.argv) > 1 else 'The animals staged a rebellion.'
    print('译文:', translate(txt))


def memo(word, context=None):
    """用一句简洁中文说明该词的含义、常见使用场景（助记描述）。"""
    import re
    key = ('m', word)
    if key in _cache:
        return _cache[key]
    prompt = (_think_prefix() + f'用一句不超过30字的中文说明英语单词 "{word}" 的意思和常见'
              f'使用场景，帮助记忆。要求：只输出这一句中文，不要英文，不要编号或标题，'
              f'不要换行：')
    if context:
        prompt += f'\n参考场景：{context}'
    out = ''
    try:
        out = _chat(prompt, max_tokens=120).strip()
    except Exception:
        out = ''
    out = out.replace('**', '').strip()
    out = re.sub(r'^(记忆提示|说明|提示|解释|用法)[:：]\s*', '', out)
    out = out.split('\n')[0].strip()
    if out:
        out = re.split(r'(?<=[。！？])', out)[0].strip()
    out = re.sub(r"[A-Za-z][A-Za-z'’.\-]*", '', out)
    out = re.sub(r'\s+', ' ', out).strip(' “”"：:,')
    _cache[key] = out
    return out
