import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models.dart';

class MacroStore {
  static const _storage = FlutterSecureStorage();
  static const _key = 'custom_macros_v1';

  Future<List<Macro>> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.trim().isEmpty) {
      return [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => _fromJson(item.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<Macro> macros) async {
    final payload = macros
        .map((macro) => {
              'id': macro.id,
              'name': macro.name,
              'description': macro.description,
              'lines': macro.lines.map((line) => line.command).toList(),
            })
        .toList();
    final raw = jsonEncode(payload);
    await _storage.write(key: _key, value: raw);
  }

  Macro _fromJson(Map<String, dynamic> json) {
    final lines = <MacroLine>[];
    final rawLines = json['lines'];
    if (rawLines is List) {
      for (final entry in rawLines) {
        if (entry is String && entry.trim().isNotEmpty) {
          lines.add(MacroLine(entry.trim()));
        }
      }
    }
    return Macro(
      id: (json['id'] as String?) ?? _newId(),
      name: (json['name'] as String?) ?? 'Custom Macro',
      description: json['description'] as String?,
      lines: lines,
      isCustom: true,
    );
  }

  String _newId() => 'custom_${DateTime.now().microsecondsSinceEpoch}';
}
