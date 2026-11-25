/// Build 13 (point 6) — PERMANENT LOGO entitlement state.
///
/// The Permanent Logo section (Logo tool) sells a one-time,
/// owner-granted entitlement: the user pays Rs 200 manually via
/// Easypaisa (the Pro pattern — number from remote config, the
/// user's login email as the payment reference, screenshot on
/// WhatsApp), and the owner switches the entitlement on from
/// the Supabase dashboard. The app only ever READS its own row
/// in `tjpro_permanent_logo` (user_id, enabled) — see
/// supabase-followups/permanent-logo-sql.sql. That SQL is a
/// FOLLOW-UP: until the owner runs it, the table does not exist
/// and this service stays in free mode (fail-soft, exactly like
/// ProService before pro-sql.sql was run).
///
/// The last server answer is cached in shared_preferences,
/// keyed to the user id it belongs to (the ProService pattern).
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'supabase_service.dart';

class PermanentLogoService {
  PermanentLogoService._();

  static final PermanentLogoService instance = PermanentLogoService._();

  /// Supabase table holding the grants (see the follow-up SQL).
  static const String table = 'tjpro_permanent_logo';

  static const String _enabledKey = 'tjpro_perm_logo_enabled_v1';
  static const String _userKey = 'tjpro_perm_logo_user_id_v1';

  /// The manual price shown in the section (rupees, one-time).
  static const int priceRupees = 200;

  /// True while the signed-in user's entitlement is on.
  final ValueNotifier<bool> entitled = ValueNotifier<bool>(false);

  bool get isEntitled => entitled.value;

  /// Loads the cached grant, then refreshes from the server.
  /// Never throws.
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getBool(_enabledKey) ?? false;
      final cachedUser = prefs.getString(_userKey) ?? '';
      final currentId = SupabaseService.currentUser?.id;
      if (currentId == null || cachedUser == currentId) {
        entitled.value = cached;
      } else {
        entitled.value = false;
      }
    } catch (_) {
      // Cache unreadable -> not entitled until a refresh succeeds.
    }
    await refresh();
  }

  /// Re-reads the signed-in user's row. Absent table / no row /
  /// any error keeps the current state (fail-soft).
  Future<void> refresh() async {
    try {
      if (!SupabaseService.isInitialized) return;
      final user = SupabaseService.currentUser;
      if (user == null) return;
      final Map<String, dynamic>? row = await SupabaseService.client
          .from(table)
          .select('enabled')
          .eq('user_id', user.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 15));
      final enabled = row != null && row['enabled'] == true;
      entitled.value = enabled;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, enabled);
      await prefs.setString(_userKey, user.id);
    } catch (_) {
      // Fail-soft: keep the cached state exactly as-is.
    }
  }
}
