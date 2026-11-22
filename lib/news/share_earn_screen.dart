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
      SnackBar(content: Text('$label copy ho gaya.')),
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
              ? 'Mubarak! Aap ko $coins referral coins mil gaye.'
              : 'Abhi koi naya reward nahi — jab aap ke link se koi '
                  'naya user login karke pehla ad dekhe ga, 100 coins '
                  'yahan aa jayenge.',
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
              ? 'Code lag gaya — login karke pehla ad dekhein, '
                  'share karne wale ko 100 coins mil jayenge.'
              : 'Ye code nahi lag saka (ghalat code, ya is phone par '
                  'pehle se ek code laga hua hai).',
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
            'Aap ke link se jo naya user ayega, login karke pehla ad '
            'dekhe ga to aap ko 100 coins milenge.',
            style: TextStyle(fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 8),
          const Text(
            'Link ke andar aap ka code khud shamil hai — naye user '
            'ko kuch bhi likhne ki zaroorat nahi. Har naye user par '
            'reward sirf ek dafa milta hai.',
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
                        tooltip: 'Code copy karein',
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
                        tooltip: 'Link copy karein',
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
                      label: const Text('Share karein'),
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
                    'Aap ki kamai',
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
                            label: 'Log join hue',
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
                            label: 'Coins mile',
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
                      label: const Text('Rewards check karein'),
                      onPressed: _busy ? null : _checkRewards,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Rewards app khulne par khud bhi check ho jate '
                    'hain — coins seedha aap ke balance mein jurte '
                    'hain.',
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
            title: const Text('Code haath se darj karein'),
            subtitle: const Text(
              'Sirf tab, jab kisi dost ne sirf code bheja ho.',
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
                      child: const Text('Lagayein'),
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
