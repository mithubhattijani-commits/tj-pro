/// Video Editor panel dispatch (Master Plan Phase 4 split).
///
/// This file used to be a `part of` the editor screen holding the
/// `_VideoEditorPanels` extension on the editor State. Phase 4
/// replaced the extension with real widgets under `panels/`; what
/// remains here is the thin dispatch layer: which panel (or panel
/// composition) belongs to the active tool/tab, the tab model, and
/// the legacy-panel switch. All state flows through
/// [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import 'video_editor_controller.dart';
import 'panels/adjust_panel.dart';
import 'panels/ai_cut_panel.dart';
import 'panels/canvas_panel.dart';
import 'panels/cut_panel.dart';
import 'panels/cutout_panel.dart';
import 'panels/ease_panel.dart';
import 'panels/enhance_panel.dart';
import 'panels/keyframes_panel.dart';
import 'panels/legacy_audio_panel.dart';
import 'panels/legacy_beats_panel.dart';
import 'panels/legacy_captions_panel.dart';
import 'panels/legacy_chroma_panel.dart';
import 'panels/legacy_effects_panel.dart';
import 'panels/legacy_filters_panel.dart';
import 'panels/legacy_filters_row_panel.dart';
import 'panels/legacy_grading_one_panel.dart';
import 'panels/legacy_grading_panel.dart';
import 'panels/legacy_overlays_panel.dart';
import 'panels/legacy_speed_panel.dart';
import 'panels/legacy_stabilization_panel.dart';
import 'panels/legacy_stickers_panel.dart';
import 'panels/legacy_text_panel.dart';
import 'panels/legacy_titles_panel.dart';
import 'panels/legacy_tracking_panel.dart';
import 'panels/legacy_transitions_panel.dart';
import 'panels/mask_panel.dart';
import 'panels/music_panel.dart';
import 'panels/opacity_panel.dart';
import 'panels/pip_panel.dart';
import 'panels/precut_panel.dart';
import 'panels/rotate_panel.dart';
import 'panels/speed_panel.dart';
import 'panels/split_panel.dart';
import 'panels/stabilizer_panel.dart';
import 'panels/sticker_panel.dart';
import 'panels/transform_panel.dart';
import 'panels/transitions_panel.dart';
import 'panels/voice_enhance_panel.dart';
import 'panels/volume_panel.dart';
import 'widgets/panel_controls.dart';
import '../news/audio_tools_screen.dart';
import '../news/caption_translator_screen.dart';

  /// A legacy panel's body with its own leading title dropped — the
  /// tab's section titles (and the panel header) name it now.
  List<Widget> panelBody(VideoEditorController host, BuildContext context, String key) {
    final items = List<Widget>.of(legacyPanelChildren(host, context, key));
    if (items.length > 1 && items[0] is Text && items[1] is SizedBox) {
      items.removeRange(0, 2);
    }
    return items;
  }

  /// v1.3.0 (§3/§5A): every tool panel is split into SUB-TABS —
  /// only the active sub-tab's controls are on screen, ever. The
  /// tab list per tool (the panel header renders these as chips).
  List<(String, String)> panelTabs(VideoEditorController host) {
    switch (host.activeTool) {
      case 'canvas':
        return const [
          ('ratio', 'Ratio'),
          ('zoom', 'Zoom'),
          ('background', 'Background'),
        ];
      case 'precut':
        return const [
          ('trim', 'Trim'),
          ('cut', 'Cut'),
          ('split', 'Split'),
        ];
      case 'speed':
        return const [
          ('standard', 'Standard'),
          ('curve', 'Curve'),
          ('beat', 'Beat'),
        ];
      case 'audio':
        return const [
          ('music', 'Music'),
          ('voice', 'Voice'),
          ('clean', 'Clean'),
        ];
      case 'text':
        return const [
          ('text', 'Text'),
          ('titles', 'Titles'),
          ('captions', 'Captions'),
        ];
      case 'colour':
        return const [
          ('filters', 'Filters'),
          ('adjust', 'Adjust'),
        ];
      case 'effects':
        return const [
          ('effects', 'Effects'),
          ('tracking', 'Tracking'),
        ];
      case 'overlay':
        return const [
          ('sticker', 'Sticker'),
          ('keyframes', 'Keyframes'),
          ('pip', 'PIP'),
        ];
      // Build 5 (v1.5.7): no 'news' tool — the Video Editor's
      // news panels are removed (news work lives in News Studio).
      default:
        return const [];
    }
  }

  /// The active sub-tab key (falls back to the tool's first tab).
  String currentTab(VideoEditorController host) {
    final tabs = panelTabs(host);
    if (tabs.isEmpty) return '';
    final t = host.panelTab;
    if (t != null && tabs.any((e) => e.$1 == t)) return t;
    return tabs.first.$1;
  }

  /// Icon for a (tool, sub-tab) pair — the global UI rule (user
  /// order 22 Nov 2026): every sub-option carries its own small
  /// related icon, never bare text alone.
  IconData tabIconFor(String tool, String tab) {
    switch ((tool, tab)) {
      case ('canvas', 'ratio'):
        return Icons.aspect_ratio;
      case ('canvas', 'zoom'):
        return Icons.zoom_in;
      case ('canvas', 'background'):
        return Icons.wallpaper;
      case ('precut', 'trim'):
        return Icons.content_cut;
      case ('precut', 'cut'):
        return Icons.cut;
      case ('precut', 'split'):
        return Icons.call_split;
      case ('speed', 'standard'):
        return Icons.speed;
      case ('speed', 'curve'):
        return Icons.show_chart;
      case ('speed', 'beat'):
        return Icons.music_note;
      case ('audio', 'music'):
        return Icons.music_note;
      case ('audio', 'voice'):
        return Icons.mic;
      case ('audio', 'clean'):
        return Icons.cleaning_services;
      case ('text', 'text'):
        return Icons.text_fields;
      case ('text', 'titles'):
        return Icons.title;
      case ('text', 'captions'):
        return Icons.closed_caption;
      case ('colour', 'filters'):
        return Icons.photo_filter;
      case ('colour', 'adjust'):
        return Icons.tune;
      case ('effects', 'effects'):
        return Icons.auto_awesome;
      case ('effects', 'tracking'):
        return Icons.gps_fixed;
      case ('overlay', 'sticker'):
        return Icons.emoji_emotions;
      case ('overlay', 'keyframes'):
        return Icons.animation;
      case ('overlay', 'pip'):
        return Icons.picture_in_picture_alt;
      case ('overlay', 'background'):
        return Icons.wallpaper;
      default:
        return Icons.circle_outlined;
    }
  }

  /// The sub-tab row under the panel header (§3): ONE horizontal
  /// swipeable line of icon+label items (global UI rule) — the
  /// same visual language as the main tool rail.
class PanelTabRow extends StatelessWidget {
  final VideoEditorController host;
  const PanelTabRow(this.host, {super.key});

  @override
  Widget build(BuildContext context) {
    final tabs = panelTabs(host);
    if (tabs.length < 2) return const SizedBox.shrink();
    final current = currentTab(host);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: iconChoiceRail(host, [
        for (final t in tabs)
          iconChoiceItem(host, 
            icon: tabIconFor(host.activeTool ?? '', t.$1),
            label: t.$2,
            selected: current == t.$1,
            onTap: () => host.update(() => host.panelTab = t.$1),
          ),
      ]),
    );
  }
}


  /// v1.5.0 dispatch: ONE panel per tool key (the flat InShot row
  /// opens these directly). Legacy bodies are reused by slice —
  /// every legacy control stays reachable exactly once.
  List<Widget> toolPanelChildren(VideoEditorController host, BuildContext context) {
    switch (host.activeTool) {
      case 'canvas':
        switch (currentTab(host)) {
          case 'zoom':
            return [TransformPanel(host)];
          case 'background':
            return [PanelColumn(children: CanvasPanel(host).backgroundChildren(context))];
          default:
            return [CanvasPanel(host)];
        }
      case 'precut':
        switch (currentTab(host)) {
          case 'cut':
            return [CutPanel(host)];
          case 'split':
            return [SplitPanel(host)];
          default:
            return [PrecutPanel(host)];
        }
      case 'speed':
        switch (currentTab(host)) {
          case 'curve':
            return [PanelColumn(children: SpeedPanel(host).curveChildren(context))];
          case 'beat':
            return panelBody(host, context, 'beats');
          default:
            return [SpeedPanel(host)];
        }
      case 'audio':
        final body = panelBody(host, context, 'audio');
        final voiceIdx =
            anchorIndex(body, (w) => isTextStarting(w, 'Voice changer'));
        final cleanIdx =
            anchorIndex(body, (w) => isTextStarting(w, 'Cleanup'));
        final v = voiceIdx < 0 ? body.length : voiceIdx;
        var c = cleanIdx < 0 ? body.length : cleanIdx;
        if (c < v) c = v;
        switch (currentTab(host)) {
          case 'voice':
            return body.sublist(v, c);
          case 'clean':
            return body.sublist(c);
          default:
            return [
              ...body.sublist(0, v),
              ...MusicPanel(host).buildChildren(context),
              const Divider(height: 32),
              ListTile(
                leading: const Icon(Icons.build_circle_outlined),
                title: const Text('More audio tools'),
                subtitle: const Text('Converter, trimmer, joiner, extract'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AudioToolsScreen(),
                    ),
                  );
                },
              ),
            ];
        }
      case 'text':
        switch (currentTab(host)) {
          case 'titles':
            return panelBody(host, context, 'titles');
          case 'captions':
            return [
              ...panelBody(host, context, 'captions'),
              SectionTitle('Urdu (AI) captions'),
              const Text(
                'Shruti Urdu AI model (on-device) se Urdu captions — '
                'Whisper wale option se alag, Urdu ke liye trained. '
                'Model pack pehli dafa download hota hai.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (host.transcribing || host.busy)
                      ? null
                      : host.generateUrduCaptions,
                  icon: const Icon(Icons.closed_caption, size: 18),
                  label: Text(
                    host.transcribing
                        ? 'Captions ban rahe hain…'
                        : 'Urdu (AI) captions banayein',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.translate),
                title: const Text('Translate captions'),
                subtitle: const Text('Caption Translator (ML Kit)'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CaptionTranslatorScreen(
                        initialSegments: host.captions,
                        fromLang: host.captionLocale,
                        toLang: host.captionLocale == 'ur' ? 'en' : 'ur',
                      ),
                    ),
                  );
                },
              ),
            ];
          default:
            return panelBody(host, context, 'text');
        }
      case 'colour':
        return currentTab(host) == 'adjust'
            ? [AdjustPanel(host)]
            : legacyPanelChildren(host, context, 'filtersRow');
      case 'volume':
      case 'clipVolume':
        return [VolumePanel(host)];
      case 'effects':
        return currentTab(host) == 'tracking'
            ? panelBody(host, context, 'tracking')
            : panelBody(host, context, 'effects');
      case 'overlay':
        switch (currentTab(host)) {
          case 'keyframes':
            return [KeyframesPanel(host)];
          case 'pip':
            return [
              ...panelBody(host, context, 'overlays'),
              ...PipPanel(host).extrasChildren(context),
            ];
          default:
            return [StickerPanel(host)];
        }
      case 'aicut':
        return [AiCutPanel(host)];
      case 'voiceenhance':
        return [VoiceEnhancePanel(host)];
      case 'edit':
        return [TransformPanel(host)];
      case 'enhance':
        return [EnhancePanel(host)];
      case 'stabilizer':
        return [StabilizerPanel(host)];
      case 'cutout':
        return [CutoutPanel(host)];
      case 'mask':
        return [MaskPanel(host)];
      case 'opacity':
        return [OpacityPanel(host)];
      case 'rotate':
        return [RotatePanel(host)];
      case 'ease':
        return [EasePanel(host)];
      case 'transitions':
        return [TransitionsPanel(host)];
      default:
        return legacyPanelChildren(host, context, 'text');
    }
  }

/// The legacy per-tool panels (Phase 4: one class per case under
/// `panels/legacy_*_panel.dart`). Unknown keys — and 'text' —
/// land on the text panel, exactly like the old switch's default.
List<Widget> legacyPanelChildren(VideoEditorController host, BuildContext context, String toolKey) {
  switch (toolKey) {
    case 'stickers':
      return LegacyStickersPanel(host).buildChildren(context);
    case 'effects':
      return LegacyEffectsPanel(host).buildChildren(context);
    case 'titles':
      return LegacyTitlesPanel(host).buildChildren(context);
    case 'filters':
      return LegacyFiltersPanel(host).buildChildren(context);
    case 'audio':
      return LegacyAudioPanel(host).buildChildren(context);
    case 'speed':
      return LegacySpeedPanel(host).buildChildren(context);
    case 'transitions':
      return LegacyTransitionsPanel(host).buildChildren(context);
    case 'overlays':
      return LegacyOverlaysPanel(host).buildChildren(context);
    // Build 5 (v1.5.7): the 'news' / 'newsTemplate' / 'newsText' /
    // 'newsLogo' / 'live' legacy panels are DELETED with the News
    // tool (user ruling: news work only in News Studio). Unknown
    // keys land on the text panel, like the old default.
    case 'captions':
      return LegacyCaptionsPanel(host).buildChildren(context);
    case 'stabilization':
      return LegacyStabilizationPanel(host).buildChildren(context);
    case 'chroma':
      return LegacyChromaPanel(host).buildChildren(context);
    case 'tracking':
      return LegacyTrackingPanel(host).buildChildren(context);
    case 'beats':
      return LegacyBeatsPanel(host).buildChildren(context);
    case 'grading':
      return LegacyGradingPanel(host).buildChildren(context);
    case 'filtersRow':
      return LegacyFiltersRowPanel(host).buildChildren(context);
    case 'gradingOne':
      return LegacyGradingOnePanel(host).buildChildren(context);
    case 'text':
    default:
      return LegacyTextPanel(host).buildChildren(context);
  }
}
