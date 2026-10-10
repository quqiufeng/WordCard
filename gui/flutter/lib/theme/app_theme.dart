import 'package:flutter/material.dart';

import 'fonts.dart';

/// 中国传统色（**仅作语义数据色**，不覆盖 Yaru / 系统主色）。
///
/// 取自 `src/dotui.h` 与 `vocab_card.py` 的「中国色·霜地」浅色板。
abstract final class ChinaColors {
  static const shuangdi = Color(0xFFE2F0CB); // 霜地（生词卡底）
  static const nenjulv = Color(0xFFF3F8E8); // 嫩菊绿（卡片渐变上）
  static const cardBottom = Color(0xFFE7F0D6); // 卡片渐变下
  static const border = Color(0xFFC4D6A6); // 边框
  static const qiuxiang = Color(0xFFA3A33E); // 秋香色（强调边框）
  static const ink = Color(0xFF1D1B1C); // 墨色（正文）
  static const muted = Color(0xFF5B6B4F); // 次要文字
  static const dim = Color(0xFF8A9A7E); // 更弱文字
  static const daiLan = Color(0xFF2A3C5C); // 黛蓝（数据强调）
  static const qinglv = Color(0xFF2E8B57); // 青绿（正确）
  static const zhusha = Color(0xFFD92121); // 朱砂红（错误）
  static const orange = Color(0xFFE95420); // Ubuntu 橙（不会）
  static const warn = Color(0xFFC77A16); // 警示
}

/// 将 WordCard 的字体与语义色套用到 Yaru 提供的 `ThemeData` 上。
abstract final class AppTheme {
  static ThemeData apply(ThemeData base) {
    return base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: AppFonts.mapleMono),
      primaryTextTheme:
          base.primaryTextTheme.apply(fontFamily: AppFonts.mapleMono),
    );
  }
}
