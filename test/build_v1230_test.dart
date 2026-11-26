// v1.23.0 — Engine Vault integration tests.
//
// The pure planner has its own 52-test suite
// (engine_vault_gemini_test.dart, the checked Gemini core). These
// tests prove the WIRING against the REAL registry:
//   (a) simulated update — manifest + files present, plan is all
//       keep, zero download actions (the planner has no app
//       version input at all, so an update cannot invalidate);
//   (b) a new pack in the catalogue → only it downloads;
//   (c) one file's size changed → only that pack repairs, and
//       only that one file is named;
//   (d) manifest corrupt/deleted → complete packs adopt, zero
//       downloads;
//   (e) one pack's vaultVersion bumped → only it refreshes;
//   (f) an existing user's first vault launch (no manifest file
//       at all, packs already on disk from pre-vault versions)
//       → every complete pack adopts, zero downloads — proven
//       end-to-end through the real disk scan + manifest persist.
// Plus catalogue integrity: every registry file with a pinned
// size is in the catalogue with that exact size, and every pack
// carries vaultVersion >= 1.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tj_pro/services/engine_vault.dart';
import 'package:tj_pro/services/engine_vault_service.dart';
import 'package:tj_pro/services/model_pack_service.dart';

/// A diskFiles map where every catalogue file exists at its
/// exact def size — a fully installed device.
Map<String, Map<String, int>> fullDisk(List<VaultPackDef> catalogue) {
  return <String, Map<String, int>>{
    for (final pack in catalogue)
      pack.id: <String, int>{
        for (final f in pack.files) f.name: f.sizeBytes,
      },
  };
}

VaultAction actionFor(List<VaultAction> actions, String packId) {
  return actions.singleWhere((a) => a.packId == packId);
}

void main() {
  final catalogue = EngineVaultService.catalogue();

  group('catalogue integrity (real registry)', () {
    test('every registry pack is in the catalogue, same order', () {
      expect(catalogue.length, ModelPackService.packs.length);
      for (var i = 0; i < catalogue.length; i++) {
        expect(catalogue[i].id, ModelPackService.packs[i].id);
        expect(
          catalogue[i].version,
          ModelPackService.packs[i].vaultVersion,
        );
      }
    });

    test('every pack carries vaultVersion >= 1', () {
      for (final pack in ModelPackService.packs) {
        expect(pack.vaultVersion, greaterThanOrEqualTo(1),
            reason: 'pack ${pack.id}');
      }
    });

    test('every pinned registry file is in the catalogue exactly', () {
      for (final pack in ModelPackService.packs) {
        final def = catalogue.singleWhere((d) => d.id == pack.id);
        final pinned = <String, int>{
          for (final f in pack.files)
            if (f.expectedBytes > 0) f.name: f.expectedBytes,
        };
        expect(def.files.length, pinned.length, reason: pack.id);
        for (final f in def.files) {
          expect(pinned[f.name], f.sizeBytes,
              reason: '${pack.id}/${f.name}');
        }
        expect(def.totalBytes, pinned.values.fold<int>(0, (a, b) => a + b),
            reason: pack.id);
      }
    });

    test('rnnoise cb.rnnn size is pinned (was the only unknown)', () {
      final pack = ModelPackService.packById('rnnoise_models')!;
      final file = pack.files.singleWhere((f) => f.name == 'cb.rnnn');
      expect(file.expectedBytes, 299741);
    });

    test('no registry file is left unpinned anymore', () {
      for (final pack in ModelPackService.packs) {
        for (final f in pack.files) {
          expect(f.expectedBytes, greaterThan(0),
              reason: '${pack.id}/${f.name} must have a pinned size '
                  'or it can never join the exact-size catalogue');
        }
      }
    });
  });

  group('vault plan against the real catalogue', () {
    test('(a) simulated update: everything installed -> all keep, '
        'zero downloads', () {
      final disk = fullDisk(catalogue);
      final manifest = VaultPlanner.buildManifest(
        catalogue: catalogue,
        diskFiles: disk,
      );
      // The "update" changes only the app version — which is not
      // an input to the planner at all. Same catalogue, same
      // manifest, same disk => same plan.
      final actions = VaultPlanner.plan(
        catalogue: catalogue,
        manifest: manifest,
        diskFiles: disk,
      );
      expect(actions.length, catalogue.length);
      for (final a in actions) {
        expect(a.type, VaultActionType.keep, reason: a.packId);
      }
      expect(
        actions.where((a) => a.type == VaultActionType.download),
        isEmpty,
      );
      expect(
        actions.where((a) => a.type == VaultActionType.refresh),
        isEmpty,
      );
      expect(
        actions.where((a) => a.type == VaultActionType.repair),
        isEmpty,
      );
    });

    test('(b) new pack in the catalogue -> only it downloads', () {
      final disk = fullDisk(catalogue);
      final manifest = VaultPlanner.buildManifest(
        catalogue: catalogue,
        diskFiles: disk,
      );
      const newPack = VaultPackDef(
        id: 'brand_new_pack',
        version: 1,
        files: [VaultFileDef(name: 'new.onnx', sizeBytes: 1234)],
      );
      final bigger = <VaultPackDef>[...catalogue, newPack];
      final disk2 = <String, Map<String, int>>{
        ...disk,
        'brand_new_pack': <String, int>{},
      };
      final actions = VaultPlanner.plan(
        catalogue: bigger,
        manifest: manifest,
        diskFiles: disk2,
      );
      final downloads =
          actions.where((a) => a.type == VaultActionType.download).toList();
      expect(downloads.length, 1);
      expect(downloads.single.packId, 'brand_new_pack');
      expect(downloads.single.files, ['new.onnx']);
      for (final a in actions) {
        if (a.packId != 'brand_new_pack') {
          expect(a.type, VaultActionType.keep, reason: a.packId);
        }
      }
    });

    test('(c) one file size changed -> only that pack repairs, '
        'only that file', () {
      final disk = fullDisk(catalogue);
      final manifest = VaultPlanner.buildManifest(
        catalogue: catalogue,
        diskFiles: disk,
      );
      // Corrupt exactly one file of one real pack (dfn3/config.ini).
      disk['dfn3'] = <String, int>{...disk['dfn3']!, 'config.ini': 999};
      final actions = VaultPlanner.plan(
        catalogue: catalogue,
        manifest: manifest,
        diskFiles: disk,
      );
      final repairs =
          actions.where((a) => a.type == VaultActionType.repair).toList();
      expect(repairs.length, 1);
      expect(repairs.single.packId, 'dfn3');
      expect(repairs.single.files, ['config.ini']);
      expect(
        actions.where((a) => a.type == VaultActionType.download),
        isEmpty,
      );
      for (final a in actions) {
        if (a.packId != 'dfn3') {
          expect(a.type, VaultActionType.keep, reason: a.packId);
        }
      }
    });

    test('(d) manifest corrupt -> complete packs adopt, '
        'zero downloads', () {
      final disk = fullDisk(catalogue);
      final corrupt = VaultManifest.tryDecode('{"packs":{"dfn3":');
      expect(corrupt, isNull);
      final actions = VaultPlanner.plan(
        catalogue: catalogue,
        manifest: corrupt,
        diskFiles: disk,
      );
      expect(actions.length, catalogue.length);
      for (final a in actions) {
        expect(a.type, VaultActionType.adopt, reason: a.packId);
      }
      expect(
        actions.where((a) => a.type == VaultActionType.download),
        isEmpty,
      );
    });

    test('(e) one pack vaultVersion bumped -> only it refreshes', () {
      final disk = fullDisk(catalogue);
      final manifest = VaultPlanner.buildManifest(
        catalogue: catalogue,
        diskFiles: disk,
      );
      final bumped = <VaultPackDef>[
        for (final def in catalogue)
          if (def.id == 'modnet')
            VaultPackDef(
              id: def.id,
              version: def.version + 1,
              files: def.files,
            )
          else
            def,
      ];
      final actions = VaultPlanner.plan(
        catalogue: bumped,
        manifest: manifest,
        diskFiles: disk,
      );
      final refreshes =
          actions.where((a) => a.type == VaultActionType.refresh).toList();
      expect(refreshes.length, 1);
      expect(refreshes.single.packId, 'modnet');
      expect(
        refreshes.single.files,
        catalogue.singleWhere((d) => d.id == 'modnet').files.map((f) => f.name).toList(),
      );
      for (final a in actions) {
        if (a.packId != 'modnet') {
          expect(a.type, VaultActionType.keep, reason: a.packId);
        }
      }
    });
  });

  group('disk scan + manifest persistence (temp vault root)', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('vault_test_');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    Future<void> writePackFiles(
      VaultPackDef def, {
      Map<String, int> sizeOverrides = const {},
    }) async {
      final dir = Directory('${root.path}/${def.id}');
      await dir.create(recursive: true);
      for (final f in def.files) {
        final size = sizeOverrides[f.name] ?? f.sizeBytes;
        final raf = await File('${dir.path}/${f.name}').open(mode: FileMode.write);
        await raf.truncate(size);
        await raf.close();
      }
    }

    test('(f) first vault launch of an existing user: packs on '
        'disk, no manifest -> all adopt, manifest then persists '
        'and the next plan is all keep', () async {
      // A small synthetic catalogue keeps the temp files tiny;
      // the planner path is identical to the real one.
      const cat = <VaultPackDef>[
        VaultPackDef(
          id: 'pack_one',
          version: 1,
          files: [
            VaultFileDef(name: 'a.onnx', sizeBytes: 100),
            VaultFileDef(name: 'b.onnx', sizeBytes: 200),
          ],
        ),
        VaultPackDef(
          id: 'pack_two',
          version: 1,
          files: [VaultFileDef(name: 'c.onnx', sizeBytes: 50)],
        ),
      ];
      for (final def in cat) {
        await writePackFiles(def);
      }
      // No manifest file exists — the pre-vault user's state.
      final manifest = await EngineVaultService.loadManifestIn(root);
      expect(manifest, isNull);

      final disk = await EngineVaultService.scanDiskIn(root, cat);
      final actions = VaultPlanner.plan(
        catalogue: cat,
        manifest: manifest,
        diskFiles: disk,
      );
      expect(actions.length, 2);
      for (final a in actions) {
        expect(a.type, VaultActionType.adopt, reason: a.packId);
      }

      // Prep persists the manifest; from then on: all keep.
      final written = await EngineVaultService.persistManifestIn(root, cat);
      expect(written, isNotNull);
      expect(written!.packs.keys, containsAll(<String>['pack_one', 'pack_two']));
      final manifestFile = File(
        '${root.path}/${EngineVaultService.manifestFileName}',
      );
      expect(await manifestFile.exists(), isTrue);

      final reloaded = await EngineVaultService.loadManifestIn(root);
      expect(reloaded, isNotNull);
      final disk2 = await EngineVaultService.scanDiskIn(root, cat);
      final actions2 = VaultPlanner.plan(
        catalogue: cat,
        manifest: reloaded,
        diskFiles: disk2,
      );
      for (final a in actions2) {
        expect(a.type, VaultActionType.keep, reason: a.packId);
      }
    });

    test('scan ignores .part files and missing dirs', () async {
      const cat = <VaultPackDef>[
        VaultPackDef(
          id: 'pack_one',
          version: 1,
          files: [VaultFileDef(name: 'a.onnx', sizeBytes: 100)],
        ),
        VaultPackDef(
          id: 'pack_missing',
          version: 1,
          files: [VaultFileDef(name: 'z.onnx', sizeBytes: 10)],
        ),
      ];
      final dir = Directory('${root.path}/pack_one');
      await dir.create(recursive: true);
      final raf = await File('${dir.path}/a.onnx.part').open(mode: FileMode.write);
      await raf.truncate(40);
      await raf.close();

      final disk = await EngineVaultService.scanDiskIn(root, cat);
      expect(disk['pack_one'], isEmpty,
          reason: 'a .part file must never pose as the real file');
      expect(disk['pack_missing'], isEmpty);

      final actions = VaultPlanner.plan(
        catalogue: cat,
        manifest: null,
        diskFiles: disk,
      );
      expect(actionFor(actions, 'pack_one').type, VaultActionType.download);
      expect(actionFor(actions, 'pack_missing').type, VaultActionType.download);
    });

    test('persistManifest records only fully-verified packs', () async {
      const cat = <VaultPackDef>[
        VaultPackDef(
          id: 'pack_full',
          version: 1,
          files: [VaultFileDef(name: 'a.onnx', sizeBytes: 100)],
        ),
        VaultPackDef(
          id: 'pack_broken',
          version: 1,
          files: [VaultFileDef(name: 'b.onnx', sizeBytes: 100)],
        ),
      ];
      await writePackFiles(cat[0]);
      await writePackFiles(cat[1], sizeOverrides: {'b.onnx': 7});

      final manifest = await EngineVaultService.persistManifestIn(root, cat);
      expect(manifest, isNotNull);
      expect(manifest!.packs.containsKey('pack_full'), isTrue);
      expect(manifest.packs.containsKey('pack_broken'), isFalse,
          reason: 'a size-mismatched pack must never be recorded '
              'as installed — that is what would hide corruption');
    });

    test('corrupt manifest file on disk loads as null (safe)', () async {
      await File('${root.path}/${EngineVaultService.manifestFileName}')
          .writeAsString('this is not json at all');
      final manifest = await EngineVaultService.loadManifestIn(root);
      expect(manifest, isNull);
    });
  });
}
