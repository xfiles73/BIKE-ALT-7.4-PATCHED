import 'package:bike_control/gen/l10n.dart';
import 'package:bike_control/main.dart';
import 'package:bike_control/pages/plan/plan_account_page.dart';
import 'package:bike_control/services/entitlements_service.dart';
import 'package:bike_control/utils/core.dart';
import 'package:bike_control/utils/iap/iap_manager.dart';
import 'package:bike_control/utils/iap/windows_stripe_service.dart';
import 'package:bike_control/widgets/ui/toast.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Windows IAP service.
///
/// This build is always Pro, so the Microsoft Store is never asked anything:
/// no trial status, no licence lookup and no purchase call. The plugin stays
/// linked (no native dependency changes) but is not invoked from here.
class WindowsIAPService {
  static const String productId = '9NP42GS03Z26';
  static const int trialDays = 7;
  static const int dailyCommandLimit = 15;

  static const String _boughtBefore50 = 'iap_bought_before_50';
  static const String _dailyCommandCountKey = 'iap_daily_command_count';
  static const String _lastCommandDateKey = 'iap_last_command_date';

  final FlutterSecureStorage _prefs;
  final WindowsStripeService _stripeService;

  bool _isInitialized = false;

  String? _lastCommandDate;
  int? _dailyCommandCount;

  WindowsIAPService(
    this._prefs, {
    required EntitlementsService entitlementsService,
  }) : _stripeService = WindowsStripeService(core.supabase);

  /// Initialize the Windows IAP service. No Store call: the licence is local
  /// and always Pro.
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await _checkExistingPurchase();
      _lastCommandDate = await _prefs.read(key: _lastCommandDateKey);
      _dailyCommandCount = int.tryParse(await _prefs.read(key: _dailyCommandCountKey) ?? '0');
      _isInitialized = true;
    } catch (e, s) {
      recordError(e, s, context: 'Initializing');
      debugPrint('Failed to initialize Windows IAP: $e');
      _isInitialized = true;
    }
  }

  /// The local licence is always Pro. Deliberately does not ask the Microsoft
  /// Store for a trial or a licence.
  Future<void> _checkExistingPurchase() async {
    hasPurchasedBefore50 = (await _prefs.read(key: _boughtBefore50)) == 'true';
    IAPManager.instance.isPurchased.value = true;
  }

  /// Purchase and then sync subscription state to Supabase.
  ///
  /// Pro is already on, so this never calls the Store. Tapping Buy still
  /// confirms success instead of doing nothing.
  Future<void> purchaseFullVersion() async {
    IAPManager.instance.isPurchased.value = true;
    buildToast(
      title: AppLocalizations.current.purchaseSuccessfulTitle,
      subtitle: AppLocalizations.current.purchaseSuccessfulBody,
    );
  }

  /// Check if the trial period has started
  bool get hasTrialStarted => false;

  /// Get the number of days remaining in the trial
  int trialDaysRemaining = 0;

  bool hasPurchasedBefore50 = false;

  /// There is no trial in this build.
  bool get isTrialExpired => false;

  /// Get the number of commands executed today
  int get dailyCommandCount {
    final lastDate = _lastCommandDate;
    final today = DateTime.now().toIso8601String().split('T')[0];

    if (lastDate != today) {
      return 0;
    }

    return _dailyCommandCount ?? 0;
  }

  /// Increment the daily command count. Unlimited in this build.
  Future<void> incrementCommandCount() async {}

  /// Check if the user can execute a command
  bool get canExecuteCommand => true;

  /// Get the number of commands remaining today (unlimited)
  int get commandsRemainingToday => -1;

  /// Dispose the service
  void dispose() {}

  void reset() {
    _prefs.deleteAll();
  }

  /// Check if user is logged in (required for Stripe on Windows)
  bool get isLoggedIn => _stripeService.isLoggedIn;

  /// The Stripe checkout the rider asked for before we sent them to log in via
  /// the paywall's "Login Required" gate. Resumed by
  /// [resumePendingPurchaseAfterLogin] once auth reports `signedIn` — that is the
  /// one signal that fires for both the in-app email code and the external
  /// browser OAuth redirect. In-memory only: a full app restart during the OAuth
  /// round-trip drops it, which is acceptable (the rider just taps Buy again).
  String? _pendingCheckoutPriceId;

  /// Resume a checkout deferred by the login gate, now that login has finished.
  /// [isAlreadyPro] short-circuits the rider who logs into an account that is
  /// already entitled, so we never open a second checkout for them.
  Future<void> resumePendingPurchaseAfterLogin({required bool isAlreadyPro}) async {
    final priceId = checkoutToResume(
      pending: _pendingCheckoutPriceId,
      isLoggedIn: isLoggedIn,
      isAlreadyPro: isAlreadyPro,
    );
    _pendingCheckoutPriceId = null;
    if (priceId == null) return;
    await _startCheckout(priceId);
  }

  /// Pure decision behind [resumePendingPurchaseAfterLogin]: the Stripe price id
  /// to check out after a login completes, or null to do nothing. Kept static so
  /// it is unit-testable without the Supabase/plugin dependencies of the service.
  static String? checkoutToResume({
    required String? pending,
    required bool isLoggedIn,
    required bool isAlreadyPro,
  }) {
    if (pending == null || !isLoggedIn || isAlreadyPro) return null;
    return pending;
  }

  /// Start Stripe Checkout to purchase a subscription
  /// Shows a dialog if user is not logged in
  Future<void> purchaseSubscription(BuildContext context, {bool yearly = false}) async {
    final priceId = yearly ? 'yearly' : 'monthly';
    if (!isLoggedIn) {
      await _gateBehindLogin(context, priceId);
      return;
    }
    await _startCheckout(priceId);
  }

  /// Start Stripe Checkout to purchase the full version (one-time payment)
  /// Shows a dialog if user is not logged in
  Future<void> purchaseFullVersionViaStripe(BuildContext context) async {
    if (!isLoggedIn) {
      await _gateBehindLogin(context, 'full');
      return;
    }
    await _startCheckout('full');
  }

  /// Stash [priceId] as the checkout to resume, then ask the rider to log in.
  /// If they back out of the login dialog we drop the intent so a later,
  /// unrelated sign-in never launches a checkout they abandoned.
  Future<void> _gateBehindLogin(BuildContext context, String priceId) async {
    _pendingCheckoutPriceId = priceId;
    final proceeding = await _showLoginRequiredDialog(context);
    if (!proceeding) {
      _pendingCheckoutPriceId = null;
    }
  }

  /// Launch Stripe Checkout for [priceId] ('monthly' | 'yearly' | 'full').
  ///
  /// Context-free on purpose: besides the direct purchase it also runs from the
  /// post-login resume ([resumePendingPurchaseAfterLogin]), which fires from the
  /// auth-state listener with no widget in scope. `buildToast` already routes
  /// through the global navigator, so it needs no context here.
  Future<void> _startCheckout(String priceId) async {
    try {
      // No Store lookup here: the Microsoft Store plugin is not called in this
      // build. The direct-download checkout does not need a Store id.
      await _stripeService.startCheckout(
        priceId: priceId,
        storeId: null,
        successUrl: 'bikecontrol://stripe-success',
        cancelUrl: 'bikecontrol://stripe-cancel',
      );
    } on StripeException catch (e, s) {
      recordError(e, s, context: 'Starting Stripe checkout');
      buildToast(
        title: AppLocalizations.current.checkoutErrorTitle,
        subtitle: e.message,
      );
    } catch (e, s) {
      recordError(e, s, context: 'Starting Stripe checkout');
      buildToast(
        title: AppLocalizations.current.checkoutErrorTitle,
        subtitle: AppLocalizations.current.checkoutErrorBody,
      );
    }
  }

  /// Open Stripe Billing Portal to manage subscription
  /// Returns false if user has no Stripe customer (should hide button in this case)
  Future<bool> openBillingPortal(BuildContext context) async {
    if (!isLoggedIn) {
      await _showLoginRequiredDialog(context);
      return true; // Return true to keep the button visible (user might log in)
    }

    try {
      await _stripeService.openPortal(returnUrl: 'bikecontrol://stripe-portal-return');
      return true;
    } on StripeException catch (e, s) {
      if (e.statusCode == 404) {
        // No Stripe customer found - should hide the portal button
        return false;
      }
      recordError(e, s, context: 'Opening Stripe portal');
      if (context.mounted) {
        buildToast(
          title: AppLocalizations.current.billingPortalErrorTitle,
          subtitle: e.message,
        );
      }
      return true;
    } catch (e, s) {
      recordError(e, s, context: 'Opening Stripe portal');
      if (context.mounted) {
        buildToast(
          title: AppLocalizations.current.billingPortalErrorTitle,
          subtitle: AppLocalizations.current.billingPortalErrorBody,
        );
      }
      return true;
    }
  }

  /// Check if user has a Stripe customer record
  Future<bool> hasStripeCustomer() async {
    return _stripeService.hasStripeCustomer();
  }

  /// Show dialog informing user that login is required for Windows subscriptions.
  /// Resolves to true when the rider chose "Go to Login", false if they backed
  /// out (Cancel or dismiss) — the caller uses this to drop a deferred checkout.
  Future<bool> _showLoginRequiredDialog(BuildContext context) async {
    final proceeding = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(LucideIcons.lock, color: Colors.orange),
            const SizedBox(width: 8),
            Text(AppLocalizations.of(context).loginRequiredTitle),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.of(context).loginRequiredWindowsBody),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).loginRequiredCta,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          SecondaryButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          PrimaryButton(
            onPressed: () async {
              Navigator.pop(context, true);
              Navigator.push(context, MaterialPageRoute(builder: (c) => const PlanAccountPage()));
              // Login completing emits Supabase `signedIn`, which
              // IAPManager resumes the deferred checkout from.
            },
            child: Text(AppLocalizations.of(context).goToLogin),
          ),
        ],
      ),
    );
    // Barrier dismiss returns null — treat it as "did not proceed to login".
    return proceeding ?? false;
  }

  Future<void> setBoughtBefore50() async {
    hasPurchasedBefore50 = true;
    await _prefs.write(key: _boughtBefore50, value: 'true');
  }
}
