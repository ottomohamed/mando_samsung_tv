import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SamsungTVService {
  WebSocket? _socket;
  bool _isConnected = false;
  String? _token;
  String? _currentHost;
  Completer<bool>? _connectCompleter;

  Function(bool)? onConnectionChanged;
  Function(String)? onError;

  bool get isConnected => _isConnected;

  Future<bool> connect(String host) async {
    _currentHost = host;
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('tv_token_$host');

      final appName = base64Url.encode(utf8.encode('Samsung Remote'));
      var uriStr = 'wss://$host:8002/api/v2/channels/samsung.remote.control?name=$appName';
      if (_token != null) uriStr += '&token=$_token';

      final success = await _tryConnect(Uri.parse(uriStr), timeout: 20);
      if (success) return true;

      // Fallback to port 8001 if 8002 fails
      debugPrint('WSS failed, trying WS fallback...');
      var fallbackUri = 'ws://$host:8001/api/v2/channels/samsung.remote.control?name=$appName';
      if (_token != null) fallbackUri += '&token=$_token';
      
      return await _tryConnect(Uri.parse(fallbackUri), timeout: 10);
    } catch (e) {
      debugPrint('Connection failed: $e');
      return false;
    }
  }

  Future<bool> _tryConnect(Uri uri, {int timeout = 20}) async {
    try {
      _socket?.close();
      _connectCompleter = Completer<bool>();
      
      final client = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true
        ..connectionTimeout = const Duration(seconds: 5);

      final request = await client.openUrl('GET', uri);
      request.headers.set('Connection', 'Upgrade');
      request.headers.set('Upgrade', 'websocket');
      request.headers.set('sec-websocket-version', '13');
      request.headers.set('sec-websocket-key', base64.encode(List<int>.generate(16, (_) => 0)));

      final response = await request.close();
      final socket = await response.detachSocket();
      _socket = WebSocket.fromUpgradedSocket(socket, serverSide: false);

      _socket!.listen(
        _onData,
        onDone: _onDisconnected,
        onError: (e) {
          debugPrint('WS Error: $e');
          _onDisconnected();
          if (_connectCompleter?.isCompleted == false) _connectCompleter?.complete(false);
        },
      );

      final success = await _connectCompleter!.future.timeout(
        Duration(seconds: timeout),
        onTimeout: () => false,
      );

      if (success) {
        _isConnected = true;
        onConnectionChanged?.call(true);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('TryConnect Error: $e');
      return false;
    }
  }

  void _onData(dynamic data) {
    try {
      final json = jsonDecode(data);
      debugPrint('TV Data: $json');
      
      if (json['event'] == 'ms.channel.connect') {
        final dataMap = json['data'];
        if (dataMap != null && dataMap['token'] != null) {
          _token = dataMap['token'];
          _saveToken();
        }
        if (_connectCompleter?.isCompleted == false) _connectCompleter?.complete(true);
      }
    } catch (_) {}
  }

  Future<void> _saveToken() async {
    if (_token != null && _currentHost != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('tv_token_$_currentHost', _token!);
    }
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
              
              const batchSize = 40;
              for (int i = 1; i <= 254; i += batchSize) {
                final futures = <Future>[];
                for (int j = 0; j < batchSize && (i + j) <= 254; j++) {
                  final ip = '$subnet.${i + j}';
                  futures.add(_checkPort(ip, 8002).then((ok) { 
                    if (ok) found.add(ip); 
                  }));
                  futures.add(_checkPort(ip, 8001).then((ok) { 
                    if (ok && !found.contains(ip)) found.add(ip); 
                  }));
                }
                await Future.wait(futures);
              }
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
