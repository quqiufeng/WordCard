# Voice Wrappers 编译说明

> 独立维护的 C++ Wrapper，用于将 SenseVoice 和 Piper TTS 封装为 C 接口供 Python ctypes 调用。

---

## 文件说明

| 文件 | 来源 | 说明 |
|------|------|------|
| `sensevoice_wrapper.cpp` | `~/my-agent/sense-voice-wrapper/` | SenseVoice 语音识别 C 接口封装 |
| `piper_wrapper.cpp` | `~/my-agent/piper-wrapper/` | Piper TTS 语音合成 C 接口封装 |

---

## 编译步骤

### 1. SenseVoice Wrapper

```bash
# 在 SenseVoice.cpp 源码目录下编译
cd /home/dministrator/SenseVoice.cpp

g++ -shared -fPIC -std=c++17 \
  -I. -Isense-voice/csrc -Ibuild/_deps/ggml-src/include \
  sense-voice/csrc/sensevoice_wrapper.cpp \
  build/lib/libsense-voice-core.a \
  build/lib/libcommon.a \
  -Lbuild/lib -lggml -lggml-base -lggml-cpu \
  -o libsensevoice.so \
  -lpthread -ldl

# 复制到本项目
cp libsensevoice.so /home/dministrator/WordCard/voice/libs/
```

**依赖**：
- SenseVoice.cpp 源码：`/home/dministrator/SenseVoice.cpp`
- 模型文件：`models/sense-voice-small-q6_k.gguf`
- ggml 库（随 SenseVoice 编译生成）

### 2. Piper TTS Wrapper

```bash
# 在 Piper 源码目录下编译
cd /opt/piper-src

# 1. 先编译 Piper 本体
mkdir build && cd build
cmake -DCMAKE_CXX_FLAGS="-fPIC" ..
make -j$(nproc) piper_tts

# 2. 编译 wrapper
cd ..
g++ -shared -fPIC -std=c++17 \
  -Isrc/cpp \
  -Ibuild \
  -Ipiper-phonemize/src \
  -Ionnxruntime/include \
  src/cpp/piper_wrapper.cpp \
  build/src/cpp/piper.cpp \
  -Lbuild/lib -lpiper_phonemize -lonnxruntime \
  -lespeak-ng \
  -o libpiper_tts.so \
  -lpthread -ldl

# 复制到本项目
cp libpiper_tts.so /home/dministrator/WordCard/voice/libs/
```

**依赖**：
- Piper 源码：`/opt/piper-src`
- ONNX Runtime：`/opt/piper-src/onnxruntime`
- espeak-ng：`/usr/lib/x86_64-linux-gnu/espeak-ng-data`
- 模型文件：`zh_CN-huayan-medium.onnx` + `.json` 配置

---

## Python 调用方式

```python
import ctypes

# SenseVoice
lib = ctypes.CDLL("voice/libs/libsensevoice.so")
ctx = lib.sensevoice_load_model(b"models/sense-voice-small-q6_k.gguf", 4)
text = lib.sensevoice_recognize(ctx, b"/tmp/test.wav", 4)

# Piper
lib = ctypes.CDLL("voice/libs/libpiper_tts.so")
lib.piper_initialize(b"/usr/lib/x86_64-linux-gnu/espeak-ng-data", None)
voice = lib.piper_load_voice(b"models/zh_CN-huayan-medium.onnx", 
                              b"models/zh_CN-huayan-medium.onnx.json", -1, 0)
lib.piper_synthesize_to_file(voice, b"你好世界", b"/tmp/output.wav")
```

---

## 修改记录

| 日期 | 修改内容 | 说明 |
|------|----------|------|
| 2026-05-14 | 初始导入 | 从 `~/my-agent` 复制 wrapper 源码，独立维护 |

---

**注意**：
- `.so` 文件需要依赖对应的模型文件和库文件才能运行
- 如果修改了 `.cpp` 文件，需要重新编译并复制 `.so` 到 `voice/libs/`
- 模型文件路径在 Python 层配置，不在 C 层硬编码
