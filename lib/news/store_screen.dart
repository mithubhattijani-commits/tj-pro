import 'dart:async';

import 'package:flutter/material.dart';

import '../services/coin_service.dart';
import '../services/store_service.dart';
import '../services/unity_ads_service.dart';
import '../theme.dart';
import 'coins_screen.dart';

/// Online Store screen (TJ Pro v1.2.0, plan §3, mockup
/// n-online-store): coins pill header, the 8 Drive category chips,
/// and a scrollable grid of item cards with price / FREE badges and
/// owned state.
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
  const StoreScreen({super.key});

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  final StoreService _store = StoreService.instance;
  final CoinService _coins = CoinService.instance;

  String _category = StoreConfig.categories.first;
  List<StoreItem> _items = const <StoreItem>[];
  Set<String> _ownedIds = <String>{};
  bool _loadingCache = true;
  bool _refreshing = false;
  bool _refreshFailed = false;
  String? _busyItemId;
  bool _entryGateAttempted = false;

  @override
  void initState() {
    super.initState();
    unawaited(_coins.load());
    unawaited(_loadCategory(_category));
    _attemptEntryGate();
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
      body: Column(
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
                  selectedColor: TjProTheme.violet,
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
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.78,
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
    return Container(
      decoration: TjProTheme.glassCard(),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _categoryBadge(item.category),
              const Spacer(),
              Icon(
                _iconFor(item),
                color: TjProTheme.violetBright,
                size: 28,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Text(
              item.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
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
                  size: 18,
                ),
                const SizedBox(width: 4),
                Text(
                  '$price',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: TjProTheme.gold,
                  ),
                ),
              ],
              const Spacer(),
              IconButton(
                onPressed: busy ? null : () => unawaited(_buy(item)),
                tooltip: owned ? 'Owned — available offline' : 'Get item',
                icon: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        category.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.6,
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
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
