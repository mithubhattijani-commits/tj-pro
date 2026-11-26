/// MOTION GRAPHICS STUDIO — Gallery (Build M1, v1.11.0).
///
/// Section 1 of the Studio, in the user's own reference visual
/// (deep navy/black, electric blue + purple + cyan glow, premium
/// rounded cards — this tool follows the supplied reference,
/// per the user's standing rule of 2026-11-25). Every card's
/// preview is the template's scene ANIMATING LIVE through the
/// shared engine painter — there are no video assets and no
/// fake thumbnails.
///
/// M1 scope (plan §4): browse + search + category filter +
/// FREE/PRO/COINS labels at their REMOTE prices + real unlock
/// flows + a full-screen preview. The Editor and "Video Par
/// Lagao" arrive in M2 — nothing on this screen pretends
/// otherwise.
///
/// M4 (v1.26.0): the search is the prompt matcher (CHECK #7) —
/// type what you want in English, Roman Urdu or Urdu script
/// and matching designs come first, score-ordered, with a
/// "Matched: …" line saying WHY. No match → honest category
/// suggestions, never a fake "AI result" (the screen labels
/// the feature "Smart Match — template-based help, not
/// generative AI", plan §4). Plus: a Create button into the
/// blank-canvas Creator (M5), Favourites (heart on a card)
/// and Recently Used rail chips.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/ai_tool_charge.dart';
import '../services/feature_gate.dart';
import '../services/pro_service.dart';
import '../services/remote_config_service.dart';
import '../widgets/tool_guide.dart';
import 'motion_access.dart';
import 'motion_editor_screen.dart';
import 'motion_gallery_meta.dart';
import 'motion_my_templates.dart';
import 'motion_preview.dart';
import 'motion_preview_screen.dart';
import 'motion_prompt_matcher.dart';
import 'motion_template_keywords.dart';
import 'motion_templates.dart';
import 'motion_unlock.dart';

// The reference palette (kept local to the Studio: the rest of
// the app keeps its own design system).
const Color _kBgTop = Color(0xFF060A1C);
const Color _kBgBottom = Color(0xFF04060F);
const Color _kCard = Color(0xFF0C1428);
const Color _kCardBorder = Color(0xFF1E3A6E);
const Color _kBlue = Color(0xFF2F7BFF);
const Color _kCyan = Color(0xFF00C6FF);
const Color _kPurple = Color(0xFF7B2FFF);
const Color _kGold = Color(0xFFFFC800);
const Color _kGreen = Color(0xFF2ECC71);

class MotionGalleryScreen extends StatefulWidget {
  const MotionGalleryScreen({super.key});

  @override
  State<MotionGalleryScreen> createState() => _MotionGalleryScreenState();
}

class _MotionGalleryScreenState extends State<MotionGalleryScreen> {
  String _query = '';
  String _category = 'all';
  Set<String> _owned = const {};
  bool _isPro = false;

  /// v1.14.0 M2: the user's saved templates (Editor's Save).
  List<MotionMyTemplate> _mine = const [];

  /// v1.26.0 M4: heart-marked template ids + recently used.
  Set<String> _favourites = const {};
  List<String> _recent = const [];

  @override
  void initState() {
    super.initState();
    _isPro = ProService.instance.proActive;
    ProService.instance.isPro.addListener(_onProChanged);
    RemoteConfigService.instance.notifier.addListener(_onConfigChanged);
    _reloadOwned();
    _reloadMine();
    _reloadMeta();
  }

  Future<void> _reloadMine() async {
    final mine = await MotionMyTemplates.load();
    if (mounted) setState(() => _mine = mine);
  }

  Future<void> _reloadMeta() async {
    final favs = await MotionFavourites.load();
    final recent = await MotionRecents.load();
    if (mounted) {
      setState(() {
        _favourites = favs;
        _recent = recent;
      });
    }
  }

  @override
  void dispose() {
    ProService.instance.isPro.removeListener(_onProChanged);
    RemoteConfigService.instance.notifier
        .removeListener(_onConfigChanged);
    super.dispose();
  }

  void _onProChanged() {
    if (mounted) setState(() => _isPro = ProService.instance.proActive);
  }

  void _onConfigChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _reloadOwned() async {
    final owned = await MotionOwnership.load();
    if (mounted) setState(() => _owned = owned);
  }

  MotionAccess _accessFor(MotionTemplate t) => MotionAccessResolver.resolve(
        t,
        isPro: _isPro,
        owned: _owned.contains(t.id),
        prices: RemoteConfigService.instance.config.prices,
      );

  /// v1.26.0 M4: the prompt matcher drives the search while
  /// browsing "All" with a non-empty query. Inside a chosen
  /// category the classic name/label filter stays (browsing a
  /// shelf is not a prompt).
  bool get _matcherActive =>
      _category == 'all' && _query.trim().isNotEmpty;

  List<MotionMatch> get _matches => _matcherActive
      ? MotionPromptMatcher.match(
          prompt: _query,
          catalogue: motionCatalogue(mine: _mine),
          limit: 12,
        )
      : const [];

  /// The words that matched, across the current results, in
  /// result order — the "Matched: …" honesty line (the user
  /// can see WHY these designs came up).
  List<String> get _matchedTerms {
    final seen = <String>{};
    final out = <String>[];
    for (final m in _matches) {
      for (final term in m.matchedTerms) {
        if (seen.add(term)) out.add(term);
      }
    }
    return out;
  }

  /// Category LABELS worth suggesting when nothing matched
  /// (the matcher's honest fallback — never a fake result).
  List<String> get _suggestedCategories => _matcherActive
      ? MotionPromptMatcher.suggestCategories(
          prompt: _query,
          catalogue: motionCatalogue(mine: _mine),
        )
      : const [];

  /// A saved template as a grid card (M2's wrapper: tier free
  /// = always usable, no unlock flow; _onTap recognises the
  /// 'mine:' id and opens the Editor).
  MotionTemplate _savedWrapper(MotionMyTemplate r) => MotionTemplate(
        id: 'mine:${r.id}',
        name: r.name,
        category: r.category,
        tier: MotionTier.free,
        scene: r.scene,
      );

  bool _classicMatch(MotionTemplate t, String q) {
    if (q.isEmpty) return true;
    final label =
        (MotionCategories.labels[t.category] ?? '').toLowerCase();
    return t.name.toLowerCase().contains(q) || label.contains(q);
  }

  List<MotionTemplate> get _visible {
    final q = _query.trim().toLowerCase();
    if (_matcherActive) {
      // Score-ordered matcher results (built-ins + saved).
      final byId = <String, MotionTemplate>{
        for (final t in MotionTemplates.all) t.id: t,
        for (final r in _mine) 'mine:${r.id}': _savedWrapper(r),
      };
      return [
        for (final m in _matches)
          if (byId[m.templateId] != null) byId[m.templateId]!,
      ];
    }
    if (_category == 'mine') {
      return _mine
          .where((r) => q.isEmpty || r.name.toLowerCase().contains(q))
          .map(_savedWrapper)
          .toList(growable: false);
    }
    if (_category == 'recent') {
      return [
        for (final id in _recent)
          if (MotionTemplates.byId(id) != null &&
              _classicMatch(MotionTemplates.byId(id)!, q))
            MotionTemplates.byId(id)!,
      ];
    }
    if (_category == 'favourites') {
      return MotionTemplates.all
          .where((t) => _favourites.contains(t.id) && _classicMatch(t, q))
          .toList(growable: false);
    }
    return MotionTemplates.all.where((t) {
      if (_category != 'all' && t.category != _category) return false;
      return _classicMatch(t, q);
    }).toList(growable: false);
  }

  Future<void> _toggleFavourite(MotionTemplate t) async {
    await MotionFavourites.toggle(t.id);
    await _reloadMeta();
  }

  Future<void> _openCreator() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const MotionEditorScreen.blank(),
      ),
    );
    // A blank design may have been saved — refresh My Templates.
    await _reloadMine();
  }

  Future<void> _onTap(MotionTemplate t) async {
    if (!t.id.startsWith('mine:')) {
      // M4: Recently Used — recorded on open (fire-and-forget;
      // the rail refreshes when it lands).
      unawaited(
        MotionRecents.record(t.id).then((_) => _reloadMeta()),
      );
    }
    if (t.id.startsWith('mine:')) {
      final id = t.id.substring(5);
      for (final r in _mine) {
        if (r.id == id) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MotionEditorScreen.fromSaved(saved: r),
            ),
          );
          await _reloadMine();
          return;
        }
      }
      return;
    }
    final access = _accessFor(t);
    if (access.canUse) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MotionPreviewScreen(template: t),
        ),
      );
      return;
    }
    final outcome = await MotionUnlock.unlock(
      context,
      template: t,
      access: access,
    );
    if (!mounted) return;
    switch (outcome) {
      case MotionUnlockOutcome.ok:
        await _reloadOwned();
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MotionPreviewScreen(template: t),
          ),
        );
      case MotionUnlockOutcome.insufficient:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(AiToolCharge.insufficientMessage),
          ),
        );
      case MotionUnlockOutcome.failed:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unlock failed — try again.',
            ),
          ),
        );
      case MotionUnlockOutcome.killed:
        setState(() {}); // build() now shows the killed notice.
      case MotionUnlockOutcome.proOnly:
      case MotionUnlockOutcome.cancelled:
        // Pro status may have changed on the Pro screen.
        _onProChanged();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgBottom,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'MOTION',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                fontSize: 19,
              ),
            ),
            Text(
              'Graphics Studio',
              style: TextStyle(fontSize: 11.5, color: _kCyan),
            ),
          ],
        ),
        actions: [
          // v1.26.0 M5: blank-canvas Creator.
          IconButton(
            key: const Key('motionCreateButton'),
            tooltip: 'Create your own',
            onPressed: _openCreator,
            icon: const Icon(Icons.add_circle_outline,
                color: _kCyan, size: 22),
          ),
          // Point #21: Studio ki Guide.
          const ToolGuideButton(guideId: 'motion'),
          const SizedBox(width: 6),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_kBgTop, _kBgBottom],
          ),
        ),
        child: FeatureGate.isKilled(KillableFeature.motion)
            ? const KilledFeatureNotice()
            : Column(
                children: [
                  _searchBar(),
                  if (_matcherActive && _matches.isNotEmpty)
                    _matchHint(),
                  _categoryRail(),
                  Expanded(child: _grid()),
                ],
              ),
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      child: TextField(
        key: const Key('motionSearchField'),
        onChanged: (v) => setState(() => _query = v),
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Describe a design — English, Roman Urdu, Urdu…',
          hintStyle: const TextStyle(color: Colors.white38),
          prefixIcon: const Icon(Icons.search, color: _kCyan, size: 20),
          filled: true,
          fillColor: const Color(0xFF101B38),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _kCardBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _kCardBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _kBlue, width: 1.6),
          ),
        ),
      ),
    );
  }

  /// v1.26.0 M4: shown under the search bar when the prompt
  /// matcher produced the grid — what matched, and the honest
  /// label for the feature (plan §4: no fake "AI").
  Widget _matchHint() {
    final terms = _matchedTerms;
    return Padding(
      key: const Key('motionMatchHint'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Smart Match — template-based help (not generative AI)',
            style: TextStyle(
              color: _kCyan,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          if (terms.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Matched: ${terms.join(', ')}',
              style:
                  const TextStyle(color: Colors.white54, fontSize: 11.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _categoryRail() {
    final cats = [
      'all',
      if (_mine.isNotEmpty) 'mine',
      if (_recent.isNotEmpty) 'recent',
      if (_favourites.isNotEmpty) 'favourites',
      ...MotionTemplates.presentCategories,
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        key: const Key('motionCategoryRail'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: cats.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final c = cats[i];
          final selected = _category == c;
          final label = c == 'all'
              ? 'All'
              : c == 'mine'
                  ? 'My Templates'
                  : c == 'recent'
                      ? 'Recent'
                      : c == 'favourites'
                          ? 'Favourites'
                          : (MotionCategories.labels[c] ?? c);
          return GestureDetector(
            key: Key('motionCat-$c'),
            onTap: () => setState(() => _category = c),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: selected
                    ? const LinearGradient(colors: [_kBlue, _kPurple])
                    : null,
                color: selected ? null : const Color(0xFF101B38),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? Colors.transparent : _kCardBorder,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: _kBlue.withValues(alpha: 0.45),
                          blurRadius: 12,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontSize: 12.5,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// v1.26.0 M4: the no-match fallback panel (see _grid).
  Widget _noMatchPanel() {
    final suggestions = _suggestedCategories;
    if (suggestions.isEmpty) {
      return const Center(
        child: Text(
          'No design found — try changing the search or category.',
          style: TextStyle(color: Colors.white54, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      );
    }
    // Suggestion chips carry category LABELS; map back to keys.
    final keyByLabel = <String, String>{
      for (final e in MotionCategories.labels.entries) e.value: e.key,
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No design found for "${_query.trim()}" — '
              'these categories may help:',
              style:
                  const TextStyle(color: Colors.white54, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final label in suggestions)
                  if (keyByLabel[label] != null)
                    GestureDetector(
                      key: Key(
                          'motionSuggestChip-${keyByLabel[label]}'),
                      onTap: () => setState(
                          () => _category = keyByLabel[label]!),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF101B38),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _kCardBorder),
                        ),
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _grid() {
    // M4: a prompt that matched nothing gets the honest
    // fallback — suggested categories when the matcher has a
    // weak signal, a plain no-result line when it has none.
    // A template is NEVER dressed up as an "AI result".
    if (_matcherActive && _matches.isEmpty) {
      return _noMatchPanel();
    }
    final items = _visible;
    if (items.isEmpty) {
      return const Center(
        child: Text(
          'No design found — try changing the search or category.',
          style: TextStyle(color: Colors.white54, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      );
    }
    return GridView.builder(
      key: const Key('motionGalleryGrid'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 14,
        childAspectRatio: 0.82,
      ),
      itemCount: items.length,
      itemBuilder: (ctx, i) => _card(items[i]),
    );
  }

  Widget _card(MotionTemplate t) {
    final access = _accessFor(t);
    return GestureDetector(
      key: Key('motionCard-${t.id}'),
      onTap: () => _onTap(t),
      child: Container(
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kCardBorder),
          boxShadow: [
            BoxShadow(
              color: _kBlue.withValues(alpha: 0.12),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(15)),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MotionSceneView(scene: t.scene),
                    if (!t.id.startsWith('mine:'))
                      Positioned(
                        top: 2,
                        left: 2,
                        child: GestureDetector(
                          key: Key('motionFav-${t.id}'),
                          onTap: () => _toggleFavourite(t),
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color:
                                  Colors.black.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              _favourites.contains(t.id)
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              size: 14,
                              color: _favourites.contains(t.id)
                                  ? const Color(0xFFFF5A76)
                                  : Colors.white70,
                            ),
                          ),
                        ),
                      ),
                    if (!access.canUse)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.lock,
                            size: 13,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      MotionCategories.labels[t.category] ?? t.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        const Icon(
                          Icons.timer_outlined,
                          size: 13,
                          color: Colors.white38,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${t.durationSec.toStringAsFixed(0)}s',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                        const Spacer(),
                        _tierLabel(t, access),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The flat tier/price label — it shows the EFFECTIVE price
  /// (remote config included), never the raw tier alone.
  Widget _tierLabel(MotionTemplate t, MotionAccess access) {
    final (String text, Color color, IconData? icon) = switch (access.kind) {
      MotionAccessKind.free => ('FREE', _kGreen, null),
      MotionAccessKind.proIncluded => ('PRO ✓', _kPurple, null),
      MotionAccessKind.owned => ('OWNED', _kCyan, null),
      MotionAccessKind.lockedCoins => (
          '${access.coins} COINS',
          _kGold,
          Icons.monetization_on_outlined,
        ),
      MotionAccessKind.lockedProOnly => (
          'PRO',
          _kPurple,
          Icons.workspace_premium,
        ),
      MotionAccessKind.lockedAd => ('AD', _kCyan, Icons.play_circle_outline),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}
