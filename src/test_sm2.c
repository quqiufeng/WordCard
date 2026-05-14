#include <stdio.h>
#include <string.h>
#include <assert.h>
#include "wordcard.h"

/* ========================================================================
 * 单元测试
 * ======================================================================== */

static int tests_passed = 0;
static int tests_failed = 0;

#define TEST(name) void test_##name()
#define RUN(name) do { \
    printf("  [%s] " #name " ... ", __func__); \
    test_##name(); \
    printf("OK\n"); \
    tests_passed++; \
} while(0)

#define ASSERT(cond) do { \
    if (!(cond)) { \
        printf("FAILED: %s:%d: %s\n", __FILE__, __LINE__, #cond); \
        tests_failed++; \
        return; \
    } \
} while(0)

/* -------- 测试 1: 数据库初始化和内存管理 -------- */

TEST(db_init_free) {
    wordcard_db_t *db = wc_db_init();
    ASSERT(db != NULL);
    ASSERT(db->vocab_count == 0);
    ASSERT(db->user_count == 0);
    ASSERT(db->mastery_count == 0);
    wc_db_free(db);
}

/* -------- 测试 2: 词汇添加和查找 -------- */

TEST(vocab_add_find) {
    wordcard_db_t *db = wc_db_init();
    
    vocab_entry_t v = {0};
    strcpy(v.word, "hello");
    strcpy(v.meaning, "你好");
    v.difficulty = 1;
    
    uint32_t id = wc_add_vocab(db, &v);
    ASSERT(id > 0);
    ASSERT(db->vocab_count == 1);
    
    vocab_entry_t *found = wc_find_vocab_by_word(db, "hello");
    ASSERT(found != NULL);
    ASSERT(found->id == id);
    ASSERT(strcmp(found->word, "hello") == 0);
    
    vocab_entry_t *found2 = wc_find_vocab_by_id(db, id);
    ASSERT(found2 == found); /* 应该指向同一个内存 */
    
    wc_db_free(db);
}

/* -------- 测试 3: 用户创建和查找 -------- */

TEST(user_create_find) {
    wordcard_db_t *db = wc_db_init();
    
    uint32_t uid = wc_create_user(db, "ding123", "TestUser");
    ASSERT(uid > 0);
    ASSERT(db->user_count == 1);
    
    user_t *u = wc_find_user(db, "ding123");
    ASSERT(u != NULL);
    ASSERT(u->id == uid);
    ASSERT(strcmp(u->name, "TestUser") == 0);
    ASSERT(u->daily_new_limit == 10);
    
    user_t *u2 = wc_find_user_by_id(db, uid);
    ASSERT(u2 == u);
    
    wc_db_free(db);
}

/* -------- 测试 4: SM-2 算法 -------- */

TEST(sm2_algorithm) {
    user_vocab_mastery_t m = {0};
    m.ease_factor = 2.5f;
    
    /* 第一次学习，rating=4 (Good) */
    wc_sm2_update(&m, 4);
    ASSERT(m.sm2_status == SM2_LEARNING);
    ASSERT(m.interval_days == 1);
    ASSERT(m.repetitions == 1);
    ASSERT(m.forget_count == 0);
    
    /* 第二次，rating=4 */
    wc_sm2_update(&m, 4);
    ASSERT(m.interval_days == 6);
    ASSERT(m.repetitions == 2);
    
    /* 第三次，rating=5 (Easy) */
    wc_sm2_update(&m, 5);
    ASSERT(m.interval_days > 6); /* 应该增长 */
    ASSERT(m.repetitions == 3);
    
    /* 忘记，rating=1 (Again) */
    uint16_t old_interval = m.interval_days;
    wc_sm2_update(&m, 1);
    ASSERT(m.interval_days == 1); /* 重置 */
    ASSERT(m.repetitions == 0);   /* 重置 */
    ASSERT(m.forget_count == 1);
    
    wc_db_free(wc_db_init()); /* 只是为了没有未使用警告 */
}

/* -------- 测试 5: 掌握度更新 -------- */

TEST(mastery_dimensions) {
    user_vocab_mastery_t m = {0};
    
    wc_recalc_overall(&m);
    ASSERT(m.overall == 0);
    
    m.recognition = 80;
    m.recall = 60;
    m.spelling = 40;
    m.listening = 70;
    m.pronunciation = 50;
    m.usage = 30;
    
    wc_recalc_overall(&m);
    /* 加权: 80*0.25 + 60*0.20 + 40*0.20 + 70*0.15 + 50*0.10 + 30*0.10 = 58.5 */
    ASSERT(m.overall >= 58 && m.overall <= 59);
    
    /* 测试更新 */
    wordcard_db_t *db = wc_db_init();
    wc_update_mastery_dimension(db, &m, 's', 1, 0); /* 拼写正确 +10 */
    ASSERT(m.spelling == 50);
    
    wc_update_mastery_dimension(db, &m, 's', 0, 0); /* 拼写错误 -15 */
    ASSERT(m.spelling == 35);
    
    wc_db_free(db);
}

/* -------- 测试 6: 磁盘保存和加载 -------- */

TEST(db_save_load) {
    wordcard_db_t *db = wc_db_init();
    
    /* 添加数据 */
    vocab_entry_t v = {0};
    strcpy(v.word, "test");
    strcpy(v.meaning, "测试");
    wc_add_vocab(db, &v);
    wc_create_user(db, "user1", "User");
    
    /* 保存 */
    int ret = wc_save_db(db, "/tmp/test_wordcard.db");
    ASSERT(ret == WC_OK);
    wc_db_free(db);
    
    /* 加载 */
    wordcard_db_t *db2 = wc_load_db("/tmp/test_wordcard.db");
    ASSERT(db2 != NULL);
    ASSERT(db2->vocab_count == 1);
    ASSERT(db2->user_count == 1);
    
    vocab_entry_t *found = wc_find_vocab_by_word(db2, "test");
    ASSERT(found != NULL);
    ASSERT(strcmp(found->meaning, "测试") == 0);
    
    wc_db_free(db2);
}

/* -------- 测试 7: 推荐算法 -------- */

TEST(recommend_mode) {
    user_vocab_mastery_t m = {0};
    uint32_t now = wc_now();
    
    /* 新词 -> 闪卡 */
    study_mode_t mode = wc_recommend_mode(&m, now);
    ASSERT(mode == MODE_FLASHCARD);
    
    /* 连续忘记 -> 闪卡 */
    m.total_reviews = 5;
    m.forget_count = 3;
    mode = wc_recommend_mode(&m, now);
    ASSERT(mode == MODE_FLASHCARD);
    
    /* 识别高，拼写低 -> 拼写 */
    m.forget_count = 0;
    m.recognition = 85;
    m.spelling = 40;
    mode = wc_recommend_mode(&m, now);
    ASSERT(mode == MODE_SPELLING);
    
    /* 全面掌握 -> 速闪 */
    m.recognition = 90; m.recall = 90; m.spelling = 90;
    m.listening = 90; m.pronunciation = 90; m.usage = 90;
    m.overall = 90;
    m.streak_days = 5;
    mode = wc_recommend_mode(&m, now);
    ASSERT(mode == MODE_SPEED_REVIEW);
    
    wc_db_free(wc_db_init());
}

/* -------- 测试 8: 载体操作 -------- */

TEST(source_api) {
    wordcard_db_t *db = wc_db_init();
    
    content_source_t s = {0};
    strcpy(s.name, "CET-4");
    s.type = SOURCE_WORDLIST;
    
    uint32_t sid = wc_add_source(db, &s);
    ASSERT(sid > 0);
    ASSERT(db->source_count == 1);
    
    content_source_t *found = wc_find_source_by_id(db, sid);
    ASSERT(found != NULL);
    ASSERT(strcmp(found->name, "CET-4") == 0);
    
    content_source_t *found2 = wc_find_source_by_name(db, "CET-4");
    ASSERT(found2 == found);
    
    /* 重复添加应返回 0 */
    uint32_t sid2 = wc_add_source(db, &s);
    ASSERT(sid2 == 0);
    
    wc_db_free(db);
}

/* -------- 测试 9: O(1) 用户ID查找 -------- */

TEST(user_id_hash) {
    wordcard_db_t *db = wc_db_init();
    
    uint32_t uid = wc_create_user(db, "ding456", "HashTest");
    ASSERT(uid > 0);
    
    /* wc_find_user_by_id 应使用哈希，O(1) */
    user_t *u = wc_find_user_by_id(db, uid);
    ASSERT(u != NULL);
    ASSERT(strcmp(u->name, "HashTest") == 0);
    
    /* 不存在的用户 */
    user_t *u2 = wc_find_user_by_id(db, 99999);
    ASSERT(u2 == NULL);
    
    wc_db_free(db);
}

/* -------- 测试 10: 到期复习索引 -------- */

TEST(due_words_index) {
    wordcard_db_t *db = wc_db_init();
    
    /* 创建用户 */
    uint32_t uid = wc_create_user(db, "due_test", "DueTest");
    ASSERT(uid > 0);
    
    /* 添加单词 */
    vocab_entry_t v = {0};
    strcpy(v.word, "apple");
    strcpy(v.meaning, "苹果");
    uint32_t vid = wc_add_vocab(db, &v);
    ASSERT(vid > 0);
    
    /* 创建掌握度记录并模拟学习 */
    user_vocab_mastery_t *m = wc_get_or_create_mastery(db, uid, vid);
    ASSERT(m != NULL);
    
    /* 第一次学习，rating=4 -> next_review 设为 1 天后 */
    wc_sm2_update(m, 4);
    wc_notify_mastery_changed(db);
    
    uint32_t now = wc_now();
    uint32_t ids[10];
    
    /* 现在不应该到期 */
    size_t count = wc_get_due_words(db, uid, now, ids, 10);
    ASSERT(count == 0);
    
    /* 模拟 2 天后，应该到期 */
    uint32_t future = now + 2 * 86400;
    count = wc_get_due_words(db, uid, future, ids, 10);
    ASSERT(count == 1);
    ASSERT(ids[0] == vid);
    
    /* 复习后，再次不应到期 */
    wc_sm2_update(m, 5);
    wc_notify_mastery_changed(db);
    count = wc_get_due_words(db, uid, future, ids, 10);
    ASSERT(count == 0);
    
    wc_db_free(db);
}

/* ========================================================================
 * 主函数
 * ======================================================================== */

int main(void) {
    printf("=== WordCard Unit Tests ===\n\n");
    
    RUN(db_init_free);
    RUN(vocab_add_find);
    RUN(user_create_find);
    RUN(sm2_algorithm);
    RUN(mastery_dimensions);
    RUN(db_save_load);
    RUN(recommend_mode);
    RUN(source_api);
    RUN(user_id_hash);
    RUN(due_words_index);
    
    printf("\n===========================\n");
    printf("Passed: %d\n", tests_passed);
    printf("Failed: %d\n", tests_failed);
    printf("===========================\n");
    
    return tests_failed > 0 ? 1 : 0;
}
