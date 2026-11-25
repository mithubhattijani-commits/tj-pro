/// Clip picker list (Phase 4, shared by News Maker + AI News Maker).
///
/// Gallery videos via [ImagePicker.pickVideo] and multi-file video
/// pick via [FilePicker] (both real pickers — no fake clips). Items
/// reorder with drag handles and delete per item; duplicates are
/// skipped on add. Paths are plain file paths — the screens store
/// them in the project JSON, and Phase 7 hands them to the video
/// editor timeline + FFmpeg export.
///
/// v1.5.0 (#32): PHOTOS are pickable too (multi-image gallery pick)
/// — a photo path in the same list; the preview composites it into
/// the template's main area and the export turns it into a real
/// segment via photoClipCommand.
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../news_project.dart';
import 'template_media_preview.dart' show isPhotoMediaPath;

class ClipPickerList extends StatelessWidget {
  const ClipPickerList({
    super.key,
    required this.paths,
    required this.onChanged,
    this.unifiedPicker = false,
  });

  /// Clip file paths, in timeline order.
  final List<String> paths;

  /// Called with the new list after add / reorder / remove.
  final ValueChanged<List<String>> onChanged;

  /// Build 12 (point #14d): ONE unified media picker — a
  /// single "Media add karein" button that opens a source
  /// sheet (gallery video / files / photo) instead of three
  /// separate add buttons. The three sources, their keys and
  /// their handlers are exactly the same; only the entry
  /// point is unified. The News Maker passes true; the AI
  /// News Maker keeps the classic three-button row.
  final bool unifiedPicker;

  Future<void> _addFromGallery(BuildContext context) async {
    try {
      final picked = await ImagePicker().pickVideo(
        source: ImageSource.gallery,
      );
      if (picked == null) return;
      if (!context.mounted) return;
      _addPaths(context, [picked.path]);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Clip add nahi hua: $e')),
        );
      }
    }
  }

  Future<void> _addFromFiles(BuildContext context) async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.video,
      );
      final picked =
          files.map((f) => f.path).whereType<String>().toList();
      if (picked.isEmpty) return;
      if (!context.mounted) return;
      _addPaths(context, picked);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Clip add nahi hua: $e')),
        );
      }
    }
  }

  /// v1.5.0 (#32): photos from the gallery (multi-pick). Photo paths
  /// land in the same ordered list as videos — order = timeline
  /// order for preview + export.
  Future<void> _addPhotos(BuildContext context) async {
    try {
      final picked = await ImagePicker().pickMultiImage();
      if (picked.isEmpty) return;
      if (!context.mounted) return;
      _addPaths(context, picked.map((f) => f.path).toList());
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Photo add nahi hua: $e')),
        );
      }
    }
  }

  void _addPaths(BuildContext context, List<String> picked) {
    // Phase 9 cap: at most NewsProject.maxClips (20) clips — every
    // clip becomes a full normalised intermediate MP4 at export.
    // Extras are REPORTED, never silently dropped.
    final probe = NewsProject(id: '', clipPaths: List<String>.from(paths));
    final result = probe.addClips(picked);
    if (result.clips.length != paths.length) onChanged(result.clips);
    if (result.droppedByCap > 0 && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.droppedByCap} clip(s) add nahi hue — '
            'project mein zyada se zyada ${NewsProject.maxClips} '
            'clips ho sakte hain.',
          ),
        ),
      );
    }
  }

  /// Build 12 (point #14d): the unified picker's source
  /// sheet — the same three sources with the same keys, one
  /// door.
  Future<void> _showUnifiedSourceSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF12151C),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Media kahan se add karein?',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              ListTile(
                key: const Key('addClipGallery'),
                leading: const Icon(Icons.video_library_outlined),
                title: const Text('Gallery se video'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_addFromGallery(context));
                },
              ),
              ListTile(
                key: const Key('addClipFiles'),
                leading: const Icon(Icons.folder_open_outlined),
                title: const Text('Files se chunein'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_addFromFiles(context));
                },
              ),
              ListTile(
                key: const Key('addClipPhoto'),
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Photo add karein'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_addPhotos(context));
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (unifiedPicker)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('mediaAddButton'),
              onPressed: () => _showUnifiedSourceSheet(context),
              icon: const Icon(Icons.add_photo_alternate_outlined,
                  size: 19),
              label: const Text('Media add karein'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFFC800),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('addClipGallery'),
                  onPressed: () => _addFromGallery(context),
                  icon: const Icon(Icons.video_library),
                  label: const Text('Gallery se video'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('addClipFiles'),
                  onPressed: () => _addFromFiles(context),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Files se chunein'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('addClipPhoto'),
              onPressed: () => _addPhotos(context),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Photo add karein'),
            ),
          ),
        ],
        const SizedBox(height: 8),
        if (paths.isEmpty)
          const Text(
            'Abhi koi clip nahi — gallery ya files se video ya photo '
            'add karein; yehi template ke main area mein lagega.',
            style: TextStyle(color: Colors.grey),
          )
        else
          ReorderableListView.builder(
            key: const Key('clipReorderList'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: paths.length,
            onReorderItem: (oldIndex, newIndex) {
              final next = List<String>.from(paths);
              final item = next.removeAt(oldIndex);
              next.insert(newIndex, item);
              onChanged(next);
            },
            itemBuilder: (context, index) {
              final path = paths[index];
              final name = path.split('/').last;
              final isPhoto = isPhotoMediaPath(path);
              return Card(
                key: ValueKey(path),
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  leading: Icon(
                    isPhoto
                        ? Icons.image_outlined
                        : Icons.play_circle_outline,
                  ),
                  title: Text(
                    '${isPhoto ? 'Photo' : 'Clip'} ${index + 1} — $name',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.drag_handle, color: Colors.grey),
                      IconButton(
                        key: Key('removeClip-$index'),
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Clip hatayein',
                        onPressed: () {
                          final next = List<String>.from(paths)
                            ..removeAt(index);
                          onChanged(next);
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
