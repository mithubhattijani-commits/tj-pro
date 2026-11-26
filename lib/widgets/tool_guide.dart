/// Point #21 — HAR TOOL MEIN GUIDE (user, 2026-11-25).
///
/// ONE reusable guide system for the whole app: every tool
/// panel carries a Guide button (placed in its header — the
/// editors' panel headers and the News Studio's panel shell),
/// and tapping it opens [ToolGuideSheet] with that tool's
/// entry from [kToolGuides]: ye tool kya karta hai, kaise
/// kaam karta hai, aur step-by-step kaise istemal hota hai —
/// asan Roman Urdu mein, app ki apni awaz mein.
///
/// The data is ONE map keyed by guide id:
///   `ve.<panel key>`  — Video Editor panels (plus the rail's
///                       instant ops: split/delete/…)
///   `pe.<tool key>`   — Photo Editor tools
///   `ns.<dock key>`   — News Studio dock tools
///   `motion`          — Motion Graphics Studio (Gallery)
///
/// A future tool joins by adding ONE entry here and passing
/// its id to [ToolGuideButton] — nothing else changes. A
/// missing id renders NO button (never a broken one); the
/// coverage test (test/next_build_guide_parts_test.dart)
/// pins every inventoried dock/panel id to a real entry.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

/// One tool's guide: kya karta hai (aik-do lines), step-by-step
/// istemal, aur aam maslon ke hal.
class ToolGuideEntry {
  const ToolGuideEntry({
    required this.title,
    required this.what,
    required this.steps,
    this.tips = const [],
  });

  /// The tool's display name (the app's own label).
  final String title;

  /// Ye tool kya karta hai — aik ya do lines.
  final String what;

  /// Step-by-step istemal (numbered, isi tarteeb mein).
  final List<String> steps;

  /// 'If something goes wrong' — common mistakes and their fixes.
  final List<String> tips;
}

/// The guide entry for [id], or null when none exists.
ToolGuideEntry? toolGuideFor(String id) => kToolGuides[id];

/// The Video Editor's panel key → guide id ('clipVolume'
/// shares the Volume panel's guide).
String vePanelGuideId(String toolKey) =>
    toolKey == 'clipVolume' ? 've.volume' : 've.$toolKey';

/// Opens [guideId]'s guide as a bottom sheet. An unknown id
/// does nothing (the button hides itself in that case anyway).
void showToolGuide(BuildContext context, String guideId) {
  final entry = toolGuideFor(guideId);
  if (entry == null) return;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF12151C),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => ToolGuideSheet(entry: entry),
  );
}

/// The Guide button placed in every tool's header/panel —
/// ONE look everywhere: a small gold help icon + 'Guide'.
/// Renders nothing when the id has no entry.
///
/// [compact] = sirf icon wala 28px gold circle — un headers ke
/// liye jahan jagah fix hai (panel headers): labeled button ki
/// chaurai se fixed-height panel zones overflow ho jate thay
/// (panel_overflow_test ne pakra), is liye headers compact
/// istemal karte hain; AppBar jaisi khuli jagah par poora
/// 'Guide' label wala button lagta hai.
class ToolGuideButton extends StatelessWidget {
  const ToolGuideButton({
    super.key,
    required this.guideId,
    this.compact = false,
  });

  final String guideId;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (toolGuideFor(guideId) == null) return const SizedBox.shrink();
    if (compact) {
      return Tooltip(
        message: 'Guide',
        child: InkWell(
          key: Key('toolGuideButton-$guideId'),
          onTap: () => showToolGuide(context, guideId),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: TjProTheme.gold, width: 1.2),
            ),
            child: const Icon(
              Icons.help_outline,
              size: 16,
              color: TjProTheme.gold,
            ),
          ),
        ),
      );
    }
    return TextButton.icon(
      key: Key('toolGuideButton-$guideId'),
      onPressed: () => showToolGuide(context, guideId),
      icon: const Icon(Icons.help_outline, size: 17),
      label: const Text('Guide'),
      style: TextButton.styleFrom(
        foregroundColor: TjProTheme.gold,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// The guide sheet itself: title, 'kya karta hai',
/// step-by-step steps, aur 'agar masla aye to' tips.
class ToolGuideSheet extends StatelessWidget {
  const ToolGuideSheet({super.key, required this.entry});

  final ToolGuideEntry entry;

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.82;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.help_outline,
                    size: 20,
                    color: TjProTheme.gold,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${entry.title} — Guide',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const _GuideHeading('What this tool does'),
              Text(
                entry.what,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: Color(0xFFD8DBE0),
                ),
              ),
              const SizedBox(height: 14),
              const _GuideHeading('How to use — step by step'),
              for (var i = 0; i < entry.steps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 21,
                        height: 21,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: TjProTheme.gold,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          entry.steps[i],
                          style: const TextStyle(
                            fontSize: 13.5,
                            height: 1.45,
                            color: Color(0xFFD8DBE0),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (entry.tips.isNotEmpty) ...[
                const SizedBox(height: 8),
                const _GuideHeading('If something goes wrong'),
                for (final tip in entry.tips)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '•  ',
                          style: TextStyle(
                            fontSize: 13.5,
                            color: TjProTheme.gold,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            tip,
                            style: const TextStyle(
                              fontSize: 13.5,
                              height: 1.45,
                              color: Color(0xFFD8DBE0),
                            ),
                          ),
                        ),
                      ],
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

class _GuideHeading extends StatelessWidget {
  const _GuideHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: TjProTheme.gold,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Every tool's guide, by id. Adding a tool = adding an entry.
const Map<String, ToolGuideEntry> kToolGuides = {
  ..._veGuides,
  ..._peGuides,
  ..._nsGuides,
};

// ---------------------------------------------------------------------
// Video Editor — panel keys (video_editor_panels.dart dispatch)
// + the rail's instant ops (tool_rows.dart).
// ---------------------------------------------------------------------
const Map<String, ToolGuideEntry> _veGuides = {
  've.canvas': ToolGuideEntry(
    title: 'Canvas',
    what:
        'Sets the video size (ratio), zoom and the background behind it — '
        'such as 9:16 for Reels or 16:9 for YouTube.',
    steps: [
      'From the Ratio tab, choose the video size (9:16, 16:9, 1:1, etc.).',
      'In the Zoom tab, make the video bigger/smaller to fit the frame.',
      'From the Background tab, set a colour or a blurred picture behind.',
      'Tap ✓ above — the change will be confirmed.',
    ],
    tips: [
      'If the video is being cut at the edges, reduce the Zoom to bring it fully into the frame.',
      'The background shows only when the video is smaller than the frame.',
    ],
  ),
  've.precut': ToolGuideEntry(
    title: 'Precut (Trim / Cut / Split)',
    what:
        'It is for cutting the unwanted parts of a clip — Trim for the edges, '
        'Cut for the middle portion, and Split to divide a clip into two parts.',
    steps: [
      'First select the clip on the timeline you want to work on.',
      'Trim: drag the handles at the clip\'s start/end to remove the unwanted part.',
      'Cut: set two points and remove the middle portion.',
      'Split: wherever the playhead (yellow line) is, the clip divides right there.',
      'Tap ✓ above to close the panel.',
    ],
    tips: [
      'Split happens at the playhead\'s position — first play the video or drag the timeline to bring the line to the right place.',
      'If a cut goes wrong, the Undo (↩) above brings it back.',
    ],
  ),
  've.split': ToolGuideEntry(
    title: 'Split',
    what:
        'The clip UNDER the playhead (yellow line) is cut into two parts exactly at the line '
        'cuts from that place into two parts — then each part separately '
        'can be handled separately.',
    steps: [
      'Drag the timeline to bring the yellow line to the cutting spot — the clip under the line is the one that will be cut (not an older selected clip).',
      'Tap Split — the clip will divide right there, and a confirmation will show on screen.',
      'At the top of the panel is the "At playhead / From the middle" choice: At playhead = at the line; From the middle = the selected clip is cut exactly in the middle.',
    ],
    tips: [
      'If the line is exactly on the clip\'s edge, the split does NOT happen and the reason shows on screen — it no longer cuts silently from the middle like before. Move the line a little inward.',
      'After a split, the first (left) part stays selected — pressing again will not cut at the wrong place.',
      'The time shown in the middle of the timeline is the actual second under the line — verify from there before cutting.',
      'Split also obeys the timeline snap setting (in the Trim panel\'s Timeline section) — with snap off, the line is completely free.',
    ],
  ),
  've.timeline': ToolGuideEntry(
    title: 'Timeline (Precision)',
    what:
        'The timeline is now ready for fine work — zoom, '
        'timecode, frame-by-frame movement, snap, multi-select and range.',
    steps: [
      'Zoom: pinch with two fingers, or tap −/+; with the Fit button (on the right) the whole video comes into one view.',
      'Timecode: tap the TC chip and the time shows in H:MM:SS:FF; with the ‹ › buttons next to play, move one frame forward/back.',
      'Snap: the anchor chip turns snap on/off; hold the chip (long press) to change the strength — Light, Normal, Strong. The full setting is in the Timeline section of the Trim panel.',
      'Multi-select: turn on the checklist chip and choose many clips — then delete, duplicate or move them together.',
      'Range: from the Range section of the Trim panel, set In/Out at the playhead — a gold band will appear; then looping the range or deleting it is one tap.',
      'When a tool is open, the timeline hides itself so the preview stays big and only that tool\'s options show — close the tool and the timeline comes back.',
    ],
    tips: [
      'When snap is off, the playhead/trim are completely free — no point pulls them.',
      'In a range delete, a clip that falls half in the range is cut right there — nothing disappears.',
      'The time in the middle of the timeline is always the second under the line — the playhead and the label never disagree.',
      'Inside a panel, the sections appear as chips in one line at the top — tap a chip and only that section\'s options show below; you do not have to scroll the whole panel.',
    ],
  ),
  've.trim': ToolGuideEntry(
    title: 'Trim / Roll / Slip',
    what:
        'Fixing the clip\'s length and inside portion. There are three modes '
        'are: Trim (cutting edges), Roll (the boundary of two clips), '
        'Slip (slide the inner portion).',
    steps: [
      'Choose a mode: Trim, Roll or Slip — the timeline handles work in the same mode.',
      'Trim: set start/end with the sliders, or keep the playhead inside the clip and tap "Start → playhead" / "End → playhead".',
      'Roll: the boundary will move — one clip longer, the other shorter, total length unchanged. Drag the handle on the timeline or tap the 1-frame buttons.',
      'Slip: the clip stays in its place; the inner portion slides forward/back. Drag the clip left/right on the timeline or tap the 0.1s buttons.',
      'The Range (In/Out), Snap and Timecode settings are also below in this panel.',
    ],
    tips: [
      'A photo clip does not slip — it has no inner portion to slide.',
      'Roll happens only between two clips — it does not apply at the first clip\'s start or the last clip\'s end.',
    ],
  ),
  've.delete': ToolGuideEntry(
    title: 'Delete',
    what: 'Removes the selected clip from the timeline.',
    steps: [
      'Select the clip on the timeline that you want to remove.',
      'Tap Delete — the clip will disappear and the other clips will close the gap.',
    ],
    tips: [
      'If it is deleted by mistake, the clip comes back with Undo (↩).',
    ],
  ),
  've.duplicate': ToolGuideEntry(
    title: 'Duplicate',
    what: 'Makes another copy of the selected clip right next to it.',
    steps: [
      'Select a clip.',
      'Tap Duplicate — the copy will be placed right after it.',
    ],
    tips: [
      'The copy is exactly like the original — a separate effect/speed can be applied to it.',
    ],
  ),
  've.disable': ToolGuideEntry(
    title: 'Disable',
    what:
        'Turns the selected clip off WITHOUT deleting it — its place on the '
        'timeline stays, but the preview shows black and the export renders '
        'black + silence for its length. Turn it back on with Enable.',
    steps: [
      'Select a clip.',
      'Tap Disable — the clip block is veiled with an OFF mark.',
      'Tap Enable to bring it back exactly as it was.',
    ],
    tips: [
      'Good for A/B comparison: disable a clip, export, then enable and export again.',
      'Small badges on a clip block show its real state: muted, volume changed, trimmed, audio unlinked.',
      'Lane controls: the speaker icon on the Audio lane mutes the music in the export; the lock on the PIP lane protects the PIP window from accidental drags.',
    ],
  ),
  've.label': ToolGuideEntry(
    title: 'Label',
    what:
        'Gives the selected clip a colour label — a coloured strip on its '
        'timeline block, saved with the project.',
    steps: [
      'Select a clip.',
      'Tap Label and pick a colour (or None to remove it).',
    ],
    tips: [
      'Use colours to mark kinds of clips — for example blue for the main story, green for B-roll, yellow for waiting.',
    ],
  ),
  've.replace': ToolGuideEntry(
    title: 'Replace',
    what:
        'Replaces the selected clip with another video from the gallery — '
        'the place and duration stay the same.',
    steps: [
      'Select a clip.',
      'Tap Replace and choose a new video from the gallery.',
      'The new video will be placed at the old place, at the same length.',
    ],
    tips: [
      'If the new video is short it may loop/be cut short — choosing a longer video is better.',
    ],
  ),
  've.freeze': ToolGuideEntry(
    title: 'Freeze',
    what:
        'Freezing the playhead frame makes a still picture-clip '
        'that stays on screen for a few seconds.',
    steps: [
      'Bring the yellow line to the frame you want to freeze.',
      'Tap Freeze — a freeze clip will be placed there.',
      'You can increase/decrease its length by dragging the edges.',
    ],
    tips: [
      'Freeze is best for emphasising a special moment.',
    ],
  ),
  've.capture': ToolGuideEntry(
    title: 'Capture',
    what: 'Makes a picture (photo) of the playhead frame and places it as a clip.',
    steps: [
      'Peeli line matlooba frame par layein.',
      'Tap Capture — a photo clip of that frame will be placed on the timeline.',
    ],
    tips: [
      'Capture a good frame for a thumbnail or cover and use it.',
    ],
  ),
  've.reverse': ToolGuideEntry(
    title: 'Reverse',
    what: 'Plays the selected clip in reverse — from the end towards the start.',
    steps: [
      'Select a clip.',
      'Tap Reverse — it will take a little time, the clip will play in reverse.',
    ],
    tips: [
      'In reverse the sound also reverses — if needed, turn the sound off from Volume.',
      'Reverse takes more time on a long clip.',
    ],
  ),
  've.switch': ToolGuideEntry(
    title: 'Switch',
    what:
        'Removes the selected clip from the main video and makes it a small PIP (picture '
        'in picture), or turns PIP back into the main.',
    steps: [
      'Select a clip.',
      'Tap Switch — the clip will become PIP (or PIP back to a main clip).',
      'Drag the PIP with your finger to set its place and size.',
    ],
    tips: [
      'More PIP settings are in the Overlay PIP tab.',
    ],
  ),
  've.speed': ToolGuideEntry(
    title: 'Speed',
    what:
        'Changes the clip\'s speed — slow motion or fast. With Curve, the speed '
        'changes gradually; with Beat, to the music\'s beat.',
    steps: [
      'Select the clip and open Speed.',
      'In the Standard tab, set the speed with the slider (0.5× slow, 2× fast).',
      'In the Curve tab, choose ready shapes — the speed will change smoothly.',
      'Tap ✓ — the clip length will change according to the speed.',
    ],
    tips: [
      'In slow motion the sound also slows down — often the Volume is reduced.',
      'Very fast (more than 4×) video can look jerky.',
    ],
  ),
  've.audio': ToolGuideEntry(
    title: 'Audio',
    what:
        'The centre of the video\'s sound: applying background Music, changing the voice with Voice Effect, '
        'and reducing noise with Clean.',
    steps: [
      'Music tab: apply music from your file or the Store, set the volume.',
      'Voice tab: apply an effect (voice changer) to the voice.',
      'Clean tab: reduce the recording\'s noise/hiss.',
      'Every tab\'s change is confirmed with ✓.',
    ],
    tips: [
      'If the music is loud and the voice is drowned, keep the music volume at 20–30%.',
      'More audio tools also include a converter, trimmer and joiner.',
    ],
  ),
  've.volume': ToolGuideEntry(
    title: 'Volume',
    what: 'Increases or decreases the selected clip\'s sound volume.',
    steps: [
      'Select a clip.',
      'Set the volume with the slider — 0 means the sound is fully off.',
      'tap ✓.',
    ],
    tips: [
      'To turn off the background clip\'s sound, set the volume to 0.',
    ],
  ),
  've.text': ToolGuideEntry(
    title: 'Text',
    what:
        'Applies text on the video — plain Text, ready Motion Titles, and '
        'Captions that are created automatically from speech.',
    steps: [
      'Text tab: write the text, then set its Font, Size, Colour and Background pill.',
      'Tap the text on the preview to select it — the Text tab opens with all its options.',
      'Pinch the text on the preview with two fingers to make it bigger or smaller (the Size slider moves with it).',
      'Titles tab: choose a ready animated title and write your words.',
      'Captions tab: create captions automatically from the video\'s voice (Urdu AI is also available).',
      'Once captions exist, the timeline shows a CC lane: every caption is a strip at its time — tap a strip to jump to it and edit it.',
    ],
    tips: [
      'Captions take a little time to create — if the video is long, be patient.',
      'If the text does not show, check whether it is inside the clip\'s time.',
      'The Kasheeda font exports exactly as it previews; other fonts style the preview and the export uses the system font.',
      'Every video clip block shows its real audio waveform at the bottom — a flat line means silence there.',
    ],
  ),
  've.colour': ToolGuideEntry(
    title: 'Colour (Filters / Adjust)',
    what:
        'Fixes the video colours — a look in one tap with Filters, '
        'Fine settings for light, colour and clarity from Adjust.',
    steps: [
      'Filters tab: choose a filter and set its amount (intensity).',
      'Adjust tab: fix brightness, contrast, saturation etc. with the sliders.',
      'The effect shows in the preview as you go — confirm with ✓.',
      'My Looks: save the settings you like with a name using "Save look" under Adjust — next time that look applies with one tap.',
    ],
    tips: [
      'The effect of LUT, Sharpen and Clarity appears only in the exported video — it does not show in the preview; this is normal.',
      'With hold-to-compare you can see the before/after state.',
      'Saved looks stay only on this phone; a look is removed with its dustbin (delete) icon, and saving again with the same name updates the look.',
    ],
  ),
  've.effects': ToolGuideEntry(
    title: 'Effects',
    what:
        'Applies visual effects on the video; with Tracking, the effect '
        'sticks to a thing and moves with it.',
    steps: [
      'Choose an effect from the Effects tab — it will show in the preview immediately.',
      'Tracking tab: attach the effect to a point; it will move with it.',
      'tap ✓.',
    ],
    tips: [
      'Too many effects can make the video heavy and slow — keep just one or two.',
    ],
  ),
  've.overlay': ToolGuideEntry(
    title: 'Overlay (Sticker / Keyframes / PIP)',
    what:
        'Places things over the video — Sticker, a small glimpse of another video '
        'glimpse (PIP), and movement animation with Keyframes.',
    steps: [
      'Sticker tab: choose a sticker, set its place and size.',
      'PIP tab: place another video/photo on top; edges can be round or masked too.',
      'PIP timing: set the Start/End sliders (or the playhead buttons) to show the inset only on part of the timeline — the PIP lane shows that window as a segment; drag the segment to move the window.',
      'Keyframes tab: give something movement over time.',
      'Confirm with ✓.',
    ],
    tips: [
      'When PIP is selected, the element row appears below — Edit/Delete is easy from there.',
      'The PIP sections (Position, Size, Style, Blend, Mask) are chips in one line at the top of the panel — tap a chip and only that section\'s options appear.',
      'A Motion overlay placed with "Place on Video" is this same PIP layer — its timing window is set the same way. The inset starts at its own beginning when the window starts; in the preview it loops inside the window, in the export a shorter inset holds its last frame until the window ends.',
    ],
  ),
  've.aicut': ToolGuideEntry(
    title: 'AI Cut',
    what:
        'Helps you automatically find and cut the silent and useless parts of a video '
        '— for making a long recording shorter.',
    steps: [
      'Open AI Cut and let the analysis finish.',
      'Check the parts you want to keep; the rest will be cut.',
      'Tap Apply — a new shorter version will be created.',
    ],
    tips: [
      'The AI suggestion is not perfect every time — check the preview before applying.',
      'This tool runs on coins; the price is written on the button.',
    ],
  ),
  've.voiceenhance': ToolGuideEntry(
    title: 'Voice Enhance',
    what: 'Makes the recording\'s sound clean and clear — less noise, prominent voice.',
    steps: [
      'Select the clip and open Voice Enhance.',
      'Set the amount and check by listening to the preview.',
      'tap ✓.',
    ],
    tips: [
      'Too much enhance can make the sound unnatural — a medium amount is better.',
    ],
  ),
  've.edit': ToolGuideEntry(
    title: 'Crop / Transform',
    what: 'Cropping the clip, rotating it, and changing its place/size in the frame.',
    steps: [
      'Drag the edges to crop — the outside part will be cut off.',
      'Change the size with Scale, the place with Position.',
      'tap ✓.',
    ],
    tips: [
      'If empty space appears after cropping, you can fill it from the Canvas Background.',
    ],
  ),
  've.enhance': ToolGuideEntry(
    title: 'Enhance (HD)',
    what: 'Improves the video quality — cleanliness and sharpness increase.',
    steps: [
      'Select the clip and open Enhance.',
      'Running Enhance will process — let it finish.',
      'Check the preview and tap ✓.',
    ],
    tips: [
      'A very old/blurry video does not magically become HD — but improvement definitely comes.',
      'Long videos take more time.',
    ],
  ),
  've.stabilizer': ToolGuideEntry(
    title: 'Stabilizer',
    what: 'Smooths a video made shaky by hand movement — the jerks reduce.',
    steps: [
      'Open Stabilizer and pick a level (Low, Standard or Most Stable).',
      'The clips are stabilized RIGHT AWAY, one by one, with progress — this is the bake.',
      'Export afterwards is assembly only: no stabilization is processed at export time, so exports stay fast.',
    ],
    tips: [
      'In Stabilize the edges get slightly cut — that is part of the process.',
      'A very shaky video does not become fully smooth.',
      'A clip added after baking is not baked yet — the panel shows it and offers Bake now; an unbaked clip exports without stabilization and the export says so.',
    ],
  ),
  've.cutout': ToolGuideEntry(
    title: 'Cutout / Chroma',
    what:
        'Removes the video background — with a green screen (chroma) or AI cutout '
        'the person is separated.',
    steps: [
      'Select the clip and open Cutout.',
      'If there is a green/single-colour screen, choose the chroma colour; otherwise run AI cutout.',
      'If the edges look right, tap ✓.',
    ],
    tips: [
      'If the background and clothing colours are the same, the cutout can cut in from there.',
      'AI cutout runs on coins; the price is shown first.',
    ],
  ),
  've.mask': ToolGuideEntry(
    title: 'Mask',
    what:
        'Hides/shows a part of the clip or PIP — in round, square or '
        'soft-edged shapes.',
    steps: [
      'Select the item and open Mask.',
      'Choose the mask shape and set the size/place.',
      'Soften the edges with Feather, tap ✓.',
    ],
    tips: [
      'Inverting the mask makes the hidden part show and the visible part hide.',
    ],
  ),
  've.opacity': ToolGuideEntry(
    title: 'Opacity',
    what: 'Sets how transparent the selected item should be.',
    steps: [
      'Select the item.',
      'Lower the slider and the item starts blending into the video behind it.',
      'tap ✓.',
    ],
    tips: [
      'For a light watermark-like glimpse, 30–40% opacity works well.',
    ],
  ),
  've.rotate': ToolGuideEntry(
    title: 'Rotate / Flip',
    what: 'Rotates the clip (in 90° steps) or flips it.',
    steps: [
      'Select the clip and open Rotate.',
      'Rotate with Rotate, mirror with Flip.',
      'tap ✓.',
    ],
    tips: [
      'A video recorded on the wrong side (portrait/landscape) is straightened right here.',
    ],
  ),
  've.ease': ToolGuideEntry(
    title: 'Ease',
    what:
        'Makes the animation movement smooth — slow at the start/end '
        'or fast (ease in/out).',
    steps: [
      'Select the item that has keyframe animation.',
      'Choose the ease shape — the style of movement will change.',
      'Play the preview and check, then tap ✓.',
    ],
    tips: [
      'Ease takes effect only when keyframes are applied — first create the animation from the Keyframes tab.',
    ],
  ),
  've.transitions': ToolGuideEntry(
    title: 'Transitions',
    what: 'Applies the join (transition) between two clips — fade, slide, etc.',
    steps: [
      'Tap the join (edge) of two clips on the timeline.',
      'Choose a transition and set its duration.',
      'Check the join in the preview and tap ✓.',
    ],
    tips: [
      'A transition applies only at the join of clips — not in the middle of a clip.',
      'More transitions can be found in the Store.',
    ],
  ),
  've.templates': ToolGuideEntry(
    title: 'Templates (Store)',
    what: 'Opens the Templates section of the Online Store — ready designs that apply with one tap.',
    steps: [
      'Tap Templates — the Store will open.',
      'Choose a design, see the preview, then download/apply.',
      'Some templates are available for coins — the price is written there.',
    ],
    tips: [
      'Internet is required for download; once a template has arrived, it also works offline.',
    ],
  ),
};

// ---------------------------------------------------------------------
// Photo Editor — toolbar keys (photo_editor_screen.dart _toolbar).
// ---------------------------------------------------------------------
const Map<String, ToolGuideEntry> _peGuides = {
  'pe.canvas': ToolGuideEntry(
    title: 'Canvas',
    what: 'Changes the photo size/ratio and sets the background of the empty space around it.',
    steps: [
      'Choose a ratio (1:1, 4:5, 9:16, etc.) — the photo will come into that frame.',
      'For the empty space, choose a colour or blur background.',
      'Tap ✓ (Confirm).',
    ],
    tips: [
      '1:1 is common for DP/profile, 9:16 for stories.',
    ],
  ),
  'pe.filter': ToolGuideEntry(
    title: 'Filter',
    what: 'Applies a ready colour look (filter) to the photo with one tap.',
    steps: [
      'Choose a filter — the effect shows in the preview immediately.',
      'Adjust the filter amount with the slider.',
      'tap ✓.',
    ],
    tips: [
      'Hold-to-compare (hold the chip above) shows the before state.',
    ],
  ),
  'pe.adjust': ToolGuideEntry(
    title: 'Adjust',
    what:
        'Fixes the photo\'s light and colour with fine settings — '
        'brightness, contrast, saturation, HSL waghera.',
    steps: [
      'Move the slider of the setting you want to change.',
      'In HSL you can fix one colour separately.',
      'Check the preview and tap ✓ — what showed in the preview is what will be saved.',
    ],
    tips: [
      'Change little by little — too much adjusting makes the photo unnatural.',
    ],
  ),
  'pe.effect': ToolGuideEntry(
    title: 'Effect',
    what: 'Applies special visual effects to the photo.',
    steps: [
      'Choose an effect — it will show in the preview.',
      'The effect is confirmed only when you tap Apply.',
    ],
    tips: [
      'Closing the panel removes an unapplied effect — if you like it, Apply first.',
    ],
  ),
  'pe.background': ToolGuideEntry(
    title: 'Background',
    what: 'Replaces the photo\'s background with a new background.',
    steps: [
      'Choose the background type (colour, blurred, or another picture).',
      'Check the edges — the subject should look cleanly cut.',
      'tap ✓.',
    ],
    tips: [
      'For changing the background, the Cutout must be clean first — check the edges all around.',
    ],
  ),
  'pe.portrait': ToolGuideEntry(
    title: 'Portrait',
    what: 'Special improvement for faces and portraits — smooth skin, clear face.',
    steps: [
      'Open Portrait — the face is detected automatically.',
      'Set the amount with the sliders.',
      'tap ✓.',
    ],
    tips: [
      'Too much smoothing can make the face look like plastic — keep the amount light.',
    ],
  ),
  'pe.sticker': ToolGuideEntry(
    title: 'Sticker',
    what: 'Applies a sticker to the photo — place, size and rotation can be set.',
    steps: [
      'Choose a sticker — it will appear on the photo.',
      'Drag with a finger to place; set the size with two fingers.',
      'tap ✓.',
    ],
    tips: [
      'A sticker can be removed by selecting it and using the delete mark.',
    ],
  ),
  'pe.text': ToolGuideEntry(
    title: 'Text',
    what: 'Applies text to the photo — font, colour and style can all be changed.',
    steps: [
      'Write your text.',
      'Set the look from the Style/Colour/Font tabs.',
      'Drag the text box into place; change the box width with the edge dots.',
      'tap ✓.',
    ],
    tips: [
      'For Urdu text, choose the Nastaliq font — it will look right and beautiful.',
    ],
  ),
  'pe.pip': ToolGuideEntry(
    title: 'PIP',
    what: 'Places another small photo on top of the photo (picture in picture).',
    steps: [
      'Choose the second photo with PIP.',
      'Set the place and size; the edges can be round too.',
      'tap ✓.',
    ],
    tips: [
      'Give the PIP photo a light border and it stands out clearly.',
    ],
  ),
  'pe.remove': ToolGuideEntry(
    title: 'Remove',
    what: 'Erases an unwanted thing or person from the photo — the space behind fills itself.',
    steps: [
      'Open Remove — paint with the brush over the thing you want to remove.',
      'Set the brush size, then run Remove/Apply.',
      'Check the result, then tap ✓.',
    ],
    tips: [
      'A big thing does not clean in one go — repeat two or three times.',
      'If paint lands in the wrong place, you can erase the mask with the eraser.',
    ],
  ),
  'pe.enhance': ToolGuideEntry(
    title: 'Enhance',
    what: 'Automatically improves the photo quality — cleanliness, light and sharpness.',
    steps: [
      'Open Enhance and run it.',
      'Compare before/after and see.',
      'If you like it, tap ✓.',
    ],
    tips: [
      'This AI tool runs on coins — the price is shown first.',
    ],
  ),
  'pe.cutout': ToolGuideEntry(
    title: 'Cutout',
    what: 'Cuts the photo subject out from the background — the back becomes transparent.',
    steps: [
      'Run Cutout — the subject is detected automatically.',
      'The AI runs in the background with progress — the app stays responsive while it works.',
      'Look at the edges carefully (hair, edge parts).',
      'Tap ✓ — now you can place it on any background.',
    ],
    tips: [
      'If the subject and background colours are the same, the edges can cut weakly.',
      'This AI tool runs on coins.',
    ],
  ),
  'pe.doodle': ToolGuideEntry(
    title: 'Doodle',
    what: 'Drawing/lines with your finger on the photo — for marking or fun.',
    steps: [
      'Choose the colour and brush size.',
      'Draw on the photo with your finger.',
      'tap ✓.',
    ],
    tips: [
      'The last stroke comes back with Undo.',
    ],
  ),
  'pe.makeup': ToolGuideEntry(
    title: 'Makeup',
    what: 'Makeup effects on a portrait — lipstick, blush, etc.',
    steps: [
      'Open Makeup on a photo with a face.',
      'Choose the effect you want and set the amount.',
      'tap ✓.',
    ],
    tips: [
      'The face should be clearly visible, otherwise the makeup does not land in the right place.',
    ],
  ),
  'pe.crop': ToolGuideEntry(
    title: 'Crop',
    what: 'Cuts the photo edges and keeps only the wanted part.',
    steps: [
      'Drag the frame edges to choose the part you want.',
      'You can also choose a ready ratio.',
      'tap ✓.',
    ],
    tips: [
      'After cropping the photo becomes smaller — too much cropping drops the quality.',
    ],
  ),
  'pe.expand': ToolGuideEntry(
    title: 'Expand',
    what: 'Enlarges the photo canvas — the edges expand.',
    steps: [
      'Open Expand and set how much to expand.',
      'Choose the background for the new edges.',
      'tap ✓.',
    ],
    tips: [
      'Expand does not enlarge the photo; it adds space around it.',
    ],
  ),
  'pe.frame': ToolGuideEntry(
    title: 'Frame',
    what: 'Applies a frame/border around the photo.',
    steps: [
      'Choose the frame design.',
      'Set the colour and thickness.',
      'tap ✓.',
    ],
    tips: [
      'A light border often looks more professional.',
    ],
  ),
  'pe.rotate': ToolGuideEntry(
    title: 'Rotate',
    what: 'Rotates the photo or flips it.',
    steps: [
      'Rotate 90° with Rotate, or straighten a slight tilt with the slider.',
      'Flip to mirror it.',
      'tap ✓.',
    ],
    tips: [
      'A slightly tilted photo straightens with a small angle on the slider.',
    ],
  ),
};

// ---------------------------------------------------------------------
// News Studio — dock keys (news_maker_screen.dart _toolDefs).
// 'ns.motion' aur 'motion' aik hi entry share karte hain — Motion
// Gallery ka guide.
// ---------------------------------------------------------------------
const ToolGuideEntry _motionGuide = ToolGuideEntry(
  title: 'Motion Graphics Studio',
  what:
      'A gallery of ready animated designs — headlines, name '
      'strips (lower thirds), counters, etc. that move by themselves.',
  steps: [
    'Choose a design in the Gallery — a live glimpse runs on every card.',
    'Find your kind of design by category or search.',
    'SMART MATCH: type what you want in the search — English, Roman Urdu or Urdu script — and the best-matching designs come first with a "Matched:" line showing why. This is template-based help, not generative AI; if nothing matches, the Gallery honestly suggests categories instead of inventing a result.',
    'Tap the heart on any card to favourite it — Favourites and Recently Used get their own chips in the category rail.',
    'CREATE YOUR OWN: tap the + button in the Gallery to start from a blank canvas — add Text, Shape, Logo/Image, Counter, Ticker and Chart layers, then SAVE it into My Templates.',
    'Tap a design — the big preview will open.',
    'The FREE one opens instantly; PRO/COINS ones unlock first (the price is written there).',
    'In the preview, tap "Edit" — the Editor will open: choose a layer, change text/font/colour, place, size, timing and animation style.',
    'In the Editor you can also tap a layer directly on the preview — it is selected and brought to the front — and pinch with two fingers to resize it.',
    'If you want to place your logo, choose the Logo/Image layer and pick a photo — it will be saved with the template.',
    'KEYFRAMES: in the Editor, the KEYFRAMES section animates a layer between points — choose a property (Opacity, Scale, Position X/Y, Rotation), move the playhead, tap "Add keyframe at …", then set that point\'s value and easing. Add more points for multi-step motion; the preview shows exactly what will export.',
    'UNDO / REDO / RESET: the Editor top bar undoes and redoes every change; Reset brings back the design exactly as you opened it.',
    'Tapping SAVE saves the design in "My Templates" — it reopens from the My Templates category of the Gallery.',
    'Tap "Place on Video" — the design becomes a video and is placed as a PIP overlay in the Video Editor; then place it on your video and export.',
    'In the Video Editor, the overlay is the PIP layer: set its place/size in the PIP panel, and its timing in "PIP timing" (Start/End) or by dragging its segment on the timeline PIP lane — it then shows only inside that window, in the preview and the export alike.',
  ],
  tips: [
    'When placing, a transparent (WebM) video is made first; if the phone cannot encode it, an MP4 is made and the screen clearly states which one was made.',
    'PRO designs are included for Pro users — no coins needed.',
    'A design you create yourself is always free — keyframes included.',
    'There is one PIP layer: a new "Place on Video" replaces the previous inset, it does not stack a second one.',
  ],
);

const Map<String, ToolGuideEntry> _nsGuides = {
  'motion': _motionGuide,
  'ns.motion': _motionGuide,
  'ns.template': ToolGuideEntry(
    title: 'Template',
    what:
        'Choosing the design (template) of the whole news — ribbons, strips '
        'and the look all change together.',
    steps: [
      'See the design cards in the rail and tap the one you like.',
      'If it is a breaking template, you can also choose its variant.',
      'From the section below, set things like the banner, lower third and PIP.',
      'Every change shows in the preview immediately and saves by itself.',
    ],
    tips: [
      'Changing the template does not remove your written news/ticker — only the design changes.',
    ],
  ),
  'ns.media': ToolGuideEntry(
    title: 'Media (Clips)',
    what:
        'The news video clips go here — adding, reordering, '
        'removing, and now Trim/Split too.',
    steps: [
      'Choose clips from the gallery with Add — they will be placed in the line (lane) below.',
      'Press a clip to select it; move it forward/back to reorder.',
      'Trim: cut the unwanted part with the sliders at the clip\'s start/end.',
      'Split: wherever the playhead is, the clip divides right there.',
      'Remove the clip you do not want with Remove.',
    ],
    tips: [
      'The export always takes only the part inside the trim — the full original file stays safe.',
      'Tapping a clip opens the Media panel — that is where its settings live.',
      'At the top-right corner of the preview there is a grid button — it shows the safe-area guides (thirds + safe-area marks) so the headline/ticker does not hit the edges. These are for the preview only; they never appear in the export.',
      'The timeline is now on a real time-scale: clips take space according to their length, and there is a ruler (scale) on top. Zoom with the header − / fit / +; when zoomed, drag the lanes left/right to scroll.',
      'Tapping or dragging on the ruler moves the playhead there (scrub). If it is inside the first clip, the preview also shows from there; on later clips the playhead/readout goes there but the preview still shows the first clip — the actual video plays fully in the export.',
      'Split now lands at the playhead\'s actual position — scrub the playhead onto any clip and tap Split; that clip will be cut right there.',
      'Drag a clip to trim (B3): select the clip on the timeline — gold handles appear on both its edges; grab an edge and drag it in/out, the trim changes right there.',
      'Each clip block on the V1 lane is a filmstrip of frames from across the clip, so a long clip shows what is inside it. The A1 lane shows the voiceover\'s waveform and the A2 lane the music\'s — cut where the waveform goes quiet.',
      'Drag to reorder a clip (B4): press and hold the clip (long press), then drag left/right — the clip changes its place, and the trim goes with it.',
      'Marker (B9): mark the playhead spot with the header bookmark button; the marker shows as a gold line on every lane. Tapping again at the same spot or tapping the marker removes it.',
      'Lane controls (B10): the eye button next to each lane\'s name hides/shows the lane (view only). The sound button next to A2 turns the music off/on — if off, the music will not be in the export either.',
    ],
  ),
  'ns.elements': ToolGuideEntry(
    title: 'Elements',
    what:
        'Setting the place and size of the template parts (logo, ribbons, capsule, etc.) '
        'in fine detail.',
    steps: [
      'Choose the part you want to set.',
      'Change its place (up/down, right/left) and size with the sliders.',
      'The effect will show live in the big preview.',
      'You can also work directly on the preview: tap any part (headline, ticker, ribbon, logo, media) to open its own tool, drag it to move it, and pinch with two fingers to resize it.',
    ],
    tips: [
      'If you want to hide a part, turn its switch off — no need to delete it.',
      'If something goes wrong, you can reset the element and bring it back to its original place.',
      'The gold frame around a part only shows while Elements is open or while you are dragging — the normal preview stays clean.',
      'The media always stays the back layer: the logo and ticker can never be covered by it, in the preview or in the export.',
    ],
  ),
  'ns.tehreer': ToolGuideEntry(
    title: 'Tehreer (Headline)',
    what: 'Writing the news\'s big headline and setting its style.',
    steps: [
      'Write your headline in the headline box.',
      'Choose a font — for Urdu, Nastaliq looks best.',
      'Set the colour and size; it will show in the preview immediately.',
    ],
    tips: [
      'Keep the headline short and clear — long text gets tight in the ribbon.',
      'While writing, the whole screen does not rebuild — keep writing comfortably.',
    ],
  ),
  'ns.ticker': ToolGuideEntry(
    title: 'Ticker',
    what:
        'The text of the running strip (ticker) below — the news items that run in a line '
        'run in a line.',
    steps: [
      'Write the ticker text — join each news item with a separate line/symbol.',
      'Choose the direction: for Urdu, right-to-left is usually right.',
      'Set the speed and font — it will run the same in the preview and the export.',
    ],
    tips: [
      'If the direction is wrong, the ticker will run the wrong way — check it in the preview before export.',
      'A very long ticker takes time to read to the end — keep it short.',
    ],
  ),
  'ns.ribbons': ToolGuideEntry(
    title: 'Ribbons',
    what:
        'The channel\'s three ribbons (top yellow, middle red, bottom '
        'deep) — their text, colour, size and on/off are set from here.',
    steps: [
      'Choose the ribbon you want to set.',
      'Set its text, colour and height.',
      'Turn off the switch of the ribbon you do not want.',
    ],
    tips: [
      'These are the channel (preset) settings — they apply automatically to new projects.',
      'Each story\'s own ticker text is in the Ticker panel; here is only the design.',
    ],
  ),
  'ns.logo': ToolGuideEntry(
    title: 'Logo (Cube + Parts)',
    what:
        'Places the channel logo — the picture itself becomes a rotating 3D cube, '
        'or by breaking the logo into its own parts (elements), each '
        'part can be rotated separately: each part is a box + the design inside it '
        'design (like the NEWS box, the HD box), and each part at its own '
        'centre (pivot — default is the box\'s centre), at its own delay.',
    steps: [
      'Choose the logo picture (or video) — the video\'s background is removed automatically.',
      'For the cube: set the rotation speed, direction and tilt; if you want, give a different picture on each face.',
      'For Logo Parts, use the buttons below in order: Logo → Parts → Rotate → Timing → Glow → Save.',
      'In the Parts tab, tap "Suggest parts automatically" — the app will suggest boxes for the logo\'s elements. The suggestion is only a start: drag the box to move it, drag its corner to fix the size, or draw a box yourself with "Create new box" to make a part.',
      'On a solid-background logo, the suggestion first keys (cleans) the background — its strength is set by the "Keying strength" slider in the Logo tab: keep it light and the elements\' edges stay safe; increase it and colours close to the background are also removed. Change the slider and suggest again; the effect comes then.',
      'Tap a part on the big preview above to choose it — that part will highlight in gold, and the rotation will apply to it.',
      'The tools to fix the chosen part are in the Parts tab: with "Only this part (Isolate)" view the part alone and check the box caught the right thing; with "Merge" join the neighbouring box into one element; with "Split" cut the box into two parts; with "Rename" give the part a name; with "Delete part" remove the part — the original logo is untouched. "Clear all (Reset)" clears all the boxes.',
      'In the Rotate tab, set the chosen part\'s Rotate switch, Direction, Speed and style: Flat (like a wheel) or 3D (spinning from the side like a coin) — on round parts (like a globe), rotation shows clearly with 3D.',
      'The style is also in the Rotate tab: in "Full spin" the part rotates a full turn; in "Swing" it swings forward/back like a clock pendulum — set how many degrees it swings with the angle slider. In swing, the speed is the duration of one full swing.',
      'Pulse is also in the Rotate tab: turn it on and the part keeps gently growing/shrinking like breathing — increase/decrease with the strength slider. Pulse is separate from rotation: even with Rotate off, the part keeps breathing.',
      'The centre of rotation (Pivot) is also in the Rotate tab: drag the gold dot and place it wherever you want — the part will rotate around that point. With "Back to centre" the centre returns to the box\'s centre.',
      'To apply one part\'s full movement to another part, at the end of the Rotate tab there is "Settings copy": on the first part tap "Copy this part\'s settings", then choose the second part and tap "Apply the copied settings here". Rotation, style, speed, style-mode, pulse, easing, delay and pivot are copied — the box and name stay each part\'s own.',
      'In the Timing tab, set each part\'s start delay — with "Apply sequence" the parts start rotating one after another with a 0.2 second gap; with "All together (Sync)" all delays become zero. The delay is counted inside the 12-second loop, so the loop never breaks.',
      'Easing is also in the Timing tab with every part: on "Soft", Swing and Pulse run like a smooth sine (slow at the edges); on "Even", at a uniform speed. A full spin always rotates at a uniform speed — easing applies only to swinging movements (Swing/Pulse). If the glow\'s movement is Pulse, its easing is also available separately at the top of the Timing tab.',
      'In the Glow tab, a glowing layer is placed behind the logo (this layer is created, not cut from the picture): turn Glow on, choose a colour — on "Auto" the glow is made from the logo\'s own colour, or you can give your own colour — then set Intensity (how strong the glow is) and Spread (how far it reaches). For movement choose Fixed, Pulse (the glow breathes) or Slowly rotating. Glow applies only to a logo with parts.',
      'The bottom plate (Base) is also in the Glow tab: in "Cut-out base" (default), when a rotating part lifts, the video behind shows through its place; in "No base" only the parts remain; in "Full logo below" (ghost) the original logo stays fixed below and the parts rotate on top of it — this gives a double effect.',
      'The preview background is also in the Glow tab — Checker, Green or Black. It is only for viewing the preview; it has no effect on the export. On Checker, the logo\'s empty areas show clearly.',
      'The light wave (Light Sweep) is also in the Glow tab: turn it on and a wave of shine keeps passing over the whole logo — just like TV channel idents. The wave shines only inside the logo\'s shape; increase/decrease its speed with the slider.',
      'In the Parts tab list, change the layer order with the arrows (up/down) — the first part stays at the very back, the last at the very top.',
      'If you want to keep the parts settings, save from the Save tab — it stays for 7 days for 300 coins.',
      'The Save tab also has the Export size: the green-screen (Permanent Logo) export frames are made at 512 (Light — fast, light) or 1024 (Clear — clearer, a bit heavy). The default is 512.',
    ],
    tips: [
      'If the rotation does not show, first check that part\'s Rotate switch — it should be ON.',
      'A round part\'s Flat rotation shows less — try the 3D style or the 2-second speed on it.',
      'If the suggestion gives a wrong box, do not worry — moving/sizing the box is the real method; a 100% correct suggestion from a flat picture is not possible every time.',
      'If you do not save the settings, they are only for this session — they end when the app closes.',
    ],
  ),
  'ns.logo_maker': ToolGuideEntry(
    title: 'Logo Maker',
    what:
        'A full-screen maker for the channel logo: it gives a flat logo '
        'a 3D look — thickness (depth), an edge (bevel), materials like '
        'gold and chrome, a shadow and a glow — with a big live preview '
        'that moves as you work. You can also make a brand-new logo '
        'from text or from a shape here.',
    steps: [
      'Open it from the Logo tool in News Studio — tap "Open Logo Maker" at the top of the panel. The logo you see is the channel logo from that tool.',
      'In the Logo tab, the current logo is shown. Tap "Create from Text" to type a name, pick one of the 8 text styles and a size, then tap "Use This Logo" — it becomes the channel logo right away. Tap "Pick a Shape / Badge" to choose one of the 12 shapes and a colour scheme, then "Use This Shape" — that becomes the channel logo too.',
      'In the Style tab, tap a preset (Gold Spin, Chrome Flip, Neon Pulse and more) to apply a full ready-made look in one tap. Below it, set the Material (gold, chrome, silver, neon, glass, fire, ocean, sunset, mono or none), the Depth (thickness), Bevel (edge light), Shadow Blur, and the Shadow and Glow switches with the Glow Intensity slider.',
      'In the Spin tab, turn the flat spin on or off and set its speed. The preview above always shows the current settings moving.',
      'In the Light tab, give the logo studio lighting and a camera angle: tap a ready preset (Studio Soft, Dramatic Side, Top Light, Neon Rim, Stage Tilt) or set your own — the Lighting switch, the light\'s angle, intensity, shadow depth and rim glow, plus the camera\'s tilt, zoom and rotation. The preview above shows the light falling on the styled logo at once, and the news export renders it the same way. Leaving everything at its default (No Light) keeps the export exactly as before.',
      'In the Reveal tab, pick one of the 6 reveal styles (Fade Zoom, Slide Wipe, Shine Sweep, Bounce In, Spin Reveal, Rise & Glow) — or None — and a backdrop scene (Midnight Studio, Royal Stage, Neon Grid, Soft Spotlight, Deep Ocean, Plain Dark) with its Backdrop Glow slider. The preview above then shows the backdrop with the styled logo revealing over it: tap Play to run it again, or drag the scrub slider to hold it at any point. Choosing a style plays it at once, at that style\'s own speed. When a style is chosen here, the news video export also opens with this reveal over its backdrop — a one-time intro at the very start; the intro itself is silent and the news sound begins right after it, uncut.',
      'Tap Save (top right, or open the Save tab in the dock and tap "Save logo") to keep the settings. They are saved with the channel preset, so they are still there when you come back — and the back arrow returns you to News Studio with the logo in place.',
      'In the Save tab, tap "Export Logo Clip" to make a standalone video of this logo: pick the length (3, 5 or 8 seconds), the shape (widescreen, square or portrait), the reveal, the backdrop and the spin, watch it play, then tap "Export MP4" and share the file wherever you need it.',
    ],
    tips: [
      'The 3D Cube and the Parts (elements) controls are not in this maker — they stay in the News Studio Logo tool, exactly as before. Nothing was removed.',
      'The reveal and backdrop open the NEWS video export as a one-time intro segment whenever a reveal style is chosen and these settings are saved (the intro carries no sound of its own — the news audio starts right after it, whole). The export then uses the maker\'s styled logo (with its spin, as described below) in its usual place, exactly as before. The Logo Clip export still makes a standalone MP4 of the styled logo over its backdrop, the reveal playing first and the spin after it. Choosing None as the reveal style turns the intro off.',
      'Export: when these settings differ from the maker\'s defaults, the video export uses this maker\'s styled logo — depth, material, bevel, shadow and glow, plus the lighting and camera look from the Light tab, spinning flat at the speed set here, or held as a styled still when the spin is off — in the logo\'s usual place, instead of the cube/parts/default logo for that export. Settings left at the defaults keep the standard export logo, exactly as before.',
      'One honest limit: at the slowest spin speeds the export loop is capped at 20 seconds, so there the exported spin can turn a little faster than this preview shows.',
      'A very high Depth on a weak phone can make the preview heavy — the maker now renders the still look once and only spins that picture, so normal use stays smooth.',
    ],
  ),
  'ns.reporter': ToolGuideEntry(
    title: 'Reporter',
    what:
        'Places the reporter\'s name strap and photo; '
        'Recording by reading the script from the Teleprompter also happens from here.',
    steps: [
      'Write the reporter\'s name and attach a photo.',
      'Choose the strap style — it will show in the preview.',
      'Background Remove / Replace runs in the background with progress in the status line — the app stays responsive while it works.',
      'If speaking is difficult, open the Teleprompter: the script will run in front of you, read and record — the recording joins the clips by itself.',
    ],
    tips: [
      'The confirmation message after recording comes only when it has actually joined the clips.',
      'The background model downloads once during the one-time Preparing your tools setup; if it is ever missing, the tool says so honestly instead of hanging.',
    ],
  ),
  'ns.audio': ToolGuideEntry(
    title: 'Audio',
    what:
        'The news voice settings — background music, sounds taken from the Store '
        'sounds, and volume.',
    steps: [
      'Choose background music (your file or the Store\'s Music).',
      'Keep the music volume lower than the voice so the news is heard clearly.',
      'The volume of the clip\'s own sound is also set from here.',
    ],
    tips: [
      'If the music is loud the voice gets drowned — keep the music at 15–25%.',
    ],
  ),
  'ns.voice': ToolGuideEntry(
    title: 'Voice (Voiceover)',
    what:
        'Speaking over the news: record your voice, or write the script and '
        'create an AI voice.',
    steps: [
      'Your own voice: tap record, read the news, stop.',
      'AI voice: write the script and create the voice — the created voice stays saved (cached), creating it again costs no coins.',
      'The background music switch is right here — keep it on if you want music under the voice.',
      'Listen and check, then export.',
    ],
    tips: [
      'Choose a quiet place before recording — noise comes clearly in the voice.',
      'The AI voice price (coins) is written on the button.',
    ],
  ),
  'ns.captions': ToolGuideEntry(
    title: 'Captions',
    what:
        'Captions (subtitles) that run with the speech on the video — choose the style '
        'choose; the captions also show in the preview.',
    steps: [
      'Turn captions on and choose the style.',
      'Set the font, size and place.',
      'Play the preview and check whether the captions come at the right time.',
      'In the export, the captions will come burned onto the video.',
    ],
    tips: [
      'Captions with real timings are created from the voice automatically — a long video can take time.',
      'Keep the caption colour different from the background, otherwise it will not be readable.',
    ],
  ),
  'ns.export': ToolGuideEntry(
    title: 'Export',
    what: 'Turns the finished news into a video file — choose the quality and export.',
    steps: [
      'Choose the quality: 720p is free; 1080p/2K show ads (not for Pro).',
      'Tap Export — ads will come first, then the export will start.',
      'Let the progress finish — do not close the app during the export.',
      'The created video is saved in the gallery.',
    ],
    tips: [
      'If the export feels stuck at 50–60%, wait a little — the heavy part is running; an app close is now reported.',
      'On a weak phone, 720p stays the smoothest.',
    ],
  ),
};
