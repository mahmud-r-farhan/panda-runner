import 'save_store.dart';

/// Non-web, non-io fallback (e.g. Wasm web builds where `dart:html` is not
/// available). Keeps the game fully playable, just without persistence.
SaveStore createSaveStore() => InMemorySaveStore();
