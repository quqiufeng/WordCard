/// 语音引擎（`libvoice_engine.so`）FFI 绑定的占位模块。
///
/// ASR / TTS 的 C ABI 尚未在本里程碑范围内，待实现时：
///   1. 从 `voice/wrappers/voice_engine.cpp` 与 `voice.py` 核对确切导出签名；
///   2. 用 `DynamicLibrary.open('libvoice_engine.so')` + `lookupFunction` 绑定；
///   3. 在此暴露 `recognize()` / `synthesize()` 的 Dart 友好接口。
library;
