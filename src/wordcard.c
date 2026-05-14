#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <pthread.h>
#include "wordcard.h"

/* ========================================================================
 * 简单哈希表实现（链地址法）
 * ======================================================================== */

#define HASH_LOAD_FACTOR 0.75f

typedef struct int_node {
    uint32_t key;
    int value;
    struct int_node *next;
} int_node_t;

typedef struct {
    int_node_t **buckets;
    size_t size;
    size_t count;
} int_hash_t;

typedef struct str_node {
    char key[128];
    int value;
    struct str_node *next;
} str_node_t;

typedef struct {
    str_node_t **buckets;
    size_t size;
    size_t count;
} str_hash_t;

typedef struct pair_node {
    uint32_t key1;
    uint32_t key2;
    int value;
    struct pair_node *next;
} pair_node_t;

typedef struct {
    pair_node_t **buckets;
    size_t size;
    size_t count;
} pair_hash_t;

static int_hash_t* int_hash_new(size_t size) {
    int_hash_t *h = calloc(1, sizeof(int_hash_t));
    h->size = size;
    h->buckets = calloc(size, sizeof(int_node_t*));
    return h;
}

static void int_hash_free(int_hash_t *h) {
    if (!h) return;
    for (size_t i = 0; i < h->size; i++) {
        int_node_t *n = h->buckets[i];
        while (n) {
            int_node_t *tmp = n;
            n = n->next;
            free(tmp);
        }
    }
    free(h->buckets);
    free(h);
}

static void int_hash_resize(int_hash_t *h, size_t new_size);

static void int_hash_set(int_hash_t *h, uint32_t key, int value) {
    size_t idx = key % h->size;
    int_node_t *n = h->buckets[idx];
    while (n) {
        if (n->key == key) { n->value = value; return; }
        n = n->next;
    }
    n = malloc(sizeof(int_node_t));
    n->key = key; n->value = value;
    n->next = h->buckets[idx];
    h->buckets[idx] = n;
    h->count++;
    
    if ((float)h->count / (float)h->size > HASH_LOAD_FACTOR) {
        int_hash_resize(h, h->size * 2);
    }
}

static int int_hash_get(int_hash_t *h, uint32_t key, int *out) {
    size_t idx = key % h->size;
    int_node_t *n = h->buckets[idx];
    while (n) {
        if (n->key == key) { *out = n->value; return 1; }
        n = n->next;
    }
    return 0;
}

static void int_hash_resize(int_hash_t *h, size_t new_size) {
    if (new_size <= h->size) return;
    int_node_t **old_buckets = h->buckets;
    size_t old_size = h->size;
    
    h->buckets = calloc(new_size, sizeof(int_node_t*));
    h->size = new_size;
    
    for (size_t i = 0; i < old_size; i++) {
        int_node_t *n = old_buckets[i];
        while (n) {
            int_node_t *next = n->next;
            size_t idx = n->key % h->size;
            n->next = h->buckets[idx];
            h->buckets[idx] = n;
            n = next;
        }
    }
    free(old_buckets);
}

static str_hash_t* str_hash_new(size_t size) {
    str_hash_t *h = calloc(1, sizeof(str_hash_t));
    h->size = size;
    h->buckets = calloc(size, sizeof(str_node_t*));
    return h;
}

static void str_hash_free(str_hash_t *h) {
    if (!h) return;
    for (size_t i = 0; i < h->size; i++) {
        str_node_t *n = h->buckets[i];
        while (n) {
            str_node_t *tmp = n;
            n = n->next;
            free(tmp);
        }
    }
    free(h->buckets);
    free(h);
}

static void str_hash_resize(str_hash_t *h, size_t new_size);

static size_t str_hash_idx(str_hash_t *h, const char *key) {
    size_t idx = 0;
    for (const char *p = key; *p; p++) idx = idx * 31 + *p;
    return idx % h->size;
}

static void str_hash_set(str_hash_t *h, const char *key, int value) {
    size_t idx = str_hash_idx(h, key);
    str_node_t *n = h->buckets[idx];
    while (n) {
        if (strcmp(n->key, key) == 0) { n->value = value; return; }
        n = n->next;
    }
    n = malloc(sizeof(str_node_t));
    strncpy(n->key, key, sizeof(n->key)-1);
    n->key[sizeof(n->key)-1] = '\0';
    n->value = value;
    n->next = h->buckets[idx];
    h->buckets[idx] = n;
    h->count++;
    
    if ((float)h->count / (float)h->size > HASH_LOAD_FACTOR) {
        str_hash_resize(h, h->size * 2);
    }
}

static int str_hash_get(str_hash_t *h, const char *key, int *out) {
    size_t idx = str_hash_idx(h, key);
    str_node_t *n = h->buckets[idx];
    while (n) {
        if (strcmp(n->key, key) == 0) { *out = n->value; return 1; }
        n = n->next;
    }
    return 0;
}

static void str_hash_resize(str_hash_t *h, size_t new_size) {
    if (new_size <= h->size) return;
    str_node_t **old_buckets = h->buckets;
    size_t old_size = h->size;
    
    h->buckets = calloc(new_size, sizeof(str_node_t*));
    h->size = new_size;
    
    for (size_t i = 0; i < old_size; i++) {
        str_node_t *n = old_buckets[i];
        while (n) {
            str_node_t *next = n->next;
            size_t idx = str_hash_idx(h, n->key);
            n->next = h->buckets[idx];
            h->buckets[idx] = n;
            n = next;
        }
    }
    free(old_buckets);
}

static pair_hash_t* pair_hash_new(size_t size) {
    pair_hash_t *h = calloc(1, sizeof(pair_hash_t));
    h->size = size;
    h->buckets = calloc(size, sizeof(pair_node_t*));
    return h;
}

static void pair_hash_free(pair_hash_t *h) {
    if (!h) return;
    for (size_t i = 0; i < h->size; i++) {
        pair_node_t *n = h->buckets[i];
        while (n) {
            pair_node_t *tmp = n;
            n = n->next;
            free(tmp);
        }
    }
    free(h->buckets);
    free(h);
}

static void pair_hash_resize(pair_hash_t *h, size_t new_size);

static size_t pair_hash_idx(pair_hash_t *h, uint32_t k1, uint32_t k2) {
    uint64_t combined = ((uint64_t)k1 << 32) | k2;
    return (size_t)(combined % h->size);
}

static void pair_hash_set(pair_hash_t *h, uint32_t k1, uint32_t k2, int value) {
    size_t idx = pair_hash_idx(h, k1, k2);
    pair_node_t *n = h->buckets[idx];
    while (n) {
        if (n->key1 == k1 && n->key2 == k2) { n->value = value; return; }
        n = n->next;
    }
    n = malloc(sizeof(pair_node_t));
    n->key1 = k1; n->key2 = k2; n->value = value;
    n->next = h->buckets[idx];
    h->buckets[idx] = n;
    h->count++;
    
    if ((float)h->count / (float)h->size > HASH_LOAD_FACTOR) {
        pair_hash_resize(h, h->size * 2);
    }
}

static int pair_hash_get(pair_hash_t *h, uint32_t k1, uint32_t k2, int *out) {
    size_t idx = pair_hash_idx(h, k1, k2);
    pair_node_t *n = h->buckets[idx];
    while (n) {
        if (n->key1 == k1 && n->key2 == k2) { *out = n->value; return 1; }
        n = n->next;
    }
    return 0;
}

static void pair_hash_resize(pair_hash_t *h, size_t new_size) {
    if (new_size <= h->size) return;
    pair_node_t **old_buckets = h->buckets;
    size_t old_size = h->size;
    
    h->buckets = calloc(new_size, sizeof(pair_node_t*));
    h->size = new_size;
    
    for (size_t i = 0; i < old_size; i++) {
        pair_node_t *n = old_buckets[i];
        while (n) {
            pair_node_t *next = n->next;
            size_t idx = pair_hash_idx(h, n->key1, n->key2);
            n->next = h->buckets[idx];
            h->buckets[idx] = n;
            n = next;
        }
    }
    free(old_buckets);
}

/* ========================================================================
 * 全局锁（线程安全）
 * ======================================================================== */

static pthread_mutex_t g_db_mutex = PTHREAD_MUTEX_INITIALIZER;

#define LOCK()   pthread_mutex_lock(&g_db_mutex)
#define UNLOCK() pthread_mutex_unlock(&g_db_mutex)

/* ========================================================================
 * 内部辅助函数
 * ======================================================================== */

static void* ensure_array(void *arr, size_t count, size_t *cap, size_t elem_size) {
    if (count >= *cap) {
        size_t new_cap = *cap * WC_GROWTH_FACTOR;
        if (new_cap < WC_INIT_CAPACITY) new_cap = WC_INIT_CAPACITY;
        void *new_arr = realloc(arr, new_cap * elem_size);
        if (!new_arr) return NULL;
        *cap = new_cap;
        return new_arr;
    }
    return arr;
}

static wordcard_db_t *g_sort_db = NULL;

static int compare_mastery_by_due(const void *a, const void *b) {
    uint32_t idx_a = *(const uint32_t*)a;
    uint32_t idx_b = *(const uint32_t*)b;
    uint32_t due_a = g_sort_db->mastery[idx_a].next_review;
    uint32_t due_b = g_sort_db->mastery[idx_b].next_review;
    if (due_a < due_b) return -1;
    if (due_a > due_b) return 1;
    return 0;
}

static void rebuild_due_index(wordcard_db_t *db) {
    if (!db->mastery_due_dirty && db->mastery_due_sorted_count == db->mastery_count) {
        return;
    }
    
    if (db->mastery_capacity > 0 && !db->mastery_due_sorted) {
        db->mastery_due_sorted = malloc(db->mastery_capacity * sizeof(uint32_t));
    }
    if (!db->mastery_due_sorted) return;
    
    db->mastery_due_sorted_count = db->mastery_count;
    for (size_t i = 0; i < db->mastery_count; i++) {
        db->mastery_due_sorted[i] = (uint32_t)i;
    }
    
    if (db->mastery_count > 1) {
        g_sort_db = db;
        qsort(db->mastery_due_sorted, db->mastery_count, sizeof(uint32_t), compare_mastery_by_due);
        g_sort_db = NULL;
    }
    
    db->mastery_due_dirty = 0;
}

static void rebuild_indexes(wordcard_db_t *db) {
    /* 重建 id_hash */
    int_hash_free((int_hash_t*)db->id_hash);
    db->id_hash = int_hash_new(db->item_capacity * 2 + 1);
    for (size_t i = 0; i < db->item_count; i++) {
        int_hash_set((int_hash_t*)db->id_hash, db->items[i].id, (int)i);
    }
    
    /* 重建 question_hash */
    str_hash_free((str_hash_t*)db->question_hash);
    db->question_hash = str_hash_new(db->item_capacity * 2 + 1);
    for (size_t i = 0; i < db->item_count; i++) {
        str_hash_set((str_hash_t*)db->question_hash, db->items[i].question, (int)i);
    }
    
    /* 重建 source_hash */
    int_hash_free((int_hash_t*)db->source_hash);
    db->source_hash = int_hash_new(db->source_capacity * 2 + 1);
    for (size_t i = 0; i < db->source_count; i++) {
        int_hash_set((int_hash_t*)db->source_hash, db->sources[i].id, (int)i);
    }
    
    /* 重建 user_hash */
    str_hash_free((str_hash_t*)db->user_hash);
    db->user_hash = str_hash_new(db->user_capacity * 2 + 1);
    for (size_t i = 0; i < db->user_count; i++) {
        str_hash_set((str_hash_t*)db->user_hash, db->users[i].dingtalk_uid, (int)i);
    }
    
    /* 重建 user_id_hash */
    int_hash_free((int_hash_t*)db->user_id_hash);
    db->user_id_hash = int_hash_new(db->user_capacity * 2 + 1);
    for (size_t i = 0; i < db->user_count; i++) {
        int_hash_set((int_hash_t*)db->user_id_hash, db->users[i].id, (int)i);
    }
    
    /* 重建 mastery_hash */
    pair_hash_free((pair_hash_t*)db->mastery_hash);
    db->mastery_hash = pair_hash_new(db->mastery_capacity * 2 + 1);
    for (size_t i = 0; i < db->mastery_count; i++) {
        pair_hash_set((pair_hash_t*)db->mastery_hash, 
                      db->mastery[i].user_id, db->mastery[i].item_id, (int)i);
    }
    
    /* 重建 stat_hash */
    pair_hash_free((pair_hash_t*)db->stat_hash);
    db->stat_hash = pair_hash_new(db->stat_capacity * 2 + 1);
    for (size_t i = 0; i < db->stat_count; i++) {
        pair_hash_set((pair_hash_t*)db->stat_hash,
                      db->stats[i].user_id, db->stats[i].date, (int)i);
    }
    
    /* 重建到期复习索引 */
    db->mastery_due_dirty = 1;
    rebuild_due_index(db);
}

/* ========================================================================
 * 数据库生命周期
 * ======================================================================== */

wordcard_db_t* wc_db_init(void) {
    wordcard_db_t *db = calloc(1, sizeof(wordcard_db_t));
    if (!db) return NULL;
    
    db->item_capacity = WC_INIT_CAPACITY;
    db->items = calloc(db->item_capacity, sizeof(item_entry_t));
    
    db->source_capacity = 64;
    db->sources = calloc(db->source_capacity, sizeof(content_source_t));
    
    db->chapter_capacity = 256;
    db->chapters = calloc(db->chapter_capacity, sizeof(chapter_t));
    
    db->user_capacity = WC_INIT_CAPACITY;
    db->users = calloc(db->user_capacity, sizeof(user_t));
    
    db->mastery_capacity = WC_INIT_CAPACITY;
    db->mastery = calloc(db->mastery_capacity, sizeof(user_item_mastery_t));
    
    db->progress_capacity = WC_INIT_CAPACITY;
    db->progress = calloc(db->progress_capacity, sizeof(reading_progress_t));
    
    db->stat_capacity = WC_INIT_CAPACITY;
    db->stats = calloc(db->stat_capacity, sizeof(daily_stat_t));
    
    db->dirty = 0;
    db->db_path[0] = '\0';
    db->mastery_due_dirty = 1;
    
    if (!db->items || !db->sources || !db->chapters || 
        !db->users || !db->mastery || !db->progress || !db->stats) {
        wc_db_free(db);
        return NULL;
    }
    
    /* 创建空哈希表 */
    db->question_hash = str_hash_new(1024);
    db->id_hash = int_hash_new(1024);
    db->source_hash = int_hash_new(128);
    db->user_hash = str_hash_new(1024);
    db->user_id_hash = int_hash_new(1024);
    db->mastery_hash = pair_hash_new(1024);
    db->stat_hash = pair_hash_new(1024);
    
    /* 分配到期复习排序数组 */
    db->mastery_due_sorted = malloc(db->mastery_capacity * sizeof(uint32_t));
    
    return db;
}

void wc_db_free(wordcard_db_t *db) {
    if (!db) return;
    
    str_hash_free((str_hash_t*)db->question_hash);
    int_hash_free((int_hash_t*)db->id_hash);
    int_hash_free((int_hash_t*)db->source_hash);
    str_hash_free((str_hash_t*)db->user_hash);
    int_hash_free((int_hash_t*)db->user_id_hash);
    pair_hash_free((pair_hash_t*)db->mastery_hash);
    pair_hash_free((pair_hash_t*)db->stat_hash);
    
    free(db->mastery_due_sorted);
    
    free(db->items);
    free(db->sources);
    free(db->chapters);
    free(db->users);
    free(db->mastery);
    free(db->progress);
    free(db->stats);
    free(db);
}

/* ========================================================================
 * 磁盘加载与保存（结构体直写磁盘）
 * ======================================================================== */

wordcard_db_t* wc_load_db(const char *path) {
    FILE *fp = fopen(path, "rb");
    if (!fp) return NULL;
    
    wc_file_header_t header;
    if (fread(&header, sizeof(header), 1, fp) != 1) {
        fclose(fp);
        return NULL;
    }
    
    /* 验证魔数和版本 */
    if (memcmp(header.magic, WC_MAGIC, 4) != 0 || header.version != WC_VERSION) {
        fclose(fp);
        return NULL;
    }
    
    wordcard_db_t *db = wc_db_init();
    if (!db) { fclose(fp); return NULL; }
    
    strncpy(db->db_path, path, sizeof(db->db_path)-1);
    db->db_path[sizeof(db->db_path)-1] = '\0';
    
    int ok = 1;
    
    /* 加载学习项表 */
    if (ok && header.item_count > 0) {
        db->item_count = header.item_count;
        while (db->item_capacity < db->item_count) {
            db->item_capacity *= WC_GROWTH_FACTOR;
        }
        db->items = realloc(db->items, db->item_capacity * sizeof(item_entry_t));
        if (!db->items || fread(db->items, sizeof(item_entry_t), db->item_count, fp) != db->item_count) {
            ok = 0;
        }
    }
    
    /* 加载载体表 */
    if (ok && header.source_count > 0) {
        db->source_count = header.source_count;
        while (db->source_capacity < db->source_count) {
            db->source_capacity *= WC_GROWTH_FACTOR;
        }
        db->sources = realloc(db->sources, db->source_capacity * sizeof(content_source_t));
        if (!db->sources || fread(db->sources, sizeof(content_source_t), db->source_count, fp) != db->source_count) {
            ok = 0;
        }
    }
    
    /* 加载章节表 */
    if (ok && header.chapter_count > 0) {
        db->chapter_count = header.chapter_count;
        while (db->chapter_capacity < db->chapter_count) {
            db->chapter_capacity *= WC_GROWTH_FACTOR;
        }
        db->chapters = realloc(db->chapters, db->chapter_capacity * sizeof(chapter_t));
        if (!db->chapters || fread(db->chapters, sizeof(chapter_t), db->chapter_count, fp) != db->chapter_count) {
            ok = 0;
        }
    }
    
    /* 加载用户表 */
    if (ok && header.user_count > 0) {
        db->user_count = header.user_count;
        while (db->user_capacity < db->user_count) {
            db->user_capacity *= WC_GROWTH_FACTOR;
        }
        db->users = realloc(db->users, db->user_capacity * sizeof(user_t));
        if (!db->users || fread(db->users, sizeof(user_t), db->user_count, fp) != db->user_count) {
            ok = 0;
        }
    }
    
    /* 加载掌握度表 */
    if (ok && header.mastery_count > 0) {
        db->mastery_count = header.mastery_count;
        while (db->mastery_capacity < db->mastery_count) {
            db->mastery_capacity *= WC_GROWTH_FACTOR;
        }
        db->mastery = realloc(db->mastery, db->mastery_capacity * sizeof(user_item_mastery_t));
        if (!db->mastery || fread(db->mastery, sizeof(user_item_mastery_t), db->mastery_count, fp) != db->mastery_count) {
            ok = 0;
        }
    }
    
    /* 加载阅读进度 */
    if (ok && header.progress_count > 0) {
        db->progress_count = header.progress_count;
        while (db->progress_capacity < db->progress_count) {
            db->progress_capacity *= WC_GROWTH_FACTOR;
        }
        db->progress = realloc(db->progress, db->progress_capacity * sizeof(reading_progress_t));
        if (!db->progress || fread(db->progress, sizeof(reading_progress_t), db->progress_count, fp) != db->progress_count) {
            ok = 0;
        }
    }
    
    /* 加载每日统计 */
    if (ok && header.stat_count > 0) {
        db->stat_count = header.stat_count;
        while (db->stat_capacity < db->stat_count) {
            db->stat_capacity *= WC_GROWTH_FACTOR;
        }
        db->stats = realloc(db->stats, db->stat_capacity * sizeof(daily_stat_t));
        if (!db->stats || fread(db->stats, sizeof(daily_stat_t), db->stat_count, fp) != db->stat_count) {
            ok = 0;
        }
    }
    
    fclose(fp);
    
    if (!ok) {
        wc_db_free(db);
        return NULL;
    }
    
    /* 重建哈希索引 */
    rebuild_indexes(db);
    
    db->dirty = 0;
    return db;
}

int wc_save_db(wordcard_db_t *db, const char *path) {
    if (!db) return WC_ERR_INVALID;
    
    const char *target = path ? path : db->db_path;
    if (!target || !target[0]) return WC_ERR_INVALID;
    
    char tmp_path[512];
    snprintf(tmp_path, sizeof(tmp_path), "%s.tmp", target);
    
    FILE *fp = fopen(tmp_path, "wb");
    if (!fp) return WC_ERR_FILE;
    
    /* 写入文件头 */
    wc_file_header_t header;
    memset(&header, 0, sizeof(header));
    memcpy(header.magic, WC_MAGIC, 4);
    header.version = WC_VERSION;
    header.item_count = (uint32_t)db->item_count;
    header.source_count = (uint32_t)db->source_count;
    header.chapter_count = (uint32_t)db->chapter_count;
    header.user_count = (uint32_t)db->user_count;
    header.mastery_count = (uint32_t)db->mastery_count;
    header.progress_count = (uint32_t)db->progress_count;
    header.stat_count = (uint32_t)db->stat_count;
    
    if (fwrite(&header, sizeof(header), 1, fp) != 1) {
        fclose(fp); remove(tmp_path); return WC_ERR_FILE;
    }
    
    /* 按顺序写入各数组 */
    if (db->item_count > 0) {
        if (fwrite(db->items, sizeof(item_entry_t), db->item_count, fp) != db->item_count)
            goto fail;
    }
    if (db->source_count > 0) {
        if (fwrite(db->sources, sizeof(content_source_t), db->source_count, fp) != db->source_count)
            goto fail;
    }
    if (db->chapter_count > 0) {
        if (fwrite(db->chapters, sizeof(chapter_t), db->chapter_count, fp) != db->chapter_count)
            goto fail;
    }
    if (db->user_count > 0) {
        if (fwrite(db->users, sizeof(user_t), db->user_count, fp) != db->user_count)
            goto fail;
    }
    if (db->mastery_count > 0) {
        if (fwrite(db->mastery, sizeof(user_item_mastery_t), db->mastery_count, fp) != db->mastery_count)
            goto fail;
    }
    if (db->progress_count > 0) {
        if (fwrite(db->progress, sizeof(reading_progress_t), db->progress_count, fp) != db->progress_count)
            goto fail;
    }
    if (db->stat_count > 0) {
        if (fwrite(db->stats, sizeof(daily_stat_t), db->stat_count, fp) != db->stat_count)
            goto fail;
    }
    
    if (fflush(fp) != 0 || fclose(fp) != 0) {
        remove(tmp_path); return WC_ERR_FILE;
    }
    
    /* 原子替换 */
    if (rename(tmp_path, target) != 0) {
        remove(tmp_path); return WC_ERR_FILE;
    }
    
    db->dirty = 0;
    return WC_OK;
    
fail:
    fclose(fp);
    remove(tmp_path);
    return WC_ERR_FILE;
}

void wc_mark_dirty(wordcard_db_t *db) {
    if (db) db->dirty = 1;
}

/* ========================================================================
 * 学习项操作
 * ======================================================================== */

uint32_t wc_add_item(wordcard_db_t *db, const item_entry_t *entry) {
    if (!db || !entry) return 0;
    
    LOCK();
    
    /* 检查是否已存在 */
    int idx;
    if (str_hash_get((str_hash_t*)db->question_hash, entry->question, &idx)) {
        UNLOCK();
        return 0; /* 已存在 */
    }
    
    /* 扩容 */
    void *new_arr = ensure_array(db->items, db->item_count, &db->item_capacity, 
                                  sizeof(item_entry_t));
    if (!new_arr) { UNLOCK(); return 0; }
    db->items = new_arr;
    
    /* 分配新ID */
    uint32_t new_id = (db->item_count > 0) ? db->items[db->item_count - 1].id + 1 : 1;
    
    /* 复制数据 */
    item_entry_t *v = &db->items[db->item_count];
    memcpy(v, entry, sizeof(item_entry_t));
    v->id = new_id;
    db->item_count++;
    
    /* 更新索引 */
    str_hash_set((str_hash_t*)db->question_hash, v->question, (int)(db->item_count - 1));
    int_hash_set((int_hash_t*)db->id_hash, v->id, (int)(db->item_count - 1));
    
    wc_mark_dirty(db);
    UNLOCK();
    return new_id;
}

item_entry_t* wc_find_item_by_question(wordcard_db_t *db, const char *question) {
    if (!db || !question) return NULL;
    LOCK();
    int idx;
    if (str_hash_get((str_hash_t*)db->question_hash, question, &idx)) {
        UNLOCK();
        return &db->items[idx];
    }
    UNLOCK();
    return NULL;
}

item_entry_t* wc_find_item_by_id(wordcard_db_t *db, uint32_t item_id) {
    if (!db) return NULL;
    LOCK();
    int idx;
    if (int_hash_get((int_hash_t*)db->id_hash, item_id, &idx)) {
        UNLOCK();
        return &db->items[idx];
    }
    UNLOCK();
    return NULL;
}

/* ========================================================================
 * 载体/内容源操作
 * ======================================================================== */

uint32_t wc_add_source(wordcard_db_t *db, const content_source_t *source) {
    if (!db || !source) return 0;
    
    LOCK();
    
    /* 检查名称是否已存在 */
    for (size_t i = 0; i < db->source_count; i++) {
        if (strcmp(db->sources[i].name, source->name) == 0) {
            UNLOCK();
            return 0;
        }
    }
    
    void *new_arr = ensure_array(db->sources, db->source_count, &db->source_capacity, 
                                  sizeof(content_source_t));
    if (!new_arr) { UNLOCK(); return 0; }
    db->sources = new_arr;
    
    uint32_t new_id = (db->source_count > 0) ? db->sources[db->source_count - 1].id + 1 : 1;
    
    content_source_t *s = &db->sources[db->source_count];
    memcpy(s, source, sizeof(content_source_t));
    s->id = new_id;
    db->source_count++;
    
    int_hash_set((int_hash_t*)db->source_hash, s->id, (int)(db->source_count - 1));
    
    wc_mark_dirty(db);
    UNLOCK();
    return new_id;
}

content_source_t* wc_find_source_by_id(wordcard_db_t *db, uint32_t source_id) {
    if (!db) return NULL;
    LOCK();
    int idx;
    if (int_hash_get((int_hash_t*)db->source_hash, source_id, &idx)) {
        UNLOCK();
        return &db->sources[idx];
    }
    UNLOCK();
    return NULL;
}

content_source_t* wc_find_source_by_name(wordcard_db_t *db, const char *name) {
    if (!db || !name) return NULL;
    /* 线性查找（source 数量通常很少） */
    LOCK();
    for (size_t i = 0; i < db->source_count; i++) {
        if (strcmp(db->sources[i].name, name) == 0) {
            UNLOCK();
            return &db->sources[i];
        }
    }
    UNLOCK();
    return NULL;
}

/* ========================================================================
 * 用户操作
 * ======================================================================== */

uint32_t wc_create_user(wordcard_db_t *db, const char *dingtalk_uid, const char *name) {
    if (!db || !dingtalk_uid) return 0;
    
    LOCK();
    
    /* 检查是否已存在 */
    int idx;
    if (str_hash_get((str_hash_t*)db->user_hash, dingtalk_uid, &idx)) {
        UNLOCK();
        return 0;
    }
    
    void *new_arr = ensure_array(db->users, db->user_count, &db->user_capacity, sizeof(user_t));
    if (!new_arr) { UNLOCK(); return 0; }
    db->users = new_arr;
    
    uint32_t new_id = (db->user_count > 0) ? db->users[db->user_count - 1].id + 1 : 1;
    
    user_t *u = &db->users[db->user_count];
    memset(u, 0, sizeof(user_t));
    u->id = new_id;
    strncpy(u->dingtalk_uid, dingtalk_uid, sizeof(u->dingtalk_uid) - 1);
    if (name) strncpy(u->name, name, sizeof(u->name) - 1);
    u->daily_new_limit = WC_DAILY_NEW_LIMIT;
    u->daily_review_limit = WC_DAILY_REVIEW_LIMIT;
    u->created_at = wc_now();
    u->last_active = u->created_at;
    
    db->user_count++;
    str_hash_set((str_hash_t*)db->user_hash, u->dingtalk_uid, (int)(db->user_count - 1));
    int_hash_set((int_hash_t*)db->user_id_hash, u->id, (int)(db->user_count - 1));
    
    wc_mark_dirty(db);
    UNLOCK();
    return new_id;
}

user_t* wc_find_user(wordcard_db_t *db, const char *dingtalk_uid) {
    if (!db || !dingtalk_uid) return NULL;
    LOCK();
    int idx;
    if (str_hash_get((str_hash_t*)db->user_hash, dingtalk_uid, &idx)) {
        UNLOCK();
        return &db->users[idx];
    }
    UNLOCK();
    return NULL;
}

user_t* wc_find_user_by_id(wordcard_db_t *db, uint32_t user_id) {
    if (!db) return NULL;
    LOCK();
    int idx;
    if (int_hash_get((int_hash_t*)db->user_id_hash, user_id, &idx)) {
        UNLOCK();
        return &db->users[idx];
    }
    UNLOCK();
    return NULL;
}

/* ========================================================================
 * 掌握度操作
 * ======================================================================== */

user_item_mastery_t* wc_get_or_create_mastery(wordcard_db_t *db, 
                                               uint32_t user_id, 
                                               uint32_t item_id) {
    if (!db) return NULL;
    
    LOCK();
    
    int idx;
    if (pair_hash_get((pair_hash_t*)db->mastery_hash, user_id, item_id, &idx)) {
        UNLOCK();
        return &db->mastery[idx];
    }
    
    /* 创建新记录 */
    size_t old_cap = db->mastery_capacity;
    void *new_arr = ensure_array(db->mastery, db->mastery_count, 
                                  &db->mastery_capacity, sizeof(user_item_mastery_t));
    if (!new_arr) { UNLOCK(); return NULL; }
    db->mastery = new_arr;
    
    /* 同步扩容 due_sorted 数组 */
    if (db->mastery_capacity > old_cap && db->mastery_due_sorted) {
        uint32_t *new_due = realloc(db->mastery_due_sorted, db->mastery_capacity * sizeof(uint32_t));
        if (new_due) db->mastery_due_sorted = new_due;
    }
    
    user_item_mastery_t *m = &db->mastery[db->mastery_count];
    memset(m, 0, sizeof(user_item_mastery_t));
    m->user_id = user_id;
    m->item_id = item_id;
    m->ease_factor = WC_DEFAULT_EF;
    m->first_seen = wc_now();
    
    pair_hash_set((pair_hash_t*)db->mastery_hash, user_id, item_id, (int)db->mastery_count);
    db->mastery_count++;
    db->mastery_due_dirty = 1; /* 新记录可能影响排序 */
    
    wc_mark_dirty(db);
    UNLOCK();
    return m;
}

user_item_mastery_t* wc_find_mastery(wordcard_db_t *db, 
                                      uint32_t user_id, 
                                      uint32_t item_id) {
    if (!db) return NULL;
    LOCK();
    int idx;
    if (pair_hash_get((pair_hash_t*)db->mastery_hash, user_id, item_id, &idx)) {
        UNLOCK();
        return &db->mastery[idx];
    }
    UNLOCK();
    return NULL;
}

/* ========================================================================
 * SM-2 算法
 * ======================================================================== */

void wc_sm2_update(user_item_mastery_t *mastery, uint8_t quality) {
    if (!mastery || quality > 5) return;
    
    mastery->total_reviews++;
    mastery->last_review = wc_now();
    
    if (quality >= 3) {
        /* 记住了 */
        mastery->correct_count++;
        mastery->streak_days++;
        mastery->forget_count = 0;
        
        if (mastery->sm2_status == SM2_NEW) {
            mastery->sm2_status = SM2_LEARNING;
        }
        if (mastery->repetitions == 0) {
            mastery->interval_days = 1;
        } else if (mastery->repetitions == 1) {
            mastery->interval_days = 6;
        } else {
            mastery->interval_days = (uint16_t)(mastery->interval_days * mastery->ease_factor);
        }
        mastery->repetitions++;
        
        if (mastery->interval_days > 3650) mastery->interval_days = 3650; /* 上限10年 */
        
    } else {
        /* 忘记了 */
        mastery->wrong_count++;
        mastery->streak_days = 0;
        mastery->forget_count++;
        mastery->last_wrong = wc_now();
        mastery->repetitions = 0;
        mastery->interval_days = 1;
    }
    
    /* 更新 ease factor */
    mastery->ease_factor += (0.1f - (5 - quality) * (0.08f + (5 - quality) * 0.02f));
    if (mastery->ease_factor < WC_MIN_EF) mastery->ease_factor = WC_MIN_EF;
    
    /* 计算下次复习时间 */
    mastery->next_review = mastery->last_review + mastery->interval_days * 86400;
    
    /* 如果连续多次记住且间隔较大，标记为已掌握 */
    if (mastery->repetitions >= 5 && mastery->interval_days >= 21) {
        mastery->sm2_status = SM2_MASTERED;
    }
}

/* ========================================================================
 * 多维度掌握度更新
 * ======================================================================== */

void wc_update_mastery_dimension(wordcard_db_t *db,
                                  user_item_mastery_t *mastery,
                                  char dimension,
                                  int correct,
                                  uint8_t score) {
    if (!mastery) return;
    
    int delta = correct ? 10 : -15;
    uint8_t *target = NULL;
    
    switch (dimension) {
        case 'r': target = &mastery->recognition; break;
        case 'c': target = &mastery->recall; break;
        case 's': target = &mastery->spelling; break;
        case 'l': target = &mastery->listening; break;
        case 'p': target = &mastery->pronunciation; break;
        case 'u': target = &mastery->usage; break;
        default: return;
    }
    
    if (dimension == 'p' && score > 0) {
        /* 发音评分直接使用 ASR 分数 */
        *target = score;
    } else {
        int new_val = (int)*target + delta;
        if (new_val < 0) new_val = 0;
        if (new_val > 100) new_val = 100;
        *target = (uint8_t)new_val;
    }
    
    wc_recalc_overall(mastery);
    if (db) wc_mark_dirty(db);
}

void wc_recalc_overall(user_item_mastery_t *mastery) {
    if (!mastery) return;
    float overall = mastery->recognition * 0.25f +
                    mastery->recall * 0.20f +
                    mastery->spelling * 0.20f +
                    mastery->listening * 0.15f +
                    mastery->pronunciation * 0.10f +
                    mastery->usage * 0.10f;
    mastery->overall = (uint8_t)overall;
}

/* ========================================================================
 * 查询接口
 * ======================================================================== */

size_t wc_get_due_items(wordcard_db_t *db, uint32_t user_id, uint32_t now,
                         uint32_t *out_ids, size_t max_count) {
    if (!db || !out_ids || max_count == 0) return 0;
    
    LOCK();
    rebuild_due_index(db);
    
    size_t count = 0;
    for (size_t i = 0; i < db->mastery_due_sorted_count && count < max_count; i++) {
        uint32_t m_idx = db->mastery_due_sorted[i];
        user_item_mastery_t *m = &db->mastery[m_idx];
        
        /* 按 next_review 排序，遇到未来时间直接退出 */
        if (m->next_review > now) break;
        
        if (m->user_id == user_id && m->sm2_status != SM2_NEW) {
            out_ids[count++] = m->item_id;
        }
    }
    UNLOCK();
    return count;
}

size_t wc_get_new_items(wordcard_db_t *db, uint32_t user_id, uint32_t source_id,
                         uint32_t *out_ids, size_t max_count) {
    if (!db || !out_ids || max_count == 0) return 0;
    
    LOCK();
    size_t count = 0;
    
    /* 遍历学习项库，找到用户未学过的项 */
    for (size_t i = 0; i < db->item_count && count < max_count; i++) {
        uint32_t vid = db->items[i].id;
        
        /* 如果指定了载体，过滤 */
        if (source_id != 0 && db->items[i].source_id != source_id) continue;
        
        /* 检查用户是否已有掌握度记录 */
        int idx;
        if (!pair_hash_get((pair_hash_t*)db->mastery_hash, user_id, vid, &idx)) {
            out_ids[count++] = vid;
        }
    }
    UNLOCK();
    return count;
}

/* ========================================================================
 * 每日统计
 * ======================================================================== */

daily_stat_t* wc_get_or_create_daily_stat(wordcard_db_t *db, 
                                            uint32_t user_id, 
                                            uint32_t date) {
    if (!db) return NULL;
    
    LOCK();
    /* O(1) 哈希查找 */
    int idx;
    if (pair_hash_get((pair_hash_t*)db->stat_hash, user_id, date, &idx)) {
        UNLOCK();
        return &db->stats[idx];
    }
    
    void *new_arr = ensure_array(db->stats, db->stat_count, 
                                  &db->stat_capacity, sizeof(daily_stat_t));
    if (!new_arr) { UNLOCK(); return NULL; }
    db->stats = new_arr;
    
    daily_stat_t *s = &db->stats[db->stat_count];
    memset(s, 0, sizeof(daily_stat_t));
    s->user_id = user_id;
    s->date = date;
    
    pair_hash_set((pair_hash_t*)db->stat_hash, user_id, date, (int)db->stat_count);
    db->stat_count++;
    
    wc_mark_dirty(db);
    UNLOCK();
    return s;
}

void wc_record_activity(wordcard_db_t *db, uint32_t user_id, 
                         int is_new, int is_correct, uint32_t time_spent) {
    if (!db) return;
    
    daily_stat_t *s = wc_get_or_create_daily_stat(db, user_id, wc_today());
    if (!s) return;
    
    if (is_new) {
        s->new_items++;
    } else {
        s->reviewed_items++;
    }
    
    if (is_correct) {
        s->mastered_items++;
    } else {
        s->wrong_items++;
    }
    
    s->study_time_sec += time_spent;
    wc_mark_dirty(db);
}

/* ========================================================================
 * 通知与工具函数
 * ======================================================================== */

void wc_notify_mastery_changed(wordcard_db_t *db) {
    if (db) db->mastery_due_dirty = 1;
}

uint32_t wc_now(void) {
    return (uint32_t)time(NULL);
}

uint32_t wc_today(void) {
    time_t t = time(NULL);
    struct tm *tm_info = localtime(&t);
    return (uint32_t)((tm_info->tm_year + 1900) * 10000 + 
                      (tm_info->tm_mon + 1) * 100 + 
                      tm_info->tm_mday);
}

const char* wc_version_string(void) {
    return "WordCard DB v3.0.0 (Universal)";
}
