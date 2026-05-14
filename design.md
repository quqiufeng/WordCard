# WordCard 设计方案

> 基于 C 语言内存数据结构 + Python FastAPI HTTP 服务的极简架构
> 支持 PDF 文档导入，将整本书转化为渐进式记忆课程

---

## 一、设计哲学

**不需要数据库，不需要前端，不需要复杂部署。**

- **C 数据结构**：自己实现一个极简版 SQLite，数据结构紧凑，全部驻留内存，性能最大化
- **Python FastAPI**：只负责 HTTP 接口，业务逻辑（SM-2）下沉到 C 层
- **文件持久化**：启动时从硬盘加载到内存，运行时全内存操作，退出/定时保存回硬盘
- **钉钉机器人**：已解决用户入口，本地只需暴露 HTTP API
- **PDF 阅读**：上传一本英文 PDF，自动提取核心词汇，按阅读进度分批记忆，最终读懂全书

---

## 二、技术架构

```
用户上传 PDF
    │
    ▼
┌──────────────────────────────────────────┐
│  import_pdf.py (Python 处理层)            │
│  · PDF 文本提取 (PyMuPDF)                │
│  · 词汇频率分析                          │
│  · 生词筛选 (对比已掌握词汇库)            │
│  · 调用 llm.py 翻译 + 例句生成            │
│  · 按章节分块，生成词汇课程               │
└──────────────┬───────────────────────────┘
               │ 写入 .db
               ▼
┌──────────────────────────────────────────┐
│  libwordcard.so (C 共享库)                │
│  · 内存数据结构                          │
│  · SM-2 算法                             │
│  · 8 种记忆模式                          │
└───────┬──────────────────────────────────┘
        │
钉钉 App → 钉钉机器人 ──HTTP──→ Python FastAPI
                                        │
                                        ▼ ctypes FFI
                                ┌───────────────┐
                                │ libwordcard.so│
                                └───────────────┘
                                        │
                                        ▼
                                wordcard.db (二进制文件)
```

---

## 三、记忆方案矩阵

> 核心：找到用户最感兴趣的学习场景，用科学方法记住单词

### 3.1 方案总览

| 优先级 | 方案 | 目标用户 | 核心卖点 | 实现复杂度 | 状态 |
|--------|------|----------|----------|------------|------|
| **P0** | **短文模式** | 日常阅读者 | 读文章学单词，有上下文 | ⭐ | 已有 `llm.py` |
| **P0** | **精读模式** | 要读懂某本书的人 | 把整本PDF变成课程 | ⭐⭐ | 已有 `books/` |
| **P0** | **词汇表模式** | 应试备考者 | CET-4/6、雅思、托福系统背 | ⭐ | 词表导入 |
| **P0** | **语音互动** | 所有人 | 听写/朗读/发音评分 | ⭐⭐ | 已有 ASR+TTS |
| **P1** | **词根词缀模式** | 想举一反三的人 | 一个词根记住10个单词 | ⭐⭐ | 词根数据库 |
| **P1** | **主题场景模式** | 出国/工作/旅游 | 机场、餐厅、医院等实用场景 | ⭐⭐ | 场景词包 |
| **P1** | **易混词辨析** | 经常记混的人 | adapt vs adopt 不再混淆 | ⭐ | 混淆词对数据库 |
| **P2** | **影视台词模式** | 美剧爱好者 | 从Friends/绝命毒师学地道表达 | ⭐⭐⭐ | 字幕文件导入 |
| **P2** | **真题语境模式** | 短期冲刺者 | 历年真题原文语境记忆 | ⭐⭐ | 真题文本导入 |
| **P2** | **搭配语块模式** | 提高写作者 | 不背单词，背搭配 | ⭐⭐ | collocation 库 |
| **P2** | **游戏化模式** | 喜欢游戏的人 | 填字游戏、闯关解锁 | ⭐⭐⭐ | 游戏引擎 |

### 3.2 四大学习场景

```
场景 1: "我要读懂这本书"
    └── 方案: 精读模式 (PDF)
    └── 输入: 放入 books/ 目录
    └── 输出: 按章节解锁，全书通关
    └── 用户画像: 大学生、研究者、专业人士

场景 2: "我要考过四六级/雅思"
    └── 方案: 词汇表模式 + 真题语境
    └── 输入: 选择词表 (CET-4/6/IELTS/TOEFL)
    └── 输出: 按考纲系统背诵 + 真题验证
    └── 用户画像: 大学生、留学预备人员

场景 3: "我想提高日常英语"
    └── 方案: 短文模式 + 主题场景 + 影视台词
    └── 输入: 选择感兴趣的文章/美剧
    └── 输出: 地道表达 + 场景词汇
    └── 用户画像: 职场人士、英语爱好者

场景 4: "我总是记混单词"
    └── 方案: 易混词辨析 + 词根词缀
    └── 输入: 系统推送易混词对
    └── 输出: 对比记忆 + 词族网络
    └── 用户画像: 所有学习者（普遍存在）
```

### 3.3 统一底层架构

所有方案共享同一个核心：

```
┌─────────────────────────────────────┐
│           用户选择场景                │
│  (PDF精读/词汇表/短文/影视/真题...)   │
└──────────────┬──────────────────────┘
               │ 语料导入
               ▼
┌─────────────────────────────────────┐
│         C 核心库 (libwordcard.so)    │
│  · 统一数据结构 (vocab/record/progress)│
│  · SM-2 间隔重复算法                  │
│  · 内存数据库 + 文件持久化             │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│      8 种记忆模式 (modes.c)          │
│  闪卡/选择/填空/拼写/听写/朗读/配对/速闪│
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│      语音系统 (voice/)               │
│  · ASR 语音识别 (SenseVoice)         │
│  · TTS 语音合成 (Piper)              │
│  · 发音评估                          │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│      钉钉机器人 (HTTP API)           │
│  · 推送学习提醒                      │
│  · 接收用户回复                      │
│  · 返回学习结果                      │
└─────────────────────────────────────┘
```

### 3.4 数据结构扩展（支持多方案）

```c
/* 学习方案类型 */
typedef enum {
    MODE_ARTICLE = 1,       // 短文模式
    MODE_PDF = 2,           // 精读模式
    MODE_WORDLIST = 3,      // 词汇表模式
    MODE_SCENE = 4,         // 主题场景
    MODE_ROOT = 5,          // 词根词缀
    MODE_CONFUSABLE = 6,    // 易混词辨析
    MODE_MOVIE = 7,         // 影视台词
    MODE_EXAM = 8,          // 真题语境
} study_mode_t;

/* 词表条目（用于词汇表模式） */
typedef struct {
    uint32_t vocab_id;
    char list_name[64];     // "CET-4", "IELTS", "TOEFL"
    uint32_t list_order;    // 在词表中的顺序
    uint8_t is_required;    // 是否必考词
} wordlist_entry_t;

/* 场景条目（用于主题场景模式） */
typedef struct {
    uint32_t vocab_id;
    char scene_name[64];    // "airport", "restaurant", "hospital"
    char dialogue[512];     // 场景对话例句
} scene_entry_t;

/* 易混词对 */
typedef struct {
    uint32_t word1_id;
    uint32_t word2_id;
    char contrast[512];     // 对比说明
    char mnemonic[256];     // 记忆口诀
} confusable_pair_t;
```

### 3.5 各方案的语料来源

| 方案 | 语料来源 | 导入方式 |
|------|----------|----------|
| 短文模式 | `res/*.txt` 或用户粘贴 | 直接放入目录 |
| 精读模式 | `books/*.pdf` | `python import_books.py` |
| 词汇表模式 | 内置词表 / 用户上传 CSV | 选择词表导入 |
| 主题场景 | 内置场景库 | 随系统分发 |
| 词根词缀 | 内置词根数据库 | 随系统分发 |
| 易混词辨析 | 内置混淆词对 | 随系统分发 |
| 影视台词 | `movies/*.srt` | `python import_subtitles.py` |
| 真题语境 | `exams/*.txt` | `python import_exams.py` |

---

## 四、核心场景：读懂一本英文 PDF

### 3.1 使用流程

```
第 1 步: 放置 PDF 到指定目录
    └── 将英文 PDF 放入 books/ 目录
    └── 运行扫描工具: python import_books.py
    └── 系统分析: 总词数、生词数、预估学习时间

第 2 步: 系统生成阅读课程
    └── 按章节/页码分段
    └── 每段提取核心词汇 (20-30个)
    └── 生成释义、例句、发音
    └── 按词频排序 (高频优先)

第 3 步: 每日学习
    └── 系统按 SM-2 推送今日词汇
    └── 用户通过钉钉完成 8 种模式练习
    └── 掌握后解锁下一段内容

第 4 步: 阅读验证
    └── 每完成一段词汇，推送原文段落
    └── 用户阅读并回答理解题
    └── 通过后标记该段"已读懂"

第 5 步: 全书通关
    └── 所有段落标记"已读懂"
    └── 恭喜：你可以流畅阅读这本书了！
```

### 3.2 关键指标

| 指标 | 说明 |
|------|------|
| **词汇覆盖率** | 掌握 90% 高频词即可理解 95% 内容 |
| **渐进式解锁** | 按阅读顺序学习，不跳读 |
| **语境记忆** | 每个词都附带原文例句 |
| **阅读验证** | 学完词汇后立即阅读原文，检验理解 |

---

## 五、C 层数据结构（libwordcard.so）

### 4.1 核心结构体

```c
/* ==================== 全局共享数据（所有用户共用） ==================== */

/* 载体类别：单词的来源 */
typedef enum {
    SOURCE_PDF = 1,         // PDF 精读
    SOURCE_WORDLIST = 2,    // 词汇表（CET-4/6/雅思等）
    SOURCE_ARTICLE = 3,     // 短文
    SOURCE_MOVIE = 4,       // 影视台词
    SOURCE_EXAM = 5,        // 真题语境
    SOURCE_SCENE = 6,       // 主题场景
} source_type_t;

typedef struct {
    uint32_t id;
    source_type_t type;     // 载体类型
    char name[128];         // 名称："Solar System", "CET-4", "Friends S01E01"
    char file_path[256];    // 源文件路径
    uint32_t vocab_start;   // 在全局词汇表中的起始索引
    uint32_t vocab_count;   // 包含的词汇数量
    uint32_t created_at;
} content_source_t;

/* 单词条目 */
typedef struct {
    uint32_t id;
    char word[64];
    char phonetic[64];
    char meaning[256];
    char pos[16];
    char example[512];      // 原文例句
    char example_cn[512];   // 例句翻译
    uint8_t difficulty;
    uint32_t source_id;     // 关联载体ID（替代原来的article_id）
    uint32_t frequency;     // 在载体中出现次数
} vocab_entry_t;

/* 段落/章节（仅 PDF 精读模式需要） */
typedef struct {
    uint32_t id;
    uint32_t source_id;     // 关联载体ID
    char title[256];        // 章节标题
    uint32_t page_start;    // 起始页码
    uint32_t page_end;      // 结束页码
    uint32_t vocab_start_idx;
    uint32_t vocab_count;
    char summary[1024];     // 中文摘要
} chapter_t;

/* ==================== 用户私有数据（每个用户独立） ==================== */

/* 用户表 */
typedef struct {
    uint32_t id;                    // 内部用户ID
    char dingtalk_uid[64];          // 钉钉用户唯一标识
    char name[64];                  // 昵称
    uint8_t role;                   // 0=学生, 1=老师
    uint16_t daily_new_limit;       // 每日新词上限（默认10）
    uint16_t daily_review_limit;    // 每日复习上限（默认50）
    uint32_t created_at;
    uint32_t last_active;
} user_t;

/* 用户单词掌握度 - 替代原来的 study_record_t，多维度追踪 */
typedef struct {
    uint32_t user_id;               // 所属用户
    uint32_t vocab_id;              // 单词ID
    
    // ====== SM-2 核心参数 ======
    uint8_t sm2_status;             // 0=新词, 1=学习中, 2=已掌握
    uint16_t interval_days;         // 下次间隔
    uint16_t repetitions;           // 重复次数
    float ease_factor;              // 难度因子（默认2.5）
    uint32_t next_review;           // 下次复习时间戳
    uint32_t last_review;           // 上次复习时间戳
    
    // ====== 多维度掌握度（0-100）======
    // 算法根据这些值决定推荐哪种练习模式
    uint8_t recognition;            // 视觉识别：看英文→知中文
    uint8_t recall;                 // 主动回忆：看中文→想英文
    uint8_t spelling;               // 拼写准确度
    uint8_t listening;              // 听音辨词
    uint8_t pronunciation;          // 发音评分（ASR评估）
    uint8_t usage;                  // 语境中使用
    uint8_t overall;                // 综合掌握度（加权计算）
    
    // ====== 学习统计 ======
    uint16_t total_reviews;         // 总复习次数
    uint16_t correct_count;         // 正确次数
    uint16_t wrong_count;           // 错误次数
    uint8_t streak_days;            // 连续正确天数
    uint32_t first_seen;            // 首次学习时间
    uint32_t last_wrong;            // 上次错误时间
    uint8_t forget_count;           // "忘记"次数（评级<3）
    
    // ====== 用户标记 ======
    uint8_t is_difficult;           // 用户标记困难
    uint8_t is_favorite;            // 用户收藏
    uint8_t is_banned;              // 用户屏蔽（不再推送）
} user_vocab_mastery_t;

/* 阅读进度（PDF精读模式专用） */
typedef struct {
    uint32_t user_id;               // 所属用户
    uint32_t chapter_id;
    uint8_t status;                 // 0=锁定, 1=已解锁, 2=已读懂
    uint32_t unlocked_at;
    uint32_t completed_at;
    uint8_t quiz_score;             // 理解测试得分
} reading_progress_t;

/* 每日统计 */
typedef struct {
    uint32_t user_id;
    uint32_t date;                  // YYYYMMDD
    uint16_t new_words;             // 今日新学
    uint16_t reviewed_words;        // 今日复习
    uint16_t mastered_words;        // 今日掌握
    uint16_t wrong_words;           // 今日错误
    uint32_t study_time_sec;        // 学习时长
} daily_stat_t;

/* ==================== 内存数据库主结构 ==================== */

typedef struct {
    // ====== 全局共享数据（只读/少写） ======
    vocab_entry_t *vocab;           // 词汇库（所有用户共用）
    size_t vocab_count;
    size_t vocab_capacity;
    
    content_source_t *sources;      // 载体列表
    size_t source_count;
    size_t source_capacity;
    
    chapter_t *chapters;            // 章节列表（PDF用）
    size_t chapter_count;
    size_t chapter_capacity;
    
    // ====== 用户私有数据（按用户隔离） ======
    user_t *users;
    size_t user_count;
    size_t user_capacity;
    
    user_vocab_mastery_t *mastery;  // 用户-单词掌握度（核心表）
    size_t mastery_count;
    size_t mastery_capacity;
    
    reading_progress_t *progress;   // 阅读进度
    size_t progress_count;
    size_t progress_capacity;
    
    daily_stat_t *stats;            // 每日统计
    size_t stat_count;
    size_t stat_capacity;
    
    // ====== 运行时索引 ======
    void *word_hash;                // word -> vocab_index
    void *id_hash;                  // vocab_id -> vocab_index
    void *source_hash;              // source_id -> source_index
    void *user_hash;                // dingtalk_uid -> user_index
    void *mastery_hash;             // (user_id, vocab_id) -> mastery_index
    void *user_vocab_list;          // user_id -> vocab_id[]（该用户的词库）
} wordcard_db_t;
```

### 4.2 文件格式（wordcard.db）

```
[文件头] 64 bytes
  magic: "WCD\x02" (4 bytes)         // 版本升级到 2
  version: uint32_t = 2
  vocab_count: uint32_t
  source_count: uint32_t              // 载体数量
  chapter_count: uint32_t
  user_count: uint32_t                // 用户数量
  mastery_count: uint32_t             // 掌握度记录数
  progress_count: uint32_t
  stat_count: uint32_t                // 统计记录数
  reserved: 28 bytes

[词汇表]     vocab_count   * sizeof(vocab_entry_t)
[载体表]     source_count  * sizeof(content_source_t)
[章节表]     chapter_count * sizeof(chapter_t)

[用户表]     user_count    * sizeof(user_t)
[掌握度表]   mastery_count * sizeof(user_vocab_mastery_t)   // ⭐ 核心表
[阅读进度]   progress_count* sizeof(reading_progress_t)
[每日统计]   stat_count    * sizeof(daily_stat_t)
```

### 4.3 智能推荐算法（基于多维度掌握度）

算法不再只依赖 SM-2 的间隔，而是结合 **6 维掌握度** 做精准推荐：

```c
// 算法决策流程
void recommend_next_study(user_id, vocab_id) {
    user_vocab_mastery_t *m = get_mastery(user_id, vocab_id);
    
    // 规则 1: 新词 → 闪卡模式（建立初步认知）
    if (m->total_reviews == 0) {
        return MODE_FLASHCARD;
    }
    
    // 规则 2: 识别度高但拼写差 → 拼写/听写模式
    if (m->recognition > 80 && m->spelling < 50) {
        return MODE_SPELLING;
    }
    
    // 规则 3: 能认不能读 → 朗读模式（ASR 评分）
    if (m->recognition > 70 && m->pronunciation < 60) {
        return MODE_PRONUNCIATION;
    }
    
    // 规则 4: 能认不能听 → 听写模式
    if (m->recognition > 70 && m->listening < 50) {
        return MODE_DICTATION;
    }
    
    // 规则 5: 连续忘记 3 次以上 → 降级为闪卡 + 高频复习
    if (m->forget_count >= 3) {
        m->is_difficult = 1;
        return MODE_FLASHCARD;  // 回到基础重新建立
    }
    
    // 规则 6: 全面掌握 → 速闪维持
    if (m->overall > 85 && m->streak_days >= 5) {
        return MODE_SPEED_REVIEW;
    }
    
    // 规则 7: SM-2 到期复习 → 根据最弱维度选模式
    if (now >= m->next_review) {
        int weakest = min(m->recognition, m->recall, m->spelling, 
                         m->listening, m->pronunciation);
        return mode_for_dimension(weakest);
    }
    
    // 默认：综合测试（选择题）
    return MODE_CHOICE;
}
```

**掌握度更新示例**：
```c
// 用户完成一次拼写练习
void update_after_spelling(user_id, vocab_id, bool correct) {
    user_vocab_mastery_t *m = get_mastery(user_id, vocab_id);
    
    // 更新拼写掌握度（滑动平均）
    int delta = correct ? +10 : -15;
    m->spelling = clamp(m->spelling + delta, 0, 100);
    
    // 同步更新综合掌握度（加权）
    m->overall = (m->recognition * 0.25 + 
                  m->recall * 0.20 + 
                  m->spelling * 0.20 + 
                  m->listening * 0.15 + 
                  m->pronunciation * 0.10 + 
                  m->usage * 0.10);
    
    // SM-2 也更新
    sm2_update(m, correct ? 4 : 1);  // good=4, again=1
}
```

### 4.4 数据结构总览（共 7 种）

| 数据结构 | 类型 | 用途 | 关键字段 |
|---------|------|------|----------|
| `content_source_t` | 全局 | 载体类别（PDF/词表/短文） | type, name, file_path |
| `vocab_entry_t` | 全局 | 单词条目 | word, meaning, example, source_id |
| `chapter_t` | 全局 | 章节信息（PDF用） | title, source_id, vocab_range |
| `user_t` | 用户私有 | 用户信息 | dingtalk_uid, role, daily_limit |
| `user_vocab_mastery_t` | 用户私有 | **核心：单词掌握度** | SM-2参数 + 6维掌握度 + 统计 |
| `reading_progress_t` | 用户私有 | 阅读进度 | status, quiz_score |
| `daily_stat_t` | 用户私有 | 每日统计 | new/review/mastered count |

---

## 六、PDF 导入流程

### 5.1 处理步骤

```python
# import_books.py

def scan_books(directory="books/"):
    """扫描目录下的所有 PDF 文件"""
    pdf_files = []
    for f in os.listdir(directory):
        if f.endswith('.pdf'):
            pdf_files.append(os.path.join(directory, f))
    return pdf_files

def process_pdf(pdf_path, user_db_path):
    # 1. 提取文本
    text = extract_text_from_pdf(pdf_path)
    
    # 2. 分章节/分页
    chapters = split_into_chapters(text)
    
    # 3. 词汇分析
    for chapter in chapters:
        words = extract_unique_words(chapter.text)
        word_freq = count_frequency(words)
        
        # 4. 对比用户已掌握词汇，筛选生词
        new_words = filter_unknown_words(word_freq, user_db_path)
        
        # 5. 按频率排序 (高频优先)
        new_words.sort_by_frequency(desc=True)
        
        # 6. 调用 llm.py 翻译
        for word in new_words[:30]:  # 每章最多30个生词
            translation = llm_translate(word, chapter.context)
            save_to_db(word, translation, chapter.id)
    
    # 7. 生成解锁计划
    # 第1章默认解锁，后续章节需掌握前章 80% 词汇后解锁

# 命令行入口
if __name__ == '__main__':
    books = scan_books("books/")
    for book in books:
        print(f"导入: {book}")
        process_pdf(book, "data/wordcard.db")
```

### 5.2 智能生词筛选

不是 PDF 中所有生词都要背，而是：**高频 + 关键 + 不影响理解的跳过**

```python
def filter_unknown_words(word_freq, known_vocab):
    """
    筛选策略：
    1. 排除用户已掌握词汇
    2. 排除极高频基础词 (the, is, and 等)
    3. 排除低频专有名词 (人名、地名，除非重复出现)
    4. 按 frequency 排序
    5. 每章取 top 30
    """
    stop_words = load_stop_words()  # the, is, are, ...
    
    candidates = []
    for word, freq in word_freq.items():
        if word in known_vocab:
            continue
        if word in stop_words:
            continue
        if is_proper_noun(word) and freq < 3:
            continue
        candidates.append((word, freq))
    
    candidates.sort(key=lambda x: x[1], reverse=True)
    return candidates[:30]
```

### 5.3 解锁机制

```
章节 1: 默认解锁
    └── 学习词汇 → 完成练习 → 阅读原文 → 理解测试
    └── 测试通过 → 标记"已读懂" → 解锁章节 2

章节 2: 需章节 1 掌握 80% 词汇
    └── ...

章节 N: 渐进解锁，确保渐进式理解
```

---

## 七、8 种记忆模式（针对 PDF 语料优化）

### 6.1 模式列表

| 模式 | 说明 | PDF 语料优势 | 语音支持 |
|------|------|-------------|---------|
| **闪卡** | 单词 ↔ 释义 | 附带原文例句 | 🔊 TTS 播放发音 |
| **选择题** | 四选一 | 干扰项来自同章节其他词 | - |
| **填空** | 在例句中填词 | 例句直接取自原文 | 🔊 TTS 播放句子 |
| **拼写** | 看释义写单词 | - | 🔊 TTS 播放发音提示 |
| **听写** | 听发音写单词 | - | 🔊 TTS 播放单词 |
| **朗读** | 读单词/句子 | - | 🎤 ASR 识别 + 评分 |
| **配对** | 单词-释义配对 | 同一章节的词一起练 | - |
| **词根** | 分析词根词缀 | - | - |
| **速闪** | 3秒快速判断 | 适合复习已掌握词汇 | 🔊 TTS 自动播放 |

### 6.2 语音集成架构

```
钉钉用户发送语音消息
    │
    ▼
┌──────────────────┐
│ 钉钉机器人服务器  │
│ 下载语音文件(amr) │
└────────┬─────────┘
         │ HTTP POST /api/v1/voice/asr
         ▼
┌──────────────────┐
│  WordCard API    │
│  · ffmpeg 转 WAV  │
│  · SenseVoice 识别│
│  · 返回文本       │
└────────┬─────────┘
         │
         ▼ 文本命令（如"开始学习"、"下一个"）
    执行对应逻辑
         │
         ▼ 需要语音回复
┌──────────────────┐
│  Piper TTS 合成   │
│  · 文本 → WAV    │
│  · 返回音频 URL  │
└────────┬─────────┘
         │
         ▼
    钉钉机器人发送语音给用户
```

### 6.3 原文语境优先

所有模式的例句都**直接取自 PDF 原文**，不是 AI 生成的：

```json
{
    "word": "asteroid",
    "meaning": "小行星",
    "example": "Beyond Mars lies the asteroid belt, a region containing millions of rocky objects.",
    "example_cn": "火星之外是小行星带，那里有数百万颗岩石天体。",
    "source": "Solar System, Chapter 3, Page 12"
}
```

### 6.4 阅读验证模式

学完一段词汇后，进入**原文阅读验证**：

```
[原文段落]
The solar system consists of the Sun and everything that orbits, 
or travels around, the Sun. This includes the eight planets and 
their moons, dwarf planets, and countless asteroids, comets, 
and other small icy objects.

[理解测试]
1. 太阳系包含哪些天体？
   A) 只有行星    B) 行星、卫星、小行星等    C) 只有太阳
   
2. "orbits" 在文中的意思是？
   A) 发光    B) 绕行    C) 爆炸

答对 80% 以上 → 标记"已读懂" → 解锁下一章
```

---

## 七、API 设计

### 7.1 PDF 导入

```bash
# 命令行扫描目录，导入所有 PDF
python import_books.py --dir books/

# 输出:
# 扫描到 3 本 PDF:
#   [1] Solar System.pdf - 45页, 340生词, 8章节, 预计17天
#   [2] Biology Basics.pdf - 120页, 520生词, 12章节, 预计26天
#   [3] World History.pdf - 200页, 680生词, 15章节, 预计34天
# 
# 开始导入...
# Solar System.pdf: 提取词汇 ▓▓▓▓▓▓▓▓▓▓ 100%
# Biology Basics.pdf: 翻译中 ▓▓▓▓▓▓▓▓░░ 80%
# 
# 导入完成！已更新 wordcard.db
# 新增词汇: 1540, 新增章节: 35
# 输入 'python api.py' 启动服务开始学习
```

### 7.3 今日任务（含阅读解锁）

```
POST /api/v1/study/today
Body: {"user_id": "ding_xxx"}

→ {
    "review_count": 12,
    "new_count": 8,
    "reading": {
        "chapter_id": 3,
        "title": "The Outer Planets",
        "status": "unlocked",       // 已解锁，可以读了
        "vocab_mastered": "85%",    // 已掌握该章 85% 词汇
        "can_read": true            // 达到 80% 阈值，开放阅读
    },
    "tasks": [...]
}
```

### 7.4 阅读验证

```
POST /api/v1/reading/quiz
Body: {"user_id": "ding_xxx", "chapter_id": 3}

→ {
    "chapter_id": 3,
    "title": "The Outer Planets",
    "text": "Beyond Neptune lies the Kuiper Belt...",
    "questions": [
        {
            "q_id": 1,
            "question": "What lies beyond Neptune?",
            "options": ["Asteroid belt", "Kuiper Belt", "Oort Cloud"],
            "correct": 1
        }
    ]
}
```

提交：
```
POST /api/v1/reading/submit
Body: {"user_id": "ding_xxx", "chapter_id": 3, "answers": [1, 0, 2]}

→ {
    "score": 85,
    "passed": true,              // >= 80%
    "chapter_unlocked": 4,       // 解锁下一章
    "mastery_bonus": "+5%"       // 本章词汇熟练度加成
}
```

### 7.5 阅读进度

```
GET /api/v1/reading/progress?user_id=ding_xxx

→ {
    "current_book": "Solar System",
    "total_chapters": 8,
    "completed_chapters": 3,
    "completion_rate": "37.5%",
    "vocab_mastered": 156,
    "vocab_total": 340,
    "estimated_finish": "2026-05-28",
    "chapters": [
        {"id": 1, "title": "Introduction", "status": "completed", "mastery": "95%"},
        {"id": 2, "title": "The Sun", "status": "completed", "mastery": "88%"},
        {"id": 3, "title": "The Outer Planets", "status": "learning", "mastery": "85%"},
        {"id": 4, "title": "Moons and Rings", "status": "locked", "mastery": "0%"},
        ...
    ]
}
```

---

## 八、卡片系统（card.py 集成）

> 复用现有的 `card.py` 渲染引擎，为教学场景提供卡片生成服务

### 8.1 老师语音教学场景

```
老师在钉钉群发送语音：
"今天的单词是 solar 和 asteroid，大家记一下"

    │
    ▼
ASR 识别 → 提取关键词 "solar", "asteroid"
    │
    ▼
查询 C 数据库 → 获取单词释义、例句、音标
    │
    ▼
card.py 渲染 → 生成 PNG 卡片
    │
    ▼
钉钉机器人 → 发送图片到群里
    │
    ▼
学生收到精美单词卡片，可收藏/转发
```

### 8.2 卡片 API

#### 生成单词卡片（从数据库）

```
POST /api/v1/card/generate
Body: {"vocab_ids": [23, 45], "format": "png"}

→ {
    "code": 200,
    "data": {
        "cards": [
            {
                "vocab_id": 23,
                "word": "solar",
                "image_url": "/tmp/card_23_1699123456.png",
                "preview": "data:image/png;base64,iVBORw0KGgo..."
            }
        ]
    }
}
```

#### 老师语音生成卡片

```
POST /api/v1/card/voice
Content-Type: multipart/form-data
Body: file=@teacher_voice.amr, format="png"

→ {
    "code": 200,
    "data": {
        "recognized_text": "今天的单词是 solar 和 asteroid",
        "extracted_words": ["solar", "asteroid"],
        "cards": [
            {
                "word": "solar",
                "image_url": "/tmp/card_solar_1699123456.png"
            },
            {
                "word": "asteroid",
                "image_url": "/tmp/card_asteroid_1699123456.png"
            }
        ]
    }
}
```

#### 批量生成课程卡片

```
POST /api/v1/card/lesson
Body: {"chapter_id": 3, "format": "pdf"}

→ {
    "code": 200,
    "data": {
        "lesson_title": "The Outer Planets",
        "vocab_count": 20,
        "output_file": "/tmp/lesson_ch3_1699123456.pdf",
        "pages": 5
    }
}
```

### 8.3 卡片格式支持

| 格式 | 用途 | 特点 |
|------|------|------|
| **PNG** | 钉钉群分享 | 固定宽度 780px，米色护眼背景，适合手机浏览 |
| **PDF** | 打印/分发 | 多页面，每页一个章节，标准文档格式 |
| **MD** | 二次编辑 | 纯文本，GitHub 渲染，可修改 |

### 8.4 卡片内容结构

```
┌──────────────────────────────┐
│  WordCard                    │
├──────────────────────────────┤
│  solar  /ˈsoʊlər/            │
├──────────────────────────────┤
│  原文                        │
│  The solar system consists   │
│  of the Sun...               │
├──────────────────────────────┤
│  中英双语                    │
│  The solar system consists   │
│  太阳系由太阳和...           │
├──────────────────────────────┤
│  词汇表                      │
│  solar  太阳的  │  system   │
│  orbit  轨道    │  planet   │
├──────────────────────────────┤
│  精彩句子                    │
│  The solar panels convert    │
│  sunlight into electricity.  │
│  太阳能板将阳光转化为电能。  │
└──────────────────────────────┘
```

### 8.5 集成方式

```python
# api/card_service.py
from card import load_txt, create_md, create_png, create_pdf
from voice.asr import recognize_audio
import re

def generate_card_from_vocab(vocab_id: int, db, format: str = "png"):
    """从数据库生成单张卡片"""
    # 1. 查询 C 数据库
    vocab = db.get_vocab(vocab_id)
    
    # 2. 构建 sections 字典（card.py 需要的格式）
    sections = {
        'title': vocab.word,
        'original': vocab.example,
        'en_ch': f"{vocab.example}\n{vocab.example_cn}",
        'vocabulary': [f"{vocab.word}|{vocab.meaning}"],
        'sentences': f"{vocab.example}\n{vocab.example_cn}"
    }
    
    # 3. 调用 card.py 渲染
    output_path = f"/tmp/card_{vocab_id}_{int(time.time())}.{format}"
    if format == "png":
        create_png(sections, output_path)
    elif format == "pdf":
        create_pdf(sections, output_path)
    elif format == "md":
        create_md(sections, output_path)
    
    return output_path

def generate_cards_from_voice(voice_file: str, db, format: str = "png"):
    """从老师语音生成卡片"""
    # 1. ASR 识别
    text = recognize_audio(voice_file)
    
    # 2. 提取英文单词（正则匹配）
    words = re.findall(r'\b[a-zA-Z]+\b', text)
    
    # 3. 查询数据库，过滤有效单词
    valid_words = []
    for word in words:
        vocab = db.find_word(word.lower())
        if vocab:
            valid_words.append(vocab)
    
    # 4. 批量生成卡片
    cards = []
    for vocab in valid_words:
        path = generate_card_from_vocab(vocab.id, db, format)
        cards.append({
            "word": vocab.word,
            "image_url": path
        })
    
    return {
        "recognized_text": text,
        "extracted_words": [v.word for v in valid_words],
        "cards": cards
    }
```

### 8.6 项目结构更新

```
WordCard/
├── card.py                   # 卡片渲染引擎（已有，复用）
├── api/
│   ├── card_service.py       # 卡片业务逻辑
│   └── routes.py             # 新增 /card/* 路由
└── output/cards/             # 生成的卡片缓存
```

---

## 九、项目结构

```
WordCard/
├── run_qwen3.sh              # llama.cpp 启动脚本
├── llm.py                    # 翻译生成
├── card.py                   # 卡片生成
│
├── src/                      # C 语言核心库
│   ├── wordcard.h            # 头文件
│   ├── wordcard.c            # 数据库 + SM-2 + 文件 IO
│   ├── modes.c               # 8 种记忆模式
│   └── Makefile              # 编译 libwordcard.so
│
├── api.py                    # FastAPI 入口
├── api/
│   ├── __init__.py
│   ├── routes.py             # HTTP 路由
│   ├── models.py             # Pydantic 模型
│   └── ffi.py                # ctypes FFI 绑定
│
├── importer/                 # ⭐ PDF 导入系统
│   ├── __init__.py
│   ├── pdf_parser.py         # PDF 文本提取
│   ├── vocab_analyzer.py     # 词汇频率分析 + 生词筛选
│   ├── chapter_splitter.py   # 章节分割
│   └── import_books.py       # 目录扫描 + 导入入口
│
### 语音系统复刻（来自 ~/my-agent）

**ASR 语音识别** (`voice/asr.py`):
```python
# 复刻自 ~/my-agent/ding/voice_recognition.py
# - 加载 libsensevoice.so (ctypes)
# - 模型常驻内存（避免每次加载 ~0.8s）
# - ffmpeg 音频格式转换
# - 支持 amr/wav/mp3 → 16kHz WAV

# 依赖：
#   - libsensevoice.so (已编译)
#   - sense-voice-small-q6_k.gguf (模型文件)
#   - ffmpeg
```

**TTS 语音合成** (`voice/tts.py`):
```python
# 复刻自 ~/my-agent/ding/text_to_speech.py
# - 加载 libpiper_tts.so (ctypes)
# - 模型常驻内存
# - 纯 CPU 运行，零显存
# - 输出 16-bit PCM WAV

# 依赖：
#   - libpiper_tts.so (已编译)
#   - zh_CN-huayan-medium.onnx (中文模型)
#   - zh_CN-huayan-medium.onnx.json (配置)
#   - espeak-ng-data/
```

**发音评估** (`voice/pronunciation.py`):
```python
# 组合 ASR + TTS：
# 1. TTS 播放标准发音
# 2. 用户录制语音
# 3. ASR 识别用户语音
# 4. 对比文本相似度
# 5. 返回评分（0-100）
```
│
├── tools/
│   └── import_data.py        # 从 output/ 导入
│
├── data/
│   └── wordcard.db           # 数据文件
│
└── requirements.txt
```

---

## 九、开发计划

### 阶段一：C 核心库（1天）
- 数据结构定义
- 文件 IO（load/save）
- SM-2 算法
- 基础查询接口

### 阶段二：记忆模式（1天）
- 8 种模式题目生成
- 熟练度追踪
- 混合练习推荐

### 阶段三：PDF 导入系统（1天）
- PDF 文本提取
- 词汇分析 + 生词筛选
- 章节分割
- 调用 llm.py 翻译

### 阶段四：Python API（0.5天）
- FastAPI 路由
- ctypes FFI
- PDF 上传处理
- 阅读验证

**总计：3.5 天**

---

## 十、使用示例

```bash
# 1. 启动 llama.cpp
./run_qwen3.sh

# 2. 放置 PDF 到 books/ 目录
mkdir -p books/
cp ~/Downloads/solar_system.pdf books/

# 3. 扫描导入所有 PDF
python importer/import_books.py --dir books/

# 4. 启动 API（语音模型自动加载）
uvicorn api:app --host 0.0.0.0 --port 8000

# 5. 用户通过钉钉开始学习
# 支持语音交互：
#   - 用户发送语音 → ASR 识别 → 执行命令
#   - 系统推送 TTS 发音 → 用户听写/跟读
```

---

---

## 十二、语音系统编译与集成

### 12.1 目录结构

```
voice/
├── __init__.py
├── asr.py                    # ASR Python 接口
├── tts.py                    # TTS Python 接口
├── pronunciation.py          # 发音评估
├── libs/                     # 编译好的共享库
│   ├── libsensevoice.so      # SenseVoice 库
│   └── libpiper_tts.so       # Piper TTS 库
├── models/                   # 模型文件
│   ├── sense-voice-small-q6_k.gguf
│   ├── zh_CN-huayan-medium.onnx
│   ├── zh_CN-huayan-medium.onnx.json
│   └── espeak-ng-data/       # espeak-ng 数据目录
└── wrappers/                 # C++ Wrapper 源码（独立维护）
    ├── sensevoice_wrapper.cpp
    ├── piper_wrapper.cpp
    └── README.md             # 编译说明
```

### 12.2 编译步骤

#### Step 1: 编译 SenseVoice Wrapper

```bash
# 进入 SenseVoice 源码目录
cd /home/dministrator/SenseVoice.cpp

# 编译 wrapper（链接 SenseVoice 静态库 + ggml）
g++ -shared -fPIC -std=c++17 \
  -I. -Isense-voice/csrc -Ibuild/_deps/ggml-src/include \
  voice/wrappers/sensevoice_wrapper.cpp \
  build/lib/libsense-voice-core.a \
  build/lib/libcommon.a \
  -Lbuild/lib -lggml -lggml-base -lggml-cpu \
  -o voice/libs/libsensevoice.so \
  -lpthread -ldl

# 验证
ls -lh voice/libs/libsensevoice.so
```

**依赖检查清单**：
- [ ] SenseVoice.cpp 源码已编译 (`build/lib/` 下有 `.a` 文件)
- [ ] ggml 库已生成 (`build/lib/libggml.so`)
- [ ] 模型文件：`models/sense-voice-small-q6_k.gguf`

#### Step 2: 编译 Piper TTS Wrapper

```bash
# 进入 Piper 源码目录
cd /opt/piper-src

# 1. 先编译 Piper 本体（如果还没编译）
mkdir -p build && cd build
cmake -DCMAKE_CXX_FLAGS="-fPIC" ..
make -j$(nproc) piper_tts

# 2. 编译 wrapper
cd /opt/piper-src
g++ -shared -fPIC -std=c++17 \
  -Isrc/cpp -Ibuild -Ipiper-phonemize/src -Ionnxruntime/include \
  /home/dministrator/WordCard/voice/wrappers/piper_wrapper.cpp \
  build/src/cpp/piper.cpp \
  -Lbuild/lib -lpiper_phonemize -lonnxruntime \
  -lespeak-ng \
  -o /home/dministrator/WordCard/voice/libs/libpiper_tts.so \
  -lpthread -ldl

# 验证
ls -lh /home/dministrator/WordCard/voice/libs/libpiper_tts.so
```

**依赖检查清单**：
- [ ] Piper 源码已编译 (`build/src/cpp/piper.cpp` 存在)
- [ ] ONNX Runtime 已安装 (`onnxruntime/include/`)
- [ ] espeak-ng 已安装 (`/usr/lib/x86_64-linux-gnu/espeak-ng-data`)
- [ ] 模型文件：`models/zh_CN-huayan-medium.onnx` + `.json`

#### Step 3: 复制模型文件

```bash
# SenseVoice 模型（从 my-agent 复制）
mkdir -p voice/models
cp ~/my-agent/models/sense-voice-small-q6_k.gguf voice/models/

# Piper 模型（从 my-agent 复制）
cp ~/my-agent/models/zh_CN-huayan-medium.onnx voice/models/
cp ~/my-agent/models/zh_CN-huayan-medium.onnx.json voice/models/
cp -r ~/my-agent/models/espeak-ng-data voice/models/

# 验证
ls -lh voice/models/
```

### 12.3 Python 集成

```python
# voice/asr.py
import ctypes
import os
import subprocess
import tempfile
import re

SENSEVOICE_SO = os.path.join(os.path.dirname(__file__), "libs", "libsensevoice.so")
SENSEVOICE_MODEL = os.path.join(os.path.dirname(__file__), "models", "sense-voice-small-q6_k.gguf")

_lib = None
_ctx = None

def _load_library():
    """加载 SenseVoice 共享库（延迟加载，首次调用时初始化）"""
    global _lib
    if _lib is not None:
        return _lib
    
    if not os.path.exists(SENSEVOICE_SO):
        raise FileNotFoundError(
            f"SenseVoice 库不存在: {SENSEVOICE_SO}\n"
            f"请先编译: cd voice/wrappers && make sensevoice"
        )
    
    _lib = ctypes.CDLL(SENSEVOICE_SO)
    
    _lib.sensevoice_load_model.argtypes = [ctypes.c_char_p, ctypes.c_int]
    _lib.sensevoice_load_model.restype = ctypes.c_void_p
    
    _lib.sensevoice_recognize.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
    _lib.sensevoice_recognize.restype = ctypes.c_char_p
    
    _lib.sensevoice_free_text.argtypes = [ctypes.c_char_p]
    _lib.sensevoice_free_text.restype = None
    
    _lib.sensevoice_free_model.argtypes = [ctypes.c_void_p]
    _lib.sensevoice_free_model.restype = None
    
    return _lib

def _convert_to_wav(input_path, output_path):
    """ffmpeg 音频格式转换"""
    cmd = [
        "ffmpeg", "-y", "-i", input_path,
        "-ar", "16000", "-ac", "1",
        "-c:a", "pcm_s16le",
        output_path
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    return result.returncode == 0

def recognize_audio(audio_path):
    """
    识别音频文件，返回文本
    支持格式：amr, wav, mp3, ogg（自动转码为 16kHz WAV）
    """
    global _ctx
    
    if not os.path.exists(audio_path):
        return ""
    
    # 转换为 16kHz WAV
    is_wav = audio_path.lower().endswith(".wav")
    wav_path = audio_path
    temp_wav = None
    
    if not is_wav:
        temp_wav = tempfile.mktemp(suffix=".wav")
        if not _convert_to_wav(audio_path, temp_wav):
            return ""
        wav_path = temp_wav
    
    try:
        lib = _load_library()
        
        # 延迟加载模型（常驻内存）
        if _ctx is None:
            _ctx = lib.sensevoice_load_model(SENSEVOICE_MODEL.encode("utf-8"), 4)
        
        text_ptr = lib.sensevoice_recognize(_ctx, wav_path.encode("utf-8"), 4)
        text = ctypes.string_at(text_ptr).decode("utf-8", errors="ignore")
        lib.sensevoice_free_text(text_ptr)
        
        # 移除 SenseVoice 标签
        text = re.sub(r"<\|[a-z_]+\|>", "", text).strip()
        return text
        
    finally:
        if temp_wav and os.path.exists(temp_wav):
            os.unlink(temp_wav)

def cleanup():
    """释放模型资源"""
    global _ctx
    if _ctx is not None and _lib is not None:
        _lib.sensevoice_free_model(_ctx)
        _ctx = None
```

```python
# voice/tts.py
import ctypes
import os
import time

PIPER_LIB = os.path.join(os.path.dirname(__file__), "libs", "libpiper_tts.so")
PIPER_MODEL = os.path.join(os.path.dirname(__file__), "models", "zh_CN-huayan-medium.onnx")
PIPER_CONFIG = os.path.join(os.path.dirname(__file__), "models", "zh_CN-huayan-medium.onnx.json")
ESPEAK_DATA = os.path.join(os.path.dirname(__file__), "models", "espeak-ng-data")

_lib = None
_voice = None

def _load_library():
    """加载 Piper TTS 共享库"""
    global _lib
    if _lib is not None:
        return _lib
    
    if not os.path.exists(PIPER_LIB):
        raise FileNotFoundError(
            f"Piper 库不存在: {PIPER_LIB}\n"
            f"请先编译: cd voice/wrappers && make piper"
        )
    
    _lib = ctypes.CDLL(PIPER_LIB)
    
    _lib.piper_initialize.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    _lib.piper_initialize.restype = ctypes.c_int
    
    _lib.piper_load_voice.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int64, ctypes.c_int]
    _lib.piper_load_voice.restype = ctypes.c_void_p
    
    _lib.piper_synthesize_to_file.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
    _lib.piper_synthesize_to_file.restype = ctypes.c_int
    
    _lib.piper_free_voice.argtypes = [ctypes.c_void_p]
    _lib.piper_free_voice.restype = None
    
    _lib.piper_terminate.argtypes = []
    _lib.piper_terminate.restype = None
    
    return _lib

def text_to_speech(text, output_path=None):
    """
    文本转语音
    返回 WAV 文件路径
    """
    global _voice
    
    if not text or not text.strip():
        return ""
    
    lib = _load_library()
    
    # 初始化（仅一次）
    if _voice is None:
        lib.piper_initialize(ESPEAK_DATA.encode("utf-8"), None)
        _voice = lib.piper_load_voice(
            PIPER_MODEL.encode("utf-8"),
            PIPER_CONFIG.encode("utf-8"),
            -1, 0
        )
    
    if output_path is None:
        output_path = f"/tmp/wordcard_tts_{int(time.time())}.wav"
    
    result = lib.piper_synthesize_to_file(
        _voice,
        text.strip().encode("utf-8"),
        output_path.encode("utf-8")
    )
    
    return output_path if result == 0 and os.path.exists(output_path) else ""

def cleanup():
    """释放资源"""
    global _voice
    if _voice is not None and _lib is not None:
        _lib.piper_free_voice(_voice)
        _voice = None
    if _lib is not None:
        _lib.piper_terminate()
```

### 12.4 调用流程

```
用户发送语音 (amr/wav/mp3)
    │
    ▼
ffmpeg 转码 → 16kHz WAV
    │
    ▼
SenseVoice (libsensevoice.so) → 文本
    │
    ▼
NLP 理解 → 执行命令（如"开始学习"、"下一个单词"）
    │
    ▼
需要语音回复？
    │
    ├─ 是 → Piper TTS (libpiper_tts.so) → WAV
    │         │
    │         ▼
    │    返回音频文件
    │
    └─ 否 → 返回文本
```

### 12.5 Makefile（voice/wrappers/Makefile）

```makefile
# Voice Wrappers Makefile
# 编译 SenseVoice 和 Piper TTS 的 C++ Wrapper

# 配置
SENSEVOICE_SRC = /home/dministrator/SenseVoice.cpp
PIPER_SRC = /opt/piper-src
OUTPUT_DIR = ../libs

.PHONY: all sensevoice piper clean

all: sensevoice piper

sensevoice:
	@echo "编译 SenseVoice Wrapper..."
	mkdir -p $(OUTPUT_DIR)
	g++ -shared -fPIC -std=c++17 \
	  -I$(SENSEVOICE_SRC) \
	  -I$(SENSEVOICE_SRC)/sense-voice/csrc \
	  -I$(SENSEVOICE_SRC)/build/_deps/ggml-src/include \
	  sensevoice_wrapper.cpp \
	  $(SENSEVOICE_SRC)/build/lib/libsense-voice-core.a \
	  $(SENSEVOICE_SRC)/build/lib/libcommon.a \
	  -L$(SENSEVOICE_SRC)/build/lib -lggml -lggml-base -lggml-cpu \
	  -o $(OUTPUT_DIR)/libsensevoice.so \
	  -lpthread -ldl
	@echo "完成: $(OUTPUT_DIR)/libsensevoice.so"

piper:
	@echo "编译 Piper TTS Wrapper..."
	mkdir -p $(OUTPUT_DIR)
	g++ -shared -fPIC -std=c++17 \
	  -I$(PIPER_SRC)/src/cpp \
	  -I$(PIPER_SRC)/build \
	  -I$(PIPER_SRC)/piper-phonemize/src \
	  -I$(PIPER_SRC)/onnxruntime/include \
	  piper_wrapper.cpp \
	  $(PIPER_SRC)/build/src/cpp/piper.cpp \
	  -L$(PIPER_SRC)/build/lib -lpiper_phonemize -lonnxruntime \
	  -lespeak-ng \
	  -o $(OUTPUT_DIR)/libpiper_tts.so \
	  -lpthread -ldl
	@echo "完成: $(OUTPUT_DIR)/libpiper_tts.so"

clean:
	rm -f $(OUTPUT_DIR)/libsensevoice.so
	rm -f $(OUTPUT_DIR)/libpiper_tts.so
	@echo "已清理"
```

---

## 十三、语音 API 详细设计

### 13.1 ASR 接口（HTTP）

```
POST /api/v1/voice/asr
Content-Type: multipart/form-data
Body: file=@voice.amr

→ {
    "code": 200,
    "data": {
        "text": "开始学习今天的单词",
        "confidence": 0.95,
        "duration_ms": 2300
    }
}
```

**内部处理**：
1. 接收 amr/wav/mp3/ogg
2. ffmpeg 转为 16kHz 单声道 WAV
3. SenseVoice 识别（模型常驻内存，首次调用加载）
4. 移除 `<|zh|>` 等标签，返回纯文本

### 13.2 TTS 接口（HTTP）

```
POST /api/v1/voice/tts
Body: {"text": "solar", "speed": 1.0}

→ {
    "code": 200,
    "data": {
        "audio_url": "/tmp/tts_solar_1699123456.wav",
        "duration_ms": 800,
        "format": "wav"
    }
}
```

**内部处理**：
1. Piper TTS 合成（模型常驻内存）
2. 输出 16-bit PCM WAV
3. 返回文件路径（由 Python 提供 HTTP 下载或上传 OSS）

### 13.3 发音评估接口（HTTP）

```
POST /api/v1/voice/pronunciation
Content-Type: multipart/form-data
Body: file=@user_voice.wav, word="solar"

→ {
    "code": 200,
    "data": {
        "word": "solar",
        "user_text": "solar",           # ASR 识别结果
        "correct": true,                # 是否匹配
        "similarity": 0.92,             # 文本相似度 (0-1)
        "suggestion": "发音准确！"
    }
}
```

**内部处理**：
1. ASR 识别用户语音 → 文本
2. 对比目标单词（忽略大小写、标点）
3. 计算编辑距离相似度
4. 返回评分和建议

### 13.4 语音记忆模式调用示例

```python
# 听写模式
@app.post("/api/v1/study/mode/dictation")
def dictation_mode(vocab_id: int):
    # 1. 获取单词
    word = get_word(vocab_id)
    
    # 2. TTS 播放发音
    audio_path = tts.text_to_speech(word.word)
    
    # 3. 返回题目
    return {
        "mode": "dictation",
        "vocab_id": vocab_id,
        "audio_url": audio_path,
        "hint": word.phonetic,  # 音标提示
        "answer": word.word
    }

# 用户提交答案后
@app.post("/api/v1/study/mode/dictation/submit")
def submit_dictation(vocab_id: int, user_audio: UploadFile):
    # 保存用户录音
    temp_path = save_upload(user_audio)
    
    # ASR 识别
    user_text = asr.recognize_audio(temp_path)
    
    # 对比答案
    word = get_word(vocab_id)
    correct = user_text.lower().strip() == word.word.lower().strip()
    
    # 更新学习记录
    if correct:
        review_word(vocab_id, rating="good")
    
    return {"correct": correct, "user_text": user_text, "answer": word.word}
```

---

## 十四、核心优势

```python
# voice/asr.py (复刻自 ~/my-agent/ding/voice_recognition.py)

import ctypes
import os
import subprocess
import tempfile
import re

# 配置
SENSEVOICE_SO = "libs/libsensevoice.so"
SENSEVOICE_MODEL = "models/sense-voice-small-q6_k.gguf"

_lib = None
_ctx = None

def _load_library():
    """加载 SenseVoice 共享库"""
    global _lib
    if _lib is not None:
        return _lib
    
    _lib = ctypes.CDLL(SENSEVOICE_SO)
    
    _lib.sensevoice_load_model.argtypes = [ctypes.c_char_p, ctypes.c_int]
    _lib.sensevoice_load_model.restype = ctypes.c_void_p
    
    _lib.sensevoice_recognize.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
    _lib.sensevoice_recognize.restype = ctypes.c_char_p
    
    _lib.sensevoice_free_model.argtypes = [ctypes.c_void_p]
    _lib.sensevoice_free_model.restype = None
    
    return _lib

def recognize_audio(audio_path: str) -> str:
    """识别音频文件，返回文本"""
    # 1. ffmpeg 转为 16kHz WAV
    # 2. SenseVoice 识别
    # 3. 移除标签，返回纯文本
    pass
```

### 12.2 TTS 接口

```python
# voice/tts.py (复刻自 ~/my-agent/ding/text_to_speech.py)

import ctypes
import os
import time

# 配置
PIPER_LIB = "libs/libpiper_tts.so"
PIPER_MODEL = "models/zh_CN-huayan-medium.onnx"
PIPER_CONFIG = "models/zh_CN-huayan-medium.onnx.json"
ESPEAK_DATA = "models/espeak-ng-data"

_lib = None
_voice = None

def text_to_speech(text: str, output_path: str = None) -> str:
    """文本转语音，返回 WAV 文件路径"""
    # 1. 加载 libpiper_tts.so
    # 2. 初始化 Piper
    # 3. 合成音频
    # 4. 返回文件路径
    pass
```

### 12.3 发音评估

```python
# voice/pronunciation.py

from .asr import recognize_audio
from .tts import text_to_speech

def evaluate_pronunciation(user_audio_path: str, target_word: str) -> dict:
    """
    评估用户发音
    
    流程:
    1. ASR 识别用户语音 → user_text
    2. 对比 user_text 和 target_word
    3. 计算文本相似度
    4. 返回评分
    """
    user_text = recognize_audio(user_audio_path)
    
    # 简单文本匹配（可扩展为音素级对比）
    similarity = calculate_similarity(user_text.lower(), target_word.lower())
    
    return {
        "word": target_word,
        "user_text": user_text,
        "correct": similarity > 0.8,
        "similarity": similarity,
        "suggestion": "发音准确！" if similarity > 0.8 else "请再试一次"
    }
```

---

## 十三、核心优势

1. **目标驱动**：不是为了背单词而背单词，是为了读懂一本书
2. **语境记忆**：每个词都有原文例句，不是孤立的
3. **渐进解锁**：像游戏关卡一样，掌握一章解锁一章
4. **科学记忆**：SM-2 间隔重复，8 种模式多维度强化
5. **语音交互**：支持语音输入/输出，解放双手
6. **极简部署**：C + Python，单文件数据库，一键启动
