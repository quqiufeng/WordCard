import 'package:flutter/material.dart';

import '../automation/automation.dart';
import '../ebook_import.dart';
import '../ffi/wordcard.dart';
import '../paste_import.dart';
import '../theme/app_theme.dart';
import '../wordlist.dart';

/// 导入页。
///
/// **词典与电子书只是来源（source）不同**：导入后都成为同一
/// `wordcard.db` 中结构相同的学习项，进入同一复习队列，用同一套
/// SM-2 算法记忆——不存在两套复习逻辑。
class ImportPage extends StatefulWidget {
  const ImportPage({super.key, required this.engine});

  final WordCardEngine engine;

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  late final WordlistService _service = WordlistService(widget.engine);
  late final List<WordlistInfo> _lists = _service.list();
  final Map<String, int> _imported = {};

  String? _busy;
  int _done = 0;
  int _total = 0;
  String? _error;

  String? _ebookStage;
  String? _ebookMsg;

  final TextEditingController _pasteCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  String? _pasteStage;
  String? _pasteMsg;

  @override
  void initState() {
    super.initState();
    final a = Automation.instance;
    a.register('import.ebook', () => _importEbook());
    a.register('import.dict.all', () => _importAll());
    a.register('import.paste', () => _createPasteTask());
    for (final info in _lists) {
      a.register('import.dict.${info.name}', () => _import(info));
    }
  }

  @override
  void dispose() {
    _pasteCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _createPasteTask() async {
    final text = _pasteCtrl.text;
    if (text.trim().isEmpty) {
      setState(() => _pasteMsg = '请先粘贴单词表');
      return;
    }
    final name = _nameCtrl.text.trim().isEmpty
        ? '粘贴词表 ${DateTime.now().toString().substring(0, 16)}'
        : _nameCtrl.text.trim();
    setState(() {
      _pasteStage = '导入中';
      _pasteMsg = null;
    });
    try {
      final importer = PasteImporter(widget.engine);
      final added = await importer.import(name, text, onProgress: (d, t) {
        if (mounted) setState(() => _pasteStage = '导入中 $d/$t');
      });
      if (!mounted) return;
      setState(() {
        _pasteStage = null;
        _pasteMsg = '任务「$name」：新增 $added 词';
        _pasteCtrl.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pasteStage = null;
        _pasteMsg = '失败: $e';
      });
    }
  }

  Future<void> _importEbook() async {
    final importer = EbookImporter(widget.engine);
    final path = await importer.pickFile();
    if (path == null || !mounted) return;
    setState(() {
      _ebookStage = '解析中';
      _ebookMsg = null;
      _error = null;
    });
    try {
      final extract = await importer.extract(path, onStage: (s) {
        if (mounted) setState(() => _ebookStage = s);
      });
      if (!mounted) return;
      setState(() => _ebookStage = '导入中');
      final added = await importer.importWords(
        extract,
        onProgress: (d, t) {
          if (mounted) setState(() => _ebookMsg = '$d/$t');
        },
      );
      if (!mounted) return;
      // 单词释义来自 ECDICT；段落/例句由 LLM 异步翻译并回填
      setState(() => _ebookStage = '翻译段落/例句 0/${extract.words.length}');
      final translated = await importer.translateAll(
        extract,
        onProgress: (d, t) {
          if (mounted) setState(() => _ebookStage = '翻译段落/例句 $d/$t');
        },
      );
      if (!mounted) return;
      setState(() {
        _ebookStage = null;
        _ebookMsg = '《${extract.title}》新增 $added 词，译文回填 $translated 条；'
            '对照文件: ${extract.bilingualPath}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ebookStage = null;
        _error = e.toString();
      });
    }
  }

  Future<void> _import(WordlistInfo info) async {
    setState(() {
      _busy = info.name;
      _done = 0;
      _total = info.count;
      _error = null;
    });
    try {
      final added = await _service.import(info.name, onProgress: (d, t) {
        if (mounted) setState(() => _done = d);
      });
      if (!mounted) return;
      setState(() {
        _imported[info.name] = added;
        _busy = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _busy = null;
      });
    }
  }

  Future<void> _importAll() async {
    for (final info in _lists) {
      if (_busy != null) return;
      await _import(info);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Automation.instance.updateState({
      'page': 'import',
      'lists': _lists.map((l) => l.name).toList(),
      'busy': _busy,
      'stage': _ebookStage,
      'msg': _ebookMsg,
    });
    return ListView(
      primary: false,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Text(
            '来源不同，记忆相同：导入后进入同一复习队列，共用 SM-2。',
            style: theme.textTheme.bodySmall?.copyWith(color: ChinaColors.muted),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(_error!,
                style: TextStyle(color: theme.colorScheme.error)),
          ),

        _sectionHeader(
          theme,
          '考试词表',
          trailing: OutlinedButton.icon(
            onPressed: _busy == null && _lists.isNotEmpty
                ? () => Automation.instance.invoke('import.dict.all')
                : null,
            icon: const Icon(Icons.download_for_offline_outlined, size: 18),
            label: const Text('全部导入'),
          ),
        ),
        if (_lists.isEmpty)
          const ListTile(
            leading: Icon(Icons.folder_off_outlined, color: ChinaColors.dim),
            title: Text('未找到词表数据'),
            subtitle: Text('运行: python3 tools/build_wordlists.py'),
          )
        else
          ..._lists.map((i) => _wordlistTile(theme, i)),

        const Divider(height: 32),
        _sectionHeader(theme, '电子书'),
        ListTile(
          leading: const Icon(Icons.menu_book_outlined),
          title: const Text('PDF / MOBI / AZW3 / EPUB / MD'),
          subtitle: Text(
            _ebookStage != null
                ? '$_ebookStage ${_ebookMsg ?? ''}'
                : _ebookMsg ?? '解析复用 importer，词条并入同一复习队列',
            style: theme.textTheme.bodySmall,
          ),
          trailing: _ebookStage != null
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : FilledButton.tonal(
                  onPressed: _busy == null
                      ? () => Automation.instance.invoke('import.ebook')
                      : null,
                  child: const Text('选择电子书…'),
                ),
        ),

        const Divider(height: 32),
        _sectionHeader(theme, '粘贴单词表'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: '任务名称（可空）',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _pasteCtrl,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(
                  hintText: '每行一个单词；可带释义：\nabandon 放弃\norbit',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _pasteStage ?? _pasteMsg ?? '',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _pasteMsg != null && _pasteMsg!.startsWith('失败')
                            ? theme.colorScheme.error
                            : ChinaColors.muted,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _pasteStage == null
                        ? () => Automation.instance.invoke('import.paste')
                        : null,
                    icon: const Icon(Icons.add_task, size: 18),
                    label: const Text('创建任务'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(ThemeData theme, String title, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
      child: Row(
        children: [
          Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _wordlistTile(ThemeData theme, WordlistInfo info) {
    final isBusy = _busy == info.name;
    final imported = _imported[info.name];
    return ListTile(
      leading: const Icon(Icons.translate_outlined),
      title: Text(info.title),
      subtitle: Text(
        isBusy
            ? '导入中 $_done / $_total'
            : imported != null
                ? '已导入 $imported 词'
                : '${info.count} 词',
        style: theme.textTheme.bodySmall?.copyWith(
          color: imported != null ? ChinaColors.qinglv : ChinaColors.muted,
        ),
      ),
      trailing: isBusy
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2))
          : FilledButton.tonal(
              onPressed: _busy == null
                  ? () => Automation.instance
                      .invoke('import.dict.${info.name}')
                  : null,
              child: const Text('导入'),
            ),
    );
  }
}
