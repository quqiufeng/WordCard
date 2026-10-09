"""translate — 本地 LLM 翻译/释义（llama-server, OpenAI 兼容 API）

使用 /data/models 下的 GGUF 模型，零外部 API 依赖。
"""

import json, os, subprocess, time, urllib.request

LLAMA_BIN = os.environ.get('LLAMA_SERVER', '/opt/llama.cpp/build/bin/llama-server')
MODEL = os.environ.get('WC_LLM_MODEL', '/data/models/Qwen3-14B-Q4_K_M.gguf')
URL = os.environ.get('WC_LLM_URL', 'http://127.0.0.1:8081')
_LOG = '/tmp/llama_server.log'

_cache = {}

def _health():
    try:
        with urllib.request.urlopen(URL + '/health', timeout=2) as r:
            return b'"status":"ok"' in r.read()
    except Exception:
        return False

def ensure_server(timeout=180):
    if _health():
        return True
    if not os.path.exists(LLAMA_BIN) or not os.path.exists(MODEL):
        return False
    with open(_LOG, 'ab') as log:
        subprocess.Popen(
            [LLAMA_BIN, '-m', MODEL, '-ngl', '99', '-c', '4096',
             '--host', '127.0.0.1', '--port', URL.rsplit(':', 1)[-1]],
            stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
            start_new_session=True)
    t0 = time.time()
    while time.time() - t0 < timeout:
        if _health():
            return True
        time.sleep(2)
    return False

def _chat(prompt, system=None, max_tokens=400, temperature=0.2):
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
    return ensure_server() if not _health() else True

def translate(text, system=None):
    """英译中，只返回中文"""
    key = ('t', text)
    if key in _cache:
        return _cache[key]
    if not text.strip():
        return ''
    out = _chat('/no_think Translate the following English into natural, fluent Chinese. '
                'Output ONLY the Chinese translation, no explanation:\n' + text,
                system=system or '你是专业英译中译者，只输出中文译文。')
    _cache[key] = out
    return out

def define(word):
    """返回 (英文释义, 中文释义, 词性)"""
    key = ('d', word)
    if key in _cache:
        return _cache[key]
    prompt = (
        '/no_think For the English word "%s", give a concise bilingual entry.\n'
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
