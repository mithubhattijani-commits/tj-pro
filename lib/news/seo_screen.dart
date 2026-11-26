/// SEO step (Phase 4, mockup 7 + §12).
///
/// Flow stepper: Edit ✓ → Finalize ✓ → SEO → Publish. The SEO step
/// lives inside the editor flow — title (hook first, /100), description,
/// hashtags (5–6, English/Roman only), keywords, follow line, X 280-char
/// warning, no-links note. Save persists the SEO fields into the
/// shared project JSON.
///
/// "Suggested — tap to add": calls POST /trends-suggest (see
/// lib/news/trends_service.dart). STATUS: that endpoint does NOT exist
/// yet (verified 20 Nov 2026 — Worker answers 404), so the section
/// shows "Suggestions unavailable — manually likhein" until it lands.
/// Suggestions are NEVER invented — an empty suggestion is correct.
///
/// Publish is PARKED (master prompt §15 / publishing track): the
/// button saves the SEO and says so — there is no Publish action
/// here until the publishing build lands.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/gemini_voice_service.dart';
import 'news_analysis.dart';
import 'news_project.dart';
import 'trends_service.dart';

class SeoScreen extends StatefulWidget {
  /// The project whose SEO is edited. The screen writes the SEO
  /// fields back into it and saves the project JSON on Save.
  const SeoScreen({super.key, required this.project});

  final NewsProject project;

  @override
  State<SeoScreen> createState() => _SeoScreenState();
}

class _SeoScreenState extends State<SeoScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _keywordsController;
  late final TextEditingController _followController;
  final _hashtagController = TextEditingController();

  late List<String> _hashtags;
  String _hashtagError = '';

  TrendsResult? _suggestions;
  bool _suggestionsLoading = false;

  bool _saving = false;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    final seo = widget.project.seo;
    _titleController = TextEditingController(
      text: seo.title.isEmpty ? widget.project.headline : seo.title,
    );
    _descriptionController = TextEditingController(
      text: seo.description.isEmpty ? widget.project.summary : seo.description,
    );
    _keywordsController = TextEditingController(text: seo.keywords);
    _followController = TextEditingController(text: seo.followLine);
    _hashtags = List<String>.from(seo.hashtags);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _keywordsController.dispose();
    _followController.dispose();
    _hashtagController.dispose();
    _saveTimer?.cancel();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Live caption preview + X cut, from the current fields.
  String get _caption => buildCaption(
        title: _titleController.text,
        description: _descriptionController.text,
        hashtags: _hashtags,
        followLine: _followController.text,
      );

  String get _xCut => xCaption(
        title: _titleController.text,
        hashtags: _hashtags,
      );

  Future<void> _refreshSuggestions() async {
    final text = widget.project.tehreer.isNotEmpty
        ? widget.project.tehreer
        : _titleController.text;
    if (text.trim().isEmpty) {
      _showMessage('Write the script or title first.');
      return;
    }
    setState(() {
      _suggestionsLoading = true;
      _suggestions = null;
    });
    final result = await TrendsService.fetchSuggestions(
      text: text,
      lang: GeminiVoiceService.detectLang(text),
    );
    if (!mounted) return;
    setState(() {
      _suggestionsLoading = false;
      _suggestions = result;
    });
  }

  void _addHashtag(String raw) {
    var tag = raw.trim();
    if (tag.isEmpty) return;
    if (!tag.startsWith('#')) tag = '#$tag';
    tag = tag.replaceAll(RegExp(r'\s+'), '');
    if (!isRomanHashtag(tag)) {
      setState(
        () => _hashtagError =
            '"$tag" — only English/Roman letters allowed (no Urdu script).',
      );
      return;
    }
    if (_hashtags.contains(tag)) {
      setState(() => _hashtagError = '"$tag" already exists.');
      return;
    }
    setState(() {
      _hashtagError = '';
      _hashtags.add(tag);
      _hashtagController.clear();
    });
  }

  Future<void> _saveSeo() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final seo = widget.project.seo;
      seo.title = _titleController.text.trim();
      seo.description = _descriptionController.text.trim();
      seo.hashtags = List<String>.from(_hashtags);
      seo.keywords = _keywordsController.text.trim();
      seo.followLine = _followController.text.trim();
      await NewsProjectStore.save(widget.project);
      _showMessage(
        'SEO saved — Publish (parked) will come later.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7C3AED),
          secondary: Color(0xFF7C3AED),
        ),
        scaffoldBackgroundColor: const Color(0xFF080810),
        cardColor: const Color(0xFF181828),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('SEO — Finalize'),
          backgroundColor: const Color(0xFF080810),
        ),
        body: ListView(
          key: const Key('seoList'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            Text(
              '${widget.project.title.isEmpty ? widget.project.headline.isEmpty ? 'Project' : widget.project.headline : widget.project.title} • Step 3 of 4',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            _buildStepper(),
            const SizedBox(height: 20),
            _sectionTitle('Title (hook first)'),
            const SizedBox(height: 8),
            TextField(
              key: const Key('seoTitleField'),
              controller: _titleController,
              maxLines: 2,
              minLines: 1,
              decoration: InputDecoration(
                hintText: 'Hook first — write the title here…',
                border: const OutlineInputBorder(),
                counterText:
                    '${_titleController.text.length} / 100',
                counterStyle: TextStyle(
                  color: _titleController.text.length > 100
                      ? Colors.red
                      : Colors.grey,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_titleController.text.length > 100)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'The title is over 100 chars (YouTube cap) — make it shorter.',
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
            const SizedBox(height: 16),
            _sectionTitle('Description'),
            const SizedBox(height: 8),
            TextField(
              key: const Key('seoDescriptionField'),
              controller: _descriptionController,
              maxLines: 4,
              minLines: 3,
              decoration: const InputDecoration(
                hintText: 'Hook first line, then the story… (no link)',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            _sectionTitle('Hashtags (5–6, trending, English/Roman only)'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ..._hashtags.map(
                  (tag) => InputChip(
                    key: Key('hashtag-$tag'),
                    label: Text(tag),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => setState(() => _hashtags.remove(tag)),
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: TextField(
                    key: const Key('hashtagAddField'),
                    controller: _hashtagController,
                    decoration: const InputDecoration(
                      hintText: 'Add #tag',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                    onSubmitted: _addHashtag,
                  ),
                ),
              ],
            ),
            if (_hashtagError.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _hashtagError,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
            ...hashtagProblems(_hashtags).map(
              (p) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  p,
                  style: const TextStyle(color: Colors.amber, fontSize: 12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildSuggestions(),
            const SizedBox(height: 16),
            _sectionTitle('Keywords'),
            const SizedBox(height: 8),
            TextField(
              key: const Key('seoKeywordsField'),
              controller: _keywordsController,
              decoration: const InputDecoration(
                hintText: 'Sheikhupura police, liquor, arrest, Punjab',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            _sectionTitle('Follow line (at the end)'),
            const SizedBox(height: 8),
            TextField(
              key: const Key('seoFollowField'),
              controller: _followController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            if (_caption.length > 280)
              Card(
                color: const Color(0xFF2A1A1A),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '⚠ X: ${_caption.length} chars — the caption will be short',
                        key: const Key('xWarning'),
                        style: const TextStyle(
                          color: Colors.amber,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'X cut: $_xCut',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const Text(
              'No link in the caption — links only in comments',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Caption preview • ${_caption.length} chars',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _caption.isEmpty ? '—' : _caption,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('saveSeoButton'),
                onPressed: _saving ? null : _saveSeo,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(
                  _saving ? 'Saving…' : 'Save SEO',
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Publish (5 platforms) is parked — applications are pending '
              'they are. The SEO is saved and stays in the project JSON.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    );
  }

  /// Flow stepper: Edit ✓ → Finalize ✓ → SEO → Publish.
  Widget _buildStepper() {
    Widget step(String label, Widget circle, {bool done = false}) {
      return Column(
        children: [
          circle,
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: done ? Colors.white : Colors.grey,
              fontWeight: done ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ],
      );
    }

    Widget circle(String text, {bool done = false, bool current = false}) {
      final color = done
          ? const Color(0xFF7C3AED)
          : current
              ? const Color(0xFF7C3AED)
              : Colors.white24;
      return Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    const line = Expanded(
      child: Padding(
        padding: EdgeInsets.only(bottom: 20),
        child: Divider(color: Colors.white24, thickness: 2),
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        step('Edit', circle('✓', done: true), done: true),
        line,
        step('Finalize', circle('✓', done: true), done: true),
        line,
        step('SEO', circle('3', current: true), done: true),
        line,
        step('Publish', circle('4')),
      ],
    );
  }

  /// "Suggested — tap to add" section. States: idle (never fetched),
  /// loading, unavailable (endpoint 404 / error — manual entry), and
  /// loaded (tap a chip to add it; each chip shows its source).
  Widget _buildSuggestions() {
    final result = _suggestions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '✦ Trending suggestions',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFB794F6),
                ),
              ),
            ),
            TextButton.icon(
              key: const Key('suggestionsRefresh'),
              onPressed: _suggestionsLoading ? null : _refreshSuggestions,
              icon: _suggestionsLoading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 16),
              label: const Text('Refresh'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Suggested — tap to add',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (_suggestionsLoading)
          const Text(
            'Live check is running…',
            style: TextStyle(color: Colors.grey),
          )
        else if (result == null)
          const Text(
            'Tap Refresh — a live check will run from Google Trends + X.',
            style: TextStyle(color: Colors.grey),
          )
        else if (!result.available)
          Card(
            key: const Key('suggestionsUnavailable'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Suggestions unavailable — write manually\n'
                '(${result.reason ?? 'endpoint abhi live nahi'})',
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          )
        else if (result.suggestion!.hashtags.isEmpty &&
            result.suggestion!.keywords.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'No trending tag found for this topic — write manually.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: result.suggestion!.hashtags.map((tag) {
                  return ActionChip(
                    key: Key('suggested-$tag'),
                    label: Text('+ $tag'),
                    onPressed: () => _addHashtag(tag),
                  );
                }).toList(),
              ),
              if (result.suggestion!.keywords.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: result.suggestion!.keywords.map((kw) {
                    return ActionChip(
                      key: Key('suggested-kw-$kw'),
                      label: Text('+ $kw'),
                      onPressed: () {
                        final current = _keywordsController.text.trim();
                        setState(() {
                          _keywordsController.text = current.isEmpty
                              ? kw
                              : '$current, $kw';
                        });
                      },
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                'Live check: ${result.suggestion!.sources.isEmpty ? 'Google Trends + X' : result.suggestion!.sources.join(' + ')}'
                ' • Extracted from the script',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
      ],
    );
  }
}
