// Build 4 — Video Editor player bug fix regression tests.
//
// Diagnosis (PLAYER-BUG-DIAGNOSIS.md): playback auto-scroll uses
// jumpTo(), which manufactures ScrollStart/End notifications; the
// timeline's ScrollEnd handler treated them as a user scrub and
// seeked the player back to the boundary snap (0) on every tick —
// a seek-fight loop that pinned playback at 0:00 with a black
// preview. The ScrollEnd -> seek decision now goes through
// TimelineMath.scrubSeekOnScrollEnd; these tests pin it.
//
// (A widget-level test of the full listener would need a fake of
// the 255-member VideoEditorController contract — not feasible;
// the decision itself is pure and pinned here instead.)
import 'package:flutter_test/flutter_test.dart';
import 'package:tj_pro/video/widgets/editor_stage.dart';

void main() {
  group('Build 4 player fix — scrubSeekOnScrollEnd', () {
    test('playing: a ScrollEnd must NOT seek (strip follows player)', () {
      expect(
        TimelineMath.scrubSeekOnScrollEnd(
          isPlaying: true,
          programmaticScroll: false,
        ),
        isFalse,
      );
    });

    test('programmatic jumpTo: a ScrollEnd must NOT seek', () {
      expect(
        TimelineMath.scrubSeekOnScrollEnd(
          isPlaying: false,
          programmaticScroll: true,
        ),
        isFalse,
      );
    });

    test('paused user scrub: a ScrollEnd DOES seek (unchanged)', () {
      expect(
        TimelineMath.scrubSeekOnScrollEnd(
          isPlaying: false,
          programmaticScroll: false,
        ),
        isTrue,
      );
    });
  });
}
