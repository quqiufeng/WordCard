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

#define WC_MAGIC            "WCD\x02"        /* 文件魔数，版本2 */
#define WC_VERSION          2
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

/* 载体类别：单词的来源 */
typedef enum {
    SOURCE_PDF = 1,         /* PDF 精读 */
    SOURCE_WORDLIST = 2,    /* 词汇表（CET-4/6/雅思等） */
    SOURCE_ARTICLE = 3,     /* 短文 */
    SOURCE_MOVIE = 4,       /* 影视台词 */
    SOURCE_EXAM = 5,        /* 真题语境 */
    SOURCE_SCENE = 6,       /* 主题场景 */
} source_type_t;

/* 学习模式/练习模式 */
typedef enum {
    MODE_FLASHCARD = 1,     /* 闪卡模式 */
    MODE_CHOICE = 2,        /* 选择题 */
    MODE_FILLBLANK = 3,     /* 填空题 */
    MODE_SPELLING = 4,      /* 拼写 */
    MODE_DICTATION = 5,     /* 听写 */
    MODE_PRONUNCIATION = 6, /* 朗读/发音 */
    MODE_MATCHING = 7,      /* 配对 */
    MODE_SPEED_REVIEW = 8,  /* 速闪 */
} study_mode_t;

/* SM-2 学习状态 */
typedef enum {
    SM2_NEW = 0,            /* 新词 */
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
    char name[128];                 /* 名称："Solar System", "CET-4" */
    char file_path[256];            /* 源文件路径 */
    uint32_t vocab_start;           /* 在全局词汇表中的起始索引 */
    uint32_t vocab_count;           /* 包含的词汇数量 */
    uint32_t created_at;            /* 创建时间戳 */
} content_source_t;

/* 单词条目 */
typedef struct {
    uint32_t id;                    /* 唯一ID */
    char word[64];                  /* 英文单词 */
    char phonetic[64];              /* 音标 */
    char meaning[256];              /* 中文释义 */
    char pos[16];                   /* 词性：n./v./adj. */
    char example[512];              /* 原文例句 */
    char example_cn[512];           /* 例句翻译 */
    uint8_t difficulty;             /* 难度等级 1-5 */
    uint32_t source_id;             /* 关联载体ID */
    uint32_t frequency;             /* 在载体中出现次数 */
} vocab_entry_t;

/* 段落/章节（PDF精读模式用） */
typedef struct {
    uint32_t id;                    /* 唯一ID */
    uint32_t source_id;             /* 关联载体ID */
    char title[256];                /* 章节标题 */
    uint32_t page_start;            /* 起始页码 */
    uint32_t page_end;              /* 结束页码 */
    uint32_t vocab_start_idx;       /* 词汇起始索引 */
    uint32_t vocab_count;           /* 词汇数量 */
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
    uint16_t daily_new_limit;       /* 每日新词上限 */
    uint16_t daily_review_limit;    /* 每日复习上限 */
    uint32_t created_at;            /* 注册时间 */
    uint32_t last_active;           /* 最后活跃时间 */
} user_t;

/* 用户单词掌握度 —— 核心表，追踪学习全过程 */
typedef struct {
    uint32_t user_id;               /* 所属用户 */
    uint32_t vocab_id;              /* 单词ID */
    
    /* ====== SM-2 核心参数 ====== */
    uint8_t sm2_status;             /* 0=新词, 1=学习中, 2=已掌握 */
    uint16_t interval_days;         /* 下次间隔天数 */
    uint16_t repetitions;           /* 成功重复次数 */
    float ease_factor;              /* 难度因子（默认2.5） */
    uint32_t next_review;           /* 下次复习时间戳 */
    uint32_t last_review;           /* 上次复习时间戳 */
    
    /* ====== 多维度掌握度（0-100）====== */
    uint8_t recognition;            /* 视觉识别：看英文→知中文 */
    uint8_t recall;                 /* 主动回忆：看中文→想英文 */
    uint8_t spelling;               /* 拼写准确度 */
    uint8_t listening;              /* 听音辨词 */
    uint8_t pronunciation;          /* 发音评分（ASR评估） */
    uint8_t usage;                  /* 语境中使用 */
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
} user_vocab_mastery_t;

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
    uint16_t new_words;             /* 今日新学 */
    uint16_t reviewed_words;        /* 今日复习 */
    uint16_t mastered_words;        /* 今日掌握 */
    uint16_t wrong_words;           /* 今日错误 */
    uint32_t study_time_sec;        /* 学习时长（秒） */
} daily_stat_t;

/* ========================================================================
 * 文件头结构（64字节，磁盘格式）
 * ======================================================================== */

typedef struct {
    char magic[4];                  /* "WCD\x02" */
    uint32_t version;               /* 版本号 = 2 */
    uint32_t vocab_count;           /* 词汇数量 */
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
    vocab_entry_t *vocab;           /* 词汇库 */
    size_t vocab_count;
    size_t vocab_capacity;
    
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
    
    user_vocab_mastery_t *mastery;  /* 核心表：用户-单词掌握度 */
    size_t mastery_count;
    size_t mastery_capacity;
    
    reading_progress_t *progress;   /* 阅读进度 */
    size_t progress_count;
    size_t progress_capacity;
    
    daily_stat_t *stats;            /* 每日统计 */
    size_t stat_count;
    size_t stat_capacity;
    
    /* ====== 运行时索引（不保存到磁盘）====== */
    void *word_hash;                /* word(string) → vocab_index */
    void *id_hash;                  /* vocab_id → vocab_index */
    void *source_hash;              /* source_id → source_index */
    void *user_hash;                /* dingtalk_uid → user_index */
    void *user_id_hash;             /* user_id → user_index (O(1) 用户ID查找) */
    void *mastery_hash;             /* (user_id,vocab_id) → mastery_index */
    void *stat_hash;                /* (user_id,date) → stat_index (O(1) 统计查找) */
    
    /* ====== 到期复习索引（惰性重建）====== */
    uint32_t *mastery_due_sorted;   /* 按 next_review 排序的 mastery 索引数组 */
    size_t mastery_due_sorted_count;/* 已排序记录数 */
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

/**
 * 初始化空数据库
 * @return 数据库句柄，失败返回 NULL
 */
wordcard_db_t* wc_db_init(void);

/**
 * 释放数据库及所有内存
 */
void wc_db_free(wordcard_db_t *db);

/**
 * 从磁盘加载数据库
 * @param path 文件路径
 * @return 数据库句柄，失败返回 NULL
 */
wordcard_db_t* wc_load_db(const char *path);

/**
 * 同步保存数据库到磁盘
 * @param db 数据库句柄
 * @param path 文件路径（NULL 则使用 db->db_path）
 * @return WC_OK 或错误码
 */
int wc_save_db(wordcard_db_t *db, const char *path);

/**
 * 标记数据库为脏（有修改），触发异步保存
 */
void wc_mark_dirty(wordcard_db_t *db);

/* -------- 词汇库操作 -------- */

/**
 * 添加单词到全局词汇库
 * @return 新单词的ID，失败返回 0
 */
uint32_t wc_add_vocab(wordcard_db_t *db, const vocab_entry_t *entry);

/**
 * 根据单词文本查找（精确匹配）
 * @return vocab_entry_t 指针，未找到返回 NULL
 */
vocab_entry_t* wc_find_vocab_by_word(wordcard_db_t *db, const char *word);

/**
 * 根据ID查找单词
 */
vocab_entry_t* wc_find_vocab_by_id(wordcard_db_t *db, uint32_t vocab_id);

/* -------- 用户操作 -------- */

/**
 * 创建用户
 * @param dingtalk_uid 钉钉用户ID
 * @return 新用户的内部ID，失败返回 0
 */
uint32_t wc_create_user(wordcard_db_t *db, const char *dingtalk_uid, const char *name);

/**
 * 根据钉钉UID查找用户
 */
user_t* wc_find_user(wordcard_db_t *db, const char *dingtalk_uid);

/**
 * 根据内部ID查找用户
 */
user_t* wc_find_user_by_id(wordcard_db_t *db, uint32_t user_id);

/* -------- 载体/内容源操作 -------- */

/**
 * 添加内容载体
 * @return 新载体ID，失败返回 0
 */
uint32_t wc_add_source(wordcard_db_t *db, const content_source_t *source);

/**
 * 根据ID查找载体
 */
content_source_t* wc_find_source_by_id(wordcard_db_t *db, uint32_t source_id);

/**
 * 根据名称查找载体
 */
content_source_t* wc_find_source_by_name(wordcard_db_t *db, const char *name);

/* -------- 掌握度操作 -------- */

/**
 * 获取或创建用户对某词的掌握度记录
 * @return mastery 指针，失败返回 NULL
 */
user_vocab_mastery_t* wc_get_or_create_mastery(wordcard_db_t *db, 
                                                  uint32_t user_id, 
                                                  uint32_t vocab_id);

/**
 * 查询掌握度（不创建新记录）
 */
user_vocab_mastery_t* wc_find_mastery(wordcard_db_t *db, 
                                       uint32_t user_id, 
                                       uint32_t vocab_id);

/**
 * 更新 SM-2 参数（核心算法）
 * @param mastery 掌握度记录
 * @param quality 用户评级 0-5（0=完全忘记, 5=完美回忆）
 */
void wc_sm2_update(user_vocab_mastery_t *mastery, uint8_t quality);

/**
 * 更新多维度掌握度
 * @param dimension 维度：'r'=recognition, 'c'=recall, 's'=spelling, 
 *                         'l'=listening, 'p'=pronunciation, 'u'=usage
 * @param correct 是否正确/得分
 * @param score 发音评分等具体分数（0-100），其他维度传0
 */
void wc_update_mastery_dimension(wordcard_db_t *db,
                                  user_vocab_mastery_t *mastery,
                                  char dimension,
                                  int correct,
                                  uint8_t score);

/**
 * 重新计算综合掌握度
 */
void wc_recalc_overall(user_vocab_mastery_t *mastery);

/* -------- 查询接口 -------- */

/**
 * 获取用户今日到期复习的单词列表
 * @param user_id 用户ID
 * @param now 当前时间戳
 * @param out_ids 输出数组（调用者分配）
 * @param max_count 最大返回数量
 * @return 实际返回数量
 */
size_t wc_get_due_words(wordcard_db_t *db, uint32_t user_id, uint32_t now,
                         uint32_t *out_ids, size_t max_count);

/**
 * 获取用户的新词列表（未学习过的单词）
 * @param source_id 载体ID（0=全部载体）
 */
size_t wc_get_new_words(wordcard_db_t *db, uint32_t user_id, uint32_t source_id,
                         uint32_t *out_ids, size_t max_count);

/**
 * 生成今日学习队列
 * @param out_modes 输出推荐模式数组（与 out_ids 对应）
 */
size_t wc_generate_daily_queue(wordcard_db_t *db, uint32_t user_id, uint32_t now,
                                uint32_t *out_ids, uint8_t *out_modes, 
                                size_t max_count);

/* -------- 推荐算法 -------- */

/**
 * 根据掌握度推荐学习模式
 * @return study_mode_t 枚举值
 */
study_mode_t wc_recommend_mode(const user_vocab_mastery_t *mastery, uint32_t now);

/* -------- 每日统计 -------- */

/**
 * 获取或创建用户某日的统计记录
 */
daily_stat_t* wc_get_or_create_daily_stat(wordcard_db_t *db, 
                                            uint32_t user_id, 
                                            uint32_t date);

/**
 * 记录学习活动（自动更新每日统计）
 * @param is_new 是否是新词
 * @param is_correct 是否正确
 * @param time_spent 花费时间（秒）
 */
void wc_record_activity(wordcard_db_t *db, uint32_t user_id, 
                         int is_new, int is_correct, uint32_t time_spent);

/* -------- 工具函数 -------- */

/**
 * 获取当前时间戳
 */
uint32_t wc_now(void);

/**
 * 获取今日日期（YYYYMMDD）
 */
uint32_t wc_today(void);

/**
 * 通知掌握度数据已变更，触发到期索引重建
 */
void wc_notify_mastery_changed(wordcard_db_t *db);

/**
 * 返回版本号字符串
 */
const char* wc_version_string(void);

/* ======================================================================== */

#ifdef __cplusplus
}
#endif

#endif /* WORDCARD_H */
