/// News Studio home (Phase 2; v1.5.0 rebuild per mockup N1).
///
/// Layout (v1.5.0; v1.5.1 NS1, fixes #44/#45): the REAL template
/// preview as the hero, the three #32 controls directly under it
/// (Add Video / Templates / Ribbons — always visible), the
/// Channel preset card with the RESOLVED design colours (#15),
/// ONE tool line (every studio destination in a single horizontal
/// icon+label row — News Maker, Live Studio, AI News, Templates,
/// Studio, Branding, Voice, Captions, Audio), Recent projects,
/// Help, and ONE "More" group (Publish/SEO, Export, Coins,
/// Advertise, Online Store — one entry point each). The v1.5.1
/// step removed the News Maker summary card and the Breaking
/// templates list from the home (both live on inside News Maker);
/// nothing was removed from the app.
///
/// The bottom padding is deliberate (#20): this screen is also a
/// bottom-nav tab body, and the list must never slide under the
/// navigation bar.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/asset_download_service.dart';
import '../services/coin_service.dart';
import '../live/live_studio_screen.dart';
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
import 'store_screen.dart';
import 'template_studio_screen.dart';
import 'tts_studio_screen.dart';
import 'widgets/breaking_preview.dart';
import 'widgets/clip_picker.dart';
import 'widgets/draft_recovery_card.dart';
import 'widgets/nigraan_final_preview.dart';
import 'widgets/studio_pickers.dart';
import 'widgets/template_media_preview.dart';

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
    final latestProject = await NewsProjectStore.loadLatest();
    final allProjects = await NewsProjectStore.loadAll();
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
    final recent = List<NewsProject>.from(allProjects)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return _StudioData(
      preset: preset,
      presetCount: presets.length,
      fontReady: fontReady,
      draft: findRecoverableDraft(latestProject),
      latestProject: latestProject,
      recentProjects: recent.take(5).toList(),
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

  Future<void> _open(BuildContext context, Widget screen) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
    _reload();
  }

  /// v1.5.0 (#32) — Add Video sheet on the latest project (a fresh
  /// one is created + saved when none exists yet). The SAME
  /// ClipPickerList as in News Maker — one control, shared state.
  void _showClipsSheet(BuildContext context, _StudioData data) {
    final project = data.latestProject ??
        NewsProject.create(presetId: data.preset.id);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, sheetSetState) => SafeArea(
          child: SizedBox(
            height: 440,
            child: Column(
              children: [
                const ListTile(
                  title: Text(
                    'Apni video / photo — template ke main area ke liye',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Pehli clip preview mein dikhti hai; export mein '
                    'saari clips order se lagti hain.',
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: ClipPickerList(
                      paths: project.clipPaths,
                      onChanged: (next) {
                        project.clipPaths = next;
                        sheetSetState(() {});
                        _saveProject(project);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(_reload);
  }

  /// Fire-and-forget project save for sheet edits (the store is
  /// fail-soft by design; the home reloads when the sheet closes).
  void _saveProject(NewsProject project) {
    unawaited(NewsProjectStore.save(project));
  }

  /// v1.5.0 (#32) — Templates sheet: design picks set the preset's
  /// template kind + Final variant and persist; Store / Library
  /// picks navigate (shared picker implementation).
  Future<void> _showTemplatesSheet(
    BuildContext context,
    ChannelPreset preset,
  ) async {
    final pick = await showTemplatesPicker(
      context,
      currentKind: preset.templateKind,
      currentIsFinal3: preset.finalIs3Ribbon,
    );
    if (pick == null || !context.mounted) return;
    if (await openTemplatePickDestination(context, pick)) {
      _reload();
      return;
    }
    switch (pick) {
      case TemplatePick.final3:
        preset.templateKind = 'nigraanFinal';
        preset.finalVariant = kFinalVariant3;
      case TemplatePick.classic2:
        preset.templateKind = 'nigraanFinal';
        preset.finalVariant = kFinalVariantClassic2;
      case TemplatePick.breaking:
        preset.templateKind = 'breaking';
      case TemplatePick.classic:
        preset.templateKind = 'classic';
      case TemplatePick.store:
      case TemplatePick.library:
        return; // handled above
    }
    await persistPresetChange(preset);
    _reload();
  }

  /// v1.5.0 (#32) — Ribbons sheet (shared picker): design picks
  /// mutate + persist the preset; Studio / Store navigate.
  Future<void> _showRibbonsSheet(
    BuildContext context,
    ChannelPreset preset,
  ) async {
    final pick = await showRibbonsPicker(
      context,
      currentIsFinal3: preset.finalIs3Ribbon,
    );
    if (pick == null || !context.mounted) return;
    await handleRibbonPick(
      context,
      pick,
      preset: preset,
      persistPreset: () => persistPresetChange(preset),
    );
    _reload();
  }

  static String _templateLabel(ChannelPreset preset) {
    if (preset.templateKind == 'breaking') {
      return 'Breaking • '
          '${BreakingVariant.fromId(preset.breakingVariant).label}';
    }
    if (preset.templateKind == 'classic') return 'Classic';
    return preset.finalIs3Ribbon ? 'Final 3-Ribbon' : 'Classic 2-Ribbon';
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
          final latest = data.latestProject;
          return ListView(
            key: const Key('newsStudioList'),
            // #20: generous bottom padding — content never slides
            // under the bottom navigation bar.
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
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
              // HERO — the real template preview; with the user's
              // own media composited into the main area when the
              // latest project has clips (#32).
              Center(
                child: preset.templateKind == kTemplateFinal
                    ? (latest != null && latest.clipPaths.isNotEmpty)
                        ? TemplateMediaPreview(
                            key: const Key('studioMediaPreview'),
                            preset: preset,
                            mediaPaths: latest.clipPaths,
                            fontReady: data.fontReady,
                            height: 280,
                            elementOverrides: latest.elementOverrides,
                            tickerLabel: latest.tickerLabel.isEmpty
                                ? null
                                : latest.tickerLabel,
                            reporterPhotoPath: latest.reporterPhotoPath,
                            reporterName: latest.reporterName,
                            logoRotate: preset.logoRotate,
                          )
                        : NigraanFinalPreview(
                            preset: preset,
                            fontReady: data.fontReady,
                            height: 280,
                            elementOverrides:
                                latest?.elementOverrides ?? const {},
                            tickerLabel: (latest?.tickerLabel ?? '')
                                    .isEmpty
                                ? null
                                : latest!.tickerLabel,
                            reporterPhotoPath: latest?.reporterPhotoPath,
                            reporterName: latest?.reporterName,
                            logoRotate: preset.logoRotate,
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
              const SizedBox(height: 12),
              // #32 — the three controls, always visible under the
              // preview: Add Video / Templates / Ribbons.
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('studioAddVideoButton'),
                      onPressed: () => _showClipsSheet(context, data),
                      icon: const Icon(Icons.add),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Add Video'),
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('studioTemplatesButton'),
                      onPressed: () => _showTemplatesSheet(context, preset),
                      icon: const Icon(Icons.dashboard_customize_outlined),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Templates'),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('studioRibbonsButton'),
                      onPressed: () => _showRibbonsSheet(context, preset),
                      icon: const Icon(Icons.view_agenda_outlined),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Ribbons'),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _SectionTitle('Channel preset — ${preset.name}'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Template: ${_templateLabel(preset)}'),
                      const SizedBox(height: 4),
                      Text(
                        preset.logoPath == null
                            ? 'Logo: default (3D rotate on)'
                            : 'Logo: custom (3D rotate on)',
                      ),
                      const SizedBox(height: 12),
                      // #15: the swatches show the RESOLVED design
                      // colours (preset.design*Color) — the colours
                      // the template actually renders — not the raw
                      // factory values stored on the preset.
                      _RibbonRow(
                        label: 'Top',
                        kind: 'Current story',
                        color: preset.designTopColor,
                        enabled: preset.topRibbon.enabled,
                      ),
                      _RibbonRow(
                        label: 'Middle',
                        kind: 'National news (Urdu)',
                        color: preset.designUrduColor,
                        enabled: preset.urduRibbon.enabled,
                      ),
                      _RibbonRow(
                        label: 'Bottom',
                        kind: 'International (English)',
                        color: preset.designEnglishColor,
                        enabled: preset.englishRibbon.enabled,
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
              // ONE tool line (#25 pattern): every studio
              // destination, one horizontal icon+label row.
              const _SectionTitle('Tools'),
              SizedBox(
                height: 84,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _ToolLineItem(
                      icon: Icons.edit_note,
                      label: 'News Maker',
                      onTap: () =>
                          _open(context, const NewsMakerScreen()),
                    ),
                    _ToolLineItem(
                      icon: Icons.sensors,
                      label: 'Live Studio',
                      onTap: () =>
                          _open(context, const LiveStudioScreen()),
                    ),
                    _ToolLineItem(
                      icon: Icons.auto_awesome,
                      label: 'AI News',
                      onTap: () =>
                          _open(context, const AiNewsMakerScreen()),
                    ),
                    _ToolLineItem(
                      icon: Icons.dashboard_customize_outlined,
                      label: 'Templates',
                      onTap: () => _showTemplatesSheet(context, preset),
                    ),
                    _ToolLineItem(
                      icon: Icons.tune,
                      label: 'Studio',
                      onTap: () =>
                          _open(context, const TemplateStudioScreen()),
                    ),
                    _ToolLineItem(
                      icon: Icons.branding_watermark,
                      label: 'Branding',
                      onTap: () => _open(
                        context,
                        ChannelBrandingScreen(initialPreset: preset),
                      ),
                    ),
                    _ToolLineItem(
                      icon: Icons.record_voice_over,
                      label: 'Voice',
                      onTap: () =>
                          _open(context, const TtsStudioScreen()),
                    ),
                    _ToolLineItem(
                      icon: Icons.subtitles,
                      label: 'Captions',
                      onTap: () =>
                          _open(context, const CaptionStudioScreen()),
                    ),
                    _ToolLineItem(
                      icon: Icons.audio_file,
                      label: 'Audio',
                      onTap: () =>
                          _open(context, const AudioToolsScreen()),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // v1.5.1 (NS1, fixes #44/#45): ONE "More" group —
              // the News Maker summary card, the Breaking
              // templates list and the separate Publish / Coins /
              // Advertise / Store cards are GONE from the home.
              // News Maker lives in the tool line; Breaking
              // templates live in the Maker's Template tool; the
              // five secondary destinations below keep exactly
              // one entry point each, grouped here.
              const _SectionTitle('More'),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.search),
                      title: const Text('Publish — SEO'),
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
                    const Divider(height: 1),
                    ListTile(
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
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.monetization_on),
                      title: const Text('Coins'),
                      subtitle: ValueListenableBuilder<int>(
                        valueListenable: CoinService.instance.balance,
                        builder: (context, balance, _) => Text(
                          'Balance: $balance coins — Watch Ads, daily '
                          'free, history',
                        ),
                      ),
                      trailing: const Icon(Icons.arrow_forward),
                      onTap: () => _open(context, const CoinsScreen()),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.campaign),
                      title: const Text('Advertise'),
                      subtitle: const Text(
                        'Banner + WhatsApp booking + Watch Ads, '
                        'Earn Coins',
                      ),
                      trailing: const Icon(Icons.arrow_forward),
                      onTap: () =>
                          _open(context, const AdvertiseScreen()),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.storefront),
                      title: const Text('Online Store'),
                      subtitle: const Text(
                        'Templates, music, ribbons & more — new '
                        'stock weekly',
                      ),
                      trailing: const Icon(Icons.arrow_forward),
                      onTap: () => _open(context, const StoreScreen()),
                    ),
                  ],
                ),
              ),
              if (data.recentProjects.isNotEmpty) ...[
                const SizedBox(height: 20),
                const _SectionTitle('Recent projects'),
                ...data.recentProjects.map(
                  (project) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.folder_open_outlined),
                      title: Text(
                        project.title.trim().isNotEmpty
                            ? project.title
                            : (project.headline.trim().isNotEmpty
                                ? project.headline
                                : 'Untitled project'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${project.clipPaths.length} clip(s) • '
                        '${project.updatedAt.day}/${project.updatedAt.month} '
                        '${project.updatedAt.hour.toString().padLeft(2, '0')}:'
                        '${project.updatedAt.minute.toString().padLeft(2, '0')}',
                      ),
                      trailing: const Icon(Icons.arrow_forward),
                      onTap: () => _open(
                        context,
                        NewsMakerScreen(
                          initialPreset: preset,
                          initialProject: project,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
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
    required this.fontReady,
    required this.draft,
    required this.latestProject,
    required this.recentProjects,
  });
  final ChannelPreset preset;
  final int presetCount;

  /// True once the Kasheeda font loaded in this process (home preview
  /// renders Urdu in Kasheeda when true, fallback font otherwise).
  final bool fontReady;

  /// The autosaved draft offered for recovery (Phase 9), or null
  /// when the latest project has nothing worth recovering.
  final RecoverableDraft? draft;

  /// The most recently updated project (hero media + News Maker
  /// summary), or null when no project exists yet.
  final NewsProject? latestProject;

  /// Up to 5 most recent projects for the Recent list.
  final List<NewsProject> recentProjects;
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

/// One item of the News Studio tool line: icon over label, fixed
/// width, the label scales down instead of truncating.
class _ToolLineItem extends StatelessWidget {
  const _ToolLineItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.blueGrey.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 24),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label, style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}

class _RibbonRow extends StatelessWidget {
  const _RibbonRow({
    required this.label,
    required this.kind,
    required this.color,
    required this.enabled,
  });
  final String label;
  final String kind;

  /// The RESOLVED design colour (what the template renders).
  final int color;
  final bool enabled;

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
              color: Color(color),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text('$label — $kind'),
          ),
          Text(enabled ? 'ON' : 'OFF'),
        ],
      ),
    );
  }
}
