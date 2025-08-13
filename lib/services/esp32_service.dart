// esp32_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

enum ConnectionMode { http, websocket }

class Esp32Service extends ChangeNotifier {
  String ip = '192.168.4.1';
  int port = 80;
  int wsPort = 81; // Port WebSocket de l'ESP32
  ConnectionMode mode = ConnectionMode.http;
  bool _manualDisconnect = false;

  WebSocketChannel? _ws;
  StreamSubscription? _wsSub;

  bool connected = false;
  double battery = 100.0;
  int rssi = 0;
  double speed = 0.7; // Valeur entre 0.0 et 1.0

  void updateConfig({
    required String ipAddr,
    required int portNum,
    required ConnectionMode newMode,
    int? wsPortNum,
  }) {
    ip = ipAddr;
    port = portNum;
    if (wsPortNum != null) wsPort = wsPortNum;
    mode = newMode;
    disconnect();
    notifyListeners();
  }

  String get baseUrl => 'http://$ip:$port';
  String get wsUrl => 'ws://$ip:$wsPort';

  Future<bool> testConnection() async {
    try {
      if (mode == ConnectionMode.http) {
        final res = await http
            .get(Uri.parse('$baseUrl/ping'))
            .timeout(const Duration(seconds: 3));
        connected = res.statusCode == 200;
      } else {
        await connectWebSocket();
      }
    } catch (e) {
      connected = false;
      debugPrint('Connection test failed: $e');
    }
    notifyListeners();
    return connected;
  }

  Future<void> connectWebSocket(
      {Duration timeout = const Duration(seconds: 4)}) async {
    _manualDisconnect = false;

    if (_ws != null) return;

    try {
      final completer = Completer<void>();

      _ws = WebSocketChannel.connect(Uri.parse(wsUrl));
      _wsSub = _ws!.stream.listen(
        (data) {
          debugPrint('WS Data: $data');

          try {
            final payload = jsonDecode(data);
            // Nouveau: Reconnaissance des réponses ESP32
            if (payload is Map && payload['status'] != null) {
              if (!completer.isCompleted) completer.complete();
              connected = true;
              notifyListeners();
              
              // Nouveau: Gestion des erreurs côté client
              if (payload['error'] != null) {
                debugPrint('Erreur ESP32: ${payload['error']}');
              }
            }
          } catch (_) {
            // ignore non-json
          }
        },
        onDone: () {
          debugPrint('WS onDone');
          connected = false;
          notifyListeners();
          if (!_manualDisconnect) {
            Future.delayed(const Duration(seconds: 2), () => connectWebSocket());
          }
        },
        onError: (error) {
          debugPrint('WS Error: $error');
          connected = false;
          notifyListeners();
          if (!_manualDisconnect) {
            Future.delayed(const Duration(seconds: 2), () => connectWebSocket());
          }
        },
        cancelOnError: true,
      );

      // Nouveau: Envoi d'un message de connexion spécifique ESP32
      _ws?.sink.add(jsonEncode({
        'cmd': 'handshake',
        'type': 'mobile_client',
        'version': '1.0'
      }));

      await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint('WS handshake timeout');
          try {
            _ws?.sink.close();
          } catch (_) {}
          _ws = null;
          connected = false;
          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint('WS Connection Error: $e');
      connected = false;
      _ws = null;
      notifyListeners();
      if (!_manualDisconnect) {
        Future.delayed(const Duration(seconds: 2), () => connectWebSocket());
      }
    }
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    await _wsSub?.cancel();
    await _ws?.sink.close();
    _ws = null;
    _wsSub = null;
    connected = false;
    notifyListeners();
  }

  Future<void> sendCommand(String command,
      {Map<String, dynamic>? data}) async {
    if (!connected) return;

    try {
      if (mode == ConnectionMode.http) {
        final uri = Uri.parse('$baseUrl/command?cmd=$command');
        await http.get(uri).timeout(const Duration(seconds: 2));
      } else {
        // Nouveau: Format ESP32-compatible
        final msg = jsonEncode({
          'cmd': command,
          if (data != null) 'data': data,
        });

        if (_ws == null) {
          debugPrint('WebSocket sink not available');
          connected = false;
          notifyListeners();
          return;
        }

        _ws!.sink.add(msg);
      }
    } catch (e) {
      debugPrint('Error sending command: $e');
      connected = false;
      notifyListeners();
    }
  }

  // Commandes adaptées pour ESP32
  Future<void> forward() => sendCommand('forward', data: {'speed': (speed * 255).toInt()});
  Future<void> backward() => sendCommand('backward', data: {'speed': (speed * 255).toInt()});
  Future<void> left() => sendCommand('left', data: {'speed': (speed * 255).toInt()});
  Future<void> right() => sendCommand('right', data: {'speed': (speed * 255).toInt()});
  Future<void> stop() => sendCommand('stop');
  Future<void> ledToggle() => sendCommand('led_toggle');
  Future<void> buzzer() => sendCommand('buzzer');

  void setSpeed(double s) {
    speed = s.clamp(0.0, 1.0);
    notifyListeners();
  }
}