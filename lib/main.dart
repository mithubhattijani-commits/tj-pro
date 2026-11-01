/// TJ Pro — home screen.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'photo/photo_editor_screen.dart';
import 'app_config.dart';
import 'services/ad_service.dart';
import 'services/unity_ads_service.dart';
import 'services/update_service.dart';
import 'video/video_editor_screen.dart';
import 'live/live_studio_screen.dart';
import 'widgets/banner_ad_widget.dart';
import 'widgets/native_ad_widget.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AdService.init();
  UnityAdsService.init();
  runApp(const PhotoVideoEditorApp());
}

class PhotoVideoEditorApp extends StatelessWidget {
  const PhotoVideoEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal, brightness: Brightness.dark),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Silent update check: shows a dialog only when a newer version
    // exists; a missing manifest or no network means no prompt at all.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Cold-start app open ad first; the update dialog waits for the
      // next launch when an ad was shown, so the two never stack.
      if (!AdService.showAppOpen()) {
        UpdateService.checkOnLaunch(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppConfig.appName)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            AppConfig.homeHeading,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          if (AppConfig.photoEditorEnabled)
            _EntryCard(
              icon: Icons.photo,
            title: 'Photo Editor',
            subtitle:
                'Filters, crop, rotate, brightness, text, AI tools',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PhotoEditorScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          if (AppConfig.videoEditorEnabled)
            _EntryCard(
              icon: Icons.videocam,
            title: 'Video Editor',
            subtitle:
                'Trim, cut & merge, text, music, speed, filters, crossfade',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const VideoEditorScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          if (AppConfig.liveStudioEnabled)
            _EntryCard(
              icon: Icons.live_tv,
              title: 'Live Studio',
              subtitle:
                  'Facebook + YouTube par ek saath live — breaking news templates ke saath',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LiveStudioScreen(),
                  ),
                );
              },
            ),
          const SizedBox(height: 16),
          const NativeAdWidget(),
          const SizedBox(height: 16),
          const _PremiumUnlockCard(),
          const SizedBox(height: 16),
          const Text(
            'Works offline. No account, no uploads — '
            'everything is processed on your phone. '
            'Basic editing is free; Premium AI tools unlock '
            'with one short ad.',
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.system_update),
              title: const Text('Check for updates'),
              subtitle: const Text(
                'Naya version aaye to yahan se update karein.',
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 18),
              onTap: () => UpdateService.checkManually(context),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.support_agent),
              title: const Text('مدد اور سپورٹ'),
              subtitle: const Text('Jaani Bhatti — 03090808180'),
              trailing: const Icon(Icons.chat),
              onTap: () async {
                final uri = Uri.parse('https://wa.me/923090808180');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
          ),
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline),
                      SizedBox(width: 8),
                      Text(
                        'About',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'TJ Pro by Nigraan TV — photo & video editor that '
                    'works fully offline on your phone. No account, no '
                    'uploads.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const AdvertisingBanner(),
          const SizedBox(height: 16),
          const Center(child: BannerAdWidget()),
        ],
      ),
    );
  }
}

/// In-app advertising banner (Jaani, 2 Nov 2026): placed in the About
/// section on the home screen. Tapping opens a WhatsApp chat with
/// Nigraan TV for ad bookings.
class AdvertisingBanner extends StatelessWidget {
  const AdvertisingBanner({super.key});

  static const String _waUrl = 'https://wa.me/923090808180';

  Future<void> _openWhatsApp() async {
    final Uri uri = Uri.parse(_waUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 3,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: _openWhatsApp,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF0F2027),
                Color(0xFF203A43),
                Color(0xFF2C5364),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/jaani_ad_banner.jpg',
                  width: 84,
                  height: 112,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'For Advertising',
                      style: TextStyle(
                        color: Color(0xFFFFD76A),
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Contact Us on WhatsApp:',
                      style:
                          TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.chat,
                            color: Color(0xFF25D366), size: 18),
                        SizedBox(width: 6),
                        Text(
                          '03090808180',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PremiumUnlockCard extends StatefulWidget {
  const _PremiumUnlockCard();

  @override
  State<_PremiumUnlockCard> createState() => _PremiumUnlockCardState();
}

class _PremiumUnlockCardState extends State<_PremiumUnlockCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.aiToolsEnabled) {
      return const SizedBox.shrink();
    }
    if (AdService.isPremiumUnlocked) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.workspace_premium),
          title: Text('Premium AI unlocked'),
          subtitle: Text('All AI tools are available.'),
        ),
      );
    }
    return Card(
      child: ListTile(
        leading: const Icon(Icons.workspace_premium),
        title: const Text('Premium AI tools'),
        subtitle: const Text(
          'Background remover, blur, beautify and auto-enhance.',
        ),
        trailing: _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(
                onPressed: () async {
                  setState(() => _busy = true);
                  final messenger = ScaffoldMessenger.of(context);
                  final ok = await AdService.showRewarded();
                  if (mounted) {
                    setState(() => _busy = false);
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          ok
                              ? 'Premium AI unlocked.'
                              : 'No ad was available right now. Try again.',
                        ),
                      ),
                    );
                  }
                },
                child: const Text('Watch ad'),
              ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(icon, size: 44, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}


