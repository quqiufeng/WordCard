import 'dart:convert';
import 'dart:ffi';

/// 从定长 `char[N]`（UTF-8、NUL 结尾）读取 Dart 字符串。
///
/// FFI 的 `Array` 无运行时长度，需显式传入容量 [max]。
String readCString(Array<Uint8> arr, int max) {
  final codes = <int>[];
  for (var i = 0; i < max; i++) {
    final b = arr[i];
    if (b == 0) break;
    codes.add(b);
  }
  return utf8.decode(codes, allowMalformed: true);
}

/// 将字符串以 UTF-8 写入定长 `char[N]`（[max] 为容量，含结尾 NUL）。
void writeCString(Array<Uint8> arr, String s, int max) {
  final bytes = utf8.encode(s);
  final n = bytes.length < max - 1 ? bytes.length : max - 1;
  for (var i = 0; i < n; i++) {
    arr[i] = bytes[i];
  }
  arr[n] = 0;
}

/// 通用学习项 —— 对齐 `item_entry_t`（src/wordcard.h）。
final class ItemEntry extends Struct {
  @Uint32()
  external int id;

  @Array(512)
  external Array<Uint8> question;

  @Array(512)
  external Array<Uint8> answer;

  @Array(1024)
  external Array<Uint8> explanation;

  @Array(256)
  external Array<Uint8> hint;

  @Uint8()
  external int difficulty;

  @Uint32()
  external int sourceId;

  @Uint32()
  external int category;

  @Array(128)
  external Array<Uint8> tags;

  @Uint32()
  external int frequency;

  String get questionText => readCString(question, 512);
  String get answerText => readCString(answer, 512);
  String get explanationText => readCString(explanation, 1024);
  String get hintText => readCString(hint, 256);
  String get tagsText => readCString(tags, 128);
}

/// 用户 —— 对齐 `user_t`。
final class User extends Struct {
  @Uint32()
  external int id;

  @Array(64)
  external Array<Uint8> dingtalkUid;

  @Array(64)
  external Array<Uint8> name;

  @Uint8()
  external int role;

  @Uint16()
  external int dailyNewLimit;

  @Uint16()
  external int dailyReviewLimit;

  @Uint32()
  external int createdAt;

  @Uint32()
  external int lastActive;

  String get nameText => readCString(name, 64);
  String get uidText => readCString(dingtalkUid, 64);
}

/// 用户-学习项掌握度 —— 对齐 `user_item_mastery_t`（SM-2 + 6 维）。
final class UserItemMastery extends Struct {
  @Uint32()
  external int userId;

  @Uint32()
  external int itemId;

  @Uint8()
  external int sm2Status;

  @Uint16()
  external int intervalDays;

  @Uint16()
  external int repetitions;

  @Float()
  external double easeFactor;

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

  @Uint32()
  external int firstSeen;

  @Uint32()
  external int lastWrong;

  @Uint8()
  external int forgetCount;

  @Uint8()
  external int isDifficult;

  @Uint8()
  external int isFavorite;

  @Uint8()
  external int isBanned;
}

/// 每日统计 —— 对齐 `daily_stat_t`。
final class DailyStat extends Struct {
  @Uint32()
  external int userId;

  @Uint32()
  external int date;

  @Uint16()
  external int newItems;

  @Uint16()
  external int reviewedItems;

  @Uint16()
  external int masteredItems;

  @Uint16()
  external int wrongItems;

  @Uint32()
  external int studyTimeSec;
}
