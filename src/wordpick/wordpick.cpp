// wordpick — 从电子书正文中挑选"最值得学习"的英文单词
//
// 学习价值模型（综合多项信号）：
//   score = U(zipf) · (0.35 + 0.65·rel) · spread · prod · lenpen
//     U      : 偏态难度曲线（简单侧衰减更陡，生僻侧尾部更长）
//     rel    : 书内词频 log 归一（相关性）
//     spread : 书内散布度（跨 chunk 出现 → 主题词）
//     prod   : 构词能产性分级（高/低能产后缀）
//     lenpen : 过长词惩罚
// 过滤：噪声 / CapRatio 专有名词 / 停用词 / 基础词 / 词形还原合并
// 模式：0=学习价值  1=覆盖率（mark 未知词按边际覆盖排序）

#include "wordpick.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace {

std::unordered_map<std::string, float>        g_freq;   // word -> zipf
std::unordered_map<std::string, std::string>  g_lemma;  // inflected -> lemma
std::unordered_map<std::string, int>          g_cefr;   // word -> CEFR(1..6)

// CEFR 等级 → zipf 等效值（A1..C2）
const float kCefrZipf[6] = {5.5f, 5.0f, 4.4f, 3.9f, 3.4f, 2.9f};

inline std::string lower_ascii(const std::string& s) {
    std::string r = s;
    for (char& c : r) if (c >= 'A' && c <= 'Z') c += 32;
    return r;
}
inline bool is_alpha(char c) { return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z'); }
inline bool is_vowel(char c) {
    c = (c >= 'A' && c <= 'Z') ? c + 32 : c;
    return c=='a'||c=='e'||c=='i'||c=='o'||c=='u'||c=='y';
}

// ── 停用词 / 常用基础词 ───────────────────────────────────────
const std::unordered_set<std::string>& stopwords() {
    static const std::unordered_set<std::string> s = [] {
        std::unordered_set<std::string> v;
        const char* w[] = {
            "the","and","for","are","but","not","you","all","any","can","her",
            "was","one","our","out","day","get","has","him","his","how","man",
            "new","now","old","see","two","way","who","boy","did","its","let",
            "put","say","she","too","use","that","with","have","this","will",
            "your","from","they","know","want","been","good","much","some",
            "time","very","when","come","here","just","like","long","make",
            "many","more","only","over","such","take","than","them","well",
            "were","what","about","would","there","their","which","could",
            "other","after","first","never","these","think","where","being",
            "every","great","might","shall","still","those","under","while",
            "before","should","because","through","between","against","without",
            "himself","herself","itself","themselves","ourselves","yourself",
            "myself","another","seemed","always","though","almost","nothing",
            "others","later","away","found","better","except","began","appeared",
            "whole","year","death","hard","morning","soon","suddenly","week",
            "words","already","called","eyes","five","food","given","half","read",
            "came","went","going","gone","does","done","having","upon","thing",
            "things","made","said","says","saw","looked","thought","wanted",
            "also","just",
        };
        for (auto* p : w) v.insert(p);
        return v;
    }();
    return s;
}

const std::unordered_set<std::string>& common_words() {
    static const std::unordered_set<std::string> s = [] {
        std::unordered_set<std::string> v;
        const char* w[] = {
            "animal","animals","farm","days","night","year","years","life",
            "world","men","women","people","home","house","work","part",
            "place","case","week","company","system","program","question",
            "government","number","point","water","room","mother","father",
            "money","story","fact","month","right","study","book","eyes",
            "business","issue","side","kind","head","service","friend",
            "power","hour","game","line","member","city","community","name",
            "team","minute","idea","body","information","back","parent",
            "face","level","office","door","health","person","history",
            "party","result","change","reason","research","girl","moment",
            "air","teacher","force","education","foot","policy","process",
            "music","market","sense","nation","plan","college","interest",
            "experience","effect","class","control","care","field","role",
            "effort","rate","heart","drug","leader","light","voice","wife",
            "police","mind","price","report","decision","view","town","road",
            "difference","value","building","action","model","season",
            "society","director","position","player","record","paper",
            "space","ground","form","event","official","matter","center",
            "couple","site","project","activity","table","need","court",
            "state","area","picture","practice","piece","hand","high",
            "small","large","little","young","important","public","able",
            "human","legs","sheep","hens","horses","cows","pigs","dogs",
            "birds","milk","walls","hours","barn","field","farms",
        };
        for (auto* p : w) v.insert(p);
        return v;
    }();
    return s;
}

bool is_roman(const std::string& w) {
    if (w.size() < 2) return false;
    for (char c : w) {
        char l = (c >= 'A' && c <= 'Z') ? c + 32 : c;
        if (l!='i'&&l!='v'&&l!='x'&&l!='l'&&l!='c'&&l!='d'&&l!='m') return false;
    }
    return true;
}

bool is_noise(const std::string& raw, const std::string& low) {
    if (raw.size() >= 2) {
        bool all_up = true;
        for (char c : raw) if (!(c >= 'A' && c <= 'Z')) { all_up = false; break; }
        if (all_up) return true;
    }
    if (is_roman(raw)) return true;
    if (low.size() > 3) {
        bool any_v = false;
        for (char c : low) if (is_vowel(c)) { any_v = true; break; }
        if (!any_v) return true;
    }
    if (low.size() >= 3) {
        bool same = true;
        for (char c : low) if (c != low[0]) { same = false; break; }
        if (same) return true;
    }
    return false;
}

// ── 构词能产性分级（Marchand 式：高/低能产后缀） ─────────────
float productivity(const std::string& w) {
    static const char* high[] = {
        "tion","sion","ation","ment","ness","able","ible","ous","ive",
        "ity","ize","ise","ify","ance","ence","ously","fully"
    };
    static const char* low[] = {
        "th","dom","hood","ship","wise","ward","less","ful","most"
    };
    size_t n = w.size();
    for (auto* s : high) {
        size_t m = strlen(s);
        if (n > m + 2 && w.compare(n - m, m, s) == 0) return 1.15f;
    }
    for (auto* s : low) {
        size_t m = strlen(s);
        if (n > m + 2 && w.compare(n - m, m, s) == 0) return 1.02f;
    }
    return 1.0f;
}

// ── 规则词形还原回退 ─────────────────────────────────────────
std::string rule_lemma(const std::string& w) {
    auto exists = [](const std::string& s) { return g_freq.count(s) || g_lemma.count(s); };
    size_t n = w.size();
    auto ends = [&](const char* s) { size_t m = strlen(s); return n > m + 1 && w.compare(n - m, m, s) == 0; };
    if (ends("ies") && n > 4) { std::string b = w.substr(0, n - 3) + "y"; if (exists(b)) return b; }
    if (ends("ves") && n > 4) {
        std::string b = w.substr(0, n - 3) + "f"; if (exists(b)) return b;
        std::string b2 = w.substr(0, n - 3) + "fe"; if (exists(b2)) return b2;
    }
    if (ends("es") && n > 3) {
        std::string b = w.substr(0, n - 2); if (exists(b)) return b;
        std::string b2 = w.substr(0, n - 1); if (exists(b2)) return b2;
    }
    if (ends("s") && !ends("ss") && n > 3) { std::string b = w.substr(0, n - 1); if (exists(b)) return b; }
    if (ends("ing") && n > 5) {
        std::string b = w.substr(0, n - 3); if (exists(b)) return b;
        std::string b2 = b + "e"; if (exists(b2)) return b2;
        if (b.size() > 1 && b[b.size()-1] == b[b.size()-2]) { std::string b3 = b.substr(0, b.size()-1); if (exists(b3)) return b3; }
    }
    if (ends("ed") && n > 4) {
        std::string b = w.substr(0, n - 2); if (exists(b)) return b;
        std::string b2 = b + "e"; if (exists(b2)) return b2;
        if (b.size() > 1 && b[b.size()-1] == b[b.size()-2]) { std::string b3 = b.substr(0, b.size()-1); if (exists(b3)) return b3; }
    }
    if (ends("er") && n > 4) { std::string b = w.substr(0, n - 2); if (exists(b)) return b; }
    if (ends("est") && n > 5) { std::string b = w.substr(0, n - 3); if (exists(b)) return b; }
    if (ends("ly") && n > 4) { std::string b = w.substr(0, n - 2); if (exists(b)) return b; }
    return w;
}

std::string to_lemma(const std::string& low) {
    auto it = g_lemma.find(low);
    if (it != g_lemma.end()) return it->second;
    return rule_lemma(low);
}

float lookup_zipf(const std::string& low) {
    auto it = g_freq.find(low);
    if (it != g_freq.end()) return it->second;
    auto jt = g_lemma.find(low);
    if (jt != g_lemma.end()) { auto kt = g_freq.find(jt->second); if (kt != g_freq.end()) return kt->second - 0.3f; }
    return 2.0f;
}

int zipf_to_cefr(float z) {
    int best = 1; float bd = 1e9f;
    for (int i = 0; i < 6; ++i) { float d = fabsf(z - kCefrZipf[i]); if (d < bd) { bd = d; best = i + 1; } }
    return best;
}

std::string collapse_ws(const std::string& s) {
    std::string r; bool sp = false;
    for (char c : s) {
        if (c==' '||c=='\t'||c=='\r'||c=='\n') { sp = true; continue; }
        if (sp && !r.empty()) r += ' ';
        sp = false; r += c;
    }
    return r;
}

struct WordStat {
    std::string display, context;
    int count = 0;
    int cap_total = 0;
    int nonsinit_total = 0;
    int cap_nonsinit = 0;
    uint8_t chunks = 0;   // 8 个 chunk 的位图
};

struct Candidate {
    std::string word, context;
    float score, zipf;
    int   count, level;
};

// 读取键值 tsv 的通用加载
bool load_kv(const std::string& path, std::unordered_map<std::string, std::string>& m) {
    FILE* f = fopen(path.c_str(), "r");
    if (!f) return false;
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        char* tab = strchr(line, '\t');
        if (!tab) continue;
        *tab = '\0';
        std::string v(tab + 1);
        while (!v.empty() && (v.back()=='\n'||v.back()=='\r')) v.pop_back();
        if (!v.empty()) m[line] = v;
    }
    fclose(f);
    return true;
}

} // namespace

extern "C" {

void* wp_create(const char* freq_path) {
    if (!freq_path) return nullptr;
    FILE* f = fopen(freq_path, "r");
    if (!f) return nullptr;
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        char* tab = strchr(line, '\t');
        if (!tab) continue;
        *tab = '\0';
        g_freq[line] = strtof(tab + 1, nullptr);
    }
    fclose(f);

    std::string lp(freq_path);
    size_t slash = lp.find_last_of('/');
    std::string dir = (slash == std::string::npos) ? "" : lp.substr(0, slash + 1);

    // 词形还原表
    std::unordered_map<std::string, std::string> lm;
    if (load_kv(dir + "en_lemma.tsv", lm)) g_lemma.swap(lm);
    // 可选 CEFR 词表
    std::unordered_map<std::string, std::string> cm;
    if (load_kv(dir + "en_cefr.tsv", cm)) {
        for (auto& kv : cm) {
            int lv = atoi(kv.second.c_str());
            if (lv >= 1 && lv <= 6) g_cefr[kv.first] = lv;
        }
    }
    return &g_freq;
}

int wp_select_ex(void* handle, const char* text, const wp_config_t* cfg,
                 wp_word_t* out, int out_cap) {
    if (!handle || !text || !out || out_cap <= 0 || !cfg) return 0;

    int   max_words  = cfg->max_words > 0 ? cfg->max_words : out_cap;
    int   min_len    = cfg->min_len   > 0 ? cfg->min_len   : 5;
    float target     = cfg->target_zipf > 0 ? cfg->target_zipf : 3.8f;
    if (cfg->level >= 1 && cfg->level <= 6) target = kCefrZipf[cfg->level - 1];
    int   mode       = cfg->mode;
    float known_zipf = cfg->known_zipf > 0 ? cfg->known_zipf : 5.0f;

    const size_t text_len = strlen(text);
    std::unordered_map<std::string, WordStat> stats;
    stats.reserve(4096);

    // 按句切分，同时跟踪 byte offset 以计算 chunk
    const char* q = text;
    std::string sent;
    auto flush = [&](const std::string& s, size_t off_end) {
        std::string sentence = collapse_ws(s);
        if (sentence.empty()) return;
        int total = (int)sentence.size();
        int alpha = 0;
        for (char c : sentence) if (is_alpha(c) || c == ' ') ++alpha;
        if (total == 0 || (float)alpha / total < 0.65f) return;
        int marks = 0;
        for (char c : sentence)
            if (c==':'||c=='{'||c=='}'||c=='<'||c=='>'||c=='='||c=='/'||c=='@'||c==';') ++marks;
        if (marks > 2) return;

        int chunk = text_len ? (int)((off_end * 8) / text_len) : 0;
        if (chunk > 7) chunk = 7;

        bool first = true;   // 句首词
        size_t i = 0, n = sentence.size();
        while (i < n) {
            if (!is_alpha(sentence[i])) { ++i; continue; }
            size_t j = i;
            while (j < n && (is_alpha(sentence[j]) || (sentence[j]=='\'' && j+1<n && is_alpha(sentence[j+1])))) ++j;
            std::string raw = sentence.substr(i, j - i);
            i = j;
            if (raw.empty()) continue;
            std::string low = lower_ascii(raw);
            bool is_cap = (raw[0] >= 'A' && raw[0] <= 'Z');
            bool s_init = first;
            first = false;

            if (is_noise(raw, low)) continue;
            std::string lemma = to_lemma(low);
            if ((int)lemma.size() < min_len || lemma.size() > 24) continue;
            if (stopwords().count(lemma) || common_words().count(lemma)) continue;

            WordStat& st = stats[lemma];
            if (st.display.empty()) st.display = lemma;
            st.count++;
            if (is_cap) st.cap_total++;
            if (!s_init) { st.nonsinit_total++; if (is_cap) st.cap_nonsinit++; }
            st.chunks |= (uint8_t)(1u << chunk);
            if (st.context.empty()) {
                std::string c = sentence;
                if (c.size() > 255) c = c.substr(0, 255);
                st.context = c;
            }
        }
    };

    for (; ; ++q) {
        char c = *q;
        if (c == '\0') { flush(sent, (size_t)(q - text)); break; }
        if (c == '.' || c == '!' || c == '?' || c == '\n') {
            flush(sent, (size_t)(q - text));
            sent.clear();
        } else sent += c;
    }

    int max_count = 1;
    for (auto& kv : stats) if (kv.second.count > max_count) max_count = kv.second.count;

    const float sigma_easy = 0.65f;   // 太简单 → 陡衰减
    const float sigma_hard = 1.10f;   // 生僻 → 长尾
    std::vector<Candidate> cands;
    cands.reserve(stats.size());

    for (auto& kv : stats) {
        const std::string& w = kv.first;
        WordStat& st = kv.second;

        // B) CapRatio 专有名词过滤
        int lower_total = st.count - st.cap_total;
        if (lower_total == 0 && st.count >= 2) continue;
        if (st.nonsinit_total > 3 && (float)st.cap_nonsinit / st.nonsinit_total > 0.7f) continue;

        float zipf = lookup_zipf(w);
        int level = 0;
        auto cit = g_cefr.find(w);
        if (cit != g_cefr.end()) { level = cit->second; zipf = kCefrZipf[level - 1]; }
        if (zipf > 6.3f || zipf < 1.8f) continue;

        int pop = 0; for (int b = 0; b < 8; ++b) if (st.chunks & (1u << b)) ++pop;
        float spread = pop / 8.0f;
        float spread_f = 0.8f + 0.2f * spread;

        float score;
        if (mode == 1) {
            // F) 覆盖率模式：只取未知词，边际覆盖 = 词频
            if (zipf > known_zipf) continue;
            float d = zipf - target;
            float s = (d > 0) ? sigma_easy : sigma_hard;
            float U = expf(-(d * d) / (2.0f * s * s));
            score = U * (float)st.count;
        } else {
            float d = zipf - target;
            float s = (d > 0) ? sigma_easy : sigma_hard;   // A) 偏态
            float U = expf(-(d * d) / (2.0f * s * s));
            float rel = logf(1.0f + st.count) / logf(1.0f + max_count);
            float prod = productivity(w);                   // C) 分级
            float lenpen = (w.size() > 13) ? 0.88f : 1.0f;
            score = U * (0.35f + 0.65f * rel) * spread_f * prod * lenpen;  // D) spread
        }
        if (level == 0) level = zipf_to_cefr(zipf);
        cands.push_back({w, st.context, score, zipf, st.count, level});
    }

    std::sort(cands.begin(), cands.end(), [](const Candidate& a, const Candidate& b) {
        if (a.score != b.score) return a.score > b.score;
        return a.word < b.word;
    });

    int n = std::min((int)cands.size(), std::min(max_words, out_cap));
    for (int i = 0; i < n; ++i) {
        wp_word_t& o = out[i];
        memset(&o, 0, sizeof(o));
        strncpy(o.word, cands[i].word.c_str(), sizeof(o.word) - 1);
        strncpy(o.context, cands[i].context.c_str(), sizeof(o.context) - 1);
        o.score = cands[i].score;
        o.zipf  = cands[i].zipf;
        o.count = cands[i].count;
        o.level = cands[i].level;
    }
    return n;
}

int wp_select(void* handle, const char* text, int max_words,
              float target_zipf, int min_len, wp_word_t* out, int out_cap) {
    wp_config_t cfg;
    memset(&cfg, 0, sizeof(cfg));
    cfg.max_words = max_words;
    cfg.target_zipf = target_zipf;
    cfg.min_len = min_len;
    return wp_select_ex(handle, text, &cfg, out, out_cap);
}

void wp_destroy(void* handle) {
    (void)handle;
    g_freq.clear(); g_lemma.clear(); g_cefr.clear();
}

} // extern "C"
