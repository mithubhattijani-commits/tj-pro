import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/coin_service.dart';
import '../services/supabase_service.dart';
import '../theme.dart';
import '../widgets/help_whatsapp_button.dart';

/// Login screen — News Studio v1, mockup 9
/// (`~/workspace/tj-pro-news-maker/login.png`).
///
/// * "Continue with Google" (white button) — native Google sign-in.
/// * Email + password — Login / Register switch + Forgot password.
/// * "Coins kaise kamayein" card (1 rewarded ad = 50 coins, daily
///   free 50, max 20 ads/day = 1000 coins/day).
/// * "Admins — sab kuch free" card (the 3 admin emails, display
///   only — the free access is enforced server-side).
/// * Note: guest coins are preserved on login (anon → linked).
/// * "For Help" row with WhatsApp button (remote-config number).
///
/// Shown whenever there is no signed-in session. [onSignedIn] fires
/// after a successful sign-in / register; [onContinueAsGuest] lets
/// the user keep earning guest coins without an account (Phase 2
/// decides where the gate sits — this screen never forces login for
/// guest earning).
class LoginScreen extends StatefulWidget {
  final VoidCallback onSignedIn;
  final VoidCallback? onContinueAsGuest;

  const LoginScreen({
    super.key,
    required this.onSignedIn,
    this.onContinueAsGuest,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Login first: most returning users just need to sign in; Register
  // with an existing email signs in anyway (see AuthService).
  bool _isRegister = false;
  bool _busy = false;
  bool _showPassword = false;
  bool _resetSent = false;
  String? _error;
  String? _info;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _switchMode(bool register) {
    if (_busy) return;
    setState(() {
      _isRegister = register;
      _error = null;
      _info = null;
      _resetSent = false;
    });
  }

  Future<void> _submitEmail() async {
    if (_busy) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (!AuthService.isValidEmail(email)) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final result = _isRegister
        ? await AuthService.registerWithEmail(
            email: email,
            password: password,
          )
        : await AuthService.signInWithEmail(
            email: email,
            password: password,
          );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.ok) {
      // Coins earned as a guest move with the linked account; refresh
      // the balance now so the app-bar pill is correct immediately.
      unawaited(CoinService.instance.syncFromServer());
      widget.onSignedIn();
      return;
    }
    setState(
      () => _error = result.error ?? 'Sign-in failed. Please try again.',
    );
  }

  Future<void> _signInGoogle() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final result = await AuthService.signInWithGoogle();
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.ok) {
      unawaited(CoinService.instance.syncFromServer());
      widget.onSignedIn();
      return;
    }
    setState(
      () => _error = result.error ?? 'Sign-in failed. Please try again.',
    );
  }

  Future<void> _forgotPassword() async {
    if (_busy) return;
    final email = _emailController.text.trim();
    if (!AuthService.isValidEmail(email)) {
      setState(
        () => _error =
            'Enter your email above first, then tap Forgot password.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final result = await AuthService.resetPassword(email: email);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.ok) {
      setState(() {
        _resetSent = true;
        _info = 'Password reset email sent to $email. '
            'Check your inbox (and spam folder).';
      });
      return;
    }
    setState(
      () => _error = result.error ?? 'Could not send the reset email.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.movie_filter_outlined,
                  size: 72,
                  color: TjProTheme.gold,
                ),
                const SizedBox(height: 16),
                const Text(
                  'TJ Pro — News Studio',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Sign in to save your coins and projects.\n'
                  'Your coins stay with your account, so they '
                  'are safe even if you reinstall the app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Colors.grey),
                ),
                const SizedBox(height: 28),
                // Continue with Google — first, per mockup 9.
                ElevatedButton(
                  onPressed: _busy ? null : _signInGoogle,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Colors.grey),
                  ),
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'G',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF4285F4),
                              ),
                            ),
                            SizedBox(width: 12),
                            Text(
                              'Continue with Google',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 24),
                const Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'ya email se',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 20),
                // Login / Register switch.
                Row(
                  children: [
                    Expanded(
                      child: _ModeButton(
                        label: 'Login',
                        selected: !_isRegister,
                        onTap: () => _switchMode(false),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ModeButton(
                        label: 'Register',
                        selected: _isRegister,
                        onTap: () => _switchMode(true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'you@example.com',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _passwordController,
                  obscureText: !_showPassword,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  enabled: !_busy,
                  onSubmitted: (_) => _submitEmail(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    hintText: 'At least 6 characters',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: _busy
                          ? null
                          : () => setState(
                                () => _showPassword = !_showPassword,
                              ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: _busy ? null : _submitEmail,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TjProTheme.gold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _isRegister ? 'Register' : 'Login',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy ? null : _forgotPassword,
                  child: const Text('Forgot password?'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red, fontSize: 14),
                  ),
                ],
                if (_info != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _info!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontSize: 14,
                    ),
                  ),
                ],
                if (_resetSent) const SizedBox(height: 4),
                const SizedBox(height: 20),
                // Coins kaise kamayein card.
                _InfoCard(
                  title: 'Coins kaise kamayein',
                  icon: Icons.monetization_on_outlined,
                  lines: <String>[
                    '1 rewarded ad = ${CoinService.rewardPerAd} coins',
                    'Daily free coins = ${CoinService.dailyFreeCoins}',
                    'Max ${CoinService.maxRewardedAdsPerDay} ads/day = '
                        '${CoinService.maxAdCoinsPerDay} coins/day',
                  ],
                ),
                const SizedBox(height: 12),
                // Admins card (display only — free access is server-side).
                _InfoCard(
                  title: 'Admins — sab kuch free, no coins, no ads',
                  icon: Icons.admin_panel_settings_outlined,
                  lines: SupabaseService.adminEmails,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Guest coins login par save rehte hain '
                  '(anon → linked).',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                if (widget.onContinueAsGuest != null) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _busy ? null : widget.onContinueAsGuest,
                    child: const Text('Continue as guest'),
                  ),
                ],
                const SizedBox(height: 20),
                const HelpWhatsAppRow(),
                const SizedBox(height: 16),
                const Text(
                  'Nigraan TV  •  TJ Pro News Studio',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor:
            selected ? theme.colorScheme.primary : Colors.transparent,
        foregroundColor: selected
            ? theme.colorScheme.onPrimary
            : theme.colorScheme.onSurface,
        side: BorderSide(
          color: selected ? theme.colorScheme.primary : Colors.grey,
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<String> lines;

  const _InfoCard({
    required this.title,
    required this.icon,
    required this.lines,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: TjProTheme.gold),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '•  $line',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
