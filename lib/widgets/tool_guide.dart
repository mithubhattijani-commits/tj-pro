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

  /// 'Agar masla aye to' — aam ghaltiyan aur un ka hal.
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
                    tooltip: 'Band karein',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const _GuideHeading('Ye tool kya karta hai'),
              Text(
                entry.what,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: Color(0xFFD8DBE0),
                ),
              ),
              const SizedBox(height: 14),
              const _GuideHeading('Kaise istemal karein — step by step'),
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
                const _GuideHeading('Agar masla aye to'),
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
        'Video ka size (ratio), zoom aur peeche ka background set karta hai — '
        'jaise 9:16 Reels ke liye ya 16:9 YouTube ke liye.',
    steps: [
      'Ratio tab se video ka size chunein (9:16, 16:9, 1:1 waghera).',
      'Zoom tab mein video ko bara/chhota karke frame mein fit karein.',
      'Background tab se peeche ka rang ya dhundli (blur) tasveer lagayein.',
      'Upar ✓ dabayein — tabdeeli pakki ho jayegi.',
    ],
    tips: [
      'Video kinaron se kat raha ho to Zoom kam karke pura frame mein layein.',
      'Background sirf tab nazar ata hai jab video frame se chhota ho.',
    ],
  ),
  've.precut': ToolGuideEntry(
    title: 'Precut (Trim / Cut / Split)',
    what:
        'Clip ke ghair-zaroori hisay katne ke liye hai — Trim se kinare, '
        'Cut se darmiyan ka hissa, aur Split se clip do hison mein.',
    steps: [
      'Pehle timeline mein wo clip select karein jis par kaam karna hai.',
      'Trim: clip ke shuru/aakhir ke handle kheench kar fazool hissa hatayein.',
      'Cut: do points set karke darmiyan ka hissa nikaal dein.',
      'Split: playhead (peeli line) jis jagah ho, clip wahin se do ho jayegi.',
      'Upar ✓ dabakar panel band karein.',
    ],
    tips: [
      'Split playhead ki jagah par hota hai — pehle video chala kar ya timeline kheench kar line sahi jagah par layein.',
      'Galat kat jaye to upar wale Undo (↩) se wapas ho jata hai.',
    ],
  ),
  've.split': ToolGuideEntry(
    title: 'Split',
    what:
        'Select ki hui clip ko playhead (peeli line) wali jagah se do hison '
        'mein kaat deta hai — phir har hissa alag handle hota hai.',
    steps: [
      'Timeline mein clip select karein.',
      'Video chalayein ya timeline kheench kar peeli line katne wali jagah par layein.',
      'Split dabayein — clip wahin se do ho jayegi, screen par tasdeeq bhi ayegi.',
    ],
    tips: [
      'Line clip ke bilkul kinare par ho to split nahi hota — thora andar layein.',
      'Split ke baad dusra hissa select ho jata hai; dobara dabane se wahi aur katega.',
    ],
  ),
  've.timeline': ToolGuideEntry(
    title: 'Timeline (Precision)',
    what:
        'Timeline ab bilkul bareek kaam ke liye tayyar hai — zoom, '
        'timecode, frame-by-frame harkat, snap, multi-select aur range.',
    steps: [
      'Zoom: do unglion se pinch karein, ya −/+ dabayein. Fit wale button (dayein taraf) se poori video aik nazar mein ajati hai.',
      'Timecode: TC chip dabane se waqt H:MM:SS:FF mein nazar aye ga; play ke sath wale ‹ › buttons se aik frame aage/peechay jayein.',
      'Snap: anchor wala chip snap on/off karta hai; chip ko daba kar rakhein (long press) to taqat badalti hai — Halki, Normal, Mazboot. Mukammal setting Trim panel ke Timeline hisay mein hai.',
      'Multi-select: checklist wala chip on karke kai clips chunein — phir aik sath delete, duplicate ya aage/peechay karein.',
      'Range: Trim panel ke Range hisay se playhead par In/Out lagayein — gold band ban jayega; phir range loop chalana ya range delete karna aik tap hai.',
    ],
    tips: [
      'Snap band ho to playhead/trim bilkul free hote hain — koi point unhen kheenchta nahi.',
      'Range delete mein jo clip aadha range mein aye wo wahin kat jata hai — kuch ghayab nahi hota.',
    ],
  ),
  've.trim': ToolGuideEntry(
    title: 'Trim / Roll / Slip',
    what:
        'Clip ki lambai aur andar ka hissa theek karna. Teen modes '
        'hain: Trim (kinare katna), Roll (do clips ki boundary), '
        'Slip (andar ka hissa sarkana).',
    steps: [
      'Mode chunein: Trim, Roll ya Slip — timeline ke handle bhi usi mode mein kaam karte hain.',
      'Trim: sliders se start/end set karein, ya playhead clip ke andar rakh kar "Start → playhead" / "End → playhead" dabayein.',
      'Roll: boundary hile gi — aik clip lamba, dusra chhota, kul lambai waisi ki waisi. Timeline par handle ghaseetein ya 1-frame buttons dabayein.',
      'Slip: clip apni jagah rehta hai, andar ka hissa aage/peechay sarakta hai. Timeline par clip ko left/right ghaseetein ya 0.1s buttons dabayein.',
      'Range (In/Out), Snap aur Timecode ki settings bhi isi panel mein neeche hain.',
    ],
    tips: [
      'Photo clip slip nahi hota — us ke andar sarkane wala hissa hota hi nahi.',
      'Roll sirf do clips ke darmiyan hota hai — pehli clip ke start ya aakhri ke end par roll nahi lagta.',
    ],
  ),
  've.delete': ToolGuideEntry(
    title: 'Delete',
    what: 'Select ki hui clip ko timeline se hata deta hai.',
    steps: [
      'Timeline mein wo clip select karein jo hatani hai.',
      'Delete dabayein — clip gayab ho jayegi aur baqi clips jagah par kar lengi.',
    ],
    tips: [
      'Ghalti se delete ho jaye to Undo (↩) se clip wapas a jati hai.',
    ],
  ),
  've.duplicate': ToolGuideEntry(
    title: 'Duplicate',
    what: 'Select ki hui clip ki aik aur copy usi ke sath bana deta hai.',
    steps: [
      'Clip select karein.',
      'Duplicate dabayein — copy foran us ke baad lag jayegi.',
    ],
    tips: [
      'Copy bilkul asal jaisi hoti hai — us par alag effect/speed lag sakta hai.',
    ],
  ),
  've.replace': ToolGuideEntry(
    title: 'Replace',
    what:
        'Select ki hui clip ko gallery ki dusri video se badal deta hai — '
        'jagah aur muddat (duration) wahi rehti hai.',
    steps: [
      'Clip select karein.',
      'Replace dabayein aur gallery se nayi video chunein.',
      'Nayi video purani jagah par, utni hi lambi ho kar lag jayegi.',
    ],
    tips: [
      'Nayi video chhoti ho to wo loop/short ho sakti hai — lambi video chunein to behtar.',
    ],
  ),
  've.freeze': ToolGuideEntry(
    title: 'Freeze',
    what:
        'Playhead wale frame ko rok kar (freeze) aik khari hui tasveer-clip '
        'bana deta hai jo chand second screen par rehti hai.',
    steps: [
      'Peeli line us frame par layein jise rokna hai.',
      'Freeze dabayein — wahan aik freeze clip lag jayega.',
      'Us ki lambai kinare kheench kar kam/zyada kar sakte hain.',
    ],
    tips: [
      'Kisi khaas lamhe ko zor de kar dikhane ke liye freeze behtareen hai.',
    ],
  ),
  've.capture': ToolGuideEntry(
    title: 'Capture',
    what: 'Playhead wale frame ki tasveer (photo) bana kar clip ke tor par laga deta hai.',
    steps: [
      'Peeli line matlooba frame par layein.',
      'Capture dabayein — us frame ki photo clip timeline mein lag jayegi.',
    ],
    tips: [
      'Thumbnail ya cover ke liye acha frame capture karke istemal karein.',
    ],
  ),
  've.reverse': ToolGuideEntry(
    title: 'Reverse',
    what: 'Select ki hui clip ko ulta chala deta hai — aakhir se shuru ki taraf.',
    steps: [
      'Clip select karein.',
      'Reverse dabayein — kuch dair lage gi, clip ulta chalegi.',
    ],
    tips: [
      'Reverse mein awaz bhi ulti ho jati hai — zaroorat ho to Volume se awaz band kar dein.',
      'Lambi clip par reverse mein waqt zyada lagta hai.',
    ],
  ),
  've.switch': ToolGuideEntry(
    title: 'Switch',
    what:
        'Select ki hui clip ko main video se hata kar chhoti PIP (tasveer '
        'mein tasveer) bana deta hai, ya PIP ko wapas main bana deta hai.',
    steps: [
      'Clip select karein.',
      'Switch dabayein — clip PIP ban jayegi (ya PIP wapas main clip).',
      'PIP ko ungli se kheench kar jagah aur size set karein.',
    ],
    tips: [
      'PIP ki mazeed settings Overlay ke PIP tab mein milti hain.',
    ],
  ),
  've.speed': ToolGuideEntry(
    title: 'Speed',
    what:
        'Clip ki raftaar badalta hai — slow motion ya tez. Curve se raftaar '
        'ahista ahista badalti hai, Beat se music ki taal par.',
    steps: [
      'Clip select karke Speed kholein.',
      'Standard tab mein slider se raftaar set karein (0.5× slow, 2× tez).',
      'Curve tab mein tayyar shapes chunein — raftaar naram badlegi.',
      '✓ dabayein — clip ki lambai raftaar ke hisab se badal jayegi.',
    ],
    tips: [
      'Slow motion mein awaz bhi dheemi ho jati hai — aksar Volume kam kar dete hain.',
      'Bohat tez (4× se zyada) par video jhatke wali lag sakti hai.',
    ],
  ),
  've.audio': ToolGuideEntry(
    title: 'Audio',
    what:
        'Video ki awaz ka markaz: background Music lagana, Voice Effect se '
        'awaz badalna, aur Clean se shor kam karna.',
    steps: [
      'Music tab: apni file ya Store se music lagayein, volume set karein.',
      'Voice tab: awaz par effect (voice changer) lagayein.',
      'Clean tab: recording ka shor/hiss kam karein.',
      'Har tab ki tabdeeli ✓ se pakki hoti hai.',
    ],
    tips: [
      'Music tez ho aur awaz dab jaye to music ka volume 20–30% rakhein.',
      'More audio tools mein converter, trimmer aur joiner bhi hain.',
    ],
  ),
  've.volume': ToolGuideEntry(
    title: 'Volume',
    what: 'Select ki hui clip ki awaz ka volume kam ya zyada karta hai.',
    steps: [
      'Clip select karein.',
      'Slider se volume set karein — 0 matlab awaz bilkul band.',
      '✓ dabayein.',
    ],
    tips: [
      'Background clip ki awaz band karne ke liye volume 0 kar dein.',
    ],
  ),
  've.text': ToolGuideEntry(
    title: 'Text',
    what:
        'Video par likhai lagata hai — aam Text, tayyar Motion Titles, aur '
        'bolne par khud banne wale Captions.',
    steps: [
      'Text tab: naya text likhein, font, rang aur size set karein.',
      'Text ko ungli se kheench kar sahi jagah rakhein.',
      'Titles tab: tayyar animated title chunein aur apna lafz likhein.',
      'Captions tab: video ki awaz se khud captions banayein (Urdu AI bhi hai).',
    ],
    tips: [
      'Caption banane mein thora waqt lagta hai — video lambi ho to sabr karein.',
      'Text nazar na aye to dekhein wo clip ke time ke andar hai ya nahi.',
    ],
  ),
  've.colour': ToolGuideEntry(
    title: 'Colour (Filters / Adjust)',
    what:
        'Video ke rang theek karta hai — Filters se aik tap mein look, '
        'Adjust se roshni, rang aur safai ki bareek settings.',
    steps: [
      'Filters tab: koi filter chunein aur us ki miqdar (intensity) set karein.',
      'Adjust tab: brightness, contrast, saturation waghera sliders se theek karein.',
      'Preview mein asar sath sath nazar ata hai — ✓ se pakka karein.',
      'My Looks: jo settings pasand ayen, Adjust ke neeche "Save look" se naam de kar save kar lein — agli dafa wo look aik tap se lag jayega.',
    ],
    tips: [
      'LUT, Sharpen aur Clarity ka asar sirf export ki hui video mein ata hai — preview mein nahi dikhta, ye normal hai.',
      'Hold-to-compare se pehle/bag ki halat dekh sakte hain.',
      'Saved looks sirf is phone par rehte hain; kisi look ke dustbin (delete) icon se wo hat jata hai, aur usi naam se dobara Save karne se look update ho jata hai.',
    ],
  ),
  've.effects': ToolGuideEntry(
    title: 'Effects',
    what:
        'Video par visual effects lagata hai; Tracking se effect kisi '
        'cheez ke sath chipak kar chalta hai.',
    steps: [
      'Effects tab se effect chunein — preview mein foran nazar aye ga.',
      'Tracking tab: effect ko kisi point par lagayein, wo us ke sath hile ga.',
      '✓ dabayein.',
    ],
    tips: [
      'Zyada effects video ko bhari aur slow kar sakte hain — aik do hi rakhein.',
    ],
  ),
  've.overlay': ToolGuideEntry(
    title: 'Overlay (Sticker / Keyframes / PIP)',
    what:
        'Video ke upar cheezen lagata hai — Sticker, dusri video ki chhoti '
        'jhalak (PIP), aur Keyframes se harkat wali animation.',
    steps: [
      'Sticker tab: sticker chunein, jagah aur size set karein.',
      'PIP tab: dusri video/photo upar lagayein, kinare gol ya mask bhi hota hai.',
      'Keyframes tab: kisi cheez ko waqt ke sath hilne ki harkat dein.',
      '✓ se pakka karein.',
    ],
    tips: [
      'PIP select karne par neeche element wali line ati hai — wahan se Edit/Delete asan hai.',
    ],
  ),
  've.aicut': ToolGuideEntry(
    title: 'AI Cut',
    what:
        'AI video ke khamosh aur fazool hisay khud pehchan kar katne mein '
        'madad karta hai — lambi recording chhoti karne ke liye.',
    steps: [
      'AI Cut kholein aur analysis khatam hone dein.',
      'Jo hisay rakhne hain wo check karein, baqi kat jayenge.',
      'Apply karein — naya chhota version ban jayega.',
    ],
    tips: [
      'AI ki tajweez har dafa kaamil nahi hoti — apply se pehle preview dekh lein.',
      'Ye tool coins se chalta hai; qeemat button par likhi hoti hai.',
    ],
  ),
  've.voiceenhance': ToolGuideEntry(
    title: 'Voice Enhance',
    what: 'Recording ki awaz saaf aur wazeh karta hai — shor kam, awaz ubhri hui.',
    steps: [
      'Clip select karke Voice Enhance kholein.',
      'Miqdar set karein aur preview sun kar check karein.',
      '✓ dabayein.',
    ],
    tips: [
      'Bohat zyada enhance awaz ko ghair-qudrati bana sakta hai — darmiyani miqdar behtar hai.',
    ],
  ),
  've.edit': ToolGuideEntry(
    title: 'Crop / Transform',
    what: 'Clip ko crop karna, ghumana, aur frame mein us ki jagah/size badalna.',
    steps: [
      'Kinare kheench kar crop karein — bahar wala hissa kat jayega.',
      'Scale se bara/chhota, position se jagah badlein.',
      '✓ dabayein.',
    ],
    tips: [
      'Crop ke baad khali jagah aye to Canvas ke Background se bhar sakte hain.',
    ],
  ),
  've.enhance': ToolGuideEntry(
    title: 'Enhance (HD)',
    what: 'Video ki quality behtar karta hai — safai aur sharpness barhti hai.',
    steps: [
      'Clip select karke Enhance kholein.',
      'Enhance chalane par processing hogi — khatam hone dein.',
      'Preview dekh kar ✓ dabayein.',
    ],
    tips: [
      'Bohat purani/dhundli video jadui tor par HD nahi banti — behtari zaroor ati hai.',
      'Lambi video par waqt zyada lagta hai.',
    ],
  ),
  've.stabilizer': ToolGuideEntry(
    title: 'Stabilizer',
    what: 'Hath ke hilne se bani video ko smooth karta hai — jhatke kam ho jate hain.',
    steps: [
      'Clip select karke Stabilizer kholein.',
      'Stabilize chalanein — analysis aur processing hogi.',
      'Natija dekh kar ✓ dabayein.',
    ],
    tips: [
      'Stabilize mein kinare thore kat jate hain — ye is amal ka hissa hai.',
      'Bohat zyada hili hui video poori smooth nahi hoti.',
    ],
  ),
  've.cutout': ToolGuideEntry(
    title: 'Cutout / Chroma',
    what:
        'Video ka background hatata hai — sabz parda (chroma) ya AI cutout se '
        'banda alag ho jata hai.',
    steps: [
      'Clip select karke Cutout kholein.',
      'Sabz/ek-rang parda ho to chroma rang chunein; warna AI cutout chalanein.',
      'Kinare theek nazar ayen to ✓ dabayein.',
    ],
    tips: [
      'Background aur kapron ka rang aik jaisa ho to cutout wahan se kat sakta hai.',
      'AI cutout coins se chalta hai; qeemat pehle dikh jati hai.',
    ],
  ),
  've.mask': ToolGuideEntry(
    title: 'Mask',
    what:
        'Clip ya PIP ke kisi hisay ko chhupata/dikhata hai — gol, chokor ya '
        'naram kinare wali shaklon mein.',
    steps: [
      'Cheez select karke Mask kholein.',
      'Mask ki shakal chunein aur size/jagah set karein.',
      'Feather se kinare naram karein, ✓ dabayein.',
    ],
    tips: [
      'Mask ulta (invert) karne se chhupa hua hissa dikhne lagta hai aur dikhne wala chhup jata hai.',
    ],
  ),
  've.opacity': ToolGuideEntry(
    title: 'Opacity',
    what: 'Select ki hui cheez ko kitna dhundla (transparent) karna hai — ye set karta hai.',
    steps: [
      'Cheez select karein.',
      'Slider kam karein to cheez peeche wali video mein ghulne lage gi.',
      '✓ dabayein.',
    ],
    tips: [
      'Watermark jaisi halki jhalak ke liye 30–40% opacity acha rehta hai.',
    ],
  ),
  've.rotate': ToolGuideEntry(
    title: 'Rotate / Flip',
    what: 'Clip ko ghumata hai (90° ke steps) ya ulta (flip) karta hai.',
    steps: [
      'Clip select karke Rotate kholein.',
      'Rotate se ghumayein, Flip se aaine jaisa ulta karein.',
      '✓ dabayein.',
    ],
    tips: [
      'Galat side par bani video (portrait/landscape) yahin se seedhi hoti hai.',
    ],
  ),
  've.ease': ToolGuideEntry(
    title: 'Ease',
    what:
        'Animation ki harkat ko naram karta hai — shuru/aakhir mein ahista '
        'ya tez (ease in/out).',
    steps: [
      'Jis cheez par keyframe animation hai use select karein.',
      'Ease ki shakal chunein — harkat ka andaaz badal jayega.',
      'Preview chala kar dekhein, phir ✓ dabayein.',
    ],
    tips: [
      'Ease sirf tab asar karta hai jab keyframes lage hon — pehle Keyframes tab se animation banayein.',
    ],
  ),
  've.transitions': ToolGuideEntry(
    title: 'Transitions',
    what: 'Do clips ke darmiyan ka jorna (transition) lagata hai — fade, slide waghera.',
    steps: [
      'Timeline mein do clips ke jor (kinara) par tap karein.',
      'Transition chunein aur us ki muddat set karein.',
      'Preview mein jor dekh kar ✓ dabayein.',
    ],
    tips: [
      'Transition sirf clips ke jor par lagta hai — clip ke darmiyan nahi.',
      'Store se mazeed transitions mil sakte hain.',
    ],
  ),
  've.templates': ToolGuideEntry(
    title: 'Templates (Store)',
    what: 'Online Store ka Templates hisa kholta hai — tayyar designs jo aik tap mein lagte hain.',
    steps: [
      'Templates dabayein — Store khul jayega.',
      'Design chunein, preview dekhein, phir download/apply karein.',
      'Kuch templates coins se milte hain — qeemat wahan likhi hoti hai.',
    ],
    tips: [
      'Download ke liye internet lazmi hai; aik dafa aya hua template offline bhi chalta hai.',
    ],
  ),
};

// ---------------------------------------------------------------------
// Photo Editor — toolbar keys (photo_editor_screen.dart _toolbar).
// ---------------------------------------------------------------------
const Map<String, ToolGuideEntry> _peGuides = {
  'pe.canvas': ToolGuideEntry(
    title: 'Canvas',
    what: 'Photo ka size/ratio badalta hai aur aas paas ki khali jagah ka background set karta hai.',
    steps: [
      'Ratio chunein (1:1, 4:5, 9:16 waghera) — photo us frame mein ajaye gi.',
      'Khali jagah ke liye rang ya blur background chunein.',
      '✓ (Confirm) dabayein.',
    ],
    tips: [
      'DP/profile ke liye 1:1, story ke liye 9:16 aam istemal hai.',
    ],
  ),
  'pe.filter': ToolGuideEntry(
    title: 'Filter',
    what: 'Photo par aik tap mein tayyar rang-look (filter) lagata hai.',
    steps: [
      'Filter chunein — preview mein foran asar dikhe ga.',
      'Slider se filter ki miqdar kam/zyada karein.',
      '✓ dabayein.',
    ],
    tips: [
      'Hold-to-compare (upar wala chip dabaye rakhein) se pehle ki halat dikhti hai.',
    ],
  ),
  'pe.adjust': ToolGuideEntry(
    title: 'Adjust',
    what:
        'Photo ki roshni aur rang bareek settings se theek karta hai — '
        'brightness, contrast, saturation, HSL waghera.',
    steps: [
      'Jo setting badalni hai us ka slider chalanein.',
      'HSL mein kisi aik rang ko alag se theek kar sakte hain.',
      'Preview dekh kar ✓ dabayein — wahi save hoga jo preview mein dikha.',
    ],
    tips: [
      'Thora thora badlein — zyada adjust photo ko ghair-qudrati bana deta hai.',
    ],
  ),
  'pe.effect': ToolGuideEntry(
    title: 'Effect',
    what: 'Photo par khaas visual effects lagata hai.',
    steps: [
      'Effect chunein — preview mein nazar aye ga.',
      'Apply dabayein tab hi effect pakka hota hai.',
    ],
    tips: [
      'Panel band karne se ghair-apply shuda effect khatam ho jata hai — pasand aye to pehle Apply karein.',
    ],
  ),
  'pe.background': ToolGuideEntry(
    title: 'Background',
    what: 'Photo ka peeche wala hissa naye background se badalta hai.',
    steps: [
      'Background ki qisam chunein (rang, dhundla, ya dusri tasveer).',
      'Kinare check karein — subject saaf kata hua nazar aye.',
      '✓ dabayein.',
    ],
    tips: [
      'Background badalne ke liye pehle Cutout saaf hona chahiye — kinare ghum phir kar dekhein.',
    ],
  ),
  'pe.portrait': ToolGuideEntry(
    title: 'Portrait',
    what: 'Chehre aur portrait ke liye khaas behtari — skin smooth, chehra saaf.',
    steps: [
      'Portrait kholein — chehra khud pehchana jata hai.',
      'Sliders se miqdar set karein.',
      '✓ dabayein.',
    ],
    tips: [
      'Zyada smooth karne se chehra plastic jaisa lag sakta hai — halki miqdar rakhein.',
    ],
  ),
  'pe.sticker': ToolGuideEntry(
    title: 'Sticker',
    what: 'Photo par sticker lagata hai — jagah, size aur ghumao set hota hai.',
    steps: [
      'Sticker chunein — photo par ajayega.',
      'Ungli se kheench kar jagah, do ungliyon se size set karein.',
      '✓ dabayein.',
    ],
    tips: [
      'Sticker select karke delete wale nishan se hataya ja sakta hai.',
    ],
  ),
  'pe.text': ToolGuideEntry(
    title: 'Text',
    what: 'Photo par likhai lagata hai — font, rang, style sab badal sakte hain.',
    steps: [
      'Apna text likhein.',
      'Style/Colour/Font tabs se look set karein.',
      'Text box ko kheench kar jagah par rakhein; kinare wale dots se box ki width badlein.',
      '✓ dabayein.',
    ],
    tips: [
      'Urdu text ke liye Nastaliq font chunein — sahi aur khubsurat lage ga.',
    ],
  ),
  'pe.pip': ToolGuideEntry(
    title: 'PIP',
    what: 'Photo ke upar dusri chhoti photo lagata hai (tasveer mein tasveer).',
    steps: [
      'PIP se dusri photo chunein.',
      'Jagah aur size set karein; kinare gol bhi ho sakte hain.',
      '✓ dabayein.',
    ],
    tips: [
      'PIP photo ko halki border dein to wo alag saaf nazar ati hai.',
    ],
  ),
  'pe.remove': ToolGuideEntry(
    title: 'Remove',
    what: 'Photo se ghair-zaroori cheez ya banda mita deta hai — peeche ki jagah khud bharti hai.',
    steps: [
      'Remove kholein — brush se us cheez par rang pherein jo hatani hai.',
      'Brush ka size set karein, phir Remove/Apply chalanein.',
      'Natija dekh kar ✓ dabayein.',
    ],
    tips: [
      'Barri cheez aik dafa mein saaf nahi hoti — do teen dafa dohrayen.',
      'Ghalat jagah rang jaye to eraser se mask mita sakte hain.',
    ],
  ),
  'pe.enhance': ToolGuideEntry(
    title: 'Enhance',
    what: 'Photo ki quality khud behtar karta hai — safai, roshni aur sharpness.',
    steps: [
      'Enhance kholein aur chalanein.',
      'Pehle/baad compare karke dekhein.',
      'Pasand aye to ✓ dabayein.',
    ],
    tips: [
      'Ye AI tool coins se chalta hai — qeemat pehle dikh jati hai.',
    ],
  ),
  'pe.cutout': ToolGuideEntry(
    title: 'Cutout',
    what: 'Photo ke subject ko background se alag kaat deta hai — peeche transparent ho jata hai.',
    steps: [
      'Cutout chalanein — subject khud pehchana jata hai.',
      'Kinare gaur se dekhein (baal, kinare wale hisay).',
      '✓ dabayein — ab isay kisi bhi background par laga sakte hain.',
    ],
    tips: [
      'Subject aur background ka rang aik jaisa ho to kinare kamzor kat sakte hain.',
      'Ye AI tool coins se chalta hai.',
    ],
  ),
  'pe.doodle': ToolGuideEntry(
    title: 'Doodle',
    what: 'Photo par ungli se drawing/line banana — nishan lagane ya mazaq ke liye.',
    steps: [
      'Rang aur brush size chunein.',
      'Photo par ungli se draw karein.',
      '✓ dabayein.',
    ],
    tips: [
      'Akhri stroke Undo se wapas ho jata hai.',
    ],
  ),
  'pe.makeup': ToolGuideEntry(
    title: 'Makeup',
    what: 'Portrait par makeup wale effects — lipstick, blush waghera.',
    steps: [
      'Chehre wali photo par Makeup kholein.',
      'Jo effect chahiye chunein aur miqdar set karein.',
      '✓ dabayein.',
    ],
    tips: [
      'Chehra saaf nazar ana chahiye warna makeup sahi jagah nahi lagta.',
    ],
  ),
  'pe.crop': ToolGuideEntry(
    title: 'Crop',
    what: 'Photo ke kinare kaat kar sirf matlooba hissa rakhta hai.',
    steps: [
      'Frame ke kinare kheench kar matlooba hissa chunein.',
      'Tayyar ratio bhi chun sakte hain.',
      '✓ dabayein.',
    ],
    tips: [
      'Crop ke baad photo chhoti ho jati hai — bohat zyada crop se quality girti hai.',
    ],
  ),
  'pe.expand': ToolGuideEntry(
    title: 'Expand',
    what: 'Photo ke canvas ko bara karta hai — kinare barh jate hain.',
    steps: [
      'Expand kholein aur kitna barhana hai set karein.',
      'Naye kinaron ka background chunein.',
      '✓ dabayein.',
    ],
    tips: [
      'Expand photo ko bara nahi karta, us ke aas paas jagah barhata hai.',
    ],
  ),
  'pe.frame': ToolGuideEntry(
    title: 'Frame',
    what: 'Photo ke gird frame/border lagata hai.',
    steps: [
      'Frame ka design chunein.',
      'Rang aur motai set karein.',
      '✓ dabayein.',
    ],
    tips: [
      'Halki border aksar zyada professional lagti hai.',
    ],
  ),
  'pe.rotate': ToolGuideEntry(
    title: 'Rotate',
    what: 'Photo ko ghumata hai ya ulta (flip) karta hai.',
    steps: [
      'Rotate se 90° ghumayein, ya slider se halka sa terha seedha karein.',
      'Flip se aaine wala ulta karein.',
      '✓ dabayein.',
    ],
    tips: [
      'Halki terhi photo slider ke chhote se angle se seedhi ho jati hai.',
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
      'Tayyar animated designs ki gallery hai — headlines, naam wali '
      'pattiyan (lower thirds), counters waghera jo khud harkat karte hain.',
  steps: [
    'Gallery mein design chunein — har card par us ki live jhalak chalti hai.',
    'Category ya search se apni qisam ka design dhunden.',
    'Design par tap karein — bara preview khul jayega.',
    'FREE wala foran khulta hai; PRO/COINS wale pehle unlock hote hain (qeemat wahan likhi hai).',
    'Preview mein "Edit karein" dabayein — Editor khul jayega: layer chunein, text/font/rang, jagah, size, waqt aur animation style badlein.',
    'Apna logo lagana ho to Logo/Image layer chunein aur photo chunein — template ke sath save ho jayega.',
    'SAVE dabane se design "My Templates" mein save hota hai — Gallery ki My Templates category se dobara khulta hai.',
    '"Video par Lagao" dabayein — design video ban kar Video Editor mein PIP overlay lag jayega; phir use apni video par rakh kar export karein.',
  ],
  tips: [
    'Lagao mein pehle transparent (WebM) video banta hai; agar phone par wo encode na ho to MP4 banta hai aur screen par wazeh likha ata hai ke konsa bana.',
    'Pro users ke liye PRO designs shamil hain — coins nahi lagte.',
  ],
);

const Map<String, ToolGuideEntry> _nsGuides = {
  'motion': _motionGuide,
  'ns.motion': _motionGuide,
  'ns.template': ToolGuideEntry(
    title: 'Template',
    what:
        'Poori khabar ka design (template) chunna hai — ribbons, pattiyan '
        'aur look aik sath badal jata hai.',
    steps: [
      'Rail mein design cards dekhein aur pasandida par tap karein.',
      'Breaking template ho to us ki variant bhi chun sakte hain.',
      'Neeche wale hisay se banner, lower third aur PIP jaisi cheezen set karein.',
      'Har tabdeeli preview mein foran nazar ati hai aur khud save ho jati hai.',
    ],
    tips: [
      'Template badalne se aap ki likhi khabar/ticker nahi udta — sirf design badalta hai.',
    ],
  ),
  'ns.media': ToolGuideEntry(
    title: 'Media (Clips)',
    what:
        'Khabar ki video clips yahan lagti hain — jorna, tartib badalna, '
        'hatana, aur ab Trim/Split bhi.',
    steps: [
      'Add se gallery se clips chunein — wo neeche line (lane) mein lag jayengi.',
      'Clip ko daba kar select karein; tartib ke liye aage/peeche karein.',
      'Trim: clip ke shuru/aakhir ke sliders se fazool hissa katein.',
      'Split: playhead jis jagah ho, clip wahin do ho jayegi.',
      'Jo clip nahi chahiye use Remove se hatayein.',
    ],
    tips: [
      'Export hamesha wahi hisa leta hai jo trim ke andar hai — poori asal file mehfooz rehti hai.',
      'Clip par tap karne se Media panel khulta hai — yahi is ki settings ki jagah hai.',
      'Preview ke upar dayein konay mein grid wala button hai — us se safe-area guides (thirds + mehfooz hisay ke nishan) nazar ate hain taake headline/ticker kinaron se takraye nahi. Ye sirf preview ke liye hain, export mein kabhi nahi ate.',
      'Timeline ab asal time-scale par hai: clips apni lambai ke hisab se jagah lete hain, upar ruler (scale) hai. Header ke − / fit / + se zoom karein; zoom ho to lanes ko left/right ghaseet kar scroll karein.',
      'Ruler par tap ya drag karne se playhead wahan chala jata hai (scrub). Pehli clip ke andar ho to preview bhi wahin se nazar aye ga; aage ki clips par playhead/readout wahan jata hai lekin preview pehli clip hi dikhata hai — asal video export mein poori chalti hai.',
      'Split ab playhead ki asal jagah par lagta hai — playhead ko kisi bhi clip par scrub karke Split dabayein, wahi clip wahin kategi.',
    ],
  ),
  'ns.elements': ToolGuideEntry(
    title: 'Elements',
    what:
        'Template ke hison (logo, ribbons, capsule waghera) ki jagah aur '
        'size bareek se set karna.',
    steps: [
      'Jo hissa set karna hai use chunein.',
      'Sliders se us ki jagah (upar/neeche, daen/baen) aur size badlein.',
      'Asar bare preview mein live nazar aye ga.',
    ],
    tips: [
      'Koi hissa ghayab karna ho to us ka switch band kar dein — delete karne ki zaroorat nahi.',
      'Ghalat ho jaye to element ko reset karke asal jagah wapas la sakte hain.',
    ],
  ),
  'ns.tehreer': ToolGuideEntry(
    title: 'Tehreer (Headline)',
    what: 'Khabar ki barri headline (surkhi) likhna aur us ka andaaz set karna.',
    steps: [
      'Headline wale khane mein apni surkhi likhein.',
      'Font chunein — Urdu ke liye Nastaliq sab se acha lagta hai.',
      'Rang aur size set karein; preview mein foran nazar aye ga.',
    ],
    tips: [
      'Headline chhoti aur saaf rakhein — lambi tehreer ribbon mein tang ati hai.',
      'Likhne par poori screen dobara nahi banti — aram se likhte jayein.',
    ],
  ),
  'ns.ticker': ToolGuideEntry(
    title: 'Ticker',
    what:
        'Neeche chalti hui patti (ticker) ki tehreer — jo khabrein line '
        'mein chalti hain.',
    steps: [
      'Ticker ka text likhein — har khabar ko alag line/simbol se jorein.',
      'Direction chunein: Urdu ke liye aam tor par right-to-left sahi rehta hai.',
      'Raftaar aur font set karein — preview aur export dono mein aik jaisa chalega.',
    ],
    tips: [
      'Direction ghalat ho to ticker ulti taraf chalega — export se pehle preview mein dekh lein.',
      'Bohat lamba ticker aakhir tak parhne mein waqt leta hai — mukhtasar rakhein.',
    ],
  ),
  'ns.ribbons': ToolGuideEntry(
    title: 'Ribbons',
    what:
        'Channel ki teen pattiyan (upar peeli, darmiyan surkh, neeche '
        'gehri) — un ka text, rang, size aur on/off yahan se set hota hai.',
    steps: [
      'Jo ribbon set karni hai use chunein.',
      'Us ka text, rang aur height set karein.',
      'Jo ribbon nahi chahiye us ka switch band kar dein.',
    ],
    tips: [
      'Ye channel (preset) ki settings hain — naye projects par khud lag jati hain.',
      'Har khabar ka apna ticker text Ticker panel mein hota hai, yahan sirf design hai.',
    ],
  ),
  'ns.logo': ToolGuideEntry(
    title: 'Logo (Cube + Parts)',
    what:
        'Channel ka logo lagata hai — tasveer khud ghumta hua 3D cube ban '
        'jati hai, ya logo ko us ke apne hison (elements) mein tor kar har '
        'hisa alag ghumaya ja sakta hai: har hissa aik box + us ke andar ka '
        'design hai (jaise NEWS wala box, HD wala box), aur har hissa apne '
        'markaz (pivot — default box ka centre) se, apne waqfay par ghoomta hai.',
    steps: [
      'Logo ki tasveer (ya video) chunein — video ka background khud hat jata hai.',
      'Cube ke liye: ghumao ki speed, direction aur rukh (tilt) set karein; chahein to har rukh (face) par alag tasveer dein.',
      'Logo Parts ke liye neeche ke buttons tarteeb se istemal karein: Logo → Hisay → Ghumao → Waqt → Glow → Save.',
      'Hisay tab mein "Auto Hisay tajweez" dabayein — app logo ke elements ke boxes tajweez kar de gi. Tajweez sirf shuruaat hai: box ko ghaseet kar hilayein, us ke kone ko ghaseet kar size theek karein, ya "Naya box banao" se khud box kheench kar hissa banayein.',
      'Solid background wale logo par tajweez pehle background ko key (saaf) karti hai — us ki sakhti Logo tab ke "Keying mazbooti" slider se tay hoti hai: Halka rakhein to elements ke kinare mehfooz rahte hain, zyada kar dein to background ke qareebi rang bhi hat jate hain. Slider badal kar dobara tajweez karein, asar tab ayega.',
      'Upar wale bare preview par kisi hisay ko tap karke chunein — wahi hissa gold rang mein highlight hoga, aur Ghumao usi par lage ga.',
      'Chuna hissa theek karne ke tools Hisay tab mein hain: "Sirf ye hissa (Isolate)" se hissa akela dekh kar check karein ke box ne sahi cheez pakri hai; "Merge" se sath wala box mila kar aik element banayein; "Split" se box do hison mein kaat lein; "Naam badlein" se hisay ko naam dein; "Hissa khatam" se hissa urayein — asal logo ko kuch nahi hota. "Saare saaf (Reset)" se saare boxes saaf ho jate hain.',
      'Ghumao tab mein chune huay hisay ka Rotate switch, Direction, Speed aur andaaz set karein: Flat (pahiye ki tarah) ya 3D (sikkay ki tarah side se ghumna) — gol hisay (jaise globe) par 3D se ghumao saaf nazar ata hai.',
      'Andaaz bhi Ghumao tab mein hai: "Poora chakkar" mein hissa purey chakkar ghumta hai; "Jhoolna (Swing)" mein ghari ke pendulum ki tarah aagay-peeche jhoolta hai — zawiya slider se tay karein kitne degree tak jhoolay. Speed swing mein aik purey jhoolay ki muddat hai.',
      'Pulse bhi Ghumao tab mein hai: on karein to hissa saans ki tarah halka bara-chhota hota rehta hai — taqat slider se kam/zyada karein. Pulse ghumao se alag hai: Rotate band ho tab bhi hissa saans leta rehta hai.',
      'Ghumne ka markaz (Pivot) bhi Ghumao tab mein hai: sunahra nukta ghaseet kar jahan chahein rakh lein — hissa usi nukte ke gird ghume ga. "Centre par wapas" se markaz dobara box ke centre par aa jata hai.',
      'Aik hisay ki poori harkat doosre hisay par lagani ho to Ghumao tab ke aakhir mein "Settings copy" hai: pehle hisay par "Is hisay ki settings copy karein" dabayein, phir doosra hissa chunein aur "Copy ki settings yahan lagayein" dabayein. Ghumao, style, speed, andaaz, pulse, narmi, waqfa aur pivot copy hote hain — box aur naam har hisay ka apna hi rehta hai.',
      'Waqt tab mein har hisay ka start waqfa (delay) set karein — "Sequence lagao" se hisay 0.2 second ke faslay se aik ke baad aik ghumna shuru hote hain, "Sab aik sath (Sync)" se saare waqfay zero ho jate hain. Waqfa 12 second ke loop ke andar hisaab hota hai, is liye loop kabhi nahi tootta.',
      'Narmi (Easing) bhi Waqt tab mein har hisay ke sath hai: "Narm" par Jhoolna aur Pulse narm sine ki tarah chalte hain (kinaron par aahista), "Barabar" par aik si raftaar se. Poora chakkar hamesha aik si raftaar se ghoomta hai — narmi sirf doolnay wali harkaton (Swing/Pulse) par lagti hai. Glow ki harkat Pulse ho to us ki narmi bhi Waqt tab ke upar alag se milti hai.',
      'Glow tab mein logo ke peeche chamak wali layer lagti hai (ye layer banti hai, tasveer se katti nahi): Glow on karein, rang chunein — "Auto" par logo ke apne rang ki chamak banti hai, ya apna rang bhi de sakte hain — phir Shadeed (chamak kitni tez) aur Phailao (kitni door tak) set karein. Harkat mein Sabit, Pulse (chamak saans leti hai) ya Aahista ghoomti chunein. Glow sirf hison wale logo par lagta hai.',
      'Neeche ki plate (Base) bhi Glow tab mein hai: "Kata hua base" (default) mein ghumta hissa uthe to us ki jagah se peeche ki video dikhti hai; "Koi base nahi" mein sirf hisay rehte hain; "Poora logo neeche" (ghost) mein asal logo sabit neeche rehta hai aur hisay us ke upar ghoomte hain — ye dohra asar deta hai.',
      'Preview ka pas-manzar bhi Glow tab mein hai — Checker, Green ya Kala. Ye sirf preview dekhne ke liye hai, export par is ka koi asar nahi hota; Checker par logo ki khaali jaghein saaf nazar ati hain.',
      'Roshni ki lehar (Light Sweep) bhi Glow tab mein hai: on karein to aik chamak ki lehar poore logo ke upar se guzarti rehti hai — bilkul TV channel ke idents ki tarah. Lehar sirf logo ki shakal ke andar chamakti hai; us ki raftaar slider se kam/zyada karein.',
      'Hisay tab ki list mein teer (upar/neeche) se layer ki tarteeb badlein — pehla hissa sab se peeche, aakhri sab se upar rehta hai.',
      'Parts ki setting mehfooz rakhni ho to Save tab se save karein — 300 coins mein 7 din tak rehti hai.',
      'Save tab mein Export size bhi hai: green-screen (Permanent Logo) export ke frames 512 (Halka — tez, halka) ya 1024 (Saaf — zyada saaf, thoda bhari) ke bante hain. Default 512 hai.',
    ],
    tips: [
      'Ghumao nazar na aye to pehle us hisay ka Rotate switch check karein — ON hona chahiye.',
      'Gol hisay ka Flat ghumao kam nazar ata hai — us par 3D style ya 2 second wali speed rakh kar dekhein.',
      'Tajweez ghalat box de to ghabrayein nahi — box hilana/size karna hi asal tareeqa hai; flat tasveer se har dafa 100% durust tajweez mumkin nahi hoti.',
      'Settings save na karein to wo sirf is session ke liye hain — app band karne par khatam.',
    ],
  ),
  'ns.reporter': ToolGuideEntry(
    title: 'Reporter',
    what:
        'Reporter ki naam-patti (name strap) aur us ki photo lagata hai; '
        'Teleprompter se script parh kar recording bhi yahin se hoti hai.',
    steps: [
      'Reporter ka naam likhein aur photo lagayein.',
      'Patti ka andaaz chunein — preview mein nazar aye gi.',
      'Bolna mushkil ho to Teleprompter kholein: script samne chalega, parh kar record karein — recording khud clips mein shamil ho jati hai.',
    ],
    tips: [
      'Recording ke baad tasdeeq ka message tab hi ata hai jab wo asal mein clips mein shamil ho jaye.',
    ],
  ),
  'ns.audio': ToolGuideEntry(
    title: 'Audio',
    what:
        'Khabar ki awaz ki settings — background music, Store se liye '
        'huye sounds, aur volume.',
    steps: [
      'Background music chunein (apni file ya Store ki Music).',
      'Music ka volume awaz se kam rakhein taake khabar saaf sunai de.',
      'Jo clip ki apni awaz hai us ka volume bhi yahin se set hota hai.',
    ],
    tips: [
      'Music tez ho to voice dab jati hai — music 15–25% par rakhein.',
    ],
  ),
  'ns.voice': ToolGuideEntry(
    title: 'Voice (Voiceover)',
    what:
        'Khabar par bolna: apni awaz record karein, ya tehreer likh kar '
        'AI awaz banwayein.',
    steps: [
      'Apni awaz: record dabayein, khabar parhein, stop karein.',
      'AI awaz: script likhein aur awaz banwayein — bani hui awaz mehfooz (cache) rehti hai, dobara par coins nahi lagte.',
      'Background music ka switch yahin hai — voice ke neeche music rakhna ho to on rakhein.',
      'Sun kar check karein, phir export karein.',
    ],
    tips: [
      'Record se pehle khamosh jagah chunein — shor awaz mein saaf ata hai.',
      'AI awaz ki qeemat (coins) button par likhi hoti hai.',
    ],
  ),
  'ns.captions': ToolGuideEntry(
    title: 'Captions',
    what:
        'Video par bolne ke sath chalne wale captions (subtitles) — andaaz '
        'chunein, captions preview mein bhi nazar ate hain.',
    steps: [
      'Captions on karein aur andaaz (style) chunein.',
      'Font, size aur jagah set karein.',
      'Preview chala kar dekhein captions sahi waqt par ate hain ya nahi.',
      'Export mein captions video par pakke (burn) ho kar ayenge.',
    ],
    tips: [
      'Asal timings wale captions awaz se khud bante hain — lambi video par waqt lag sakta hai.',
      'Caption ka rang background se alag rakhein warna parha nahi jayega.',
    ],
  ),
  'ns.export': ToolGuideEntry(
    title: 'Export',
    what: 'Tayyar khabar ko video file banata hai — quality chunein aur export karein.',
    steps: [
      'Quality chunein: 720p muft hai; 1080p/2K par ads ate hain (Pro par nahi).',
      'Export dabayein — ads pehle ayenge, phir export shuru hoga.',
      'Progress khatam hone dein — export ke doran app band na karein.',
      'Bani hui video gallery mein mehfooz ho jati hai.',
    ],
    tips: [
      'Export 50–60% par rukta mehsoos ho to thora intezar karein — bhari hisa chal raha hota hai; app band hona ab report ho jata hai.',
      'Kamzor phone par 720p sab se pur-sukoon rehta hai.',
    ],
  ),
};
