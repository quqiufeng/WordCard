#ifndef VOICE_ENGINE_H
#define VOICE_ENGINE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// ── ASR (Speech-to-Text) ──────────────────────────────────────────

void* voice_asr_create(const char* model_dir);
int   voice_asr_load(void* engine, const char* enc_frontend, const char* enc_backend,
                     const char* dec_gguf, int n_threads, int use_gpu);
char*  voice_asr_transcribe_file(void* engine, const char* wav_path, const char* language);
void   voice_asr_free_text(char* text);
void   voice_asr_destroy(void* engine);

// ── TTS (Text-to-Speech) ──────────────────────────────────────────

void* voice_tts_create(const char* model_dir);
int   voice_tts_load(void* engine, const char* model_path, const char* config_path,
                     int n_threads, int use_gpu);
char*  voice_tts_synthesize(void* engine, const char* text, const char* output_path);
void   voice_tts_set_sid(void* engine, int sid);
void   voice_tts_free_text(char* text);
void   voice_tts_destroy(void* engine);

// ── Audio Capture (ALSA + VAD) ────────────────────────────────────

typedef void (*voice_capture_callback)(const int16_t* pcm, int frames, void* user_data);

void* voice_capture_create(const char* device, int sample_rate, int frame_ms,
                           int silence_ms, int min_speech_ms, int max_seg_ms,
                           voice_capture_callback cb, void* user_data);
int   voice_capture_start(void* capture);
void  voice_capture_stop(void* capture);
void  voice_capture_destroy(void* capture);

// ── Audio Playback ────────────────────────────────────────────────

int voice_play_wav(const char* wav_path, const char* device);

// ── Utility ───────────────────────────────────────────────────────

int voice_convert_to_wav(const char* input_path, const char* output_path, int sample_rate);

#ifdef __cplusplus
}
#endif

#endif
