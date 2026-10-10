import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'structs.dart';

/// SM-2 记忆态 —— 对齐 `wc_mem_t`（src/store.h）。
final class MemStore extends Struct {
  @Uint32()
  external int userId;

  @Uint32()
  external int itemId;

  @Uint8()
  external int status;

  @Uint16()
  external int intervalDays;

  @Uint16()
  external int repetitions;

  @Float()
  external double ef;

  @Uint32()
  external int nextReview;

  @Uint32()
  external int lastReview;

  @Uint8()
  external int recognition;

  @Uint8()
  external int recall;

  @Uint8()
  external int spelling;

  @Uint8()
  external int listening;

  @Uint8()
  external int pronunciation;

  @Uint8()
  external int usage;

  @Uint8()
  external int overall;

  @Uint16()
  external int totalReviews;

  @Uint16()
  external int correctCount;

  @Uint16()
  external int wrongCount;

  @Uint8()
  external int streakDays;

  @Uint8()
  external int forgetCount;
}

/// 基于 KV Cache (mmap 零拷贝) 的记忆存储。
final class Store {
  Store._(this._handle, this._lib) {
    _close = _lib.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('wc_store_close');
    _sync = _lib.lookupFunction<Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)>('wc_store_sync');
    _addItem = _lib.lookupFunction<
        Uint32 Function(Pointer<Void>, Pointer<ItemEntry>),
        int Function(Pointer<Void>, Pointer<ItemEntry>)>('wc_store_add_item');
    _getItem = _lib.lookupFunction<
        Int32 Function(Pointer<Void>, Uint32, Pointer<ItemEntry>),
        int Function(
            Pointer<Void>, int, Pointer<ItemEntry>)>('wc_store_get_item');
    _findByWord = _lib.lookupFunction<
        Uint32 Function(Pointer<Void>, Pointer<Utf8>),
        int Function(Pointer<Void>, Pointer<Utf8>)>('wc_store_find_by_word');
    _memGet = _lib.lookupFunction<
        Int32 Function(Pointer<Void>, Uint32, Uint32, Pointer<MemStore>),
        int Function(
            Pointer<Void>, int, int, Pointer<MemStore>)>('wc_store_mem_get');
    _sm2 = _lib.lookupFunction<
        Int32 Function(Pointer<Void>, Uint32, Uint32, Uint8, Pointer<MemStore>),
        int Function(Pointer<Void>, int, int, int,
            Pointer<MemStore>)>('wc_store_sm2');
    _due = _lib.lookupFunction<
        Size Function(Pointer<Void>, Uint32, Uint32, Pointer<Uint32>, Size),
        int Function(Pointer<Void>, int, int, Pointer<Uint32>,
            int)>('wc_store_due');
  }

  final Pointer<Void> _handle;
  final DynamicLibrary _lib;

  late final void Function(Pointer<Void>) _close;
  late final int Function(Pointer<Void>) _sync;
  late final int Function(Pointer<Void>, Pointer<ItemEntry>) _addItem;
  late final int Function(Pointer<Void>, int, Pointer<ItemEntry>) _getItem;
  late final int Function(Pointer<Void>, Pointer<Utf8>) _findByWord;
  late final int Function(Pointer<Void>, int, int, Pointer<MemStore>) _memGet;
  late final int Function(Pointer<Void>, int, int, int, Pointer<MemStore>) _sm2;
  late final int Function(Pointer<Void>, int, int, Pointer<Uint32>, int) _due;

  static Store open(String dir, {String? libraryPath, int maxMemory = 256 << 20}) {
    final lib = DynamicLibrary.open(libraryPath ?? 'libwordcard.so');
    final open = lib.lookupFunction<
        Pointer<Void> Function(Pointer<Utf8>, Size),
        Pointer<Void> Function(Pointer<Utf8>, int)>('wc_store_open');
    final d = dir.toNativeUtf8();
    try {
      final h = open(d, maxMemory);
      if (h == nullptr) throw StateError('wc_store_open failed: $dir');
      return Store._(h, lib);
    } finally {
      malloc.free(d);
    }
  }

  int addItem({
    required String question,
    String answer = '',
    String explanation = '',
    String hint = '',
    String tags = '',
    int difficulty = 1,
  }) {
    final p = calloc<ItemEntry>();
    try {
      final r = p.ref;
      writeCString(r.question, question, 512);
      writeCString(r.answer, answer, 512);
      writeCString(r.explanation, explanation, 1024);
      writeCString(r.hint, hint, 256);
      writeCString(r.tags, tags, 128);
      r.difficulty = difficulty;
      return _addItem(_handle, p);
    } finally {
      calloc.free(p);
    }
  }

  ItemEntry? getItem(int id) {
    final p = calloc<ItemEntry>();
    try {
      return _getItem(_handle, id, p) == 0 ? p.ref : null;
    } finally {
      calloc.free(p);
    }
  }

  int findByWord(String word) {
    final w = word.toNativeUtf8();
    try {
      return _findByWord(_handle, w);
    } finally {
      malloc.free(w);
    }
  }

  MemStore memGet(int userId, int itemId) {
    final p = calloc<MemStore>();
    try {
      _memGet(_handle, userId, itemId, p);
      return p.ref;
    } finally {
      calloc.free(p);
    }
  }

  MemStore sm2(int userId, int itemId, int quality) {
    final p = calloc<MemStore>();
    try {
      _sm2(_handle, userId, itemId, quality, p);
      return p.ref;
    } finally {
      calloc.free(p);
    }
  }

  List<int> due(int userId, int now, {int max = 200}) {
    final buf = calloc<Uint32>(max);
    try {
      final n = _due(_handle, userId, now, buf, max);
      return List<int>.generate(n, (i) => buf[i]);
    } finally {
      calloc.free(buf);
    }
  }

  int sync() => _sync(_handle);
  void close() => _close(_handle);
}
