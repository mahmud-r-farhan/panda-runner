// `dart:html` is the smallest dependency-free way to reach `localStorage`
// synchronously. It is used for the JS web build only; Wasm builds compile the
// stub implementation instead.
// ignore_for_file: deprecated_member_use

import 'dart:html' as html;

import 'save_store.dart';

SaveStore createSaveStore() => LocalStorageSaveStore();

class LocalStorageSaveStore extends SaveStore {
  @override
  String? read(String key) {
    try {
      return html.window.localStorage[key];
    } catch (_) {
      // Private mode / storage disabled.
      return null;
    }
  }

  @override
  void write(String key, String value) {
    try {
      html.window.localStorage[key] = value;
    } catch (_) {}
  }
}
