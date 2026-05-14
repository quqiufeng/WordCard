#ifndef WORDCARD_H
#define WORDCARD_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ========================================================================
 * 常量定义
 * ======================================================================== */

#define WC_MAGIC            "WCD\x03"        /* 文件魔数，版本3（通用学习项） */
#define WC_VERSION          3
#define WC_HEADER_SIZE      64               /* 文件头固定64字节 */

/* 数组初始容量和增长因子 */
#define WC_INIT_CAPACITY    1024
#define WC_GROWTH_FACTOR    2

/* 默认值 */
#define WC_DEFAULT_EF       2.5f             /* SM-2 默认 ease factor */
#define WC_MIN_EF           1.3f             /* SM-2 最低 ease factor */
#define WC_DAILY_NEW_LIMIT  10               /* 每日默认新词数 */
#define WC_DAILY_REVIEW_LIMIT 50             /* 每日默认复习数 */

/* ========================================================================
 * 枚举类型
 * ======================================================================== */

/* 内容类型：学习项的类别 */
typedef enum {
    CAT_ENGLISH_VOCAB = 1,      /* 英语词汇 */
    CAT_LEGAL_LAW = 2,          /* 法律法规 */
    CAT_IELTS_SPEAKING = 3,     /* 雅思口语 */
    CAT_IELTS_WRITING = 4,      /* 雅思写作 */
    CAT_GRE_VERBAL = 5,         /* GRE 语文 */
    CAT_GRE_QUANT = 6,          /* GRE 数学 */
    CAT_MEDICAL_TERM = 7,       /* 医学术语 */
    CAT_CPA = 8,                /* 注册会计师 */
    CAT_CUSTOM = 99,            /* 用户自定义 */
} item_category_t;

/* 载体类别：学习项的来源 */
typedef enum {
    SOURCE_PDF = 1,         /* PDF 精读 */
    SOURCE_WORDLIST = 2,    /* 词汇表/题库 */
    SOURCE_ARTICLE = 3,     /* 短文/案例 */
    SOURCE_MOVIE = 4,       /* 影视台词 */
    SOURCE_EXAM = 5,        /* 真题语境 */
    SOURCE_SCENE = 6,       /* 主题场景 */
} source_type_t;

/* 学习模式/练习模式 */
typedef enum {
    MODE_FLASHCARD = 1,     /* 闪卡模式（建立初步认知） */
    MODE_CHOICE = 2,        /* 选择题 */
    MODE_FILLBLANK = 3,     /* 填空题 */
    MODE_SPELLING = 4,      /* 拼写/默写 */
    MODE_DICTATION = 5,     /* 听写/听辨 */
    MODE_PRONUNCIATION = 6, /* 朗读/发音（ASR 评分） */
    MODE_MATCHING = 7,      /* 配对 */
    MODE_SPEED_REVIEW = 8,  /* 速闪 */
} study_mode_t;

/* SM-2 学习状态 */
typedef enum {
    SM2_NEW = 0,            /* 新项 */
    SM2_LEARNING = 1,       /* 学习中 */
    SM2_MASTERED = 2,       /* 已掌握 */
} sm2_status_t;

/* 阅读进度状态 */
typedef enum {
    CHAPTER_LOCKED = 0,     /* 锁定 */
    CHAPTER_UNLOCKED = 1,   /* 已解锁 */
    CHAPTER_COMPLETED = 2,  /* 已读懂 */
} chapter_status_t;

/* ========================================================================
 * 核心数据结构（全局共享，所有用户共用）
 * 所有结构体均为定长，无指针，可直接 fwrite/fread
 * ======================================================================== */

/* 载体/内容源 */
typedef struct {
    uint32_t id;                    /* 唯一ID */
    source_type_t type;             /* 载体类型 */
    char name[128];                 /* 名称 */
    char file_path[256];            /* 源文件路径 */
    uint32_t item_start;            /* 在全局学习项表中的起始索引 */
    uint32_t item_count;            /* 包含的学习项数量 */
    uint32_t created_at;            /* 创建时间戳 */
} content_source_t;

/* 通用学习项（知识卡片）
 * 适用于任何学习内容：单词、法条、数学题、口语话题等
 */
typedef struct {
    uint32_t id;                    /* 唯一ID */
    char question[512];             /* 问题/提示/题目/英文单词 */
    char answer[512];               /* 答案/释义/法条/解答 */
    char explanation[1024];         /* 详细解析/例句/案例/记忆技巧 */
    char hint[256];                 /* 提示/音标/关键词/公式 */
    uint8_t difficulty;             /* 难度等级 1-5 */
    uint32_t source_id;             /* 关联载体ID */
    uint32_t category;              /* 内容类型（item_category_t） */
    char tags[128];                 /* 标签，逗号分隔 */
    uint32_t frequency;             /* 出现频率统计 */
} item_entry_t;

/* 段落/章节（PDF精读模式用） */
typedef struct {
    uint32_t id;                    /* 唯一ID */
    uint32_t source_id;             /* 关联载体ID */
    char title[256];                /* 章节标题 */
    uint32_t page_start;            /* 起始页码 */
    uint32_t page_end;              /* 结束页码 */
    uint32_t item_start_idx;        /* 学习项起始索引 */
    uint32_t item_count;            /* 学习项数量 */
    char summary[1024];             /* 中文摘要 */
} chapter_t;

/* ========================================================================
 * 用户私有数据结构
 * ======================================================================== */

/* 用户表 */
typedef struct {
    uint32_t id;                    /* 内部用户ID */
    char dingtalk_uid[64];          /* 钉钉用户唯一标识 */
    char name[64];                  /* 昵称 */
    uint8_t role;                   /* 0=学生, 1=老师 */
    uint16_t daily_new_limit;       /* 每日新项上限 */
    uint16_t daily_review_limit;    /* 每日复习上限 */
    uint32_t created_at;            /* 注册时间 */
    uint32_t last_active;           /* 最后活跃时间 */
} user_t;

/* 用户学习项掌握度 —— 核心表，追踪学习全过程
 * 注意：字段名保留 "vocab" 历史名称以保持兼容性，但语义已泛化
 */
typedef struct {
    uint32_t user_id;               /* 所属用户 */
    uint32_t item_id;               /* 学习项ID（原 vocab_id） */
    
    /* ====== SM-2 核心参数 ====== */
    uint8_t sm2_status;             /* 0=新项, 1=学习中, 2=已掌握 */
    uint16_t interval_days;         /* 下次间隔天数 */
    uint16_t repetitions;           /* 成功重复次数 */
    float ease_factor;              /* 难度因子（默认2.5） */
    uint32_t next_review;           /* 下次复习时间戳 */
    uint32_t last_review;           /* 上次复习时间戳 */
    
    /* ====== 多维度掌握度（0-100）====== */
    uint8_t recognition;            /* 识别：看到问题→知答案 */
    uint8_t recall;                 /* 回忆：看到提示→想答案 */
    uint8_t spelling;               /* 默写/复现准确度 */
    uint8_t listening;              /* 听辨/理解 */
    uint8_t pronunciation;          /* 表达/发音评分 */
    uint8_t usage;                  /* 应用/实践 */
    uint8_t overall;                /* 综合掌握度（加权计算） */
    
    /* ====== 学习统计 ====== */
    uint16_t total_reviews;         /* 总复习次数 */
    uint16_t correct_count;         /* 正确次数 */
    uint16_t wrong_count;           /* 错误次数 */
    uint8_t streak_days;            /* 连续正确天数 */
    uint32_t first_seen;            /* 首次学习时间 */
    uint32_t last_wrong;            /* 上次错误时间 */
    uint8_t forget_count;           /* "忘记"次数（评级<3） */
    
    /* ====== 用户标记 ====== */
    uint8_t is_difficult;           /* 用户标记困难 */
    uint8_t is_favorite;            /* 用户收藏 */
    uint8_t is_banned;              /* 用户屏蔽（不再推送） */
} user_item_mastery_t;

/* 阅读进度（PDF精读模式专用） */
typedef struct {
    uint32_t user_id;               /* 所属用户 */
    uint32_t chapter_id;            /* 章节ID */
    uint8_t status;                 /* 0=锁定, 1=已解锁, 2=已读懂 */
    uint32_t unlocked_at;           /* 解锁时间 */
    uint32_t completed_at;          /* 完成时间 */
    uint8_t quiz_score;             /* 理解测试得分 */
} reading_progress_t;

/* 每日统计 */
typedef struct {
    uint32_t user_id;               /* 所属用户 */
    uint32_t date;                  /* YYYYMMDD */
    uint16_t new_items;             /* 今日新学 */
    uint16_t reviewed_items;        /* 今日复习 */
    uint16_t mastered_items;        /* 今日掌握 */
    uint16_t wrong_items;           /* 今日错误 */
    uint32_t study_time_sec;        /* 学习时长（秒） */
} daily_stat_t;

/* ========================================================================
 * 文件头结构（64字节，磁盘格式）
 * ======================================================================== */

typedef struct {
    char magic[4];                  /* "WCD\x03" */
    uint32_t version;               /* 版本号 = 3 */
    uint32_t item_count;            /* 学习项数量 */
    uint32_t source_count;          /* 载体数量 */
    uint32_t chapter_count;         /* 章节数量 */
    uint32_t user_count;            /* 用户数量 */
    uint32_t mastery_count;         /* 掌握度记录数 */
    uint32_t progress_count;        /* 阅读进度记录数 */
    uint32_t stat_count;            /* 统计记录数 */
    char reserved[28];              /* 预留 */
} wc_file_header_t;

/* ========================================================================
 * 内存数据库主结构
 * ======================================================================== */

typedef struct {
    /* ====== 全局共享数据（只读/少写）====== */
    item_entry_t *items;            /* 学习项库（原 vocab） */
    size_t item_count;
    size_t item_capacity;
    
    content_source_t *sources;      /* 载体列表 */
    size_t source_count;
    size_t source_capacity;
    
    chapter_t *chapters;            /* 章节列表 */
    size_t chapter_count;
    size_t chapter_capacity;
    
    /* ====== 用户私有数据 ====== */
    user_t *users;
    size_t user_count;
    size_t user_capacity;
    
    user_item_mastery_t *mastery;   /* 核心表：用户-学习项掌握度 */
    size_t mastery_count;
    size_t mastery_capacity;
    
    reading_progress_t *progress;   /* 阅读进度 */
    size_t progress_count;
    size_t progress_capacity;
    
    daily_stat_t *stats;            /* 每日统计 */
    size_t stat_count;
    size_t stat_capacity;
    
    /* ====== 运行时索引（不保存到磁盘）====== */
    void *question_hash;            /* question(string) → item_index */
    void *id_hash;                  /* item_id → item_index */
    void *source_hash;              /* source_id → source_index */
    void *user_hash;                /* dingtalk_uid → user_index */
    void *user_id_hash;             /* user_id → user_index (O(1)) */
    void *mastery_hash;             /* (user_id,item_id) → mastery_index */
    void *stat_hash;                /* (user_id,date) → stat_index (O(1)) */
    
    /* ====== 到期复习索引（惰性重建）====== */
    uint32_t *mastery_due_sorted;   /* 按 next_review 排序的 mastery 索引 */
    size_t mastery_due_sorted_count;
    int mastery_due_dirty;          /* 1 = 需要重建排序 */
    
    /* ====== 异步保存状态 ====== */
    int dirty;                      /* 数据是否被修改 */
    char db_path[256];              /* 数据库文件路径 */
} wordcard_db_t;

/* ========================================================================
 * 错误码
 * ======================================================================== */

typedef enum {
    WC_OK = 0,                      /* 成功 */
    WC_ERR_MEMORY = -1,             /* 内存分配失败 */
    WC_ERR_FILE = -2,               /* 文件操作失败 */
    WC_ERR_CORRUPT = -3,            /* 文件损坏 */
    WC_ERR_NOT_FOUND = -4,          /* 记录不存在 */
    WC_ERR_EXISTS = -5,             /* 记录已存在 */
    WC_ERR_INVALID = -6,            /* 参数无效 */
} wc_error_t;

/* ========================================================================
 * API 函数声明
 * ======================================================================== */

/* -------- 数据库生命周期 -------- */

wordcard_db_t* wc_db_init(void);
void wc_db_free(wordcard_db_t *db);
wordcard_db_t* wc_load_db(const char *path);
int wc_save_db(wordcard_db_t *db, const char *path);
void wc_mark_dirty(wordcard_db_t *db);

/* -------- 学习项操作 -------- */

uint32_t wc_add_item(wordcard_db_t *db, const item_entry_t *entry);
item_entry_t* wc_find_item_by_question(wordcard_db_t *db, const char *question);
item_entry_t* wc_find_item_by_id(wordcard_db_t *db, uint32_t item_id);

/* -------- 载体/内容源操作 -------- */

uint32_t wc_add_source(wordcard_db_t *db, const content_source_t *source);
content_source_t* wc_find_source_by_id(wordcard_db_t *db, uint32_t source_id);
content_source_t* wc_find_source_by_name(wordcard_db_t *db, const char *name);

/* -------- 用户操作 -------- */

uint32_t wc_create_user(wordcard_db_t *db, const char *dingtalk_uid, const char *name);
user_t* wc_find_user(wordcard_db_t *db, const char *dingtalk_uid);
user_t* wc_find_user_by_id(wordcard_db_t *db, uint32_t user_id);

/* -------- 掌握度操作 -------- */

user_item_mastery_t* wc_get_or_create_mastery(wordcard_db_t *db, 
                                               uint32_t user_id, 
                                               uint32_t item_id);
user_item_mastery_t* wc_find_mastery(wordcard_db_t *db, 
                                      uint32_t user_id, 
                                      uint32_t item_id);
void wc_sm2_update(user_item_mastery_t *mastery, uint8_t quality);
void wc_update_mastery_dimension(wordcard_db_t *db,
                                  user_item_mastery_t *mastery,
                                  char dimension,
                                  int correct,
                                  uint8_t score);
void wc_recalc_overall(user_item_mastery_t *mastery);

/* -------- 查询接口 -------- */

size_t wc_get_due_items(wordcard_db_t *db, uint32_t user_id, uint32_t now,
                         uint32_t *out_ids, size_t max_count);
size_t wc_get_new_items(wordcard_db_t *db, uint32_t user_id, uint32_t source_id,
                         uint32_t *out_ids, size_t max_count);
size_t wc_generate_daily_queue(wordcard_db_t *db, uint32_t user_id, uint32_t now,
                                uint32_t *out_ids, uint8_t *out_modes, 
                                size_t max_count);

/* -------- 推荐算法 -------- */

study_mode_t wc_recommend_mode(const user_item_mastery_t *mastery, uint32_t now);

/* -------- 每日统计 -------- */

daily_stat_t* wc_get_or_create_daily_stat(wordcard_db_t *db, 
                                            uint32_t user_id, 
                                            uint32_t date);
void wc_record_activity(wordcard_db_t *db, uint32_t user_id, 
                         int is_new, int is_correct, uint32_t time_spent);

/* -------- 通知与工具函数 -------- */

void wc_notify_mastery_changed(wordcard_db_t *db);
uint32_t wc_now(void);
uint32_t wc_today(void);
const char* wc_version_string(void);

/* ======================================================================== */

#ifdef __cplusplus
}
#endif

#endif /* WORDCARD_H */
