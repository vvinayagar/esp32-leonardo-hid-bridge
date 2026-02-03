import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BleService extends ChangeNotifier {
  static final Guid serviceUuid = Guid('6E400001-B5A3-F393-E0A9-E50E24DCCA9E');
  static final Guid writeUuid = Guid('6E400002-B5A3-F393-E0A9-E50E24DCCA9E');

  final List<ScanResult> _results = [];
  bool _isScanning = false;
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  String? _lastError;
  bool? _isSupported;
  bool? _permissionsGranted;
  PermissionStatus? _scanPermission;
  PermissionStatus? _connectPermission;
  bool _hasService = false;
  bool _hasWriteChar = false;
  bool _discovering = false;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChar;
  BluetoothConnectionState _deviceState =
      BluetoothConnectionState.disconnected;

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _stateSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;

  BleService() {
    _adapterSub = FlutterBluePlus.adapterState.listen(
      (state) {
        _adapterState = state;
        if (state != BluetoothAdapterState.on && _isScanning) {
          FlutterBluePlus.stopScan().catchError((_) {});
          _isScanning = false;
        }
        notifyListeners();
      },
      onError: (error) {
        _lastError = 'Bluetooth state error: $error';
        notifyListeners();
      },
    );
    refreshStatus();
  }

  List<ScanResult> get scanResults => List.unmodifiable(_results);
  bool get isScanning => _isScanning;
  BluetoothDevice? get device => _device;
  BluetoothConnectionState get deviceState => _deviceState;
  bool get isConnected => _deviceState == BluetoothConnectionState.connected;
  BluetoothAdapterState get adapterState => _adapterState;
  String? get lastError => _lastError;
  bool? get isSupported => _isSupported;
  bool? get permissionsGranted => _permissionsGranted;
  PermissionStatus? get scanPermission => _scanPermission;
  PermissionStatus? get connectPermission => _connectPermission;
  bool get hasService => _hasService;
  bool get hasWriteChar => _hasWriteChar;

  void _setError(String message) {
    _lastError = message;
    notifyListeners();
  }

  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  Future<void> refreshStatus({bool requestPermissions = false}) async {
    try {
      _isSupported = await FlutterBluePlus.isSupported;
    } catch (e) {
      _isSupported = null;
      _setError('Bluetooth support check failed: $e');
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      _scanPermission = requestPermissions
          ? await Permission.bluetoothScan.request()
          : await Permission.bluetoothScan.status;
      _connectPermission = requestPermissions
          ? await Permission.bluetoothConnect.request()
          : await Permission.bluetoothConnect.status;
      _permissionsGranted =
          (_scanPermission?.isGranted ?? false) &&
          (_connectPermission?.isGranted ?? false);
    } else {
      _permissionsGranted = true;
      _scanPermission = null;
      _connectPermission = null;
    }

    notifyListeners();
  }

  Future<bool> ensurePermissions() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;

    final scanStatus = await Permission.bluetoothScan.request();
    final connectStatus = await Permission.bluetoothConnect.request();
    _scanPermission = scanStatus;
    _connectPermission = connectStatus;
    _permissionsGranted =
        scanStatus.isGranted && connectStatus.isGranted;
    notifyListeners();

    if (scanStatus.isGranted && connectStatus.isGranted) {
      return true;
    }

    _setError('Bluetooth permission denied. Enable Bluetooth permissions in Settings.');
    return false;
  }

  Future<bool> ensureBluetoothOn() async {
    final supported = await FlutterBluePlus.isSupported;
    if (!supported) {
      _setError('Bluetooth not supported on this device.');
      return false;
    }

    final state = await FlutterBluePlus.adapterState.first;
    if (state == BluetoothAdapterState.on) {
      return true;
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await FlutterBluePlus.turnOn();
        return true;
      } catch (e) {
        _setError('Bluetooth is off. Please enable it to scan.');
        return false;
      }
    }

    _setError('Bluetooth is off. Turn it on in system settings.');
    return false;
  }

  Future<void> requestEnableBluetooth() async {
    clearError();
    await ensureBluetoothOn();
  }

  Future<void> startScan() async {
    _results.clear();
    clearError();

    final permissionsOk = await ensurePermissions();
    if (!permissionsOk) return;

    final bluetoothOk = await ensureBluetoothOn();
    if (!bluetoothOk) return;

    _isScanning = true;
    notifyListeners();

    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
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

    try {
      await FlutterBluePlus.startScan();
    } catch (e) {
      _setError('Scan failed: $e');
      _isScanning = false;
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    _isScanning = false;
    notifyListeners();
  }

  Future<void> connect(ScanResult result) async {
    clearError();
    final permissionsOk = await ensurePermissions();
    if (!permissionsOk) {
      throw Exception(_lastError ?? 'Bluetooth permission denied');
    }

    final bluetoothOk = await ensureBluetoothOn();
    if (!bluetoothOk) {
      throw Exception(_lastError ?? 'Bluetooth is off');
    }

    await stopScan();

    _attachDevice(result.device);
    await _stateSub?.cancel();
    _stateSub = _device!.connectionState.listen((state) {
      _deviceState = state;
      if (state == BluetoothConnectionState.disconnected) {
        _writeChar = null;
        _hasService = false;
        _hasWriteChar = false;
      }
      notifyListeners();
    });

    await _device!.connect(autoConnect: false);
    _deviceState = BluetoothConnectionState.connected;
    notifyListeners();

    await _discoverAndCache();
  }

  Future<void> connectById(String remoteId, {bool autoConnect = true}) async {
    clearError();
    final permissionsOk = await ensurePermissions();
    if (!permissionsOk) {
      throw Exception(_lastError ?? 'Bluetooth permission denied');
    }

    final bluetoothOk = await ensureBluetoothOn();
    if (!bluetoothOk) {
      throw Exception(_lastError ?? 'Bluetooth is off');
    }

    await stopScan();
    _attachDevice(BluetoothDevice.fromId(remoteId));

    await _device!.connect(
      autoConnect: autoConnect,
      mtu: autoConnect ? null : 512,
    );

    if (_device!.isConnected) {
      _deviceState = BluetoothConnectionState.connected;
      notifyListeners();
      await _discoverAndCache();
    }
  }

  Future<void> disconnect() async {
    if (_device != null) {
      await _device!.disconnect(queue: false);
    }
    _deviceState = BluetoothConnectionState.disconnected;
    _writeChar = null;
    _hasService = false;
    _hasWriteChar = false;
    notifyListeners();
  }

  Future<void> writeLine(String line) async {
    if (_writeChar == null) {
      throw Exception('Not connected to write characteristic');
    }
    final value = utf8.encode(line);
    final withoutResponse = _writeChar!.properties.writeWithoutResponse;
    final mtu = _device?.mtuNow ?? 23;
    final maxPayload = (mtu - 3).clamp(1, 512);
    final chunkSize = withoutResponse
        ? (maxPayload < 20 ? maxPayload : 20)
        : maxPayload;

    for (var offset = 0; offset < value.length; offset += chunkSize) {
      final end = (offset + chunkSize) > value.length
          ? value.length
          : offset + chunkSize;
      final chunk = value.sublist(offset, end);
      await _writeChar!.write(chunk, withoutResponse: withoutResponse);
      if (withoutResponse && end < value.length) {
        await Future.delayed(const Duration(milliseconds: 8));
      }
    }
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _stateSub?.cancel();
    _adapterSub?.cancel();
    super.dispose();
  }

  void _attachDevice(BluetoothDevice device) {
    _device = device;
    _hasService = false;
    _hasWriteChar = false;
    _writeChar = null;
    _stateSub?.cancel();
    _stateSub = _device!.connectionState.listen((state) {
      _deviceState = state;
      if (state == BluetoothConnectionState.connected) {
        _discoverAndCache().catchError(
          (e) => _setError('Service discovery failed: $e'),
        );
      } else if (state == BluetoothConnectionState.disconnected) {
        _writeChar = null;
        _hasService = false;
        _hasWriteChar = false;
      }
      notifyListeners();
    });
  }

  Future<void> _discoverAndCache() async {
    if (_device == null || _discovering) return;
    _discovering = true;
    try {
      final services = await _device!.discoverServices();
      for (final service in services) {
        if (service.uuid == serviceUuid) {
          _hasService = true;
          for (final char in service.characteristics) {
            if (char.uuid == writeUuid) {
              _writeChar = char;
              _hasWriteChar = true;
              notifyListeners();
              _discovering = false;
              return;
            }
          }
        }
      }
    } finally {
      _discovering = false;
    }

    throw Exception('Write characteristic not found');
  }
}
