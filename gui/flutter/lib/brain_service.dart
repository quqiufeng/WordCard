import 'dart:io';

/// App 启动时拉起/复用可见的 WordCard 口语大脑终端（tmux + serve + TUI）。
///
/// 实际动作在 `tools/wordcard_brain.lua`：LuaJIT FFI(libxdo) 打开终端，
/// tmux 里窗口 0 = TUI、窗口 1 = opencode serve(:4098)。
final class BrainService {
  BrainService._();

  static Future<void> start() async {
    String? root;
    for (final c in ['.', '/opt/WordCard']) {
      if (File('$c/tools/wordcard_brain.lua').existsSync()) {
        root = Directory(c).absolute.path;
        break;
      }
    }
    if (root == null) return;
    try {
      final p = await Process.start(
        'luajit',
        ['$root/tools/wordcard_brain.lua'],
        workingDirectory: root,
      );
      // 启动器很快退出；终端/tmux 由它自己 setsid 保持
      p.stdout.drain<void>();
      p.stderr.drain<void>();
    } catch (_) {
      // 大脑启动失败不阻塞 App；开始对话时 voice_chat_server 还会再确保一次
    }
  }
}
