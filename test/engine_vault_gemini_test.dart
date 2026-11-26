// Functional check tests for the Gemini-supplied Engine Vault core
// (gemini-inbox/engine_vault.dart), written against
// MASTER-PROMPT-ENGINE-VAULT.txt rule by rule.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tj_pro/services/engine_vault.dart';

const packA = VaultPackDef(
  id: 'pack_a',
  version: 2,
  files: [
    VaultFileDef(name: 'a1.onnx', sizeBytes: 100),
    VaultFileDef(name: 'a2.onnx', sizeBytes: 200),
    VaultFileDef(name: 'a3.txt', sizeBytes: 30),
  ],
);

const packB = VaultPackDef(
  id: 'pack_b',
  version: 1,
  files: [
    VaultFileDef(name: 'b1.onnx', sizeBytes: 500),
  ],
);

const packC = VaultPackDef(
  id: 'pack_c',
  version: 3,
  files: [
    VaultFileDef(name: 'c1.onnx', sizeBytes: 700),
    VaultFileDef(name: 'c2.onnx', sizeBytes: 800),
  ],
);

const diskAFull = <String, int>{'a1.onnx': 100, 'a2.onnx': 200, 'a3.txt': 30};
const diskBFull = <String, int>{'b1.onnx': 500};
const diskCFull = <String, int>{'c1.onnx': 700, 'c2.onnx': 800};

VaultManifest manifestOf(Map<String, VaultInstalledPack> packs) {
  return VaultManifest(packs: packs);
}

VaultInstalledPack installed(String id, int version, Map<String, int> sizes) {
  return VaultInstalledPack(id: id, version: version, fileSizes: sizes);
}

VaultAction onlyAction(List<VaultAction> actions, String packId) {
  return actions.singleWhere((a) => a.packId == packId);
}

void main() {
  group('VaultManifest.tryDecode', () {
    test('null input returns null', () {
      expect(VaultManifest.tryDecode(null), isNull);
    });

    test('empty string returns null', () {
      expect(VaultManifest.tryDecode(''), isNull);
    });

    test('garbage JSON returns null', () {
      expect(VaultManifest.tryDecode('this is not json'), isNull);
      expect(VaultManifest.tryDecode('{"packs":'), isNull);
    });

    test('non-map JSON returns null', () {
      expect(VaultManifest.tryDecode('[]'), isNull);
      expect(VaultManifest.tryDecode('42'), isNull);
      expect(VaultManifest.tryDecode('"packs"'), isNull);
    });

    test('missing or wrong-shaped packs key returns null', () {
      expect(VaultManifest.tryDecode('{}'), isNull);
      expect(VaultManifest.tryDecode('{"packs":[]}'), isNull);
      expect(VaultManifest.tryDecode('{"packs":42}'), isNull);
    });

    test('negative file size returns null', () {
      const bad = '{"packs":{"p":{"id":"p","version":1,'
          '"fileSizes":{"f.onnx":-5}}}}';
      expect(VaultManifest.tryDecode(bad), isNull);
    });

    test('negative version returns null', () {
      const bad = '{"packs":{"p":{"id":"p","version":-1,"fileSizes":{}}}}';
      expect(VaultManifest.tryDecode(bad), isNull);
    });

    test('inner id not matching the map key returns null', () {
      const bad = '{"packs":{"p":{"id":"q","version":1,"fileSizes":{}}}}';
      expect(VaultManifest.tryDecode(bad), isNull);
    });

    test('wrong value shapes return null', () {
      const badVersion = '{"packs":{"p":{"id":"p","version":1.5,'
          '"fileSizes":{}}}}';
      const badSize = '{"packs":{"p":{"id":"p","version":1,'
          '"fileSizes":{"f.onnx":"100"}}}}';
      const badPack = '{"packs":{"p":42}}';
      expect(VaultManifest.tryDecode(badVersion), isNull);
      expect(VaultManifest.tryDecode(badSize), isNull);
      expect(VaultManifest.tryDecode(badPack), isNull);
    });

    test('one malformed pack poisons the whole manifest', () {
      const mixed = '{"packs":{'
          '"good":{"id":"good","version":1,"fileSizes":{"g":10}},'
          '"bad":{"id":"bad","version":-2,"fileSizes":{}}'
          '}}';
      expect(VaultManifest.tryDecode(mixed), isNull);
    });

    test('empty packs object decodes to an empty manifest', () {
      final m = VaultManifest.tryDecode('{"packs":{}}');
      expect(m, isNotNull);
      expect(m!.packs, isEmpty);
    });

    test('valid JSON decodes to the exact manifest', () {
      const good = '{"packs":{"pack_a":{"id":"pack_a","version":2,'
          '"fileSizes":{"a1.onnx":100,"a2.onnx":200,"a3.txt":30}}}}';
      final m = VaultManifest.tryDecode(good);
      expect(m, isNotNull);
      expect(m!.packs.length, 1);
      expect(m.packs['pack_a'], installed('pack_a', 2, diskAFull));
    });

    test('encode -> tryDecode roundtrip preserves the manifest', () {
      final original = manifestOf({
        'pack_a': installed('pack_a', 2, diskAFull),
        'pack_b': installed('pack_b', 1, diskBFull),
      });
      final decoded = VaultManifest.tryDecode(original.encode());
      expect(decoded, isNotNull);
      expect(decoded!.packs.length, 2);
      expect(decoded.packs['pack_a'], original.packs['pack_a']);
      expect(decoded.packs['pack_b'], original.packs['pack_b']);
      expect(decoded.encode(), original.encode());
    });

    test('empty manifest roundtrips', () {
      final decoded = VaultManifest.tryDecode(VaultManifest.empty().encode());
      expect(decoded, isNotNull);
      expect(decoded!.packs, isEmpty);
    });
  });

  group('VaultManifest.encode', () {
    test('produces the documented JSON shape', () {
      final m = manifestOf({'pack_b': installed('pack_b', 1, diskBFull)});
      final decoded = jsonDecode(m.encode()) as Map<String, dynamic>;
      final packs = decoded['packs'] as Map<String, dynamic>;
      final pack = packs['pack_b'] as Map<String, dynamic>;
      expect(pack['id'], 'pack_b');
      expect(pack['version'], 1);
      expect(pack['fileSizes'], {'b1.onnx': 500});
    });

    test('never throws on an invalid in-memory manifest', () {
      final m = manifestOf({
        'broken': installed('broken', -3, {'f': -1}),
        '': installed('', 1, {}),
      });
      expect(m.encode, returnsNormally);
      final decoded = VaultManifest.tryDecode(m.encode());
      expect(decoded, isNotNull);
      expect(decoded!.packs.containsKey('broken'), isFalse);
    });
  });

  group('VaultPlanner.plan', () {
    test('(a) empty disk and no record -> download with all files', () {
      final actions = VaultPlanner.plan(
        catalogue: const [packA],
        manifest: null,
        diskFiles: const {},
      );
      expect(actions.length, 1);
      expect(actions.single.packId, 'pack_a');
      expect(actions.single.type, VaultActionType.download);
      expect(actions.single.files, ['a1.onnx', 'a2.onnx', 'a3.txt']);
    });

    test('(a2) empty manifest (not null) and empty disk -> download', () {
      final actions = VaultPlanner.plan(
        catalogue: const [packA],
        manifest: VaultManifest.empty(),
        diskFiles: const {},
      );
      expect(actions.single.type, VaultActionType.download);
    });

    test('(b) record, same version, all files exact -> keep', () {
      final actions = VaultPlanner.plan(
        catalogue: const [packA],
        manifest: manifestOf({'pack_a': installed('pack_a', 2, diskAFull)}),
        diskFiles: const {'pack_a': diskAFull},
      );
      expect(actions.single.type, VaultActionType.keep);
      expect(actions.single.files, ['a1.onnx', 'a2.onnx', 'a3.txt']);
    });

    test('(b2) extra unknown files on disk do not break keep', () {
      final actions = VaultPlanner.plan(
        catalogue: const [packA],
        manifest: manifestOf({'pack_a': installed('pack_a', 2, diskAFull)}),
        diskFiles: const {
          'pack_a': {'a1.onnx': 100, 'a2.onnx': 200, 'a3.txt': 30, 'x': 9},
        },
      );
      expect(actions.single.type, VaultActionType.keep);
    });

    test('(c) older record version -> refresh, only that pack', () {
      final actions = VaultPlanner.plan(
        catalogue: const [packA, packB],
        manifest: manifestOf({
          'pack_a': installed('pack_a', 1, diskAFull),
          'pack_b': installed('pack_b', 1, diskBFull),
        }),
        diskFiles: const {'pack_a': diskAFull, 'pack_b': diskBFull},
      );
      expect(actions.length, 2);
      final a = onlyAction(actions, 'pack_a');
      expect(a.type, VaultActionType.refresh);
      expect(a.files, ['a1.onnx', 'a2.onnx', 'a3.txt']);
      expect(onlyAction(actions, 'pack_b').type, VaultActionType.keep);
    });

    test('(d) newer record version -> keep, never downgrade', () {
      final actions = VaultPlanner.plan(
        catalogue: const [packA],
        manifest: manifestOf({'pack_a': installed('pack_a', 5, diskAFull)}),
        diskFiles: const {'pack_a': diskAFull},
      );
      expect(actions.single.type, VaultActionType.keep);
    });

    test('(d2) newer record version with empty disk is still keep', () {
      final actions = VaultPlanner.plan(
        catalogue: const [packA],
        manifest: manifestOf({'pack_a': installed('pack_a', 5, diskAFull)}),
        diskFiles: const {},
      );
      expect(actions.single.type, VaultActionType.keep);
    });

    test('(e) same version, one wrong size + one missing -> repair '
        'with ONLY those two files, in def order', () {
      final actions = VaultPlanner.plan(
        catalogue: const [packA],
        manifest: manifestOf({'pack_a': installed('pack_a', 2, diskAFull)}),
        diskFiles: const {
          'pack_a': {'a1.onnx': 100, 'a2.onnx': 999},
        },
      );
      final a = actions.single;
      expect(a.type, VaultActionType.repair);
      expect(a.files, ['a2.onnx', 'a3.txt']);
    });

    test('(e2) same version, disk completely empty -> repair all files', () {
      final actions = VaultPlanner.plan(
        catalogue: const [packA],
        manifest: manifestOf({'pack_a': installed('pack_a', 2, diskAFull)}),
        diskFiles: const {},
      );
      final a = actions.single;
      expect(a.type, VaultActionType.repair);
      expect(a.files, ['a1.onnx', 'a2.onnx', 'a3.txt']);
    });

    test('(f) null manifest (corrupt) + disk fully correct -> adopt', () {
      final actions = VaultPlanner.plan(
        catalogue: const [packA],
        manifest: null,
        diskFiles: const {'pack_a': diskAFull},
      );
      final a = actions.single;
      expect(a.type, VaultActionType.adopt);
      expect(a.files, ['a1.onnx', 'a2.onnx', 'a3.txt']);
    });

    test('(f2) manifest present but no record + disk correct -> adopt', () {
      final actions = VaultPlanner.plan(
        catalogue: const [packA],
        manifest: manifestOf({'pack_b': installed('pack_b', 1, diskBFull)}),
        diskFiles: const {'pack_a': diskAFull},
      );
      expect(actions.single.type, VaultActionType.adopt);
    });

    test('(g) null manifest + some files good, some bad -> repair '
        'with only the bad ones', () {
      final actions = VaultPlanner.plan(
        catalogue: const [packA],
        manifest: null,
        diskFiles: const {
          'pack_a': {'a1.onnx': 100, 'a2.onnx': 12345},
        },
      );
      final a = actions.single;
      expect(a.type, VaultActionType.repair);
      expect(a.files, ['a2.onnx', 'a3.txt']);
    });

    test('(h) null manifest + no file matches -> download', () {
      final actions = VaultPlanner.plan(
        catalogue: const [packA],
        manifest: null,
        diskFiles: const {
          'pack_a': {'a1.onnx': 1, 'a2.onnx': 2, 'a3.txt': 3},
        },
      );
      expect(actions.single.type, VaultActionType.download);
      expect(actions.single.files, ['a1.onnx', 'a2.onnx', 'a3.txt']);
    });

    test('(h2) null manifest + only unknown files on disk -> download', () {
      final actions = VaultPlanner.plan(
        catalogue: const [packA],
        manifest: null,
        diskFiles: const {
          'pack_a': {'unrelated.bin': 42},
        },
      );
      expect(actions.single.type, VaultActionType.download);
    });

    test('(i) new pack added to the catalogue -> only it downloads', () {
      final manifest = manifestOf({
        'pack_a': installed('pack_a', 2, diskAFull),
        'pack_b': installed('pack_b', 1, diskBFull),
      });
      const disk = {'pack_a': diskAFull, 'pack_b': diskBFull};
      final before = VaultPlanner.plan(
        catalogue: const [packA, packB],
        manifest: manifest,
        diskFiles: disk,
      );
      expect(before.every((a) => a.type == VaultActionType.keep), isTrue);

      final after = VaultPlanner.plan(
        catalogue: const [packA, packB, packC],
        manifest: manifest,
        diskFiles: disk,
      );
      expect(after.length, 3);
      expect(onlyAction(after, 'pack_a').type, VaultActionType.keep);
      expect(onlyAction(after, 'pack_b').type, VaultActionType.keep);
      final c = onlyAction(after, 'pack_c');
      expect(c.type, VaultActionType.download);
      expect(c.files, ['c1.onnx', 'c2.onnx']);
    });

    test('(j) packs outside the catalogue get NO action', () {
      final actions = VaultPlanner.plan(
        catalogue: const [packA],
        manifest: manifestOf({
          'pack_a': installed('pack_a', 2, diskAFull),
          'ghost': installed('ghost', 9, {'g.bin': 1}),
        }),
        diskFiles: const {
          'pack_a': diskAFull,
          'ghost': {'g.bin': 1},
        },
      );
      expect(actions.length, 1);
      expect(actions.single.packId, 'pack_a');
    });

    test('(k) actions follow catalogue order, files follow def order', () {
      final actions = VaultPlanner.plan(
        catalogue: const [packC, packA, packB],
        manifest: manifestOf({'pack_a': installed('pack_a', 2, diskAFull)}),
        diskFiles: const {
          'pack_a': {'a2.onnx': 200},
        },
      );
      expect(actions.map((a) => a.packId).toList(),
          ['pack_c', 'pack_a', 'pack_b']);
      final a = onlyAction(actions, 'pack_a');
      expect(a.type, VaultActionType.repair);
      expect(a.files, ['a1.onnx', 'a3.txt']);
    });

    test('(l) bad inputs never throw and decide safely', () {
      const weirdCatalogue = [
        VaultPackDef(id: '', version: 1, files: [
          VaultFileDef(name: 'x', sizeBytes: 1),
        ]),
        VaultPackDef(id: 'neg_version', version: -1, files: [
          VaultFileDef(name: 'x', sizeBytes: 1),
        ]),
        packA,
      ];
      List<VaultAction> actions;
      actions = VaultPlanner.plan(
        catalogue: weirdCatalogue,
        manifest: null,
        diskFiles: const {
          'pack_a': {'a1.onnx': -50, 'a2.onnx': 200, '': 10},
        },
      );
      // Only pack_a survives validation; the negative disk size counts
      // as a mismatch, so a1 + a3 need repair.
      expect(actions.length, 1);
      final a = actions.single;
      expect(a.type, VaultActionType.repair);
      expect(a.files, ['a1.onnx', 'a3.txt']);
    });

    test('(l2) empty catalogue -> no actions', () {
      final actions = VaultPlanner.plan(
        catalogue: const [],
        manifest: null,
        diskFiles: const {'pack_a': diskAFull},
      );
      expect(actions, isEmpty);
    });
  });

  group('VaultPlanner.planMigration', () {
    test('all legacy files match -> adopt', () {
      final actions = VaultPlanner.planMigration(
        catalogue: const [packA],
        legacyFiles: const {'pack_a': diskAFull},
      );
      final a = actions.single;
      expect(a.type, VaultActionType.adopt);
      expect(a.files, ['a1.onnx', 'a2.onnx', 'a3.txt']);
    });

    test('some match -> repair with only the bad/missing files', () {
      final actions = VaultPlanner.planMigration(
        catalogue: const [packA],
        legacyFiles: const {
          'pack_a': {'a1.onnx': 100, 'a3.txt': 31},
        },
      );
      final a = actions.single;
      expect(a.type, VaultActionType.repair);
      expect(a.files, ['a2.onnx', 'a3.txt']);
    });

    test('none match -> download', () {
      final actions = VaultPlanner.planMigration(
        catalogue: const [packA],
        legacyFiles: const {
          'pack_a': {'a1.onnx': 1},
        },
      );
      expect(actions.single.type, VaultActionType.download);
    });

    test('no legacy files at all -> download', () {
      final actions = VaultPlanner.planMigration(
        catalogue: const [packC],
        legacyFiles: const {},
      );
      final a = actions.single;
      expect(a.type, VaultActionType.download);
      expect(a.files, ['c1.onnx', 'c2.onnx']);
    });

    test('ghost legacy packs are ignored', () {
      final actions = VaultPlanner.planMigration(
        catalogue: const [packB],
        legacyFiles: const {
          'pack_b': diskBFull,
          'ghost': {'g.bin': 1},
        },
      );
      expect(actions.length, 1);
      expect(actions.single.type, VaultActionType.adopt);
    });
  });

  group('VaultPlanner.buildManifest', () {
    test('records only fully-present packs, with catalogue version '
        'and def sizes', () {
      final m = VaultPlanner.buildManifest(
        catalogue: const [packA, packB, packC],
        diskFiles: const {
          'pack_a': diskAFull,
          'pack_b': {'b1.onnx': 499},
          'pack_c': diskCFull,
        },
      );
      expect(m.packs.length, 2);
      expect(m.packs['pack_a'], installed('pack_a', 2, diskAFull));
      expect(m.packs['pack_c'], installed('pack_c', 3, diskCFull));
      expect(m.packs.containsKey('pack_b'), isFalse);
    });

    test('a half-present pack is not recorded', () {
      final m = VaultPlanner.buildManifest(
        catalogue: const [packA],
        diskFiles: const {
          'pack_a': {'a1.onnx': 100, 'a2.onnx': 200},
        },
      );
      expect(m.packs, isEmpty);
    });

    test('extra files on disk do not block recording', () {
      final m = VaultPlanner.buildManifest(
        catalogue: const [packB],
        diskFiles: const {
          'pack_b': {'b1.onnx': 500, 'leftover.tmp': 3},
        },
      );
      expect(m.packs['pack_b'], installed('pack_b', 1, diskBFull));
    });

    test('never throws on bad input', () {
      final m = VaultPlanner.buildManifest(
        catalogue: const [packA],
        diskFiles: const {
          'pack_a': {'a1.onnx': -1},
        },
      );
      expect(m.packs, isEmpty);
    });

    test('built manifest feeds plan() back to all-keep', () {
      const disk = {'pack_a': diskAFull, 'pack_b': diskBFull};
      final m = VaultPlanner.buildManifest(
        catalogue: const [packA, packB],
        diskFiles: disk,
      );
      final actions = VaultPlanner.plan(
        catalogue: const [packA, packB],
        manifest: m,
        diskFiles: disk,
      );
      expect(actions.length, 2);
      expect(actions.every((a) => a.type == VaultActionType.keep), isTrue);
    });
  });

  group('equality and hashCode', () {
    test('VaultFileDef compares by value incl. sha256', () {
      const f1 = VaultFileDef(name: 'x', sizeBytes: 10, sha256: 'abc');
      const f2 = VaultFileDef(name: 'x', sizeBytes: 10, sha256: 'abc');
      const f3 = VaultFileDef(name: 'x', sizeBytes: 10);
      const f4 = VaultFileDef(name: 'x', sizeBytes: 11, sha256: 'abc');
      expect(f1, f2);
      expect(f1.hashCode, f2.hashCode);
      expect(f1, isNot(f3));
      expect(f1, isNot(f4));
    });

    test('VaultPackDef compares by value; file order matters', () {
      const p1 = VaultPackDef(id: 'p', version: 1, files: [
        VaultFileDef(name: 'a', sizeBytes: 1),
        VaultFileDef(name: 'b', sizeBytes: 2),
      ]);
      const p2 = VaultPackDef(id: 'p', version: 1, files: [
        VaultFileDef(name: 'a', sizeBytes: 1),
        VaultFileDef(name: 'b', sizeBytes: 2),
      ]);
      const pSwapped = VaultPackDef(id: 'p', version: 1, files: [
        VaultFileDef(name: 'b', sizeBytes: 2),
        VaultFileDef(name: 'a', sizeBytes: 1),
      ]);
      const pOtherVersion = VaultPackDef(id: 'p', version: 2, files: [
        VaultFileDef(name: 'a', sizeBytes: 1),
        VaultFileDef(name: 'b', sizeBytes: 2),
      ]);
      expect(p1, p2);
      expect(p1.hashCode, p2.hashCode);
      expect(p1, isNot(pSwapped));
      expect(p1, isNot(pOtherVersion));
    });

    test('VaultInstalledPack equality ignores map insertion order, '
        'hashCode agrees', () {
      final i1 = installed('p', 1, {'a': 1, 'b': 2, 'c': 3});
      final i2 = installed('p', 1, {'c': 3, 'a': 1, 'b': 2});
      final i3 = installed('p', 1, {'a': 1, 'b': 2, 'c': 4});
      final i4 = installed('p', 2, {'a': 1, 'b': 2, 'c': 3});
      expect(i1, i2);
      expect(i1.hashCode, i2.hashCode);
      expect(i1, isNot(i3));
      expect(i1, isNot(i4));
    });
  });

  group('VaultPackDef.totalBytes', () {
    test('sums the file sizes', () {
      expect(packA.totalBytes, 330);
      expect(packB.totalBytes, 500);
      expect(packC.totalBytes, 1500);
    });

    test('empty file list sums to zero', () {
      const empty = VaultPackDef(id: 'e', version: 1, files: []);
      expect(empty.totalBytes, 0);
    });

    test('is the literal sum of the def sizes (spec wording)', () {
      // The prompt defines totalBytes as "sum of file sizes" with no
      // filtering; the as-received code silently skipped
      // sizeBytes <= 0 entries. Pinned after the conformance fix in
      // the checked copy.
      const odd = VaultPackDef(id: 'odd', version: 1, files: [
        VaultFileDef(name: 'a', sizeBytes: 100),
        VaultFileDef(name: 'b', sizeBytes: 0),
        VaultFileDef(name: 'c', sizeBytes: -30),
      ]);
      expect(odd.totalBytes, 70);
    });
  });

  group('VaultActionType', () {
    test('has exactly the five spec values in spec order', () {
      expect(VaultActionType.values, [
        VaultActionType.keep,
        VaultActionType.download,
        VaultActionType.repair,
        VaultActionType.adopt,
        VaultActionType.refresh,
      ]);
    });
  });
}
