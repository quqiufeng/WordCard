// store.c — 基于 KV Cache (mmap 零拷贝) 的记忆存储实现
#include "store.h"
#include "cache.h"

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <math.h>
#include <time.h>

struct wc_store {
    cache_t* cache;
};

/* ── base64（struct <-> 文本，存进 KV）── */
static const char B64[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static char* b64_encode(const unsigned char* data, size_t len) {
    size_t olen = 4 * ((len + 2) / 3);
    char* out = (char*)malloc(olen + 1);
    if (!out) return NULL;
    size_t i, j = 0;
    for (i = 0; i < len; i += 3) {
        unsigned v = (unsigned)data[i] << 16;
        if (i + 1 < len) v |= (unsigned)data[i + 1] << 8;
        if (i + 2 < len) v |= (unsigned)data[i + 2];
        out[j++] = B64[(v >> 18) & 63];
        out[j++] = B64[(v >> 12) & 63];
        out[j++] = (i + 1 < len) ? B64[(v >> 6) & 63] : '=';
        out[j++] = (i + 2 < len) ? B64[v & 63] : '=';
    }
    out[j] = '\0';
    return out;
}

static int b64_val(char c) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return -1;
}

static size_t b64_decode(const char* s, unsigned char* out, size_t outcap) {
    size_t n = 0;
    unsigned v = 0;
    int bits = 0;
    for (; *s; s++) {
        if (*s == '=' || *s == '\n') continue;
        int d = b64_val(*s);
        if (d < 0) continue;
        v = (v << 6) | (unsigned)d;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            if (n < outcap) out[n] = (unsigned char)((v >> bits) & 0xFF);
            n++;
        }
    }
    return n;
}

static void lower_copy(char* dst, size_t cap, const char* src) {
    size_t i = 0;
    for (; src[i] && i < cap - 1; i++) {
        char c = src[i];
        dst[i] = (c >= 'A' && c <= 'Z') ? (char)(c - 'A' + 'a') : c;
    }
    dst[i] = '\0';
}

/* ── 生命周期 ── */
wc_store_t* wc_store_open(const char* dir, size_t max_memory) {
    cache_t* c = cache_open(dir, max_memory);
    if (!c) return NULL;
    wc_store_t* s = (wc_store_t*)calloc(1, sizeof(wc_store_t));
    if (!s) { cache_close(c); return NULL; }
    s->cache = c;
    return s;
}

void wc_store_close(wc_store_t* s) {
    if (!s) return;
    cache_sync(s->cache);
    cache_close(s->cache);
    free(s);
}

int wc_store_sync(wc_store_t* s) { return s ? cache_sync(s->cache) : -1; }

/* ── 学习项 ── */
static uint32_t next_seq(wc_store_t* s, const char* key) {
    const char* v = cache_get(s->cache, key);
    uint32_t n = v ? (uint32_t)strtoul(v, NULL, 10) : 0;
    n++;
    char buf[32];
    snprintf(buf, sizeof(buf), "%u", n);
    cache_set(s->cache, key, buf, 0);
    return n;
}

uint32_t wc_store_add_item(wc_store_t* s, const wc_item_t* it) {
    if (!s || !it || !it->question[0]) return 0;
    char wl[512];
    lower_copy(wl, sizeof(wl), it->question);
    char wkey[600];
    snprintf(wkey, sizeof(wkey), "/wc/word/%s", wl);
    const char* exist = cache_get(s->cache, wkey);
    if (exist) return (uint32_t)strtoul(exist, NULL, 10);

    uint32_t id = next_seq(s, "/wc/seq/item");
    wc_item_t copy = *it;
    copy.id = id;
    char* enc = b64_encode((const unsigned char*)&copy, sizeof(copy));
    if (!enc) return 0;
    char ikey[64];
    snprintf(ikey, sizeof(ikey), "/wc/item/%u", id);
    cache_set(s->cache, ikey, enc, 0);
    free(enc);

    char idbuf[32];
    snprintf(idbuf, sizeof(idbuf), "%u", id);
    cache_set(s->cache, wkey, idbuf, 0);
    return id;
}

int wc_store_get_item(wc_store_t* s, uint32_t id, wc_item_t* out) {
    if (!s || !out) return -1;
    char key[64];
    snprintf(key, sizeof(key), "/wc/item/%u", id);
    const char* v = cache_get(s->cache, key);
    if (!v) return -1;
    if (b64_decode(v, (unsigned char*)out, sizeof(*out)) != sizeof(*out)) return -1;
    return 0;
}

uint32_t wc_store_find_by_word(wc_store_t* s, const char* word) {
    if (!s || !word) return 0;
    char wl[512];
    lower_copy(wl, sizeof(wl), word);
    char wkey[600];
    snprintf(wkey, sizeof(wkey), "/wc/word/%s", wl);
    const char* v = cache_get(s->cache, wkey);
    return v ? (uint32_t)strtoul(v, NULL, 10) : 0;
}

/* ── SM-2 记忆态 ── */
static void mem_default(wc_mem_t* m, uint32_t uid, uint32_t item) {
    memset(m, 0, sizeof(*m));
    m->user_id = uid;
    m->item_id = item;
    m->status = 0;
    m->ef = 2.5f;
}

int wc_store_mem_get(wc_store_t* s, uint32_t uid, uint32_t item, wc_mem_t* out) {
    if (!s || !out) return -1;
    char key[80];
    snprintf(key, sizeof(key), "/wc/mem/%u/%u", uid, item);
    const char* v = cache_get(s->cache, key);
    if (!v) { mem_default(out, uid, item); return -1; }
    if (b64_decode(v, (unsigned char*)out, sizeof(*out)) != sizeof(*out)) {
        mem_default(out, uid, item);
        return -1;
    }
    return 0;
}

static void mem_store(wc_store_t* s, const wc_mem_t* m) {
    char key[80];
    snprintf(key, sizeof(key), "/wc/mem/%u/%u", m->user_id, m->item_id);
    char* enc = b64_encode((const unsigned char*)m, sizeof(*m));
    if (enc) { cache_set(s->cache, key, enc, 0); free(enc); }
}

int wc_store_sm2(wc_store_t* s, uint32_t uid, uint32_t item, uint8_t q,
                 wc_mem_t* out) {
    if (!s) return -1;
    wc_mem_t m;
    wc_store_mem_get(s, uid, item, &m);

    uint32_t now = (uint32_t)time(NULL);
    m.total_reviews++;
    m.last_review = now;
    if (q < 3) {
        m.repetitions = 0;
        m.interval_days = 1;
        m.status = 0;
        m.wrong_count++;
        m.forget_count++;
    } else {
        m.correct_count++;
        m.repetitions++;
        if (m.repetitions == 1) m.interval_days = 1;
        else if (m.repetitions == 2) m.interval_days = 6;
        else m.interval_days = (uint16_t)lroundf(m.interval_days * m.ef);
        if (m.repetitions >= 5 && m.interval_days >= 21) m.status = 2;
        else m.status = 1;
    }
    /* ease factor 调整 */
    float d = (float)(5 - q);
    m.ef = m.ef + 0.1f - d * (0.08f + d * 0.02f);
    if (m.ef < 1.3f) m.ef = 1.3f;

    /* 多维掌握度（简化：正确 +10，错误 -15，clamp 0-100） */
    int delta = (q >= 3) ? 10 : -15;
    int v = (int)m.overall + delta;
    if (v < 0) v = 0; else if (v > 100) v = 100;
    m.overall = (uint8_t)v;

    m.next_review = now + (uint32_t)m.interval_days * 86400u;
    mem_store(s, &m);
    if (out) *out = m;
    return 0;
}

size_t wc_store_due(wc_store_t* s, uint32_t uid, uint32_t now,
                    uint32_t* out_ids, size_t max) {
    if (!s || !out_ids) return 0;
    char prefix[48];
    snprintf(prefix, sizeof(prefix), "/wc/mem/%u/", uid);
    cache_search_options_t opts = cache_search_options_default();
    opts.max_results = 0;
    cache_result_t* results = NULL;
    size_t count = 0;
    if (cache_search_prefix(s->cache, prefix, &opts, &results, &count) != 0)
        return 0;
    size_t n = 0;
    for (size_t i = 0; i < count && n < max; i++) {
        wc_mem_t m;
        if (b64_decode(results[i].value, (unsigned char*)&m, sizeof(m)) != sizeof(m))
            continue;
        if (m.next_review == 0 || m.next_review <= now) out_ids[n++] = m.item_id;
    }
    if (results) cache_results_free(results);
    return n;
}
