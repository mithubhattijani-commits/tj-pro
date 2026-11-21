import 'package:flutter/material.dart';

import '../news/coins_screen.dart';
import '../services/auth_service.dart';
import '../services/coin_service.dart';
import '../theme.dart';

/// Coins balance pill for the app bar (Phase 10, login/coins wiring).
///
/// Shows the live balance from [CoinService.balance]; tapping opens
/// [CoinsScreen]. HIDDEN for admins (server-confirmed via
/// [AuthService.isAdmin]) — for them everything is free and there is
/// nothing to earn, so no pill at all. Renders nothing but a
/// [SizedBox.shrink] when the balance is unknown (never initialized)
/// — the pill only appears once [CoinService.load] has run at startup.
class CoinsPill extends StatelessWidget {
  const CoinsPill({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AuthService.isAdmin,
      builder: (context, isAdmin, _) {
        if (isAdmin) return const SizedBox.shrink();
        return ValueListenableBuilder<int>(
          valueListenable: CoinService.instance.balance,
          builder: (context, balance, _) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                key: const Key('coinsPill'),
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CoinsScreen(),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: TjProTheme.gold.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: TjProTheme.gold),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.monetization_on,
                        color: TjProTheme.gold,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$balance',
                        key: const Key('coinsPillBalance'),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
