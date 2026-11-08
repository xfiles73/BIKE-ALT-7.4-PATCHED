import 'package:bike_control/models/device_limit_reached_error.dart';
import 'package:bike_control/models/entitlement.dart';
import 'package:bike_control/services/device_identity_service.dart';
import 'package:bike_control/services/license/license_service.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The account's entitlements, as far as this build is concerned.
///
/// This used to call the `get-entitlements` edge function, cache the answer
/// and re-fetch it every [refreshTtl] (and whenever the app resumed). That
/// server-side token check is now stubbed: [refresh] never touches the
/// network and always yields an active Pro licence, so an offline app can
/// never be downgraded to the free tier.
///
/// The public surface is unchanged on purpose: [IAPManager], the paywall and
/// the plan screens keep reading the same getters and the same
/// [ChangeNotifier] notifications.
class EntitlementsService extends ChangeNotifier {
  /// Kept for callers that used to reason about staleness. The local licence
  /// never goes stale, see [isCacheStale].
  static const Duration refreshTtl = Duration.zero;

  static const String _premiumMonthlyProductKey = 'premium_monthly';
  static const String _premiumYearlyProductKey = 'premium_yearly';
  static const String _fullVersionProductKey = 'full_version';

  // The constructor keeps its production signature so tests and consumers do
  // not change; neither dependency is consulted by the stub.
  // ignore: unused_field
  final SupabaseClient _supabase;
  // ignore: unused_field
  final DeviceIdentityService _deviceIdentityService;

  bool _isInitialized = false;

  DateTime? _lastFetchedAt;
  List<Entitlement> _entitlements = const [];
  bool _isRegisteredDevice = false;

  EntitlementsService(
    this._supabase, {
    required DeviceIdentityService deviceIdentityService,
  }) : _deviceIdentityService = deviceIdentityService;

  List<Entitlement> get current => List.unmodifiable(_entitlements);

  DateTime? get lastFetchedAt => _lastFetchedAt;

  /// Every device is registered for the local Pro licence.
  bool get isRegisteredDevice => _isRegisteredDevice;

  /// The local stub cannot produce a device-limit error.
  DeviceLimitReachedError? get lastDeviceLimitError => null;

  /// The licence is hard-coded, so a cached answer never becomes stale.
  bool get isCacheStale => false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    _applyStubLicence();
    _isInitialized = true;
  }

  /// Stubbed re-validation. Deliberately does not call the licensing backend
  /// and does not start a timer: the licence below is always Pro.
  Future<void> refresh({bool force = false}) async {
    await initialize();
    _applyStubLicence();
    notifyListeners();
  }

  bool hasActive(String productKey) {
    return _entitlements.any((entitlement) {
      return entitlement.productKey == productKey && entitlement.isActive;
    });
  }

  DateTime? activeUntil(String productKey) {
    DateTime? latest;
    for (final entitlement in _entitlements) {
      if (entitlement.productKey != productKey) continue;
      final value = entitlement.activeUntil;
      if (value == null) continue;
      if (latest == null || value.isAfter(latest)) latest = value;
    }
    return latest;
  }

  /// A sign-out used to empty the cache. It must not revoke the local
  /// licence, so the stub is simply re-applied.
  Future<void> clearCache() async {
    await initialize();
    _applyStubLicence();
    notifyListeners();
  }

  void _applyStubLicence() {
    final licence = licenseService.current;
    final until = licence.expiresAt ?? DateTime.now().add(const Duration(days: 3650));
    _entitlements = [
      Entitlement(
        productKey: _premiumMonthlyProductKey,
        status: licence.valid ? 'active' : 'expired',
        activeUntil: until,
        source: 'license_stub:${licence.tier}',
      ),
      Entitlement(
        productKey: _premiumYearlyProductKey,
        status: licence.valid ? 'active' : 'expired',
        activeUntil: until,
        source: 'license_stub:${licence.tier}',
      ),
      Entitlement(
        productKey: _fullVersionProductKey,
        status: licence.valid ? 'active' : 'expired',
        activeUntil: until,
        source: 'license_stub:${licence.tier}',
      ),
    ];
    _lastFetchedAt = DateTime.now();
    _isRegisteredDevice = licence.valid;
  }
}
