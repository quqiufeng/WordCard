# WordCard 开发进度

> 基于 design.md 的详细任务跟踪文档
> 每次完成一个功能后立即更新状态

---

## 项目总览

**核心目标**：构建基于 C 语言内存数据结构 + Python FastAPI 的单词记忆系统
**核心卖点**：记忆曲线追踪 + 多维度掌握度 + 智能推荐算法
**数据持久化**：结构体直写磁盘 bin 文件，启动时直接载入内存

---

## 已完成的里程碑

### ✅ 阶段 0: 项目初始化与设计
- [x] 编写 design.md 完整架构文档 (1741 行)
- [x] 确定 7 种核心数据结构
- [x] 确定文件格式 v2 (magic: "WCD\x02")
- [x] 确定多维度掌握度算法 (6维度 + SM-2)
- [x] 集成现有组件：llm.py, card.py, voice wrappers
- [x] 更新 README.md

### ✅ 阶段 1: C 核心层基础 (P0)
- [x] 1.1 创建 `src/wordcard.h` 头文件（所有结构体、枚举、API声明）
- [x] 1.2 数据库初始化与内存管理（`wc_db_init/free`，动态扩容，线程锁）
- [x] 1.3 磁盘文件格式加载与保存（结构体直写，`wc_load_db/save_db`，原子写入）
- [x] 1.4 运行时哈希索引（word/id/source/user/mastery 五种哈希表）

### ✅ 阶段 2: SM-2 算法与掌握度系统 (P0)
- [x] 2.1 SM-2 间隔重复算法（标准实现，含单元测试验证）
- [x] 2.2 多维度掌握度更新（6维度滑动平均 + 加权综合计算）
- [x] 2.3 掌握度查询接口（`wc_get_due_words`, `wc_get_new_words`）

### ✅ 阶段 3: 智能推荐算法 (P0)
- [x] 3.1 学习模式推荐引擎（7条规则，覆盖所有场景）
- [x] 3.2 今日学习队列生成（复习优先 + 新词补充）

### ✅ 阶段 4: Python API 层 (P0) - 基础完成
- [x] 4.1 ctypes FFI 绑定（`api.py` 中定义所有结构体和函数签名）
- [x] 4.2 FastAPI HTTP 服务（用户/词汇/学习/复习等端点）
- [x] 4.3 异步保存机制（后台线程每60秒自动保存 + 退出时保存）

### ✅ 阶段 5: 语音系统集成 (P1) - 框架完成
- [x] 5.1 封装 SenseVoice (ASR) 和 Piper (TTS) 的 `.so` 调用
- [x] 5.2 发音评分算法（对比用户读音和标准音的相似度）
- [ ] 5.3 FastAPI 语音端点（待集成到 api.py）

### ✅ 阶段 6: 数据导入工具 (P1) - 基础完成
- [x] 6.1 `import_article.py` - 读取 res/*.txt，提取高频词汇，写入 C DB
- [ ] 6.2 PDF 导入（PyMuPDF + 词汇频率分析）
- [ ] 6.3 词表导入（CET-4/6/IELTS）

### ✅ 阶段 7: 单元测试 (P1)
- [x] 7.1 C 层单元测试（`src/test_sm2.c`，7个测试全部通过）
- [ ] 7.2 性能测试（10万词加载 < 1秒）
- [ ] 7.3 集成测试（端到端用户流程）

---

## 当前进度摘要

| 阶段 | 任务数 | 已完成 | 进行中 | 待开始 |
|------|--------|--------|--------|--------|
| 阶段 0: 设计 | 1 | 1 | 0 | 0 |
| 阶段 1: C核心基础 | 4 | 4 | 0 | 0 |
| 阶段 2: SM-2与掌握度 | 3 | 3 | 0 | 0 |
| 阶段 3: 智能推荐 | 2 | 2 | 0 | 0 |
| 阶段 4: Python API | 3 | 3 | 0 | 0 |
| 阶段 5: 语音系统 | 2 | 1 | 0 | 1 |
| 阶段 6: 数据导入 | 3 | 1 | 0 | 2 |
| 阶段 7: 测试优化 | 3 | 1 | 0 | 2 |
| **总计** | **21** | **16** | **0** | **5** |

**当前完成度: 76%**

---

## 核心架构验证

### ✅ 数据结构直写磁盘验证
```bash
$ cd src && ./test_sm2
  [main] db_save_load ... OK
# 验证：数据库创建 → 添加数据 → 保存 → 加载 → 数据完整恢复
# 文件头 64 字节，魔数 "WCD\x02"，版本 2
```

### ✅ SM-2 记忆曲线算法
```bash
  [main] sm2_algorithm ... OK
# 验证：新词→1天→6天→间隔增长，忘记→重置，与 Anki 行为一致
```

### ✅ 智能推荐验证
```bash
  [main] recommend_mode ... OK
# 验证：新词→闪卡，拼写差→拼写模式，全面掌握→速闪
```

### ✅ 文章导入验证
```bash
$ python import_article.py
Importing: The Solar System: Our Cosmic Neighborhood
Found 189 unique words, top 50 selected
Import complete: 30 words added
```

---

## 快速开始

### 编译 C 核心库
```bash
cd src
make clean && make
```

### 运行 C 单元测试
```bash
cd src
./test_sm2
# 预期：7 tests passed, 0 failed
```

### 导入文章
```bash
python import_article.py --all  # 导入所有 res/*.txt
# 或
python import_article.py res/solar_system.txt  # 导入单篇
```

### 启动 HTTP API 服务
```bash
python api.py
# 服务启动后访问 http://localhost:8000/docs 查看 API 文档
```

### API 测试示例
```bash
# 注册用户
curl -X POST http://localhost:8000/api/v1/user/register \
  -H "Content-Type: application/json" \
  -d '{"dingtalk_uid": "user001", "name": "TestUser"}'

# 添加单词
curl -X POST http://localhost:8000/api/v1/vocab \
  -H "Content-Type: application/json" \
  -d '{"word": "hello", "meaning": "你好"}'

# 获取今日队列
curl http://localhost:8000/api/v1/user/1/daily-queue

# 提交复习
curl -X POST http://localhost:8000/api/v1/study/review \
  -H "Content-Type: application/json" \
  -d '{"user_id": 1, "vocab_id": 1, "quality": 4, "dimension": "r", "correct": true}'
```

---

## 项目文件清单

| 文件 | 说明 | 状态 |
|------|------|------|
| `design.md` | 完整架构设计文档 | ✅ |
| `src/wordcard.h` | C 头文件（数据结构 + API声明） | ✅ |
| `src/wordcard.c` | C 核心库（数据库 + SM-2 + IO + 哈希索引） | ✅ |
| `src/modes.c` | 智能推荐算法 | ✅ |
| `src/test_sm2.c` | C 单元测试 | ✅ |
| `src/Makefile` | 编译脚本 | ✅ |
| `api.py` | Python FastAPI + ctypes FFI 绑定 | ✅ |
| `import_article.py` | 文章导入工具 | ✅ |
| `voice/__init__.py` | 语音系统集成（ASR/TTS/评分） | ✅ |
| `llm.py` | LLM 翻译引擎（已有） | ✅ |
| `card.py` | 卡片渲染（已有） | ✅ |
| `task.md` | 开发进度跟踪 | ✅ |

---

## 下一步行动建议

当前核心系统已经可用，建议按以下优先级继续：

1. **P0（今天）**: 启动 `python api.py`，用浏览器打开 `http://localhost:8000/docs` 测试 API
2. **P1（本周）**: 将语音端点集成到 `api.py`（`/api/v1/voice/tts`, `/api/v1/voice/asr`）
3. **P1（本周）**: 实现 PDF 导入（`import_pdf.py`，PyMuPDF）
4. **P2（下周）**: 集成钉钉机器人回调，实现完整的推送-学习-反馈闭环
5. **P2（下周）**: 添加更多词表（CET-4/6, IELTS）

---

*最后更新: 2026-05-14*
*核心系统完成度: 76%*
