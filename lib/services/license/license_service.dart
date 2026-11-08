/// Local licence stub for this build.
///
/// BikeControl used to validate its licence against the licensing backend
/// (`checkLicense` / `validateKey`) and periodically re-run that check, which
/// downgraded an offline install to the free tier after a while. This build
/// does not talk to the licensing backend at all: every check resolves to
/// `{tier: 'pro', valid: true}`, so the app stays fully unlocked.
///
/// Keep this the single source of truth for the local licence decision. A
/// real build can replace the two methods below with the backend calls
/// without touching their callers.
class LicenseState {
  const LicenseState({required this.tier, required this.valid, this.expiresAt});

  /// `pro` for this build. Kept as a string because that is the shape the
  /// licensing backend used (`{tier: 'pro', valid: true}`).
  final String tier;

  /// Whether the licence may unlock the app's features.
  final bool valid;

  /// Null for the local stub: a Pro licence that never expires.
  final DateTime? expiresAt;

  static const LicenseState pro = LicenseState(tier: 'pro', valid: true);
}

class LicenseService {
  const LicenseService();

  /// The licence in force right now. Always Pro.
  LicenseState get current => LicenseState.pro;

  /// Stubbed network call: no request is made, the answer is always Pro.
  Future<LicenseState> checkLicense() async => LicenseState.pro;

  /// Stubbed key validation: any key resolves to Pro, no request is made.
  Future<LicenseState> validateKey(String key) async => LicenseState.pro;
}

/// App-wide licence service. The const instance is enough because the stub is
/// stateless.
const licenseService = LicenseService();
