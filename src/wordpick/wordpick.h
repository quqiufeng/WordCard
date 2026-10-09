#ifndef WORDPICK_H
#define WORDPICK_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// 候选词结果
typedef struct {
    char  word[48];       // 词（小写）
    char  context[256];   // 例句
    float score;          // 学习价值分
    float zipf;           // 通用词频 (0-8)
    int   count;          // 在本书中出现次数
} wp_word_t;

// 句柄：加载词频表
void* wp_create(const char* freq_path);

// 选择最值得学习的词
//   text        UTF-8 正文
//   max_words   最多返回词数
//   target_zipf 目标词频难度（默认 4.0，适中；越大越选常用词）
//   min_len     最小词长（默认 5）
//   out/out_cap 输出数组及容量
// 返回实际写入数量
int wp_select(void* handle, const char* text, int max_words,
              float target_zipf, int min_len,
              wp_word_t* out, int out_cap);

void wp_destroy(void* handle);

#ifdef __cplusplus
}
#endif

#endif
