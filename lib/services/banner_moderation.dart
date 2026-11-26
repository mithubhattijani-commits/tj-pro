/// Build 9 (v1.7.0, fix-list point #6A-2) — BANNER AUTO-MODERATION.
///
/// Every banner booking is checked BEFORE it can go live
/// (user's order: "koi gandi tasveer, gaali wali likhai ya koi
/// buri/ghalat cheez banner par NAHI lag sakegi"). Three
/// verdicts:
///
/// - [ModerationVerdict.pass]   — booking may go live.
/// - [ModerationVerdict.review] — mashkook (doubtful): the
///   booking is stored as `pending_review` and NEVER goes live
///   on its own; the owner reviews it in the Supabase dashboard.
/// - [ModerationVerdict.reject] — hard violation: the booking
///   is refused before any coin charge.
///
/// WHAT IS ACTUALLY CHECKED (honest scope):
/// - TEXT (the ad text + link): profanity filter with wordlists
///   for English, Roman Urdu and Urdu script (hard list =
///   reject; borderline list = review). The link must be a
///   plain http/https URL.
/// - IMAGE: technical validity with the bundled `image`
///   package — the file must really decode as an image, its
///   extension must be jpg/png/webp, size and dimensions must
///   be sane. ML Kit face detection (already a dependency) is
///   run as a signal only: a face in an ad is NOT a violation,
///   so it never changes the verdict by itself.
/// - NOT POSSIBLE with the current dependencies: true NSFW /
///   explicit-content image classification. No such model ships
///   with the app and none was added (no new heavy dependency,
///   per the build brief). Doubtful images therefore rely on
///   the technical checks + the pending_review path, and the
///   owner remains the final reviewer — stated plainly in the
///   build report.
library;

import 'dart:io';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

enum ModerationVerdict { pass, review, reject }

class ModerationResult {
  const ModerationResult(this.verdict, this.reasons);

  final ModerationVerdict verdict;

  /// Human-readable reasons (Roman Urdu / English mix, shown to
  /// the booking user and stored on the booking row).
  final List<String> reasons;

  static const ModerationResult clean =
      ModerationResult(ModerationVerdict.pass, <String>[]);

  /// The worse of two verdicts (reject > review > pass).
  static ModerationVerdict worst(
    ModerationVerdict a,
    ModerationVerdict b,
  ) {
    if (a == ModerationVerdict.reject || b == ModerationVerdict.reject) {
      return ModerationVerdict.reject;
    }
    if (a == ModerationVerdict.review || b == ModerationVerdict.review) {
      return ModerationVerdict.review;
    }
    return ModerationVerdict.pass;
  }

  ModerationResult combine(ModerationResult other) {
    return ModerationResult(
      worst(verdict, other.verdict),
      <String>[...reasons, ...other.reasons],
    );
  }
}

class BannerModeration {
  BannerModeration._();

  // --- Limits ------------------------------------------------------
  static const int maxImageBytes = 5 * 1024 * 1024; // 5 MB
  static const int minImageWidth = 200;
  static const int minImageHeight = 80;
  static const double maxAspectRatio = 6.0; // wider/taller = doubtful
  static const Set<String> allowedExtensions = <String>{
    'jpg',
    'jpeg',
    'png',
    'webp',
  };

  // --- Wordlists -----------------------------------------------------
  // Hard list: clear profanity / abuse — a match REJECTS the
  // booking. Matching is on word boundaries after normalisation
  // (lowercase, punctuation stripped), so innocent words that
  // merely CONTAIN a listed string are not hit.

  static const List<String> _hardEnglish = <String>[
    'fuck', 'fucking', 'shit', 'bitch', 'bastard', 'whore',
    'slut', 'porn', 'porno', 'xxx', 'sex', 'nude', 'naked',
    'dick', 'pussy', 'asshole', 'motherfucker', 'cunt',
  ];

  static const List<String> _hardRomanUrdu = <String>[
    'harami', 'haramzada', 'kutta', 'kutti', 'kamini', 'kamina',
    'randi', 'gashti', 'bhenchod', 'madarchod', 'chutiya',
    'lund', 'phuddi', 'gaand', 'besharam', 'lanat', 'lanati',
  ];

  static const List<String> _hardUrduScript = <String>[
    'حرامی', 'کمینہ', 'کتیا', 'رنڈی', 'بے شرم', 'لعنت', 'حرامزادہ',
  ];

  // Borderline list: not profanity, but categories a family
  // news app should not auto-approve — a match sends the
  // booking to pending_review for the owner's eyes.
  static const List<String> _reviewWords = <String>[
    'casino', 'betting', 'bet', 'gambling', 'lottery', 'adult',
    'dating', 'escort', 'crypto giveaway', 'double money',
    'جوا', 'سٹہ', 'شراب', 'wine', 'beer', 'vodka',
  ];

  static String _normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _containsWord(String normalized, String word) {
    final w = _normalize(word);
    if (w.isEmpty) return false;
    if (w.contains(' ')) return normalized.contains(w);
    return normalized.split(' ').contains(w);
  }

  /// Text check for the ad text AND the link (both are
  /// user-supplied strings that end up associated with the
  /// banner). Pure — unit-tested.
  static ModerationResult checkText(String text, {String label = 'Text'}) {
    final normalized = _normalize(text);
    if (normalized.isEmpty) return ModerationResult.clean;
    for (final word in _hardEnglish) {
      if (_containsWord(normalized, word)) {
        return ModerationResult(
          ModerationVerdict.reject,
          <String>['Abusive/invalid word found in $label — booking refused.'],
        );
      }
    }
    for (final word in _hardRomanUrdu) {
      if (_containsWord(normalized, word)) {
        return ModerationResult(
          ModerationVerdict.reject,
          <String>['Abusive/invalid word found in $label — booking refused.'],
        );
      }
    }
    for (final word in _hardUrduScript) {
      if (_containsWord(text, word) || _containsWord(normalized, word)) {
        return ModerationResult(
          ModerationVerdict.reject,
          <String>['Abusive/invalid word found in $label — booking refused.'],
        );
      }
    }
    for (final word in _reviewWords) {
      if (_containsWord(normalized, word) ||
          _containsWord(text, word)) {
        return ModerationResult(
          ModerationVerdict.review,
          <String>[
            'A doubtful-category word was found in $label — '
                'the decision will be made after owner review.',
          ],
        );
      }
    }
    return ModerationResult.clean;
  }

  /// Link check: when a link is given it must be a plain
  /// http/https URL; its text also goes through [checkText].
  static ModerationResult checkLink(String link) {
    final trimmed = link.trim();
    if (trimmed.isEmpty) return ModerationResult.clean;
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return const ModerationResult(
        ModerationVerdict.reject,
        <String>['The link is not valid — only an http/https link works.'],
      );
    }
    return checkText(trimmed, label: 'Link');
  }

  /// Image check: extension, size, real decode, dimensions.
  /// Pure file work (no ML Kit) — unit-tested.
  static Future<ModerationResult> checkImageFile(File file) async {
    try {
      final name = file.path.toLowerCase();
      final ext = name.contains('.') ? name.split('.').last : '';
      if (!allowedExtensions.contains(ext)) {
        return const ModerationResult(
          ModerationVerdict.reject,
          <String>['Invalid image type — provide a jpg, png or webp.'],
        );
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        return const ModerationResult(
          ModerationVerdict.reject,
          <String>['The image file is empty.'],
        );
      }
      if (bytes.length > maxImageBytes) {
        return const ModerationResult(
          ModerationVerdict.reject,
          <String>['The image is too large — provide one smaller than 5 MB.'],
        );
      }
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        return const ModerationResult(
          ModerationVerdict.reject,
          <String>['The image cannot be opened — the file seems corrupt.'],
        );
      }
      if (decoded.width < minImageWidth || decoded.height < minImageHeight) {
        return const ModerationResult(
          ModerationVerdict.review,
          <String>[
            'The image is too small — it will not look clear on the banner, '
                'so it will go to owner review.',
          ],
        );
      }
      final aspect = decoded.width / decoded.height;
      if (aspect > maxAspectRatio || aspect < 1 / maxAspectRatio) {
        return const ModerationResult(
          ModerationVerdict.review,
          <String>[
            'The image dimensions are unusual — '
                'it will go to owner review.',
          ],
        );
      }
      return ModerationResult.clean;
    } catch (_) {
      return const ModerationResult(
        ModerationVerdict.reject,
        <String>['The image could not be checked — try again.'],
      );
    }
  }

  /// ML Kit face-detection signal. A face is NOT a violation —
  /// this only records whether a person appears in the image,
  /// for the booking record. Never changes a verdict, never
  /// throws. Returns null when detection is unavailable.
  static Future<bool?> detectFaces(File file) async {
    FaceDetector? detector;
    try {
      detector = FaceDetector(
        options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast),
      );
      final faces = await detector.processImage(
        InputImage.fromFile(file),
      );
      return faces.isNotEmpty;
    } catch (_) {
      return null;
    } finally {
      try {
        await detector?.close();
      } catch (_) {
        // Nothing to clean up that can be allowed to throw.
      }
    }
  }

  /// The full pre-live check for one booking: text + link +
  /// image. The combined verdict is the worst of the three.
  static Future<ModerationResult> moderate({
    required String text,
    required String link,
    required File imageFile,
  }) async {
    var result = checkText(text);
    result = result.combine(checkLink(link));
    result = result.combine(await checkImageFile(imageFile));
    return result;
  }
}
