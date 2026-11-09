import '../models/inventory_models.dart';
import '../services/live_api_client.dart';
import 'inventory_store.dart';

/// Version-checked shared inventory. Local device data is never read or changed.
class RemoteInventoryStore implements InventoryStore {
  RemoteInventoryStore({required this.apiClient}) {
    apiClient.addListener(_resetVersion);
  }

  final LiveApiClient apiClient;
  int? _version;

  int? get version => _version;
  bool get hasLoaded => _version != null;

  void _resetVersion() => _version = null;

  void dispose() => apiClient.removeListener(_resetVersion);

  @override
  Future<InventoryData?> load() async {
    // A failed refresh must not leave stale data eligible for a later write.
    _version = null;
    try {
      final response = await apiClient.getInventory();
      final version = _readVersion(response);
      final raw = response['data'];
      if (raw != null && raw is! Map<String, dynamic>) {
        throw const FormatException('Invalid live inventory.');
      }
      final data = raw == null
          ? null
          : InventoryData.fromJson(raw as Map<String, dynamic>);
      _version = version;
      return data;
    } on LiveApiException catch (error) {
      throw InventoryException(error.message, code: error.code);
    } catch (_) {
      throw const InventoryException(
        'The live inventory could not be opened. Contact your administrator; no local data has been changed.',
        code: 'storage_read_failed',
      );
    }
  }

  @override
  Future<void> save(InventoryData data) async {
    final expectedVersion = _requireLoaded();
    try {
      final response = await apiClient.putInventory(
        expectedVersion: expectedVersion,
        data: data.toJson(),
      );
      final version = _readVersion(response);
      if (version <= expectedVersion) {
        throw const FormatException('Invalid version.');
      }
      _version = version;
    } on LiveApiException catch (error) {
      throw InventoryException(error.message, code: error.code);
    } catch (_) {
      throw const InventoryException(
        'The server could not confirm this change. Refresh the live inventory before trying again.',
        code: 'storage_write_failed',
      );
    }
  }

  @override
  Future<void> clear() async {
    final expectedVersion = _requireLoaded();
    try {
      final response = await apiClient.deleteInventory(
        expectedVersion: expectedVersion,
      );
      final version = _readVersion(response);
      if (version <= expectedVersion) {
        throw const FormatException('Invalid version.');
      }
      _version = version;
    } on LiveApiException catch (error) {
      throw InventoryException(error.message, code: error.code);
    } catch (_) {
      throw const InventoryException(
        'The server could not confirm the reset. Refresh the live inventory before trying again.',
        code: 'storage_clear_failed',
      );
    }
  }

  int _requireLoaded() {
    if (_version == null) {
      throw const InventoryException(
        'Load the live inventory before making changes.',
        code: 'inventory_not_loaded',
      );
    }
    return _version!;
  }

  static int _readVersion(Map<String, dynamic> response) {
    final version = response['version'];
    if (version is! int || version < 0) {
      throw const FormatException('The live version is invalid.');
    }
    return version;
  }
}
