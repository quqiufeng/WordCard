import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordcard/theme/app_theme.dart';
import 'package:wordcard/theme/fonts.dart';

void main() {
  test('字体与语义色常量已定义', () {
    expect(AppFonts.mapleMono, 'MapleMonoNF');
    expect(ChinaColors.qiuxiang, isA<Color>());
    expect(ChinaColors.daiLan, isA<Color>());
  });
}
