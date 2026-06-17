#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>
#include "cache.h"

static int passed = 0, failed = 0;

#define TEST(name) void test_##name()
#define RUN(name) do { \
    printf("  [cache] " #name " ... "); \
    test_##name(); \
    printf("OK\n"); \
    passed++; \
} while(0)

#define ASSERT(cond) do { \
    if (!(cond)) { \
        printf("FAILED: %s\n", #cond); \
        failed++; \
        return; \
    } \
} while(0)

static const char *TEST_DIR = "/tmp/test_cache_basic";

static cache_t* open_cache(void) {
    if (system("rm -rf /tmp/test_cache_basic") < 0) {}
    return cache_open(TEST_DIR, CACHE_MAX_MEMORY_DEFAULT);
}

static void close_cache(cache_t *c) {
    if (c) cache_close(c);
    if (system("rm -rf /tmp/test_cache_basic") < 0) {}
}

/* 测试 1: 打开/关闭 */
TEST(open_close) {
    cache_t *c = open_cache();
    ASSERT(c != NULL);
    ASSERT(cache_count(c) == 0);
    close_cache(c);
}

/* 测试 2: set / get */
TEST(set_get) {
    cache_t *c = open_cache();
    ASSERT(cache_set(c, "/test/key1", "value1", 0) == CACHE_OK);
    const char *v = cache_get(c, "/test/key1");
    ASSERT(v != NULL && strcmp(v, "value1") == 0);

    /* 更新 */
    ASSERT(cache_set(c, "/test/key1", "value2", 0) == CACHE_OK);
    v = cache_get(c, "/test/key1");
    ASSERT(v != NULL && strcmp(v, "value2") == 0);

    /* 不存在的 key */
    ASSERT(cache_get(c, "/test/nonexist") == NULL);

    close_cache(c);
}

/* 测试 3: exists / del */
TEST(exists_del) {
    cache_t *c = open_cache();
    ASSERT(cache_set(c, "/test/k", "v", 0) == CACHE_OK);
    ASSERT(cache_exists(c, "/test/k"));
    ASSERT(cache_del(c, "/test/k") == CACHE_OK);
    ASSERT(!cache_exists(c, "/test/k"));

    /* 删除不存在的 key */
    ASSERT(cache_del(c, "/test/nonexist") == CACHE_ERR_NOENT);

    close_cache(c);
}

/* 测试 4: 命名空间 */
TEST(namespace) {
    cache_t *c = open_cache();
    ASSERT(cache_set_ns(c, "/ns/a", "x", "X", 0) == CACHE_OK);
    const char *v = cache_get_ns(c, "/ns/a", "x");
    ASSERT(v != NULL && strcmp(v, "X") == 0);

    /* 删除 namespace */
    ASSERT(cache_del_ns(c, "/ns/a", "x") == CACHE_OK);
    ASSERT(cache_get_ns(c, "/ns/a", "x") == NULL);

    close_cache(c);
}

/* 测试 5: 前缀搜索 */
TEST(search_prefix) {
    cache_t *c = open_cache();
    cache_set(c, "/a/one", "1", 0);
    cache_set(c, "/a/two", "2", 0);
    cache_set(c, "/b/one", "3", 0);

    cache_search_options_t opts = cache_search_options_default();
    cache_result_t *results = NULL;
    size_t count = 0;

    ASSERT(cache_search_prefix(c, "/a/", &opts, &results, &count) == CACHE_OK);
    ASSERT(count == 2);
    cache_results_free(results);

    ASSERT(cache_search_prefix(c, "/", &opts, &results, &count) == CACHE_OK);
    ASSERT(count == 3);
    cache_results_free(results);

    close_cache(c);
}

/* 测试 6: 范围搜索 */
TEST(search_range) {
    cache_t *c = open_cache();
    cache_set(c, "/a/apple", "", 0);
    cache_set(c, "/a/banana", "", 0);
    cache_set(c, "/a/cherry", "", 0);

    cache_search_options_t opts = cache_search_options_default();
    cache_result_t *results = NULL;
    size_t count = 0;

    ASSERT(cache_search_range(c, "/a/banana", "/a/cherry\x00", &opts, &results, &count) == CACHE_OK);
    ASSERT(count >= 1); /* 至少 banana */
    cache_results_free(results);

    close_cache(c);
}

/* 测试 7: 持久化 */
TEST(persistence) {
    cache_t *c = open_cache();
    cache_set(c, "/persist/key", "survived", 0);
    cache_set_ns(c, "/persist", "ns", "ns_data", 0);
    cache_sync(c);
    cache_close(c);

    /* 重新打开 */
    c = cache_open(TEST_DIR, CACHE_MAX_MEMORY_DEFAULT);
    ASSERT(c != NULL);

    const char *v = cache_get(c, "/persist/key");
    ASSERT(v != NULL && strcmp(v, "survived") == 0);

    v = cache_get_ns(c, "/persist", "ns");
    ASSERT(v != NULL && strcmp(v, "ns_data") == 0);

    ASSERT(cache_count(c) == 2);
    close_cache(c);
}

/* 测试 8: TTL 过期 */
TEST(ttl_expire) {
    cache_t *c = open_cache();
    /* 1ms TTL */
    ASSERT(cache_set(c, "/ttl/key", "gone", 1) == CACHE_OK);
    ASSERT(cache_exists(c, "/ttl/key")); /* 立即存在 */

    /* 等待过期 */
    struct timespec ts = {0, 2000000}; /* 2ms */
    nanosleep(&ts, NULL);

    /* 应被惰性删除 */
    ASSERT(cache_get(c, "/ttl/key") == NULL);

    close_cache(c);
}

/* 测试 9: batch set */
TEST(batch_set) {
    cache_t *c = open_cache();
    cache_batch_item_t items[3] = {
        {"/batch/a", "A", 0},
        {"/batch/b", "B", 0},
        {"/batch/c", "C", 0},
    };
    ASSERT(cache_batch_set(c, items, 3) == CACHE_OK);
    ASSERT(cache_count(c) == 3);

    ASSERT(strcmp(cache_get(c, "/batch/b"), "B") == 0);
    close_cache(c);
}

/* 测试 10: 热点缓存 */
TEST(hot_cache) {
    cache_t *c = open_cache();
    cache_set(c, "/hot/k", "hot_value", 0);

    /* 重复读取应命中热点 */
    for (int i = 0; i < 10; i++) {
        const char *v = cache_get(c, "/hot/k");
        ASSERT(v != NULL && strcmp(v, "hot_value") == 0);
    }
    close_cache(c);
}

int main(void) {
    printf("=== KV Cache Unit Tests ===\n\n");

    RUN(open_close);
    RUN(set_get);
    RUN(exists_del);
    RUN(namespace);
    RUN(search_prefix);
    RUN(search_range);
    RUN(persistence);
    RUN(ttl_expire);
    RUN(batch_set);
    RUN(hot_cache);

    printf("\n===========================\n");
    printf("Passed: %d\n", passed);
    printf("Failed: %d\n", failed);
    printf("===========================\n");

    if (system("rm -rf /tmp/test_cache_basic") < 0) {}
    return failed > 0 ? 1 : 0;
}
