#include "qwen3_asr_engine.h"
#include "qwen3_asr_bridge.h"

#include <cstring>
#include <string>

extern "C" {

void* qwen3_asr_create(const char* model_dir) {
    Qwen3ASREngineConfig cfg;
    if (model_dir) cfg.model_dir = model_dir;

    auto* engine = new (std::nothrow) Qwen3ASREngine();
    if (!engine) return nullptr;

    if (!engine->load(cfg)) {
        delete engine;
        return nullptr;
    }
    return engine;
}

int qwen3_asr_load(void* engine, const char* enc_frontend, const char* enc_backend,
                    const char* dec_gguf, int n_threads, int use_gpu) {
    auto* eng = static_cast<Qwen3ASREngine*>(engine);
    if (!eng) return -1;

    Qwen3ASREngineConfig cfg;
    if (enc_frontend) cfg.encoder_frontend = enc_frontend;
    if (enc_backend)  cfg.encoder_backend  = enc_backend;
    if (dec_gguf)     cfg.decoder_gguf     = dec_gguf;
    cfg.n_threads = n_threads > 0 ? n_threads : 4;
    cfg.use_gpu   = use_gpu != 0;

    return eng->load(cfg) ? 0 : -1;
}

const char* qwen3_asr_transcribe_file(void* engine, const char* wav_path, const char* language) {
    auto* eng = static_cast<Qwen3ASREngine*>(engine);
    if (!eng || !wav_path) return nullptr;

    std::string lang = language ? language : "";
    std::string result = eng->transcribe_file(wav_path, lang);

    char* buf = (char*)malloc(result.size() + 1);
    if (!buf) return nullptr;
    memcpy(buf, result.c_str(), result.size() + 1);
    return buf;
}

void qwen3_asr_free_text(const char* text) {
    free(const_cast<char*>(text));
}

void qwen3_asr_destroy(void* engine) {
    delete static_cast<Qwen3ASREngine*>(engine);
}

} // extern "C"
