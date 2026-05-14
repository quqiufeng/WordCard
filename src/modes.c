#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include "wordcard.h"

/* ========================================================================
 * 智能推荐算法
 * 根据多维度掌握度推荐最合适的学习模式
 * ======================================================================== */

study_mode_t wc_recommend_mode(const user_vocab_mastery_t *mastery, uint32_t now) {
    if (!mastery) return MODE_FLASHCARD;
    
    /* 规则1: 新词 → 闪卡模式（建立初步认知） */
    if (mastery->total_reviews == 0) {
        return MODE_FLASHCARD;
    }
    
    /* 规则5: 连续忘记 3 次以上 → 降级为闪卡 + 高频复习 */
    if (mastery->forget_count >= 3) {
        return MODE_FLASHCARD;
    }
    
    /* 规则2: 识别度高但拼写差 → 拼写/听写模式 */
    if (mastery->recognition > 80 && mastery->spelling < 50) {
        return MODE_SPELLING;
    }
    
    /* 规则3: 能认不能读 → 朗读模式（ASR 评分） */
    if (mastery->recognition > 70 && mastery->pronunciation < 60) {
        return MODE_PRONUNCIATION;
    }
    
    /* 规则4: 能认不能听 → 听写模式 */
    if (mastery->recognition > 70 && mastery->listening < 50) {
        return MODE_DICTATION;
    }
    
    /* 规则6: 全面掌握 → 速闪维持 */
    if (mastery->overall > 85 && mastery->streak_days >= 5) {
        return MODE_SPEED_REVIEW;
    }
    
    /* 规则7: SM-2 到期复习 → 根据最弱维度选模式 */
    if (now >= mastery->next_review) {
        uint8_t weakest = mastery->recognition;
        study_mode_t mode = MODE_CHOICE;
        
        if (mastery->recall < weakest) { weakest = mastery->recall; mode = MODE_FILLBLANK; }
        if (mastery->spelling < weakest) { weakest = mastery->spelling; mode = MODE_SPELLING; }
        if (mastery->listening < weakest) { weakest = mastery->listening; mode = MODE_DICTATION; }
        if (mastery->pronunciation < weakest) { weakest = mastery->pronunciation; mode = MODE_PRONUNCIATION; }
        if (mastery->usage < weakest) { weakest = mastery->usage; mode = MODE_MATCHING; }
        
        return mode;
    }
    
    /* 默认: 综合测试（选择题） */
    return MODE_CHOICE;
}

/* ========================================================================
 * 今日学习队列生成
 * ======================================================================== */

size_t wc_generate_daily_queue(wordcard_db_t *db, uint32_t user_id, uint32_t now,
                                uint32_t *out_ids, uint8_t *out_modes, 
                                size_t max_count) {
    if (!db || !out_ids || !out_modes || max_count == 0) return 0;
    
    user_t *user = wc_find_user_by_id(db, user_id);
    if (!user) return 0;
    
    size_t count = 0;
    
    /* 第一步: 添加到期复习的单词 */
    uint32_t *due_buffer = malloc(sizeof(uint32_t) * max_count);
    if (!due_buffer) return 0;
    
    size_t due_count = wc_get_due_words(db, user_id, now, due_buffer, max_count);
    
    for (size_t i = 0; i < due_count && count < max_count; i++) {
        user_vocab_mastery_t *m = wc_find_mastery(db, user_id, due_buffer[i]);
        if (m) {
            out_ids[count] = due_buffer[i];
            out_modes[count] = (uint8_t)wc_recommend_mode(m, now);
            count++;
        }
    }
    
    free(due_buffer);
    
    /* 第二步: 添加新词（不超过每日限制） */
    size_t new_limit = user->daily_new_limit;
    if (count < max_count && new_limit > 0) {
        uint32_t *new_buffer = malloc(sizeof(uint32_t) * new_limit);
        if (new_buffer) {
            size_t new_count = wc_get_new_words(db, user_id, 0, new_buffer, new_limit);
            for (size_t i = 0; i < new_count && count < max_count; i++) {
                out_ids[count] = new_buffer[i];
                out_modes[count] = MODE_FLASHCARD; /* 新词一律闪卡 */
                count++;
            }
            free(new_buffer);
        }
    }
    
    return count;
}
