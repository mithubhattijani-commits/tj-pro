/// Build 9 (v1.7.0, fix-list point #6A + the user's slot
/// correction of 2026-11-25 ~07:13 PKT) — BANNER BOOKING.
///
/// In-app self-service banner advertising on the Home hero:
///
/// - BOTH hero slots are bookable (the user's correction: the
///   "only slide 2" default was rejected). Each slot has its
///   own bookings, durations and expiry.
/// - Prices (user-confirmed): 1 hour = 100 coins, 2 hours =
///   200 coins, 4 hours = 300 coins.
/// - The OWNER's own banners stay the saved default/fallback
///   for both slots (the existing remote -> cache -> bundled
///   chain in main.dart is untouched). While a slot has an
///   ACTIVE approved booking the booked ad shows on that slot;
///   the moment the booking's time ends, the owner's own
///   banner is back automatically — expiry is computed from
///   the stored timestamps on every read, no manual step.
/// - Bookings QUEUE per slot: a new booking starts when the
///   slot's current approved booking ends (or now, when the
///   slot is free), so two paid ads never overlap on one slot.
/// - AUTO-MODERATION runs BEFORE any coin charge (see
///   banner_moderation.dart): hard violation -> refused, no
///   charge; doubtful -> stored as `pending_review`, which
///   NEVER goes live by itself; clean -> `approved`.
/// - Coins move through the existing CoinService flow, charged
///   LAST (after upload + row insert succeed) with a stable
///   idempotency key; if the charge fails, the row and the
///   uploaded image are removed again — no orphan charges.
/// - REJECTED bookings are refunded automatically: when the
///   owner rejects a pending booking in the dashboard, the app
///   calls the `tjpro_refund_banner_booking` RPC on its next
///   launch (security-definer, idempotent — see build9-sql.sql)
///   and the coins land back in the user's ledger.
///
/// Everything is fail-soft: until build9-sql.sql runs (table +
/// storage bucket), every call here quietly does nothing and
/// the hero keeps showing the owner's banners, exactly as
/// before this build.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'banner_moderation.dart';
import 'coin_service.dart';
import 'pricing_service.dart';
import 'supabase_service.dart';

/// One row of `tjpro_banner_bookings`.
class BannerBooking {
  const BannerBooking({
    required this.id,
    required this.userId,
    required this.slot,
    required this.imageUrl,
    required this.text,
    required this.linkUrl,
    required this.durationHours,
    required this.priceCoins,
    required this.status,
    required this.startsAt,
    required this.endsAt,
    required this.createdAt,
    this.refundedAt,
  });

  final String id;
  final String userId;

  /// Hero slot: 1 or 2.
  final int slot;
  final String imageUrl;
  final String text;
  final String linkUrl;
  final int durationHours;
  final int priceCoins;

  /// pending_review | approved | rejected
  final String status;
  final DateTime startsAt;
  final DateTime endsAt;
  final DateTime createdAt;
  final DateTime? refundedAt;

  static const String statusPendingReview = 'pending_review';
  static const String statusApproved = 'approved';
  static const String statusRejected = 'rejected';

  /// True when this booking should be ON the hero slot at
  /// [now]: approved and inside its paid window. This single
  /// check is what makes expiry automatic — the moment
  /// [endsAt] passes, the owner's banner is back.
  bool isActiveAt(DateTime now) {
    return status == statusApproved &&
        !startsAt.isAfter(now) &&
        endsAt.isAfter(now);
  }

  factory BannerBooking.fromJson(Map<String, dynamic> json) {
    DateTime parse(dynamic v) =>
        DateTime.tryParse((v ?? '').toString()) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return BannerBooking(
      id: (json['id'] ?? '').toString(),
      userId: (json['user_id'] ?? '').toString(),
      slot: (json['slot'] as num?)?.toInt() ?? 0,
      imageUrl: (json['image_url'] ?? '').toString(),
      text: (json['ad_text'] ?? '').toString(),
      linkUrl: (json['link_url'] ?? '').toString(),
      durationHours: (json['duration_hours'] as num?)?.toInt() ?? 0,
      priceCoins: (json['price_coins'] as num?)?.toInt() ?? 0,
      status: (json['status'] ?? '').toString(),
      startsAt: parse(json['starts_at']),
      endsAt: parse(json['ends_at']),
      createdAt: parse(json['created_at']),
      refundedAt: json['refunded_at'] == null
          ? null
          : DateTime.tryParse(json['refunded_at'].toString()),
    );
  }
}

/// Outcome of one booking attempt.
class BookingAttempt {
  const BookingAttempt({
    required this.ok,
    this.booking,
    this.error,
    this.moderation,
  });

  final bool ok;
  final BannerBooking? booking;

  /// Machine-readable failure: insufficient_balance |
  /// moderation_rejected | upload_failed | insert_failed |
  /// charge_failed | not_signed_in | unavailable
  final String? error;
  final ModerationResult? moderation;
}

class BannerBookingService {
  BannerBookingService._();

  static final BannerBookingService instance = BannerBookingService._();

  static const String table = 'tjpro_banner_bookings';
  static const String bucket = 'tjpro-banners';
  static const String refundRpc = 'tjpro_refund_banner_booking';
  static const String spendReason = 'banner_booking';

  /// The user's confirmed price table (fix-list point #6A).
  /// Point #20: each price resolves through PricingService
  /// (price_banner_booking_1h / _2h / _4h) so the owner can
  /// reprice a duration in tj-pro.json without a build; an
  /// absent key keeps the confirmed 100 / 200 / 300. A getter,
  /// not a const, because the config can change at runtime.
  static List<({int hours, int coins})> get durations =>
      <({int hours, int coins})>[
        (
          hours: 1,
          coins: PricingService.coinsOr(
            PricingService.keyBannerBooking1h,
            100,
          ),
        ),
        (
          hours: 2,
          coins: PricingService.coinsOr(
            PricingService.keyBannerBooking2h,
            200,
          ),
        ),
        (
          hours: 4,
          coins: PricingService.coinsOr(
            PricingService.keyBannerBooking4h,
            300,
          ),
        ),
      ];

  static const Duration _timeout = Duration(seconds: 20);

  /// Bumped whenever the cached booking set changes, so the
  /// Home hero can rebuild (same pattern as HeroBannerCache).
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  List<BannerBooking> _approved = <BannerBooking>[];
  List<BannerBooking> _mine = <BannerBooking>[];

  /// Clock seam for tests.
  static DateTime Function() nowFn = DateTime.now;

  // --- IO seams (tests) -----------------------------------------
  static Future<List<Map<String, dynamic>>> Function()? fetchApprovedOverride;
  static Future<List<Map<String, dynamic>>> Function(String userId)?
      fetchMineOverride;
  static Future<String?> Function(String path, List<int> bytes)?
      uploadOverride;
  static Future<bool> Function(Map<String, dynamic> row)? insertOverride;
  static Future<void> Function(String id)? deleteRowOverride;
  static Future<void> Function(String path)? deleteFileOverride;
  static Future<bool> Function(String bookingId)? refundOverride;

  static void resetForTest() {
    final s = instance;
    s._approved = <BannerBooking>[];
    s._mine = <BannerBooking>[];
    s.revision.value = 0;
    nowFn = DateTime.now;
    fetchApprovedOverride = null;
    fetchMineOverride = null;
    uploadOverride = null;
    insertOverride = null;
    deleteRowOverride = null;
    deleteFileOverride = null;
    refundOverride = null;
  }

  // --- Pure scheduling math ---------------------------------------

  /// When a NEW booking on [slot] may start: now, or the end of
  /// the slot's last still-running/queued approved booking —
  /// bookings on one slot never overlap.
  static DateTime computeStart(
    List<BannerBooking> approved,
    int slot,
    DateTime now,
  ) {
    var start = now;
    for (final b in approved) {
      if (b.slot != slot || b.status != BannerBooking.statusApproved) {
        continue;
      }
      if (b.endsAt.isAfter(start)) start = b.endsAt;
    }
    return start;
  }

  /// The booking (if any) that owns [slot] at [now] from a set
  /// of approved bookings: the active one with the earliest
  /// start (queue order).
  static BannerBooking? activeFrom(
    List<BannerBooking> approved,
    int slot,
    DateTime now,
  ) {
    BannerBooking? best;
    for (final b in approved) {
      if (b.slot != slot || !b.isActiveAt(now)) continue;
      if (best == null || b.startsAt.isBefore(best.startsAt)) best = b;
    }
    return best;
  }

  // --- Reads ---------------------------------------------------------

  /// The booking currently owning [slot], from the cache
  /// (refreshed by [init] / [refresh] / a successful booking).
  BannerBooking? activeBookingForSlot(int slot) {
    return activeFrom(_approved, slot, nowFn());
  }

  /// My own bookings (newest first), from the cache.
  List<BannerBooking> get myBookings =>
      List<BannerBooking>.unmodifiable(_mine);

  /// The cached approved set (both slots), read-only — the
  /// Home hero uses it to arm its next-transition timer.
  List<BannerBooking> get approvedBookings =>
      List<BannerBooking>.unmodifiable(_approved);

  /// Startup: load the approved set (for the hero) + my own
  /// bookings, and settle any refunds owed. Fail-soft.
  Future<void> init() async {
    await refresh();
    await settleRefunds();
  }

  Future<void> refresh() async {
    try {
      final approved = await _fetchApproved();
      if (approved != null) {
        _approved = approved;
        revision.value++;
      }
    } catch (_) {
      // Keep the cache; the hero falls back to the owner's
      // banners for any slot without an active booking.
    }
    try {
      final mine = await _fetchMine();
      if (mine != null) _mine = mine;
    } catch (_) {
      // My-bookings list is a nicety; booking itself is guarded
      // separately.
    }
  }

  Future<List<BannerBooking>?> _fetchApproved() async {
    final override = fetchApprovedOverride;
    final List<Map<String, dynamic>> rows;
    if (override != null) {
      rows = await override();
    } else {
      if (!SupabaseService.isInitialized) return null;
      final res = await SupabaseService.client
          .from(table)
          .select()
          .eq('status', BannerBooking.statusApproved)
          .gt('ends_at', nowFn().toUtc().toIso8601String())
          .order('starts_at')
          .timeout(_timeout);
      rows = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    return rows.map(BannerBooking.fromJson).toList();
  }

  Future<List<BannerBooking>?> _fetchMine() async {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) return null;
    final override = fetchMineOverride;
    final List<Map<String, dynamic>> rows;
    if (override != null) {
      rows = await override(userId);
    } else {
      if (!SupabaseService.isInitialized) return null;
      final res = await SupabaseService.client
          .from(table)
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .timeout(_timeout);
      rows = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    return rows.map(BannerBooking.fromJson).toList();
  }

  // --- Refunds -------------------------------------------------------

  /// For every one of MY bookings that the owner rejected and
  /// that has not been refunded yet, call the refund RPC (it
  /// re-verifies status server-side and pays the ledger credit
  /// idempotently). Fail-soft per booking.
  Future<void> settleRefunds() async {
    try {
      for (final b in _mine) {
        if (b.status != BannerBooking.statusRejected) continue;
        if (b.refundedAt != null) continue;
        await _refund(b.id);
      }
    } catch (_) {
      // Refunds retry on the next launch.
    }
  }

  Future<bool> _refund(String bookingId) async {
    final override = refundOverride;
    if (override != null) return override(bookingId);
    if (!SupabaseService.isInitialized) return false;
    try {
      final res = await SupabaseService.client
          .rpc(refundRpc, params: <String, dynamic>{
            'p_booking_id': bookingId,
          })
          .timeout(_timeout);
      return res is Map && res['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  // --- Booking ---------------------------------------------------------

  static String _newUuid() {
    final r = Random.secure();
    String hex(int n) => List<String>.generate(
          n,
          (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
    return '${hex(4)}-${hex(2)}-4${hex(2).substring(1)}-'
        '${(8 + r.nextInt(4)).toRadixString(16)}${hex(2).substring(1)}-'
        '${hex(6)}';
  }

  /// Runs one full booking: moderation -> upload -> insert ->
  /// charge (last). See the file header for the ordering
  /// rationale. Never throws.
  Future<BookingAttempt> createBooking({
    required int slot,
    required File imageFile,
    required String text,
    required String link,
    required int hours,
    required int priceCoins,
  }) async {
    final user = SupabaseService.currentUser;
    if (user == null || !SupabaseService.isInitialized) {
      return const BookingAttempt(ok: false, error: 'not_signed_in');
    }
    // 1) AUTO-MODERATION — before money moves, before upload.
    final moderation = await BannerModeration.moderate(
      text: text,
      link: link,
      imageFile: imageFile,
    );
    if (moderation.verdict == ModerationVerdict.reject) {
      return BookingAttempt(
        ok: false,
        error: 'moderation_rejected',
        moderation: moderation,
      );
    }
    final status = moderation.verdict == ModerationVerdict.review
        ? BannerBooking.statusPendingReview
        : BannerBooking.statusApproved;

    final bookingId = _newUuid();
    final ext = imageFile.path.split('.').last.toLowerCase();
    final storagePath = '${user.id}/$bookingId.$ext';

    // 2) Upload the image (public bucket; the hero loads it by
    // URL like every other remote banner).
    String? imageUrl;
    try {
      final bytes = await imageFile.readAsBytes();
      imageUrl = await _upload(storagePath, bytes);
    } catch (_) {
      imageUrl = null;
    }
    if (imageUrl == null) {
      return const BookingAttempt(ok: false, error: 'upload_failed');
    }

    // 3) Insert the booking row (window queued per slot).
    final now = nowFn();
    final start = status == BannerBooking.statusApproved
        ? computeStart(_approved, slot, now)
        : now;
    final row = <String, dynamic>{
      'id': bookingId,
      'user_id': user.id,
      'slot': slot,
      'image_url': imageUrl,
      'ad_text': text.trim(),
      'link_url': link.trim(),
      'duration_hours': hours,
      'price_coins': priceCoins,
      'status': status,
      'moderation': <String, dynamic>{
        'verdict': moderation.verdict.name,
        'reasons': moderation.reasons,
        'has_faces': await BannerModeration.detectFaces(imageFile),
      },
      'starts_at': start.toUtc().toIso8601String(),
      'ends_at':
          start.add(Duration(hours: hours)).toUtc().toIso8601String(),
    };
    final inserted = await _insert(row);
    if (!inserted) {
      await _deleteFile(storagePath);
      return const BookingAttempt(ok: false, error: 'insert_failed');
    }

    // 4) Charge LAST, with a stable idempotency key. On failure
    // the row + image are removed again — no orphan charge, no
    // unpaid ad.
    final charge = await CoinService.instance.spendAmount(
      priceCoins,
      reason: spendReason,
      idempotencyKey: 'banner_booking:$bookingId',
    );
    if (!charge.ok) {
      await _deleteRow(bookingId);
      await _deleteFile(storagePath);
      return BookingAttempt(
        ok: false,
        error: charge.error == 'insufficient_balance'
            ? 'insufficient_balance'
            : 'charge_failed',
      );
    }

    final booking = BannerBooking.fromJson(<String, dynamic>{
      ...row,
      'created_at': now.toUtc().toIso8601String(),
    });
    await refresh();
    return BookingAttempt(ok: true, booking: booking);
  }

  Future<String?> _upload(String path, List<int> bytes) async {
    final override = uploadOverride;
    if (override != null) return override(path, bytes);
    try {
      final storage = SupabaseService.client.storage.from(bucket);
      await storage
          .uploadBinary(
            path,
            Uint8List.fromList(bytes),
            fileOptions: const FileOptions(upsert: true),
          )
          .timeout(_timeout);
      return storage.getPublicUrl(path);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _insert(Map<String, dynamic> row) async {
    final override = insertOverride;
    if (override != null) return override(row);
    try {
      await SupabaseService.client
          .from(table)
          .insert(row)
          .timeout(_timeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _deleteRow(String id) async {
    final override = deleteRowOverride;
    if (override != null) {
      await override(id);
      return;
    }
    try {
      await SupabaseService.client
          .from(table)
          .delete()
          .eq('id', id)
          .timeout(_timeout);
    } catch (_) {
      // Cleanup is best-effort; an orphaned row without a
      // charge is inert (its window still ends on schedule).
    }
  }

  Future<void> _deleteFile(String path) async {
    final override = deleteFileOverride;
    if (override != null) {
      await override(path);
      return;
    }
    try {
      await SupabaseService.client.storage
          .from(bucket)
          .remove(<String>[path])
          .timeout(_timeout);
    } catch (_) {
      // Best-effort cleanup (see _deleteRow).
    }
  }
}
