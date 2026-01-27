import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BleService extends ChangeNotifier {
  static final Guid serviceUuid = Guid('6E400001-B5A3-F393-E0A9-E50E24DCCA9E');
  static final Guid writeUuid = Guid('6E400002-B5A3-F393-E0A9-E50E24DCCA9E');

  final FlutterBluePlus _ble = FlutterBluePlus.instance;
  final List<ScanResult> _results = [];
  bool _isScanning = false;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChar;
  BluetoothDeviceState _deviceState = BluetoothDeviceState.disconnected;

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothDeviceState>? _stateSub;

  List<ScanResult> get scanResults => List.unmodifiable(_results);
  bool get isScanning => _isScanning;
  BluetoothDevice? get device => _device;
  BluetoothDeviceState get deviceState => _deviceState;
  bool get isConnected => _deviceState == BluetoothDeviceState.connected;

  Future<void> ensurePermissions() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;

    final scanStatus = await Permission.bluetoothScan.request();
    final connectStatus = await Permission.bluetoothConnect.request();

    if (!scanStatus.isGranted || !connectStatus.isGranted) {
      // Location permission is still required on older Android versions.
      await Permission.locationWhenInUse.request();
    }
  }

  Future<void> startScan() async {
    await ensurePermissions();
    _results.clear();
    _isScanning = true;
    notifyListeners();

    await _scanSub?.cancel();
    _scanSub = _ble.scanResults.listen((results) {
      for (final result in results) {
        final existingIndex = _results.indexWhere(
          (r) => r.device.id == result.device.id,
        );
        if (existingIndex >= 0) {
          _results[existingIndex] = result;
        } else {
          _results.add(result);
        }
      }
      notifyListeners();
    });

    await _ble.startScan(timeout: const Duration(seconds: 6));
    _isScanning = false;
    notifyListeners();
  }

  Future<void> stopScan() async {
    await _ble.stopScan();
    _isScanning = false;
    notifyListeners();
  }

  Future<void> connect(ScanResult result) async {
    await ensurePermissions();
    await stopScan();

    _device = result.device;
    await _stateSub?.cancel();
    _stateSub = _device!.state.listen((state) {
      _deviceState = state;
      if (state == BluetoothDeviceState.disconnected) {
        _writeChar = null;
      }
      notifyListeners();
    });

    await _device!.connect(autoConnect: false);
    _deviceState = BluetoothDeviceState.connected;
    notifyListeners();

    final services = await _device!.discoverServices();
    for (final service in services) {
      if (service.uuid == serviceUuid) {
        for (final char in service.characteristics) {
          if (char.uuid == writeUuid) {
            _writeChar = char;
            notifyListeners();
            return;
          }
        }
      }
    }

    throw Exception('Write characteristic not found');
  }

  Future<void> disconnect() async {
    if (_device != null) {
      await _device!.disconnect();
    }
    _deviceState = BluetoothDeviceState.disconnected;
    _writeChar = null;
    notifyListeners();
  }

  Future<void> writeLine(String line) async {
    if (_writeChar == null) {
      throw Exception('Not connected to write characteristic');
    }
    final value = utf8.encode(line);
    final withoutResponse = _writeChar!.properties.writeWithoutResponse;
    await _writeChar!.write(value, withoutResponse: withoutResponse);
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }
}
