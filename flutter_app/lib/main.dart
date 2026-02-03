import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'ble_service.dart';
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
  int _index = 0;
  String _token = '1234';
  bool _autoArm = false;
  bool _prefsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  @override
  void dispose() {
    _ble.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _token = prefs.getString('token') ?? '1234';
      _autoArm = prefs.getBool('autoArm') ?? false;
      _prefsLoaded = true;
    });
  }

  Future<void> _savePrefs(String token, bool autoArm) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setBool('autoArm', autoArm);
  }

  Future<void> _openSettings() async {
    final tokenController = TextEditingController(text: _token);
    bool autoArm = _autoArm;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Settings'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Column(
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
                ],
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
                if (token.isEmpty) return;
                _savePrefs(token, autoArm);
                setState(() {
                  _token = token;
                  _autoArm = autoArm;
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
          )
        : _index == 1
            ? ControlScreen(
                ble: _ble,
                token: _token,
              )
            : StatusScreen(
                ble: _ble,
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

  const ScanScreen({
    super.key,
    required this.ble,
    required this.token,
    required this.autoArm,
  });

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _showAll = false;

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
              ),
              const SizedBox(height: 12),
              Expanded(
                child: shown.isEmpty
                    ? Center(
                        child: Text(emptyMessage),
                      )
                    : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (context, index) {
                          final result = shown[index];
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
  final String token;

  const ControlScreen({
    super.key,
    required this.ble,
    required this.token,
  });

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  final TextEditingController _typeController = TextEditingController();
  String _lastSent = '';

  bool _macroRunning = false;
  bool _cancelMacro = false;
  int _macroIndex = 0;
  int _macroTotal = 0;
  String _macroName = '';
  String _macroStatus = '';

  String _wrapCommand(String cmd) => 'TOKEN=${widget.token};$cmd\n';

  Future<void> _send(String cmd) async {
    if (!widget.ble.isConnected) {
      _showSnack('Not connected');
      return;
    }
    try {
      await widget.ble.writeLine(cmd);
      setState(() => _lastSent = cmd.trim());
    } catch (e) {
      _showSnack('Send failed: $e');
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _runMacro(Macro macro) async {
    if (_macroRunning) return;
    if (!widget.ble.isConnected) {
      _showSnack('Not connected');
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
      if (!widget.ble.isConnected) {
        _showSnack('Disconnected during macro');
        break;
      }

      final template = macro.lines[i].template;
      final line = template.replaceAll('{TOKEN}', widget.token);
      final withNewline = line.endsWith('\n') ? line : '$line\n';

      try {
        await widget.ble.writeLine(withNewline);
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.ble,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    widget.ble.isConnected
                        ? Icons.bluetooth_connected
                        : Icons.bluetooth_disabled,
                    color: widget.ble.isConnected ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.ble.isConnected
                        ? 'Connected'
                        : 'Not connected',
                  ),
                ],
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
                          Text('Last: ${_lastSent.isEmpty ? '-': _lastSent}'),
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
                            onPressed: () => _send(_wrapCommand('HOTKEY:CTRL+ALT+T')),
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
              Row(
                children: [
                  Text(
                    'Macros',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
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
              Expanded(
                child: ListView.builder(
                  itemCount: predefinedMacros.length,
                  itemBuilder: (context, index) {
                    final macro = predefinedMacros[index];
                    return Card(
                      child: ListTile(
                        title: Text(macro.name),
                        subtitle: macro.description != null
                            ? Text(macro.description!)
                            : null,
                        trailing: const Icon(Icons.play_arrow),
                        onTap: _macroRunning ? null : () => _runMacro(macro),
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

class StatusScreen extends StatefulWidget {
  final BleService ble;
  final String token;

  const StatusScreen({
    super.key,
    required this.ble,
    required this.token,
  });

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  bool _refreshing = false;
  bool _testing = false;
  String _testResult = '';

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
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
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



