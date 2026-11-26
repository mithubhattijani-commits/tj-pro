import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/coin_service.dart';
import '../services/feature_gate.dart';
import '../services/performance_engine.dart';
import '../services/remote_config_service.dart';
import '../services/store_audio_preview.dart';
import '../services/store_preview_cache.dart';
import '../services/store_service.dart';
import '../services/unity_ads_service.dart';
import '../theme.dart';
import 'coins_screen.dart';

/// Online Store screen (TJ Pro v1.2.0, plan §3, mockup
/// n-online-store): coins pill header, the 8 Drive category chips,
/// and a scrollable grid of item cards with price / FREE badges and
/// owned state.
///
/// Build 10 (v1.8.0, fix-list point #8 + the user's audio order):
/// the grid is now COMPACT — 3 columns of small boxes, so 9–12
/// items are on screen at once instead of the old 2-wide tall
/// cards — and every AUDIO item carries a play/pause button so
/// it can be heard before it is bought (the store's single
/// preview player: one item sounds at a time, leaving the
/// screen stops it).
///
/// Cache-first by construction: the grid renders instantly from
/// [StoreService.cachedListing] and the owned records on disk, then a
/// background refresh swaps in the live Drive listing. A failed
/// refresh never blanks the screen — it only raises a quiet
/// "showing saved items" note with a retry button.
///
/// Entry gate: opening the store attempts ONE Unity interstitial
/// ([UnityAdsService.showInterstitialAd], which self-caps at one show
/// per 120s). The attempt runs in the background and is never awaited
/// by the UI — if the ad is not ready or fails, the user is simply
/// already inside the store.
class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key, this.initialCategory});

  /// v1.5.0 (#31/#32): the category the store opens on — the Video
  /// Editor's Templates tool and the News Studio Templates/Ribbons
  /// pickers pass 'Templates' / 'Ribbons' so the store lands on that
  /// section. Unknown/absent values fall back to the first category.
  final String? initialCategory;

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  final StoreService _store = StoreService.instance;
  final CoinService _coins = CoinService.instance;

  late String _category = StoreConfig.categories.contains(
    widget.initialCategory,
  )
      ? widget.initialCategory!
      : StoreConfig.categories.first;
  List<StoreItem> _items = const <StoreItem>[];
  Set<String> _ownedIds = <String>{};
  bool _loadingCache = true;
  bool _refreshing = false;
  bool _refreshFailed = false;
  String? _busyItemId;
  bool _entryGateAttempted = false;

  /// The last audio-preview error already surfaced, so the
  /// snackbar fires once per failure, not per rebuild.
  String? _lastAudioErrorShown;

  @override
  void initState() {
    super.initState();
    unawaited(_coins.load());
    unawaited(_loadCategory(_category));
    _attemptEntryGate();
    StoreAudioPreviewPlayer.instance.state.addListener(_onAudioState);
  }

  @override
  void dispose() {
    StoreAudioPreviewPlayer.instance.state
        .removeListener(_onAudioState);
    // Leaving the store stops any sounding preview.
    unawaited(StoreAudioPreviewPlayer.instance.stop());
    super.dispose();
  }

  /// Surfaces a preview-playback failure once (the failing
  /// card itself returns to its play state on its own).
  void _onAudioState() {
    final s = StoreAudioPreviewPlayer.instance.state.value;
    if (s.phase != StoreAudioPhase.error) {
      _lastAudioErrorShown = null;
      return;
    }
    final key = '${s.itemId}:${s.message}';
    if (_lastAudioErrorShown == key || !mounted) return;
    _lastAudioErrorShown = key;
    if (s.message != null) _showMessage(s.message!);
  }

  /// One interstitial as the store entry gate — fire-and-forget.
  /// Never blocks entry and never throws: [UnityAdsService] swallows
  /// its own failures and returns false when nothing is ready.
  void _attemptEntryGate() {
    if (_entryGateAttempted) return;
    _entryGateAttempted = true;
    unawaited(() async {
      try {
        await UnityAdsService.init();
        if (!UnityAdsService.isInitialized) return;
        final loaded = await UnityAdsService.loadInterstitialAd();
        if (!loaded) return;
        await UnityAdsService.showInterstitialAd();
      } catch (_) {
        // Ad gate is best-effort — the store is already open.
      }
    }());
  }

  Future<void> _loadCategory(String category) async {
    final cached = await _store.cachedListing(category);
    final owned = await _store.ownedItems(category);
    if (!mounted || category != _category) return;
    setState(() {
      _items = cached;
      _ownedIds = owned.map((e) => e.id).toSet();
      _loadingCache = false;
    });
    unawaited(_refresh(category));
  }

  Future<void> _refresh(String category) async {
    if (_refreshing || !mounted) return;
    setState(() => _refreshing = true);
    final lastOkBefore = _store.lastSuccessfulRefreshAt;
    final fresh = await _store.refreshCategory(category);
    final owned = await _store.ownedItems(category);
    if (!mounted || category != _category) return;
    setState(() {
      _refreshing = false;
      if (fresh.isNotEmpty) _items = fresh;
      _ownedIds = owned.map((e) => e.id).toSet();
      // Quiet retry state: no successful live refresh happened —
      // the cache stays on screen, never a blank screen.
      _refreshFailed = _store.lastSuccessfulRefreshAt == lastOkBefore;
    });
  }

  Future<void> _selectCategory(String category) async {
    if (category == _category) return;
    // A preview from the old category must not keep sounding
    // over the new one.
    unawaited(StoreAudioPreviewPlayer.instance.stop());
    setState(() {
      _category = category;
      _items = const <StoreItem>[];
      _ownedIds = <String>{};
      _loadingCache = true;
      _refreshFailed = false;
    });
    await _loadCategory(category);
  }

  Future<void> _buy(StoreItem item) async {
    if (_busyItemId != null) return;
    if (_ownedIds.contains(item.id)) {
      _showMessage('Already in your library — available offline.');
      return;
    }
    setState(() => _busyItemId = item.id);
    final result = await _store.purchase(item);
    if (!mounted) return;
    setState(() => _busyItemId = null);
    if (result.ok) {
      setState(() => _ownedIds = <String>{..._ownedIds, item.id});
      _showMessage(
        _store.priceFor(item) == 0
            ? 'Saved to your library.'
            : 'Purchased and saved to your library.',
      );
      return;
    }
    if (result.insufficientBalance) {
      _showInsufficientCoins(item);
      return;
    }
    _showMessage(
      result.error == 'download_failed'
          ? 'Download failed — no coins were taken. Please retry.'
          : 'Purchase failed — no coins were kept. Please retry.',
    );
  }

  void _showInsufficientCoins(StoreItem item) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Not enough coins'),
          content: Text(
            'This item costs ${_store.priceFor(item)} coins. '
            'Watch ads or claim your daily coins to earn more.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Later'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CoinsScreen(),
                  ),
                );
              },
              child: const Text('Earn coins'),
            ),
          ],
        );
      },
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _openCoins() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CoinsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TjProTheme.surfaceNavy,
      appBar: AppBar(
        title: const Text('Online Store'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: _coinsPill()),
          ),
        ],
      ),
      body: ValueListenableBuilder<RemoteConfig>(
        valueListenable: RemoteConfigService.instance.notifier,
        builder: (context, cfg, _) {
          // Build 9 (v1.7.0, point #5): remote kill switch — a
          // killed store shows the polite closed state instead
          // of the catalogue (the AppBar and coins pill above
          // stay exactly as they are).
          if (FeatureGate.isKilled(KillableFeature.store, config: cfg)) {
            return const KilledFeatureNotice();
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
          // Category chips — horizontally scrollable, all 8 categories.
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: StoreConfig.categories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final category = StoreConfig.categories[index];
                final selected = category == _category;
                return ChoiceChip(
                  label: Text(category),
                  selected: selected,
                  onSelected: (_) => unawaited(_selectCategory(category)),
                  selectedColor: TjProTheme.motionBlue,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : null,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                );
              },
            ),
          ),
          if (_refreshFailed && _items.isNotEmpty)
            _quietNote(
              'Showing saved items — could not refresh just now.',
            ),
              Expanded(child: _body()),
            ],
          );
        },
      ),
    );
  }

  /// Gold coins pill (mockup header) — live balance, tap opens Coins.
  Widget _coinsPill() {
    return ValueListenableBuilder<int>(
      valueListenable: _coins.balance,
      builder: (context, value, _) {
        return InkWell(
          onTap: _openCoins,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: TjProTheme.gold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: TjProTheme.gold.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.monetization_on,
                  color: TjProTheme.gold,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  '$value',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: TjProTheme.gold,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _quietNote(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
          TextButton(
            onPressed:
                _refreshing ? null : () => unawaited(_refresh(_category)),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loadingCache) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      // Quiet empty / retry state — never a blank screen.
      return RefreshIndicator(
        onRefresh: () => _refresh(_category),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 48),
            const Icon(
              Icons.storefront_outlined,
              size: 56,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            const Text(
              'No items to show yet.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'New stock appears here automatically. If you are '
              'offline, pull down or tap Retry — saved items will '
              'show as soon as they load.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Center(
              child: OutlinedButton.icon(
                onPressed:
                    _refreshing ? null : () => unawaited(_refresh(_category)),
                icon: const Icon(Icons.refresh),
                label: Text(_refreshing ? 'Retrying…' : 'Retry'),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _refresh(_category),
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          // Build 10 (point #8): compact boxes — 3 columns, so
          // a full screen holds 9–12 items (3–4 rows) instead
          // of the old 2-wide tall cards.
          childAspectRatio: 0.72,
        ),
        itemCount: _items.length,
        itemBuilder: (context, index) => _itemCard(_items[index]),
      ),
    );
  }

  Widget _itemCard(StoreItem item) {
    final price = _store.priceFor(item);
    final owned = _ownedIds.contains(item.id);
    final busy = _busyItemId == item.id;
    final isAudio = storeItemIsAudio(item);
    return Container(
      decoration: TjProTheme.glassCard(),
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The item's REAL preview on top of the card (Build
          // 8) — what it is, how it looks, what colour — before
          // the user spends coins on it. The category badge
          // overlays the preview's top-left corner; the old
          // category icon survives as the preview area's
          // fallback (no preview / load failure = the icon
          // shows, exactly as before).
          // Build 10: audio items also carry the play/pause
          // button at the preview's bottom-right corner.
          AspectRatio(
            aspectRatio: 16 / 10,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _StorePreviewImage(
                    previewId: _store.previewIdFor(item),
                    fallbackIcon: _iconFor(item),
                  ),
                  Positioned(
                    top: 4,
                    left: 4,
                    child: _categoryBadge(item.category),
                  ),
                  if (isAudio)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: _AudioPlayButton(item: item),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Text(
              // Cleaned display name (Build 8) — the technical
              // "(Transparent)" / "(Landscape)" / ... markers
              // no longer clutter the card title. Pricing still
              // reads the RAW name (priceFor).
              item.displayTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (owned)
                const _Badge(
                  label: 'Owned',
                  color: Colors.green,
                  icon: Icons.check_circle,
                )
              else if (price == 0)
                const _Badge(label: 'FREE', color: Colors.green)
              else ...[
                const Icon(
                  Icons.monetization_on,
                  color: TjProTheme.gold,
                  size: 14,
                ),
                const SizedBox(width: 3),
                Text(
                  '$price',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: TjProTheme.gold,
                  ),
                ),
              ],
              const Spacer(),
              IconButton(
                onPressed: busy ? null : () => unawaited(_buy(item)),
                tooltip: owned ? 'Owned — available offline' : 'Get item',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 30,
                  minHeight: 30,
                ),
                iconSize: 19,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        owned ? Icons.download_done : Icons.download,
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _categoryBadge(String category) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        category.toUpperCase(),
        style: const TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  IconData _iconFor(StoreItem item) {
    switch (item.extension) {
      case '.mp3':
      case '.m4a':
      case '.wav':
      case '.ogg':
        return Icons.music_note;
      case '.mp4':
      case '.mov':
        return Icons.play_circle_outline;
      case '.png':
      case '.jpg':
      case '.jpeg':
      case '.gif':
        return Icons.image_outlined;
      default:
        return Icons.auto_awesome_outlined;
    }
  }
}

/// Build 8 (v1.6.0): one store card's preview area. Shows the
/// item's cached preview image ([StorePreviewCache]) when one is
/// available; until then — and on any failure — the card's
/// traditional category icon on the deep preview backdrop the
/// prepared previews were composited on (#14122B), so a card
/// without a preview looks exactly as it did before Build 8.
/// Loading never blocks the list: the icon paints instantly and
/// the image swaps in when the cache lands it.
class _StorePreviewImage extends StatefulWidget {
  const _StorePreviewImage({
    required this.previewId,
    required this.fallbackIcon,
  });

  /// Drive file id of the item's preview, or null when the
  /// item's folder holds no preview file.
  final String? previewId;
  final IconData fallbackIcon;

  @override
  State<_StorePreviewImage> createState() => _StorePreviewImageState();
}

class _StorePreviewImageState extends State<_StorePreviewImage> {
  File? _file;

  @override
  void initState() {
    super.initState();
    StorePreviewCache.instance.revision.addListener(_sync);
    final String? id = widget.previewId;
    if (id != null) {
      _file = StorePreviewCache.instance.cachedFileFor(id);
      unawaited(StorePreviewCache.instance.warm(id));
    }
  }

  @override
  void didUpdateWidget(_StorePreviewImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.previewId != widget.previewId) {
      final String? id = widget.previewId;
      _file = id == null ? null : StorePreviewCache.instance.cachedFileFor(id);
      if (id != null) unawaited(StorePreviewCache.instance.warm(id));
    }
  }

  @override
  void dispose() {
    StorePreviewCache.instance.revision.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    final String? id = widget.previewId;
    if (id == null) return;
    final File? file = StorePreviewCache.instance.cachedFileFor(id);
    if (file != _file) setState(() => _file = file);
  }

  Widget _fallback() {
    return Center(
      child: Icon(
        widget.fallbackIcon,
        color: TjProTheme.violetBright,
        size: 30,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final File? file = _file;
    return Container(
      color: const Color(0xFF14122B),
      child: file == null
          ? _fallback()
          : Image.file(
              file,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              // Build 10 (7B): decode at the engine's per-tier
              // width for these small cards — a 1200 px preview
              // decoded into a ~120 dp box is memory a weak
              // phone cannot spare.
              cacheWidth:
                  PerformanceEngine.instance.config.value.previewThumbCacheWidth,
              errorBuilder: (context, error, stackTrace) => _fallback(),
            ),
    );
  }
}

/// Build 10 (v1.8.0): the play/pause button on an AUDIO item's
/// card — hear it before you buy it. Driven entirely by the
/// store's single preview player ([StoreAudioPreviewPlayer]):
/// this item playing shows pause, this item loading shows a
/// spinner, anything else shows play; starting this item
/// stops whichever item was sounding.
class _AudioPlayButton extends StatelessWidget {
  const _AudioPlayButton({required this.item});

  final StoreItem item;

  @override
  Widget build(BuildContext context) {
    final player = StoreAudioPreviewPlayer.instance;
    return ValueListenableBuilder<StoreAudioPreviewState>(
      valueListenable: player.state,
      builder: (context, s, _) {
        final mine = s.itemId == item.id;
        final loading = mine && s.phase == StoreAudioPhase.loading;
        final playing = mine && s.phase == StoreAudioPhase.playing;
        return Material(
          color: Colors.black.withValues(alpha: 0.55),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: loading
                ? null
                : () => unawaited(player.toggle(item)),
            child: SizedBox(
              width: 28,
              height: 28,
              child: loading
                  ? const Padding(
                      padding: EdgeInsets.all(7),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      playing ? Icons.pause : Icons.play_arrow,
                      size: 17,
                      color: Colors.white,
                    ),
            ),
          ),
        );
      },
    );
  }
}

/// Small pill badge (FREE / Owned) on an item card.
class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 3),
        ],
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
