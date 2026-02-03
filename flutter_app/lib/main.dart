import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'ble_service.dart';
import 'desktop_link.dart';
import 'macro_store.dart';
import 'models.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP HID Bridge',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final BleService _ble = BleService();
  final DesktopLink _desktop = DesktopLink();
  final MacroStore _macroStore = MacroStore();
  int _index = 0;
  String _token = '1234';
  bool _autoArm = false;
  String _desktopHost = '';
  int _desktopPort = 51515;
  bool _desktopEnabled = false;
  String? _lastDeviceId;
  List<Macro> _customMacros = [];
  bool _prefsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  @override
  void dispose() {
    _ble.dispose();
    _desktop.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final macros = await _macroStore.load();
    setState(() {
      _token = prefs.getString('token') ?? '1234';
      _autoArm = prefs.getBool('autoArm') ?? false;
      _desktopHost = prefs.getString('desktopHost') ?? '';
      _desktopPort = prefs.getInt('desktopPort') ?? 51515;
      _desktopEnabled = prefs.getBool('desktopEnabled') ?? false;
      _lastDeviceId = prefs.getString('lastDeviceId');
      _customMacros = macros;
      _desktop.configure(
        host: _desktopHost,
        port: _desktopPort,
        enabled: _desktopEnabled,
      );
      _prefsLoaded = true;
    });
  }

  Future<void> _savePrefs(
    String token,
    bool autoArm,
    String desktopHost,
    int desktopPort,
    bool desktopEnabled,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setBool('autoArm', autoArm);
    await prefs.setString('desktopHost', desktopHost);
    await prefs.setInt('desktopPort', desktopPort);
    await prefs.setBool('desktopEnabled', desktopEnabled);
  }

  Future<void> _updateCustomMacros(List<Macro> macros) async {
    await _macroStore.save(macros);
    if (mounted) {
      setState(() => _customMacros = macros);
    }
  }

  Future<void> _saveLastDeviceId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastDeviceId', id);
    if (mounted) {
      setState(() => _lastDeviceId = id);
    }
  }

  Future<void> _forgetLastDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('lastDeviceId');
    if (mounted) {
      setState(() => _lastDeviceId = null);
    }
  }

  Future<void> _openSettings() async {
    final tokenController = TextEditingController(text: _token);
    final hostController = TextEditingController(text: _desktopHost);
    final portController = TextEditingController(text: '$_desktopPort');
    bool autoArm = _autoArm;
    bool desktopEnabled = _desktopEnabled;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Settings'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: tokenController,
                      decoration: const InputDecoration(
                        labelText: 'Token',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Auto ARM on connect'),
                      value: autoArm,
                      onChanged: (value) => setState(() => autoArm = value),
                    ),
                    const Divider(height: 24),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Desktop Link (Wi-Fi)',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: hostController,
                      decoration: const InputDecoration(
                        labelText: 'Desktop Host / IP',
                        hintText: '192.168.1.10',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: portController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Desktop Port',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Enable desktop link'),
                      value: desktopEnabled,
                      onChanged: (value) => setState(() => desktopEnabled = value),
                    ),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final token = tokenController.text.trim();
                final host = hostController.text.trim();
                final port = int.tryParse(portController.text.trim()) ?? 51515;
                if (token.isEmpty) return;
                _savePrefs(token, autoArm, host, port, desktopEnabled);
                setState(() {
                  _token = token;
                  _autoArm = autoArm;
                  _desktopHost = host;
                  _desktopPort = port;
                  _desktopEnabled = desktopEnabled;
                  _desktop.configure(
                    host: host,
                    port: port,
                    enabled: desktopEnabled,
                  );
                });
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _index == 0
        ? ScanScreen(
            ble: _ble,
            token: _token,
            autoArm: _autoArm,
            lastDeviceId: _lastDeviceId,
            onDeviceConnected: _saveLastDeviceId,
            onForgetDevice: _forgetLastDevice,
          )
        : _index == 1
            ? ControlScreen(
                ble: _ble,
                desktop: _desktop,
                token: _token,
                customMacros: _customMacros,
                onCustomMacrosChanged: _updateCustomMacros,
              )
            : StatusScreen(
                ble: _ble,
                desktop: _desktop,
                token: _token,
              );

    if (!_prefsLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('ESP HID Bridge'),
        actions: [
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: body,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (value) => setState(() => _index = value),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.bluetooth_searching),
            label: 'Scan',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.keyboard),
            label: 'Control',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.health_and_safety),
            label: 'Status',
          ),
        ],
      ),
    );
  }
}

class ScanScreen extends StatefulWidget {
  final BleService ble;
  final String token;
  final bool autoArm;
  final String? lastDeviceId;
  final ValueChanged<String> onDeviceConnected;
  final VoidCallback onForgetDevice;

  const ScanScreen({
    super.key,
    required this.ble,
    required this.token,
    required this.autoArm,
    required this.lastDeviceId,
    required this.onDeviceConnected,
    required this.onForgetDevice,
  });

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _showAll = false;
  bool _autoConnectTried = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryAutoConnect();
    });
  }

  Future<void> _tryAutoConnect() async {
    if (_autoConnectTried) return;
    final id = widget.lastDeviceId;
    if (id == null || id.trim().isEmpty) return;
    _autoConnectTried = true;
    try {
      await widget.ble.connectById(id.trim(), autoConnect: true);
      if (widget.autoArm) {
        await widget.ble.writeLine('TOKEN=${widget.token};ARM:ON\n');
      }
    } catch (_) {
      // If auto-connect fails, user can still scan and connect manually.
    }
  }

  String _rawName(ScanResult result) {
    final deviceName = result.device.name;
    if (deviceName.isNotEmpty) return deviceName;
    final advName = result.advertisementData.localName;
    if (advName.isNotEmpty) return advName;
    return '';
  }

  String _displayName(ScanResult result) {
    final name = _rawName(result);
    return name.isNotEmpty ? name : 'Unnamed device';
  }

  bool _isEspHid(ScanResult result) {
    final name = _rawName(result).toLowerCase();
    return name.contains('esp-hid');
  }

  String _adapterLabel(BluetoothAdapterState state) {
    switch (state) {
      case BluetoothAdapterState.on:
        return 'On';
      case BluetoothAdapterState.off:
        return 'Off';
      case BluetoothAdapterState.unauthorized:
        return 'Unauthorized';
      case BluetoothAdapterState.unavailable:
        return 'Unavailable';
      case BluetoothAdapterState.turningOn:
        return 'Turning on...';
      case BluetoothAdapterState.turningOff:
        return 'Turning off...';
      default:
        return 'Unknown';
    }
  }

  Future<void> _connect(BuildContext context, ScanResult result) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.ble.connect(result);
      widget.onDeviceConnected(result.device.id.id);
      if (widget.autoArm) {
        await widget.ble.writeLine('TOKEN=${widget.token};ARM:ON\n');
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Connect failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.ble,
      builder: (context, _) {
        final allResults = widget.ble.scanResults;
        final filtered = allResults.where(_isEspHid).toList();
        final shown = _showAll ? allResults : filtered;
        final hasAny = allResults.isNotEmpty;
        final emptyMessage = _showAll
            ? 'No Bluetooth devices found.'
            : hasAny
                ? 'Devices found, but none match "ESP-HID".'
                : 'No ESP-HID devices found.';
        final adapterState = widget.ble.adapterState;
        final adapterOn = adapterState == BluetoothAdapterState.on;
        final canRequestEnable =
            !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
        final countLabel = _showAll
            ? 'Devices: ${allResults.length}'
            : 'ESP-HID: ${filtered.length} / ${allResults.length}';
        final connectedDevice = widget.ble.device;
        final connectedName = connectedDevice?.name?.isNotEmpty == true
            ? connectedDevice!.name
            : 'Connected device';
        final connectedId = connectedDevice?.id.id;
        final shownFiltered = connectedId == null
            ? shown
            : shown
                .where((result) => result.device.id.id != connectedId)
                .toList();
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed:
                        widget.ble.isScanning ? null : widget.ble.startScan,
                    icon: const Icon(Icons.search),
                    label: const Text('Start Scan'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed:
                        widget.ble.isScanning ? widget.ble.stopScan : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.ble.isScanning ? 'Scanning...' : 'Scan idle',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show all BLE devices'),
                value: _showAll,
                onChanged: (value) => setState(() => _showAll = value),
              ),
              Text(
                countLabel,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    adapterOn ? Icons.bluetooth : Icons.bluetooth_disabled,
                    color: adapterOn ? Colors.blue : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Text('Bluetooth: ${_adapterLabel(adapterState)}'),
                  const Spacer(),
                  if (!adapterOn && canRequestEnable)
                    TextButton.icon(
                      onPressed: widget.ble.requestEnableBluetooth,
                      icon: const Icon(Icons.power),
                      label: const Text('Enable'),
                    ),
                ],
              ),
              if (widget.ble.lastError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(
                    widget.ble.lastError!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                widget.ble.isConnected
                    ? 'Connected: ${widget.ble.device?.name ?? 'Unknown'}'
                    : 'Not connected',
                style: Theme.of(context).textTheme.bodyMedium,
                maxLines: 2,
                softWrap: true,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: shownFiltered.isEmpty && connectedDevice == null
                    ? Center(
                        child: Text(emptyMessage),
                      )
                    : ListView.builder(
                        itemCount:
                            shownFiltered.length + (connectedDevice != null ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (connectedDevice != null && index == 0) {
                            return Card(
                              child: ListTile(
                                leading: Icon(
                                  Icons.bluetooth_connected,
                                  color: Colors.green.shade700,
                                ),
                                title: Text(
                                  connectedName,
                                  maxLines: 2,
                                  softWrap: true,
                                ),
                                subtitle: Text(connectedDevice.id.id),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextButton(
                                      onPressed: widget.ble.disconnect,
                                      child: const Text('Disconnect'),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton(
                                      onPressed: () async {
                                        await widget.ble.disconnect();
                                        widget.onForgetDevice();
                                      },
                                      child: const Text('Forget'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          final offset = connectedDevice != null ? 1 : 0;
                          final result = shownFiltered[index - offset];
                          final isConnected =
                              widget.ble.isConnected &&
                              widget.ble.device?.id == result.device.id;
                          return Card(
                            child: ListTile(
                              title: Text(_displayName(result)),
                              subtitle: Text(result.device.id.id),
                              trailing: isConnected
                                  ? ElevatedButton(
                                      onPressed: widget.ble.disconnect,
                                      child: const Text('Disconnect'),
                                    )
                                  : ElevatedButton(
                                      onPressed: () => _connect(context, result),
                                      child: const Text('Connect'),
                                    ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class ControlScreen extends StatefulWidget {
  final BleService ble;
  final DesktopLink desktop;
  final String token;
  final List<Macro> customMacros;
  final ValueChanged<List<Macro>> onCustomMacrosChanged;

  const ControlScreen({
    super.key,
    required this.ble,
    required this.desktop,
    required this.token,
    required this.customMacros,
    required this.onCustomMacrosChanged,
  });

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  final TextEditingController _typeController = TextEditingController();
  String _lastSent = '';

  bool _sendBle = true;
  bool _sendDesktop = false;

  bool _dragMode = false;
  bool _scrollMode = false;
  double _trackpadSensitivity = 1.0;
  double _airMouseSensitivity = 1.0;
  bool _airMouseEnabled = false;
  StreamSubscription<UserAccelerometerEvent>? _airSub;
  DateTime _lastAirSend = DateTime.fromMillisecondsSinceEpoch(0);
  double _airDx = 0;
  double _airDy = 0;
  double _airVelX = 0;
  double _airVelY = 0;
  DateTime _airLastSample = DateTime.fromMillisecondsSinceEpoch(0);
  bool _airInvertX = true;
  bool _airInvertY = true;
  DateTime _lastTrackpadSend = DateTime.fromMillisecondsSinceEpoch(0);
  double _trackpadDx = 0;
  double _trackpadDy = 0;

  bool _macroRunning = false;
  bool _cancelMacro = false;
  int _macroIndex = 0;
  int _macroTotal = 0;
  String _macroName = '';
  String _macroStatus = '';

  @override
  void initState() {
    super.initState();
    _sendDesktop = widget.desktop.enabled;
  }

  @override
  void didUpdateWidget(covariant ControlScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.desktop.enabled != widget.desktop.enabled &&
        !widget.desktop.enabled) {
      setState(() => _sendDesktop = false);
    }
  }

  @override
  void dispose() {
    _airSub?.cancel();
    super.dispose();
  }

  String _wrapCommand(String cmd) => 'TOKEN=${widget.token};$cmd\n';

  bool _hasActiveTarget() {
    final bleOk = _sendBle && widget.ble.isConnected;
    final desktopOk = _sendDesktop && widget.desktop.isConfigured;
    return bleOk || desktopOk;
  }

  Future<void> _sendCommand(String command) async {
    await _send(_wrapCommand(command));
  }

  Future<void> _sendMouseMove(int dx, int dy) async {
    dx = dx.clamp(-127, 127).toInt();
    dy = dy.clamp(-127, 127).toInt();
    if (dx == 0 && dy == 0) return;
    await _sendCommand('MOUSE:MOVE:$dx,$dy');
  }

  Future<void> _sendMouseScroll(int dy) async {
    dy = dy.clamp(-127, 127).toInt();
    if (dy == 0) return;
    await _sendCommand('MOUSE:SCROLL:$dy');
  }

  Future<void> _sendMouseButton(String action, String button) async {
    await _sendCommand('MOUSE:$action:$button');
  }

  Future<void> _send(String cmd) async {
    final trimmed = cmd.trim();
    final errors = <String>[];
    var sent = false;

    if (_sendBle) {
      if (!widget.ble.isConnected) {
        errors.add('BLE not connected');
      } else {
        try {
          await widget.ble.writeLine(cmd);
          sent = true;
        } catch (e) {
          errors.add('BLE send failed: $e');
        }
      }
    }

    if (_sendDesktop) {
      if (!widget.desktop.isConfigured) {
        errors.add('Desktop link not configured');
      } else {
        try {
          await widget.desktop.send(cmd);
          sent = true;
        } catch (e) {
          errors.add('Desktop send failed: $e');
        }
      }
    }

    if (!sent) {
      _showSnack(errors.isNotEmpty ? errors.join(' | ') : 'No active targets');
      return;
    }
    setState(() => _lastSent = trimmed);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _runMacro(Macro macro) async {
    if (_macroRunning) return;
    if (!_hasActiveTarget()) {
      _showSnack('No active targets');
      return;
    }

    setState(() {
      _macroRunning = true;
      _cancelMacro = false;
      _macroIndex = 0;
      _macroTotal = macro.lines.length;
      _macroName = macro.name;
      _macroStatus = 'Running macro...';
    });

    for (var i = 0; i < macro.lines.length; i++) {
      if (_cancelMacro) break;
      if (!_hasActiveTarget()) {
        _showSnack('No active targets');
        break;
      }

      final command = macro.lines[i].command.trim();
      if (command.isEmpty) {
        continue;
      }
      final withNewline = _wrapCommand(command);

      try {
        await _send(withNewline);
        setState(() {
          _macroIndex = i + 1;
          _lastSent = withNewline.trim();
        });
      } catch (e) {
        _showSnack('Macro failed: $e');
        break;
      }

      await Future.delayed(const Duration(milliseconds: 120));
    }

    setState(() {
      if (_cancelMacro) {
        _macroStatus = 'Macro canceled';
      } else {
        _macroStatus = 'Macro finished';
      }
      _macroRunning = false;
    });
  }

  void _stopMacro() {
    if (!_macroRunning) return;
    setState(() {
      _cancelMacro = true;
      _macroStatus = 'Stopping macro...';
    });
  }

  Future<void> _toggleAirMouse(bool enabled) async {
    if (enabled == _airMouseEnabled) return;
    setState(() => _airMouseEnabled = enabled);
    await _airSub?.cancel();
    _airSub = null;
    _airDx = 0;
    _airDy = 0;
    _airVelX = 0;
    _airVelY = 0;
    _airLastSample = DateTime.now();
    if (!enabled) return;

    _airSub = userAccelerometerEvents.listen(
      (event) {
        if (!_hasActiveTarget()) return;
        final scale = 35.0 * _airMouseSensitivity;
        const velocityDamping = 0.85;
        const deadZone = 0.08;
        const maxVelocity = 40.0;
        final rawX = _airInvertX ? -event.x : event.x;
        final rawY = _airInvertY ? -event.y : event.y;
        final ax = rawX.abs() < deadZone ? 0.0 : rawX;
        final ay = rawY.abs() < deadZone ? 0.0 : rawY;
        final nowSample = DateTime.now();
        final dtMs = nowSample.difference(_airLastSample).inMilliseconds;
        final dt = (dtMs <= 0 ? 16 : dtMs).clamp(8, 50) / 1000.0;
        _airLastSample = nowSample;
        _airVelX = (_airVelX + (ax * scale * dt)) * velocityDamping;
        _airVelY = (_airVelY + (ay * scale * dt)) * velocityDamping;
        _airVelX = _airVelX.clamp(-maxVelocity, maxVelocity);
        _airVelY = _airVelY.clamp(-maxVelocity, maxVelocity);
        _airDx += _airVelX;
        _airDy += _airVelY;
        final now = DateTime.now();
        if (now.difference(_lastAirSend).inMilliseconds < 20) {
          return;
        }
        final dx = _airDx.round().clamp(-127, 127).toInt();
        final dy = _airDy.round().clamp(-127, 127).toInt();
        _airDx -= dx;
        _airDy -= dy;
        _lastAirSend = now;
        _sendMouseMove(dx, dy);
      },
      onError: (_) {},
    );
  }

  void _handleTrackpadDelta(Offset delta) {
    if (!_hasActiveTarget()) return;
    final scale = _trackpadSensitivity;
    _trackpadDx += delta.dx * scale;
    _trackpadDy += delta.dy * scale;
    final now = DateTime.now();
    if (now.difference(_lastTrackpadSend).inMilliseconds < 12) {
      return;
    }
    final dx = _trackpadDx.round().clamp(-127, 127).toInt();
    final dy = _trackpadDy.round().clamp(-127, 127).toInt();
    _trackpadDx = 0;
    _trackpadDy = 0;
    _lastTrackpadSend = now;
    if (_scrollMode) {
      _sendMouseScroll(dy);
    } else {
      _sendMouseMove(dx, dy);
    }
  }

  List<String> _normalizeCommands(String raw) {
    final lines = raw.split('\n');
    final commands = <String>[];
    for (var line in lines) {
      var trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('TOKEN=')) {
        final idx = trimmed.indexOf(';');
        if (idx >= 0 && idx + 1 < trimmed.length) {
          trimmed = trimmed.substring(idx + 1).trim();
        }
      }
      if (trimmed.isEmpty) continue;
      commands.add(trimmed);
    }
    return commands;
  }

  Future<Macro?> _openMacroEditor({Macro? existing}) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final descriptionController =
        TextEditingController(text: existing?.description ?? '');
    final commandsController = TextEditingController(
      text: existing == null
          ? ''
          : existing.lines.map((line) => line.command).join('\n'),
    );

    var mode = 'commands';
    var passwordValue = '';
    var appendEnter = false;

    if (existing != null) {
      final commands = existing.lines.map((line) => line.command).toList();
      if (commands.isNotEmpty && commands.first.startsWith('TYPE:')) {
        final candidate = commands.first.substring(5);
        final rest = commands.skip(1).toList();
        final onlyEnter =
            rest.isEmpty || (rest.length == 1 && rest.first == 'KEY:ENTER');
        if (onlyEnter) {
          mode = 'password';
          passwordValue = candidate;
          appendEnter = rest.isNotEmpty;
        }
      }
    }

    final passwordController = TextEditingController(text: passwordValue);

    final result = await showDialog<Macro>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(existing == null ? 'Add Macro' : 'Edit Macro'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Macro name',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: mode,
                      decoration: const InputDecoration(
                        labelText: 'Macro type',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'commands',
                          child: Text('Commands'),
                        ),
                        DropdownMenuItem(
                          value: 'password',
                          child: Text('Password'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() => mode = value ?? 'commands');
                      },
                    ),
                    const SizedBox(height: 12),
                    if (mode == 'password') ...[
                      TextField(
                        controller: passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                        ),
                      ),
                      SwitchListTile(
                        title: const Text('Append ENTER'),
                        value: appendEnter,
                        onChanged: (value) =>
                            setState(() => appendEnter = value),
                      ),
                    ] else ...[
                      TextField(
                        controller: commandsController,
                        decoration: const InputDecoration(
                          labelText: 'Commands (one per line)',
                          hintText: 'TYPE:hello\nKEY:ENTER',
                        ),
                        minLines: 3,
                        maxLines: 6,
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                final description = descriptionController.text.trim();
                final password = passwordController.text;
                if (name.isEmpty) return;

                final commands = mode == 'password'
                    ? <String>[
                        'TYPE:$password',
                        if (appendEnter) 'KEY:ENTER',
                      ]
                    : _normalizeCommands(commandsController.text);

                if (commands.isEmpty ||
                    (mode == 'password' && password.trim().isEmpty)) {
                  return;
                }

                final id = existing?.id ??
                    'custom_${DateTime.now().microsecondsSinceEpoch}';
                final macro = Macro(
                  id: id,
                  name: name,
                  description: description.isEmpty ? null : description,
                  lines: commands.map((cmd) => MacroLine(cmd)).toList(),
                  isCustom: true,
                );
                Navigator.pop(context, macro);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    return result;
  }

  Future<void> _addMacro() async {
    final macro = await _openMacroEditor();
    if (macro == null) return;
    final updated = [...widget.customMacros, macro];
    widget.onCustomMacrosChanged(updated);
  }

  Future<void> _editMacro(Macro macro) async {
    final updatedMacro = await _openMacroEditor(existing: macro);
    if (updatedMacro == null) return;
    final updated = widget.customMacros
        .map((item) => item.id == macro.id ? updatedMacro : item)
        .toList();
    widget.onCustomMacrosChanged(updated);
  }

  Future<void> _deleteMacro(Macro macro) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete macro?'),
          content: Text('Delete "${macro.name}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirm != true) return;
    final updated =
        widget.customMacros.where((item) => item.id != macro.id).toList();
    widget.onCustomMacrosChanged(updated);
  }

  Widget _buildMacroTile(Macro macro, {bool editable = false}) {
    return Card(
      child: ListTile(
        title: Text(
          macro.name,
          maxLines: 2,
          softWrap: true,
        ),
        subtitle: macro.description != null
            ? Text(
                macro.description!,
                maxLines: 2,
                softWrap: true,
              )
            : null,
        trailing: editable
            ? PopupMenuButton<String>(
                enabled: !_macroRunning,
                onSelected: (value) {
                  if (value == 'edit') {
                    _editMacro(macro);
                  } else if (value == 'delete') {
                    _deleteMacro(macro);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'edit',
                    child: Text('Edit'),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete'),
                  ),
                ],
              )
            : const Icon(Icons.play_arrow),
        onTap: _macroRunning ? null : () => _runMacro(macro),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.ble,
      builder: (context, _) {
        final bleConnected = widget.ble.isConnected;
        final desktopConfigured = widget.desktop.isConfigured;
        final desktopEnabled = widget.desktop.enabled;
        final desktopLabel = desktopConfigured
            ? '${widget.desktop.host}:${widget.desktop.port}'
            : 'Not configured';

        Widget sectionLabel(String text) => Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(
                text,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            );

        final macroWidgets = <Widget>[
          sectionLabel('Predefined'),
          ...predefinedMacros.map(_buildMacroTile),
          const SizedBox(height: 8),
          sectionLabel('Custom'),
          if (widget.customMacros.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('No custom macros yet. Tap Add to create one.'),
            ),
          ...widget.customMacros
              .map((macro) => _buildMacroTile(macro, editable: true)),
        ];

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Targets',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilterChip(
                          label: const Text('ESP32 BLE'),
                          selected: _sendBle,
                          avatar: Icon(
                            bleConnected
                                ? Icons.bluetooth_connected
                                : Icons.bluetooth_disabled,
                            size: 18,
                            color: bleConnected ? Colors.green : Colors.red,
                          ),
                          onSelected: (value) =>
                              setState(() => _sendBle = value),
                        ),
                        FilterChip(
                          label: const Text('Desktop Wi-Fi'),
                          selected: _sendDesktop && desktopEnabled,
                          avatar: const Icon(Icons.desktop_windows, size: 18),
                          onSelected: desktopEnabled
                              ? (value) =>
                                  setState(() => _sendDesktop = value)
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'BLE: ${bleConnected ? 'Connected' : 'Disconnected'}',
                      maxLines: 2,
                      softWrap: true,
                    ),
                    Text(
                      'Desktop: $desktopLabel',
                      maxLines: 2,
                      softWrap: true,
                    ),
                    if (_lastSent.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Last: $_lastSent',
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 2,
                          softWrap: true,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Manual Controls',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _typeController,
                      decoration: const InputDecoration(
                        labelText: 'Type text',
                        border: OutlineInputBorder(),
                      ),
                      minLines: 1,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: () {
                            final text = _typeController.text;
                            if (text.trim().isEmpty) return;
                            _send(_wrapCommand('TYPE:$text'));
                            _typeController.clear();
                          },
                          child: const Text('Send TYPE'),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _lastSent.isEmpty ? 'Last: -' : 'Last: $_lastSent',
                            maxLines: 2,
                            softWrap: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton(
                          onPressed: () => _send(_wrapCommand('ARM:ON')),
                          child: const Text('ARM ON'),
                        ),
                        ElevatedButton(
                          onPressed: () => _send(_wrapCommand('ARM:OFF')),
                          child: const Text('ARM OFF'),
                        ),
                        ElevatedButton(
                          onPressed: () => _send(_wrapCommand('KEY:ENTER')),
                          child: const Text('Enter'),
                        ),
                        ElevatedButton(
                          onPressed: () => _send(_wrapCommand('KEY:TAB')),
                          child: const Text('Tab'),
                        ),
                        ElevatedButton(
                          onPressed: () =>
                              _send(_wrapCommand('HOTKEY:CTRL+ALT+T')),
                          child: const Text('Ctrl+Alt+T'),
                        ),
                        ElevatedButton(
                          onPressed: () => _send(_wrapCommand('HOTKEY:WIN+R')),
                          child: const Text('Win+R'),
                        ),
                        ElevatedButton(
                          onPressed: () => _send(_wrapCommand('DELAY:500')),
                          child: const Text('Delay 500ms'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pointer Control',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('Air mouse'),
                        const Spacer(),
                        Switch(
                          value: _airMouseEnabled,
                          onChanged: _toggleAirMouse,
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Text('Air sensitivity'),
                        Expanded(
                          child: Slider(
                            value: _airMouseSensitivity,
                            min: 0.5,
                            max: 3.0,
                            divisions: 10,
                            label: _airMouseSensitivity.toStringAsFixed(1),
                            onChanged: (value) =>
                                setState(() => _airMouseSensitivity = value),
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Invert X'),
                      value: _airInvertX,
                      onChanged: (value) =>
                          setState(() => _airInvertX = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Invert Y'),
                      value: _airInvertY,
                      onChanged: (value) =>
                          setState(() => _airInvertY = value),
                    ),
                    const Divider(),
                    Row(
                      children: [
                        const Text('Trackpad'),
                        const Spacer(),
                        Text(
                          _scrollMode ? 'Scroll' : 'Move',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Scroll mode'),
                      value: _scrollMode,
                      onChanged: (value) =>
                          setState(() => _scrollMode = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Drag mode'),
                      value: _dragMode,
                      onChanged: (value) =>
                          setState(() => _dragMode = value),
                    ),
                    Row(
                      children: [
                        const Text('Trackpad sensitivity'),
                        Expanded(
                          child: Slider(
                            value: _trackpadSensitivity,
                            min: 0.5,
                            max: 3.0,
                            divisions: 10,
                            label: _trackpadSensitivity.toStringAsFixed(1),
                            onChanged: (value) =>
                                setState(() => _trackpadSensitivity = value),
                          ),
                        ),
                      ],
                    ),
                    GestureDetector(
                      onPanStart: (_) {
                        if (_dragMode) {
                          _sendMouseButton('DOWN', 'LEFT');
                        }
                      },
                      onPanEnd: (_) {
                        if (_dragMode) {
                          _sendMouseButton('UP', 'LEFT');
                        }
                      },
                      onPanUpdate: (details) =>
                          _handleTrackpadDelta(details.delta),
                      onTap: () => _sendMouseButton('CLICK', 'LEFT'),
                      onLongPress: () => _sendMouseButton('CLICK', 'RIGHT'),
                      child: Container(
                        height: 180,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade400),
                        ),
                        child: Center(
                          child: Text(
                            _scrollMode
                                ? 'Trackpad (scroll)'
                                : 'Trackpad (move)',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () => _sendMouseButton('CLICK', 'LEFT'),
                          child: const Text('Left Click'),
                        ),
                        OutlinedButton(
                          onPressed: () => _sendMouseButton('CLICK', 'RIGHT'),
                          child: const Text('Right Click'),
                        ),
                        OutlinedButton(
                          onPressed: () => _sendMouseButton('CLICK', 'MIDDLE'),
                          child: const Text('Middle Click'),
                        ),
                        OutlinedButton(
                          onPressed: () => _sendMouseScroll(-60),
                          child: const Text('Scroll Up'),
                        ),
                        OutlinedButton(
                          onPressed: () => _sendMouseScroll(60),
                          child: const Text('Scroll Down'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Macros',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: _addMacro,
                          icon: const Icon(Icons.add),
                          tooltip: 'Add macro',
                        ),
                        if (_macroRunning)
                          ElevatedButton.icon(
                            onPressed: _stopMacro,
                            icon: const Icon(Icons.stop),
                            label: const Text('Stop'),
                          ),
                      ],
                    ),
                    if (_macroRunning || _macroStatus.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 8),
                        child: Text(
                          _macroRunning
                              ? 'Running $_macroName ($_macroIndex/$_macroTotal)'
                              : _macroStatus,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ...macroWidgets,
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class StatusScreen extends StatefulWidget {
  final BleService ble;
  final DesktopLink desktop;
  final String token;

  const StatusScreen({
    super.key,
    required this.ble,
    required this.desktop,
    required this.token,
  });

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  bool _refreshing = false;
  bool _testing = false;
  String _testResult = '';
  bool _desktopTesting = false;
  String _desktopTestResult = '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  String _adapterLabel(BluetoothAdapterState state) {
    switch (state) {
      case BluetoothAdapterState.on:
        return 'On';
      case BluetoothAdapterState.off:
        return 'Off';
      case BluetoothAdapterState.unauthorized:
        return 'Unauthorized';
      case BluetoothAdapterState.unavailable:
        return 'Unavailable';
      case BluetoothAdapterState.turningOn:
        return 'Turning on...';
      case BluetoothAdapterState.turningOff:
        return 'Turning off...';
      default:
        return 'Unknown';
    }
  }

  String _supportedLabel(bool? supported) {
    if (supported == null) return 'Unknown';
    return supported ? 'Yes' : 'No';
  }

  String _permissionLabel(PermissionStatus? status) {
    if (status == null) return 'Unknown';
    if (status.isGranted) return 'Granted';
    if (status.isPermanentlyDenied) return 'Permanently denied';
    if (status.isDenied) return 'Denied';
    if (status.isRestricted) return 'Restricted';
    if (status.isLimited) return 'Limited';
    return status.toString();
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await widget.ble.refreshStatus();
    if (mounted) {
      setState(() => _refreshing = false);
    }
  }

  Future<void> _requestPermissions() async {
    setState(() => _refreshing = true);
    await widget.ble.ensurePermissions();
    await widget.ble.refreshStatus();
    if (mounted) {
      setState(() => _refreshing = false);
    }
  }

  Future<void> _enableBluetooth() async {
    await widget.ble.requestEnableBluetooth();
  }

  Future<void> _writeTest() async {
    if (!widget.ble.isConnected) {
      _showSnack('Not connected');
      return;
    }
    setState(() {
      _testing = true;
      _testResult = '';
    });
    try {
      await widget.ble.writeLine('TOKEN=${widget.token};DELAY:1\n');
      setState(() {
        _testResult = 'BLE write ok (no device feedback)';
      });
    } catch (e) {
      setState(() {
        _testResult = 'BLE write failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _testing = false);
      }
    }
  }

  Future<void> _desktopTest() async {
    if (!widget.desktop.isConfigured) {
      _showSnack('Desktop link not configured');
      return;
    }
    setState(() {
      _desktopTesting = true;
      _desktopTestResult = '';
    });
    try {
      await widget.desktop.send('TOKEN=${widget.token};DELAY:1\n');
      setState(() {
        _desktopTestResult = 'Desktop UDP send ok (no device feedback)';
      });
    } catch (e) {
      setState(() {
        _desktopTestResult = 'Desktop send failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _desktopTesting = false);
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _infoRow(String label, String value, {IconData? icon, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
          ],
          Expanded(child: Text(label)),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              softWrap: true,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.ble,
      builder: (context, _) {
        final ble = widget.ble;
        final isAndroid =
            !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
        final adapterOn = ble.adapterState == BluetoothAdapterState.on;
        final permissionsLabel = ble.permissionsGranted == true
            ? 'Granted'
            : ble.permissionsGranted == false
                ? 'Not granted'
                : 'Unknown';
        final connectedName = ble.device?.name?.isNotEmpty == true
            ? ble.device!.name
            : 'Unknown';

        return Padding(
          padding: const EdgeInsets.all(12),
          child: ListView(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bluetooth',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      _infoRow(
                        'Supported',
                        _supportedLabel(ble.isSupported),
                      ),
                      _infoRow(
                        'Adapter',
                        _adapterLabel(ble.adapterState),
                        icon: adapterOn
                            ? Icons.bluetooth
                            : Icons.bluetooth_disabled,
                        color: adapterOn ? Colors.blue : Colors.red,
                      ),
                      _infoRow(
                        'Permissions',
                        isAndroid ? permissionsLabel : 'Not required',
                      ),
                      if (isAndroid) ...[
                        _infoRow(
                          'Scan permission',
                          _permissionLabel(ble.scanPermission),
                        ),
                        _infoRow(
                          'Connect permission',
                          _permissionLabel(ble.connectPermission),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (ble.lastError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Text(
                    ble.lastError!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Connection',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      _infoRow(
                        'State',
                        ble.isConnected ? 'Connected' : 'Not connected',
                        icon: ble.isConnected
                            ? Icons.bluetooth_connected
                            : Icons.bluetooth_disabled,
                        color: ble.isConnected ? Colors.green : Colors.red,
                      ),
                      _infoRow('Device', connectedName),
                      if (ble.device != null)
                        _infoRow('Device ID', ble.device!.id.id),
                      _infoRow('Service found', ble.hasService ? 'Yes' : 'No'),
                      _infoRow(
                        'Write characteristic',
                        ble.hasWriteChar ? 'Yes' : 'No',
                      ),
                    ],
                  ),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Desktop Link',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      _infoRow(
                        'Enabled',
                        widget.desktop.enabled ? 'Yes' : 'No',
                      ),
                      _infoRow(
                        'Host',
                        widget.desktop.host.isNotEmpty
                            ? widget.desktop.host
                            : 'Not set',
                      ),
                      _infoRow('Port', widget.desktop.port.toString()),
                      _infoRow(
                        'Configured',
                        widget.desktop.isConfigured ? 'Yes' : 'No',
                      ),
                      if (widget.desktop.lastError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            widget.desktop.lastError!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed:
                            _desktopTesting ? null : _desktopTest,
                        icon: const Icon(Icons.play_arrow),
                        label:
                            Text(_desktopTesting ? 'Testing...' : 'Test desktop'),
                      ),
                      if (_desktopTestResult.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(_desktopTestResult),
                        ),
                    ],
                  ),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Actions',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _refreshing ? null : _refresh,
                            icon: const Icon(Icons.refresh),
                            label: Text(_refreshing ? 'Refreshing...' : 'Refresh'),
                          ),
                          if (isAndroid)
                            OutlinedButton.icon(
                              onPressed: _refreshing ? null : _requestPermissions,
                              icon: const Icon(Icons.lock_open),
                              label: const Text('Request permissions'),
                            ),
                          if (!adapterOn && isAndroid)
                            OutlinedButton.icon(
                              onPressed: _enableBluetooth,
                              icon: const Icon(Icons.power),
                              label: const Text('Enable Bluetooth'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'BLE Write Test',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Sends TOKEN + DELAY to check BLE write path. '
                        'This does not confirm ESP32->Leonardo or HID output.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _testing ? null : _writeTest,
                        icon: const Icon(Icons.play_arrow),
                        label: Text(_testing ? 'Testing...' : 'Run test'),
                      ),
                      if (_testResult.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(_testResult),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}



