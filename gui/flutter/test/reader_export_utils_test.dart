import 'package:flutter_test/flutter_test.dart';
import 'package:wordcard/reader_export_utils.dart';

void main() {
  test('cleanCardText 清理链接、强调和多余空行', () {
    expect(
      cleanCardText('**前言**\n\n[链接](x.html#h1_1)  正文'),
      '前言\n\n链接 正文',
    );
  });

  test('splitSentences 保留中英文句末标点', () {
    expect(splitSentences('Hello world. 你好。再见！'),
        ['Hello world.', '你好。', '再见！']);
  });

  test('splitChineseContent 短内容单块', () {
    expect(splitChineseContent('短内容', target: 100), ['短内容']);
  });

  test('splitChineseContent 长内容按时切分', () {
    final text = List.generate(20, (i) => '第$i段。${'内容' * 60}').join('\n\n');
    final chunks = splitChineseContent(text, target: 500);
    expect(chunks.length, greaterThan(1));
    expect(chunks.every((c) => c.isNotEmpty), isTrue);
  });
}
