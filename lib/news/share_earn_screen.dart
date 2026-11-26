import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/referral_service.dart';
import '../theme.dart';

/// Share & Earn screen (user spec, 22 Nov 2026).
///
/// Shows the user's own referral code + share link, a system Share
/// button, and their stats (people joined, coins earned). The link
/// carries the code INSIDE it — a new user never types anything:
/// install → login → first ad watched → the sharer gets 100 coins
/// (claimed automatically by [ReferralService] on app open; the
/// button here re-checks on demand). A manual code field sits at
/// the bottom as a LAST-RESORT fallback only, for the rare install
/// where no automatic capture channel fired.
class ShareEarnScreen extends StatefulWidget {
  const ShareEarnScreen({super.key});

  @override
  State<ShareEarnScreen> createState() => _ShareEarnScreenState();
}

class _ShareEarnScreenState extends State<ShareEarnScreen> {
  final ReferralService _ref = ReferralService.instance;
  final TextEditingController _manualCode = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _manualCode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _ref.ensureMyCode();
    await _ref.syncWithServer();
    if (mounted) setState(() {});
  }

  Future<void> _copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied.')),
    );
  }

  Future<void> _share() async {
    await _ref.ensureMyCode();
    if (!mounted) return;
    await SharePlus.instance.share(
      ShareParams(text: _ref.shareText),
    );
  }

  Future<void> _checkRewards() async {
    if (_busy) return;
    setState(() => _busy = true);
    final coins = await _ref.claimRewards();
    await _ref.refreshStats();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          coins > 0
              ? 'Congratulations! You received $coins referral coins.'
              : 'No new reward yet — when someone from your link '
                  'a new user logs in and watches the first ad, 100 coins '
                  'will come here.',
        ),
      ),
    );
  }

  Future<void> _applyManualCode() async {
    final ok = await _ref.applyManualCode(_manualCode.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Code applied — log in and watch the first ad; '
                  'the sharer will get 100 coins.'
              : 'This code could not be applied (wrong code, or a code is already '
                  'a code is already applied on this phone).',
        ),
      ),
    );
    if (ok) _manualCode.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Share & Earn')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Row(
            children: [
              Icon(Icons.group_add, size: 40, color: TjProTheme.gold),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Doston ko bulayein, coins kamayein',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'A new user who comes from your link and, after logging in, '
            'watches it, you will get 100 coins.',
            style: TextStyle(fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your code is included inside the link itself — the new user '
            'does not need to write anything. On each new user, '
            'the reward is given only once.',
            style: TextStyle(color: Colors.grey, height: 1.4),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Aap ka referral code',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: ValueListenableBuilder<String?>(
                          valueListenable: _ref.myCode,
                          builder: (context, code, _) => Text(
                            code ?? '…',
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        tooltip: 'Copy code',
                        onPressed: () {
                          final code = _ref.myCode.value;
                          if (code != null) {
                            unawaited(_copy(code, 'Code'));
                          }
                        },
                      ),
                    ],
                  ),
                  const Divider(),
                  const Text(
                    'Aap ka share link',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: ValueListenableBuilder<String?>(
                          valueListenable: _ref.myCode,
                          builder: (context, code, _) => Text(
                            _ref.shareLink,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.link),
                        tooltip: 'Copy link',
                        onPressed: () =>
                            unawaited(_copy(_ref.shareLink, 'Link')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.share),
                      label: const Text('Share'),
                      onPressed: () => unawaited(_share()),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your earnings',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ValueListenableBuilder<int>(
                          valueListenable: _ref.joinedCount,
                          builder: (context, n, _) => _StatBox(
                            icon: Icons.people,
                            value: '$n',
                            label: 'People joined',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ValueListenableBuilder<int>(
                          valueListenable: _ref.earnedCoins,
                          builder: (context, n, _) => _StatBox(
                            icon: Icons.monetization_on,
                            value: '$n',
                            label: 'Coins received',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ValueListenableBuilder<int>(
                          valueListenable: _ref.pendingClaimCount,
                          builder: (context, n, _) => _StatBox(
                            icon: Icons.hourglass_top,
                            value: '$n',
                            label: 'Rewards baqi',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.redeem),
                      label: const Text('Check rewards'),
                      onPressed: _busy ? null : _checkRewards,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Rewards are also checked automatically when the app opens '
                    'they are — the coins join your balance directly '
                    'are.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Last-resort fallback ONLY: the automatic channels (link,
          // clipboard) cover normal installs. This stays collapsed
          // and refuses to override an already-captured code.
          ExpansionTile(
            leading: const Icon(Icons.keyboard),
            title: const Text('Enter the code by hand'),
            subtitle: const Text(
              'Only when a friend sent just the code.',
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _manualCode,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          hintText: 'Referral code',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => unawaited(_applyManualCode()),
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: TjProTheme.gold),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.grey, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
