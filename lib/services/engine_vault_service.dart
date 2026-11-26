/// Engine Vault — service glue (v1.23.0).
///
/// The user's rule: AI engines/models download ONCE per device
/// and survive app updates; only a genuinely new or changed pack
/// ever downloads again, and a damaged file repairs only its own
/// pack. The pure decision core is [engine_vault.dart]
/// (`VaultPlanner` — no I/O, fully unit-tested); THIS service is
/// the thin I/O shell around it:
///
///   * [catalogue] derives the vault catalogue from the real
///     [ModelPackService] registry (single source of truth).
///   * [scanDiskIn] stats the pack folders into the planner's
///     `diskFiles` shape.
///   * [plan] / [planByPack] load the persisted manifest, scan
///     the disk and ask the planner what to do.
///   * [persistManifest] rescans after downloads and records
///     exactly the packs that verify complete on disk.
///
/// Storage: packs already live under `<app support>/model_packs/`
/// in one folder per pack id — that directory IS the vault root,
/// so existing
/// users keep their ~305 MB of packs and the first vault launch
/// ADOPTS them (zero re-download). The manifest sits next to the
/// pack folders as `engine_vault_manifest.json`. A missing or
/// corrupt manifest is safe by design: `VaultManifest.tryDecode`
/// returns null and the planner then adopts complete packs from
/// disk and repairs only broken files — corruption can never
/// cause a full re-download.
///
/// FAIL-SOFT everywhere: no method throws. Any error degrades to
/// "no plan" and callers fall back to the pre-vault behaviour
/// ([ModelPackService.isReady] / [ModelPackService.ensurePack]).
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'engine_vault.dart';
import 'model_pack_service.dart';

class EngineVaultService {
  EngineVaultService._();

  /// Manifest file name inside the vault root.
  static const String manifestFileName = 'engine_vault_manifest.json';

  /// The vault catalogue, derived from the [ModelPackService]
  /// registry. Pure — unit-tested.
  ///
  /// Only files with a pinned size (`expectedBytes > 0`) join the
  /// exact-size catalogue. A future file whose size is not pinned
  /// yet stays OUT of the catalogue (it can never match an exact
  /// size and would repair-loop on every launch); it remains
  /// covered by [ModelPackService.isReady]'s non-empty check,
  /// which the prep flow still applies to keep/adopt packs.
  static List<VaultPackDef> catalogue() {
    return <VaultPackDef>[
      for (final pack in ModelPackService.packs)
        VaultPackDef(
          id: pack.id,
          version: pack.vaultVersion,
          files: <VaultFileDef>[
            for (final f in pack.files)
              if (f.expectedBytes > 0)
                VaultFileDef(name: f.name, sizeBytes: f.expectedBytes),
          ],
        ),
    ];
  }

  /// Stats [catalogue] packs under [root] into the planner's
  /// `diskFiles` shape: packId → (fileName → sizeBytes). Only
  /// catalogue files are stat'ed; `*.part` partial downloads are
  /// never catalogue names, so they can never pose as real files.
  /// A missing pack directory yields an empty entry. Never throws.
  static Future<Map<String, Map<String, int>>> scanDiskIn(
    Directory root,
    List<VaultPackDef> catalogue,
  ) async {
    final result = <String, Map<String, int>>{};
    for (final pack in catalogue) {
      final sizes = <String, int>{};
      try {
        final dir = Directory(p.join(root.path, pack.id));
        if (await dir.exists()) {
          for (final def in pack.files) {
            try {
              final file = File(p.join(dir.path, def.name));
              if (await file.exists()) {
                sizes[def.name] = await file.length();
              }
            } catch (_) {
              // One unreadable file must not sink the whole scan.
            }
          }
        }
      } catch (_) {
        // Keep the (possibly partial) entry; the planner decides.
      }
      result[pack.id] = sizes;
    }
    return result;
  }

  /// Reads + decodes the manifest under [root]; null when the
  /// file is missing, unreadable or corrupt (all safe — the
  /// planner adopts from disk). Never throws.
  static Future<VaultManifest?> loadManifestIn(Directory root) async {
    try {
      final file = File(p.join(root.path, manifestFileName));
      if (!await file.exists()) return null;
      return VaultManifest.tryDecode(await file.readAsString());
    } catch (_) {
      return null;
    }
  }

  /// Rescans [root], builds the truthful manifest (only packs
  /// whose files ALL verify on disk are recorded) and writes it
  /// under [root]. Returns the manifest that was written, or null
  /// on failure. Never throws.
  static Future<VaultManifest?> persistManifestIn(
    Directory root,
    List<VaultPackDef> catalogue,
  ) async {
    try {
      final disk = await scanDiskIn(root, catalogue);
      final manifest = VaultPlanner.buildManifest(
        catalogue: catalogue,
        diskFiles: disk,
      );
      final file = File(p.join(root.path, manifestFileName));
      await file.writeAsString(manifest.encode(), flush: true);
      return manifest;
    } catch (_) {
      return null;
    }
  }

  /// One full planning pass against the real vault root: load
  /// manifest → scan disk → [VaultPlanner.plan]. An empty list
  /// means "no plan could be computed" — callers fall back to the
  /// pre-vault per-pack checks. Never throws.
  static Future<List<VaultAction>> plan() async {
    try {
      final root = await ModelPackService.instance.packsRoot();
      final cat = catalogue();
      final manifest = await loadManifestIn(root);
      final disk = await scanDiskIn(root, cat);
      return VaultPlanner.plan(
        catalogue: cat,
        manifest: manifest,
        diskFiles: disk,
      );
    } catch (_) {
      return const <VaultAction>[];
    }
  }

  /// [plan] indexed by pack id for per-item lookups.
  static Future<Map<String, VaultAction>> planByPack() async {
    final actions = await plan();
    return <String, VaultAction>{
      for (final a in actions) a.packId: a,
    };
  }

  /// Persists the manifest at the real vault root after downloads
  /// (records exactly the packs that now verify complete).
  /// Never throws.
  static Future<void> persistManifest() async {
    try {
      final root = await ModelPackService.instance.packsRoot();
      await persistManifestIn(root, catalogue());
    } catch (_) {
      // The manifest is an optimisation over disk truth; losing
      // one write only means the next launch re-derives it by
      // adopting from disk — never a re-download.
    }
  }
}
