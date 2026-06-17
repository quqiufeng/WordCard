#ifndef POOL_H
#define POOL_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ========================================================================
 * 内存池（mmap 零拷贝）
 * 用法：pool_init → pool_alloc → pool_close
 * ======================================================================== */

#define POOL_ALIGN          8
#define POOL_DEFAULT_SIZE   (1024 * 1024 * 100)  /* 100MB */

typedef struct {
    int     fd;
    void*   base;
    size_t  size;
    size_t  used;
    size_t  capacity;
} pool_t;

/* 初始化内存池（文件不存在则创建）*/
int pool_init(pool_t *pool, const char *path, size_t initial_size);

/* 初始化内存池（带自定义魔数和版本，用于复用已有 mmap 文件）*/
int pool_init_with_header(pool_t *pool, const char *path, size_t initial_size,
                          const char *magic, uint32_t version, size_t *out_used);

/* 关闭并同步内存池 */
void pool_close(pool_t *pool);

/* 强制刷盘（msync MS_SYNC）*/
int pool_sync(pool_t *pool);

/* 分配内存（返回 pool->base 中的指针）*/
void* pool_alloc(pool_t *pool, size_t size);

/* 扩展内存池 */
int pool_resize(pool_t *pool, size_t new_size);

/* 偏移量转指针 */
#define POOL_PTR(pool, offset) ((void*)((char*)(pool)->base + (offset)))

/* 分配内存并返回偏移量 */
static inline size_t pool_alloc_offset(pool_t *pool, size_t size) {
    void *ptr = pool_alloc(pool, size);
    if (!ptr) return 0;
    return (size_t)((char*)ptr - (char*)pool->base);
}

#ifdef __cplusplus
}
#endif

#endif /* POOL_H */
