class DesktopLink {
  String host;
  int port;
  bool enabled;
  String? lastError;

  DesktopLink({
    this.host = '',
    this.port = 51515,
    this.enabled = false,
  });

  bool get isConfigured => false;

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
    lastError = 'Desktop link not supported on this platform';
  }

  void dispose() {}
}
