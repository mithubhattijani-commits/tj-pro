import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/coin_service.dart';
import '../theme.dart';

/// Coins section — News Studio v1 (plan §7 item 18, mockup 1/9).
///
/// * Balance (updates immediately — [CoinService.balance] is a
///   [ValueNotifier] fed on every earn/spend).
/// * "Watch Ads, Earn Coins" button: one tap → one Unity rewarded ad
///   on the coins placement → 25 coins on full watch (v1.8.0),
///   up to 50 ads/day.
///   v1.5.2 (fix #66): shown for EVERYONE, admins included — it used
///   to be hidden for admins, which on the owner's own phone read
///   as "the earning button does not exist". (Admin spends stay
///   waived; earning is open to all.)
/// * Daily free claim (50 coins, once per calendar day).
/// * Earn/spend history (server ledger, on-device cache offline).
/// * Price list — v1.5.2 (fix #66): ONLY what actions actually
///   charge. Export resolutions carry NO coin price (720p is
///   free; 1080p / 4K run with ads alongside) and are listed as
///   FREE rows; features nothing spends (auto captions,
///   multi-platform publish) are not listed at all.
///
/// The screen never decides admin status itself: it listens to
/// [AuthService.isAdmin], which is fed only by the server-side
/// `tjpro-is-admin` check.
class CoinsScreen extends StatefulWidget {
  const CoinsScreen({super.key});

  @override
  State<CoinsScreen> createState() => _CoinsScreenState();
}

class _CoinsScreenState extends State<CoinsScreen> {
  final CoinService _coins = CoinService.instance;

  bool _adBusy = false;
  bool _dailyBusy = false;
  String? _message;
  List<CoinLedgerEntry>? _history;
  bool _historyLoading = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    if (_historyLoading) return;
    setState(() => _historyLoading = true);
    final entries = await _coins.fetchHistory();
    if (!mounted) return;
    setState(() {
      _history = entries;
      _historyLoading = false;
    });
  }

  Future<void> _watchAd() async {
    if (_adBusy) return;
    setState(() {
      _adBusy = true;
      _message = null;
    });
    final result = await _coins.watchRewardedAd();
    if (!mounted) return;
    setState(() {
      _adBusy = false;
      _message = result.ok
          ? '+${result.coins} coins earned!'
          : (result.error ?? 'Could not earn coins. Please try again.');
    });
    if (result.ok) unawaited(_loadHistory());
  }

  Future<void> _claimDaily() async {
    if (_dailyBusy) return;
    setState(() {
      _dailyBusy = true;
      _message = null;
    });
    final ok = await _coins.claimDaily();
    if (!mounted) return;
    setState(() {
      _dailyBusy = false;
      _message = ok
          ? '+${CoinService.dailyFreeCoins} daily coins claimed!'
          : 'Daily coins already claimed today. Come back tomorrow.';
    });
    if (ok) unawaited(_loadHistory());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Coins')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Balance card.
            Card(
              color: TjProTheme.gold.withValues(alpha: 0.12),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Text(
                      'Your balance',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    ValueListenableBuilder<int>(
                      valueListenable: _coins.balance,
                      builder: (context, value, _) {
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.monetization_on,
                              color: TjProTheme.gold,
                              size: 32,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$value',
                              style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'coins',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Watch Ads button — v1.5.2 (fix #66): for EVERYONE,
            // admins included (it was admin-hidden, which is why
            // the owner could not find any earning button here).
            ValueListenableBuilder<int>(
              valueListenable: _coins.adsWatchedToday,
              builder: (context, watched, _) {
                final remaining = CoinService.maxRewardedAdsPerDay - watched;
                final canWatch =
                    remaining > 0 && !_adBusy && !_coins.isLoading.value;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton.icon(
                      key: const Key('coinsWatchAdButton'),
                      onPressed: canWatch ? _watchAd : null,
                      icon: const Icon(Icons.play_circle_fill),
                      label: Text(
                        _adBusy
                            ? 'Loading ad…'
                            : 'Watch Ads, Earn Coins  •  +${CoinService.rewardPerAd} coins',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: TjProTheme.gold,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Ads watched today: $watched / '
                      '${CoinService.maxRewardedAdsPerDay} '
                      '(max ${CoinService.maxAdCoinsPerDay} coins/day)',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            // Daily free claim.
            OutlinedButton.icon(
              onPressed: _dailyBusy ? null : _claimDaily,
              icon: const Icon(Icons.card_giftcard),
              label: Text(
                _dailyBusy
                    ? 'Claiming…'
                    : 'Claim daily free coins  •  +${CoinService.dailyFreeCoins}',
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(
                _message!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14),
              ),
            ],
            const SizedBox(height: 20),
            const Text(
              'Prices',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    // v1.5.2 (fix #66): the list is CURATED to
                    // what actions actually charge — the old list
                    // iterated every CoinFeature and so advertised
                    // the abolished export coin prices (720p 50 /
                    // 1080p 100 / 4K 200) plus two features
                    // nothing spends. Export is FREE (ads model);
                    // chroma inside an export is the only
                    // export-related charge, listed on its own.
                    for (final (label, price) in const [
                      ('One Click AI News Maker', '100 coins'),
                      ('Voiceover', '50 coins'),
                      ('Chroma key', '50 coins'),
                      ('Premium template', '25 coins'),
                      ('AI Enhance (Photo / Video)', '50 coins'),
                      ('Export 720p', 'FREE'),
                      ('Export 1080p', 'FREE • ads ke sath'),
                      ('Export 4K', 'FREE • ads ke sath'),
                    ])
                      ListTile(
                        dense: true,
                        title: Text(label),
                        trailing: Text(
                          price,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Text(
                  'History',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadHistory,
                  tooltip: 'Refresh history',
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_historyLoading && _history == null)
              const Center(child: CircularProgressIndicator())
            else if (_history == null || _history!.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No coin activity yet. Watch an ad or claim your '
                    'daily coins to get started.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              Card(
                child: Column(
                  children: [
                    for (final entry in _history!)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          entry.isEarn
                              ? Icons.add_circle_outline
                              : Icons.remove_circle_outline,
                          color: entry.isEarn ? Colors.green : Colors.red,
                        ),
                        title: Text(_historyLabel(entry)),
                        subtitle: Text(_formatDate(entry.createdAt)),
                        trailing: Text(
                          '${entry.isEarn ? '+' : ''}${entry.amountCoins}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color:
                                entry.isEarn ? Colors.green : Colors.red,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _historyLabel(CoinLedgerEntry entry) {
    switch (entry.reason) {
      case CoinCosts.reasonAdReward:
        return 'Rewarded ad';
      case CoinCosts.reasonDaily:
        return 'Daily free coins';
      default:
        return entry.reason.replaceAll('_', ' ');
    }
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/${local.year} $hour:$minute';
  }
}
