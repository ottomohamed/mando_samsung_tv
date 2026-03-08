import 'dart:async';
import 'dart:convert';
import 'dart:io';

class SamsungTVService {
  WebSocket? _socket;
  bool _isConnected = false;

  Function(bool)? onConnectionChanged;
  Function(String)? onError;

  bool get isConnected => _isConnected;

  Future<bool> connect(String host) async {
    try {
      final appName = base64Url.encode(utf8.encode('Samsung Remote'));
      final uri = 'wss://$host:8002/api/v2/channels/samsung.remote.control?name=$appName';

      final ctx = SecurityContext.defaultContext;
      _socket = await WebSocket.connect(uri).timeout(const Duration(seconds: 10));

      _socket!.listen(
        _onData,
        onDone: _onDisconnected,
        onError: (e) {
          _isConnected = false;
          onConnectionChanged?.call(false);
        },
      );

      _isConnected = true;
      onConnectionChanged?.call(true);
      return true;
    } catch (e) {
      // جرب HTTP بدل HTTPS
      try {
        final appName = base64Url.encode(utf8.encode('Samsung Remote'));
        final uri = 'ws://$host:8001/api/v2/channels/samsung.remote.control?name=$appName';
        _socket = await WebSocket.connect(uri).timeout(const Duration(seconds: 10));
        _socket!.listen(_onData, onDone: _onDisconnected, onError: (_) {
          _isConnected = false;
          onConnectionChanged?.call(false);
        });
        _isConnected = true;
        onConnectionChanged?.call(true);
        return true;
      } catch (e2) {
        onError?.call(e2.toString());
        return false;
      }
    }
  }

  void _onData(dynamic data) {
    try {
      final json = jsonDecode(data);
      if (json['event'] == 'ms.channel.connect') {
        _isConnected = true;
        onConnectionChanged?.call(true);
      }
    } catch (_) {}
  }

  void _onDisconnected() {
    _isConnected = false;
    onConnectionChanged?.call(false);
  }

  Future<void> sendKey(String key) async {
    if (!_isConnected || _socket == null) return;
    _socket!.add(jsonEncode({
      'method': 'ms.remote.control',
      'params': {
        'Cmd': 'Click',
        'DataOfCmd': key,
        'Option': 'false',
        'TypeOfRemote': 'SendRemoteKey',
      }
    }));
  }

  void disconnect() {
    _socket?.close();
    _isConnected = false;
  }

  static Future<List<String>> scanForTVs() async {
    final List<String> found = [];
    try {
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
              final futures = <Future>[];
              for (int i = 1; i <= 254; i++) {
                final ip = '$subnet.$i';
                futures.add(_checkPort(ip, 8002).then((ok) { if (ok) found.add(ip); }));
                futures.add(_checkPort(ip, 8001).then((ok) { if (ok && !found.contains(ip)) found.add(ip); }));
              }
              await Future.wait(futures);
            }
          }
        }
      }
    } catch (_) {}
    return found;
  }

  static Future<bool> _checkPort(String ip, int port) async {
    try {
      final s = await Socket.connect(ip, port, timeout: const Duration(seconds: 2));
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }
}
