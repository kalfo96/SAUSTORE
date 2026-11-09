import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/inventory_models.dart';

abstract interface class InventoryStore {
  Future<InventoryData?> load();

  Future<void> save(InventoryData data);

  Future<void> clear();
}

class SharedPreferencesInventoryStore implements InventoryStore {
  SharedPreferencesInventoryStore({
    SharedPreferences? preferences,
    this.storageKey = defaultStorageKey,
  }) : _preferences = preferences;

  static const String defaultStorageKey = 'stockpilot.inventory.v1';

  final String storageKey;
  SharedPreferences? _preferences;

  Future<SharedPreferences> _getPreferences() async {
    return _preferences ??= await SharedPreferences.getInstance();
  }

  @override
  Future<InventoryData?> load() async {
    try {
      final preferences = await _getPreferences();
      final encoded = preferences.getString(storageKey);
      if (encoded == null || encoded.trim().isEmpty) return null;

      final decoded = jsonDecode(encoded);
      if (decoded is! Map) {
        throw const FormatException('The saved inventory has an invalid root.');
      }
      return InventoryData.fromJson(Map<String, dynamic>.from(decoded));
    } on InventoryException {
      rethrow;
    } catch (error) {
      throw InventoryException(
        'The saved inventory could not be opened. It may be damaged.',
        code: 'storage_read_failed',
      );
    }
  }

  @override
  Future<void> save(InventoryData data) async {
    try {
      final preferences = await _getPreferences();
      final didSave = await preferences.setString(
        storageKey,
        jsonEncode(data.toJson()),
      );
      if (!didSave) {
        throw const InventoryException(
          'Your changes could not be saved. Please try again.',
          code: 'storage_write_failed',
        );
      }
    } on InventoryException {
      rethrow;
    } catch (error) {
      throw const InventoryException(
        'Your changes could not be saved. Please try again.',
        code: 'storage_write_failed',
      );
    }
  }

  @override
  Future<void> clear() async {
    try {
      final preferences = await _getPreferences();
      final didRemove = await preferences.remove(storageKey);
      if (!didRemove && preferences.containsKey(storageKey)) {
        throw const InventoryException(
          'The inventory could not be cleared. Please try again.',
          code: 'storage_clear_failed',
        );
      }
    } on InventoryException {
      rethrow;
    } catch (error) {
      throw const InventoryException(
        'The inventory could not be cleared. Please try again.',
        code: 'storage_clear_failed',
      );
    }
  }
}

/// An in-memory store useful for previews, tests, and temporary sessions.
class MemoryInventoryStore implements InventoryStore {
  MemoryInventoryStore({InventoryData? initialData})
    : _data = initialData == null ? null : _clone(initialData);

  InventoryData? _data;

  InventoryData? get data => _data == null ? null : _clone(_data!);

  @override
  Future<InventoryData?> load() async {
    final current = _data;
    return current == null ? null : _clone(current);
  }

  @override
  Future<void> save(InventoryData data) async {
    _data = _clone(data);
  }

  @override
  Future<void> clear() async {
    _data = null;
  }

  static InventoryData _clone(InventoryData data) {
    return InventoryData.fromJson(data.toJson());
  }
}
