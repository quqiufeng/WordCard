import 'dart:io';

import '../ebook_import.dart';
import '../ffi/wordcard.dart';
import '../ocr_import.dart';
import '../paste_import.dart';
import '../wordlist.dart';
import 'automation.dart';

/// 对外统一 API：其他 agent（如 my-agent 的 Lua/语音/微信）可经自动化 socket
/// 调用这里注册的函数（`{"cmd":"call","fn":...,"args":{...}}`）。
///
/// 覆盖：导航 / 记忆数据 / 任务(列表·词表·学习·听写·删除·创建) /
/// 导入(词表·电子书·图片OCR) / 复习(翻转·评分·重来)。
final class AppApi {
  AppApi({
    required this.engine,
    required this.userId,
    required this.goToPage,
    required this.pageName,
    required this.pushReview,
    required this.pushDictation,
  });

  final WordCardEngine engine;
  final int userId;
  final void Function(int index) goToPage;
  final String Function() pageName;
  final void Function(List<int> itemIds, String name) pushReview;
  final void Function(List<int> itemIds, String name) pushDictation;

  void register() {
    final a = Automation.instance;

    // —— 状态 / 导航 ——
    a.registerFn('state', (_) => {
          'page': pageName(),
          'stats': _stats(),
          'tasks': _taskList(),
          'review': a.state,
        });
    a.registerFn('nav.goto', (args) {
      goToPage((args['page'] as num?)?.toInt() ?? 0);
      return true;
    });
    a.registerFn('stats', (_) => _stats());

    // —— 任务 ——
    a.registerFn('task.list', (_) => _taskList());
    a.registerFn('task.words', (args) {
      final tag = _tag(args);
      final items = engine.itemsByTag(tag);
      final page = (args['page'] as num?)?.toInt() ?? 0;
      final size = (args['size'] as num?)?.toInt() ?? 50;
      final start = (page * size).clamp(0, items.length);
      final end = (start + size).clamp(0, items.length);
      return {
        'tag': tag,
        'total': items.length,
        'page': page,
        'size': size,
        'words': [
          for (final e in items.sublist(start, end))
            {'id': e.id, 'w': e.questionText, 'a': e.answerText, 'hint': e.hintText},
        ],
      };
    });
    a.registerFn('task.study', (args) {
      final tag = _tag(args);
      final ids = _ids(tag);
      pushReview(ids, _taskName(tag));
      return ids.length;
    });
    a.registerFn('task.dictate', (args) {
      final tag = _tag(args);
      final ids = _ids(tag);
      pushDictation(ids, _taskName(tag));
      return ids.length;
    });
    a.registerFn('task.delete', (args) {
      final n = engine.deleteItemsByTag(_tag(args));
      engine.save();
      return n;
    });
    a.registerFn('task.create', (args) async {
      final name = '${args['name'] ?? '粘贴词表'}';
      final text = '${args['text'] ?? ''}';
      return PasteImporter(engine).import(name, text);
    });

    // —— 导入 ——
    a.registerFn('import.wordlist', (args) async {
      final svc = WordlistService(engine);
      final names = args['names'];
      var added = 0;
      if (names == 'all') {
        for (final l in svc.list()) {
          added += await svc.import(l.name);
        }
      } else {
        final list = names is List ? names.map((e) => '$e') : ['${args['name'] ?? ''}'];
        for (final n in list) {
          added += await svc.import(n);
        }
      }
      return added;
    });
    a.registerFn('import.ebook', (args) async {
      final path = '${args['path'] ?? ''}';
      if (path.isEmpty) throw StateError('missing path');
      final importer = EbookImporter(engine);
      final ex = await importer.extract(path);
      final added = await importer.importWords(ex);
      await importer.translateAll(ex);
      return added;
    });
    a.registerFn('import.image', (args) async {
      final raw = args['paths'];
      final paths = raw is List ? raw.map((e) => '$e').toList() : ['${args['path'] ?? ''}'];
      final text = await OcrImporter().recognizeMany(paths);
      final name = '${args['name'] ?? '图片单词表'}';
      return PasteImporter(engine).import(name, text);
    });

    // —— 复习（每日） ——
    a.registerFn('review.startDaily', (_) {
      pushReview(<int>[], '今日记忆');
      return true;
    });

    // —— 窗口 ——
    a.registerFn('window.activate', (_) async {
      await _wmctl('WID=\$(xdotool search --name "\$W" | head -1); '
          '[ -n "\$WID" ] && xdotool windowactivate --sync "\$WID" && '
          'xdotool windowraise "\$WID"; echo ok');
      return true;
    });
    a.registerFn('window.center', (_) async {
      final r = await _wmctl('''
read SW SH < <(xdotool getdisplaygeometry)
read X Y WW HH < <(wmctrl -lG | grep -i "\$W" | awk '{print \$3,\$4,\$5,\$6}')
TX=\$(( (SW-WW)/2 )); TY=\$(( (SH-HH)/2 ))
wmctrl -r "\$W" -e "0,\$TX,\$TY,\$WW,\$HH"
echo "\$TX \$TY \$WW \$HH"
''');
      return r;
    });
    a.registerFn('window.move', (args) async {
      final x = (args['x'] as num?)?.toInt() ?? 0;
      final y = (args['y'] as num?)?.toInt() ?? 0;
      final r = await _wmctl(
          'read X Y WW HH < <(wmctrl -lG | grep -i "\$W" | awk \'{print \$3,\$4,\$5,\$6}\'); '
          'wmctrl -r "\$W" -e "0,$x,$y,\$WW,\$HH"; echo ok');
      return r;
    });
    a.registerFn('app.quit', (_) {
      Future<void>.delayed(const Duration(milliseconds: 100), () => exit(0));
      return true;
    });
  }

  /// 在会话内调用 wmctrl/xdotool 操作本窗口（$W = 窗口标题）。
  Future<String> _wmctl(String body) async {
    final script = 'W=\${WC_WINDOW_TITLE:-WordCard}\n$body';
    final r = await Process.run('bash', ['-lc', script]);
    return (r.stdout as String).trim();
  }

  Map<String, dynamic> _stats() {
    final items = engine.allItems();
    final now = engine.now();
    var mastered = 0, due = 0;
    final status = <int, int>{};
    for (final it in items) {
      final m = engine.mastery(userId: userId, itemId: it.id);
      final st = m?.status ?? 0;
      status[it.id] = st;
      if (st == 2) mastered++;
      final nr = m?.nextReview ?? 0;
      if (st != 2 && (nr == 0 || nr <= now)) due++;
    }
    final total = items.length;
    return {
      'tasks': engine.tasks().length,
      'total': total,
      'mastered': mastered,
      'notMemorized': total - mastered,
      'completion': total == 0 ? 0 : (mastered * 100 / total).round(),
      'due': due,
    };
  }

  List<Map<String, dynamic>> _taskList() {
    final status = <int, int>{};
    for (final it in engine.allItems()) {
      status[it.id] = engine.mastery(userId: userId, itemId: it.id)?.status ?? 0;
    }
    return [
      for (final t in engine.tasks())
        {
          'tag': t.tag,
          'name': t.name,
          'kind': t.kind,
          'count': t.count,
          'done': engine
              .itemsByTag(t.tag)
              .where((e) => status[e.id] == 2)
              .length,
        },
    ];
  }

  String _tag(Map<String, dynamic> args) =>
      '${args['tag'] ?? args['name'] ?? ''}';

  String _taskName(String tag) => engine
      .tasks()
      .firstWhere((t) => t.tag == tag,
          orElse: () => TaskInfo(tag: tag, count: 0))
      .name;

  List<int> _ids(String tag) =>
      engine.itemsByTag(tag).map((e) => e.id).toList();
}
