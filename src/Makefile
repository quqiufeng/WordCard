CC = gcc

# OpenMP 检测（用于 HNSW 并行索引构建）
OPENMP_FLAG := $(shell echo 'int main(){return 0;}' | $(CC) -fopenmp -x c - -o /dev/null 2>/dev/null && echo "-fopenmp" || echo "")

CFLAGS = -Wall -Wextra -O2 -fPIC -std=c11 -D_GNU_SOURCE -I. $(OPENMP_FLAG)
LDFLAGS = -shared -lpthread -lm

# ====== libwordcard.so —— SM-2 间隔重复学习引擎 ======
LEARN_SRCS = wordcard.c modes.c
LEARN_OBJS = $(LEARN_SRCS:.c=.o)
LEARN_TARGET = libwordcard.so

# ====== libcache.so —— KV Cache 知识缓存系统 ======
CACHE_SRCS = crc32.c metrics.c mmap.c $(wildcard cache/*.c)
CACHE_OBJS = $(CACHE_SRCS:.c=.o)
CACHE_TARGET = libcache.so

# ====== libwordcard_full.so —— 合并版（学习引擎 + KV Cache）======
COMBINED_TARGET = libwordcard_full.so

.PHONY: all clean test test_cache

all: $(LEARN_TARGET) $(CACHE_TARGET)

combined: $(COMBINED_TARGET)

# ---- 学习引擎 ----

$(LEARN_TARGET): $(LEARN_OBJS)
	$(CC) $(LDFLAGS) -o $@ $^

wordcard.o: wordcard.c wordcard.h
	$(CC) $(CFLAGS) -c $< -o $@

modes.o: modes.c wordcard.h
	$(CC) $(CFLAGS) -c $< -o $@

# ---- KV Cache ----

$(CACHE_TARGET): $(CACHE_OBJS)
	$(CC) $(LDFLAGS) -o $@ $^

crc32.o: crc32.c
	$(CC) $(CFLAGS) -c $< -o $@

metrics.o: metrics.c
	$(CC) $(CFLAGS) -c $< -o $@

mmap.o: mmap.c pool.h
	$(CC) $(CFLAGS) -c $< -o $@

cache/%.o: cache/%.c
	$(CC) $(CFLAGS) -c $< -o $@

# ---- 合并版 ----

$(COMBINED_TARGET): $(LEARN_OBJS) $(CACHE_OBJS)
	$(CC) $(LDFLAGS) -o $@ $^

# ---- 测试 ----

test: $(LEARN_TARGET) test_sm2.c
	$(CC) $(CFLAGS) test_sm2.c -L. -lwordcard -lm -o test_sm2
	LD_LIBRARY_PATH=. ./test_sm2

test_cache: $(CACHE_TARGET) test_cache_basic.c
	$(CC) $(CFLAGS) test_cache_basic.c -L. -lcache -lm -o test_cache_basic
	LD_LIBRARY_PATH=. ./test_cache_basic

# ---- 清理 ----

clean:
	rm -f $(LEARN_OBJS) $(CACHE_OBJS)
	rm -f $(LEARN_TARGET) $(CACHE_TARGET) $(COMBINED_TARGET)
	rm -f test_sm2 test_cache_basic
	rm -rf /tmp/test_cache_basic
