import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// UI 自动化桥。
///
/// 每个按钮都通过 [invoke] 触发（UI 点击与 AI 调用同一条路径），因此：
///   · 任何点击都会以 `{"event":"click","id":...}` 事件广播给外部客户端；
///   · 外部（AI agent）可通过 Unix socket 发 `click` 命令模拟点击；
///   · 可 `list` 查询所有动作 id，`state` 查询当前界面状态。
///
/// 控制面为 Unix domain socket，JSON Lines 协议。C 客户端见
/// `src/automation/automation_ctl.c`（libwordcard_ctl.so），LuaJIT FFI 封装见
/// `gui/flutter/automation/wordcard.lua`。
final class Automation {
  Automation._();

  static final Automation instance = Automation._();

  final Map<String, void Function()> _actions = {};
  final List<Socket> _clients = [];

  ServerSocket? _server;
  String? socketPath;

  /// 当前界面状态（由页面主动写入），供 `state` 查询。
  Map<String, dynamic> state = {};

  List<String> get actionIds => _actions.keys.toList(growable: false);

  /// 注册一个可被点击的动作。
  void register(String id, void Function() handler) {
    _actions[id] = handler;
  }

  /// 触发动作（UI 点击 / AI 调用都走这里）并广播事件。
  bool invoke(String id, {String source = 'ui'}) {
    final handler = _actions[id];
    if (handler == null) return false;
    handler();
    _broadcast({'event': 'click', 'id': id, 'source': source});
    return true;
  }

  void updateState(Map<String, dynamic> s) {
    state = s;
  }

  void _broadcast(Map<String, dynamic> e) {
    final line = '${jsonEncode(e)}\n';
    for (final c in List<Socket>.of(_clients)) {
      try {
        c.write(line);
      } catch (_) {
        _clients.remove(c);
      }
    }
  }

  Future<void> start({String? path}) async {
    if (_server != null) return;
    socketPath = path ??
        Platform.environment['WC_AUTOMATION_SOCK'] ??
        '/tmp/wordcard-automation.sock';
    final f = File(socketPath!);
    if (f.existsSync()) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
    _server = await ServerSocket.bind(
      InternetAddress(socketPath!, type: InternetAddressType.unix),
      0,
    );
    _server!.listen(_onClient);
  }

  void _onClient(Socket socket) {
    _clients.add(socket);
    socket.write('${jsonEncode({
          'event': 'ready',
          'actions': actionIds,
        })}\n');
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) => _handle(socket, line),
      onDone: () => _clients.remove(socket),
      onError: (_) => _clients.remove(socket),
    );
  }

  void _reply(Socket s, Map<String, dynamic> m) {
    try {
      s.write('${jsonEncode(m)}\n');
    } catch (_) {}
  }

  void _handle(Socket s, String line) {
    if (line.trim().isEmpty) return;
    Map<String, dynamic> req;
    try {
      req = jsonDecode(line) as Map<String, dynamic>;
    } catch (e) {
      _reply(s, {'ok': false, 'error': 'bad json: $e'});
      return;
    }
    switch ('${req['cmd']}') {
      case 'list':
        _reply(s, {'ok': true, 'actions': actionIds});
        break;
      case 'state':
        _reply(s, {'ok': true, 'state': state});
        break;
      case 'click':
        final id = '${req['id']}';
        final ok = invoke(id, source: 'ai');
        _reply(s, {'ok': ok, 'id': id, 'error': ok ? null : 'unknown action'});
        break;
      case 'ping':
        _reply(s, {'ok': true, 'pong': true});
        break;
      default:
        _reply(s, {'ok': false, 'error': 'unknown cmd: ${req['cmd']}'});
    }
  }
}
