# Chroma-key backgrounds (News Studio v1)

Bundled studio backdrops for the chroma-key (green screen) background
picker: Newsroom / Studio Desk / gallery. Both images are **CC0
(public domain)** — free to use, no attribution required, no people
facing the camera, no channel branding.

| File | Image | Source | Licence |
|---|---|---|---|
| `newsroom.jpg` | Czech Radio newsroom — desks, monitors, wall screens | Wikimedia Commons: `File:Budova CR Vinohr 12 Newsroom A.jpg` — https://commons.wikimedia.org/wiki/File:Budova_CR_Vinohr_12_Newsroom_A.jpg | CC0 |
| `studio_desk.jpg` | ABC Perth news studio with anchor desk, blue-lit | Wikimedia Commons: `File:ABC Perth - News studio (1) (E37@OpenHousePerth2014).JPG` — https://commons.wikimedia.org/wiki/File:ABC_Perth_-_News_studio_(1)_(E37%40OpenHousePerth2014).JPG | CC0 |

Both are 1280×960 downloads (Wikimedia 1920px thumbnails of the
4000×3000 / 4096×3072 originals, downscaled to 1280 wide, JPEG q5) —
≥1280×720 as required, sized for a 720×1280 export (the chroma filter
scales/crops via `scale2ref`). Total bundled size ~318 KB
(newsroom.jpg 225 KB + studio_desk.jpg 93 KB) — small enough to bundle
under the app-size rule (user order 20 Nov 2026).

NOTE (app-size order, 20 Nov 2026): the heavy assets — the 12.6 MB
Kasheeda TTF and the intro video — are NOT bundled. They download
on demand via `lib/services/asset_download_service.dart` (URLs from
`AppConfig.kasheedaFontUrl` / `AppConfig.nigraanIntroUrl`, hosted at
release time). Only these two small backgrounds ship in the APK.

## Rejected candidates (checked 20 Nov 2026)
- "WEOL news studio" (CC0) — a radio control room, not a TV
  newsroom/studio; cluttered, face visible. Rejected on content.
- Rawpixel "Newsroom. Original public domain image" — an MSNBC "Morning
  Joe" studio: 5 people on camera, MSNBC branding, rawpixel watermark.
  Rejected.
- "CNN Atlanta Newsroom" — CC BY 2.0, not CC0/public-domain. Excluded
  by the sourcing rule.
- "CNN Newsroom" / ABC Perth (2) — the first was a stale Openverse
  URL (404); the second is a behind-the-scenes angle with cameras in
  frame (usable, but (1) is the cleaner desk shot).
