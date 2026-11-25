/// Timeline bar of the Video Editor (Master Plan Phase 4 split).
///
/// Was `_timelineBar` + helpers inside the panels extension on the
/// editor State; now a real widget in its own file. All editor state
/// is reached through [VideoEditorController] — behaviour unchanged.
library;

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../../theme.dart';
import '../editor_stage.dart';
import '../video_editor_controller.dart';

/// The editor's timeline: contextual hint, ruler + clip lanes with
/// the centred playhead, and the transport-adjacent zoom controls.
class TimelineBar extends StatelessWidget {
  final VideoEditorController host;
  const TimelineBar(this.host, {super.key});

  /// v1.5.0 TIMELINE (mockups V1/V2, replacing _timelineSection +
  /// _timelineCard): contextual yellow hint → the centred-playhead
  /// strip (fixed red + column at left with Mute under it, ruler
  /// labels every 2s, REAL filmstrip thumbnails, gold selection,
  /// trim handles on the selected block, transition badges on the
  /// boundaries, long-press swap) → PIP lane → audio lane → text
  /// lane → times row (current centred / total right — BOTH from
  /// the one TimelineClock model, #5/#30).
  @override
  Widget build(BuildContext context) {
    final total = host.totalDurationSec;
    // Phase 2: kick off the music waveform render (cached; the
    // audio lane paints it as its background when it lands).
    final mp = host.musicPath;
    if (mp != null && !host.musicWaveCache.containsKey(mp)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (host.mounted) unawaited(host.ensureMusicWave(mp));
      });
    }
    final wavePath = mp == null ? null : host.musicWaveCache[mp];
    return Container(
      color: const Color(0xFF161616),
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  host.elementRow && host.fxPip
                      ? 'PIP element selected — Switch se main track par wapas.'
                      : host.clipRow && host.clips.isNotEmpty
                          ? 'Long press to swap'
                          : 'Select one track to edit.',
                  style: const TextStyle(
                    color: Color(0xFFFFD60A),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Main-track lock (Phase 2): while locked, the
              // timeline's trim handles and reorder are disabled
              // (selection, playback and the panels still work).
              InkWell(
                onTap: () =>
                    host.update(() => host.mainTrackLocked = !host.mainTrackLocked),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        host.mainTrackLocked ? Icons.lock : Icons.lock_open,
                        size: 14,
                        color: host.mainTrackLocked
                            ? TjProTheme.gold
                            : Colors.white54,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'Video lock',
                        style: TextStyle(
                          color: host.mainTrackLocked
                              ? TjProTheme.gold
                              : Colors.white54,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, constraints) {
              final halfPad = constraints.maxWidth / 2 - 52;
              final contentW = halfPad * 2 + total * host.tlPxPerSec;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Fixed left column: red + (add) and, under it,
                  // the selected clip's Mute toggle (InShot's
                  // "Mute Clip" label zone).
                  SizedBox(
                    width: 52,
                    child: Column(
                      children: [
                        Material(
                          color: const Color(0xFFE53935),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: host.busy ? null : () => showAddMediaSheet(host),
                            child: const SizedBox(
                              width: 38,
                              height: 38,
                              child: Icon(
                                Icons.add,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Timeline zoom (Phase 2): − / + scale the
                        // strip around the playhead centre.
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            InkWell(
                              onTap: () => host.tlZoomBy(1 / 1.4),
                              child: const Padding(
                                padding: EdgeInsets.all(2),
                                child: Icon(
                                  Icons.remove,
                                  size: 15,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () => host.tlZoomBy(1.4),
                              child: const Padding(
                                padding: EdgeInsets.all(2),
                                child: Icon(
                                  Icons.add,
                                  size: 15,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        if (host.clips.isNotEmpty)
                          InkWell(
                            onTap: () {
                              final clip = host.clips[host.selected];
                              host.update(() => clip.muted = !clip.muted);
                              unawaited(
                                host.controller?.setVolume(
                                      clip.muted ? 0 : clip.volume,
                                    ) ??
                                    Future<void>.value(),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 2,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    host.clips[host.selected].muted
                                        ? Icons.volume_off
                                        : Icons.volume_up,
                                    size: 14,
                                    color: Colors.white70,
                                  ),
                                  const SizedBox(width: 2),
                                  const Text(
                                    'Mute',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        NotificationListener<ScrollNotification>(
                          onNotification: (n) {
                            // Build 4 player fix: jumpTo() (playback
                            // follow + zoom) dispatches its own scroll
                            // notifications — they are not user scrubs
                            // and must not touch the player.
                            if (host.tlProgrammaticScroll) return false;
                            if (n is ScrollStartNotification) {
                              host.tlUserScrolling = true;
                            } else if (n is ScrollUpdateNotification) {
                              // Live scrub (Phase 2): the preview
                              // follows the drag (paused only,
                              // debounced in _scheduleScrubSeek).
                              host.scheduleScrubSeek();
                            } else if (n is ScrollEndNotification) {
                              host.tlUserScrolling = false;
                              // Build 4 player fix: while playing, the
                              // strip FOLLOWS the player — a ScrollEnd
                              // here must not seek (the seek-fight loop
                              // that pinned playback at 0:00 on v1.5.5).
                              if (!TimelineMath.scrubSeekOnScrollEnd(
                                isPlaying: host.clock.isPlaying,
                                programmaticScroll:
                                    host.tlProgrammaticScroll,
                              )) {
                                return false;
                              }
                              var centreSec =
                                  host.tlScroll.offset / host.tlPxPerSec;
                              // Snap the resting playhead to a
                              // clip boundary when it lands close
                              // (Phase 2), with a light tick.
                              // A1 (v1.12): beats + manual markers
                              // are snap targets too.
                              final snapped = TimelineMath.snapSec(
                                centreSec,
                                [
                                  ...TimelineMath.boundaries(
                                    host.effectiveDurations,
                                  ),
                                  ...host.timelineBeats,
                                  ...host.markers,
                                ],
                                0.15,
                              );
                              if (snapped != centreSec) {
                                centreSec = snapped;
                                HapticFeedback.selectionClick();
                              }
                              unawaited(host.seekToGlobalSec(centreSec));
                            }
                            return false;
                          },
                          child: SingleChildScrollView(
                            controller: host.tlScroll,
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: contentW,
                              height: 74,
                              child: Stack(
                                children: [
                                  // Ruler labels every 2s.
                                  for (var s = 0; s <= total; s += 2)
                                    Positioned(
                                      left: halfPad + s * host.tlPxPerSec - 8,
                                      top: 0,
                                      child: Text(
                                        '${s}s',
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 9,
                                        ),
                                      ),
                                    ),
                                  // A1 (v1.12): beat ticks in the
                                  // ruler band — the detected beats,
                                  // mapped onto the timeline by
                                  // host.timelineBeats (music = 0
                                  // offset; a clip's beats shift by
                                  // its start + trim).
                                  for (final t in host.timelineBeats)
                                    Positioned(
                                      left: halfPad +
                                          t * host.tlPxPerSec -
                                          0.75,
                                      top: 2,
                                      child: Container(
                                        width: 1.5,
                                        height: 9,
                                        color: Colors.white38,
                                      ),
                                    ),
                                  // A1 (v1.12): manual markers —
                                  // a gold flag on the ruler and a
                                  // thin gold line down the strip.
                                  for (final t in host.markers) ...[
                                    Positioned(
                                      left: halfPad +
                                          t * host.tlPxPerSec -
                                          0.75,
                                      top: 11,
                                      bottom: 0,
                                      child: Container(
                                        width: 1.5,
                                        color: TjProTheme.gold
                                            .withValues(alpha: 0.55),
                                      ),
                                    ),
                                    Positioned(
                                      left: halfPad +
                                          t * host.tlPxPerSec -
                                          4,
                                      top: 0,
                                      child: Icon(
                                        Icons.bookmark,
                                        size: 9,
                                        color: TjProTheme.gold,
                                      ),
                                    ),
                                  ],
                                  // Clip blocks.
                                  for (var i = 0;
                                      i < host.clips.length;
                                      i++)
                                    _timelineClipBlock(
                                      i,
                                      left: halfPad +
                                          host.clipStartSec(i) * host.tlPxPerSec,
                                    ),
                                  // Transition badges.
                                  for (var i = 1;
                                      i < host.clips.length;
                                      i++)
                                    Positioned(
                                      left: halfPad +
                                          host.clipStartSec(i) * host.tlPxPerSec -
                                          11,
                                      top: 26,
                                      child: GestureDetector(
                                        onTap: () =>
                                            host.openTool('transitions'),
                                        child: Container(
                                          width: 22,
                                          height: 22,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(5),
                                          ),
                                          child: Icon(
                                            host.crossfade
                                                ? Icons.swap_horiz
                                                : Icons.add,
                                            size: 14,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // FIXED centre playhead.
                        Positioned(
                          left: (constraints.maxWidth - 52) / 2,
                          top: 0,
                          bottom: 0,
                          child: Container(
                            width: 2,
                            color: const Color(0xFFFFD60A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          if (host.fxPip) ...[
            const SizedBox(height: 4),
            _laneRow(
              laneKey: 'pip',
              icon: Icons.picture_in_picture_alt,
              label: 'PIP',
              child: InkWell(
              onTap: () => host.update(() {
                host.elementRow = true;
                host.clipRow = false;
                host.activeTool = null;
              }),
              child: Container(
                height: 22,
                decoration: BoxDecoration(
                  color: host.elementRow
                      ? const Color(0xFF6A4C00)
                      : const Color(0xFF263238),
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: const Row(
                  children: [
                    Icon(
                      Icons.picture_in_picture_alt,
                      size: 13,
                      color: Colors.white70,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'PIP element',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ),
          ],
          const SizedBox(height: 4),
          // Audio lane.
          _laneRow(
            laneKey: 'audio',
            icon: Icons.music_note,
            label: 'Audio',
            child: InkWell(
            onTap: () => host.openToolTab('audio', 'music'),
            child: Container(
              height: 22,
              decoration: BoxDecoration(
                color: host.musicPath != null
                    ? const Color(0xFF37474F)
                    : const Color(0xFF222222),
                borderRadius: BorderRadius.circular(4),
                // Phase 2: the music file's waveform as the lane
                // background (plain lane until it renders).
                image: (wavePath != null && wavePath.isNotEmpty)
                    ? DecorationImage(
                        image: FileImage(File(wavePath)),
                        fit: BoxFit.fill,
                        opacity: 0.5,
                      )
                    : null,
              ),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.music_note,
                    size: 13,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      host.musicPath != null
                          ? p.basename(host.musicPath!)
                          : '+ Add audio',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ),
          const SizedBox(height: 4),
          // Text lane.
          _laneRow(
            laneKey: 'text',
            icon: Icons.text_fields,
            label: 'Text',
            child: InkWell(
            onTap: () => host.openTool('text'),
            child: Container(
              height: 22,
              decoration: BoxDecoration(
                color: host.text.trim().isNotEmpty
                    ? const Color(0xFF37474F)
                    : const Color(0xFF222222),
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.text_fields,
                    size: 13,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      host.text.trim().isNotEmpty
                          ? host.text.trim()
                          : host.captions.isNotEmpty
                              ? '${host.captions.length} captions'
                              : '+ Add text',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ),
          // Build 3 (Phase 3): the Keyframes lane — ◆ points at
          // each active track's keyframe times (gold = title /
          // sticker track, cyan = PIP track; both tracks span the
          // whole timeline in v1, so the points sit at the two
          // ends, top row = title, bottom row = PIP). Shown only
          // while a keyframe track is on; tapping opens the
          // Animation panel.
          if ((host.proKeyframes &&
                  (host.proTitle.trim().isNotEmpty ||
                      host.proSticker.trim().isNotEmpty)) ||
              (host.pipKeyframes && host.fxPip)) ...[
            const SizedBox(height: 4),
            _laneRow(
              laneKey: 'keyframes',
              icon: Icons.animation,
              label: 'Keys',
              child: InkWell(
                onTap: () => host.openToolTab('overlay', 'keyframes'),
                child: Container(
                  height: 22,
                  decoration: BoxDecoration(
                    color: const Color(0xFF222222),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: LayoutBuilder(
                    builder: (context, c) {
                      Widget diamond(double frac, double top, Color color) =>
                          Positioned(
                            left: (frac * c.maxWidth).clamp(
                              0.0,
                              c.maxWidth - 10,
                            ),
                            top: top,
                            child: Transform.rotate(
                              angle: 0.7853981633974483,
                              child: Container(
                                width: 9,
                                height: 9,
                                color: color,
                              ),
                            ),
                          );
                      final titleTrack = host.proKeyframes &&
                          (host.proTitle.trim().isNotEmpty ||
                              host.proSticker.trim().isNotEmpty);
                      final pipTrack = host.pipKeyframes && host.fxPip;
                      return Stack(
                        children: [
                          if (titleTrack) ...[
                            diamond(0, 2, TjProTheme.gold),
                            diamond(1, 2, TjProTheme.gold),
                          ],
                          if (pipTrack) ...[
                            diamond(0, 11, Colors.cyanAccent),
                            diamond(1, 11, Colors.cyanAccent),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 4),
          // Times row — current centred, total right, both from
          // the ONE clock/model (#5).
          AnimatedBuilder(
            animation: host.clock,
            builder: (context, _) {
              String fmtT(double sec) {
                final m = sec ~/ 60;
                final s = (sec % 60).floor().toString().padLeft(2, '0');
                return '$m:$s';
              }

              return SizedBox(
                height: 16,
                child: Stack(
                  children: [
                    Center(
                      child: Text(
                        fmtT(host.globalPositionSec),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        fmtT(total),
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Formal track header (Phase 2): every lane gets the same
  /// 52-wide label cell (icon + name + show/hide eye) aligned with
  /// the strip's fixed column, turning the summary lanes into
  /// named tracks. Hiding collapses the lane to a slim strip; the
  /// lane's content and taps return when it is shown again.
  Widget _laneRow({
    required String laneKey,
    required IconData icon,
    required String label,
    required Widget child,
  }) {
    final hidden = host.laneHidden.contains(laneKey);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 52,
          child: Row(
            children: [
              Icon(icon, size: 12, color: Colors.white54),
              const SizedBox(width: 2),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 9,
                  ),
                ),
              ),
              InkWell(
                onTap: () => host.update(() {
                  if (hidden) {
                    host.laneHidden.remove(laneKey);
                  } else {
                    host.laneHidden.add(laneKey);
                  }
                }),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    hidden ? Icons.visibility_off : Icons.visibility,
                    size: 13,
                    color: Colors.white54,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: hidden
              ? Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B1B1B),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '$label hidden',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 9,
                    ),
                  ),
                )
              : child,
        ),
      ],
    );
  }

  /// One filmstrip block on the new timeline: real thumbnails
  /// (photo clips show themselves), gold border when selected,
  /// trim handles on the selected block, tap = select + preview,
  /// long-press = the swap sheet ("Long press to swap").
  Widget _timelineClipBlock(int i, {required double left}) {
    final clip = host.clips[i];
    final w = clip.effectiveDuration * host.tlPxPerSec;
    final selected = i == host.selected;
    final thumbs = host.thumbCache[host.thumbKey(clip)];
    return Positioned(
      // Keyed by the clip OBJECT so a drag-reorder moves the
      // block's element (and its live gesture) with the clip.
      key: ObjectKey(clip),
      left: left,
      top: 14,
      width: w,
      height: 56,
      child: GestureDetector(
        onTap: () {
          host.update(() {
            host.selected = i;
            host.clipRow = true;
            host.elementRow = false;
          });
          unawaited(host.loadPreview());
        },
        // Long press: drag = live reorder (Phase 2); a stationary
        // press still opens the swap sheet (the original path).
        // Locked track: no reorder at all.
        onLongPressStart: host.mainTrackLocked
            ? null
            : (_) => host.onClipDragStart(i),
        onLongPressMoveUpdate: host.mainTrackLocked ? null : host.onClipDragMove,
        onLongPressEnd: host.mainTrackLocked
            ? null
            : (_) => host.onClipDragEnd(i),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? TjProTheme.gold : Colors.white24,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(4),
            color: const Color(0xFF2A2A2A),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(
                child: thumbs == null || thumbs.isEmpty
                    ? const Center(
                        child: Icon(
                          Icons.movie,
                          color: Colors.white38,
                          size: 18,
                        ),
                      )
                    : Row(
                        children: [
                          for (var k = 0; k < 24; k++)
                            Expanded(
                              child: Image.file(
                                File(thumbs[k % thumbs.length]),
                                fit: BoxFit.cover,
                                height: 56,
                                errorBuilder: (_, _, _) =>
                                    const ColoredBox(
                                  color: Color(0xFF2A2A2A),
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
              if (clip.isPhoto)
                const Positioned(
                  left: 3,
                  top: 3,
                  child: Icon(
                    Icons.photo,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              if (selected && !host.mainTrackLocked) ...[
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 14,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (d) {
                      host.update(() {
                        var v = (clip.trimStart +
                                d.delta.dx / host.tlPxPerSec)
                            .clamp(0, clip.effectiveEnd - 0.3)
                            .toDouble();
                        // Snap to the clip's true start (Phase 2),
                        // one haptic tick per engagement.
                        // A1 (v1.12): beats + markers inside this
                        // clip are targets too, converted to the
                        // handle's file-second domain.
                        final snapped = TimelineMath.snapSec(
                          v,
                          [
                            0.0,
                            ...TimelineMath.trimSnapFilePoints(
                              clipStart: host.clipStartSec(i),
                              trimStart: clip.trimStart,
                              effectiveDuration: clip.effectiveDuration,
                              timelinePoints: [
                                ...host.timelineBeats,
                                ...host.markers,
                              ],
                            ),
                          ],
                          0.08,
                        );
                        if (snapped != v) {
                          if (!host.trimSnapped) {
                            host.trimSnapped = true;
                            HapticFeedback.selectionClick();
                          }
                          v = snapped;
                        } else {
                          host.trimSnapped = false;
                        }
                        clip.trimStart = v;
                      });
                    },
                    onHorizontalDragEnd: (_) {
                      host.trimSnapped = false;
                      host.pushHistory();
                    },
                    child: Container(
                      color: TjProTheme.gold.withValues(alpha: 0.85),
                      child: const Icon(
                        Icons.chevron_left,
                        size: 12,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 14,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (d) {
                      host.update(() {
                        final full = clip.duration.inMilliseconds / 1000;
                        var v = (clip.effectiveEnd +
                                d.delta.dx / host.tlPxPerSec)
                            .clamp(clip.trimStart + 0.3, full);
                        // Snap to the clip's true end (Phase 2).
                        // A1 (v1.12): beats + markers inside this
                        // clip are targets too (file-second domain).
                        final snapped = TimelineMath.snapSec(
                          v,
                          [
                            full,
                            ...TimelineMath.trimSnapFilePoints(
                              clipStart: host.clipStartSec(i),
                              trimStart: clip.trimStart,
                              effectiveDuration: clip.effectiveDuration,
                              timelinePoints: [
                                ...host.timelineBeats,
                                ...host.markers,
                              ],
                            ),
                          ],
                          0.08,
                        );
                        if (snapped != v) {
                          if (!host.trimSnapped) {
                            host.trimSnapped = true;
                            HapticFeedback.selectionClick();
                          }
                          v = snapped;
                        } else {
                          host.trimSnapped = false;
                        }
                        clip.trimEnd = v;
                      });
                    },
                    onHorizontalDragEnd: (_) {
                      host.trimSnapped = false;
                      host.pushHistory();
                    },
                    child: Container(
                      color: TjProTheme.gold.withValues(alpha: 0.85),
                      child: const Icon(
                        Icons.chevron_right,
                        size: 12,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

  /// The add-media sheet behind the timeline's red + button.
  void showAddMediaSheet(VideoEditorController host) {
    showModalBottomSheet<void>(
      context: host.context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.videocam, color: Colors.white),
              title: const Text(
                'Video add karein',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                unawaited(host.addClip());
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo, color: Colors.white),
              title: const Text(
                'Photo add karein',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                unawaited(host.addPhotoClip());
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Long-press on a clip block: swap it with a neighbour
  /// ("Long press to swap" — the reorder path of the new
  /// timeline).
  void showSwapSheet(VideoEditorController host, int i) {
    showModalBottomSheet<void>(
      context: host.context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (i > 0)
              ListTile(
                leading:
                    const Icon(Icons.arrow_back, color: Colors.white),
                title: const Text(
                  'Peechay wali clip se swap',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  swapClips(host, i, i - 1);
                },
              ),
            if (i < host.clips.length - 1)
              ListTile(
                leading:
                    const Icon(Icons.arrow_forward, color: Colors.white),
                title: const Text(
                  'Aglay wali clip se swap',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  swapClips(host, i, i + 1);
                },
              ),
          ],
        ),
      ),
    );
  }

  void swapClips(VideoEditorController host, int a, int b) {
    host.pushHistory();
    host.update(() {
      final tmp = host.clips[a];
      host.clips[a] = host.clips[b];
      host.clips[b] = tmp;
      host.selected = b;
    });
    unawaited(host.loadPreview());
  }
