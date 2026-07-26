#ifndef QWEN3_ASR_BRIDGE_H
#define QWEN3_ASR_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void* qwen3_asr_create(const char* model_dir);
int   qwen3_asr_load(void* engine, const char* enc_frontend, const char* enc_backend,
                     const char* dec_gguf, int n_threads, int use_gpu);
const char* qwen3_asr_transcribe_file(void* engine, const char* wav_path, const char* language);
void qwen3_asr_free_text(const char* text);
void qwen3_asr_destroy(void* engine);

#ifdef __cplusplus
}
#endif

#endif
