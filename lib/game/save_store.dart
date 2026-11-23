import 'save_store_stub.dart'
    if (dart.library.io) 'save_store_io.dart'
    if (dart.library.html) 'save_store_web.dart';

/// Tiny synchronous key-value store used for high scores and settings.
///
/// The concrete implementation is picked at compile time: `dart:io` writes a
/// small JSON file under the user's home directory, the web build uses
/// `localStorage`, and every other target falls back to memory (no crash, no
/// persistence). All implementations swallow platform errors so a read-only
/// filesystem or a browser with storage disabled can never take the game down.
abstract class SaveStore {
  const SaveStore();

  /// Reads the raw value stored under [key], or `null` when unset.
  String? read(String key);

  /// Stores [value] under [key]. Failures are ignored.
  void write(String key, String value);

  /// Platform default: file on native, `localStorage` on the JS web build,
  /// memory everywhere else.
  static SaveStore create() => createSaveStore();
}

/// No-op store: handy for tests and the UI preview harness.
class InMemorySaveStore extends SaveStore {
  InMemorySaveStore();

  final Map<String, String> _values = <String, String>{};

  @override
  String? read(String key) => _values[key];

  @override
  void write(String key, String value) {
    _values[key] = value;
  }
}
