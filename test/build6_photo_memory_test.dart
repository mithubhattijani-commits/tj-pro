// Build 6 (Master Plan Phase 7) — 24 MP memory/handling test.
//
// The Phase 7 verification the master plan orders: a very large
// photo (6000x4000 = 24 MP) must flow through the real pipeline —
// decode, a compute-isolate colour pass, Enlarge and the full
// export — without unbounded memory growth. The specific bound
// under test: enlargeImage must NEVER produce more than ~40 MP
// of output (a 24 MP photo at the maximum 4x used to request
// ~384 MP ≈ 1.5 GB of pixels — an OOM kill, not an edit).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tj_pro/services/photo_pipeline.dart';

void main() {
  test(
    '24 MP image: decode + colour pass + bounded enlarge + export',
    () async {
      final dir = await Directory.systemTemp.createTemp('tj_b6_24mp_');
      try {
        // A real 24 MP frame, encoded the way a phone camera
        // would deliver it.
        final src = img.Image(width: 6000, height: 4000);
        img.fill(src, color: img.ColorRgb8(120, 90, 60));
        final jpgBytes = img.encodeJpg(src, quality: 85);
        final inFile = File('${dir.path}/in.jpg');
        await inFile.writeAsBytes(jpgBytes);

        // Decode at full size (the editor's _decodeWorking path).
        final decoded = img.decodeImage(await inFile.readAsBytes());
        expect(decoded, isNotNull);
        expect(decoded!.width * decoded.height, 24000000);

        // A compute-isolate colour pass at full size.
        final matrix = buildColorMatrix(
          filter: PhotoFilter.warm,
          brightness: 5,
          contrast: 1.05,
          saturation: 1.1,
          filterIntensity: 0.8,
          exposure: 0,
          temperature: 10,
          tint: 0,
          vibrance: 0,
          fade: 0,
        );
        final passed = await applyColorMatrix(decoded, matrix);
        expect(passed.width, 6000);
        expect(passed.height, 4000);

        // THE bound: even at the maximum 4x, the enlarge output
        // stays within the ~40 MP budget — and still enlarges.
        final enlarged = await enlargeImage(decoded, scale: 4.0);
        final outPixels = enlarged.width * enlarged.height;
        expect(outPixels, lessThanOrEqualTo(40000000));
        expect(outPixels, greaterThan(24000000));

        // Typical photos keep the full requested scale: 2 MP at
        // 2x comes out at exactly 2x (8 MP, well under budget).
        final small = img.Image(width: 2000, height: 1000);
        img.fill(small, color: img.ColorRgb8(10, 20, 30));
        final enlargedSmall = await enlargeImage(small, scale: 2.0);
        expect(enlargedSmall.width, 4000);
        expect(enlargedSmall.height, 2000);

        // The full export path at 24 MP completes and writes a
        // real file.
        final outFile = await exportPhoto(
          workingFile: inFile,
          params: const PhotoEditParams(
            filter: PhotoFilter.warm,
            brightness: 5,
          ),
          outPath: '${dir.path}/out.jpg',
          keepAlpha: false,
        );
        expect(await outFile.exists(), isTrue);
        expect(await outFile.length(), greaterThan(0));
        final roundTrip = img.decodeImage(await outFile.readAsBytes());
        expect(roundTrip, isNotNull);
        expect(roundTrip!.width, 6000);
        expect(roundTrip.height, 4000);
      } finally {
        try {
          await dir.delete(recursive: true);
        } catch (_) {
          // Temp cleanup is best-effort.
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
