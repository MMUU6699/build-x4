import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppPreferences {
  AppPreferences();

  static final Map<String, Object> _globalMemoryCache = <String, Object>{};

  @visibleForTesting
  static void resetForTesting() {
    _globalMemoryCache.clear();
  }

  SharedPreferences? _prefs;
  final Map<String, Object> _memoryCache = <String, Object>{};
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;

  Future<SharedPreferences?> _getPrefs() async {
    if (_prefs != null) return _prefs;
    try {
      _prefs = await SharedPreferences.getInstance().timeout(
        const Duration(milliseconds: 300),
      );
      return _prefs;
    } catch (_) {
      return null;
    }
  }

  Future<void> load() async {
    if (_isLoaded) return;
    await _getPrefs();
    _isLoaded = true;
  }

  Future<T> runWithRestoreWriteFence<T>(Future<T> Function() operation) async {
    return await operation();
  }

  String? getString(String key) {
    return (_memoryCache[key] as String?) ??
        (_globalMemoryCache[key] as String?) ??
        _prefs?.getString(key);
  }

  Future<bool> setString(String key, String value) async {
    _memoryCache[key] = value;
    _globalMemoryCache[key] = value;
    try {
      final p = await _getPrefs();
      if (p != null) await p.setString(key, value);
      return true;
    } catch (_) {
      return true;
    }
  }

  bool? getBool(String key) {
    return (_memoryCache[key] as bool?) ??
        (_globalMemoryCache[key] as bool?) ??
        _prefs?.getBool(key);
  }

  Future<bool> setBool(String key, bool value) async {
    _memoryCache[key] = value;
    _globalMemoryCache[key] = value;
    try {
      final p = await _getPrefs();
      if (p != null) await p.setBool(key, value);
      return true;
    } catch (_) {
      return true;
    }
  }

  int? getInt(String key) {
    return (_memoryCache[key] as int?) ?? _prefs?.getInt(key);
  }

  Future<bool> setInt(String key, int value) async {
    _memoryCache[key] = value;
    try {
      final p = await _getPrefs();
      if (p != null) await p.setInt(key, value);
      return true;
    } catch (_) {
      return true;
    }
  }

  double? getDouble(String key) {
    return (_memoryCache[key] as double?) ?? _prefs?.getDouble(key);
  }

  Future<bool> setDouble(String key, double value) async {
    _memoryCache[key] = value;
    try {
      final p = await _getPrefs();
      if (p != null) await p.setDouble(key, value);
      return true;
    } catch (_) {
      return true;
    }
  }

  List<String>? getStringList(String key) {
    return (_memoryCache[key] as List<String>?) ?? _prefs?.getStringList(key);
  }

  Future<bool> setStringList(String key, List<String> value) async {
    _memoryCache[key] = value;
    try {
      final p = await _getPrefs();
      if (p != null) await p.setStringList(key, value);
      return true;
    } catch (_) {
      return true;
    }
  }

  Object? get(String key) {
    return _memoryCache[key] ?? _prefs?.get(key);
  }

  bool containsKey(String key) {
    return _memoryCache.containsKey(key) || (_prefs?.containsKey(key) ?? false);
  }

  Future<bool> remove(String key) async {
    _memoryCache.remove(key);
    _globalMemoryCache.remove(key);
    try {
      final p = await _getPrefs();
      if (p != null) await p.remove(key);
      return true;
    } catch (_) {
      return true;
    }
  }

  Future<bool> clear() async {
    _memoryCache.clear();
    _globalMemoryCache.clear();
    try {
      final p = await _getPrefs();
      if (p != null) await p.clear();
      return true;
    } catch (_) {
      return true;
    }
  }
}

typedef BusinessPreferences = AppPreferences;
