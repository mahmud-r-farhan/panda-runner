import 'dart:convert';
import 'dart:io';

import 'save_store.dart';

/// Desktop/mobile store: a tiny JSON document under `$HOME/.panda_runner`.
///
/// Inside the macOS app sandbox (and on iOS) `HOME` is already the app
/// container, so no extra entitlements are required.
SaveStore createSaveStore() => FileSaveStore();

class FileSaveStore extends SaveStore {
  FileSaveStore() : _file = _locateFile();

  final File _file;
  Map<String, String>? _cache;

  static File _locateFile() {
    final env = Platform.environment;
    var base = env['PANDA_RUNNER_HOME'];
    if (base == null || base.isEmpty) base = env['HOME'];
    if (base == null || base.isEmpty) base = env['USERPROFILE'];
    if (base == null || base.isEmpty) base = Directory.systemTemp.path;
    final dir = Directory('$base${Platform.pathSeparator}.panda_runner');
    return File('${dir.path}${Platform.pathSeparator}save.json');
  }

  Map<String, String> get _values {
    final cached = _cache;
    if (cached != null) return cached;
    final values = <String, String>{};
    try {
      if (_file.existsSync()) {
        final decoded = jsonDecode(_file.readAsStringSync());
        if (decoded is Map) {
          decoded.forEach((key, value) {
            if (key is String && value is String) values[key] = value;
          });
        }
      }
    } catch (_) {
      // Corrupt or unreadable save: start fresh, never crash.
    }
    return _cache = values;
  }

  @override
  String? read(String key) => _values[key];

  @override
  void write(String key, String value) {
    _values[key] = value;
    try {
      _file.parent.createSync(recursive: true);
      _file.writeAsStringSync(jsonEncode(_values));
    } catch (_) {
      // Read-only home or a full disk: keep the in-memory value only.
    }
  }
}
