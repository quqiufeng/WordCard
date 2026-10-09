// wordpick — 从电子书正文中挑选"最值得学习"的英文单词
//
// 核心思想（不是越长越好）：
//   1. 通用词频 zipf(u) 决定难度。学习价值在"适中难度"处最高——
//      太简单（已知）或太生僻（用不上）都降权 → 高斯峰 exp(-((zipf-T)^2)/2σ²)
//   2. 书内词频与分布 → 出现越多越值得记（contextual importance）
//   3. 构词能产性（常见前后缀）→ 可迁移记忆，微加成
//   4. 过长词（>13）轻微惩罚（多为术语/生僻）
//   综合打分 score = U(zipf) * (基础 + 相关性) * 能产性 * 长度因子

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

// ── 加载词频表（word\tzipf） ──────────────────────────────────
std::unordered_map<std::string, float> g_freq;

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
            "were","what","your","about","would","there","their","which","could",
            "other","after","first","never","these","think","where","being",
            "every","great","might","shall","still","those","under","while",
            "before","should","because","through","between","against","without",
            "himself","herself","itself","themselves","ourselves","yourself",
            "myself","another","seemed","always","though","almost","nothing",
            "without","others","later","away","found","nothing","better",
            "except","began","appeared","whole","year","death","hard","morning",
            "soon","suddenly","week","words","already","called","eyes","five",
            "food","given","half","read","came","went","going","gone","does",
            "done","having","upon","thing","things","made","made","said","says",
            "saw","looked","thought","wanted","also","just","much","many",
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
            "small","large","great","little","long","young","important",
            "public","able","human","legs","sheep","hens","horses","cows",
            "pigs","dogs","birds","food","milk","field","walls","year",
            "hours","great","large","came","went","farm","barn","field",
        };
        for (auto* p : w) v.insert(p);
        return v;
    }();
    return s;
}

bool is_roman(const std::string& w) {
    if (w.size() < 2) return false;
    for (char c : w) {
        if (c!='I'&&c!='V'&&c!='X'&&c!='L'&&c!='C'&&c!='D'&&c!='M'&&
            c!='i'&&c!='v'&&c!='x'&&c!='l'&&c!='c'&&c!='d'&&c!='m') return false;
    }
    return true;
}

bool is_noise(const std::string& raw, const std::string& low) {
    // 全大写缩写
    if (raw.size() >= 2) {
        bool all_up = true;
        for (char c : raw) if (!(c >= 'A' && c <= 'Z')) { all_up = false; break; }
        if (all_up) return true;
    }
    if (is_roman(raw)) return true;
    // 无元音且较长
    if (low.size() > 3) {
        bool any_v = false;
        for (char c : low) if (is_vowel(c)) { any_v = true; break; }
        if (!any_v) return true;
    }
    // 单字符重复
    if (low.size() >= 3) {
        bool same = true;
        for (char c : low) if (c != low[0]) { same = false; break; }
        if (same) return true;
    }
    return false;
}

// 构词能产性：常见派生后缀
bool productive_suffix(const std::string& w) {
    static const char* suf[] = {
        "tion","sion","ment","ness","ance","ence","able","ible","ous",
        "ive","ity","ally","ously","fully","less","ship","hood","wise"
    };
    for (auto* s : suf) {
        size_t n = strlen(s);
        if (w.size() > n + 2 && w.compare(w.size() - n, n, s) == 0) return true;
    }
    return false;
}

// 查找 zipf：精确 → 去后缀回退 → 默认
float lookup_zipf(const std::string& low) {
    auto it = g_freq.find(low);
    if (it != g_freq.end()) return it->second;
    // 回退：去常见屈折后缀
    static const char* suf[] = {"s","es","ed","ing","ly","er","est","'s"};
    for (auto* s : suf) {
        size_t n = strlen(s);
        if (low.size() > n + 2 && low.compare(low.size() - n, n, s) == 0) {
            std::string base = low.substr(0, low.size() - n);
            auto jt = g_freq.find(base);
            if (jt != g_freq.end()) return jt->second - 0.3f;
            // 双写辅音回退 (running -> run)
            if (base.size() > 2 && base[base.size()-1] == base[base.size()-2]) {
                auto kt = g_freq.find(base.substr(0, base.size()-1));
                if (kt != g_freq.end()) return kt->second - 0.3f;
            }
        }
    }
    return 2.0f;   // 未收录 → 视为生僻
}

struct WordStat {
    std::string display;
    std::string context;
    int  count = 0;
    bool lower_seen = false;
};

struct Candidate {
    std::string word;
    std::string context;
    float score;
    float zipf;
    int   count;
};

std::string collapse_ws(const std::string& s) {
    std::string r;
    bool sp = false;
    for (char c : s) {
        if (c==' '||c=='\t'||c=='\r'||c=='\n') { sp = true; continue; }
        if (sp && !r.empty()) r += ' ';
        sp = false;
        r += c;
    }
    return r;
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
        float z = strtof(tab + 1, nullptr);
        g_freq[line] = z;
    }
    fclose(f);
    return &g_freq;
}

int wp_select(void* handle, const char* text, int max_words,
              float target_zipf, int min_len, wp_word_t* out, int out_cap) {
    if (!handle || !text || !out || out_cap <= 0) return 0;
    if (target_zipf <= 0) target_zipf = 3.8f;
    if (min_len <= 0) min_len = 5;
    if (max_words <= 0) max_words = out_cap;

    std::unordered_map<std::string, WordStat> stats;
    stats.reserve(4096);

    // 按句切分（. ! ? 及换行）
    std::string sent;
    auto flush_sentence = [&](const std::string& s) {
        std::string sentence = collapse_ws(s);
        if (sentence.empty()) return;
        // 正文质量过滤：跳过 CSS/HTML/表格/编号行
        {
            int alpha = 0, total = (int)sentence.size();
            for (char c : sentence) if (is_alpha(c) || c == ' ') ++alpha;
            if (total == 0 || (float)alpha / total < 0.65f) return;
            int marks = 0;
            for (char c : sentence)
                if (c==':'||c=='{'||c=='}'||c=='<'||c=='>'||c=='='||c=='/'||c=='@'||c==';') ++marks;
            if (marks > 2) return;
            { int sc=0; for(char ch:sentence) if(ch==';') ++sc; if(sc>0) return; }
        }
        // 分词
        size_t i = 0, n = sentence.size();
        while (i < n) {
            if (!is_alpha(sentence[i])) { ++i; continue; }
            size_t j = i;
            while (j < n && (is_alpha(sentence[j]) || (sentence[j]=='\'' && j+1<n && is_alpha(sentence[j+1])))) ++j;
            std::string raw = sentence.substr(i, j - i);
            i = j;
            if (raw.empty()) continue;
            std::string low = lower_ascii(raw);
            if ((int)low.size() < min_len || low.size() > 24) continue;
            if (stopwords().count(low) || common_words().count(low)) continue;
            if (is_noise(raw, low)) continue;
            WordStat& st = stats[low];
            if (st.display.empty()) st.display = raw;
            st.count++;
            if (raw == low) st.lower_seen = true;
            if (st.context.empty()) {
                std::string c = sentence;
                if (c.size() > 255) c = c.substr(0, 255);
                st.context = c;
            }
        }
    };

    for (const char* q = text; ; ++q) {
        char c = *q;
        if (c == '\0') { flush_sentence(sent); break; }
        if (c == '.' || c == '!' || c == '?' || c == '\n') {
            flush_sentence(sent);
            sent.clear();
        } else {
            sent += c;
        }
    }

    // 统计最高词频用于归一化
    int max_count = 1;
    for (auto& kv : stats) if (kv.second.count > max_count) max_count = kv.second.count;

    const float T = target_zipf;
    const float sigma = 0.9f;
    std::vector<Candidate> cands;
    cands.reserve(stats.size());

    for (auto& kv : stats) {
        const std::string& w = kv.first;
        WordStat& st = kv.second;
        if (!st.lower_seen) continue;          // 专有名词
        float zipf = lookup_zipf(w);
        if (zipf > 6.3f || zipf < 1.8f) continue;  // 太简单/太生僻
        float d = zipf - T;
        float U = expf(-(d * d) / (2.0f * sigma * sigma));
        float rel = logf(1.0f + st.count) / logf(1.0f + max_count);
        float prod = productive_suffix(w) ? 1.08f : 1.0f;
        float lenpen = (w.size() > 13) ? 0.88f : 1.0f;
        float score = U * (0.35f + 0.65f * rel) * prod * lenpen;
        cands.push_back({w, st.context, score, zipf, st.count});
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
        o.zipf = cands[i].zipf;
        o.count = cands[i].count;
    }
    return n;
}

void wp_destroy(void* handle) {
    (void)handle;
    g_freq.clear();
}

} // extern "C"
