import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

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
      body: _index == 0
          ? ScanScreen(
              ble: _ble,
              token: _token,
              autoArm: _autoArm,
            )
          : ControlScreen(
              ble: _ble,
              token: _token,
            ),
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
        ],
      ),
    );
  }
}

class ScanScreen extends StatelessWidget {
  final BleService ble;
  final String token;
  final bool autoArm;

  const ScanScreen({
    super.key,
    required this.ble,
    required this.token,
    required this.autoArm,
  });

  Future<void> _connect(BuildContext context, ScanResult result) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ble.connect(result);
      if (autoArm) {
        await ble.writeLine('TOKEN=$token;ARM:ON\n');
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Connect failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ble,
      builder: (context, _) {
        final filtered = ble.scanResults
            .where((r) => r.device.name.contains('ESP-HID'))
            .toList();
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: ble.isScanning ? null : ble.startScan,
                    icon: const Icon(Icons.search),
                    label: const Text('Start Scan'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: ble.isScanning ? ble.stopScan : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                ble.isScanning ? 'Scanning...' : 'Scan idle',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Text(
                ble.isConnected
                    ? 'Connected: ${ble.device?.name ?? 'Unknown'}'
                    : 'Not connected',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text('No ESP-HID devices found.'),
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final result = filtered[index];
                          final isConnected =
                              ble.isConnected && ble.device?.id == result.device.id;
                          return Card(
                            child: ListTile(
                              title: Text(
                                result.device.name.isNotEmpty
                                    ? result.device.name
                                    : 'Unnamed device',
                              ),
                              subtitle: Text(result.device.id.id),
                              trailing: isConnected
                                  ? ElevatedButton(
                                      onPressed: ble.disconnect,
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



