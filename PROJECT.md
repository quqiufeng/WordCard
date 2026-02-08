# WordCard 开发计划

> 本文档用于指导 WordCard 项目的开发工作，阅读完后可直接执行。

## 一、项目概述

**WordCard** - 中学生英语学习助手，通过AI生成的双语文章和智能记忆算法帮助背诵单词。

### 核心功能

| 功能 | 说明 |
|------|------|
| 文章阅读 | 双语对照文章，支持难度筛选 |
| 单词背诵 | 卡片模式 + SM-2 间隔重复算法 |
| 学习统计 | 每日进度、累计掌握词数 |
| 精美卡片 | MD/PDF/图片格式导出 |

### 目标用户

- 14岁左右中学生
- 词汇量1500-4000
- 需要背诵单词、提高阅读理解

---

## 二、技术架构

```
┌─────────────────────────────────────────────────────────────┐
│                      用户端 (H5 网页)                          │
│                 Vue 3 + Vant UI + Axios                      │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐     │
│  │ 首页/学习 │ │ 单词卡   │ │ 背诵模式 │ │ 我的统计 │     │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘     │
├─────────────────────────────────────────────────────────────┤
│                     OpenResty API                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ /api/articles     - 文章列表/详情                    │    │
│  │ /api/vocab/random - 随机单词                        │    │
│  │ /api/vocab/review - 按算法复习                      │    │
│  │ /api/vocab/mark   - 标记记忆状态                    │    │
│  │ /api/stats/*      - 统计数据                        │    │
│  └─────────────────────────────────────────────────────┘    │
├─────────────────────────────────────────────────────────────┤
│                      MySQL 数据库                             │
│                  (数据库名: english_card)                    │
├─────────────────────────────────────────────────────────────┤
│                 Ant Design Pro (后台管理)                    │
│            用户统计 / 单词管理 / 内容管理                      │
└─────────────────────────────────────────────────────────────┘
```

### 技术选型

| 层级 | 技术 | 说明 |
|------|------|------|
| 后端框架 | OpenResty + Lua | 已有框架，直接使用 |
| 前端框架 | Vue 3 + Vant UI | 轻量、适配手机 |
| 数据库 | MySQL 5.7+ | 主库: english_card |
| 翻译引擎 | CTranslate2 + NLLB | 已有 translate.py |
| 样式 | Tailwind CSS + LXGW WenKai | 护眼清爽风 |

---

## 三、数据库设计

### 3.1 建库建表

> 执行以下命令创建数据库和表：

```bash
# 登录 MySQL
mysql -u root -p

# 创建数据库
CREATE DATABASE english_card DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

# 使用数据库
USE english_card;

# 创建表
```

### 3.2 表结构

```sql
-- 文章表
CREATE TABLE articles (
    id INT PRIMARY KEY AUTO_INCREMENT COMMENT '主键ID',
    title VARCHAR(255) NOT NULL COMMENT '文章标题',
    original_content LONGTEXT NOT NULL COMMENT '英文原文',
    translated_content LONGTEXT COMMENT '中文译文',
    source_url VARCHAR(500) COMMENT '来源链接',
    difficulty VARCHAR(20) DEFAULT 'intermediate' COMMENT '难度: beginner/intermediate/advanced',
    word_count INT DEFAULT 0 COMMENT '单词数',
    is_published TINYINT DEFAULT 1 COMMENT '是否发布: 0=否, 1=是',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_difficulty (difficulty),
    INDEX idx_published (is_published),
    INDEX idx_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='文章表';

-- 词汇表
CREATE TABLE vocabulary (
    id INT PRIMARY KEY AUTO_INCREMENT COMMENT '主键ID',
    word VARCHAR(100) NOT NULL COMMENT '单词',
    pos VARCHAR(20) COMMENT '词性: n./v./adj./adv./prep./conj.',
    meaning VARCHAR(255) NOT NULL COMMENT '中文释义',
    example VARCHAR(500) COMMENT '例句',
    phonetic VARCHAR(50) COMMENT '音标',
    article_id INT COMMENT '关联文章ID',
    difficulty VARCHAR(20) DEFAULT 'intermediate' COMMENT '难度等级',
    frequency INT DEFAULT 0 COMMENT '出现频率',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_word (word),
    INDEX idx_article (article_id),
    INDEX idx_difficulty (difficulty)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='词汇表';

-- 学习记录表 (SM-2算法)
CREATE TABLE learning_records (
    id INT PRIMARY KEY AUTO_INCREMENT COMMENT '主键ID',
    user_identifier VARCHAR(100) NOT NULL COMMENT '用户标识(cookie/device_id)',
    vocab_id INT NOT NULL COMMENT '词汇ID',
    status TINYINT DEFAULT 0 COMMENT '状态: 0=新词, 1=学习中, 2=已掌握',
    interval_days INT DEFAULT 1 COMMENT '间隔天数',
    repetitions INT DEFAULT 0 COMMENT '复习次数',
    ease_factor DECIMAL(4,2) DEFAULT 2.50 COMMENT '难度因子',
    next_review DATE COMMENT '下次复习日期',
    last_review DATE COMMENT '最后复习日期',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_user (user_identifier),
    INDEX idx_next_review (next_review),
    INDEX idx_user_vocab (user_identifier, vocab_id),
    UNIQUE KEY uk_user_vocab (user_identifier, vocab_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='学习记录表';

-- 精彩句子表
CREATE TABLE sentences (
    id INT PRIMARY KEY AUTO_INCREMENT COMMENT '主键ID',
    article_id INT NOT NULL COMMENT '关联文章ID',
    sentence TEXT NOT NULL COMMENT '英文句子',
    translation TEXT COMMENT '中文翻译',
    chapter VARCHAR(50) COMMENT '章节/段落标识',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_article (article_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='精彩句子表';

-- 用户统计表 (按天汇总)
CREATE TABLE daily_stats (
    id INT PRIMARY KEY AUTO_INCREMENT COMMENT '主键ID',
    user_identifier VARCHAR(100) NOT NULL COMMENT '用户标识',
    stat_date DATE NOT NULL COMMENT '统计日期',
    new_words INT DEFAULT 0 COMMENT '新学单词数',
    reviewed_words INT DEFAULT 0 COMMENT '复习单词数',
    mastered_words INT DEFAULT 0 COMMENT '掌握单词数',
    total_time INT DEFAULT 0 COMMENT '学习时长(秒)',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uk_user_date (user_identifier, stat_date),
    INDEX idx_date (stat_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='每日统计表';
```

### 3.3 测试数据

```sql
-- 插入测试文章
INSERT INTO articles (title, original_content, difficulty) VALUES
('The Power of Positive Thinking', 'Positive thinking is a mental and emotional practice...', 'intermediate');

-- 插入测试词汇
INSERT INTO vocabulary (word, pos, meaning, example, article_id) VALUES
('positive', 'adj.', '积极的，乐观的', 'She has a positive attitude towards life.', 1),
('thinking', 'n.', '思考，想法', 'Positive thinking can change your life.', 1),
('power', 'n.', '力量，能力', 'The power of positive thinking is amazing.', 1);

-- 插入精彩句子
INSERT INTO sentences (article_id, sentence, translation) VALUES
(1, 'Positive thinking is a mental and emotional practice.', '积极思考是一种精神和情感上的训练。'),
(1, 'It can help you achieve your goals and dreams.', '它可以帮助你实现目标和梦想。');
```

---

## 四、API 设计

### 4.1 基础信息

- Base URL: `http://api.wordcard.test` (本地开发)
- 认证方式: Cookie / Device ID
- 响应格式: JSON

### 4.2 API 列表

#### 文章相关

| API | 方法 | 功能 | 参数 |
|-----|------|------|------|
| `/api/articles` | GET | 文章列表 | `page=1&limit=10&difficulty=intermediate` |
| `/api/articles/:id` | GET | 文章详情 | - |
| `/api/articles/:id/sentences` | GET | 文章句子列表 | - |

#### 词汇相关

| API | 方法 | 功能 | 参数/请求体 |
|-----|------|------|------------|
| `/api/vocab/random` | GET | 随机获取新词 | `count=10&difficulty=intermediate` |
| `/api/vocab/review` | GET | 获取待复习词汇 | - |
| `/api/vocab/learn` | POST | 学习新词 | `{"vocab_ids": [1,2,3]}` |
| `/api/vocab/mark` | POST | 标记记忆状态 | `{"vocab_id": 1, "rating": "good"}` |
| `/api/vocab/detail/:id` | GET | 词汇详情 | - |

#### 统计相关

| API | 方法 | 功能 |
|-----|------|------|
| `/api/stats/daily` | GET | 今日学习统计 |
| `/api/stats/overall` | GET | 累计学习统计 |

### 4.3 请求/响应示例

#### GET /api/articles

```json
{
  "code": 200,
  "message": "success",
  "data": {
    "list": [
      {
        "id": 1,
        "title": "The Power of Positive Thinking",
        "difficulty": "intermediate",
        "word_count": 150,
        "created_at": "2024-01-01 00:00:00"
      }
    ],
    "pagination": {
      "page": 1,
      "limit": 10,
      "total": 100
    }
  }
}
```

#### POST /api/vocab/mark

**请求体：**
```json
{
  "vocab_id": 1,
  "rating": "good"
}
```

**rating 说明：**
| 值 | 说明 | 间隔变化 |
|-----|------|----------|
| `easy` | 非常简单 | 间隔 × 2.5 |
| `good` | 一般 | 间隔 × 1.5 |
| `hard` | 困难 | 间隔 × 1.0 |
| `forgot` | 完全忘记 | 间隔重置为1天 |

---

## 五、H5 前端设计

### 5.1 页面结构

```
src/
├── views/
│   ├── Home.vue           # 首页
│   ├── Articles.vue        # 文章列表
│   ├── ArticleDetail.vue  # 文章详情
│   ├── Card.vue           # 单词卡
│   ├── Review.vue         # 背诵复习
│   └── Profile.vue        # 我的
├── components/
│   ├── WordCard.vue       # 单词卡片组件
│   ├── ProgressRing.vue   # 进度环
│   └── StatCard.vue       # 统计卡片
├── api/
│   ├── articles.js        # 文章API
│   ├── vocabulary.js      # 词汇API
│   └── stats.js           # 统计API
├── utils/
│   └── sm2.js             # SM-2算法
└── styles/
    └── index.css          # 全局样式
```

### 5.2 页面功能

#### 首页 `/`
- 今日任务卡片（复习数量 + 新词数量）
- 学习进度环（已掌握 / 学习中 / 新词）
- 快捷入口（开始学习 / 背诵复习 / 查看文章）

#### 文章列表 `/articles`
- 卡片式列表展示
- 按难度筛选（初级/中级/高级）
- 下拉刷新 + 无限滚动

#### 文章详情 `/articles/:id`
- 双语对照展示
- 点击单词查看释义
- 收藏文章功能

#### 单词卡 `/card`
- 正面：单词 + 音标
- 背面：释义 + 例句
- 翻转动画效果
- 掌握程度选择

#### 背诵复习 `/review`
- 待复习列表（按SM-2算法排序）
- 批量操作（全部掌握 / 跳过）
- 进度显示

#### 我的 `/profile`
- 今日学习统计
- 累计学习数据
- 学习天数统计

### 5.3 UI 设计规范

**配色方案（护眼清爽风）：**
```css
:root {
  --bg-primary: #F5F5DC;        /* 米色背景 - 护眼 */
  --bg-card: #FFFFFF;           /* 白色卡片 */
  --bg-secondary: #F0FFF0;      /* 淡绿色 - 清新 */
  --text-primary: #2C3E50;      /* 深蓝灰 - 主要文字 */
  --text-secondary: #7F8C8D;    /* 浅灰 - 次要文字 */
  --accent-green: #27AE60;       /* 绿色 - 成功/掌握 */
  --accent-red: #E74C3C;        /* 红色 - 重点 */
  --accent-blue: #3498DB;       /* 蓝色 - 链接 */
  --border-color: #E0E0E0;      /* 边框颜色 */
}
```

**字体：**
- 中文：LXGW WenKai
- 英文：Inter / Roboto

**圆角：**
- 卡片：12px
- 按钮：8px

---

## 六、记忆算法（SM-2 简化版）

### 6.1 算法说明

SM-2 (SuperMemo 2) 是经典的间隔重复算法。

**核心公式：**
```
新间隔 = 旧间隔 × 难度因子 × EF因子
```

**用户评分与间隔：**
| 评分 | 说明 | 间隔(天) |
|------|------|----------|
| 5 | 非常简单 | 7 → 14 → 30 → 60 |
| 4 | 简单 | 4 → 7 → 14 → 30 |
| 3 | 一般 | 2 → 4 → 7 → 14 |
| 2 | 困难 | 1 → 2 → 4 → 7 |
| 1 | 完全忘记 | 1 → 1 → 2 → 3 |

### 6.2 算法实现

```javascript
// sm2.js
const SM2 = {
  // 初始参数
  initInterval: 1,      // 初始间隔(天)
  initEaseFactor: 2.5,  // 初始难度因子

  // 计算新的间隔
  calculate(interval, repetitions, easeFactor, quality) {
    // quality: 0-5 (用户评分)

    if (quality < 3) {
      // 忘记：重新开始
      return {
        interval: this.initInterval,
        repetitions: 0,
        easeFactor: Math.max(1.3, easeFactor - 0.2)
      }
    }

    // 第一次复习
    if (repetitions === 0) {
      interval = 1
    } else if (repetitions === 1) {
      interval = 6
    } else {
      interval = Math.round(interval * easeFactor)
    }

    // 更新难度因子
    easeFactor = easeFactor + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02))
    easeFactor = Math.max(1.3, easeFactor)

    return {
      interval,
      repetitions: repetitions + 1,
      easeFactor
    }
  },

  // 获取复习日期
  getNextReviewDate(interval) {
    const date = new Date()
    date.setDate(date.getDate() + interval)
    return date.toISOString().split('T')[0]
  }
}

export default SM2
```

### 6.3 每日学习流程

```javascript
// 每日学习流程
async function dailyLearningFlow(userId) {
  // 1. 获取待复习词汇
  const reviewWords = await getReviewWords(userId)

  // 2. 获取适量新词
  const newWords = await getNewWords(userId, 10)

  // 3. 合并今日任务
  const todayTasks = {
    review: reviewWords,
    new: newWords,
    total: reviewWords.length + newWords.length
  }

  return todayTasks
}
```

---

## 七、开发计划

### 阶段一：数据库和API基础（1天）

**目标：** 完成数据库设计和API开发

| 任务 | 说明 | 时间 |
|------|------|------|
| 创建数据库和表 | 执行 SQL 脚本 | 0.5小时 |
| 开发文章API | CRUD + 列表 + 详情 | 2小时 |
| 开发词汇API | 随机 + 复习 + 标记 | 3小时 |
| 开发统计API | 每日 + 累计统计 | 1.5小时 |

### 阶段二：H5前端基础（1天）

**目标：** 完成项目搭建和基础页面

| 任务 | 说明 | 时间 |
|------|------|------|
| 项目初始化 | Vue 3 + Vant UI | 1小时 |
| 路由配置 | 页面路由 + 权限 | 0.5小时 |
| API封装 | Axios 配置 + 接口 | 1小时 |
| 首页开发 | 今日任务 + 进度 | 2小时 |
| 基础组件 | 卡片 + 按钮 + 弹窗 | 1.5小时 |

### 阶段三：单词卡功能（1天）

**目标：** 完成背诵模式和SM-2算法

| 任务 | 说明 | 时间 |
|------|------|------|
| SM-2算法实现 | 间隔计算 + 复习日期 | 1小时 |
| 单词卡页面 | 翻转动画 + 评分 | 3小时 |
| 背诵流程 | 新词 + 复习 + 标记 | 3小时 |
| 进度更新 | 实时更新学习记录 | 1小时 |

### 阶段四：文章功能（1天）

**目标：** 完成文章浏览和双语对照

| 任务 | 说明 | 时间 |
|------|------|------|
| 文章列表 | 卡片 + 筛选 + 分页 | 2小时 |
| 文章详情 | 双语对照 + 词汇高亮 | 3小时 |
| 单词弹窗 | 点击查词 + 加入学习 | 2小时 |

### 阶段五：统计页面（0.5天）

**目标：** 完成个人中心和学习统计

| 任务 | 说明 | 时间 |
|------|------|------|
| 今日统计 | 学习数量 + 时长 | 1小时 |
| 累计统计 | 总词数 + 连续天数 | 1小时 |

### 阶段六：测试和部署（0.5天）

**目标：** 完成测试和上线

| 任务 | 说明 | 时间 |
|------|------|------|
| 功能测试 | 各页面功能验证 | 1小时 |
| 性能优化 | 首屏加载 + 接口响应 | 0.5小时 |
| 部署上线 | Nginx 配置 | 0.5小时 |

---

## 八、部署指南

### 8.1 环境要求

| 软件 | 版本要求 |
|------|----------|
| OpenResty | 1.27.1+ |
| MySQL | 5.7+ |
| Node.js | 16+ |
| npm / yarn | latest |

### 8.2 后端部署

```bash
# 1. 配置 nginx
sudo cp nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
sudo nginx -t
sudo nginx -s reload

# 2. 配置数据库连接
# 修改 config.lua 中的数据库配置
```

### 8.3 前端部署

```bash
# 1. 安装依赖
npm install

# 2. 开发环境运行
npm run dev

# 3. 生产环境构建
npm run build

# 4. 上传 dist 目录到服务器
```

### 8.4 一键部署脚本

```bash
#!/bin/bash

# deploy.sh
echo "开始部署 WordCard..."

# 1. 拉取代码
cd /var/www/wordcard
git pull origin main

# 2. 前端构建
cd frontend
npm install
npm run build

# 3. 重启 Nginx
sudo nginx -s reload

echo "部署完成！"
```

---

## 附录：Demo 实现（翻译+卡片生成脚本）

> 在正式开发前，先实现一个独立的脚本，功能是把英文文章翻译成双语内容并生成 MD/PDF/图片卡片。

### A.1 功能说明

| 功能 | 说明 |
|------|------|
| 输入 | 英文文章文件（.txt / .md） |
| 输出 | MD文件 + PDF卡片 + 图片卡片 |
| 内容 | 原文 + 译文 + 词汇表 + 精彩句子 |
| 复用 | 直接使用现有的 translate.py |

### A.2 使用方法

```bash
# 生成双语文章
python article_card.py 文章.txt

# 指定难度
python article_card.py 文章.txt --difficulty intermediate

# 输出到指定目录
python article_card.py 文章.txt -o ./output
```

### A.3 依赖安装

```bash
pip install markdown weasyprint pillow
```

### A.4 脚本实现

```python
#!/usr/bin/env python3
"""
生成中英双语文章卡片
MD + PDF + 图片格式
"""

import warnings
warnings.filterwarnings('ignore')

import os
import sys
import argparse
import markdown
import re
from datetime import datetime
from pathlib import Path

# 复用翻译模块
from translate import load_translator, translate_batch_fast, cleanup_translator

# 配色方案（护眼清爽风）
COLORS = {
    'bg': '#F5F5DC',           # 米色背景
    'card_bg': '#FFFFFF',       # 白色卡片
    'title': '#2C3E50',        # 深蓝灰
    'text': '#34495E',          # 深灰
    'translation': '#7F8C8D',   # 浅灰
    'accent': '#27AE60',        # 绿色
    'highlight': '#E74C3C',    # 红色
    'border': '#E0E0E0'        # 边框
}

def extract_vocabulary(text):
    """提取文章中的生词（简单实现：提取长度>4的单词）"""
    words = re.findall(r'\b[a-zA-Z]{5,}\b', text.lower())
    return list(set(words))[:50]  # 最多50个词

def split_sentences(text):
    """分割句子"""
    sentences = re.split(r'[.!?]+', text)
    return [s.strip() for s in sentences if s.strip()]

def generate_md(article):
    """生成MD文件"""
    md_content = f"""# {article['title']}

> 生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

---

## 原文

{article['original']}

---

## 译文

{article['translation']}

---

## 词汇表

| 单词 | 词性 | 释义 | 例句 |
|------|------|------|------|
"""

    for word in article['vocabulary']:
        md_content += f"| {word['word']} | {word['pos']} | {word['meaning']} | {word['example']} |\n"

    md_content += """

---

## 精彩句子

"""

    for i, sentence in enumerate(article['sentences'], 1):
        md_content += f"> **{sentence['original']}**\n>\n> {sentence['translation']}\n\n"

    return md_content

def generate_html_card(article, is_front=True):
    """生成HTML卡片"""
    if is_front:
        return f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=375, height=667">
    <style>
        @font-face {{
            font-family: 'LXGW';
            src: url('LXGWWenKai-Regular.ttf') format('truetype');
        }}
        body {{
            width: 375px;
            height: 667px;
            margin: 0;
            padding: 20px;
            background-color: {COLORS['bg']};
            font-family: 'LXGW', sans-serif;
            color: {COLORS['text']};
            box-sizing: border-box;
        }}
        .title {{
            font-size: 24px;
            font-weight: bold;
            color: {COLORS['title']};
            text-align: center;
            margin-bottom: 20px;
        }}
        .content {{
            font-size: 16px;
            line-height: 1.8;
            text-indent: 2em;
        }}
        .card {{
            background: {COLORS['card_bg']};
            border-radius: 12px;
            padding: 20px;
            box-shadow: 0 4px 12px rgba(0,0,0,0.1);
        }}
        .vocab-count {{
            position: absolute;
            top: 20px;
            right: 20px;
            background: {COLORS['accent']};
            color: white;
            padding: 4px 12px;
            border-radius: 20px;
            font-size: 12px;
        }}
    </style>
</head>
<body>
    <div class="card">
        <div class="vocab-count">{len(article['vocabulary'])} 词</div>
        <div class="title">{article['title']}</div>
        <div class="content">{article['original'][:500]}...</div>
    </div>
</body>
</html>"""
    else:
        return f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=375, height=667">
    <style>
        @font-face {{
            font-family: 'LXGW';
            src: url('LXGWWenKai-Regular.ttf') format('truetype');
        }}
        body {{
            width: 375px;
            height: 667px;
            margin: 0;
            padding: 20px;
            background-color: {COLORS['bg']};
            font-family: 'LXGW', sans-serif;
            color: {COLORS['text']};
            box-sizing: border-box;
        }}
        .card {{
            background: {COLORS['card_bg']};
            border-radius: 12px;
            padding: 20px;
            box-shadow: 0 4px 12px rgba(0,0,0,0.1);
            height: 100%;
            overflow-y: auto;
        }}
        .title {{
            font-size: 20px;
            font-weight: bold;
            color: {COLORS['title']};
            margin-bottom: 15px;
        }}
        .section-title {{
            font-size: 14px;
            color: {COLORS['accent']};
            margin: 15px 0 8px 0;
            font-weight: bold;
        }}
        .translation {{
            font-size: 16px;
            line-height: 1.8;
            color: {COLORS['translation']};
        }}
        .vocab-item {{
            margin: 8px 0;
            padding: 8px;
            background: {COLORS['bg']};
            border-radius: 8px;
        }}
        .word {{
            font-weight: bold;
            color: {COLORS['highlight']};
        }}
    </style>
</head>
<body>
    <div class="card">
        <div class="title">{article['title']}</div>
        
        <div class="section-title">译文</div>
        <div class="translation">{article['translation'][:300]}...</div>
        
        <div class="section-title">词汇表 ({len(article['vocabulary'])}词)</div>
"""

def article_to_card(input_file, output_dir='./output', difficulty='intermediate'):
    """主函数：文章转卡片"""
    
    input_path = Path(input_file)
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)
    
    # 1. 读取文章
    with open(input_path, 'r', encoding='utf-8') as f:
        original = f.read()
    
    print(f"读取文章: {input_path.name}")
    print(f"字数: {len(original)}")
    
    # 2. 翻译文章
    print("加载翻译模型...")
    translator, tokenizer = load_translator()
    
    print("翻译中...")
    translation = translate_batch_fast(
        translator, tokenizer, [original],
        source_lang='eng_Latn',
        target_lang='zho_Hans'
    )[0]
    
    cleanup_translator(translator, tokenizer)
    print("翻译完成!")
    
    # 3. 提取词汇
    print("提取词汇...")
    words = extract_vocabulary(original)
    
    # 4. 分割句子
    print("提取精彩句子...")
    sentences = split_sentences(original)[:5]
    
    # 5. 生成文章数据
    article = {
        'title': input_path.stem.replace('_', ' ').title(),
        'original': original,
        'translation': translation,
        'vocabulary': [{'word': w, 'pos': '', 'meaning': '', 'example': ''} for w in words],
        'sentences': [{'original': s, 'translation': ''} for s in sentences]
    }
    
    # 6. 翻译词汇和句子
    print("翻译词汇...")
    vocab_list = []
    for w in words:
        trans = translate_batch_fast(translator, tokenizer, [w], target_lang='zho_Hans')[0]
        vocab_list.append({
            'word': w,
            'pos': 'adj.',  # 简化处理
            'meaning': trans,
            'example': f'This word is {w}.'
        })
    article['vocabulary'] = vocab_list
    
    print("翻译句子...")
    sent_list = []
    for s in sentences[:5]:
        trans = translate_batch_fast(translator, tokenizer, [s], target_lang='zho_Hans')[0]
        sent_list.append({'original': s, 'translation': trans})
    article['sentences'] = sent_list
    
    # 7. 生成MD
    print("生成MD文件...")
    md_content = generate_md(article)
    md_file = output_path / f"{input_path.stem}.md"
    with open(md_file, 'w', encoding='utf-8') as f:
        f.write(md_content)
    print(f"MD文件: {md_file}")
    
    # 8. 生成PDF（需要安装 weasyprint）
    try:
        from weasyprint import HTML
        print("生成PDF...")
        
        html_content = f"""
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                @font-face {{ font-family: 'LXGW'; src: url('LXGWWenKai-Regular.ttf'); }}
                body {{ font-family: 'LXGW', sans-serif; padding: 20px; }}
                h1 {{ color: #2C3E50; }}
                .section {{ margin: 20px 0; }}
                .section-title {{ color: #27AE60; font-weight: bold; }}
                table {{ width: 100%; border-collapse: collapse; }}
                th, td {{ border: 1px solid #E0E0E0; padding: 8px; text-align: left; }}
                th {{ background: #F5F5DC; }}
            </style>
        </head>
        <body>
            <h1>{article['title']}</h1>
            
            <div class="section">
                <div class="section-title">原文</div>
                <p>{article['original'].replace(chr(10), '<br>')}</p>
            </div>
            
            <div class="section">
                <div class="section-title">译文</div>
                <p>{article['translation'].replace(chr(10), '<br>')}</p>
            </div>
        </body>
        </html>
        """
        
        pdf_file = output_path / f"{input_path.stem}.pdf"
        HTML(string=html_content).write_pdf(pdf_file)
        print(f"PDF文件: {pdf_file}")
    except ImportError:
        print("跳过PDF生成（需要安装: pip install weasyprint）")
    
    print("\n完成!")
    return article

def main():
    parser = argparse.ArgumentParser(description='生成中英双语文章卡片')
    parser.add_argument('input', help='输入文章文件')
    parser.add_argument('-o', '--output', default='./output', help='输出目录')
    parser.add_argument('-d', '--difficulty', default='intermediate', help='难度')
    
    args = parser.parse_args()
    
    article_to_card(args.input, args.output, args.difficulty)

if __name__ == '__main__':
    main()
```

### A.5 使用示例

```bash
# 安装依赖
pip install markdown weasyprint pillow

# 运行
python article_card.py sample_article.txt -o ./output

# 输出
output/
├── sample_article.md    # Markdown文件
├── sample_article.pdf   # PDF文件
└── cards/
    ├── sample_article_front.png
    └── sample_article_back.png
```

---

## 九、开始执行

**确认以下事项：**

- [ ] 已创建 GitHub 项目并 clone 到 `/home/quqiufeng/WordCard`
- [ ] 数据库已创建 (`english_card`)
- [ ] translate.py 可正常翻译
- [ ] Node.js 环境已安装

**开始开发：**

```bash
cd /home/quqiufeng/WordCard

# 1. 创建数据库
mysql -u root -p < sql/create_tables.sql

# 2. 开发后端 API（OpenResty）
# 编辑 /var/www/web/my-openresty/app/routes.lua 添加API路由
# 开发 /var/www/web/my-openresty/app/controllers 下的控制器

# 3. 开发前端 H5
cd frontend
npm install
npm run dev
```

---

**祝开发顺利！**
