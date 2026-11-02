import 'dart:io';

/// 统一的运行时根目录/原生二进制定位。
abstract final class NativePaths {
  static const _roots = ['.', '/opt/WordCard'];

  static List<String> get _candidates {
    final env = Platform.environment['WORDCARD_ROOT'];
    return [
      if (env != null && env.isNotEmpty) env,
      ..._roots,
    ];
  }

  static String? findFile(String relative) {
    for (final c in _candidates) {
      if (File('$c/$relative').existsSync()) {
        return Directory(c).absolute.path;
      }
    }
    return null;
  }

  static String? findDir(String relative) {
    for (final c in _candidates) {
      if (Directory('$c/$relative').existsSync()) {
        return Directory(c).absolute.path;
      }
    }
    return null;
  }

  static String? get root =>
      findFile('native/staticpy/translate/wc_translate') ??
      findDir('data') ??
      findDir('native');
}
