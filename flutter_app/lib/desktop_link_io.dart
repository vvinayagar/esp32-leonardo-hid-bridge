import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class DesktopLink {
  String host;
  int port;
  bool enabled;
  String? lastError;

  RawDatagramSocket? _socket;

  DesktopLink({
    this.host = '',
    this.port = 51515,
    this.enabled = false,
  });

  bool get isConfigured => enabled && host.trim().isNotEmpty && port > 0;

  void configure({
    String? host,
    int? port,
    bool? enabled,
  }) {
    if (host != null) this.host = host;
    if (port != null) this.port = port;
    if (enabled != null) this.enabled = enabled;
  }

  Future<void> send(String line) async {
    if (!isConfigured) {
      lastError = 'Desktop link not configured';
      return;
    }
    try {
      _socket ??= await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _socket!.broadcastEnabled = true;
      final data = Uint8List.fromList(utf8.encode(line));
      _socket!.send(data, InternetAddress(host.trim()), port);
      lastError = null;
    } catch (e) {
      lastError = 'Desktop send failed: $e';
      rethrow;
    }
  }

  void dispose() {
    _socket?.close();
    _socket = null;
  }
}
