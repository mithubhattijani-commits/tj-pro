/// Projects hub (v1.4.0, mockup S2): one hub per section kind —
/// Video, Photo, News.
///
/// Layout: gradient New Project card, ASPECT RATIO chips, START FROM
/// (gallery pick | blank canvas), then MY PROJECTS — the locally
/// stored [ProjectEntry] list for this kind, with delete.
///
/// Starting or reopening a project opens the section's EXISTING
/// editor entry exactly as Home does today (the editors take no media
/// argument — they run their own pickers); the picked media path is
/// recorded on the entry so the hub list shows its thumbnail.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import '../theme.dart';
import 'package:image_picker/image_picker.dart';

import '../news/news_maker_screen.dart';
import '../photo/photo_editor_screen.dart';
import '../video/video_editor_screen.dart';
import 'project_store.dart';

/// Aspect-ratio choices shown as chips, in mockup order.
const List<(String, String)> _ratios = <(String, String)>[
  ('9:16', 'Reels'),
  ('16:9', 'YouTube'),
  ('1:1', 'Square'),
  ('4:5', 'Post'),
  ('4:3', 'Classic'),
];

class ProjectsHubScreen extends StatefulWidget {
  const ProjectsHubScreen({super.key, required this.kind});

  /// 'video' | 'photo' | 'news'
  final String kind;

  @override
  State<ProjectsHubScreen> createState() => _ProjectsHubScreenState();
}

class _ProjectsHubScreenState extends State<ProjectsHubScreen> {
  final ImagePicker _picker = ImagePicker();

  late String _ratio;
  List<ProjectEntry> _projects = <ProjectEntry>[];
  bool _busy = false;

  String get _kindLabel => switch (widget.kind) {
        'photo' => 'Photo',
        'news' => 'News',
        _ => 'Video',
      };

  @override
  void initState() {
    super.initState();
    _ratio = widget.kind == 'photo' ? '1:1' : '9:16';
    unawaited(_reload());
  }

  Future<void> _reload() async {
    await ProjectStore.instance.load();
    if (!mounted) {
      return;
    }
    setState(() => _projects = ProjectStore.instance.forKind(widget.kind));
  }

  /// Opens the section editor exactly as Home does today. When the
  /// project carries a media path, it is handed to the editors that
  /// accept one (v1.4.0): the photo editor loads it as the editing
  /// photo and the video editor loads it as the first timeline clip.
  /// News opens the workspace directly (Build 5, v1.5.7: the old
  /// News Studio hub screen is retired; the Maker workspace is the
  /// one News Studio home, and its project chooser is in its
  /// project bar).
  Widget _editor({String? mediaPath}) {
    return switch (widget.kind) {
      'photo' => PhotoEditorScreen(initialImagePath: mediaPath),
      'news' => const NewsMakerScreen(),
      _ => VideoEditorScreen(initialVideoPath: mediaPath),
    };
  }

  String _defaultTitle() {
    final DateTime now = DateTime.now();
    const List<String> months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '$_kindLabel Project — ${now.day} ${months[now.month - 1]}';
  }

  bool _isImagePath(String path) {
    final String p = path.toLowerCase();
    return p.endsWith('.jpg') ||
        p.endsWith('.jpeg') ||
        p.endsWith('.png') ||
        p.endsWith('.webp');
  }

  /// Creates the entry, opens the editor, and bumps `updatedAt` when
  /// the user comes back.
  Future<void> _startProject(String? mediaPath) async {
    final DateTime now = DateTime.now();
    final ProjectEntry entry = ProjectEntry(
      id: now.microsecondsSinceEpoch.toString(),
      kind: widget.kind,
      title: _defaultTitle(),
      ratioLabel: _ratio,
      mediaPath: mediaPath,
      thumbPath:
          (mediaPath != null && _isImagePath(mediaPath)) ? mediaPath : null,
      createdAt: now,
      updatedAt: now,
    );
    await ProjectStore.instance.add(entry);
    if (!mounted) {
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => _editor(mediaPath: mediaPath)),
    );
    await ProjectStore.instance
        .update(entry.copyWith(updatedAt: DateTime.now()));
    await _reload();
  }

  Future<void> _pickAndStart() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      XFile? file;
      if (widget.kind == 'photo') {
        file = await _picker.pickImage(source: ImageSource.gallery);
      } else if (widget.kind == 'video') {
        file = await _picker.pickVideo(source: ImageSource.gallery);
      } else {
        // News: the user chooses whether the project starts from a
        // video clip or a photo.
        final bool? wantVideo = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: const Text('Choose from gallery'),
            content: const Text('With which media should the news project start?'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Photo'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Video'),
              ),
            ],
          ),
        );
        if (wantVideo == null) {
          return;
        }
        file = wantVideo
            ? await _picker.pickVideo(source: ImageSource.gallery)
            : await _picker.pickImage(source: ImageSource.gallery);
      }
      if (file == null || !mounted) {
        return;
      }
      await _startProject(file.path);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _reopen(ProjectEntry entry) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (_) => _editor(mediaPath: entry.mediaPath)),
    );
    await ProjectStore.instance
        .update(entry.copyWith(updatedAt: DateTime.now()));
    await _reload();
  }

  Future<void> _confirmDelete(ProjectEntry entry) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Delete project?'),
        content: Text('“${entry.title}” will be removed from the hub.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ProjectStore.instance.delete(entry.id);
      await _reload();
    }
  }

  String _relativeTime(DateTime t) {
    final Duration d = DateTime.now().difference(t);
    if (d.inMinutes < 1) {
      return 'just now';
    }
    if (d.inMinutes < 60) {
      return '${d.inMinutes} min ago';
    }
    if (d.inHours < 24) {
      return '${d.inHours} hours ago';
    }
    if (d.inDays == 1) {
      return 'yesterday';
    }
    if (d.inDays < 7) {
      return '${d.inDays} days ago';
    }
    return '${t.day}/${t.month}/${t.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('$_kindLabel Projects')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          // New Project gradient card (tap = gallery start).
          InkWell(
            onTap: _busy ? null : () => unawaited(_pickAndStart()),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  colors: <Color>[Color(0xFFF43F5E), Color(0xFFFB923C)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'New Project',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'New $_kindLabel project — completely from scratch',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'ASPECT RATIO',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _ratios.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (BuildContext context, int i) {
                final (String label, String sub) = _ratios[i];
                final bool selected = label == _ratio;
                return ChoiceChip(
                  label: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        label,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(sub, style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                  selected: selected,
                  onSelected: (_) => setState(() => _ratio = label),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'START FROM',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _StartCard(
                  icon: Icons.image_outlined,
                  iconColor: const Color(0xFFF43F5E),
                  title: widget.kind == 'photo' ? 'Image' : 'Image / Video',
                  subtitle: 'Choose from gallery',
                  onTap: _busy ? null : () => unawaited(_pickAndStart()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StartCard(
                  icon: Icons.add_box_outlined,
                  iconColor: const Color(0xFF3B82F6),
                  title: 'Empty Background',
                  subtitle: 'Blank canvas se start',
                  onTap: _busy ? null : () => unawaited(_startProject(null)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'MY PROJECTS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 10),
          if (_projects.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No project yet — start a new project from above.',
                  style: TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            ..._projects.map(
              (ProjectEntry e) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ProjectTile(
                  entry: e,
                  editedLabel: 'Edited ${_relativeTime(e.updatedAt)}',
                  onTap: () => unawaited(_reopen(e)),
                  onDelete: () => unawaited(_confirmDelete(e)),
                ),
              ),
            ),
          // Build 5 (v1.5.7): the news hub's Live Studio card is
          // REMOVED — Live Studio's only door is Home's Live
          // Streaming banner (Join Now), per the user's ruling.
        ],
      ),
    );
  }
}

class _StartCard extends StatelessWidget {
  const _StartCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      subtitle,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({
    required this.entry,
    required this.editedLabel,
    required this.onTap,
    required this.onDelete,
  });

  final ProjectEntry entry;
  final String editedLabel;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  bool get _hasThumb {
    final String? p = entry.thumbPath ?? entry.mediaPath;
    if (p == null) {
      return false;
    }
    final String lower = p.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');
  }

  IconData get _kindIcon => switch (entry.kind) {
        'photo' => Icons.image,
        'news' => Icons.newspaper,
        _ => Icons.movie,
      };

  @override
  Widget build(BuildContext context) {
    final String? thumb = entry.thumbPath ?? entry.mediaPath;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 84,
                  height: 60,
                  child: _hasThumb && thumb != null
                      ? Image.file(
                          File(thumb),
                          fit: BoxFit.cover,
                          errorBuilder: (
                            BuildContext context,
                            Object error,
                            StackTrace? stackTrace,
                          ) =>
                              ColoredBox(
                            color: TjProTheme.motionPanelRaised,
                            child: Icon(_kindIcon, color: Colors.white70),
                          ),
                        )
                      : ColoredBox(
                          color: TjProTheme.motionPanelRaised,
                          child: Icon(_kindIcon, color: Colors.white70),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entry.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      editedLabel,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        _MiniChip(label: entry.ratioLabel, warm: true),
                        const SizedBox(width: 6),
                        const _MiniChip(label: 'Draft', warm: false),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                tooltip: 'Delete project',
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label, required this.warm});

  final String label;
  final bool warm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: warm ? const Color(0xFFFFEDD5) : const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: warm ? const Color(0xFF9A3412) : const Color(0xFF374151),
        ),
      ),
    );
  }
}
