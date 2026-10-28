/// TJ Pro — home screen.
library;

import 'package:flutter/material.dart';

import 'photo/photo_editor_screen.dart';
import 'app_config.dart';
import 'services/ad_service.dart';
import 'services/update_service.dart';
import 'video/video_editor_screen.dart';
import 'live/live_studio_screen.dart';
import 'widgets/banner_ad_widget.dart';
import 'widgets/native_ad_widget.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AdService.init();
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
        useMaterial3: true,
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
          const Center(child: BannerAdWidget()),
        ],
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
                  final ok = await AdService.showRewarded();
                  if (mounted) {
                    setState(() => _busy = false);
                    ScaffoldMessenger.of(context).showSnackBar(
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


