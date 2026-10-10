// store.h — 基于 my_db KV Cache (mmap 零拷贝) 的记忆存储层
//
// 自定义数据结构：学习项 wc_item_t + SM-2 记忆态 wc_mem_t，
// 以 base64 二进制存入 KV Cache 的 mmap 池 (cache.bin)。
//
// 键设计：
//   /wc/item/<id>         -> base64(wc_item_t)
//   /wc/word/<word_lower> -> "<id>"
//   /wc/seq/item          -> "<next_id>"
//   /wc/mem/<uid>/<id>    -> base64(wc_mem_t)
#ifndef WC_STORE_H
#define WC_STORE_H

#include <stdint.h>
#include <stddef.h>

typedef struct wc_store wc_store_t;

typedef struct {
    uint32_t id;
    char question[512];
    char answer[512];
    char explanation[1024];
    char hint[256];
    char tags[128];
    uint8_t difficulty;
} wc_item_t;

typedef struct {
    uint32_t user_id;
    uint32_t item_id;
    uint8_t  status;        // 0 新, 1 学习, 2 掌握
    uint16_t interval_days;
    uint16_t repetitions;
    float    ef;
    uint32_t next_review;
    uint32_t last_review;
    uint8_t  recognition, recall, spelling, listening, pronunciation, usage, overall;
    uint16_t total_reviews, correct_count, wrong_count;
    uint8_t  streak_days, forget_count;
} wc_mem_t;

wc_store_t* wc_store_open(const char* dir, size_t max_memory);
void wc_store_close(wc_store_t* s);
int  wc_store_sync(wc_store_t* s);

uint32_t wc_store_add_item(wc_store_t* s, const wc_item_t* it);
int      wc_store_get_item(wc_store_t* s, uint32_t id, wc_item_t* out);
uint32_t wc_store_find_by_word(wc_store_t* s, const char* word);

int    wc_store_mem_get(wc_store_t* s, uint32_t uid, uint32_t item, wc_mem_t* out);
int    wc_store_sm2(wc_store_t* s, uint32_t uid, uint32_t item, uint8_t quality, wc_mem_t* out);
size_t wc_store_due(wc_store_t* s, uint32_t uid, uint32_t now,
                    uint32_t* out_ids, size_t max);

#endif
