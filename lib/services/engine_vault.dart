import 'dart:core';
import 'dart:convert';

class VaultFileDef {
  final String name;
  final int sizeBytes;
  final String? sha256;

  const VaultFileDef({
    required this.name,
    required this.sizeBytes,
    this.sha256,
  });

  @override
  bool operator ==(Object other) {
    return other is VaultFileDef &&
        other.name == name &&
        other.sizeBytes == sizeBytes &&
        other.sha256 == sha256;
  }

  @override
  int get hashCode => Object.hash(name, sizeBytes, sha256);
}

class VaultPackDef {
  final String id;
  final int version;
  final List<VaultFileDef> files;

  const VaultPackDef({
    required this.id,
    required this.version,
    required this.files,
  });

  int get totalBytes {
    int total = 0;

    for (final file in files) {
      total += file.sizeBytes;
    }

    return total;
  }

  @override
  bool operator ==(Object other) {
    if (other is! VaultPackDef ||
        other.id != id ||
        other.version != version ||
        other.files.length != files.length) {
      return false;
    }

    for (int i = 0; i < files.length; i++) {
      if (files[i] != other.files[i]) {
        return false;
      }
    }

    return true;
  }

  @override
  int get hashCode => Object.hash(
        id,
        version,
        Object.hashAll(files),
      );
}

class VaultInstalledPack {
  final String id;
  final int version;
  final Map<String, int> fileSizes;

  VaultInstalledPack({
    required this.id,
    required this.version,
    required this.fileSizes,
  });

  @override
  bool operator ==(Object other) {
    if (other is! VaultInstalledPack ||
        other.id != id ||
        other.version != version ||
        other.fileSizes.length != fileSizes.length) {
      return false;
    }

    for (final entry in fileSizes.entries) {
      if (other.fileSizes[entry.key] != entry.value ||
          !other.fileSizes.containsKey(entry.key)) {
        return false;
      }
    }

    return true;
  }

  @override
  int get hashCode {
    final entries = fileSizes.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Object.hash(
      id,
      version,
      Object.hashAll(
        entries.map((e) => Object.hash(e.key, e.value)),
      ),
    );
  }
}

class VaultManifest {
  final Map<String, VaultInstalledPack> packs;

  VaultManifest({
    required this.packs,
  });

  VaultManifest.empty() : packs = <String, VaultInstalledPack>{};

  String encode() {
    try {
      final Map<String, dynamic> encodedPacks = {};

      for (final entry in packs.entries) {
        final pack = entry.value;

        if (entry.key.isEmpty ||
            pack.id.isEmpty ||
            entry.key != pack.id ||
            pack.version < 0) {
          continue;
        }

        final Map<String, int> files = {};

        for (final file in pack.fileSizes.entries) {
          if (file.key.isNotEmpty && file.value >= 0) {
            files[file.key] = file.value;
          }
        }

        encodedPacks[entry.key] = {
          'id': pack.id,
          'version': pack.version,
          'fileSizes': files,
        };
      }

      return jsonEncode({
        'packs': encodedPacks,
      });
    } catch (_) {
      return '{"packs":{}}';
    }
  }

  static VaultManifest? tryDecode(String? json) {
    try {
      if (json == null || json.isEmpty) {
        return null;
      }

      final dynamic decoded = jsonDecode(json);

      if (decoded is! Map) {
        return null;
      }

      final dynamic rawPacks = decoded['packs'];

      if (rawPacks is! Map) {
        return null;
      }

      final Map<String, VaultInstalledPack> result = {};

      for (final entry in rawPacks.entries) {
        if (entry.key is! String ||
            (entry.key as String).isEmpty ||
            entry.value is! Map) {
          return null;
        }

        final String packId = entry.key as String;
        final Map rawPack = entry.value as Map;

        final dynamic rawId = rawPack['id'];
        final dynamic rawVersion = rawPack['version'];
        final dynamic rawSizes = rawPack['fileSizes'];

        if (rawId is! String ||
            rawId.isEmpty ||
            rawId != packId ||
            rawVersion is! int ||
            rawVersion < 0 ||
            rawSizes is! Map) {
          return null;
        }

        final Map<String, int> fileSizes = {};

        for (final file in rawSizes.entries) {
          if (file.key is! String ||
              (file.key as String).isEmpty ||
              file.value is! int ||
              file.value < 0) {
            return null;
          }

          fileSizes[file.key as String] = file.value as int;
        }

        result[packId] = VaultInstalledPack(
          id: packId,
          version: rawVersion,
          fileSizes: fileSizes,
        );
      }

      return VaultManifest(packs: result);
    } catch (_) {
      return null;
    }
  }
}

enum VaultActionType {
  keep,
  download,
  repair,
  adopt,
  refresh,
}

class VaultAction {
  final String packId;
  final VaultActionType type;
  final List<String> files;
  final String reason;

  const VaultAction({
    required this.packId,
    required this.type,
    required this.files,
    required this.reason,
  });
}

class VaultPlanner {
  VaultPlanner._();

  // ------------------------------------------------------------
  // INTERNAL VALIDATION HELPERS
  // ------------------------------------------------------------

  static bool _validPack(VaultPackDef? pack) {
    if (pack == null || pack.id.isEmpty || pack.version < 0) {
      return false;
    }

    return true;
  }

  static List<VaultFileDef> _validFiles(VaultPackDef pack) {
    final List<VaultFileDef> result = [];

    try {
      for (final file in pack.files) {
        if (file.name.isEmpty || file.sizeBytes < 0) {
          continue;
        }

        result.add(file);
      }
    } catch (_) {
      return result;
    }

    return result;
  }

  static Map<String, int> _safeDiskFiles(
    Map<String, Map<String, int>> diskFiles,
    String packId,
  ) {
    try {
      final dynamic raw = diskFiles[packId];

      if (raw is! Map) {
        return {};
      }

      final Map<String, int> result = {};

      for (final entry in raw.entries) {
        if (entry.key is String &&
            (entry.key as String).isNotEmpty &&
            entry.value is int &&
            entry.value >= 0) {
          result[entry.key as String] = entry.value as int;
        }
      }

      return result;
    } catch (_) {
      return {};
    }
  }

  static List<String> _allNames(VaultPackDef pack) {
    return _validFiles(pack)
        .map((file) => file.name)
        .toList(growable: false);
  }

  static List<String> _mismatchedFiles(
    VaultPackDef pack,
    Map<String, int> disk,
  ) {
    final List<String> result = [];

    for (final file in _validFiles(pack)) {
      final int? actualSize = disk[file.name];

      if (actualSize == null || actualSize != file.sizeBytes) {
        result.add(file.name);
      }
    }

    return result;
  }

  static bool _allFilesMatch(
    VaultPackDef pack,
    Map<String, int> disk,
  ) {
    final files = _validFiles(pack);

    if (files.isEmpty) {
      return true;
    }

    for (final file in files) {
      if (disk[file.name] != file.sizeBytes) {
        return false;
      }
    }

    return true;
  }

  static int _matchingFileCount(
    VaultPackDef pack,
    Map<String, int> disk,
  ) {
    int count = 0;

    for (final file in _validFiles(pack)) {
      if (disk[file.name] == file.sizeBytes) {
        count++;
      }
    }

    return count;
  }

  static VaultInstalledPack? _safeManifestRecord(
    VaultManifest? manifest,
    String packId,
  ) {
    try {
      if (manifest == null) {
        return null;
      }

      final dynamic record = manifest.packs[packId];

      if (record is! VaultInstalledPack ||
          record.id != packId ||
          record.version < 0) {
        return null;
      }

      return record;
    } catch (_) {
      return null;
    }
  }

  static VaultAction _action(
    VaultPackDef pack,
    VaultActionType type,
    List<String> files,
    String reason,
  ) {
    return VaultAction(
      packId: pack.id,
      type: type,
      files: List<String>.unmodifiable(files),
      reason: reason,
    );
  }

  // ------------------------------------------------------------
  // MAIN INSTALLATION PLANNER
  // ------------------------------------------------------------

  static List<VaultAction> plan({
    required List<VaultPackDef> catalogue,
    required VaultManifest? manifest,
    required Map<String, Map<String, int>> diskFiles,
  }) {
    final List<VaultAction> actions = [];

    try {
      for (final pack in catalogue) {
        if (!_validPack(pack)) {
          continue;
        }

        final List<String> allFiles = _allNames(pack);

        final Map<String, int> disk = _safeDiskFiles(
          diskFiles,
          pack.id,
        );

        final VaultInstalledPack? installed = _safeManifestRecord(
          manifest,
          pack.id,
        );

        final List<String> damaged = _mismatchedFiles(
          pack,
          disk,
        );

        final bool allMatch = damaged.isEmpty;

        // ------------------------------------------------------
        // CASE 1: No installation record.
        // ------------------------------------------------------

        if (installed == null) {
          if (disk.isEmpty) {
            actions.add(
              _action(
                pack,
                VaultActionType.download,
                allFiles,
                'Pack is not installed. Download all files.',
              ),
            );

            continue;
          }

          // No manifest record, but all files are present.
          if (allMatch) {
            actions.add(
              _action(
                pack,
                VaultActionType.adopt,
                allFiles,
                'Existing files match the catalogue. Adopt without downloading.',
              ),
            );

            continue;
          }

          // Some files are present but others are missing or damaged.
          final int matching = _matchingFileCount(pack, disk);

          if (matching > 0) {
            actions.add(
              _action(
                pack,
                VaultActionType.repair,
                damaged,
                'Existing pack is incomplete. Repair only missing or mismatched files.',
              ),
            );

            continue;
          }

          // Nothing matches the expected catalogue.
          actions.add(
            _action(
              pack,
              VaultActionType.download,
              allFiles,
              'No existing files match the catalogue. Download the complete pack.',
            ),
          );

          continue;
        }

        // ------------------------------------------------------
        // CASE 2: Installed version is older.
        // ------------------------------------------------------

        if (installed.version < pack.version) {
          actions.add(
            _action(
              pack,
              VaultActionType.refresh,
              allFiles,
              'Installed pack version is older. Refresh this pack only.',
            ),
          );

          continue;
        }

        // ------------------------------------------------------
        // CASE 3: Installed version is newer.
        // Never downgrade.
        // ------------------------------------------------------

        if (installed.version > pack.version) {
          actions.add(
            _action(
              pack,
              VaultActionType.keep,
              allFiles,
              'Installed pack version is newer. Downgrade is not allowed.',
            ),
          );

          continue;
        }

        // ------------------------------------------------------
        // CASE 4: Versions match and files are correct.
        // ------------------------------------------------------

        if (allMatch) {
          actions.add(
            _action(
              pack,
              VaultActionType.keep,
              allFiles,
              'Installed version and all file sizes match.',
            ),
          );

          continue;
        }

        // ------------------------------------------------------
        // CASE 5: Same version, but files are damaged/missing.
        // ------------------------------------------------------

        actions.add(
          _action(
            pack,
            VaultActionType.repair,
            damaged,
            'Installed version matches, but some files are missing or have incorrect sizes.',
          ),
        );
      }
    } catch (_) {
      // Never propagate malformed runtime input.
    }

    return actions;
  }

  // ------------------------------------------------------------
  // LEGACY STORAGE MIGRATION PLANNER
  // ------------------------------------------------------------

  static List<VaultAction> planMigration({
    required List<VaultPackDef> catalogue,
    required Map<String, Map<String, int>> legacyFiles,
  }) {
    final List<VaultAction> actions = [];

    try {
      for (final pack in catalogue) {
        if (!_validPack(pack)) {
          continue;
        }

        final List<String> allFiles = _allNames(pack);

        final Map<String, int> legacy = _safeDiskFiles(
          legacyFiles,
          pack.id,
        );

        final List<String> damaged = _mismatchedFiles(
          pack,
          legacy,
        );

        // Every expected file exists and matches.
        if (damaged.isEmpty) {
          actions.add(
            _action(
              pack,
              VaultActionType.adopt,
              allFiles,
              'All legacy files match. Adopt the existing pack without downloading.',
            ),
          );

          continue;
        }

        final int matching = _matchingFileCount(
          pack,
          legacy,
        );

        // Some expected files are already available.
        if (matching > 0) {
          actions.add(
            _action(
              pack,
              VaultActionType.repair,
              damaged,
              'Legacy pack is partially available. Repair only missing or mismatched files.',
            ),
          );

          continue;
        }

        // No usable legacy files.
        actions.add(
          _action(
            pack,
            VaultActionType.download,
            allFiles,
            'No legacy files match the catalogue. Download the complete pack.',
          ),
        );
      }
    } catch (_) {
      // Never propagate malformed runtime input.
    }

    return actions;
  }

  // ------------------------------------------------------------
  // MANIFEST BUILDER
  // ------------------------------------------------------------

  static VaultManifest buildManifest({
    required List<VaultPackDef> catalogue,
    required Map<String, Map<String, int>> diskFiles,
  }) {
    final Map<String, VaultInstalledPack> installedPacks = {};

    try {
      for (final pack in catalogue) {
        if (!_validPack(pack)) {
          continue;
        }

        final Map<String, int> disk = _safeDiskFiles(
          diskFiles,
          pack.id,
        );

        // Only fully installed packs are recorded.
        if (!_allFilesMatch(pack, disk)) {
          continue;
        }

        final Map<String, int> fileSizes = {};

        for (final file in _validFiles(pack)) {
          fileSizes[file.name] = file.sizeBytes;
        }

        installedPacks[pack.id] = VaultInstalledPack(
          id: pack.id,
          version: pack.version,
          fileSizes: fileSizes,
        );
      }
    } catch (_) {
      // Return whatever valid records were successfully built.
    }

    return VaultManifest(
      packs: installedPacks,
    );
  }
}
