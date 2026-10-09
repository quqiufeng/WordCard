#include "voice_engine.h"

#include <alsa/asoundlib.h>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <queue>
#include <string>
#include <thread>
#include <vector>

// ── ASR: Qwen3-ASR via subprocess (SenseVoice fallback) ──────────

#include <regex>
#include <atomic>
#include <unistd.h>

static std::string trim(const std::string &s) {
    size_t a = s.find_first_not_of(" \t\r\n");
    if (a == std::string::npos) return "";
    size_t b = s.find_last_not_of(" \t\r\n");
    return s.substr(a, b - a + 1);
}

static std::string strip_tags(std::string s) {
    static const std::regex tag(R"(<\|[^|]*\|>)");
    s = std::regex_replace(s, tag, "");
    return s;
}

struct VoiceAsrEngine {
    std::string model_dir;
    std::string asr_bin;
    std::string asr_model;
    std::string lang;
    int threads;
};

void* voice_asr_create(const char* model_dir) {
    auto* eng = new (std::nothrow) VoiceAsrEngine();
    if (!eng) return nullptr;
    if (model_dir) eng->model_dir = model_dir;
    eng->asr_bin = "/opt/SenseVoice.cpp/build/bin/sense-voice-main";
    eng->asr_model = "/data/models/sense-voice-small-q4_k.gguf";
    eng->lang = "auto";
    eng->threads = 4;
    return eng;
}

int voice_asr_load(void* engine, const char* enc_frontend, const char* enc_backend,
                   const char* dec_gguf, int n_threads, int use_gpu) {
    (void)enc_frontend; (void)enc_backend; (void)dec_gguf; (void)use_gpu;
    auto* eng = static_cast<VoiceAsrEngine*>(engine);
    if (!eng) return -1;
    if (n_threads > 0) eng->threads = n_threads;
    return 0;
}

char* voice_asr_transcribe_file(void* engine, const char* wav_path, const char* language) {
    auto* eng = static_cast<VoiceAsrEngine*>(engine);
    if (!eng || !wav_path) return nullptr;

    std::string lang = language ? language : eng->lang;
    std::string cmd = "'" + eng->asr_bin + "' -m '" + eng->asr_model + "' -t " +
                      std::to_string(eng->threads) + " -l " + lang + " '" + wav_path + "' 2>/dev/null";
    FILE* p = popen(cmd.c_str(), "r");
    if (!p) return nullptr;
    char buf[4096];
    std::string out;
    while (fgets(buf, sizeof(buf), p)) out += buf;
    pclose(p);

    static const std::regex line_pat(R"(\[[0-9.]+-[0-9.]+\]\s*(.*))");
    std::string text;
    size_t pos = 0;
    while (pos < out.size()) {
        size_t nl = out.find('\n', pos);
        std::string line = out.substr(pos, nl == std::string::npos ? std::string::npos : nl - pos);
        pos = (nl == std::string::npos) ? out.size() : nl + 1;
        std::smatch m;
        if (std::regex_search(line, m, line_pat)) {
            std::string part = trim(strip_tags(m[1].str()));
            if (!part.empty()) {
                if (!text.empty()) text += " ";
                text += part;
            }
        }
    }
    text = trim(text);
    char* result = (char*)malloc(text.size() + 1);
    if (!result) return nullptr;
    memcpy(result, text.c_str(), text.size() + 1);
    return result;
}

void voice_asr_free_text(char* text) {
    free(text);
}

void voice_asr_destroy(void* engine) {
    delete static_cast<VoiceAsrEngine*>(engine);
}

// ── TTS: Kokoro (sherpa-onnx) via subprocess ──────────────────────

struct VoiceTtsEngine {
    std::string model_dir;
    std::string tts_bin;
    std::string kokoro_dir;
    int sid;
    int threads;
};

void* voice_tts_create(const char* model_dir) {
    auto* eng = new (std::nothrow) VoiceTtsEngine();
    if (!eng) return nullptr;
    if (model_dir) eng->model_dir = model_dir;
    eng->tts_bin = "/opt/sherpa-onnx/bin/sherpa-onnx-offline-tts";
    eng->kokoro_dir = "/data/models/kokoro-multi-lang-v1_0";
    { const char* s = getenv("WC_TTS_SID"); eng->sid = s ? atoi(s) : 47; }
    eng->threads = 4;
    return eng;
}

int voice_tts_load(void* engine, const char* model_path, const char* config_path,
                   int n_threads, int use_gpu) {
    (void)model_path; (void)config_path; (void)use_gpu;
    auto* eng = static_cast<VoiceTtsEngine*>(engine);
    if (!eng) return -1;
    if (n_threads > 0) eng->threads = n_threads;
    return 0;
}

char* voice_tts_synthesize(void* engine, const char* text, const char* output_path) {
    auto* eng = static_cast<VoiceTtsEngine*>(engine);
    if (!eng || !text) return nullptr;

    std::string out = output_path ? output_path : "/tmp/voice_tts.wav";
    std::string kdir = eng->kokoro_dir;
    std::string cmd = "'" + eng->tts_bin + "'"
        " --kokoro-model='" + kdir + "/model.onnx'"
        " --kokoro-voices='" + kdir + "/voices.bin'"
        " --kokoro-tokens='" + kdir + "/tokens.txt'"
        " --kokoro-data-dir='" + kdir + "/espeak-ng-data'"
        " --kokoro-lexicon='" + kdir + "/lexicon-us-en.txt," + kdir + "/lexicon-zh.txt'"
        " --tts-rule-fsts='" + kdir + "/date-zh.fst," + kdir + "/number-zh.fst'"
        " --num-threads=" + std::to_string(eng->threads) +
        " --sid=" + std::to_string(eng->sid) +
        " --output-filename='" + out + "'"
        " '" + std::string(text) + "' 2>/dev/null";

    int rc = system(cmd.c_str());
    if (rc != 0) return nullptr;

    char* result = (char*)malloc(out.size() + 1);
    if (!result) return nullptr;
    memcpy(result, out.c_str(), out.size() + 1);
    return result;
}

void voice_tts_set_sid(void* engine, int sid) {
    auto* eng = static_cast<VoiceTtsEngine*>(engine);
    if (eng && sid >= 0) eng->sid = sid;
}

void voice_tts_free_text(char* text) {
    free(text);
}

void voice_tts_destroy(void* engine) {
    delete static_cast<VoiceTtsEngine*>(engine);
}

// ── Audio Capture (ALSA + VAD) ────────────────────────────────────

struct VoiceCapture {
    std::string device;
    int sample_rate;
    int frame_ms;
    int silence_ms;
    int min_speech_ms;
    int max_seg_ms;
    voice_capture_callback cb;
    void* user_data;

    std::atomic<bool> running{false};
    std::thread worker;
    std::queue<std::vector<int16_t>> queue;
    std::mutex mtx;
    std::condition_variable cv;
};

void* voice_capture_create(const char* device, int sample_rate, int frame_ms,
                           int silence_ms, int min_speech_ms, int max_seg_ms,
                           voice_capture_callback cb, void* user_data) {
    auto* cap = new (std::nothrow) VoiceCapture();
    if (!cap) return nullptr;
    cap->device = device ? device : "default";
    cap->sample_rate = sample_rate > 0 ? sample_rate : 16000;
    cap->frame_ms = frame_ms > 0 ? frame_ms : 100;
    cap->silence_ms = silence_ms > 0 ? silence_ms : 1200;
    cap->min_speech_ms = min_speech_ms > 0 ? min_speech_ms : 300;
    cap->max_seg_ms = max_seg_ms > 0 ? max_seg_ms : 6000;
    cap->cb = cb;
    cap->user_data = user_data;
    return cap;
}

static void capture_thread(VoiceCapture* cap) {
    snd_pcm_t* pcm = nullptr;
    if (snd_pcm_open(&pcm, cap->device.c_str(), SND_PCM_STREAM_CAPTURE, 0) != 0) {
        fprintf(stderr, "[voice] Cannot open capture device %s\n", cap->device.c_str());
        return;
    }
    snd_pcm_set_params(pcm, SND_PCM_FORMAT_S16_LE, SND_PCM_ACCESS_RW_INTERLEAVED,
                       1, cap->sample_rate, 1, 500000);

    int frame_len = cap->sample_rate * cap->frame_ms / 1000;
    std::vector<int16_t> frame(frame_len);
    std::vector<int16_t> acc;
    bool speaking = false;
    int silent = 0;
    int noise = 200;
    const int end_frames = std::max(1, cap->silence_ms / cap->frame_ms);
    const int min_frames = std::max(1, cap->min_speech_ms / cap->frame_ms);
    const int max_frames = std::max(1, cap->max_seg_ms / cap->frame_ms);

    while (cap->running) {
        int r = snd_pcm_readi(pcm, frame.data(), frame_len);
        if (r < 0) { snd_pcm_prepare(pcm); continue; }
        int peak = 0;
        for (int i = 0; i < r; ++i) {
            int a = std::abs((int)frame[i]);
            if (a > peak) peak = a;
        }
        int thr = std::max(500, noise * 2);

        if (!speaking) {
            noise = (noise * 3 + peak) / 4;
            if (peak >= thr) {
                speaking = true;
                silent = 0;
                acc.clear();
            } else {
                continue;
            }
        }

        if (peak >= thr) silent = 0;
        else ++silent;
        acc.insert(acc.end(), frame.begin(), frame.begin() + r);

        if ((int)acc.size() / frame_len >= max_frames) {
            if (cap->cb) cap->cb(acc.data(), (int)acc.size(), cap->user_data);
            { std::lock_guard<std::mutex> lk(cap->mtx); cap->queue.push(acc); }
            cap->cv.notify_one();
            acc.clear();
            silent = 0;
            continue;
        }

        if (silent >= end_frames) {
            speaking = false;
            int speech_frames = (int)acc.size() / frame_len - silent;
            if (speech_frames >= min_frames) {
                if (cap->cb) cap->cb(acc.data(), (int)acc.size(), cap->user_data);
                { std::lock_guard<std::mutex> lk(cap->mtx); cap->queue.push(acc); }
                cap->cv.notify_one();
            }
            acc.clear();
            silent = 0;
        }
    }
    snd_pcm_close(pcm);
}

int voice_capture_start(void* capture) {
    auto* cap = static_cast<VoiceCapture*>(capture);
    if (!cap || cap->running) return -1;
    cap->running = true;
    cap->worker = std::thread(capture_thread, cap);
    return 0;
}

void voice_capture_stop(void* capture) {
    auto* cap = static_cast<VoiceCapture*>(capture);
    if (!cap) return;
    cap->running = false;
    if (cap->worker.joinable()) cap->worker.join();
}

void voice_capture_destroy(void* capture) {
    auto* cap = static_cast<VoiceCapture*>(capture);
    if (!cap) return;
    voice_capture_stop(cap);
    delete cap;
}

// ── Audio Playback ────────────────────────────────────────────────

int voice_play_wav(const char* wav_path, const char* device) {
    if (!wav_path) return -1;
    std::string cmd = "aplay";
    if (device) cmd += " -D " + std::string(device);
    cmd += " -q '" + std::string(wav_path) + "' 2>/dev/null";
    return system(cmd.c_str());
}

// ── Utility ───────────────────────────────────────────────────────

int voice_convert_to_wav(const char* input_path, const char* output_path, int sample_rate) {
    if (!input_path || !output_path) return -1;
    int sr = sample_rate > 0 ? sample_rate : 16000;
    std::string cmd = "ffmpeg -y -i '" + std::string(input_path) +
                      "' -ar " + std::to_string(sr) + " -ac 1 -c:a pcm_s16le '" +
                      std::string(output_path) + "' 2>/dev/null";
    return system(cmd.c_str());
}
