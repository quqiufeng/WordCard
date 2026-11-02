# WordCard 应用方向

> 真实待办以此文件 + `gui.md` 第十五节为准。
> 书籍清单统一放 `books.txt`（约 6923 本），**不要**在本文件重复堆书名。

## 已完成

- **v4.0**：C 核心 SM-2 / 哈希索引、电子书导入、CLI/API、卡片图片
- **v4.1**：Flutter/Yaru 桌面应用、记忆数据、任务、听写、图片 OCR、Kami 排版
- **v4.2**：双语阅读器、书架、段间对照、按需 LLM 翻译、点词查词/加入任务
- **v4.3**：英语口语外教、SenseVoice ASR、Kokoro TTS、独立 `wordcard-brain`

## 当前优先

- [ ] 卡片图片导出（Flutter `RepaintBoundary` → PNG）
- [ ] 深色模式调色板（Kami 暖米 ↔ 暖深）
- [ ] 「中国色 / 系统色」主题切换设置项
- [ ] 字体子集化瘦身（Maple + 仓耳今楷体积较大）
- [ ] 每日新词上限设置（当前 10；每周词表一次练完需调大）
- [ ] 系统托盘常驻（需绕过 Flutter 隐藏窗口的 SEGV）
- [ ] Snap 打包与 CI

## 体验 / 内容

- [ ] 有声书：章节 Markdown → Kokoro TTS 合成 `.m4b`
- [ ] 阅读+复习闭环：读原版书 → 标记生词 → 自动加入复习队列
- [ ] 书籍推荐：按分类/难度/词汇量推荐，数据源 `books.txt`
- [ ] 词汇量测试：从书中抽样词汇，评估用户水平
- [ ] 学习进度追踪：每本书的阅读进度与掌握度

## 自动化 / 质量

- [ ] 自动化 API：事件订阅、复习评分质量、卡片导出
- [ ] 视觉回归：关键页面截图基线与差异检查
- [ ] ABI 校验：`src/wordcard.h` ↔ `engine.py` ↔ Dart `ffi/structs.dart` 自动比对
- [x] 清理文档版本漂移（README / design / gui / automation）

## 书籍

- 目录：`books.txt`
- 已解析可读：`/opt/books/<slug>/chapters/`
- 阅读器通过 `BOOK_MD_ROOT` 覆盖书库根目录
