/// News Studio home (Phase 2).
///
/// Shows the LIVE Phase 2 model state — the selected channel preset with
/// its three ribbons and the breaking-news templates — so the home card
/// and the bottom-nav tab have a real screen to open. Nothing here is a
/// dead button: every row shows stored state, and the Help row opens
/// the real WhatsApp chat. Destinations are grouped: News banao /
/// Studio / Voice & Captions / Publish, with Coins and Advertise as
/// slim rows at the bottom.
///
/// Phase 10 wired the login/coins track in here too (Coins tile +
/// Advertise page) — the coins balance pill lives in the home app bar.
library;

import 'package:flutter/material.dart';

import '../services/asset_download_service.dart';
import '../services/coin_service.dart';
import '../services/project_recovery.dart';
import '../widgets/help_whatsapp_button.dart';
import 'advertise_screen.dart';
import 'ai_news_maker_screen.dart';
import 'audio_tools_screen.dart';
import 'breaking_templates.dart';
import 'caption_studio_screen.dart';
import 'channel_branding_screen.dart';
import 'channel_preset.dart';
import 'coins_screen.dart';
import 'export_screen.dart';
import 'news_maker_screen.dart';
import 'news_project.dart';
import 'seo_screen.dart';
import 'template_studio_screen.dart';
import 'templates_library_screen.dart';
import 'tts_studio_screen.dart';
import 'widgets/breaking_preview.dart';
import 'widgets/draft_recovery_card.dart';
import 'widgets/nigraan_final_preview.dart';

class NewsStudioScreen extends StatefulWidget {
  const NewsStudioScreen({super.key});

  @override
  State<NewsStudioScreen> createState() => _NewsStudioScreenState();
}

class _NewsStudioScreenState extends State<NewsStudioScreen> {
  Future<_StudioData> _data = _load();

  /// True after the user taps "Baad mein" on the recovery card —
  /// hides it for this session only (the draft JSON stays).
  bool _draftDismissed = false;

  void _reload() {
    setState(() {
      _data = _load();
      _draftDismissed = false;
    });
  }

  static Future<_StudioData> _load() async {
    final presets = await ChannelPresetStore.loadAll();
    final selectedId = await ChannelPresetStore.loadSelectedId();
    final templates = await BreakingTemplateStore.loadAll();
    final latestProject = await NewsProjectStore.loadLatest();
    final preset = selectedId == null
        ? presets.first
        : presets.firstWhere(
            (p) => p.id == selectedId,
            orElse: () => presets.first,
          );
    // Kasheeda for the home preview: load it when cached, otherwise
    // the preview renders Urdu in the fallback font (never a crash).
    var fontReady = false;
    try {
      final cached = await const AssetDownloadService()
          .cachedFile(AssetDownloadService.kasheedaFileName);
      if (cached != null) {
        await AssetDownloadService.loadKasheedaFontFromFile(cached);
        fontReady = true;
      }
    } catch (_) {
      fontReady = false;
    }
    return _StudioData(
      preset: preset,
      presetCount: presets.length,
      templates: templates,
      fontReady: fontReady,
      draft: findRecoverableDraft(latestProject),
    );
  }

  Future<void> _resumeDraft(
    BuildContext context,
    RecoverableDraft draft,
    ChannelPreset preset,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NewsMakerScreen(
          initialPreset: preset,
          initialProject: draft.project,
        ),
      ),
    );
    _reload();
  }

  Future<void> _discardDraft(RecoverableDraft draft) async {
    await NewsProjectStore.delete(draft.project.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('News Studio')),
      body: FutureBuilder<_StudioData>(
        future: _data,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          final preset = data.preset;
          return ListView(
            key: const Key('newsStudioList'),
            padding: const EdgeInsets.all(20),
            children: [
              // Phase 9 — project recovery: the autosaved draft is
              // offered back here (resume / discard / dismiss).
              if (data.draft != null && !_draftDismissed) ...[
                DraftRecoveryCard(
                  draft: data.draft!,
                  onResume: () =>
                      _resumeDraft(context, data.draft!, preset),
                  onDiscard: () => _discardDraft(data.draft!),
                  onDismiss: () =>
                      setState(() => _draftDismissed = true),
                ),
                const SizedBox(height: 12),
              ],
              _SectionTitle('Channel — ${preset.name}'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Template: ${preset.templateKind == 'breaking' ? 'Breaking • ${BreakingVariant.fromId(preset.breakingVariant).label}' : preset.templateKind == 'classic' ? 'Classic' : 'Final 3-Ribbon'}',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        preset.logoPath == null
                            ? 'Logo: default (3D rotate on)'
                            : 'Logo: custom (3D rotate on)',
                      ),
                      const SizedBox(height: 12),
                      _RibbonRow(
                        label: 'Top ticker',
                        kind: 'Current story',
                        ribbon: preset.topRibbon,
                      ),
                      _RibbonRow(
                        label: 'Middle Urdu',
                        kind: 'National news',
                        ribbon: preset.urduRibbon,
                      ),
                      _RibbonRow(
                        label: 'Bottom English',
                        kind: 'International',
                        ribbon: preset.englishRibbon,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${data.presetCount} channel preset(s) — create/edit in '
                'Template & Studio.',
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),
              const _SectionTitle('Template preview'),
              Center(
                child: preset.templateKind == kTemplateFinal
                    ? NigraanFinalPreview(
                        preset: preset,
                        fontReady: data.fontReady,
                        height: 280,
                      )
                    : preset.templateKind == kTemplateBreaking
                        ? BreakingTemplatePreview(
                            template: BreakingTemplate.fromPreset(preset),
                            preset: preset,
                            fontReady: data.fontReady,
                            height: 280,
                          )
                        : ClassicPreview(
                            preset: preset,
                            fontReady: data.fontReady,
                            height: 280,
                          ),
              ),
              const SizedBox(height: 20),
              const _SectionTitle('News banao'),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.edit_note),
                  title: const Text('News Maker'),
                  subtitle: const Text(
                    'Tehreer → Gemini voice → clips → template preview',
                  ),
                  trailing: const Icon(Icons.arrow_forward),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const NewsMakerScreen(),
                      ),
                    );
                    _reload();
                  },
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.auto_awesome),
                  title: const Text('One Click AI News Maker'),
                  subtitle: const Text(
                    'Paste tehreer → 13 steps → voice + preview',
                  ),
                  trailing: const Icon(Icons.arrow_forward),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AiNewsMakerScreen(),
                      ),
                    );
                    _reload();
                  },
                ),
              ),
              const SizedBox(height: 20),
              const _SectionTitle('Studio'),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.tune),
                  title: const Text('Template & Studio'),
                  subtitle: const Text(
                    'Template, ticker, ribbons, lower third, chroma key, '
                    'intro/outro',
                  ),
                  trailing: const Icon(Icons.arrow_forward),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const TemplateStudioScreen(),
                      ),
                    );
                    // Settings changed there — reload the live state.
                    _reload();
                  },
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.branding_watermark),
                  title: const Text('Channel Branding'),
                  subtitle: const Text(
                    'Logo, brand colours, social handles, watermark, '
                    'intro/outro — naye projects par auto-apply',
                  ),
                  trailing: const Icon(Icons.arrow_forward),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ChannelBrandingScreen(initialPreset: preset),
                      ),
                    );
                    // Branding may have changed there — reload.
                    _reload();
                  },
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.dashboard_customize),
                  title: const Text('Templates Library'),
                  subtitle: Text(
                    '${data.templates.length} breaking templates — 13 '
                    'categories + Final 3-Ribbon + Classic + customs',
                  ),
                  trailing: const Icon(Icons.arrow_forward),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const TemplatesLibraryScreen(),
                      ),
                    );
                    // Templates may have changed there — reload.
                    _reload();
                  },
                ),
              ),
              const SizedBox(height: 20),
              const _SectionTitle('Voice & Captions'),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.record_voice_over),
                  title: const Text('AI Voice Studio'),
                  subtitle: const Text(
                    '8 voices, speed/pause, tone, music, MP3/WAV — 5/day cap',
                  ),
                  trailing: const Icon(Icons.arrow_forward),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const TtsStudioScreen(),
                      ),
                    );
                    _reload();
                  },
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.subtitles),
                  title: const Text('Caption Studio'),
                  subtitle: const Text(
                    '11 styles, karaoke preview, SRT/ASS export, video burn-in',
                  ),
                  trailing: const Icon(Icons.arrow_forward),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CaptionStudioScreen(),
                      ),
                    );
                    _reload();
                  },
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.audio_file),
                  title: const Text('Audio Tools'),
                  subtitle: const Text(
                    'Converter, trimmer, join, video se audio',
                  ),
                  trailing: const Icon(Icons.arrow_forward),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AudioToolsScreen(),
                      ),
                    );
                    _reload();
                  },
                ),
              ),
              const SizedBox(height: 20),
              const _SectionTitle('Breaking News templates'),
              ...data.templates.map(
                (t) => Card(
                  child: ListTile(
                    title: Text(t.displayName),
                    subtitle: Text(
                      t.isCustom ? 'Custom template' : 'Built-in',
                    ),
                    trailing: Text(
                      t.isFree ? 'FREE' : '${t.coinCost} coins',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const _SectionTitle('Publish'),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.search),
                  title: const Text('SEO'),
                  subtitle: const Text(
                    'Title, hashtags, keywords — latest project',
                  ),
                  trailing: const Icon(Icons.arrow_forward),
                  onTap: () async {
                    final project =
                        await NewsProjectStore.loadLatest() ??
                            NewsProject.create(presetId: preset.id);
                    if (!context.mounted) return;
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SeoScreen(project: project),
                      ),
                    );
                    _reload();
                  },
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.file_upload),
                  title: const Text('Export'),
                  subtitle: const Text(
                    'Resolution, format, progress — latest project',
                  ),
                  trailing: const Icon(Icons.arrow_forward),
                  onTap: () async {
                    final project =
                        await NewsProjectStore.loadLatest() ??
                            NewsProject.create(presetId: preset.id);
                    if (!context.mounted) return;
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ExportScreen(
                          project: project,
                          preset: preset,
                        ),
                      ),
                    );
                    _reload();
                  },
                ),
              ),
              const SizedBox(height: 20),
              // Coins (Phase 10): live balance + Watch Ads lives on
              // the Coins screen; admins see the free-everything note
              // there instead of the earn buttons.
              Card(
                child: ListTile(
                  leading: const Icon(Icons.monetization_on),
                  title: const Text('Coins'),
                  subtitle: ValueListenableBuilder<int>(
                    valueListenable: CoinService.instance.balance,
                    builder: (context, balance, _) => Text(
                      'Balance: $balance coins — Watch Ads, daily free, '
                      'history',
                    ),
                  ),
                  trailing: const Icon(Icons.arrow_forward),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CoinsScreen(),
                      ),
                    );
                    _reload();
                  },
                ),
              ),
              const SizedBox(height: 8),
              // Advertise (Phase 10): the DEDICATED Advertise page —
              // banner (BoxFit.contain) + WhatsApp + Watch Ads.
              Card(
                child: ListTile(
                  leading: const Icon(Icons.campaign),
                  title: const Text('Advertise'),
                  subtitle: const Text(
                    'Banner + WhatsApp booking + Watch Ads, Earn Coins',
                  ),
                  trailing: const Icon(Icons.arrow_forward),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AdvertiseScreen(),
                      ),
                    );
                    _reload();
                  },
                ),
              ),
              const SizedBox(height: 20),
              // "For Help" row (Phase 10): WhatsApp support, number
              // from remote config — the shared HelpWhatsAppRow.
              const HelpWhatsAppRow(),
            ],
          );
        },
      ),
    );
  }
}

class _StudioData {
  _StudioData({
    required this.preset,
    required this.presetCount,
    required this.templates,
    required this.fontReady,
    required this.draft,
  });
  final ChannelPreset preset;
  final int presetCount;
  final List<BreakingTemplate> templates;

  /// True once the Kasheeda font loaded in this process (home preview
  /// renders Urdu in Kasheeda when true, fallback font otherwise).
  final bool fontReady;

  /// The autosaved draft offered for recovery (Phase 9), or null
  /// when the latest project has nothing worth recovering.
  final RecoverableDraft? draft;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _RibbonRow extends StatelessWidget {
  const _RibbonRow({
    required this.label,
    required this.kind,
    required this.ribbon,
  });
  final String label;
  final String kind;
  final RibbonConfig ribbon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: Color(ribbon.color),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text('$label — $kind'),
          ),
          Text(ribbon.enabled ? 'ON' : 'OFF'),
        ],
      ),
    );
  }
}
