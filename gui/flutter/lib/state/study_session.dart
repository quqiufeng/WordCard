import 'package:flutter/foundation.dart';

import '../ffi/wordcard.dart';

/// 当前显示的卡片：队列项 + 学习项正文。
final class ActiveCard {
  const ActiveCard({required this.queue, required this.item});

  final QueueCard queue;
  final ItemEntry item;

  int get itemId => queue.itemId;
  int get mode => queue.mode;
  String get modeName => queue.modeName;
  String get question => item.questionText;
  String get answer => item.answerText;
  String get explanation => item.explanationText;
  String get hint => item.hintText;
}

/// 复习会话状态：驱动「队列 → 翻转 → 评分 → SM-2 → 下一张」闭环。
class StudySession extends ChangeNotifier {
  StudySession({required this.engine, required this.userId});

  final WordCardEngine engine;
  final int userId;

  final List<QueueCard> _queue = [];
  int _index = 0;
  bool _flipped = false;
  MasterySnapshot? _lastResult;
  String? _error;
  bool _loaded = false;

  int get total => _queue.length;
  int get done => _index;
  bool get loaded => _loaded;
  bool get finished => _loaded && _index >= _queue.length;
  bool get flipped => _flipped;
  MasterySnapshot? get lastResult => _lastResult;
  String? get error => _error;

  QueueCard? get _currentQueue =>
      _index < _queue.length ? _queue[_index] : null;

  ActiveCard? get current {
    final q = _currentQueue;
    if (q == null) return null;
    final item = engine.itemById(q.itemId);
    if (item == null) return null;
    return ActiveCard(queue: q, item: item);
  }

  /// 加载今日队列。
  void start({int limit = 50}) {
    _queue.clear();
    _index = 0;
    _flipped = false;
    _lastResult = null;
    _error = null;
    try {
      _queue.addAll(engine.dailyQueue(userId: userId, limit: limit));
      _loaded = true;
    } catch (e) {
      _error = e.toString();
      _loaded = false;
    }
    notifyListeners();
  }

  /// 翻转卡片。
  void flip() {
    _flipped = !_flipped;
    notifyListeners();
  }

  /// 提交评分（quality 0-5）并立即进入下一张。
  ///
  /// 不会 → quality 1；记得 → quality 4。
  void grade(int quality) {
    final card = current;
    if (card == null) return;
    try {
      _lastResult = engine.review(
        userId: userId,
        itemId: card.itemId,
        quality: quality,
      );
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    _advance();
  }

  void _advance() {
    if (_index < _queue.length) _index++;
    _flipped = false;
    if (_index >= _queue.length) {
      try {
        engine.save();
      } catch (_) {
        // 落盘失败不阻断 UI。
      }
    }
    notifyListeners();
  }
}
