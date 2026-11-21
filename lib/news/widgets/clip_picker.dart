/// Clip picker list (Phase 4, shared by News Maker + AI News Maker).
///
/// Gallery videos via [ImagePicker.pickVideo] and multi-file video
/// pick via [FilePicker] (both real pickers — no fake clips). Items
/// reorder with drag handles and delete per item; duplicates are
/// skipped on add. Paths are plain file paths — the screens store
/// them in the project JSON, and Phase 7 hands them to the video
/// editor timeline + FFmpeg export.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../news_project.dart';

class ClipPickerList extends StatelessWidget {
  const ClipPickerList({
    super.key,
    required this.paths,
    required this.onChanged,
  });

  /// Clip file paths, in timeline order.
  final List<String> paths;

  /// Called with the new list after add / reorder / remove.
  final ValueChanged<List<String>> onChanged;

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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        if (paths.isEmpty)
          const Text(
            'Abhi koi clip nahi — gallery ya files se video add karein.',
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
              return Card(
                key: ValueKey(path),
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  leading: const Icon(Icons.play_circle_outline),
                  title: Text(
                    'Clip ${index + 1} — $name',
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
