# WordCard 代码复盘报告

## 已修复问题

### 1. C层关键Bug修复 ✅

| 问题 | 文件 | 修复方式 |
|------|------|----------|
| 死代码 `uint8_t < 0` | `wordcard.c:707` | 改为 `if (quality > 5) quality = 5` |
| 文件句柄泄漏 | `wordcard.c:wc_load_db` | 统一使用 `ok` 标志 + 末尾统一 fclose |
| 伪词汇污染 | `import_article.py` | 移除 `__ARTICLE_` 前缀的虚假词汇 |
| 硬编码路径 | `voice/__init__.py` | 改为 `os.environ.get()` 优先读取环境变量 |

### 2. 编译验证 ✅

```bash
cd src && make clean && make  # 编译通过，0 警告
./test_sm2                     # 7/7 测试通过
```

---

## 待优化问题（建议后续处理）

### P1: 性能优化

1. **哈希表动态扩容** - 当前桶大小固定1024，数据量大时冲突率高
2. **wc_get_due_words 全表扫描** - 应维护按 next_review 排序的索引
3. **全局单锁** - 应拆分为读写锁或表级锁

### P2: 功能补全

4. **content_source_t API** - 头文件有定义但无创建/查询函数
5. **删除/更新操作** - 当前只有增加和查询
6. **用户ID索引** - wc_find_user_by_id 仍是 O(n) 扫描

### P3: 工程化

7. **Python 异常处理** - api.py 中 ctypes 调用缺少 NULL 检查
8. **结构化日志** - 使用 print 而非 logging 模块
9. **配置集中化** - 路径散落在多个文件中

---

*复盘日期: 2026-05-14*
