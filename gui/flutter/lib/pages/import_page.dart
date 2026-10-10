import 'package:flutter/material.dart';

import '../ebook_import.dart';
import '../ffi/wordcard.dart';
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
      // 词条已入库，释义异步生成、逐条回填
      final total = extract.words.length;
      setState(() {
        _ebookStage = '生成释义 0/$total';
        _ebookMsg = null;
      });
      final defined = await importer.defineAll(
        extract,
        onProgress: (d, t) {
          if (mounted) setState(() => _ebookStage = '生成释义 $d/$t');
        },
      );
      if (!mounted) return;
      setState(() {
        _ebookStage = null;
        _ebookMsg = '《${extract.title}》新增 $added 词，释义 $defined 条';
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
            onPressed: _busy == null && _lists.isNotEmpty ? _importAll : null,
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
                  onPressed: _busy == null ? _importEbook : null,
                  child: const Text('选择电子书…'),
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
              onPressed: _busy == null ? () => _import(info) : null,
              child: const Text('导入'),
            ),
    );
  }
}
