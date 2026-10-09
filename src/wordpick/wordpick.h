#ifndef WORDPICK_H
#define WORDPICK_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// 候选词结果
typedef struct {
    char  word[48];       // lemma（小写）
    char  context[256];   // 例句
    float score;          // 学习价值分
    float zipf;           // 通用词频 (0-8)
    int   count;          // 书内出现次数
    int   level;          // CEFR 等级 (1=A1..6=C2, 0=未知)
} wp_word_t;

// 选择配置
typedef struct {
    int   max_words;      // 最多返回词数
    float target_zipf;    // 目标难度 zipf (0=默认 3.8)
    int   min_len;        // 最小词长 (0=默认 5)
    int   mode;           // 0=学习价值(默认), 1=覆盖率
    int   level;          // CEFR 预设 1..6 (覆盖 target_zipf)
    float known_zipf;     // 覆盖率模式：已知词阈值 (0=默认 5.0)
} wp_config_t;

void* wp_create(const char* freq_path);
void  wp_destroy(void* handle);

// 兼容旧接口
int wp_select(void* handle, const char* text, int max_words,
              float target_zipf, int min_len,
              wp_word_t* out, int out_cap);

// 扩展接口（推荐）
int wp_select_ex(void* handle, const char* text, const wp_config_t* cfg,
                 wp_word_t* out, int out_cap);

#ifdef __cplusplus
}
#endif

#endif
