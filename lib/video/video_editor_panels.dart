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

  /// One-build regroup (proposal S4.1): the old 15 flat tools are
  /// composed into 8 tabs. Every legacy panel is reused exactly once
  /// below — no option is removed, only re-homed. (Keyframes stay
  /// with the Stickers panel: they animate the sticker/title
  /// overlay itself.)
  List<Widget> _toolPanelChildren() {
    switch (_activeTool) {
      case 'edit':
        return [
          _sectionTitle('Speed'),
          ..._panelBody('speed'),
          _sectionTitle('Beat cut'),
          ..._panelBody('beats'),
          _sectionTitle('Steady video'),
          ..._panelBody('stabilization'),
        ];
      case 'audio':
        return [
          ..._panelBody('audio'),
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
      case 'text':
        return [
          _sectionTitle('Text overlay'),
          ..._panelBody('text'),
          _sectionTitle('Motion titles'),
          ..._panelBody('titles'),
          _sectionTitle('Captions'),
          ..._panelBody('captions'),
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
      case 'colour':
        return [
          _sectionTitle('Filters'),
          ..._panelBody('filters'),
          _sectionTitle('Adjust + LUTs'),
          ..._panelBody('grading'),
        ];
      case 'effects':
        return [
          ..._panelBody('effects'),
          _sectionTitle('Motion tracking'),
          ..._panelBody('tracking'),
        ];
      case 'overlay':
        return [
          _sectionTitle('Stickers & keyframes'),
          ..._panelBody('stickers'),
          _sectionTitle('PIP'),
          ..._panelBody('overlays'),
          _sectionTitle('Background'),
          ..._panelBody('chroma'),
        ];
      case 'transitions':
        return _legacyPanelChildren('transitions');
      case 'news':
        return _legacyPanelChildren('news');
      default:
        return _legacyPanelChildren('text');
    }
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
              DropdownButtonFormField<String>(
                initialValue: _proStickerPreset,
                decoration: const InputDecoration(
                  labelText: 'Sticker preset',
                ),
                items: const [
                  'fadeIn',
                  'slideLeft',
                  'slideRight',
                  'slideUp',
                  'zoomPop',
                ]
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _proStickerPreset = v ?? 'fadeIn'),
              ),
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
                DropdownButtonFormField<KeyframeEasing>(
                  initialValue: _kfEasing,
                  decoration: const InputDecoration(
                      labelText: 'Motion easing'),
                  items: KeyframeEasing.values
                      .map((KeyframeEasing e) => DropdownMenuItem(
                            value: e,
                            child: Text(keyframeEasingLabel(e)),
                          ))
                      .toList(),
                  onChanged: (KeyframeEasing? v) =>
                      setState(() => _kfEasing = v ?? KeyframeEasing.linear),
                ),
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
          DropdownButtonFormField<ShakeFx>(
            initialValue: _fxShake,
            decoration: const InputDecoration(labelText: 'Shake intensity'),
            items: const [
              DropdownMenuItem(value: ShakeFx.none, child: Text('None')),
              DropdownMenuItem(value: ShakeFx.light, child: Text('Light')),
              DropdownMenuItem(value: ShakeFx.medium, child: Text('Medium')),
              DropdownMenuItem(value: ShakeFx.strong, child: Text('Strong')),
            ],
            onChanged: (ShakeFx? v) {
              setState(() {
                _fxShake = v ?? ShakeFx.none;
              });
            },
          ),
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
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _proTitlePreset,
                      decoration: const InputDecoration(
                        labelText: 'Title preset',
                      ),
                      items: const [
                        'fadeIn',
                        'slideLeft',
                        'slideRight',
                        'slideUp',
                        'zoomPop',
                      ]
                          .map((s) => DropdownMenuItem(
                                value: s,
                                child: Text(s),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _proTitlePreset = v ?? 'fadeIn'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _proTitlePosition,
                      decoration: const InputDecoration(
                        labelText: 'Title position',
                      ),
                      items: const ['topCenter', 'center', 'bottomCenter']
                          .map((s) => DropdownMenuItem(
                                value: s,
                                child: Text(s),
                              ))
                          .toList(),
                      onChanged: (v) => setState(
                        () => _proTitlePosition = v ?? 'bottomCenter',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
          const Divider(height: 32),
        ];
      case 'filters':
        return [
          const Text('Filters',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
// Speed / filter / aspect
          DropdownButtonFormField<String>(
            initialValue: _filter,
            decoration: const InputDecoration(labelText: 'Filter'),
            items: const ['Normal', 'Warm', 'Cool', 'B&W', 'Vivid', 'Sepia']
                .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                .toList(),
            onChanged: (v) => setState(() => _filter = v ?? 'Normal'),
          ),
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
          DropdownButtonFormField<VoiceFx>(
            initialValue: _fxVoice,
            decoration: const InputDecoration(labelText: 'Voice effect'),
            items: const [
              DropdownMenuItem(value: VoiceFx.none, child: Text('None')),
              DropdownMenuItem(value: VoiceFx.chipmunk, child: Text('Chipmunk')),
              DropdownMenuItem(value: VoiceFx.deepVoice, child: Text('Deep voice')),
              DropdownMenuItem(value: VoiceFx.robot, child: Text('Robot')),
              DropdownMenuItem(value: VoiceFx.echo, child: Text('Echo')),
            ],
            onChanged: (VoiceFx? v) {
              setState(() {
                _fxVoice = v ?? VoiceFx.none;
              });
            },
          ),
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
          DropdownButtonFormField<double>(
            initialValue: _speed,
            decoration: const InputDecoration(labelText: 'Speed'),
            items: const [0.5, 0.75, 1.0, 1.5, 2.0]
                .map((s) => DropdownMenuItem(
                      value: s,
                      child: Text('${s}x'),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _speed = v ?? 1.0),
          ),
// Speed ramp.
              const Text('Speed ramp',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              DropdownButtonFormField<String>(
                initialValue: _proRamp,
                decoration: const InputDecoration(labelText: 'Ramp preset'),
                items: const [
                  'None',
                  'slowMiddle',
                  'slowStart',
                  'slowEnd',
                  'pulse',
                ]
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() => _proRamp = v ?? 'None'),
              ),
              const Text(
                'Note: ramp on ho to fixed Speed dropdown ignore ho jata hai.',
                style: TextStyle(color: Colors.grey),
              ),
              const Divider(height: 32),
          const Text('Clip FX',
              style: TextStyle(fontWeight: FontWeight.bold)),
          SwitchListTile(
            title: const Text('Reverse video'),
            value: _fxReverse,
            onChanged: (bool v) {
              setState(() {
                _fxReverse = v;
              });
            },
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
              DropdownButtonFormField<String>(
                initialValue: _proTransition,
                decoration: const InputDecoration(labelText: 'Transition'),
                items: const [
                  'fade',
                  'slideleft',
                  'slideright',
                  'slideup',
                  'slidedown',
                  'wipeleft',
                  'wiperight',
                  'wipeup',
                  'wipedown',
                  'circlecrop',
                  'dissolve',
                  'pixelize',
                  'smoothleft',
                  'smoothright',
                  'radial',
                  'rectcrop',
                  'hblur',
                  'circleopen',
                ]
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() => _proTransition = v ?? 'fade'),
              ),
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
                }
              },
              icon: const Icon(Icons.video_library),
              label: Text(_fxPipVideo.isEmpty
                  ? 'Choose PIP video'
                  : p.basename(_fxPipVideo)),
            ),
          if (_fxPip) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<PipPosition>(
              key: const Key('pipPositionDropdown'),
              initialValue: _pipPosition,
              decoration: const InputDecoration(
                labelText: 'PIP position',
              ),
              items: PipPosition.values
                  .map(
                    (pos) => DropdownMenuItem(
                      value: pos,
                      child: Text(pos.name),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _pipPosition = v);
              },
            ),
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
                Expanded(
                  child: DropdownButtonFormField<LogoPosition>(
                    initialValue: _news.logoPosition,
                    decoration: const InputDecoration(
                      labelText: 'Logo jagah',
                      border: OutlineInputBorder(),
                    ),
                    items: LogoPosition.values
                        .map((pos) => DropdownMenuItem(
                              value: pos,
                              child: Text(pos.label),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _news.logoPosition = v);
                      unawaited(_news.save());
                    },
                  ),
                ),
              ],
            ),
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
              'Note: export me ticker aur clock ek still frame honge — '
              'scrolling ticker aur live clock sirf live me chalte hain. '
              'Yehi template Live Studio me bhi use hota hai.',
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
                child: DropdownButtonFormField<String>(
                  initialValue: _captionLocale,
                  decoration:
                      const InputDecoration(labelText: 'Caption language'),
                  items: const [
                    DropdownMenuItem(value: 'ur', child: Text('Urdu')),
                    DropdownMenuItem(value: 'en', child: Text('English')),
                  ],
                  onChanged: (v) => setState(() => _captionLocale = v ?? 'ur'),
                ),
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
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: switch (_captionStyle) {
                    CaptionStyle.standard => 'standard',
                    CaptionStyle.highlight => 'highlight',
                    CaptionStyle.gold => 'gold',
                    CaptionStyle.clean => 'clean',
                    CaptionStyle.pop => 'pop',
                    CaptionStyle.boxed => 'boxed',
                  },
                  decoration:
                      const InputDecoration(labelText: 'Caption style'),
                  items: const [
                    DropdownMenuItem(
                        value: 'standard', child: Text('Default')),
                    DropdownMenuItem(
                        value: 'highlight',
                        child: Text('Highlight (black on yellow)')),
                    DropdownMenuItem(
                        value: 'gold', child: Text('Gold')),
                    DropdownMenuItem(
                        value: 'clean', child: Text('Clean')),
                    DropdownMenuItem(
                        value: 'pop',
                        child: Text('Pop (word by word)')),
                    DropdownMenuItem(
                        value: 'boxed',
                        child: Text('Boxed (white on black)')),
                  ],
                  onChanged: (v) => setState(() {
                    _captionStyle = switch (v) {
                      'highlight' => CaptionStyle.highlight,
                      'gold' => CaptionStyle.gold,
                      'clean' => CaptionStyle.clean,
                      'pop' => CaptionStyle.pop,
                      'boxed' => CaptionStyle.boxed,
                      _ => CaptionStyle.standard,
                    };
                  }),
                ),
              ),
            ],
          ),
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
                const Text('Key color — preset ya eyedropper se sample karein'),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButton<String>(
                        value: (_proChromaColor == 'green' ||
                                _proChromaColor == 'blue')
                            ? _proChromaColor
                            : null,
                        hint: const Text('Custom (sampled)'),
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(
                              value: 'green', child: Text('Green')),
                          DropdownMenuItem(
                              value: 'blue', child: Text('Blue')),
                        ],
                        onChanged: (v) {
                          setState(() => _proChromaColor = v ?? 'green');
                          _scheduleChromaPreview();
                        },
                      ),
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
                DropdownButton<String>(
                  value: _proChromaBgKind,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'color', child: Text('Color')),
                    DropdownMenuItem(value: 'image', child: Text('Image')),
                  ],
                  onChanged: (v) {
                    setState(() => _proChromaBgKind = v ?? 'color');
                    _scheduleChromaPreview();
                  },
                ),
                if (_proChromaBgKind == 'color') ...[
                  const Text('Background color'),
                  DropdownButton<String>(
                    value: const ['#00FF00', '#0000FF', '#000000', '#FFFFFF']
                            .contains(_proChromaBgColor)
                        ? _proChromaBgColor
                        : null,
                    hint: const Text('Custom'),
                    isExpanded: true,
                    items: const {
                      '#00FF00': 'Green',
                      '#0000FF': 'Blue',
                      '#000000': 'Black',
                      '#FFFFFF': 'White',
                    }
                        .entries
                        .map((e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ))
                        .toList(),
                    onChanged: (v) {
                      setState(() => _proChromaBgColor = v ?? '#00FF00');
                      _scheduleChromaPreview();
                    },
                  ),
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        label: const Text('Newsroom'),
                        onPressed: () => _applyBackdropAsset(
                            'assets/backgrounds/newsroom.jpg'),
                      ),
                      ActionChip(
                        label: const Text('Studio Desk'),
                        onPressed: () => _applyBackdropAsset(
                            'assets/backgrounds/studio_desk.jpg'),
                      ),
                      ActionChip(
                        label: const Text('News anchor preset'),
                        onPressed: _applyNewsAnchorPreset,
                      ),
                    ],
                  ),
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
                  'Premium: ek short ad (Unity) dekh kar unlock hoga.',
                ),
                value: _proBgRemove,
                onChanged: _onBgRemoverChanged,
              ),
              if (_proBgRemove) ...[
                DropdownButtonFormField<String>(
                  initialValue: _proBgKind,
                  decoration:
                      const InputDecoration(labelText: 'Background kind'),
                  items: const [
                    DropdownMenuItem(value: 'color', child: Text('Color')),
                    DropdownMenuItem(value: 'image', child: Text('Image')),
                  ],
                  onChanged: (v) => setState(() => _proBgKind = v ?? 'color'),
                ),
                if (_proBgKind == 'color')
                  DropdownButtonFormField<String>(
                    initialValue: _proBgColor,
                    decoration:
                        const InputDecoration(labelText: 'Background color'),
                    items: const {
                      '#00FF00': 'Green',
                      '#0000FF': 'Blue',
                      '#000000': 'Black',
                      '#FFFFFF': 'White',
                    }
                        .entries
                        .map((e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _proBgColor = v ?? '#00FF00'),
                  ),
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
              DropdownButtonFormField<String>(
                initialValue: _proLut,
                decoration: const InputDecoration(labelText: 'LUT look'),
                items: proLuts
                    .map((e) => DropdownMenuItem(
                          value: e['name'] ?? '',
                          child: Text(
                            (e['name'] ?? '').isEmpty ? 'None' : e['name']!,
                          ),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _proLut = v ?? ''),
              ),
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

  Widget _timelineSection(VideoClip? clip) {
    final ctrl = _controller;
    final pos = ctrl != null && ctrl.value.isInitialized
        ? ctrl.value.position.inMilliseconds / 1000
        : 0.0;
    final dur = clip != null ? clip.duration.inMilliseconds / 1000 : 0.0;
    final frac = dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;
    return Container(
      color: const Color(0xFF1B1B1B),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Timeline',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _clips.isEmpty
                      ? 'No clips yet — Add video above'
                      : 'Playhead ${pos.toStringAsFixed(1)}s / ${dur.toStringAsFixed(1)}s'
                          ' • Clip ${_selected + 1} of ${_clips.length}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                onPressed: _clips.isEmpty ? null : _splitSelectedClip,
                icon: const Icon(Icons.content_cut, size: 18),
                label: const Text('Split'),
              ),
              TextButton.icon(
                onPressed:
                    (_clips.isEmpty || _busy) ? null : _saveFrameSnapshot,
                icon: const Icon(Icons.camera_alt_outlined, size: 18),
                label: const Text('Frame'),
              ),
              TextButton.icon(
                onPressed:
                    (_clips.isEmpty || _busy) ? null : _extractClipAudio,
                icon: const Icon(Icons.audio_file_outlined, size: 18),
                label: const Text('Audio'),
              ),
            ],
          ),
          // Playhead marker (red) above the clip blocks.
          Container(
            height: 4,
            alignment: Alignment(frac * 2 - 1, 0),
            child: Container(width: 28, height: 4, color: Colors.redAccent),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 88,
            child: _clips.isEmpty
                ? const Center(
                    child: Text('Timeline khaali hai',
                        style: TextStyle(color: Colors.grey)))
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _clips.asMap().entries.map((e) {
                        final i = e.key;
                        final c = e.value;
                        final selected = i == _selected;
                        return GestureDetector(
                          onTap: () async {
                            setState(() => _selected = i);
                            await _loadPreview();
                          },
                          child: Container(
                            width: 128,
                            height: 88,
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: selected
                                  ? TjProTheme.goldDeep
                                  : const Color(0xFF2E2E2E),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selected
                                    ? TjProTheme.gold
                                    : Colors.grey.shade700,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text('Clip ${i + 1}',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12)),
                                    ),
                                    GestureDetector(
                                      onTap: () async {
                                        setState(() {
                                          _clips.removeAt(i);
                                          if (_selected >= _clips.length) {
                                            _selected = _clips.length - 1;
                                          }
                                        });
                                        if (_clips.isNotEmpty) {
                                          await _loadPreview();
                                        } else {
                                          await _controller?.dispose();
                                          setState(() => _controller = null);
                                        }
                                      },
                                      child: const Icon(Icons.close,
                                          size: 16, color: Colors.white70),
                                    ),
                                  ],
                                ),
                                Text(
                                  p.basename(c.file.path),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 11),
                                ),
                                Text(
                                  '${c.effectiveDuration.toStringAsFixed(1)}s'
                                  ' • trim ${c.trimStart.toStringAsFixed(1)}'
                                  '–${c.effectiveEnd.toStringAsFixed(1)}s',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
          ),
          if (_clips.isNotEmpty) ...[
            const SizedBox(height: 4),
            const Text('Trim selected clip — drag the handles',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
if (clip != null) ...[
              const SizedBox(height: 8),
              Text(
                'Trim selected clip: ${clip.trimStart.toStringAsFixed(1)}s – ${clip.effectiveEnd.toStringAsFixed(1)}s',
              ),
              RangeSlider(
                values: RangeValues(
                  clip.trimStart,
                  clip.effectiveEnd,
                ),
                min: 0,
                max: clip.duration.inMilliseconds / 1000,
                divisions:
                    (clip.duration.inMilliseconds / 100).round().clamp(1, 1000),
                labels: RangeLabels(
                  '${clip.trimStart.toStringAsFixed(1)}s',
                  '${clip.effectiveEnd.toStringAsFixed(1)}s',
                ),
                onChanged: (v) {
                  if (v.end - v.start < 0.5) return;
                  setState(() {
                    clip.trimStart = v.start;
                    clip.trimEnd = v.end;
                  });
                },
              ),
            ],
          ],
        ],
      ),
    );
  }
}
