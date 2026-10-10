import 'dart:io';

/// 图片 OCR 导入：选图 → 用 tools/ocr_image.py（PP-OCRv4）识别文字 → 供粘贴导入建任务。
final class OcrImporter {
  static const _defaultOrt =
      '/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib';

  static String? _root() {
    for (final c in ['.', '/opt/WordCard']) {
      if (File('$c/tools/ocr_image.py').existsSync()) return c;
    }
    return null;
  }

  /// 选择多张图片；取消返回空。
  Future<List<String>> pickImages() async {
    final r = await Process.run('zenity', [
      '--file-selection',
      '--multiple',
      '--separator=\n',
      '--title=选择单词表图片（可多选）',
      '--file-filter=图片 | *.png *.jpg *.jpeg *.webp *.bmp *.tif *.tiff',
      '--file-filter=所有文件 | *',
    ]);
    if (r.exitCode != 0) return const [];
    return (r.stdout as String)
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// 逐张识别并合并文本。
  Future<String> recognizeMany(
    List<String> imagePaths, {
    void Function(int done, int total)? onProgress,
  }) async {
    final parts = <String>[];
    for (var i = 0; i < imagePaths.length; i++) {
      try {
        final t = await recognize(imagePaths[i]);
        if (t.trim().isNotEmpty) parts.add(t.trim());
      } catch (_) {}
      onProgress?.call(i + 1, imagePaths.length);
    }
    return parts.join('\n');
  }

  Future<String> recognize(String imagePath) async {
    final root = _root();
    if (root == null) throw StateError('未找到 tools/ocr_image.py');
    final tmp = File('${Directory.systemTemp.path}/wc_ocr_'
        '${DateTime.now().microsecondsSinceEpoch}.txt');
    final env = Map<String, String>.from(Platform.environment);
    final ort = Platform.environment['WC_ORT_LIB'] ?? _defaultOrt;
    env['LD_LIBRARY_PATH'] = '$ort:${env['LD_LIBRARY_PATH'] ?? ''}';
    try {
      final r = await Process.run(
        'python3',
        ['$root/tools/ocr_image.py', imagePath, '--out', tmp.path],
        workingDirectory: root,
        environment: env,
      );
      if (r.exitCode != 0 || !tmp.existsSync()) {
        throw StateError('OCR 失败: ${(r.stderr as String).trim()}');
      }
      return tmp.readAsStringSync();
    } finally {
      if (tmp.existsSync()) tmp.deleteSync();
    }
  }
}
