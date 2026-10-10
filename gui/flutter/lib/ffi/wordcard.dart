import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'structs.dart';

export 'structs.dart';

/// 学习队列中的一项：item_id + 推荐模式（study_mode_t）。
final class QueueCard {
  const QueueCard(this.itemId, this.mode);

  final int itemId;
  final int mode;

  /// 推荐模式名称。
  String get modeName => switch (mode) {
        1 => '闪卡',
        2 => '选择',
        3 => '填空',
        4 => '拼写',
        5 => '听写',
        6 => '发音',
        7 => '配对',
        8 => '速闪',
        _ => '未知',
      };
}

/// 复习提交后的掌握度快照（Dart 侧只读副本）。
final class MasterySnapshot {
  const MasterySnapshot({
    required this.overall,
    required this.recognition,
    required this.recall,
    required this.spelling,
    required this.listening,
    required this.pronunciation,
    required this.usage,
    required this.intervalDays,
    required this.repetitions,
    required this.easeFactor,
    required this.totalReviews,
    required this.correctCount,
    required this.wrongCount,
    required this.streakDays,
  });

  factory MasterySnapshot.from(UserItemMastery m) => MasterySnapshot(
        overall: m.overall,
        recognition: m.recognition,
        recall: m.recall,
        spelling: m.spelling,
        listening: m.listening,
        pronunciation: m.pronunciation,
        usage: m.usage,
        intervalDays: m.intervalDays,
        repetitions: m.repetitions,
        easeFactor: m.easeFactor,
        totalReviews: m.totalReviews,
        correctCount: m.correctCount,
        wrongCount: m.wrongCount,
        streakDays: m.streakDays,
      );

  final int overall;
  final int recognition;
  final int recall;
  final int spelling;
  final int listening;
  final int pronunciation;
  final int usage;
  final int intervalDays;
  final int repetitions;
  final double easeFactor;
  final int totalReviews;
  final int correctCount;
  final int wrongCount;
  final int streakDays;
}

/// `libwordcard.so` 的 Dart 封装，仅暴露 UI 需要的最小子集。
///
/// 所有指针所有权归 C 层，Dart 侧只读，不做手动释放。
final class WordCardEngine {
  WordCardEngine._(this._db, this._lib, this._dbPath) {
    _dbFree = _lib.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('wc_db_free');
    _saveDb = _lib.lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Utf8>),
        int Function(Pointer<Void>, Pointer<Utf8>)>('wc_save_db');
    _markDirty = _lib.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('wc_mark_dirty');
    _findUser = _lib.lookupFunction<
        Pointer<User> Function(Pointer<Void>, Pointer<Utf8>),
        Pointer<User> Function(Pointer<Void>, Pointer<Utf8>)>('wc_find_user');
    _createUser = _lib.lookupFunction<
        Uint32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
        int Function(Pointer<Void>, Pointer<Utf8>,
            Pointer<Utf8>)>('wc_create_user');
    _findItemById = _lib.lookupFunction<
        Pointer<ItemEntry> Function(Pointer<Void>, Uint32),
        Pointer<ItemEntry> Function(
            Pointer<Void>, int)>('wc_find_item_by_id');
    _dailyQueue = _lib.lookupFunction<
        Size Function(Pointer<Void>, Uint32, Uint32, Pointer<Uint32>,
            Pointer<Uint8>, Size),
        int Function(Pointer<Void>, int, int, Pointer<Uint32>, Pointer<Uint8>,
            int)>('wc_generate_daily_queue');
    _getOrCreateMastery = _lib.lookupFunction<
        Pointer<UserItemMastery> Function(Pointer<Void>, Uint32, Uint32),
        Pointer<UserItemMastery> Function(
            Pointer<Void>, int, int)>('wc_get_or_create_mastery');
    _findMastery = _lib.lookupFunction<
        Pointer<UserItemMastery> Function(Pointer<Void>, Uint32, Uint32),
        Pointer<UserItemMastery> Function(
            Pointer<Void>, int, int)>('wc_find_mastery');
    _sm2Update = _lib.lookupFunction<
        Void Function(Pointer<UserItemMastery>, Uint8),
        void Function(Pointer<UserItemMastery>, int)>('wc_sm2_update');
    _recalcOverall = _lib.lookupFunction<
        Void Function(Pointer<UserItemMastery>),
        void Function(Pointer<UserItemMastery>)>('wc_recalc_overall');
    _recordActivity = _lib.lookupFunction<
        Void Function(Pointer<Void>, Uint32, Int32, Int32, Uint32),
        void Function(
            Pointer<Void>, int, int, int, int)>('wc_record_activity');
    _now = _lib.lookupFunction<Uint32 Function(), int Function()>('wc_now');
    _version = _lib.lookupFunction<Pointer<Utf8> Function(),
        Pointer<Utf8> Function()>('wc_version_string');
    _addItem = _lib.lookupFunction<
        Uint32 Function(Pointer<Void>, Pointer<ItemEntry>),
        int Function(Pointer<Void>, Pointer<ItemEntry>)>('wc_add_item');
    _findItemByQuestion = _lib.lookupFunction<
        Pointer<ItemEntry> Function(Pointer<Void>, Pointer<Utf8>),
        Pointer<ItemEntry> Function(
            Pointer<Void>, Pointer<Utf8>)>('wc_find_item_by_question');
    _updateItemAnswer = _lib.lookupFunction<
        Int32 Function(Pointer<Void>, Uint32, Pointer<Utf8>),
        int Function(Pointer<Void>, int, Pointer<Utf8>)>(
        'wc_update_item_answer');
    _updateItemExplanation = _lib.lookupFunction<
        Int32 Function(Pointer<Void>, Uint32, Pointer<Utf8>),
        int Function(Pointer<Void>, int, Pointer<Utf8>)>(
        'wc_update_item_explanation');
  }

  final Pointer<Void> _db;
  final DynamicLibrary _lib;
  final String _dbPath;

  late final void Function(Pointer<Void>) _dbFree;
  late final int Function(Pointer<Void>, Pointer<Utf8>) _saveDb;
  late final void Function(Pointer<Void>) _markDirty;
  late final Pointer<User> Function(Pointer<Void>, Pointer<Utf8>) _findUser;
  late final int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)
      _createUser;
  late final Pointer<ItemEntry> Function(Pointer<Void>, int) _findItemById;
  late final int Function(Pointer<Void>, int, int, Pointer<Uint32>,
      Pointer<Uint8>, int) _dailyQueue;
  late final Pointer<UserItemMastery> Function(Pointer<Void>, int, int)
      _getOrCreateMastery;
  late final Pointer<UserItemMastery> Function(Pointer<Void>, int, int)
      _findMastery;
  late final void Function(Pointer<UserItemMastery>, int) _sm2Update;
  late final void Function(Pointer<UserItemMastery>) _recalcOverall;
  late final void Function(Pointer<Void>, int, int, int, int) _recordActivity;
  late final int Function() _now;
  late final Pointer<Utf8> Function() _version;
  late final int Function(Pointer<Void>, Pointer<ItemEntry>) _addItem;
  late final Pointer<ItemEntry> Function(Pointer<Void>, Pointer<Utf8>)
      _findItemByQuestion;
  late final int Function(Pointer<Void>, int, Pointer<Utf8>) _updateItemAnswer;
  late final int Function(Pointer<Void>, int, Pointer<Utf8>)
      _updateItemExplanation;

  String get version => _version().toDartString();

  /// 打开数据库。按候选路径依次尝试共享库与 db 文件。
  static WordCardEngine open({
    String? libraryPath,
    String? dbPath,
  }) {
    final lib = DynamicLibrary.open(_resolveLibrary(libraryPath));
    final loadDb = lib.lookupFunction<
        Pointer<Void> Function(Pointer<Utf8>),
        Pointer<Void> Function(Pointer<Utf8>)>('wc_load_db');
    final dbInit =
        lib.lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
            'wc_db_init');

    final resolvedDb = _resolveDb(dbPath);
    final dbPtr = resolvedDb.toNativeUtf8();
    Pointer<Void> db;
    try {
      db = loadDb(dbPtr);
      if (db == nullptr) db = dbInit();
    } finally {
      malloc.free(dbPtr);
    }
    if (db == nullptr) {
      throw StateError('无法打开数据库: $resolvedDb');
    }
    return WordCardEngine._(db, lib, resolvedDb);
  }

  static String _resolveLibrary(String? override) {
    final candidates = <String>[
      if (override != null) override,
      'libwordcard.so',
      'src/libwordcard.so',
      '/opt/WordCard/src/libwordcard.so',
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    // 交给系统加载器（LD_LIBRARY_PATH）再试一次。
    return override ?? 'libwordcard.so';
  }

  static String _resolveDb(String? override) {
    final candidates = <String>[
      if (override != null) override,
      'data/wordcard.db',
      '/opt/WordCard/data/wordcard.db',
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return override ?? 'data/wordcard.db';
  }

  int now() => _now();

  /// 查找或创建用户，返回其 id。
  int findOrCreateUser({String uid = 'default', String name = 'Default User'}) {
    final uidPtr = uid.toNativeUtf8();
    final namePtr = name.toNativeUtf8();
    try {
      final user = _findUser(_db, uidPtr);
      if (user != nullptr) return user.ref.id;
      return _createUser(_db, uidPtr, namePtr);
    } finally {
      malloc.free(uidPtr);
      malloc.free(namePtr);
    }
  }

  /// 今日学习队列。
  List<QueueCard> dailyQueue({required int userId, int limit = 50}) {
    final ids = malloc<Uint32>(limit);
    final modes = malloc<Uint8>(limit);
    try {
      final count =
          _dailyQueue(_db, userId, now(), ids, modes, limit);
      return List<QueueCard>.generate(
        count,
        (i) => QueueCard(ids[i], modes[i]),
        growable: false,
      );
    } finally {
      malloc.free(ids);
      malloc.free(modes);
    }
  }

  /// 读取学习项；不存在返回 null。
  ItemEntry? itemById(int itemId) {
    final p = _findItemById(_db, itemId);
    return p == nullptr ? null : p.ref;
  }

  /// 判断学习项（按 question）是否已存在。
  bool hasItem(String question) {
    final q = question.toNativeUtf8();
    try {
      return _findItemByQuestion(_db, q) != nullptr;
    } finally {
      malloc.free(q);
    }
  }

  /// 按 question 查 item_id；不存在返回 null。
  int? itemIdByQuestion(String question) {
    final q = question.toNativeUtf8();
    try {
      final p = _findItemByQuestion(_db, q);
      return p == nullptr ? null : p.ref.id;
    } finally {
      malloc.free(q);
    }
  }

  /// 更新已存在学习项的释义（用于异步回填 LLM 释义）。
  bool updateItemAnswer(int itemId, String answer) {
    final a = answer.toNativeUtf8();
    try {
      return _updateItemAnswer(_db, itemId, a) == 0;
    } finally {
      malloc.free(a);
    }
  }

  /// 更新已存在学习项的上下文（用于异步回填段落/例句译文）。
  bool updateItemExplanation(int itemId, String explanation) {
    final e = explanation.toNativeUtf8();
    try {
      return _updateItemExplanation(_db, itemId, e) == 0;
    } finally {
      malloc.free(e);
    }
  }

  /// 新增学习项，返回其 id（0 表示失败）。
  int addItem({
    required String question,
    String answer = '',
    String explanation = '',
    String hint = '',
    int difficulty = 1,
    int category = 1,
    int sourceId = 0,
    String tags = '',
  }) {
    final p = calloc<ItemEntry>();
    try {
      final r = p.ref;
      writeCString(r.question, question, 512);
      writeCString(r.answer, answer, 512);
      writeCString(r.explanation, explanation, 1024);
      writeCString(r.hint, hint, 256);
      r.difficulty = difficulty;
      r.sourceId = sourceId;
      r.category = category;
      writeCString(r.tags, tags, 128);
      r.frequency = 0;
      return _addItem(_db, p);
    } finally {
      calloc.free(p);
    }
  }

  /// 读取掌握度；不存在返回 null。
  MasterySnapshot? mastery({required int userId, required int itemId}) {
    final p = _findMastery(_db, userId, itemId);
    return p == nullptr ? null : MasterySnapshot.from(p.ref);
  }

  /// 提交一次复习（quality 0-5），更新 SM-2 并记录活动。
  MasterySnapshot review({
    required int userId,
    required int itemId,
    required int quality,
  }) {
    final p = _getOrCreateMastery(_db, userId, itemId);
    if (p == nullptr) {
      throw StateError('掌握度创建失败: user=$userId item=$itemId');
    }
    _sm2Update(p, quality);
    _recalcOverall(p);
    _recordActivity(_db, userId, 0, quality >= 3 ? 1 : 0, 0);
    _markDirty(_db);
    return MasterySnapshot.from(p.ref);
  }

  /// 落盘到打开时的数据库路径。
  int save() {
    final p = _dbPath.toNativeUtf8();
    try {
      return _saveDb(_db, p);
    } finally {
      malloc.free(p);
    }
  }

  void close() => _dbFree(_db);
}
