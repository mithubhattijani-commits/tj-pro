// The panels are an extension on the editor's State class by design
// (part-file pattern), so calling the State's protected setState from
// here is intentional.
// ignore_for_file: invalid_use_of_protected_member
part of 'video_editor_screen.dart';

/// Tool panels for the video editor (one-build regroup).
///
/// These methods live in a part file purely so each file stays
/// a manageable size; they are the same library as
/// `video_editor_screen.dart`, and the extension form keeps
/// every call site in the screen unchanged. Behaviour is
/// identical to when they were inline in the State class.
extension _VideoEditorPanels on _VideoEditorScreenState {
  /// Section title inside a regrouped tab panel (one-build UI):
  /// violet accent bar + bold label, matching the approved mockups.
  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: TjProTheme.violet,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// A legacy panel's body with its own leading title dropped — the
  /// tab's section titles (and the panel header) name it now.
  List<Widget> _panelBody(String key) {
    final items = List<Widget>.of(_legacyPanelChildren(key));
    if (items.length > 1 && items[0] is Text && items[1] is SizedBox) {
      items.removeRange(0, 2);
    }
    return items;
  }

  /// v1.3.0 (§3/§5A): every tool panel is split into SUB-TABS —
  /// only the active sub-tab's controls are on screen, ever. The
  /// tab list per tool (the panel header renders these as chips).
  List<(String, String)> _panelTabs() {
    switch (_activeTool) {
      case 'canvas':
        return const [
          ('ratio', 'Ratio'),
          ('zoom', 'Zoom'),
          ('background', 'Background'),
        ];
      case 'precut':
        return const [
          ('trim', 'Trim'),
          ('cut', 'Cut'),
          ('split', 'Split'),
        ];
      case 'speed':
        return const [
          ('standard', 'Standard'),
          ('curve', 'Curve'),
          ('beat', 'Beat'),
        ];
      case 'audio':
        return const [
          ('music', 'Music'),
          ('voice', 'Voice'),
          ('clean', 'Clean'),
        ];
      case 'text':
        return const [
          ('text', 'Text'),
          ('titles', 'Titles'),
          ('captions', 'Captions'),
        ];
      case 'colour':
        return const [
          ('filters', 'Filters'),
          ('adjust', 'Adjust'),
        ];
      case 'effects':
        return const [
          ('effects', 'Effects'),
          ('tracking', 'Tracking'),
        ];
      case 'overlay':
        return const [
          ('sticker', 'Sticker'),
          ('keyframes', 'Keyframes'),
          ('pip', 'PIP'),
        ];
      case 'news':
        return const [
          ('template', 'Template'),
          ('text', 'Text'),
          ('logo', 'Logo'),
        ];
      default:
        return const [];
    }
  }

  /// The active sub-tab key (falls back to the tool's first tab).
  String get _currentTab {
    final tabs = _panelTabs();
    if (tabs.isEmpty) return '';
    final t = _panelTab;
    if (t != null && tabs.any((e) => e.$1 == t)) return t;
    return tabs.first.$1;
  }

  /// Icon for a (tool, sub-tab) pair — the global UI rule (user
  /// order 22 Nov 2026): every sub-option carries its own small
  /// related icon, never bare text alone.
  IconData _tabIcon(String tool, String tab) {
    switch ((tool, tab)) {
      case ('canvas', 'ratio'):
        return Icons.aspect_ratio;
      case ('canvas', 'zoom'):
        return Icons.zoom_in;
      case ('canvas', 'background'):
        return Icons.wallpaper;
      case ('precut', 'trim'):
        return Icons.content_cut;
      case ('precut', 'cut'):
        return Icons.cut;
      case ('precut', 'split'):
        return Icons.call_split;
      case ('speed', 'standard'):
        return Icons.speed;
      case ('speed', 'curve'):
        return Icons.show_chart;
      case ('speed', 'beat'):
        return Icons.music_note;
      case ('audio', 'music'):
        return Icons.music_note;
      case ('audio', 'voice'):
        return Icons.mic;
      case ('audio', 'clean'):
        return Icons.cleaning_services;
      case ('text', 'text'):
        return Icons.text_fields;
      case ('text', 'titles'):
        return Icons.title;
      case ('text', 'captions'):
        return Icons.closed_caption;
      case ('colour', 'filters'):
        return Icons.photo_filter;
      case ('colour', 'adjust'):
        return Icons.tune;
      case ('effects', 'effects'):
        return Icons.auto_awesome;
      case ('effects', 'tracking'):
        return Icons.gps_fixed;
      case ('overlay', 'sticker'):
        return Icons.emoji_emotions;
      case ('overlay', 'keyframes'):
        return Icons.animation;
      case ('overlay', 'pip'):
        return Icons.picture_in_picture_alt;
      case ('overlay', 'background'):
        return Icons.wallpaper;
      case ('news', 'template'):
        return Icons.newspaper;
      case ('news', 'text'):
        return Icons.text_fields;
      case ('news', 'logo'):
        return Icons.image;
      default:
        return Icons.circle_outlined;
    }
  }

  /// The sub-tab row under the panel header (§3): ONE horizontal
  /// swipeable line of icon+label items (global UI rule) — the
  /// same visual language as the main tool rail.
  Widget _panelTabRow() {
    final tabs = _panelTabs();
    if (tabs.length < 2) return const SizedBox.shrink();
    final current = _currentTab;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: _iconChoiceRail([
        for (final t in tabs)
          _iconChoiceItem(
            icon: _tabIcon(_activeTool ?? '', t.$1),
            label: t.$2,
            selected: current == t.$1,
            onTap: () => setState(() => _panelTab = t.$1),
          ),
      ]),
    );
  }

  /// Index of the first widget matching [test], or -1. Used to
  /// split a legacy panel body at a section anchor (the widgets
  /// themselves are preserved exactly — only re-homed, §5).
  int _anchorIndex(List<Widget> items, bool Function(Widget) test) {
    for (var i = 0; i < items.length; i++) {
      if (test(items[i])) return i;
    }
    return -1;
  }

  bool _isTextStarting(Widget w, String prefix) =>
      w is Text && (w.data ?? '').startsWith(prefix);

  /// Index of the _sectionTitle whose text starts with [part], or
  /// -1 (v1.5.0 — section anchors for the Canvas / Precut splits).
  int _sectionAnchor(List<Widget> items, String part) {
    return _anchorIndex(items, (w) {
      if (w is Padding && w.child is Row) {
        for (final c in (w.child as Row).children) {
          if (c is Text && (c.data ?? '').startsWith(part)) return true;
        }
      }
      return false;
    });
  }

  /// v1.5.0 dispatch: ONE panel per tool key (the flat InShot row
  /// opens these directly). Legacy bodies are reused by slice —
  /// every legacy control stays reachable exactly once.
  List<Widget> _toolPanelChildren() {
    switch (_activeTool) {
      case 'canvas':
        switch (_currentTab) {
          case 'zoom':
            return _transformTabChildren();
          case 'background':
            return _canvasBackgroundChildren();
          default:
            return _canvasRatioChildren();
        }
      case 'precut':
        switch (_currentTab) {
          case 'cut':
            return _cutTabChildren();
          case 'split':
            return _splitTabChildren();
          default:
            return _precutTrimChildren();
        }
      case 'speed':
        switch (_currentTab) {
          case 'curve':
            return _speedCurveChildren();
          case 'beat':
            return _panelBody('beats');
          default:
            return _speedStandardChildren();
        }
      case 'audio':
        final body = _panelBody('audio');
        final voiceIdx =
            _anchorIndex(body, (w) => _isTextStarting(w, 'Voice changer'));
        final cleanIdx =
            _anchorIndex(body, (w) => _isTextStarting(w, 'Cleanup'));
        final v = voiceIdx < 0 ? body.length : voiceIdx;
        var c = cleanIdx < 0 ? body.length : cleanIdx;
        if (c < v) c = v;
        switch (_currentTab) {
          case 'voice':
            return body.sublist(v, c);
          case 'clean':
            return body.sublist(c);
          default:
            return [
              ...body.sublist(0, v),
              ..._musicExtras(),
              const Divider(height: 32),
              ListTile(
                leading: const Icon(Icons.build_circle_outlined),
                title: const Text('More audio tools'),
                subtitle: const Text('Converter, trimmer, joiner, extract'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AudioToolsScreen(),
                    ),
                  );
                },
              ),
            ];
        }
      case 'text':
        switch (_currentTab) {
          case 'titles':
            return _panelBody('titles');
          case 'captions':
            return [
              ..._panelBody('captions'),
              _sectionTitle('Urdu (AI) captions'),
              const Text(
                'Shruti Urdu AI model (on-device) se Urdu captions — '
                'Whisper wale option se alag, Urdu ke liye trained. '
                'Model pack pehli dafa download hota hai.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (_transcribing || _busy)
                      ? null
                      : _generateUrduCaptions,
                  icon: const Icon(Icons.closed_caption, size: 18),
                  label: Text(
                    _transcribing
                        ? 'Captions ban rahe hain…'
                        : 'Urdu (AI) captions banayein',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.translate),
                title: const Text('Translate captions'),
                subtitle: const Text('Caption Translator (ML Kit)'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CaptionTranslatorScreen(
                        initialSegments: _captions,
                        fromLang: _captionLocale,
                        toLang: _captionLocale == 'ur' ? 'en' : 'ur',
                      ),
                    ),
                  );
                },
              ),
            ];
          default:
            return _panelBody('text');
        }
      case 'colour':
        return _currentTab == 'adjust'
            ? _adjustPanelChildren()
            : _legacyPanelChildren('filtersRow');
      case 'volume':
      case 'clipVolume':
        return _volumePanelChildren();
      case 'effects':
        return _currentTab == 'tracking'
            ? _panelBody('tracking')
            : _panelBody('effects');
      case 'overlay':
        switch (_currentTab) {
          case 'keyframes':
            return _keyframesTabChildren();
          case 'pip':
            return [
              ..._panelBody('overlays'),
              ..._pipExtras(),
            ];
          default:
            return _stickerTabChildren();
        }
      case 'aicut':
        return _aiCutChildren();
      case 'voiceenhance':
        return _voiceEnhanceChildren();
      case 'edit':
        return _transformTabChildren();
      case 'enhance':
        return _enhancePanelChildren();
      case 'stabilizer':
        return _stabilizerPanelChildren();
      case 'cutout':
        return _cutoutPanelChildren();
      case 'mask':
        return _maskPanelChildren();
      case 'opacity':
        return _opacityPanelChildren();
      case 'rotate':
        return _rotatePanelChildren();
      case 'ease':
        return _easePanelChildren();
      case 'transitions':
        return _transitionsPanelChildren();
      case 'news':
        switch (_currentTab) {
          case 'text':
            return _legacyPanelChildren('newsText');
          case 'logo':
            return _legacyPanelChildren('newsLogo');
          default:
            return _legacyPanelChildren('newsTemplate');
        }
      default:
        return _legacyPanelChildren('text');
    }
  }

  // ---- v1.5.0 panels ----

  /// Canvas › Ratio: the Canvas section of the old Trim tab (the
  /// aspect rail), sliced at its section anchors.
  List<Widget> _canvasRatioChildren() {
    final body = _trimTabChildren();
    final canvasIdx = _sectionAnchor(body, 'Canvas');
    if (canvasIdx < 0) return body;
    final fillIdx = _anchorIndex(
      body,
      (w) => w is Text && w.data == 'Fill',
    );
    final end = fillIdx > canvasIdx ? fillIdx : body.length;
    return body.sublist(canvasIdx, end);
  }

  /// Canvas › Background: the SAME Canvas section's Fill part
  /// (Crop / Blur / Colour + fill colours). InShot's GRADIENT fill
  /// is not supported by the export's canvas fill — the note in
  /// the panel says so (PARTIAL, see the test report).
  List<Widget> _canvasBackgroundChildren() {
    final body = _trimTabChildren();
    final fillIdx = _anchorIndex(
      body,
      (w) => w is Text && w.data == 'Fill',
    );
    final introIdx = _sectionAnchor(body, 'Intro / outro');
    if (fillIdx < 0) return const [];
    final end = introIdx > fillIdx ? introIdx : body.length;
    return [
      _sectionTitle('Canvas background'),
      ...body.sublist(fillIdx, end),
      const Text(
        'Gradient fill abhi supported nahi — Blur ya Colour chunein.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const Divider(height: 32),
    ];
  }

  /// Precut › Trim: the old Trim tab's trim section (RangeSlider +
  /// fine sliders) + frame-step buttons + the timeline Zoom toggle
  /// (InShot's "Zoom Selection").
  List<Widget> _precutTrimChildren() {
    final body = _trimTabChildren();
    final canvasIdx = _sectionAnchor(body, 'Canvas');
    final trimPart = canvasIdx < 0 ? body : body.sublist(0, canvasIdx);
    return [
      ...trimPart,
      _sectionTitle('Frame step'),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => unawaited(
                        _seekToGlobalSec(_globalPositionSec - 1 / 30),
                      ),
              icon: const Icon(Icons.skip_previous, size: 18),
              label: const Text('Previous Frame'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => unawaited(
                        _seekToGlobalSec(_globalPositionSec + 1 / 30),
                      ),
              icon: const Icon(Icons.skip_next, size: 18),
              label: const Text('Next Frame'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      _iconChoiceRail([
        _iconChoiceItem(
          icon: Icons.zoom_in,
          label: 'Zoom Selection (timeline 2x)',
          selected: _tlPxPerSec > 50,
          onTap: () => setState(() => _tlPxPerSec = _tlPxPerSec > 50 ? 42 : 84),
        ),
      ]),
      const Divider(height: 32),
    ];
  }

  /// Precut › Cut: choose a range INSIDE the selected clip and
  /// remove it — the clip becomes two clips (before / after).
  List<Widget> _cutTabChildren() {
    final clip = _clips.isEmpty ? null : _clips[_selected];
    if (clip == null) {
      return const [
        Text(
          'Pehle timeline se clip select karein.',
          style: TextStyle(color: Colors.grey),
        ),
      ];
    }
    final start = clip.trimStart;
    final end = clip.effectiveEnd;
    final cutStart = _cutStart.clamp(start, end);
    final cutEnd = _cutEnd.clamp(start, end);
    return [
      _sectionTitle('Cut — darmiyan ka hissa hatayein'),
      Text(
        'Clip range: ${start.toStringAsFixed(1)}s – '
        '${end.toStringAsFixed(1)}s',
        style: const TextStyle(color: Colors.grey, fontSize: 12),
      ),
      _ProSlider(
        label: 'Cut start',
        value: cutStart,
        min: start,
        max: end,
        divisions: 100,
        onChanged: (v) => setState(() => _cutStart = v),
      ),
      _ProSlider(
        label: 'Cut end',
        value: cutEnd,
        min: start,
        max: end,
        divisions: 100,
        onChanged: (v) => setState(() => _cutEnd = v),
      ),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _busy ? null : _applyCutRange,
          icon: const Icon(Icons.cut),
          label: const Text('Cut hatao (2 clips ban jayenge)'),
        ),
      ),
      const Divider(height: 32),
    ];
  }

  /// Applies Precut › Cut: replaces the selected clip with its
  /// [trimStart..cutStart] and [cutEnd..effectiveEnd] parts.
  void _applyCutRange() {
    if (_clips.isEmpty || _busy) return;
    final idx = _selected;
    final clip = _clips[idx];
    final start = clip.trimStart;
    final end = clip.effectiveEnd;
    final cs = _cutStart.clamp(start, end);
    final ce = _cutEnd.clamp(start, end);
    if (ce - cs < 0.2) {
      _setStatus('Cut range bohat chhota hai — start/end badhayein.');
      return;
    }
    if (cs <= start + 0.05 && ce >= end - 0.05) {
      _setStatus('Poori clip cut ho jayegi — Delete use karein.');
      return;
    }
    _pushHistory();
    final parts = <VideoClip>[];
    if (cs > start + 0.05) {
      parts.add(clip.copy()..trimEnd = cs);
    }
    if (ce < end - 0.05) {
      parts.add(clip.copy()..trimStart = ce);
    }
    setState(() {
      _clips.replaceRange(idx, idx + 1, parts);
      _selected = idx;
    });
    _setStatus('Cut lag gaya — ${parts.length} clip(s) reh gaye.');
    unawaited(_loadPreview());
  }

  /// Precut › Split: the snap choice (playhead / midpoint — the
  /// toggle that used to sit in the transport row lives here now),
  /// Split, and Multi Split into N equal parts.
  List<Widget> _splitTabChildren() {
    return [
      _sectionTitle('Split'),
      const Text('Split point'),
      const SizedBox(height: 4),
      _iconChoiceRail([
        _iconChoiceItem(
          icon: Icons.push_pin,
          label: 'Playhead par',
          selected: _snapOn,
          onTap: () => setState(() => _snapOn = true),
        ),
        _iconChoiceItem(
          icon: Icons.horizontal_rule,
          label: 'Darmiyan se',
          selected: !_snapOn,
          onTap: () => setState(() => _snapOn = false),
        ),
      ]),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _busy || _clips.isEmpty ? null : _splitSelectedClip,
          icon: const Icon(Icons.call_split),
          label: const Text('Split karein'),
        ),
      ),
      _sectionTitle('Multi split'),
      _iconChoiceRail([
        for (final n in const [2, 3, 4, 5])
          _iconChoiceItem(
            icon: Icons.grid_view,
            label: '$n hisse',
            selected: false,
            onTap: _busy || _clips.isEmpty ? null : () => _multiSplit(n),
          ),
      ]),
      const Divider(height: 32),
    ];
  }

  /// Multi Split: the selected clip becomes [n] equal-length clips
  /// (trim copies — no re-encode).
  void _multiSplit(int n) {
    if (_clips.isEmpty || _busy) return;
    final idx = _selected;
    final clip = _clips[idx];
    final start = clip.trimStart;
    final step = clip.effectiveDuration / n;
    if (step < 0.3) {
      _setStatus('Clip bohat chhoti hai $n hisson ke liye.');
      return;
    }
    _pushHistory();
    final parts = <VideoClip>[];
    for (var i = 0; i < n; i++) {
      final part = clip.copy();
      part.trimStart = start + step * i;
      part.trimEnd = start + step * (i + 1);
      parts.add(part);
    }
    setState(() {
      _clips.replaceRange(idx, idx + 1, parts);
      _selected = idx;
    });
    _setStatus('Multi split — $n clips ban gaye.');
    unawaited(_loadPreview());
  }

  /// Speed › Standard: the legacy speed body (fixed chips + ramp
  /// presets; its Reverse toggle was removed — Reverse is an
  /// instant action now) + Custom ramp widgets + Smooth Slow-Mo
  /// (AI) + the resulting-total readout from the ONE timeline
  /// model.
  List<Widget> _speedStandardChildren() {
    final atSpeed = _speed == 1 || _proRamp != 'None'
        ? _totalDurationSec
        : _totalDurationSec / _speed;
    return [
      ..._panelBody('speed'),
      if (_proRamp == 'Custom') ..._customRampWidgets(),
      _sectionTitle('Smooth Slow-Mo (AI)'),
      const Text(
        'RIFE AI har frame ke darmiyan naya frame banata hai '
        '— 0.5x slow-mo bilkul smooth. Sirf ~10s tak ki '
        'selected clip par; model pack (rife_v46) chahiye.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const SizedBox(height: 6),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _busy ? null : _applySlowMoAi,
          icon: const Icon(Icons.slow_motion_video),
          label: const Text('Smooth Slow-Mo (AI) lagayein'),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Timeline total: ${_totalDurationSec.toStringAsFixed(1)}s'
        '${_proRamp == 'None' && _speed != 1 ? ' • speed ke baad ~${atSpeed.toStringAsFixed(1)}s' : ''}',
        style: const TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const Divider(height: 32),
    ];
  }

  /// Speed › Curve: the Custom-ramp point editors (the preset rail
  /// itself lives in Standard, where the legacy body puts it).
  List<Widget> _speedCurveChildren() {
    if (_proRamp != 'Custom') {
      return [
        _sectionTitle('Speed curve'),
        const Text(
          'Curve editor ke liye pehle ramp preset "Custom" chunein '
          '(Standard tab mein) — phir 3 points ki speed yahan set '
          'hoti hai.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => setState(() {
              _proRamp = 'Custom';
              _panelTab = 'curve';
            }),
            icon: const Icon(Icons.show_chart),
            label: const Text('Custom ramp on karein'),
          ),
        ),
        const Divider(height: 32),
      ];
    }
    return _customRampWidgets();
  }

  /// Voice Enhance panel: the enhance-voice op (AudioEnhanceService
  /// voice chain). Denoise is NOT duplicated here — it lives in
  /// Volume, per InShot [TUT9].
  List<Widget> _voiceEnhanceChildren() {
    return [
      _sectionTitle('Voice Enhance'),
      const Text(
        'Selected clip ki awaz saaf + wazeh: noise kam, voice '
        'band EQ, compression aur loudness normalise — on-device '
        '(AudioEnhanceService).',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _busy || _clips.isEmpty
              ? null
              : () => unawaited(_enhanceSelectedClipAudio(voice: true)),
          icon: const Icon(Icons.record_voice_over),
          label: const Text('Voice Enhance lagayein'),
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Sirf denoise chahiye to Volume panel ka Denoise use karein.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const Divider(height: 32),
    ];
  }

  /// Enhance panel (InShot [TUT11] shape): whole-clip target +
  /// one action. TJ Pro's Enhance is ON-DEVICE HD upscale (no
  /// sign-in gate — InShot's gate is a product fact we replace).
  List<Widget> _enhancePanelChildren() {
    final clip = _clips.isEmpty ? null : _clips[_selected];
    return [
      _sectionTitle('Enhance — HD (on-device)'),
      const Text(
        'Poori selected clip 2x upscale + sharpen hoti hai '
        '(ffmpeg lanczos + unsharp). Ye ESRGAN AI nahi hai — wo '
        'Photo Editor mein hai.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const SizedBox(height: 8),
      Text(
        clip == null
            ? 'Pehle clip select karein.'
            : 'Target: Clip ${_selected + 1} '
                '(${clip.effectiveDuration.toStringAsFixed(1)}s — poori clip)',
        style: const TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _busy || clip == null ? null : _enhanceSelectedClipHd,
          icon: const Icon(Icons.high_quality),
          label: const Text('Enhance karo'),
        ),
      ),
      const Divider(height: 32),
    ];
  }

  /// Stabilizer panel (InShot [TUT10] shape): 4 level tiles. Ours
  /// applies at EXPORT (vidstab two-pass in the export chain) —
  /// the note says so; the level maps to shakiness/smoothing at
  /// the export call site.
  List<Widget> _stabilizerPanelChildren() {
    return [
      _sectionTitle('Stabilizer'),
      _iconChoiceRail([
        for (final e in const [
          (0, 'Original', Icons.block),
          (1, 'Low', Icons.videocam),
          (2, 'Standard', Icons.video_stable),
          (3, 'Most Stable', Icons.video_stable),
        ])
          _iconChoiceItem(
            icon: e.$3,
            label: e.$2,
            selected: _stabLevel == e.$1,
            onTap: () => setState(() {
              _stabLevel = e.$1;
              _proStabilize = e.$1 > 0;
            }),
          ),
      ]),
      const SizedBox(height: 8),
      const Text(
        'Stabilization EXPORT par apply hoti hai (vidstab two-pass) '
        '— preview mein nahi dikhegi.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const Divider(height: 32),
    ];
  }

  /// Cutout panel: two modes (InShot [TUT3/4]) — Cutout = the ML
  /// background remover section, Chroma = the chroma-key section,
  /// sliced out of the one legacy 'chroma' body at the BG-remover
  /// switch anchor (each section shows exactly once).
  List<Widget> _cutoutPanelChildren() {
    final body = _panelBody('chroma');
    final bgIdx = _anchorIndex(
      body,
      (w) =>
          w is SwitchListTile &&
          w.title is Text &&
          ((w.title as Text).data ?? '').contains('background remover'),
    );
    final chromaPart = bgIdx < 0 ? body : body.sublist(0, bgIdx);
    final bgPart = bgIdx < 0 ? const <Widget>[] : body.sublist(bgIdx);
    return [
      _iconChoiceRail([
        _iconChoiceItem(
          icon: Icons.person_remove,
          label: 'Cutout',
          selected: _cutoutMode == 'cutout',
          onTap: () => setState(() => _cutoutMode = 'cutout'),
        ),
        _iconChoiceItem(
          icon: Icons.format_color_fill,
          label: 'Chroma',
          selected: _cutoutMode == 'chroma',
          onTap: () => setState(() => _cutoutMode = 'chroma'),
        ),
      ]),
      const SizedBox(height: 6),
      if (_cutoutMode == 'chroma') ...chromaPart else ...bgPart,
    ];
  }

  /// Mask panel: the PIP element's mask controls when a PIP is
  /// active; otherwise a pointer to add one (our mask model is the
  /// PIP mask — main clips have no mask track).
  List<Widget> _maskPanelChildren() {
    if (!_fxPip) {
      return [
        _sectionTitle('Mask'),
        const Text(
          'Mask PIP element par lagta hai. Pehle PIP add karein — '
          'phir yahan us ki mask shape / feather / invert milega.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _openToolTab('overlay', 'pip'),
            icon: const Icon(Icons.picture_in_picture_alt),
            label: const Text('PIP add karein'),
          ),
        ),
        const Divider(height: 32),
      ];
    }
    return _pipMaskChildren();
  }

  /// Opacity panel: PIP element → its opacity + blend (the PIP
  /// style slice); a plain clip → the transform opacity.
  List<Widget> _opacityPanelChildren() {
    if (_fxPip) return _pipStyleChildren();
    return [
      _sectionTitle('Opacity — clip'),
      _ProSlider(
        label: 'Clip opacity',
        value: _tfOpacity,
        min: 0,
        max: 1,
        divisions: 20,
        onChanged: (v) => setState(() => _tfOpacity = v),
      ),
      const Text(
        'Clip apne blurred backdrop par fade hota hai (Transform '
        'pass) — export par apply hota hai.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const Divider(height: 32),
    ];
  }

  /// Rotate panel (InShot [TUT9]): exactly ROTATE + FLIP.
  List<Widget> _rotatePanelChildren() {
    return [
      _sectionTitle('Rotate'),
      Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _busy || _clips.isEmpty
                  ? null
                  : () => unawaited(_rotateSelectedClip(flip: false)),
              icon: const Icon(Icons.rotate_right),
              label: const Text('ROTATE 90°'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _busy || _clips.isEmpty
                  ? null
                  : () => unawaited(_rotateSelectedClip(flip: true)),
              icon: const Icon(Icons.flip),
              label: const Text('FLIP'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      const Text(
        'Dono selected clip ke trimmed range par bake hote hain '
        '(processed copy ban jati hai).',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const Divider(height: 32),
    ];
  }

  /// Ease panel (InShot curve-preset variant — the documented
  /// superset): the 4 REAL easing curves of the keyframe system,
  /// as chips + the live curve graph.
  List<Widget> _easePanelChildren() {
    return [
      _sectionTitle('Ease — keyframe motion'),
      _iconChoiceRail([
        for (final e in KeyframeEasing.values)
          _iconChoiceItem(
            icon: switch (e) {
              KeyframeEasing.linear => Icons.trending_flat,
              KeyframeEasing.easeIn => Icons.trending_up,
              KeyframeEasing.easeOut => Icons.trending_down,
              KeyframeEasing.easeInOut => Icons.show_chart,
            },
            label: keyframeEasingLabel(e).split(' (').first,
            selected: _kfEasing == e,
            onTap: () => setState(() => _kfEasing = e),
          ),
      ]),
      Container(
        height: 56,
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1B1B1B),
          borderRadius: BorderRadius.circular(8),
        ),
        child: CustomPaint(
          painter: _EasingCurvePainter(_kfEasing),
          child: const SizedBox.expand(),
        ),
      ),
      const Text(
        'Ye easing Animation (keyframes) wale motion par lagti hai.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const Divider(height: 32),
    ];
  }

  /// Transitions panel REWRITE (#8): category rows of type chips +
  /// ONE duration slider. v1.4.0 had THREE duration controls
  /// (crossfade toggle + presets rail + slider) and a crossfade
  /// switch separate from the type — here picking a type IS the
  /// on-switch, 'None' is the off-switch, one slider sets the
  /// duration. (InShot's post-pick volume slider is skipped — no
  /// transition-SFX model exists; PARTIAL in the report.)
  List<Widget> _transitionsPanelChildren() {
    Widget typeChip(String id, String label, IconData icon) {
      final selected = _crossfade && _proTransition == id;
      return _iconChoiceItem(
        icon: icon,
        label: label,
        selected: selected,
        onTap: () => setState(() {
          _proTransition = id;
          _crossfade = true;
        }),
      );
    }

    return [
      _sectionTitle('Transition — type'),
      const Text('Basic'),
      const SizedBox(height: 4),
      _iconChoiceRail([
        _iconChoiceItem(
          icon: Icons.block,
          label: 'None',
          selected: !_crossfade,
          onTap: () => setState(() => _crossfade = false),
        ),
        typeChip('fade', 'Fade', Icons.blur_linear),
        typeChip('dissolve', 'Dissolve', Icons.grain),
        typeChip('pixelize', 'Pixelize', Icons.grid_on),
        typeChip('hblur', 'H-Blur', Icons.blur_on),
      ]),
      const SizedBox(height: 6),
      const Text('Slide'),
      const SizedBox(height: 4),
      _iconChoiceRail([
        typeChip('slideleft', 'Left', Icons.arrow_back),
        typeChip('slideright', 'Right', Icons.arrow_forward),
        typeChip('slideup', 'Up', Icons.arrow_upward),
        typeChip('slidedown', 'Down', Icons.arrow_downward),
        typeChip('smoothleft', 'Smooth L', Icons.keyboard_double_arrow_left),
        typeChip('smoothright', 'Smooth R', Icons.keyboard_double_arrow_right),
      ]),
      const SizedBox(height: 6),
      const Text('Wipe'),
      const SizedBox(height: 4),
      _iconChoiceRail([
        typeChip('wipeleft', 'Left', Icons.arrow_back),
        typeChip('wiperight', 'Right', Icons.arrow_forward),
        typeChip('wipeup', 'Up', Icons.arrow_upward),
        typeChip('wipedown', 'Down', Icons.arrow_downward),
      ]),
      const SizedBox(height: 6),
      const Text('Circle'),
      const SizedBox(height: 4),
      _iconChoiceRail([
        typeChip('circlecrop', 'Crop', Icons.circle_outlined),
        typeChip('circleopen', 'Open', Icons.radio_button_unchecked),
        typeChip('radial', 'Radial', Icons.radar),
        typeChip('rectcrop', 'Rect', Icons.crop_square),
      ]),
      _sectionTitle('Duration'),
      _ProSlider(
        label: 'Transition duration',
        value: _proTransitionDur,
        min: 0.1,
        max: 2,
        divisions: 19,
        onChanged: (v) => setState(() => _proTransitionDur = v),
      ),
      const Text(
        'Duration har clip boundary par same lagti hai; type '
        'badalne se kul duration badal sakti hai (xfade overlap).',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const Divider(height: 32),
    ];
  }

  /// AI Cut panel: on-device silence removal (ffmpeg
  /// silencedetect) — scan the selected clip, list the silence
  /// ranges, then rebuild the clip from the keep segments.
  List<Widget> _aiCutChildren() {
    final clip = _clips.isEmpty ? null : _clips[_selected];
    return [
      _sectionTitle('AI Cut — silence hatayein'),
      const Text(
        'On-device scan: khamoshi wale hisse dhoondh kar kaat diye '
        'jate hain (filler / pauses). Koi cloud ya sign-in nahi.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      if (clip == null)
        const Text(
          'Pehle clip select karein.',
          style: TextStyle(color: Colors.grey),
        )
      else ...[
        _ProSlider(
          label: 'Silence threshold (dB)',
          value: _aicutThresholdDb,
          min: -60,
          max: -10,
          divisions: 50,
          onChanged: (v) => setState(() => _aicutThresholdDb = v),
        ),
        _ProSlider(
          label: 'Kam az kam silence (s)',
          value: _aicutMinSilenceSec,
          min: 0.2,
          max: 2,
          divisions: 18,
          onChanged: (v) => setState(() => _aicutMinSilenceSec = v),
        ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _aicutBusy ? null : _scanSilence,
            icon: const Icon(Icons.search),
            label: Text(_aicutBusy ? 'Scan ho raha hai…' : 'Silence scan karein'),
          ),
        ),
        if (_aicutRanges.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '${_aicutRanges.length} silence range mile:',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          for (final r in _aicutRanges)
            Text(
              '${r.$1.toStringAsFixed(1)}s – ${r.$2.toStringAsFixed(1)}s',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _aicutBusy ? null : _applyAiCut,
              icon: const Icon(Icons.content_cut),
              label: const Text('Cut karke naya clip banao'),
            ),
          ),
        ],
      ],
      const Divider(height: 32),
    ];
  }

  /// Runs silencedetect on the selected clip and parses the
  /// silence_start / silence_end pairs out of the ffmpeg log.
  Future<void> _scanSilence() async {
    if (_clips.isEmpty || _aicutBusy) return;
    final clip = _clips[_selected];
    setState(() {
      _aicutBusy = true;
      _aicutRanges = const [];
    });
    try {
      final res = await FfmpegService.run(
        '-i ${FfmpegService.q(clip.file.path)} '
        '-af silencedetect=noise=${_aicutThresholdDb.toStringAsFixed(0)}dB'
        ':d=${_aicutMinSilenceSec.toStringAsFixed(2)} '
        '-f null -',
      );
      final starts = <double>[];
      final ranges = <(double, double)>[];
      for (final m in RegExp(r'silence_(start|end): ([\d.]+)')
          .allMatches(res.logs)) {
        final value = double.tryParse(m.group(2) ?? '') ?? 0;
        if (m.group(1) == 'start') {
          starts.add(value);
        } else if (starts.isNotEmpty) {
          ranges.add((starts.removeAt(0), value));
        }
      }
      // An unterminated silence runs to the end of the file.
      final fileEnd = clip.duration.inMilliseconds / 1000;
      for (final s in starts) {
        ranges.add((s, fileEnd));
      }
      if (!mounted) return;
      setState(() => _aicutRanges = ranges);
      _setStatus(
        ranges.isEmpty
            ? 'Koi silence nahi mili — threshold kam karke dekhein.'
            : '${ranges.length} silence range mile.',
      );
    } catch (e) {
      _setStatus('Silence scan failed: $e');
    } finally {
      if (mounted) setState(() => _aicutBusy = false);
    }
  }

  /// Rebuilds the selected clip from the KEEP segments (its trimmed
  /// range minus the scanned silences) via one trim/concat graph.
  Future<void> _applyAiCut() async {
    if (_clips.isEmpty || _aicutBusy || _aicutRanges.isEmpty) return;
    final idx = _selected;
    final clip = _clips[idx];
    final start = clip.trimStart;
    final end = clip.effectiveEnd;
    final keeps = <(double, double)>[];
    var cursor = start;
    for (final r in _aicutRanges) {
      final s = r.$1.clamp(start, end);
      final e = r.$2.clamp(start, end);
      if (s > cursor + 0.05) keeps.add((cursor, s));
      if (e > cursor) cursor = e;
    }
    if (cursor < end - 0.05) keeps.add((cursor, end));
    if (keeps.isEmpty) {
      _setStatus('Poori clip silence hai — kuch nahi bachega.');
      return;
    }
    if (keeps.length == 1 && keeps.first.$1 == start && keeps.first.$2 == end) {
      _setStatus('Trim range mein koi silence nahi — clip waisi ki waisi hai.');
      return;
    }
    setState(() => _aicutBusy = true);
    try {
      final dir = await _workDir();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final out = p.join(dir.path, 'aicut_$stamp.mp4');
      String graph(bool withAudio) {
        final b = StringBuffer();
        for (var i = 0; i < keeps.length; i++) {
          b.write(
            '[0:v]trim=start=${keeps[i].$1}:end=${keeps[i].$2},'
            'setpts=PTS-STARTPTS[v$i];',
          );
          if (withAudio) {
            b.write(
              '[0:a]atrim=start=${keeps[i].$1}:end=${keeps[i].$2},'
              'asetpts=PTS-STARTPTS[a$i];',
            );
          }
        }
        final inputs = keeps
            .asMap()
            .entries
            .map((e) => withAudio
                ? '[v${e.key}][a${e.key}]'
                : '[v${e.key}]')
            .join();
        b.write(
          '${inputs}concat=n=${keeps.length}:v=1:a=${withAudio ? 1 : 0}'
          '[outv]${withAudio ? '[outa]' : ''}',
        );
        return b.toString();
      }

      var res = await FfmpegService.run(
        '-i ${FfmpegService.q(clip.file.path)} '
        '-filter_complex "${graph(true)}" -map "[outv]" -map "[outa]" '
        '-c:v libx264 -preset veryfast -crf 23 -c:a aac -b:a 128k '
        '-y ${FfmpegService.q(out)}',
      );
      if (!res.ok) {
        res = await FfmpegService.run(
          '-i ${FfmpegService.q(clip.file.path)} '
          '-filter_complex "${graph(false)}" -map "[outv]" '
          '-c:v libx264 -preset veryfast -crf 23 '
          '-y ${FfmpegService.q(out)}',
        );
      }
      if (!res.ok) {
        _setStatus('AI Cut nahi hua. ${res.logs}');
        return;
      }
      final keepTotal =
          keeps.fold(0.0, (sum, k) => sum + (k.$2 - k.$1));
      _pushHistory();
      setState(() {
        final nc = VideoClip(
          File(out),
          Duration(milliseconds: (keepTotal * 1000).round()),
          clip.aspectRatio,
        );
        nc.volume = clip.volume;
        nc.muted = clip.muted;
        _clips[idx] = nc;
        _aicutRanges = const [];
      });
      _setStatus('AI Cut tayyar — silence hat gayi.');
      await _loadPreview();
    } catch (e) {
      _setStatus('AI Cut failed: $e');
    } finally {
      if (mounted) setState(() => _aicutBusy = false);
    }
  }

  /// The PIP style slice of [_pipExtras] (opacity + blend) — the
  /// Opacity panel's element half.
  List<Widget> _pipStyleChildren() {
    final extras = _pipExtras();
    final maskIdx = _anchorIndex(extras, (w) => _isTextStarting(w, 'Mask'));
    return maskIdx < 0 ? extras : extras.sublist(0, maskIdx);
  }

  /// The PIP mask slice of [_pipExtras] — the Mask panel's content.
  List<Widget> _pipMaskChildren() {
    final extras = _pipExtras();
    final maskIdx = _anchorIndex(extras, (w) => _isTextStarting(w, 'Mask'));
    if (maskIdx < 0) return const [];
    return [
      _sectionTitle('Mask — PIP element'),
      ...extras.sublist(maskIdx),
    ];
  }

  /// Edit › Speed extras for the Custom ramp (§6.10): three point
  /// speeds + the curve graph.
  List<Widget> _customRampWidgets() {
    return [
      _sectionTitle('Custom ramp — 3 points'),
      _ProSlider(
        label: 'Start speed',
        value: _rampStart,
        min: 0.25,
        max: 2,
        divisions: 35,
        onChanged: (v) => setState(() => _rampStart = v),
      ),
      _ProSlider(
        label: 'Middle speed',
        value: _rampMid,
        min: 0.25,
        max: 2,
        divisions: 35,
        onChanged: (v) => setState(() => _rampMid = v),
      ),
      _ProSlider(
        label: 'End speed',
        value: _rampEnd,
        min: 0.25,
        max: 2,
        divisions: 35,
        onChanged: (v) => setState(() => _rampEnd = v),
      ),
      Container(
        height: 64,
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1B1B1B),
          borderRadius: BorderRadius.circular(8),
        ),
        child: CustomPaint(
          painter: _RampCurvePainter(_rampStart, _rampMid, _rampEnd),
          child: const SizedBox.expand(),
        ),
      ),
      const Text(
        'Curve: pehla third Start speed, darmiyan Middle, aakhri '
        'third End speed par chalega.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const Divider(height: 32),
    ];
  }

  /// Audio › Music extras (§6.8 ducking + §6.9 volume keyframes).
  List<Widget> _musicExtras() {
    final posSec = _controller != null && _controller!.value.isInitialized
        ? _controller!.value.position.inMilliseconds / 1000
        : 0.0;
    return [
      const Divider(height: 32),
      SwitchListTile(
        title: const Text('Auto ducking'),
        subtitle: const Text(
          'Music clip ki awaz ke neeche khud dab jayega (sidechain) '
          '— export mein alag pass mein lagta hai.',
        ),
        value: _autoDuck,
        onChanged: (v) => setState(() => _autoDuck = v),
      ),
      if (_musicPath != null) ...[
        _sectionTitle('Volume keyframes'),
        if (_volumePoints.isEmpty)
          const Text(
            'Koi point nahi — music seedha Music volume par chalega.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        for (var i = 0; i < _volumePoints.length; i++)
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_volumePoints[i].$1.toStringAsFixed(1)}s → '
                  'gain ${_volumePoints[i].$2.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () =>
                    setState(() => _volumePoints.removeAt(i)),
              ),
            ],
          ),
        ElevatedButton.icon(
          onPressed: () {
            setState(() {
              _volumePoints.add((posSec, _musicVolume));
              _volumePoints.sort((a, b) => a.$1.compareTo(b.$1));
            });
          },
          icon: const Icon(Icons.add_location_alt_outlined),
          label: Text(
            'Point add karein — playhead ${posSec.toStringAsFixed(1)}s, '
            'gain ${_musicVolume.toStringAsFixed(2)}',
          ),
        ),
      ],
    ];
  }

  /// Overlay › Sticker: the stickers body WITHOUT the keyframes
  /// block (that lives on its own sub-tab now).
  List<Widget> _stickerTabChildren() {
    final body = _panelBody('stickers');
    final kfIdx =
        _anchorIndex(body, (w) => _isTextStarting(w, 'Keyframes animate'));
    return kfIdx < 0 ? body : body.sublist(0, kfIdx);
  }

  /// Overlay › Keyframes: easing chips + curve graph on top, then
  /// the Start OR End keyframe sliders (§5A — one page at a time).
  List<Widget> _keyframesTabChildren() {
    final body = _panelBody('stickers');
    final kfIdx =
        _anchorIndex(body, (w) => _isTextStarting(w, 'Keyframes animate'));
    if (kfIdx < 0) return body;
    final slice = body.sublist(kfIdx);
    final startIdx =
        _anchorIndex(slice, (w) => _isTextStarting(w, 'Start keyframe'));
    final endIdx =
        _anchorIndex(slice, (w) => _isTextStarting(w, 'End keyframe'));
    if (startIdx < 0 || endIdx < 0) return slice;
    final header = slice.sublist(0, startIdx);
    final startSliders = slice.sublist(startIdx, endIdx);
    final endSliders = slice.sublist(endIdx);
    return [
      ...header,
      if (_proKeyframes &&
          (_proTitle.trim().isNotEmpty || _proSticker.trim().isNotEmpty)) ...[
        const Text('Motion easing',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        _iconChoiceRail([
          for (final e in KeyframeEasing.values)
            _iconChoiceItem(
              icon: switch (e) {
                KeyframeEasing.linear => Icons.trending_flat,
                KeyframeEasing.easeIn => Icons.trending_up,
                KeyframeEasing.easeOut => Icons.trending_down,
                KeyframeEasing.easeInOut => Icons.show_chart,
              },
              label: keyframeEasingLabel(e).split(' (').first,
              selected: _kfEasing == e,
              onTap: () => setState(() => _kfEasing = e),
            ),
        ]),
        Container(
          height: 56,
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1B1B1B),
            borderRadius: BorderRadius.circular(8),
          ),
          child: CustomPaint(
            painter: _EasingCurvePainter(_kfEasing),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(height: 4),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('Start keyframe')),
            ButtonSegment(value: 1, label: Text('End keyframe')),
          ],
          selected: {_kfPage},
          onSelectionChanged: (v) => setState(() => _kfPage = v.first),
        ),
        const SizedBox(height: 8),
      ],
      if (_kfPage == 0) ...startSliders else ...endSliders,
    ];
  }

  /// Overlay › PIP extras (§6.11 + completion fix, user order
  /// 22 Nov 2026): opacity, blend mode, mask shape, feather,
  /// invert — every choice an icon+label rail (global UI rule).
  /// The blend keys ARE ffmpeg's blend mode names; 'normal' takes
  /// the plain overlay path. The mask keys map 1:1 onto the
  /// generated mask PNG (preview + export share it).
  List<Widget> _pipExtras() {
    if (!_fxPip) return const [];
    return [
      _sectionTitle('PIP style'),
      _ProSlider(
        label: 'PIP opacity',
        value: _pipOpacity,
        min: 0.1,
        max: 1,
        divisions: 18,
        onChanged: (v) => setState(() => _pipOpacity = v),
      ),
      const Text('Blend mode'),
      const SizedBox(height: 4),
      _iconChoiceRail([
        for (final e in const [
          ('normal', 'Normal', Icons.picture_in_picture_alt),
          ('multiply', 'Multiply', Icons.layers),
          ('screen', 'Screen', Icons.light_mode),
          ('overlay', 'Overlay', Icons.contrast),
          ('softlight', 'Soft Light', Icons.blur_on),
          ('hardlight', 'Hard Light', Icons.flash_on),
          ('darken', 'Darken', Icons.dark_mode),
          ('lighten', 'Lighten', Icons.brightness_high),
          ('difference', 'Difference', Icons.compare_arrows),
          ('dodge', 'Color Dodge', Icons.wb_sunny),
          ('burn', 'Color Burn', Icons.local_fire_department),
        ])
          _iconChoiceItem(
            icon: e.$3,
            label: e.$2,
            selected: _pipBlend == e.$1,
            onTap: () => setState(() => _pipBlend = e.$1),
          ),
      ]),
      const SizedBox(height: 8),
      const Text('Mask'),
      const SizedBox(height: 4),
      _iconChoiceRail([
        for (final e in const [
          ('none', 'None', Icons.block),
          ('circle', 'Circle', Icons.circle_outlined),
          ('rect', 'Rectangle', Icons.crop_square),
          ('roundrect', 'Rounded', Icons.rounded_corner),
          ('heart', 'Heart', Icons.favorite),
          ('star', 'Star', Icons.star),
          ('linear', 'Linear', Icons.gradient),
          ('radial', 'Radial', Icons.radio_button_checked),
        ])
          _iconChoiceItem(
            icon: e.$3,
            label: e.$2,
            selected: _pipMask == e.$1,
            onTap: () => setState(() => _pipMask = e.$1),
          ),
      ]),
      if (_pipMask != 'none') ...[
        _ProSlider(
          label: 'Mask feather (kinara soft)',
          value: _pipMaskFeather,
          min: 0,
          max: 1,
          divisions: 20,
          onChanged: (v) => setState(() => _pipMaskFeather = v),
        ),
        Row(
          children: [
            const Text('Mask invert'),
            const SizedBox(width: 10),
            _iconChoiceItem(
              icon: Icons.invert_colors,
              label: 'Invert',
              selected: _pipMaskInvert,
              onTap: () => setState(() => _pipMaskInvert = !_pipMaskInvert),
            ),
          ],
        ),
      ],
      const Text(
        'Blend mode inset ke andar hi lagta hai — bahar ka frame '
        'asal rehta hai. Mask, feather aur blend stage preview mein '
        'live dikhte hain, export mein wohi result aata hai.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const Divider(height: 32),
    ];
  }

  /// v1.5.0 TIMELINE (mockups V1/V2, replacing _timelineSection +
  /// _timelineCard): contextual yellow hint → the centred-playhead
  /// strip (fixed red + column at left with Mute under it, ruler
  /// labels every 2s, REAL filmstrip thumbnails, gold selection,
  /// trim handles on the selected block, transition badges on the
  /// boundaries, long-press swap) → PIP lane → audio lane → text
  /// lane → times row (current centred / total right — BOTH from
  /// the one TimelineClock model, #5/#30).
  Widget _timelineBar() {
    final total = _totalDurationSec;
    return Container(
      color: const Color(0xFF161616),
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _elementRow && _fxPip
                ? 'PIP element selected — Switch se main track par wapas.'
                : _clipRow && _clips.isNotEmpty
                    ? 'Long press to swap'
                    : 'Select one track to edit.',
            style: const TextStyle(
              color: Color(0xFFFFD60A),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, constraints) {
              final halfPad = constraints.maxWidth / 2 - 52;
              final contentW = halfPad * 2 + total * _tlPxPerSec;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Fixed left column: red + (add) and, under it,
                  // the selected clip's Mute toggle (InShot's
                  // "Mute Clip" label zone).
                  SizedBox(
                    width: 52,
                    child: Column(
                      children: [
                        Material(
                          color: const Color(0xFFE53935),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _busy ? null : _showAddMediaSheet,
                            child: const SizedBox(
                              width: 38,
                              height: 38,
                              child: Icon(
                                Icons.add,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (_clips.isNotEmpty)
                          InkWell(
                            onTap: () {
                              final clip = _clips[_selected];
                              setState(() => clip.muted = !clip.muted);
                              unawaited(
                                _controller?.setVolume(
                                      clip.muted ? 0 : clip.volume,
                                    ) ??
                                    Future<void>.value(),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 2,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _clips[_selected].muted
                                        ? Icons.volume_off
                                        : Icons.volume_up,
                                    size: 14,
                                    color: Colors.white70,
                                  ),
                                  const SizedBox(width: 2),
                                  const Text(
                                    'Mute',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        NotificationListener<ScrollNotification>(
                          onNotification: (n) {
                            if (n is ScrollStartNotification) {
                              _tlUserScrolling = true;
                            } else if (n is ScrollEndNotification) {
                              _tlUserScrolling = false;
                              final centreSec =
                                  _tlScroll.offset / _tlPxPerSec;
                              unawaited(_seekToGlobalSec(centreSec));
                            }
                            return false;
                          },
                          child: SingleChildScrollView(
                            controller: _tlScroll,
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: contentW,
                              height: 74,
                              child: Stack(
                                children: [
                                  // Ruler labels every 2s.
                                  for (var s = 0; s <= total; s += 2)
                                    Positioned(
                                      left: halfPad + s * _tlPxPerSec - 8,
                                      top: 0,
                                      child: Text(
                                        '${s}s',
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 9,
                                        ),
                                      ),
                                    ),
                                  // Clip blocks.
                                  for (var i = 0;
                                      i < _clips.length;
                                      i++)
                                    _timelineClipBlock(
                                      i,
                                      left: halfPad +
                                          _clipStartSec(i) * _tlPxPerSec,
                                    ),
                                  // Transition badges.
                                  for (var i = 1;
                                      i < _clips.length;
                                      i++)
                                    Positioned(
                                      left: halfPad +
                                          _clipStartSec(i) * _tlPxPerSec -
                                          11,
                                      top: 26,
                                      child: GestureDetector(
                                        onTap: () =>
                                            _openTool('transitions'),
                                        child: Container(
                                          width: 22,
                                          height: 22,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(5),
                                          ),
                                          child: Icon(
                                            _crossfade
                                                ? Icons.swap_horiz
                                                : Icons.add,
                                            size: 14,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // FIXED centre playhead.
                        Positioned(
                          left: (constraints.maxWidth - 52) / 2,
                          top: 0,
                          bottom: 0,
                          child: Container(
                            width: 2,
                            color: const Color(0xFFFFD60A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          if (_fxPip) ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: () => setState(() {
                _elementRow = true;
                _clipRow = false;
                _activeTool = null;
              }),
              child: Container(
                height: 22,
                decoration: BoxDecoration(
                  color: _elementRow
                      ? const Color(0xFF6A4C00)
                      : const Color(0xFF263238),
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: const Row(
                  children: [
                    Icon(
                      Icons.picture_in_picture_alt,
                      size: 13,
                      color: Colors.white70,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'PIP element',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 4),
          // Audio lane.
          InkWell(
            onTap: () => _openToolTab('audio', 'music'),
            child: Container(
              height: 22,
              decoration: BoxDecoration(
                color: _musicPath != null
                    ? const Color(0xFF37474F)
                    : const Color(0xFF222222),
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.music_note,
                    size: 13,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _musicPath != null
                          ? p.basename(_musicPath!)
                          : '+ Add audio',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Text lane.
          InkWell(
            onTap: () => _openTool('text'),
            child: Container(
              height: 22,
              decoration: BoxDecoration(
                color: _text.trim().isNotEmpty
                    ? const Color(0xFF37474F)
                    : const Color(0xFF222222),
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.text_fields,
                    size: 13,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _text.trim().isNotEmpty
                          ? _text.trim()
                          : _captions.isNotEmpty
                              ? '${_captions.length} captions'
                              : '+ Add text',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Times row — current centred, total right, both from
          // the ONE clock/model (#5).
          AnimatedBuilder(
            animation: _clock,
            builder: (context, _) {
              String fmtT(double sec) {
                final m = sec ~/ 60;
                final s = (sec % 60).floor().toString().padLeft(2, '0');
                return '$m:$s';
              }

              return SizedBox(
                height: 16,
                child: Stack(
                  children: [
                    Center(
                      child: Text(
                        fmtT(_globalPositionSec),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        fmtT(total),
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// One filmstrip block on the new timeline: real thumbnails
  /// (photo clips show themselves), gold border when selected,
  /// trim handles on the selected block, tap = select + preview,
  /// long-press = the swap sheet ("Long press to swap").
  Widget _timelineClipBlock(int i, {required double left}) {
    final clip = _clips[i];
    final w = clip.effectiveDuration * _tlPxPerSec;
    final selected = i == _selected;
    final thumbs = _thumbCache[clip.file.path];
    return Positioned(
      left: left,
      top: 14,
      width: w,
      height: 56,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selected = i;
            _clipRow = true;
            _elementRow = false;
          });
          unawaited(_loadPreview());
        },
        onLongPress: () => _showSwapSheet(i),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? TjProTheme.gold : Colors.white24,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(4),
            color: const Color(0xFF2A2A2A),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(
                child: thumbs == null || thumbs.isEmpty
                    ? const Center(
                        child: Icon(
                          Icons.movie,
                          color: Colors.white38,
                          size: 18,
                        ),
                      )
                    : Row(
                        children: [
                          for (var k = 0; k < 24; k++)
                            Expanded(
                              child: Image.file(
                                File(thumbs[k % thumbs.length]),
                                fit: BoxFit.cover,
                                height: 56,
                                errorBuilder: (_, _, _) =>
                                    const ColoredBox(
                                  color: Color(0xFF2A2A2A),
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
              if (clip.isPhoto)
                const Positioned(
                  left: 3,
                  top: 3,
                  child: Icon(
                    Icons.photo,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              if (selected) ...[
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 14,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (d) {
                      setState(() {
                        clip.trimStart = (clip.trimStart +
                                d.delta.dx / _tlPxPerSec)
                            .clamp(
                              0,
                              clip.effectiveEnd - 0.3,
                            );
                      });
                    },
                    onHorizontalDragEnd: (_) => _pushHistory(),
                    child: Container(
                      color: TjProTheme.gold.withValues(alpha: 0.85),
                      child: const Icon(
                        Icons.chevron_left,
                        size: 12,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 14,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (d) {
                      setState(() {
                        final full = clip.duration.inMilliseconds / 1000;
                        clip.trimEnd = (clip.effectiveEnd +
                                d.delta.dx / _tlPxPerSec)
                            .clamp(
                              clip.trimStart + 0.3,
                              full,
                            );
                      });
                    },
                    onHorizontalDragEnd: (_) => _pushHistory(),
                    child: Container(
                      color: TjProTheme.gold.withValues(alpha: 0.85),
                      child: const Icon(
                        Icons.chevron_right,
                        size: 12,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The add-media sheet behind the timeline's red + button.
  void _showAddMediaSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.videocam, color: Colors.white),
              title: const Text(
                'Video add karein',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                unawaited(_addClip());
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo, color: Colors.white),
              title: const Text(
                'Photo add karein',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                unawaited(_addPhotoClip());
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Long-press on a clip block: swap it with a neighbour
  /// ("Long press to swap" — the reorder path of the new
  /// timeline).
  void _showSwapSheet(int i) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (i > 0)
              ListTile(
                leading:
                    const Icon(Icons.arrow_back, color: Colors.white),
                title: const Text(
                  'Peechay wali clip se swap',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _swapClips(i, i - 1);
                },
              ),
            if (i < _clips.length - 1)
              ListTile(
                leading:
                    const Icon(Icons.arrow_forward, color: Colors.white),
                title: const Text(
                  'Aglay wali clip se swap',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _swapClips(i, i + 1);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _swapClips(int a, int b) {
    _pushHistory();
    setState(() {
      final tmp = _clips[a];
      _clips[a] = _clips[b];
      _clips[b] = tmp;
      _selected = b;
    });
    unawaited(_loadPreview());
  }

  /// Edit › Trim (§5A): fine trim + the action row (Split / Frame /
  /// Freeze / Extract / Delete — moved here from the old timeline
  /// header) + Canvas chips + fill + intro/outro attach slots.
  List<Widget> _trimTabChildren() {
    final clip = _clips.isEmpty ? null : _clips[_selected];
    final dur = clip != null ? clip.duration.inMilliseconds / 1000 : 0.0;
    return [
      _sectionTitle('Trim selected clip'),
      if (clip == null)
        const Text(
          'Pehle timeline se clip add karein (+ tile).',
          style: TextStyle(color: Colors.grey),
        )
      else ...[
        Text(
          'Trim: ${clip.trimStart.toStringAsFixed(1)}s – '
          '${clip.effectiveEnd.toStringAsFixed(1)}s '
          '(kul ${dur.toStringAsFixed(1)}s)',
        ),
        RangeSlider(
          values: RangeValues(clip.trimStart, clip.effectiveEnd),
          min: 0,
          max: dur,
          divisions: (clip.duration.inMilliseconds / 100).round().clamp(1, 1000),
          labels: RangeLabels(
            '${clip.trimStart.toStringAsFixed(1)}s',
            '${clip.effectiveEnd.toStringAsFixed(1)}s',
          ),
          onChangeStart: (_) => _pushHistory(),
          onChanged: (v) {
            if (v.end - v.start < 0.5) return;
            setState(() {
              clip.trimStart = v.start;
              clip.trimEnd = v.end;
            });
          },
        ),
        Row(
          children: [
            const Text('Start (fine)'),
            Expanded(
              child: Slider(
                value: clip.trimStart.clamp(0, dur),
                min: 0,
                max: dur,
                onChangeStart: (_) => _pushHistory(),
                onChanged: (v) {
                  if (clip.effectiveEnd - v < 0.5) return;
                  setState(() => clip.trimStart = v);
                },
              ),
            ),
            Text('${clip.trimStart.toStringAsFixed(1)}s'),
          ],
        ),
        Row(
          children: [
            const Text('End (fine)'),
            Expanded(
              child: Slider(
                value: clip.effectiveEnd.clamp(0, dur),
                min: 0,
                max: dur,
                onChangeStart: (_) => _pushHistory(),
                onChanged: (v) {
                  if (v - clip.trimStart < 0.5) return;
                  setState(() => clip.trimEnd = v);
                },
              ),
            ),
            Text('${clip.effectiveEnd.toStringAsFixed(1)}s'),
          ],
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            TextButton.icon(
              onPressed: _splitSelectedClip,
              icon: const Icon(Icons.content_cut, size: 18),
              label: const Text('Split'),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _saveFrameSnapshot,
              icon: const Icon(Icons.camera_alt_outlined, size: 18),
              label: const Text('Frame'),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _freezeFrameInsert,
              icon: const Icon(Icons.ac_unit, size: 18),
              label: const Text('Freeze'),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _extractClipAudio,
              icon: const Icon(Icons.audio_file_outlined, size: 18),
              label: const Text('Extract audio'),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _deleteSelectedClip,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Delete'),
            ),
          ],
        ),
      ],
      _sectionTitle('Canvas'),
      _iconChoiceRail([
        for (final a in const [
          ('Original', Icons.photo_size_select_actual),
          ('9:16', Icons.crop_portrait),
          ('16:9', Icons.crop_landscape),
          ('1:1', Icons.crop_square),
        ])
          _iconChoiceItem(
            icon: a.$2,
            label: a.$1,
            selected: _aspect == a.$1,
            onTap: () => setState(() => _aspect = a.$1),
          ),
      ]),
      const SizedBox(height: 6),
      const Text('Fill'),
      const SizedBox(height: 4),
      _iconChoiceRail([
        for (final e in const [
          ('none', 'Crop', Icons.crop),
          ('blur', 'Blur', Icons.blur_on),
          ('color', 'Colour', Icons.palette),
        ])
          _iconChoiceItem(
            icon: e.$3,
            label: e.$2,
            selected: _canvasFill == e.$1,
            onTap: () => setState(() => _canvasFill = e.$1),
          ),
      ]),
      if (_canvasFill == 'color') ...[
        const SizedBox(height: 6),
        const Text('Fill colour'),
        const SizedBox(height: 4),
        _iconChoiceRail([
          for (final e in const [
            ('black', 'Black', Color(0xFF000000)),
            ('white', 'White', Color(0xFFFFFFFF)),
            ('0x1A1A2E', 'Navy', Color(0xFF1A1A2E)),
            ('0x7C3AED', 'Purple', Color(0xFF7C3AED)),
          ])
            _iconChoiceItem(
              icon: Icons.circle,
              iconColor: e.$3,
              label: e.$2,
              selected: _canvasFillColor == e.$1,
              onTap: () => setState(() => _canvasFillColor = e.$1),
            ),
        ]),
      ],
      _sectionTitle('Intro / outro attach'),
      Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () async {
                final picked =
                    await _picker.pickVideo(source: ImageSource.gallery);
                if (picked != null) {
                  setState(() => _introClipPath = picked.path);
                }
              },
              icon: const Icon(Icons.movie_creation_outlined),
              label: Text(
                _introClipPath == null
                    ? 'Intro chunein'
                    : p.basename(_introClipPath!),
              ),
            ),
          ),
          if (_introClipPath != null)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () => setState(() => _introClipPath = null),
            ),
        ],
      ),
      const SizedBox(height: 6),
      Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () async {
                final picked =
                    await _picker.pickVideo(source: ImageSource.gallery);
                if (picked != null) {
                  setState(() => _outroClipPath = picked.path);
                }
              },
              icon: const Icon(Icons.movie_filter_outlined),
              label: Text(
                _outroClipPath == null
                    ? 'Outro chunein'
                    : p.basename(_outroClipPath!),
              ),
            ),
          ),
          if (_outroClipPath != null)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () => setState(() => _outroClipPath = null),
            ),
        ],
      ),
      const Text(
        'Attach export ke aakhir mein lagta hai: intro sab se '
        'pehle, outro sab se aakhir mein (export size par '
        'normalise karke).',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const Divider(height: 32),
    ];
  }

  /// Edit › Transform (§6.7) + the selected photo clip's Ken Burns
  /// controls (§6.1).
  List<Widget> _transformTabChildren() {
    final clip = _clips.isEmpty ? null : _clips[_selected];
    return [
      _sectionTitle('Transform — main clip'),
      _ProSlider(
        label: 'Scale',
        value: _tfScale,
        min: 0.5,
        max: 2,
        divisions: 30,
        onChanged: (v) => setState(() => _tfScale = v),
      ),
      _ProSlider(
        label: 'Position X',
        value: _tfX,
        min: -0.5,
        max: 0.5,
        divisions: 20,
        onChanged: (v) => setState(() => _tfX = v),
      ),
      _ProSlider(
        label: 'Position Y',
        value: _tfY,
        min: -0.5,
        max: 0.5,
        divisions: 20,
        onChanged: (v) => setState(() => _tfY = v),
      ),
      _ProSlider(
        label: 'Rotation (deg)',
        value: _tfRot,
        min: -45,
        max: 45,
        divisions: 90,
        digits: 0,
        onChanged: (v) => setState(() => _tfRot = v),
      ),
      _ProSlider(
        label: 'Opacity',
        value: _tfOpacity,
        min: 0.1,
        max: 1,
        divisions: 18,
        onChanged: (v) => setState(() => _tfOpacity = v),
      ),
      TextButton(
        onPressed: () => setState(() {
          _tfScale = 1;
          _tfX = 0;
          _tfY = 0;
          _tfRot = 0;
          _tfOpacity = 1;
        }),
        child: const Text('Transform reset'),
      ),
      const Text(
        'Transform export mein blurred backdrop par lagta hai — '
        'kaale kinare kabhi nahi aate.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      if (clip != null && clip.isPhoto) ...[
        _sectionTitle('Photo clip — Ken Burns'),
        SwitchListTile(
          title: const Text('Ken Burns (slow zoom)'),
          value: clip.kenBurns,
          onChanged: (v) => setState(() => clip.kenBurns = v),
        ),
        const Text('Zoom'),
        const SizedBox(height: 4),
        _iconChoiceRail([
          _iconChoiceItem(
            icon: Icons.zoom_in,
            label: 'Zoom in',
            selected: clip.kbZoomIn,
            onTap: () => setState(() => clip.kbZoomIn = true),
          ),
          _iconChoiceItem(
            icon: Icons.zoom_out,
            label: 'Zoom out',
            selected: !clip.kbZoomIn,
            onTap: () => setState(() => clip.kbZoomIn = false),
          ),
        ]),
        _ProSlider(
          label: 'Photo duration (s)',
          value: clip.duration.inMilliseconds / 1000,
          min: 1,
          max: 10,
          divisions: 18,
          digits: 1,
          onChanged: (v) {
            setState(() {
              final old = clip;
              final nc = VideoClip(
                old.file,
                Duration(milliseconds: (v * 1000).round()),
                old.aspectRatio,
              );
              nc.isPhoto = true;
              nc.kenBurns = old.kenBurns;
              nc.kbZoomIn = old.kbZoomIn;
              _clips[_selected] = nc;
            });
          },
        ),
      ],
      const Divider(height: 32),
    ];
  }

  List<Widget> _legacyPanelChildren(String toolKey) {
    switch (toolKey) {
      case 'stickers':
        return [
          const Text('Stickers / emoji overlay',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
TextField(
                decoration: const InputDecoration(
                  labelText: 'Sticker / emoji overlay',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _proSticker = v),
              ),
              const SizedBox(height: 8),
              const Text('Sticker preset'),
              const SizedBox(height: 4),
              _iconChoiceRail([
                for (final e in const [
                  ('fadeIn', Icons.gradient),
                  ('slideLeft', Icons.arrow_back),
                  ('slideRight', Icons.arrow_forward),
                  ('slideUp', Icons.arrow_upward),
                  ('zoomPop', Icons.zoom_in),
                ])
                  _iconChoiceItem(
                    icon: e.$2,
                    label: e.$1,
                    selected: _proStickerPreset == e.$1,
                    onTap: () =>
                        setState(() => _proStickerPreset = e.$1),
                  ),
              ]),
              const Divider(height: 32),
          const SizedBox(height: 12),
          const Text(
            'Keyframes animate the title/sticker overlay from start to end.',
            style: TextStyle(color: Colors.grey),
          ),
// Keyframes.
              SwitchListTile(
                title: const Text('Keyframes (motion title/sticker)'),
                subtitle: const Text(
                  'Start se end tak overlay move/scale/fade/rotate hoga.',
                ),
                value: _proKeyframes,
                onChanged: (v) => setState(() => _proKeyframes = v),
              ),
              if (_proKeyframes &&
                  _proTitle.trim().isEmpty &&
                  _proSticker.trim().isEmpty)
                const Text(
                  'Pehle motion title ya sticker likhein — keyframes usi '
                  'overlay par lagenge.',
                  style: TextStyle(color: Colors.grey),
                ),
              if (_proKeyframes &&
                  (_proTitle.trim().isNotEmpty ||
                      _proSticker.trim().isNotEmpty)) ...[
                // v1.3.0: the easing DROPDOWN is replaced by chips
                // + a curve graph at the top of the Keyframes
                // sub-tab (same _kfEasing state — presentation only).
                const SizedBox(height: 8),
                const Text('Start keyframe',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                _ProSlider(
                  label: 'Start X',
                  value: _kfStartX,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  onChanged: (v) => setState(() => _kfStartX = v),
                ),
                _ProSlider(
                  label: 'Start Y',
                  value: _kfStartY,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  onChanged: (v) => setState(() => _kfStartY = v),
                ),
                _ProSlider(
                  label: 'Start scale',
                  value: _kfStartScale,
                  min: 0.5,
                  max: 2,
                  divisions: 30,
                  onChanged: (v) => setState(() => _kfStartScale = v),
                ),
                _ProSlider(
                  label: 'Start opacity',
                  value: _kfStartOpacity,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  onChanged: (v) => setState(() => _kfStartOpacity = v),
                ),
                _ProSlider(
                  label: 'Start rotation',
                  value: _kfStartRotation,
                  min: -180,
                  max: 180,
                  divisions: 72,
                  digits: 0,
                  onChanged: (v) => setState(() => _kfStartRotation = v),
                ),
                const Text('End keyframe',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                _ProSlider(
                  label: 'End X',
                  value: _kfEndX,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  onChanged: (v) => setState(() => _kfEndX = v),
                ),
                _ProSlider(
                  label: 'End Y',
                  value: _kfEndY,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  onChanged: (v) => setState(() => _kfEndY = v),
                ),
                _ProSlider(
                  label: 'End scale',
                  value: _kfEndScale,
                  min: 0.5,
                  max: 2,
                  divisions: 30,
                  onChanged: (v) => setState(() => _kfEndScale = v),
                ),
                _ProSlider(
                  label: 'End opacity',
                  value: _kfEndOpacity,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  onChanged: (v) => setState(() => _kfEndOpacity = v),
                ),
                _ProSlider(
                  label: 'End rotation',
                  value: _kfEndRotation,
                  min: -180,
                  max: 180,
                  divisions: 72,
                  digits: 0,
                  onChanged: (v) => setState(() => _kfEndRotation = v),
                ),
              ],
              const Divider(height: 32),
        ];
      case 'effects':
        return [
          const Text('Effects',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Divider(height: 32),
          const Text('Shake effect',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Shake intensity'),
          const SizedBox(height: 4),
          _iconChoiceRail([
            for (final e in const [
              (ShakeFx.none, 'None', Icons.block),
              (ShakeFx.light, 'Light', Icons.air),
              (ShakeFx.medium, 'Medium', Icons.waves),
              (ShakeFx.strong, 'Strong', Icons.vibration),
            ])
              _iconChoiceItem(
                icon: e.$3,
                label: e.$2,
                selected: _fxShake == e.$1,
                onTap: () => setState(() => _fxShake = e.$1),
              ),
          ]),
          const SizedBox(height: 8),
        ];
      case 'titles':
        return [
          const Text('Motion titles',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
// Motion titles + sticker.
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Motion title (PNG render, Urdu-safe)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _proTitle = v),
              ),
              const SizedBox(height: 8),
              const Text('Title preset'),
              const SizedBox(height: 4),
              _iconChoiceRail([
                for (final e in const [
                  ('fadeIn', Icons.gradient),
                  ('slideLeft', Icons.arrow_back),
                  ('slideRight', Icons.arrow_forward),
                  ('slideUp', Icons.arrow_upward),
                  ('zoomPop', Icons.zoom_in),
                ])
                  _iconChoiceItem(
                    icon: e.$2,
                    label: e.$1,
                    selected: _proTitlePreset == e.$1,
                    onTap: () => setState(() => _proTitlePreset = e.$1),
                  ),
              ]),
              const SizedBox(height: 8),
              const Text('Title position'),
              const SizedBox(height: 4),
              _iconChoiceRail([
                for (final e in const [
                  ('topCenter', 'Top', Icons.vertical_align_top),
                  ('center', 'Center', Icons.vertical_align_center),
                  ('bottomCenter', 'Bottom', Icons.vertical_align_bottom),
                ])
                  _iconChoiceItem(
                    icon: e.$3,
                    label: e.$2,
                    selected: _proTitlePosition == e.$1,
                    onTap: () => setState(() => _proTitlePosition = e.$1),
                  ),
              ]),
              const SizedBox(height: 8),
          const Divider(height: 32),
        ];
      case 'filters':
        return [
          const Text('Filters',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
// Speed / filter / aspect
          const Text('Filter'),
          const SizedBox(height: 4),
          _iconChoiceRail([
            for (final e in const [
              ('Normal', Icons.photo),
              ('Warm', Icons.wb_sunny),
              ('Cool', Icons.ac_unit),
              ('B&W', Icons.filter_b_and_w),
              ('Vivid', Icons.palette),
              ('Sepia', Icons.history),
            ])
              _iconChoiceItem(
                icon: e.$2,
                label: e.$1,
                selected: _filter == e.$1,
                onTap: () => setState(() => _filter = e.$1),
              ),
          ]),
          const SizedBox(height: 8),
        ];
      case 'audio':
        return [
          const Text('Audio — music + waveform',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
// Music
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _pickMusic,
                  icon: const Icon(Icons.music_note),
                  label: Text(
                    _musicPath == null
                        ? 'Add music'
                        : p.basename(_musicPath!),
                  ),
                ),
              ),
              if (_musicPath != null)
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() => _musicPath = null),
                ),
            ],
          ),
          // CapCut-style music track gain: silent BGM mixing made common by
          // CapCut/VN's 2026 audio panels; applied to the music audio only.
          if (_musicPath != null)
            _ProSlider(
              label: 'Music volume',
              value: _musicVolume,
              min: 0,
              max: 1.5,
              divisions: 30,
              onChanged: (double v) {
                setState(() {
                  _musicVolume = v;
                });
              },
            ),
          const SizedBox(height: 12),
// Waveform.
              const Text('Waveform',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (_waveformBusy || _busy || _clips.isEmpty)
                          ? null
                          : _showWaveform,
                      icon: const Icon(Icons.show_chart),
                      label: Text(
                        _waveformBusy ? 'Generating…' : 'Show waveform',
                      ),
                    ),
                  ),
                ],
              ),
              if (_waveformPath != null) ...[
                const SizedBox(height: 8),
                Image.file(
                  File(_waveformPath!),
                  height: 60,
                  width: double.infinity,
                  fit: BoxFit.contain,
                ),
              ],
              const SizedBox(height: 8),
          const Divider(height: 32),
          const Text('Voice changer',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Voice effect'),
          const SizedBox(height: 4),
          _iconChoiceRail([
            for (final e in const [
              (VoiceFx.none, 'None', Icons.voice_over_off),
              (VoiceFx.chipmunk, 'Chipmunk', Icons.pets),
              (VoiceFx.deepVoice, 'Deep voice', Icons.graphic_eq),
              (VoiceFx.robot, 'Robot', Icons.smart_toy),
              (VoiceFx.echo, 'Echo', Icons.waves),
            ])
              _iconChoiceItem(
                icon: e.$3,
                label: e.$2,
                selected: _fxVoice == e.$1,
                onTap: () => setState(() => _fxVoice = e.$1),
              ),
          ]),
          _ProSlider(
            label: 'Fade in (s)',
            value: _fxFadeIn,
            min: 0,
            max: 3,
            divisions: 30,
            onChanged: (double v) {
              setState(() {
                _fxFadeIn = v;
              });
            },
          ),
          _ProSlider(
            label: 'Fade out (s)',
            value: _fxFadeOut,
            min: 0,
            max: 3,
            divisions: 30,
            onChanged: (double v) {
              setState(() {
                _fxFadeOut = v;
              });
            },
          ),
          SwitchListTile(
            title: const Text('Mute original audio'),
            subtitle: const Text(
              'Clip ki apni awaz band karein (music laga ho to ignore).',
            ),
            value: _muteOriginal,
            onChanged: (bool v) {
              setState(() {
                _muteOriginal = v;
              });
            },
          ),
          const Divider(height: 32),
          const Text('Cleanup',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Silence remover'),
            value: _fxSilenceRemove,
            onChanged: (bool v) {
              setState(() {
                _fxSilenceRemove = v;
              });
            },
          ),
          const SizedBox(height: 8),
        ];
      case 'speed':
        return [
          const Text('Speed — fixed speed + speed ramps',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
// Speed / filter / aspect
          const Text('Speed'),
          const SizedBox(height: 4),
          _iconChoiceRail([
            for (final e in const [
              (0.5, Icons.slow_motion_video),
              (0.75, Icons.speed),
              (1.0, Icons.play_arrow),
              (1.5, Icons.fast_forward),
              (2.0, Icons.double_arrow),
            ])
              _iconChoiceItem(
                icon: e.$2,
                label: '${e.$1}x',
                selected: _speed == e.$1,
                onTap: () => setState(() => _speed = e.$1),
              ),
          ]),
// Speed ramp.
              const Text('Speed ramp',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Ramp preset'),
              const SizedBox(height: 4),
              _iconChoiceRail([
                for (final e in const [
                  ('None', Icons.block),
                  ('slowMiddle', Icons.compress),
                  ('slowStart', Icons.trending_down),
                  ('slowEnd', Icons.trending_up),
                  ('pulse', Icons.show_chart),
                  ('Custom', Icons.tune),
                ])
                  _iconChoiceItem(
                    icon: e.$2,
                    label: e.$1,
                    selected: _proRamp == e.$1,
                    onTap: () => setState(() => _proRamp = e.$1),
                  ),
              ]),
              const Text(
                'Note: ramp on ho to fixed Speed dropdown ignore ho jata hai.',
                style: TextStyle(color: Colors.grey),
              ),
              const Divider(height: 32),
        ];
      case 'transitions':
        return [
          const Text('Transitions',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
if (AppConfig.crossfadeEnabled)
            SwitchListTile(
              title: const Text('Crossfade between clips'),
            subtitle: const Text('Simple fade transition when merging'),
            value: _crossfade,
            onChanged: (v) => setState(() => _crossfade = v),
          ),
          const Divider(height: 32),
          // ---- PRO tools (v2.1.0) ----
// Transitions.
              const Text('Transitions',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Transition'),
              const SizedBox(height: 4),
              _iconChoiceRail([
                for (final e in const [
                  ('fade', Icons.gradient),
                  ('slideleft', Icons.arrow_back),
                  ('slideright', Icons.arrow_forward),
                  ('slideup', Icons.arrow_upward),
                  ('slidedown', Icons.arrow_downward),
                  ('wipeleft', Icons.keyboard_arrow_left),
                  ('wiperight', Icons.keyboard_arrow_right),
                  ('wipeup', Icons.keyboard_arrow_up),
                  ('wipedown', Icons.keyboard_arrow_down),
                  ('circlecrop', Icons.circle_outlined),
                  ('dissolve', Icons.blur_on),
                  ('pixelize', Icons.grid_on),
                  ('smoothleft', Icons.keyboard_double_arrow_left),
                  ('smoothright', Icons.keyboard_double_arrow_right),
                  ('radial', Icons.radio_button_checked),
                  ('rectcrop', Icons.crop_square),
                  ('hblur', Icons.blur_linear),
                  ('circleopen', Icons.radio_button_unchecked),
                ])
                  _iconChoiceItem(
                    icon: e.$2,
                    label: e.$1,
                    selected: _proTransition == e.$1,
                    onTap: () => setState(() => _proTransition = e.$1),
                  ),
              ]),
              _ProSlider(
                label: 'Transition duration (s)',
                value: _proTransitionDur,
                min: 0.3,
                max: 2.0,
                divisions: 17,
                onChanged: (v) => setState(() => _proTransitionDur = v),
              ),
              const Text(
                'Sirf tab lagega jab Crossfade between clips ON ho; '
                'OFF par aaj ki tarah hard cuts rahenge.',
                style: TextStyle(color: Colors.grey),
              ),
              const Divider(height: 32),
        ];
      case 'overlays':
        return [
          const Text('Overlay — PIP video',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('PIP video overlay'),
            value: _fxPip,
            onChanged: (bool v) {
              setState(() {
                _fxPip = v;
              });
              _ensurePipPreview();
            },
          ),
          if (_fxPip)
            ElevatedButton.icon(
              onPressed: () async {
                final XFile? picked =
                    await _picker.pickVideo(source: ImageSource.gallery);
                if (picked != null) {
                  setState(() {
                    _fxPipVideo = picked.path;
                  });
                  _ensurePipPreview();
                }
              },
              icon: const Icon(Icons.video_library),
              label: Text(_fxPipVideo.isEmpty
                  ? 'Choose PIP video'
                  : p.basename(_fxPipVideo)),
            ),
          if (_fxPip) ...[
            const SizedBox(height: 8),
            const Text('PIP position'),
            const SizedBox(height: 4),
            _iconChoiceRail([
              for (final pos in PipPosition.values)
                _iconChoiceItem(
                  icon: switch (pos) {
                    PipPosition.topLeft => Icons.north_west,
                    PipPosition.topRight => Icons.north_east,
                    PipPosition.bottomLeft => Icons.south_west,
                    PipPosition.bottomRight => Icons.south_east,
                  },
                  label: pos.name,
                  selected: _pipPosition == pos,
                  onTap: () => setState(() => _pipPosition = pos),
                ),
            ]),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('PIP size'),
                Expanded(
                  child: Slider(
                    key: const Key('pipScaleSlider'),
                    value: _pipScale,
                    min: 0.15,
                    max: 0.5,
                    divisions: 7,
                    label: '${(_pipScale * 100).round()}%',
                    onChanged: (v) => setState(() => _pipScale = v),
                  ),
                ),
                Text('${(_pipScale * 100).round()}%'),
              ],
            ),
            if (_fxPipVideo.isEmpty)
              const Text(
                'PIP video chunein — bina inset video ke PIP export mein nahi lagega.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
          ],
          const Divider(height: 32),
        ];
      case 'news':
        return [
          const Text('News — template, ribbons, logo',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
// News template (shared with Live Studio).
          SwitchListTile(
            title: const Text('News Template (Live Studio wala)'),
            subtitle: const Text(
              'Breaking banner, lower-third, ticker, clock, logo — '
              'export par bhi lagega.',
            ),
            value: _newsEnabled,
            onChanged: (v) => setState(() => _newsEnabled = v),
          ),
          if (_newsEnabled) ...[
            TextFormField(
              initialValue: _news.breakingHeadline,
              decoration: const InputDecoration(
                labelText: 'Breaking headline (surkh patti)',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                _news.breakingHeadline = v;
                unawaited(_news.save());
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: _news.lowerTitle,
              decoration: const InputDecoration(
                labelText: 'Lower-third title (naam)',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                _news.lowerTitle = v;
                unawaited(_news.save());
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: _news.lowerSubtitle,
              decoration: const InputDecoration(
                labelText: 'Lower-third subtitle (ohda / jagah)',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                _news.lowerSubtitle = v;
                unawaited(_news.save());
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: _news.tickerText,
              decoration: const InputDecoration(
                labelText: 'Ticker text (neeche chalta hua)',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                _news.tickerText = v;
                unawaited(_news.save());
              },
            ),
            SwitchListTile(
              title: const Text('Live clock / date dikhayein'),
              value: _news.showClock,
              onChanged: (v) {
                setState(() => _news.showClock = v);
                unawaited(_news.save());
              },
            ),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final picked = await _picker.pickImage(
                        source: ImageSource.gallery,
                      );
                      if (picked == null) return;
                      setState(() => _news.logoPath = picked.path);
                      await _news.save();
                    },
                    icon: const Icon(Icons.image),
                    label: Text(
                      _news.logoPath == null
                          ? 'Logo chunein'
                          : 'Logo badlein',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Logo jagah'),
            const SizedBox(height: 4),
            _iconChoiceRail([
              for (final pos in LogoPosition.values)
                _iconChoiceItem(
                  icon: switch (pos) {
                    LogoPosition.topLeft => Icons.north_west,
                    LogoPosition.topRight => Icons.north_east,
                    LogoPosition.bottomLeft => Icons.south_west,
                    LogoPosition.bottomRight => Icons.south_east,
                  },
                  label: pos.label,
                  selected: _news.logoPosition == pos,
                  onTap: () {
                    setState(() => _news.logoPosition = pos);
                    unawaited(_news.save());
                  },
                ),
            ]),
            SwitchListTile(
              title: const Text('Logo ahista ghoome (rotation)'),
              subtitle: const Text('Sirf live me ghoomega; export me static.'),
              value: _news.logoRotate,
              onChanged: (v) {
                setState(() => _news.logoRotate = v);
                unawaited(_news.save());
              },
            ),
            const Text(
              'Note: News Studio ke Final-template (nigraanFinal) '
              'project ka export ANIMATED hota hai — dono ribbons '
              'scroll karti hain, logo ghoomta hai, clock tick karta '
              'hai. Plain editor ke live design ka export ek still '
              'frame rehta hai. Yehi template Live Studio me bhi use '
              'hota hai.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
          const Divider(height: 32),
        ];
      case 'captions':
        return [
const Text('Auto Captions (CapCut-style)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _iconChoiceRail([
                  _iconChoiceItem(
                    icon: Icons.translate,
                    label: 'Urdu',
                    selected: _captionLocale == 'ur',
                    onTap: () => setState(() => _captionLocale = 'ur'),
                  ),
                  _iconChoiceItem(
                    icon: Icons.abc,
                    label: 'English',
                    selected: _captionLocale == 'en',
                    onTap: () => setState(() => _captionLocale = 'en'),
                  ),
                ]),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed:
                      (_transcribing || _busy) ? null : _generateCaptions,
                  icon: const Icon(Icons.closed_caption),
                  label: Text(
                    _transcribing ? 'Transcribing…' : 'Generate Auto Captions',
                  ),
                ),
              ),
            ],
          ),
          if (_transcribing) ...[
            const SizedBox(height: 8),
            const Row(
              children: [
                Expanded(
                  child: Text(
                    'Video ki apni audio se captions ban rahe hain…',
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          const Text('Caption style'),
          const SizedBox(height: 4),
          _iconChoiceRail([
            for (final e in const [
              (CaptionStyle.standard, 'Default', Icons.closed_caption),
              (CaptionStyle.highlight, 'Highlight', Icons.highlight),
              (CaptionStyle.gold, 'Gold', Icons.star),
              (CaptionStyle.clean, 'Clean', Icons.format_clear),
              (CaptionStyle.pop, 'Pop', Icons.bolt),
              (CaptionStyle.boxed, 'Boxed', Icons.check_box_outline_blank),
            ])
              _iconChoiceItem(
                icon: e.$3,
                label: e.$2,
                selected: _captionStyle == e.$1,
                onTap: () => setState(() => _captionStyle = e.$1),
              ),
          ]),
          if (_captions.isNotEmpty && !_transcribing) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_captions.length} caption segments ready — export me video par jal jayenge.',
                  ),
                ),
                TextButton(
                  onPressed: _editCaptions,
                  child: const Text('Edit'),
                ),
                TextButton(
                  onPressed: () => setState(() => _captions = []),
                  child: const Text('Clear'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'Note: captions video ki apni audio se on-device banenge (whisper, Urdu/English) — mic, quiet room ya earphones ki koi pabandi nahi. Pehli dafa ~75 MB caption model download hoga (progress ke saath); us ke baad sab kuch phone par hi, offline hota hai.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 12),
        ];
      case 'stabilization':
        return [
// Stabilization.
              SwitchListTile(
                title: const Text('Stabilization'),
                subtitle: const Text(
                  'Vidstab jab available ho, warna deshake engine use hoga.',
                ),
                value: _proStabilize,
                onChanged: (v) => setState(() => _proStabilize = v),
              ),
              const Divider(height: 32),
        ];
      case 'chroma':
        return [
          const Text('Chromakey / BG remover',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
// Chromakey.
              SwitchListTile(
                title: const Text('Chromakey'),
                subtitle: const Text(
                  'Green/blue background hatakar naya background lagayein.',
                ),
                value: _proChroma,
                onChanged: (v) => setState(() => _proChroma = v),
              ),
              if (_proChroma) ...[
                // v1.4.0 (brief): 'Drag to select color' — the
                // circular picker over the preview frame (the
                // eyedropper dialog samples the exact tapped pixel
                // and keys it live). Below it ONLY the two CapCut
                // sliders are primary: Intensity (= Similarity) and
                // Shadow (= Blend); Spill/Edge stay as the existing
                // advanced controls (nothing is removed).
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _eyedropperPick,
                    icon: const Icon(Icons.colorize),
                    label: const Text('Drag to select color'),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Intensity = Similarity slider, Shadow = Blend '
                  'slider (neeche) — rang select karte hi live '
                  'preview update hota hai.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 8),
                const Text('Key color — preset ya eyedropper se sample karein'),
                Row(
                  children: [
                    Expanded(
                      child: _iconChoiceRail([
                        _iconChoiceItem(
                          icon: Icons.circle,
                          iconColor: Colors.green,
                          label: 'Green',
                          selected: _proChromaColor == 'green',
                          onTap: () {
                            setState(() => _proChromaColor = 'green');
                            _scheduleChromaPreview();
                          },
                        ),
                        _iconChoiceItem(
                          icon: Icons.circle,
                          iconColor: Colors.blue,
                          label: 'Blue',
                          selected: _proChromaColor == 'blue',
                          onTap: () {
                            setState(() => _proChromaColor = 'blue');
                            _scheduleChromaPreview();
                          },
                        ),
                      ]),
                    ),
                    IconButton(
                      tooltip: 'Eyedropper — frame par tap karke rang chunein',
                      onPressed: _eyedropperPick,
                      icon: const Icon(Icons.colorize),
                    ),
                  ],
                ),
                if (_proChromaColor.startsWith('#'))
                  Text(
                    'Sampled color: $_proChromaColor',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                _ProSlider(
                  label: 'Similarity',
                  value: _proChromaSimilarity,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  onChanged: (v) {
                    setState(() => _proChromaSimilarity = v);
                    _scheduleChromaPreview();
                  },
                ),
                _ProSlider(
                  label: 'Blend',
                  value: _proChromaBlend,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  onChanged: (v) {
                    setState(() => _proChromaBlend = v);
                    _scheduleChromaPreview();
                  },
                ),
                _ProSlider(
                  label: 'Spill (sabz kinara saaf)',
                  value: _proChromaSpill,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  onChanged: (v) {
                    setState(() => _proChromaSpill = v);
                    _scheduleChromaPreview();
                  },
                ),
                _ProSlider(
                  label: 'Edge (shrink - grow)',
                  value: _proChromaEdge,
                  min: -1,
                  max: 1,
                  divisions: 20,
                  onChanged: (v) {
                    setState(() => _proChromaEdge = v);
                    _scheduleChromaPreview();
                  },
                ),
                const Text('Background kind'),
                const SizedBox(height: 4),
                _iconChoiceRail([
                  _iconChoiceItem(
                    icon: Icons.palette,
                    label: 'Color',
                    selected: _proChromaBgKind == 'color',
                    onTap: () {
                      setState(() => _proChromaBgKind = 'color');
                      _scheduleChromaPreview();
                    },
                  ),
                  _iconChoiceItem(
                    icon: Icons.image,
                    label: 'Image',
                    selected: _proChromaBgKind == 'image',
                    onTap: () {
                      setState(() => _proChromaBgKind = 'image');
                      _scheduleChromaPreview();
                    },
                  ),
                ]),
                if (_proChromaBgKind == 'color') ...[
                  const Text('Background color'),
                  const SizedBox(height: 4),
                  _iconChoiceRail([
                    for (final e in const [
                      ('#00FF00', 'Green', Color(0xFF00FF00)),
                      ('#0000FF', 'Blue', Color(0xFF0000FF)),
                      ('#000000', 'Black', Color(0xFF000000)),
                      ('#FFFFFF', 'White', Color(0xFFFFFFFF)),
                    ])
                      _iconChoiceItem(
                        icon: Icons.circle,
                        iconColor: e.$3,
                        label: e.$2,
                        selected: _proChromaBgColor == e.$1,
                        onTap: () {
                          setState(() => _proChromaBgColor = e.$1);
                          _scheduleChromaPreview();
                        },
                      ),
                  ]),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Custom color (#RRGGBB)',
                      hintText: '#1A2B3C',
                    ),
                    onSubmitted: (v) {
                      final t = v.trim();
                      if (RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(t)) {
                        setState(() => _proChromaBgColor = t.toUpperCase());
                        _scheduleChromaPreview();
                      } else {
                        _setStatus('Rang #RRGGBB format mein likhein.');
                      }
                    },
                  ),
                ],
                if (_proChromaBgKind == 'image')
                  ElevatedButton.icon(
                    onPressed: () => _pickProImage(
                      (path) => _proChromaBgImage = path,
                    ),
                    icon: const Icon(Icons.image),
                    label: Text(
                      _proChromaBgImage == null
                          ? 'Background image chunein'
                          : p.basename(_proChromaBgImage!),
                    ),
                  ),
              ],
                if (_proChroma) ...[
                  const Divider(height: 32),
                  const Text('Backdrop shortcuts',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _iconChoiceRail([
                    _iconChoiceItem(
                      icon: Icons.meeting_room,
                      label: 'Newsroom',
                      selected: false,
                      onTap: () => _applyBackdropAsset(
                          'assets/backgrounds/newsroom.jpg'),
                    ),
                    _iconChoiceItem(
                      icon: Icons.desktop_windows,
                      label: 'Studio Desk',
                      selected: false,
                      onTap: () => _applyBackdropAsset(
                          'assets/backgrounds/studio_desk.jpg'),
                    ),
                    _iconChoiceItem(
                      icon: Icons.tv,
                      label: 'News anchor preset',
                      selected: false,
                      onTap: _applyNewsAnchorPreset,
                    ),
                  ]),
                  const SizedBox(height: 12),
                  const Text('Live preview (export jesa result)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_chromaPreviewPath != null)
                    Image.file(
                      File(_chromaPreviewPath!),
                      height: 160,
                      width: double.infinity,
                      fit: BoxFit.contain,
                    )
                  else
                    const Text(
                      'Slider badalte hi keyed frame yahan dikhega — '
                      'ya Preview button dabayein.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed:
                        _chromaPreviewBusy ? null : _refreshChromaPreview,
                    icon: const Icon(Icons.visibility),
                    label: Text(_chromaPreviewBusy
                        ? 'Preview ban raha…'
                        : 'Preview dekhein'),
                  ),
                  if (_proBgRemove)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Note: ML background remover bhi ON hai — '
                        'export mein wohi lagega, chromakey nahi '
                        '(dono ek saath nahi chalte).',
                        style:
                            TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                    ),
                ],
              const Divider(height: 32),
// Video BG remover.
              SwitchListTile(
                title: const Text('Video background remover (ML)'),
                subtitle: const Text(
                  'Premium AI: 50 coins se unlock hoga (is session '
                  'ke liye). Export mein pehle MODNet HQ matte lagta '
                  'hai; live preview ML Kit segmentation se hai.',
                ),
                value: _proBgRemove,
                onChanged: _onBgRemoverChanged,
              ),
              if (_proBgRemove) ...[
                const Text('Background kind'),
                const SizedBox(height: 4),
                _iconChoiceRail([
                  _iconChoiceItem(
                    icon: Icons.palette,
                    label: 'Color',
                    selected: _proBgKind == 'color',
                    onTap: () => setState(() => _proBgKind = 'color'),
                  ),
                  _iconChoiceItem(
                    icon: Icons.image,
                    label: 'Image',
                    selected: _proBgKind == 'image',
                    onTap: () => setState(() => _proBgKind = 'image'),
                  ),
                ]),
                if (_proBgKind == 'color') ...[
                  const SizedBox(height: 6),
                  const Text('Background color'),
                  const SizedBox(height: 4),
                  _iconChoiceRail([
                    for (final e in const [
                      ('#00FF00', 'Green', Color(0xFF00FF00)),
                      ('#0000FF', 'Blue', Color(0xFF0000FF)),
                      ('#000000', 'Black', Color(0xFF000000)),
                      ('#FFFFFF', 'White', Color(0xFFFFFFFF)),
                    ])
                      _iconChoiceItem(
                        icon: Icons.circle,
                        iconColor: e.$3,
                        label: e.$2,
                        selected: _proBgColor == e.$1,
                        onTap: () => setState(() => _proBgColor = e.$1),
                      ),
                  ]),
                ],
                if (_proBgKind == 'image')
                  ElevatedButton.icon(
                    onPressed: () =>
                        _pickProImage((path) => _proBgImage = path),
                    icon: const Icon(Icons.image),
                    label: Text(
                      _proBgImage == null
                          ? 'Background image chunein'
                          : p.basename(_proBgImage!),
                    ),
                  ),
              ],
              const Text(
                'Note: lambi clips par minutes lag sakte hain; width '
                'capped hai; saaf subject wali video par behtareen '
                'result milta hai. Progress export status me dikhega.',
                style: TextStyle(color: Colors.grey),
              ),
              const Divider(height: 32),
        ];
      case 'tracking':
        return [
// Motion tracking.
              const Text('Motion tracking (ML)',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const Text(
                'Preview video par object ko tap karein, phir Track '
                'dabayein. (Preview 16:9 box hai, is liye tap point '
                'approximate hai.)',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Tracked sticker text',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _trackSticker = v),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (_trackStartX == null ||
                              _tracking ||
                              _busy)
                          ? null
                          : _trackObject,
                      icon: const Icon(Icons.my_location),
                      label: Text(_tracking ? 'Tracking…' : 'Track object'),
                    ),
                  ),
                ],
              ),
              if (_trackStartX != null)
                Text(
                  'Tapped: (${_trackStartX!.toStringAsFixed(2)}, ${_trackStartY!.toStringAsFixed(2)})',
                ),
              if (_trackPoints.isNotEmpty)
                Text('${_trackPoints.length} track points ready.'),
              const Divider(height: 32),
        ];
      case 'beats':
        return [
// Beat sync.
              const Text('Beat sync',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (_detectingBeats || _busy || _clips.isEmpty)
                          ? null
                          : _detectBeats,
                      icon: const Icon(Icons.graphic_eq),
                      label: Text(
                        _detectingBeats ? 'Detecting…' : 'Detect beats',
                      ),
                    ),
                  ),
                ],
              ),
              if (_beats.isNotEmpty)
                Text(
                  '${_beats.length} beats — '
                  '${_beats.take(5).map((b) => '${b.toStringAsFixed(1)}s').join(', ')}'
                  '${_beats.length > 5 ? ', …' : ''}',
                ),
              SwitchListTile(
                title: const Text('Beat auto-cut'),
                subtitle: const Text(
                  'Single clip ko beat boundaries par kaatkar jorega.',
                ),
                value: _beatAutoCut,
                onChanged: (v) => setState(() => _beatAutoCut = v),
              ),
              if (_beatAutoCut && _clips.length > 1)
                const Text(
                  'Note: multi-clip me beat auto-cut nahi lagta — sirf '
                  'markers dikhenge; cut sirf single clip par hota hai. '
                  'Auto-cut OFF rakhein to single clip par bhi sirf '
                  'markers rehte hain.',
                  style: TextStyle(color: Colors.grey),
                ),
              const Divider(height: 32),
        ];
      case 'grading':
        return [
// Grading.
              const Text('Grading',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('LUT look'),
              const SizedBox(height: 4),
              _iconChoiceRail([
                for (final e in proLuts)
                  _iconChoiceItem(
                    icon: (e['name'] ?? '').isEmpty
                        ? Icons.block
                        : Icons.photo_filter,
                    label: (e['name'] ?? '').isEmpty ? 'None' : e['name']!,
                    selected: _proLut == (e['name'] ?? ''),
                    onTap: () => setState(() => _proLut = e['name'] ?? ''),
                  ),
              ]),
              _ProSlider(
                label: 'Temperature',
                value: _proTemperature,
                min: -100,
                max: 100,
                divisions: 40,
                digits: 0,
                onChanged: (v) => setState(() => _proTemperature = v),
              ),
              _ProSlider(
                label: 'Tint',
                value: _proTint,
                min: -100,
                max: 100,
                divisions: 40,
                digits: 0,
                onChanged: (v) => setState(() => _proTint = v),
              ),
              _ProSlider(
                label: 'Saturation',
                value: _proSaturation,
                min: 0,
                max: 2,
                divisions: 40,
                onChanged: (v) => setState(() => _proSaturation = v),
              ),
              _ProSlider(
                label: 'Vibrance',
                value: _proVibrance,
                min: 0,
                max: 2,
                divisions: 40,
                onChanged: (v) => setState(() => _proVibrance = v),
              ),
              _ProSlider(
                label: 'Contrast',
                value: _proContrast,
                min: 0,
                max: 2,
                divisions: 40,
                onChanged: (v) => setState(() => _proContrast = v),
              ),
              _ProSlider(
                label: 'Shadows',
                value: _proShadows,
                min: -100,
                max: 100,
                divisions: 40,
                digits: 0,
                onChanged: (v) => setState(() => _proShadows = v),
              ),
              _ProSlider(
                label: 'Highlights',
                value: _proHighlights,
                min: -100,
                max: 100,
                divisions: 40,
                digits: 0,
                onChanged: (v) => setState(() => _proHighlights = v),
              ),
              _ProSlider(
                label: 'Brightness',
                value: _proBrightness,
                min: -100,
                max: 100,
                divisions: 40,
                digits: 0,
                onChanged: (v) => setState(() => _proBrightness = v),
              ),
              _ProSlider(
                label: 'Exposure',
                value: _proExposure,
                min: -100,
                max: 100,
                divisions: 40,
                digits: 0,
                onChanged: (v) => setState(() => _proExposure = v),
              ),
              const Divider(height: 32),
        ];
      case 'live':
        return [
          const Text('Live Studio',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'Facebook + YouTube par ek saath live — breaking news '
            'templates ke saath. Live Studio apni screen par khulta hai.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LiveStudioScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.live_tv),
              label: const Text('Open Live Studio'),
            ),
          ),
        ];
      case 'filtersRow':
        // v1.3.0 (§5A Colour › Filters): chip row instead of the
        // dropdown (same _filter state) + the §6.1 intensity
        // slider. The stage preview updates LIVE via the colour
        // matrix; the export scales the same ffmpeg filter.
        return [
          const Text('Filters — LIVE preview stage par',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _iconChoiceRail([
            for (final e in const [
              ('Normal', Icons.photo),
              ('Warm', Icons.wb_sunny),
              ('Cool', Icons.ac_unit),
              ('B&W', Icons.filter_b_and_w),
              ('Vivid', Icons.palette),
              ('Sepia', Icons.history),
            ])
              _iconChoiceItem(
                icon: e.$2,
                label: e.$1,
                selected: _filter == e.$1,
                onTap: () => setState(() => _filter = e.$1),
              ),
          ]),
          _ProSlider(
            label: 'Filter intensity',
            value: _filterIntensity,
            min: 0,
            max: 1,
            divisions: 20,
            onChanged: (v) => setState(() => _filterIntensity = v),
          ),
          const Text(
            'Note: LUT looks sirf export mein lagte hain (file-based '
            'hain) — stage preview mein filter + Adjust ke values '
            'live dikhte hain.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const Divider(height: 32),
        ];
      case 'gradingOne':
        // v1.3.0 (§5A Colour › Adjust): the LUT dropdown stays on
        // top; below it ONE grade slider at a time, picked by
        // chips (same state as the old all-sliders list).
        return [
          const Text('Adjust — ek waqt mein ek slider',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('LUT look'),
          const SizedBox(height: 4),
          _iconChoiceRail([
            for (final e in proLuts)
              _iconChoiceItem(
                icon: (e['name'] ?? '').isEmpty
                    ? Icons.block
                    : Icons.photo_filter,
                label: (e['name'] ?? '').isEmpty ? 'None' : e['name']!,
                selected: _proLut == (e['name'] ?? ''),
                onTap: () => setState(() => _proLut = e['name'] ?? ''),
              ),
          ]),
          const SizedBox(height: 8),
          _iconChoiceRail([
            for (final e in const [
              ('Temperature', Icons.thermostat),
              ('Tint', Icons.colorize),
              ('Saturation', Icons.palette),
              ('Vibrance', Icons.color_lens),
              ('Contrast', Icons.contrast),
              ('Shadows', Icons.dark_mode),
              ('Highlights', Icons.light_mode),
              ('Brightness', Icons.brightness_6),
              ('Exposure', Icons.exposure),
            ])
              _iconChoiceItem(
                icon: e.$2,
                label: e.$1,
                selected: _gradeSlider == e.$1,
                onTap: () => setState(() => _gradeSlider = e.$1),
              ),
          ]),
          const SizedBox(height: 8),
          _gradeSliderWidget(),
          const Divider(height: 32),
        ];
      case 'newsTemplate':
        // v1.3.0 (§5A News › Template): the master switch + the
        // Live Studio entry (the old 'live' panel body).
        return [
          const Text('News — template',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('News Template (Live Studio wala)'),
            subtitle: const Text(
              'Breaking banner, lower-third, ticker, clock, logo — '
              'export par bhi lagega.',
            ),
            value: _newsEnabled,
            onChanged: (v) => setState(() => _newsEnabled = v),
          ),
          if (_projectTemplateKind == 'nigraanFinal')
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Ye project Final template (nigraanFinal) hai: is ka '
                'export ANIMATED lagega — Final 3-Ribbon design '
                '(neeche English ticker hamesha scroll, Urdu '
                'ribbons lambi text par scroll), ghoomta logo aur '
                'us ke neeche date capsule (bilkul asal Nigraan '
                'video jaisa). Classic 2-Ribbon design Template '
                'Studio se select ho sakta hai.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          const Divider(height: 32),
          ..._panelBody('live'),
        ];
      case 'newsText':
        // v1.3.0 (§5A News › Text): the four template text fields
        // + the clock toggle (same _news state as before).
        return [
          const Text('News — text fields',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (!_newsEnabled)
            const Text(
              'Pehle Template tab mein News Template ON karein.',
              style: TextStyle(color: Colors.grey),
            )
          else ...[
            TextFormField(
              initialValue: _news.breakingHeadline,
              decoration: const InputDecoration(
                labelText: 'Breaking headline (surkh patti)',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                _news.breakingHeadline = v;
                unawaited(_news.save());
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: _news.lowerTitle,
              decoration: const InputDecoration(
                labelText: 'Lower-third title (naam)',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                _news.lowerTitle = v;
                unawaited(_news.save());
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: _news.lowerSubtitle,
              decoration: const InputDecoration(
                labelText: 'Lower-third subtitle (ohda / jagah)',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                _news.lowerSubtitle = v;
                unawaited(_news.save());
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: _news.tickerText,
              decoration: const InputDecoration(
                labelText: 'Ticker text (neeche chalta hua)',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                _news.tickerText = v;
                unawaited(_news.save());
              },
            ),
            SwitchListTile(
              title: const Text('Live clock / date dikhayein'),
              value: _news.showClock,
              onChanged: (v) {
                setState(() => _news.showClock = v);
                unawaited(_news.save());
              },
            ),
          ],
          const Divider(height: 32),
        ];
      case 'newsLogo':
        // v1.3.0 (§5A News › Logo): logo pick + position + rotation.
        return [
          const Text('News — logo',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (!_newsEnabled)
            const Text(
              'Pehle Template tab mein News Template ON karein.',
              style: TextStyle(color: Colors.grey),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final picked = await _picker.pickImage(
                        source: ImageSource.gallery,
                      );
                      if (picked == null) return;
                      setState(() => _news.logoPath = picked.path);
                      await _news.save();
                    },
                    icon: const Icon(Icons.image),
                    label: Text(
                      _news.logoPath == null
                          ? 'Logo chunein'
                          : 'Logo badlein',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Logo jagah'),
            const SizedBox(height: 4),
            _iconChoiceRail([
              for (final pos in LogoPosition.values)
                _iconChoiceItem(
                  icon: switch (pos) {
                    LogoPosition.topLeft => Icons.north_west,
                    LogoPosition.topRight => Icons.north_east,
                    LogoPosition.bottomLeft => Icons.south_west,
                    LogoPosition.bottomRight => Icons.south_east,
                  },
                  label: pos.label,
                  selected: _news.logoPosition == pos,
                  onTap: () {
                    setState(() => _news.logoPosition = pos);
                    unawaited(_news.save());
                  },
                ),
            ]),
            SwitchListTile(
              title: const Text('Logo ahista ghoome (rotation)'),
              subtitle: const Text(
                'Live mein ghoomega; Final-template export mein '
                'logo asal template ki jagah par ghoomta hai, baqi '
                'exports mein static rehta hai.',
              ),
              value: _news.logoRotate,
              onChanged: (v) {
                setState(() => _news.logoRotate = v);
                unawaited(_news.save());
              },
            ),
            const Text(
              'Note: News Studio ke Final-template (nigraanFinal) '
              'project ka export ANIMATED hota hai — dono ribbons '
              'scroll karti hain, logo ghoomta hai, clock tick karta '
              'hai. Plain editor ke live design ka export ek still '
              'frame rehta hai. Yehi template Live Studio me bhi use '
              'hota hai.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
          const Divider(height: 32),
        ];
      case 'text':
      default:
        return [
          const Text('Text overlay',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
// Text overlay
          TextField(
            decoration: const InputDecoration(
              labelText: 'Text overlay (single line)',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _text = v),
          ),
          const SizedBox(height: 12),
          const Divider(height: 32),
        ];
    }
  }

  /// v1.4.0 clip-selected row › Volume: the SELECTED clip's own
  /// gain + mute (materialised at export — see _exportInner) and
  /// its unlink state.
  /// v1.5.0 Volume panel (InShot [TUT9]): ONE % slider (max 200%
  /// — best-knowledge, InShot's max was never verified on video),
  /// Mute, Denoise (the op lives here, not in Voice Enhance) and
  /// Extract audio. The slider applies the gain to the LIVE
  /// preview as well as the export model.
  List<Widget> _volumePanelChildren() {
    final clip = _clips.isEmpty ? null : _clips[_selected];
    if (clip == null) {
      return const [
        Text(
          'Pehle timeline se clip select karein.',
          style: TextStyle(color: Colors.grey),
        ),
      ];
    }
    return [
      _sectionTitle('Clip ${_selected + 1} — volume'),
      _ProSlider(
        label: 'Clip volume',
        value: clip.volume.clamp(0, 2),
        min: 0,
        max: 2,
        divisions: 40,
        onChanged: (v) {
          setState(() => clip.volume = v);
          unawaited(
            _controller?.setVolume(clip.muted ? 0 : v) ??
                Future<void>.value(),
          );
        },
      ),
      SwitchListTile(
        title: const Text('Mute clip'),
        subtitle: const Text('Is clip ki awaz export mein nahi aayegi.'),
        value: clip.muted,
        onChanged: (v) {
          setState(() => clip.muted = v);
          unawaited(
            _controller?.setVolume(v ? 0 : clip.volume) ??
                Future<void>.value(),
          );
        },
      ),
      if (clip.detachedAudioPath != null)
        Text(
          'Audio unlinked hai: ${p.basename(clip.detachedAudioPath!)} '
          '(alag track par hai).',
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
      const Text(
        'Volume sirf is clip par lagta hai — baqi clips ki awaz '
        'apni jagah rehti hai.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      _sectionTitle('Audio ops'),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () =>
                      unawaited(_enhanceSelectedClipAudio(voice: false)),
              icon: const Icon(Icons.noise_control_off, size: 18),
              label: const Text('Denoise'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _extractClipAudio,
              icon: const Icon(Icons.audio_file, size: 18),
              label: const Text('Extract audio'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _busy ? null : _unlinkSelectedClipAudio,
          icon: const Icon(Icons.link_off, size: 18),
          label: const Text('Unlink audio (alag track)'),
        ),
      ),
      const Divider(height: 32),
    ];
  }

  /// v1.4.0 Colour › Adjust (brief: tabs Filters | Adjust — the
  /// tabs live in [_panelTabs]; here: the LUT rail, ONE circular
  /// icon row of adjust items, ONE shared slider, Reset + ✓ (the
  /// panel header's Done is the ✓). 'Auto adjust' is a toggle in
  /// the row (ffmpeg normalize at export). HSL is not offered:
  /// the bundled ffmpeg has no per-hue-range HSL filter, and a
  /// fake slider is worse than none (see _adjustExtraFilter).
  List<Widget> _adjustPanelChildren() {
    return [
      const Text('Adjust — ek waqt mein ek slider',
          style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('LUT look'),
      const SizedBox(height: 4),
      _iconChoiceRail([
        for (final e in proLuts)
          _iconChoiceItem(
            icon: (e['name'] ?? '').isEmpty
                ? Icons.block
                : Icons.photo_filter,
            label: (e['name'] ?? '').isEmpty ? 'None' : e['name']!,
            selected: _proLut == (e['name'] ?? ''),
            onTap: () => setState(() => _proLut = e['name'] ?? ''),
          ),
      ]),
      const SizedBox(height: 8),
      _iconChoiceRail([
        _iconChoiceItem(
          icon: Icons.auto_fix_high,
          label: 'Auto adjust',
          selected: _adjAuto,
          onTap: () => setState(() => _adjAuto = !_adjAuto),
        ),
        for (final e in const [
          ('Brightness', Icons.brightness_6),
          ('Contrast', Icons.contrast),
          ('Saturation', Icons.palette),
          ('Brilliance', Icons.lightbulb_outline),
          ('Sharpen', Icons.details),
          ('Clarity', Icons.filter_drama_outlined),
          ('Highlights', Icons.light_mode),
          ('Shadows', Icons.dark_mode),
          ('Whites', Icons.wb_sunny),
          ('Blacks', Icons.nightlight_round),
          ('Temperature', Icons.thermostat),
          ('Tint', Icons.colorize),
          ('Vibrance', Icons.color_lens),
          ('Exposure', Icons.exposure),
          ('Hue', Icons.gradient),
          ('Fade', Icons.waves),
          ('Vignette', Icons.vignette),
          ('Grain', Icons.grain),
        ])
          _iconChoiceItem(
            icon: e.$2,
            label: e.$1,
            selected: _gradeSlider == e.$1,
            onTap: () => setState(() => _gradeSlider = e.$1),
          ),
      ]),
      const SizedBox(height: 8),
      _gradeSliderWidget(),
      const SizedBox(height: 4),
      Row(
        children: [
          TextButton.icon(
            onPressed: _resetGrade,
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('Reset'),
          ),
          const Spacer(),
          const Text(
            'Har item per selected clip ke export par lagta hai.',
            style: TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ],
      ),
      const Divider(height: 32),
    ];
  }

  /// The ONE grade slider currently picked on Colour › Adjust.
  Widget _gradeSliderWidget() {
    switch (_gradeSlider) {
      case 'Temperature':
        return _ProSlider(
          label: 'Temperature',
          value: _proTemperature,
          min: -100,
          max: 100,
          divisions: 40,
          digits: 0,
          onChanged: (v) => setState(() => _proTemperature = v),
        );
      case 'Tint':
        return _ProSlider(
          label: 'Tint',
          value: _proTint,
          min: -100,
          max: 100,
          divisions: 40,
          digits: 0,
          onChanged: (v) => setState(() => _proTint = v),
        );
      case 'Saturation':
        return _ProSlider(
          label: 'Saturation',
          value: _proSaturation,
          min: 0,
          max: 2,
          divisions: 40,
          onChanged: (v) => setState(() => _proSaturation = v),
        );
      case 'Vibrance':
        return _ProSlider(
          label: 'Vibrance',
          value: _proVibrance,
          min: 0,
          max: 2,
          divisions: 40,
          onChanged: (v) => setState(() => _proVibrance = v),
        );
      case 'Contrast':
        return _ProSlider(
          label: 'Contrast',
          value: _proContrast,
          min: 0,
          max: 2,
          divisions: 40,
          onChanged: (v) => setState(() => _proContrast = v),
        );
      case 'Shadows':
        return _ProSlider(
          label: 'Shadows',
          value: _proShadows,
          min: -100,
          max: 100,
          divisions: 40,
          digits: 0,
          onChanged: (v) => setState(() => _proShadows = v),
        );
      case 'Highlights':
        return _ProSlider(
          label: 'Highlights',
          value: _proHighlights,
          min: -100,
          max: 100,
          divisions: 40,
          digits: 0,
          onChanged: (v) => setState(() => _proHighlights = v),
        );
      case 'Brightness':
        return _ProSlider(
          label: 'Brightness',
          value: _proBrightness,
          min: -100,
          max: 100,
          divisions: 40,
          digits: 0,
          onChanged: (v) => setState(() => _proBrightness = v),
        );
      // v1.4.0 Adjust extras — one shared slider, values ride
      // _adjustExtraFilter() at export.
      case 'Brilliance':
        return _ProSlider(
          label: 'Brilliance',
          value: _adjBrilliance,
          min: -100,
          max: 100,
          divisions: 40,
          digits: 0,
          onChanged: (v) => setState(() => _adjBrilliance = v),
        );
      case 'Sharpen':
        return _ProSlider(
          label: 'Sharpen',
          value: _adjSharpen,
          min: 0,
          max: 100,
          divisions: 20,
          digits: 0,
          onChanged: (v) => setState(() => _adjSharpen = v),
        );
      case 'Clarity':
        return _ProSlider(
          label: 'Clarity',
          value: _adjClarity,
          min: 0,
          max: 100,
          divisions: 20,
          digits: 0,
          onChanged: (v) => setState(() => _adjClarity = v),
        );
      case 'Whites':
        return _ProSlider(
          label: 'Whites',
          value: _adjWhites,
          min: -100,
          max: 100,
          divisions: 40,
          digits: 0,
          onChanged: (v) => setState(() => _adjWhites = v),
        );
      case 'Blacks':
        return _ProSlider(
          label: 'Blacks',
          value: _adjBlacks,
          min: -100,
          max: 100,
          divisions: 40,
          digits: 0,
          onChanged: (v) => setState(() => _adjBlacks = v),
        );
      case 'Hue':
        return _ProSlider(
          label: 'Hue (deg)',
          value: _adjHue,
          min: -180,
          max: 180,
          divisions: 72,
          digits: 0,
          onChanged: (v) => setState(() => _adjHue = v),
        );
      case 'Fade':
        return _ProSlider(
          label: 'Fade',
          value: _adjFade,
          min: 0,
          max: 100,
          divisions: 20,
          digits: 0,
          onChanged: (v) => setState(() => _adjFade = v),
        );
      case 'Vignette':
        return _ProSlider(
          label: 'Vignette',
          value: _adjVignette,
          min: 0,
          max: 100,
          divisions: 20,
          digits: 0,
          onChanged: (v) => setState(() => _adjVignette = v),
        );
      case 'Grain':
        return _ProSlider(
          label: 'Grain',
          value: _adjGrain,
          min: 0,
          max: 100,
          divisions: 20,
          digits: 0,
          onChanged: (v) => setState(() => _adjGrain = v),
        );
      default:
        return _ProSlider(
          label: 'Exposure',
          value: _proExposure,
          min: -100,
          max: 100,
          divisions: 40,
          digits: 0,
          onChanged: (v) => setState(() => _proExposure = v),
        );
    }
  }
}

/// §6.10 — the custom speed-ramp curve: three plateaus (start /
/// middle / end thirds) drawn as a step graph.
class _RampCurvePainter extends CustomPainter {
  const _RampCurvePainter(this.start, this.mid, this.end);

  final double start;
  final double mid;
  final double end;

  @override
  void paint(Canvas canvas, Size size) {
    final axis = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - 4),
      Offset(size.width, size.height - 4),
      axis,
    );
    double y(double speed) =>
        size.height - 4 - (speed.clamp(0.25, 2) / 2) * (size.height - 10);
    final path = Path()
      ..moveTo(0, y(start))
      ..lineTo(size.width / 3, y(start))
      ..lineTo(size.width / 3, y(mid))
      ..lineTo(size.width * 2 / 3, y(mid))
      ..lineTo(size.width * 2 / 3, y(end))
      ..lineTo(size.width, y(end));
    canvas.drawPath(
      path,
      Paint()
        ..color = TjProTheme.gold
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_RampCurvePainter old) =>
      old.start != start || old.mid != mid || old.end != end;
}

/// §5A — the keyframe easing curve graph (the motion the overlay
/// will follow from the Start to the End keyframe).
class _EasingCurvePainter extends CustomPainter {
  const _EasingCurvePainter(this.easing);

  final KeyframeEasing easing;

  @override
  void paint(Canvas canvas, Size size) {
    final axis = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    canvas.drawRect(
      Rect.fromLTWH(2, 2, size.width - 4, size.height - 4),
      axis..style = PaintingStyle.stroke,
    );
    final w = size.width - 8;
    final h = size.height - 8;
    Offset pt(double x, double y) => Offset(4 + x * w, 4 + (1 - y) * h);
    final path = Path()..moveTo(pt(0, 0).dx, pt(0, 0).dy);
    switch (easing) {
      case KeyframeEasing.linear:
        path.lineTo(pt(1, 1).dx, pt(1, 1).dy);
      case KeyframeEasing.easeIn:
        path.quadraticBezierTo(pt(0.6, 0).dx, pt(0.6, 0).dy, pt(1, 1).dx, pt(1, 1).dy);
      case KeyframeEasing.easeOut:
        path.quadraticBezierTo(pt(0.4, 1).dx, pt(0.4, 1).dy, pt(1, 1).dx, pt(1, 1).dy);
      case KeyframeEasing.easeInOut:
        path.cubicTo(
          pt(0.4, 0).dx, pt(0.4, 0).dy,
          pt(0.6, 1).dx, pt(0.6, 1).dy,
          pt(1, 1).dx, pt(1, 1).dy,
        );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = TjProTheme.gold
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_EasingCurvePainter old) => old.easing != easing;
}
