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

  Future<String?> pickImage() async {
    final r = await Process.run('zenity', [
      '--file-selection',
      '--title=选择单词表图片',
      '--file-filter=图片 | *.png *.jpg *.jpeg *.webp *.bmp *.tif *.tiff',
      '--file-filter=所有文件 | *',
    ]);
    if (r.exitCode != 0) return null;
    final path = (r.stdout as String).trim();
    return path.isEmpty ? null : path;
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
