/// Tool rows of the Video Editor (Master Plan Phase 4 split).
///
/// Were `_mainToolRow` / `_clipToolRow` / `_elementToolRow` /
/// `_toolPanelHeader` + helpers inside the editor State; now real
/// widgets in their own file. All editor state is reached through
/// [VideoEditorController] — behaviour unchanged.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../motion/motion_gallery_screen.dart';
import '../../news/store_screen.dart';
import '../../widgets/tool_guide.dart';
import '../video_editor_controller.dart';

/// The three tool rails + the open panel's header, sharing the
/// row/item builders below.
class ToolRows {
  final VideoEditorController host;
  const ToolRows(this.host);

  /// Point #21: rail item id → guide id. Har rail tool ki
  /// guide item ko der tak dabane (long-press) se khulti hai —
  /// panel wale tools ki guide un ke panel header mein bhi
  /// hai; instant ops (Split, Delete, …) ke liye yahi un ki
  /// Guide ka rasta hai.
  static const Map<String, String> _railGuideIds = {
    'canvas': 've.canvas',
    'audio': 've.audio',
    'sticker': 've.overlay',
    'text': 've.text',
    'effect': 've.effects',
    'filter': 've.colour',
    'pip': 've.overlay',
    'precut': 've.precut',
    'split': 've.split',
    'delete': 've.delete',
    'volume': 've.volume',
    'background': 've.canvas',
    'speed': 've.speed',
    'animation': 've.overlay',
    'aicut': 've.aicut',
    'voiceenhance': 've.voiceenhance',
    'crop': 've.edit',
    'switch': 've.switch',
    'enhance': 've.enhance',
    'stabilizer': 've.stabilizer',
    'cutout': 've.cutout',
    'mask': 've.mask',
    'templates': 've.templates',
    'opacity': 've.opacity',
    'replace': 've.replace',
    'voiceeffect': 've.audio',
    'duplicate': 've.duplicate',
    'rotate': 've.rotate',
    'freeze': 've.freeze',
    'capture': 've.capture',
    'reverse': 've.reverse',
    'ease': 've.ease',
    'motion': 'motion',
  };

  /// Wraps a rail item so a long-press opens its guide. The
  /// item's own tap behaviour is untouched.
  Widget _withGuide(String railId, Widget item) {
    final guideId = _railGuideIds[railId];
    if (guideId == null || toolGuideFor(guideId) == null) return item;
    return GestureDetector(
      onLongPress: () => showToolGuide(host.context, guideId),
      child: item,
    );
  }

  List<(String, Widget)> _toolItems() {
    final busy = host.busy;
    final hasClip = host.clips.isNotEmpty;
    // P2: an unavailable clip op stays TAPPABLE but only
    // explains itself (busy / no clip) in the status line —
    // a silently dead dimmed button was the S-VE-7 complaint.
    VoidCallback clipOp(Future<void> Function() f) =>
        (busy || !hasClip) ? host.explainToolTap : () => unawaited(f());
    return [
      (
        'canvas',
        _toolRowItem(
          icon: Icons.aspect_ratio,
          label: 'Canvas',
          onTap: () => host.openTool('canvas'),
        ),
      ),
      (
        'audio',
        _toolRowItem(
          icon: Icons.music_note,
          label: 'Audio',
          onTap: () => host.openTool('audio'),
        ),
      ),
      (
        'sticker',
        _toolRowItem(
          icon: Icons.emoji_emotions,
          label: 'Sticker',
          onTap: () => host.openToolTab('overlay', 'sticker'),
        ),
      ),
      (
        'text',
        _toolRowItem(
          icon: Icons.text_fields,
          label: 'Text',
          onTap: () => host.openTool('text'),
        ),
      ),
      (
        'effect',
        _toolRowItem(
          icon: Icons.auto_awesome,
          label: 'Effect',
          onTap: () => host.openTool('effects'),
        ),
      ),
      (
        'filter',
        _toolRowItem(
          icon: Icons.photo_filter,
          label: 'Filter',
          onTap: () => host.openToolTab('colour', 'filters'),
        ),
      ),
      (
        'pip',
        _toolRowItem(
          icon: Icons.picture_in_picture_alt,
          label: 'PIP',
          onTap: () => host.openToolTab('overlay', 'pip'),
        ),
      ),
      (
        'precut',
        _toolRowItem(
          icon: Icons.content_cut,
          label: 'Precut',
          onTap: () => host.openTool('precut'),
        ),
      ),
      (
        'split',
        _toolRowItem(
          icon: Icons.call_split,
          label: 'Split',
          onTap: (busy || !hasClip)
              ? host.explainToolTap
              : host.splitSelectedClip,
          dimmed: busy || !hasClip,
        ),
      ),
      (
        'delete',
        _toolRowItem(
          icon: Icons.delete_outline,
          label: 'Delete',
          danger: true,
          onTap: clipOp(host.deleteSelectedClip),
          dimmed: busy || !hasClip,
        ),
      ),
      (
        'volume',
        _toolRowItem(
          icon: Icons.volume_up,
          label: 'Volume',
          onTap: () => host.openTool('volume'),
        ),
      ),
      (
        'background',
        _toolRowItem(
          icon: Icons.wallpaper,
          label: 'Background',
          onTap: () => host.openToolTab('canvas', 'background'),
        ),
      ),
      (
        'speed',
        _toolRowItem(
          icon: Icons.speed,
          label: 'Speed',
          onTap: () => host.openTool('speed'),
        ),
      ),
      (
        'animation',
        _toolRowItem(
          icon: Icons.animation,
          label: 'Animation',
          onTap: () => host.openToolTab('overlay', 'keyframes'),
        ),
      ),
      (
        'aicut',
        _toolRowItem(
          icon: Icons.content_cut_outlined,
          label: 'AI Cut',
          onTap: () => host.openTool('aicut'),
        ),
      ),
      (
        'voiceenhance',
        _toolRowItem(
          icon: Icons.record_voice_over,
          label: 'Voice Enhance',
          onTap: () => host.openTool('voiceenhance'),
        ),
      ),
      (
        'crop',
        _toolRowItem(
          icon: Icons.crop,
          label: 'Crop',
          onTap: () => host.openToolTab('edit', 'transform'),
        ),
      ),
      (
        'switch',
        _toolRowItem(
          icon: Icons.swap_vert,
          label: 'Switch',
          onTap: clipOp(host.switchSelectedClipToPip),
          dimmed: busy || !hasClip,
        ),
      ),
      (
        'enhance',
        _toolRowItem(
          icon: Icons.high_quality,
          label: 'Enhance',
          onTap: () => host.openTool('enhance'),
        ),
      ),
      (
        'stabilizer',
        _toolRowItem(
          icon: Icons.videocam,
          label: 'Stabilizer',
          onTap: () => host.openTool('stabilizer'),
        ),
      ),
      (
        'cutout',
        _toolRowItem(
          icon: Icons.person_remove,
          label: 'Cutout',
          onTap: () => host.openTool('cutout'),
        ),
      ),
      (
        'mask',
        _toolRowItem(
          icon: Icons.blur_on,
          label: 'Mask',
          onTap: () => host.openTool('mask'),
        ),
      ),
      (
        'templates',
        _toolRowItem(
          icon: Icons.dashboard_customize,
          label: 'Templates',
          // #31: the editor's Templates slot opens OUR Online
          // Store on its Templates section.
          onTap: () {
            Navigator.push(
              host.context,
              MaterialPageRoute(
                builder: (_) => const StoreScreen(initialCategory: 'Templates'),
              ),
            );
          },
        ),
      ),
      (
        'opacity',
        _toolRowItem(
          icon: Icons.opacity,
          label: 'Opacity',
          onTap: () => host.openTool('opacity'),
        ),
      ),
      (
        'replace',
        _toolRowItem(
          icon: Icons.find_replace,
          label: 'Replace',
          onTap: clipOp(host.replaceSelectedClip),
          dimmed: busy || !hasClip,
        ),
      ),
      (
        'voiceeffect',
        _toolRowItem(
          icon: Icons.voice_chat,
          label: 'Voice Effect',
          onTap: () => host.openToolTab('audio', 'voice'),
        ),
      ),
      (
        'duplicate',
        _toolRowItem(
          icon: Icons.copy,
          label: 'Duplicate',
          onTap: (busy || !hasClip)
              ? host.explainToolTap
              : host.duplicateSelectedClip,
          dimmed: busy || !hasClip,
        ),
      ),
      (
        'rotate',
        _toolRowItem(
          icon: Icons.rotate_right,
          label: 'Rotate',
          onTap: () => host.openTool('rotate'),
        ),
      ),
      (
        'freeze',
        _toolRowItem(
          icon: Icons.ac_unit,
          label: 'Freeze',
          onTap: clipOp(host.freezeFrameInsert),
          dimmed: busy || !hasClip,
        ),
      ),
      (
        'capture',
        _toolRowItem(
          icon: Icons.camera_alt_outlined,
          label: 'Capture',
          onTap: clipOp(host.captureFrameInsert),
          dimmed: busy || !hasClip,
        ),
      ),
      (
        'reverse',
        _toolRowItem(
          icon: Icons.history,
          label: 'Reverse',
          onTap: clipOp(host.reverseSelectedClip),
          dimmed: busy || !hasClip,
        ),
      ),
      (
        'ease',
        _toolRowItem(
          icon: Icons.show_chart,
          label: 'Ease',
          onTap: () => host.openTool('ease'),
        ),
      ),
      (
        'motion',
        _toolRowItem(
          icon: Icons.movie_creation_outlined,
          label: 'Motion',
          // Build M1 (v1.11.0): the Motion Graphics Studio's
          // second entry point — appended AFTER the InShot set
          // so its 32 keep their exact order. Opens the Gallery
          // (the Studio's home); placement INTO this editor's
          // timeline is M3, per the Motion plan.
          onTap: () {
            Navigator.push(
              host.context,
              MaterialPageRoute(
                builder: (_) => const MotionGalleryScreen(),
              ),
            );
          },
        ),
      ),
      // Build 5 (v1.5.7, user ruling): NO News tool here — news
      // ka kaam SIRF News Studio mein hota hai. The Video Editor's
      // news template/text/logo panels are removed; their whole
      // capability lives in the News Maker workspace.
    ];
  }

  /// The InShot tool set (INSHOT-REFERENCE §B, exact order) as
  /// (id, item) pairs — ONE list behind both the main row and the
  /// clip row (the clip row filters it), so a tool can never exist
  /// twice with two behaviours. Instant ops run immediately; the
  /// rest open their panel. InShot's 32 keep their exact order.
  /// One item of an InShot tool row: icon above a small label,
  /// 64 wide, in a horizontal swipeable line (mockups V1/V2).
  Widget _toolRowItem({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool danger = false,
    // P2: visually dimmed while UNAVAILABLE, even when the item
    // keeps an explain-on-tap handler (see clipOp above).
    bool dimmed = false,
  }) {
    final color = danger ? const Color(0xFFFF6B5E) : Colors.white;
    return SizedBox(
      width: 64,
      child: InkWell(
        onTap: onTap,
        child: Opacity(
          opacity: (onTap == null || dimmed) ? 0.4 : 1,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 23),
              const SizedBox(height: 3),
              SizedBox(
                height: 14,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: TextStyle(color: color, fontSize: 10.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The shell every tool row renders in: dark bar, ONE horizontal
  /// swipeable line.
  Widget _toolRowShell(String key, List<Widget> items) {
    return Container(
      key: ValueKey<String>(key),
      color: const Color(0xFF1B1B1B),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        children: items,
      ),
    );
  }



  /// MAIN tool row (mockup V1): the full InShot order.
  Widget mainToolRow() {
    return _toolRowShell(
      'video-rail',
      _toolItems().map((e) => _withGuide(e.$1, e.$2)).toList(),
    );
  }

  /// CLIP row (mockup V2): the main row minus Canvas / Audio /
  /// Sticker / Text (InShot's rule), led by a ✓ that exits clip
  /// mode. Every item is the SAME item as in the main row — the
  /// v1.4.0 clip row's duplicate mappings (Retouch→Adjust, a second
  /// Opacity→Transform, Reverse→Speed, Mask→PIP) are gone.
  Widget clipToolRow() {
    const excluded = {'canvas', 'audio', 'sticker', 'text'};
    return _toolRowShell('video-clip-row', [
      _toolRowItem(
        icon: Icons.check_circle,
        label: 'Done',
        onTap: () => host.update(() => host.clipRow = false),
      ),
      for (final e in _toolItems())
        if (!excluded.contains(e.$1)) _withGuide(e.$1, e.$2),
    ]);
  }

  /// ELEMENT row (PIP selected): scoped to the ops that are real
  /// for our single-inset PIP model — source / edit / delete /
  /// Switch back to the main track / Mask / Blend / Opacity / Ease.
  /// (InShot's fuller element row also trims/speeds the element;
  /// our PIP has no trim/speed model — PARTIAL, see the report.)
  Widget elementToolRow() {
    return _toolRowShell('video-element-row', [
      _toolRowItem(
        icon: Icons.check_circle,
        label: 'Done',
        onTap: () => host.update(() => host.elementRow = false),
      ),
      _toolRowItem(
        icon: Icons.picture_in_picture_alt,
        label: 'PIP',
        onTap: () => host.openToolTab('overlay', 'pip'),
      ),
      _toolRowItem(
        icon: Icons.edit,
        label: 'Edit',
        onTap: () => host.openToolTab('overlay', 'pip'),
      ),
      _toolRowItem(
        icon: Icons.delete_outline,
        label: 'Delete',
        danger: true,
        onTap: host.busy
            ? null
            : () => host.update(() {
                host.fxPip = false;
                host.fxPipVideo = '';
                host.elementRow = false;
              }),
      ),
      _toolRowItem(
        icon: Icons.swap_vert,
        label: 'Switch',
        onTap: host.busy ? null : () => unawaited(host.switchPipToMainTrack()),
      ),
      _toolRowItem(
        icon: Icons.blur_on,
        label: 'Mask',
        onTap: () => host.openTool('mask'),
      ),
      _toolRowItem(
        icon: Icons.layers,
        label: 'Blend',
        onTap: () => host.openToolTab('overlay', 'pip'),
      ),
      _toolRowItem(
        icon: Icons.opacity,
        label: 'Opacity',
        onTap: () => host.openTool('opacity'),
      ),
      _toolRowItem(
        icon: Icons.show_chart,
        label: 'Ease',
        onTap: () => host.openTool('ease'),
      ),
    ]);
  }

  /// Header for the open tool panel: ✗ Cancel + tool name + ✓
  /// Apply — ONE pattern for every panel (Build 3 audit, PRO-SPEC
  /// points 4 + 19). Panel edits apply LIVE to the preview while
  /// the panel is open; ✓ keeps them and closes, ✗ rolls back
  /// everything the panel's controls changed since it opened (the
  /// [_panelBase] snapshot) and closes. v1.5.0 (#11): the confirm
  /// is a ✓ ICON everywhere.
  Widget toolPanelHeader(String toolKey) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Cancel — panel ki changes wapas',
            onPressed: host.cancelPanel,
            icon: const Icon(Icons.close, color: Colors.white),
          ),
          Expanded(
            child: Text(
              host.toolDisplayName(toolKey),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Point #21: har tool ki Guide, isi header mein.
          ToolGuideButton(guideId: vePanelGuideId(toolKey), compact: true),
          IconButton(
            tooltip: 'Apply',
            onPressed: () => host.openTool(null),
            icon: const Icon(Icons.check, color: TjProTheme.gold),
          ),
        ],
      ),
    );
  }
}

/// The main (no clip selected) tool rail.
class MainToolRow extends StatelessWidget {
  final VideoEditorController host;
  const MainToolRow(this.host, {super.key});

  @override
  Widget build(BuildContext context) => ToolRows(host).mainToolRow();
}

/// The clip-selected tool rail.
class ClipToolRow extends StatelessWidget {
  final VideoEditorController host;
  const ClipToolRow(this.host, {super.key});

  @override
  Widget build(BuildContext context) => ToolRows(host).clipToolRow();
}

/// The element-selected (text/PIP) tool rail.
class ElementToolRow extends StatelessWidget {
  final VideoEditorController host;
  const ElementToolRow(this.host, {super.key});

  @override
  Widget build(BuildContext context) => ToolRows(host).elementToolRow();
}

/// The open tool panel's header (title + tab close affordance).
class ToolPanelHeader extends StatelessWidget {
  final VideoEditorController host;
  final String tool;
  const ToolPanelHeader(this.host, this.tool, {super.key});

  @override
  Widget build(BuildContext context) => ToolRows(host).toolPanelHeader(tool);
}
