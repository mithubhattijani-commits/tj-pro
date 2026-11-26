/// Live Studio screen (TJ Pro v2).
///
/// One screen for the whole news-live workflow:
///   1. Save the Facebook and/or YouTube stream keys (secure storage
///      only — the keys are never displayed, not even partially).
///   2. Edit the breaking-news template (headline, lower-third, ticker,
///      clock, logo + position + rotation).
///   3. Watch the camera preview with the template overlaid, choose
///      which platform(s) this live goes to (Facebook, YouTube, or
///      both — every saved-key platform starts ON), then tap GO LIVE.
///
/// Honest warnings shown on-screen, not buried: dual publish uses
/// extra battery and mobile data, and the first live should be a
/// private/unlisted test, never a public broadcast.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'live_service.dart';
import 'news_template.dart';
import 'stream_key_store.dart';

class LiveStudioScreen extends StatefulWidget {
  const LiveStudioScreen({super.key});

  @override
  State<LiveStudioScreen> createState() => _LiveStudioScreenState();
}

class _LiveStudioScreenState extends State<LiveStudioScreen>
    with TickerProviderStateMixin {
  final _service = LiveService();
  final _picker = ImagePicker();
  final _fbKeyCtrl = TextEditingController();
  final _ytKeyCtrl = TextEditingController();
  // Persistent template-field controllers: recreating controllers in
  // build() would yank the cursor on every keystroke.
  final _headlineCtrl = TextEditingController();
  final _lowerTitleCtrl = TextEditingController();
  final _lowerSubtitleCtrl = TextEditingController();
  final _tickerTextCtrl = TextEditingController();

  NewsTemplate _template = NewsTemplate();
  bool _fbConnected = false;
  bool _ytConnected = false;
  // Per-live platform choice (v2.0.1): every saved-key platform starts
  // ON, so touching nothing keeps the v2.0.0 dual-live default. The
  // toggles never delete keys — they only choose this live's targets.
  bool _fbSelected = false;
  bool _ytSelected = false;
  bool _cameraReady = false;
  // #35: frame-primed gate. The rtmp_streaming plugin exposes no
  // first-frame callback, so "Camera ready." cannot be trusted the
  // moment initCamera() returns — the preview can still be black.
  // The gate is frame-based instead: once the camera reports ready,
  // the preview must survive 3 consecutive post-frame callbacks
  // before _previewPrimed flips and the ready state is shown.
  bool _previewPrimed = false;
  int _previewFrameCount = 0;
  bool _primeCallbackScheduled = false;
  // #36: the red "select a platform" hint is an error, so it only
  // appears after the user has actually tapped GO LIVE once.
  bool _goLiveAttempted = false;
  bool _muted = false;
  DateTime? _liveSince;
  Timer? _clockTimer;
  late final AnimationController _tickerCtrl;
  late final AnimationController _logoSpinCtrl;

  @override
  void initState() {
    super.initState();
    _tickerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat();
    _logoSpinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ok = await _service.initCamera();
      if (mounted) {
        setState(() => _cameraReady = ok);
        if (ok) _schedulePreviewPrime();
      }
    });
    _clockTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (mounted) setState(() {});
      },
    );
  }

  Future<void> _load() async {
    final template = await NewsTemplate.load();
    final fb = await StreamKeyStore.hasFacebook;
    final yt = await StreamKeyStore.hasYouTube;
    if (!mounted) return;
    setState(() {
      _template = template;
      _fbConnected = fb;
      _ytConnected = yt;
      _fbSelected = fb;
      _ytSelected = yt;
      _headlineCtrl.text = template.breakingHeadline;
      _lowerTitleCtrl.text = template.lowerTitle;
      _lowerSubtitleCtrl.text = template.lowerSubtitle;
      _tickerTextCtrl.text = template.tickerText;
    });
    _service.setTemplate(template);
  }

  /// #35: counts post-frame callbacks after the camera reports
  /// ready; the third consecutive one primes the preview. Chained
  /// callbacks (not a timer) so the count tracks real frames drawn.
  void _schedulePreviewPrime() {
    if (_previewPrimed || _primeCallbackScheduled || !_cameraReady) {
      return;
    }
    if (_service.previewWidget() == null) return;
    _primeCallbackScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _primeCallbackScheduled = false;
      if (!mounted || _previewPrimed) return;
      if (!_cameraReady || _service.previewWidget() == null) {
        _previewFrameCount = 0;
        return;
      }
      _previewFrameCount++;
      if (_previewFrameCount >= 3) {
        setState(() => _previewPrimed = true);
      } else {
        _schedulePreviewPrime();
      }
    });
  }

  Future<void> _saveTemplate() async {
    _service.setTemplate(_template);
    await _template.save();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _tickerCtrl.dispose();
    _logoSpinCtrl.dispose();
    _fbKeyCtrl.dispose();
    _ytKeyCtrl.dispose();
    _headlineCtrl.dispose();
    _lowerTitleCtrl.dispose();
    _lowerSubtitleCtrl.dispose();
    _tickerTextCtrl.dispose();
    // Never leave an orphan live stream behind when leaving the screen.
    unawaited(_service.stopLive());
    unawaited(_service.dispose());
    super.dispose();
  }

  String get _elapsed {
    final since = _liveSince;
    if (since == null) return '00:00';
    final d = DateTime.now().difference(since);
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get _clockText {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  Alignment _logoAlignment() {
    switch (_template.logoPosition) {
      case LogoPosition.topLeft:
        return Alignment.topLeft;
      case LogoPosition.topRight:
        return Alignment.topRight;
      case LogoPosition.bottomLeft:
        return Alignment.bottomLeft;
      case LogoPosition.bottomRight:
        return Alignment.bottomRight;
    }
  }

  /// The news template as the presenter sees it, over the preview.
  /// The broadcast carries the same layout via the composited image.
  Widget _templateOverlay(BoxConstraints constraints) {
    final w = constraints.maxWidth;
    final headline = _template.breakingHeadline.trim();
    final title = _template.lowerTitle.trim();
    final subtitle = _template.lowerSubtitle.trim();
    final ticker = _template.tickerText.trim();
    final logoPath = _template.logoPath;
    Widget? logo;
    if (logoPath != null) {
      final img = Image.file(
        File(logoPath),
        width: 64,
        height: 64,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
      logo = _template.logoRotate
          ? RotationTransition(turns: _logoSpinCtrl, child: img)
          : img;
    }
    return Stack(
      children: [
        if (headline.isNotEmpty)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: const Color(0xFFD50000),
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              child: Text(
                'BREAKING: $headline',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        if (_template.showClock)
          Positioned(
            top: headline.isNotEmpty ? 52 : 8,
            right: 8,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Text(
                // #37: 'LIVE' wording only while actually live;
                // offline the chip is just a clock.
                _service.isLive ? 'LIVE $_clockText' : _clockText,
                style: const TextStyle(
                  color: Color(0xFFFFEB3B),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        if (title.isNotEmpty || subtitle.isNotEmpty)
          Positioned(
            left: 0,
            bottom: ticker.isNotEmpty ? 34 : 8,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              constraints: BoxConstraints(maxWidth: w * 0.72),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title.isNotEmpty)
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (ticker.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.black87,
              height: 34,
              clipBehavior: Clip.hardEdge,
              alignment: Alignment.centerLeft,
              child: AnimatedBuilder(
                animation: _tickerCtrl,
                builder: (_, _) {
                  final offset =
                      w - _tickerCtrl.value * (w + 600);
                  return Transform.translate(
                    offset: Offset(offset, 0),
                    child: Text(
                      ticker,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      softWrap: false,
                    ),
                  );
                },
              ),
            ),
          ),
        if (logo != null)
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Align(alignment: _logoAlignment(), child: logo),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final live = _service.isLive;
    // Per-live platform choice: Go Live streams only to the toggled-on
    // platforms. With nothing toggled on the button stays tappable
    // (#36) so the tap itself can explain what is missing, instead of
    // a red error sitting on screen before any user action.
    final anySelected = _fbSelected || _ytSelected;
    final goLiveLabel = _fbSelected && _ytSelected
        ? 'GO LIVE — dono par'
        : _fbSelected
            ? 'GO LIVE — Facebook par'
            : _ytSelected
                ? 'GO LIVE — YouTube par'
                : 'GO LIVE';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Studio'),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Status row.
          ValueListenableBuilder<String>(
            valueListenable: _service.status,
            builder: (_, status, _) {
              // #35: never claim 'Camera ready.' while the preview
              // is still priming (it may still be black).
              final displayStatus =
                  (!_previewPrimed && status == 'Camera ready.')
                      ? 'Camera is getting ready…'
                      : status;
              return Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: live ? Colors.red : Colors.grey,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      live ? '● LIVE $_elapsed' : '● OFFLINE',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(displayStatus)),
                ],
              );
            },
          ),
          ValueListenableBuilder<String>(
            valueListenable: _service.statsLine,
            builder: (_, stats, _) =>
                stats.isEmpty ? const SizedBox.shrink() : Text(stats),
          ),
          const SizedBox(height: 12),
          // Preview + template.
          Center(
            child: SizedBox(
              width: 270,
              height: 480,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final preview = _service.previewWidget();
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: Container(
                            color: Colors.black,
                            child: preview ??
                                const Center(
                                  child: Text(
                                    'Camera is getting ready…',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                ),
                          ),
                        ),
                        // #35: until the preview is primed, keep the
                        // 'tayyar ho raha hai' label on top so a
                        // still-black preview is never presented as
                        // ready.
                        if (!_previewPrimed)
                          Positioned.fill(
                            child: Container(
                              color: Colors.black,
                              child: const Center(
                                child: Text(
                                  'Camera is getting ready…',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ),
                            ),
                          ),
                        Positioned.fill(
                          child: _templateOverlay(constraints),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Platform choice (v2.0.1): which platform(s) this live goes
          // to. A toggle works only when that platform's key is saved;
          // with no key saved it stays off with a hint to save the key.
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    'On which one should the live run?',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Facebook'),
                  subtitle: _fbConnected
                      ? null
                      : const Text('Save the Facebook key first'),
                  value: _fbSelected,
                  onChanged: _fbConnected
                      ? (v) => setState(() => _fbSelected = v)
                      : null,
                ),
                SwitchListTile(
                  title: const Text('YouTube'),
                  subtitle: _ytConnected
                      ? null
                      : const Text('Save the YouTube key first'),
                  value: _ytSelected,
                  onChanged: _ytConnected
                      ? (v) => setState(() => _ytSelected = v)
                      : null,
                ),
                // #36: plain guidance (not an error) when no key is
                // saved yet — point at the Stream Keys fields below
                // before the user ever taps GO LIVE.
                if (!_fbConnected && !_ytConnected)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      'For live, first save your key below in Stream Keys '
                      'save the key — then turn the platform on here.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Go live / stop.
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (!_cameraReady || !_previewPrimed || live)
                      ? null
                      : () async {
                          // #36: no platform selected is handled here,
                          // on the tap — guidance via SnackBar, and
                          // only now may the red inline hint appear.
                          if (!anySelected) {
                            setState(() => _goLiveAttempted = true);
                            final message =
                                (!_fbConnected && !_ytConnected)
                                    ? 'For live, first below in Stream '
                                        'save your key in Keys, '
                                        'then select the platform.'
                                    : 'Select at least one platform.';
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(message)),
                            );
                            return;
                          }
                          final selected = <String>{
                            if (_fbSelected) 'facebook',
                            if (_ytSelected) 'youtube',
                          };
                          final ok = await _service.goLive(only: selected);
                          if (mounted && ok) {
                            setState(() => _liveSince = DateTime.now());
                          }
                        },
                  icon: const Icon(Icons.live_tv),
                  label: Text(goLiveLabel),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (live)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await _service.stopLive();
                      if (mounted) setState(() => _liveSince = null);
                    },
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop Live'),
                  ),
                ),
            ],
          ),
          // #36: red inline error only after a GO LIVE attempt.
          if (_goLiveAttempted && !anySelected && !live)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Select at least one platform.',
                style: TextStyle(color: Colors.red),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await _service.switchCamera();
                    // Preview re-initializes with a new controller on
                    // switch, so rebuild to mount the new preview.
                    // #35: the new preview must re-prime before it
                    // can be called ready again.
                    if (mounted) {
                      setState(() {
                        _previewPrimed = false;
                        _previewFrameCount = 0;
                      });
                      _schedulePreviewPrime();
                    }
                  },
                  icon: const Icon(Icons.switch_camera),
                  label: const Text('Camera badlein'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SwitchListTile(
                  title: const Text('Mic band'),
                  value: _muted,
                  onChanged: (v) async {
                    setState(() => _muted = v);
                    await _service.setMuted(v);
                  },
                ),
              ),
            ],
          ),
          ValueListenableBuilder<Map<String, LiveDestinationState>>(
            valueListenable: _service.destinations,
            builder: (_, states, _) {
              if (states.isEmpty) return const SizedBox.shrink();
              return Column(
                children: states.entries.map((e) {
                  final name =
                      e.key == 'facebook' ? 'Facebook' : 'YouTube';
                  final label = switch (e.value) {
                    LiveDestinationState.live => 'LIVE',
                    LiveDestinationState.starting => 'Connecting…',
                    LiveDestinationState.failed => 'Failed — try again',
                    LiveDestinationState.stopped => 'Band',
                  };
                  return ListTile(
                    title: Text('$name: $label'),
                    trailing: e.value == LiveDestinationState.live
                        ? TextButton(
                            onPressed: () =>
                                _service.stopDestination(e.key),
                            child: const Text('Turn this off'),
                          )
                        : null,
                  );
                }).toList(),
              );
            },
          ),
          const Divider(height: 32),
          // Stream keys.
          const Text(
            'Stream Keys (safe only on this phone)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Facebook: facebook.com > Live Video > Stream Key. YouTube: '
            'YouTube Studio > Go Live > Stream Key. The key will never be shown on screen, '
            'will not be shown, only "connected" will appear.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _fbKeyCtrl,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Facebook stream key',
              border: const OutlineInputBorder(),
              suffixIcon: _fbConnected
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    await StreamKeyStore.saveFacebook(_fbKeyCtrl.text);
                    if (!mounted) return;
                    setState(() {
                      _fbConnected = _fbKeyCtrl.text.trim().isNotEmpty;
                      // A newly saved key starts selected (default ON).
                      _fbSelected = _fbConnected;
                      _fbKeyCtrl.clear();
                    });
                  },
                  child: const Text('Save the Facebook key'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    await StreamKeyStore.saveFacebook('');
                    if (mounted) {
                      setState(() {
                        _fbConnected = false;
                        _fbSelected = false;
                      });
                    }
                  },
                  child: const Text('Clear'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ytKeyCtrl,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'YouTube stream key',
              border: const OutlineInputBorder(),
              suffixIcon: _ytConnected
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    await StreamKeyStore.saveYouTube(_ytKeyCtrl.text);
                    if (!mounted) return;
                    setState(() {
                      _ytConnected = _ytKeyCtrl.text.trim().isNotEmpty;
                      // A newly saved key starts selected (default ON).
                      _ytSelected = _ytConnected;
                      _ytKeyCtrl.clear();
                    });
                  },
                  child: const Text('Save the YouTube key'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    await StreamKeyStore.saveYouTube('');
                    if (mounted) {
                      setState(() {
                        _ytConnected = false;
                        _ytSelected = false;
                      });
                    }
                  },
                  child: const Text('Clear'),
                ),
              ),
            ],
          ),
          const Divider(height: 32),
          // Template editors.
          const Text(
            'Breaking News Template',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Breaking headline (surkh patti)',
              border: OutlineInputBorder(),
            ),
            controller: _headlineCtrl,
            onChanged: (v) {
              _template.breakingHeadline = v;
              _saveTemplate();
              setState(() {});
            },
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Lower-third title (naam)',
              border: OutlineInputBorder(),
            ),
            controller: _lowerTitleCtrl,
            onChanged: (v) {
              _template.lowerTitle = v;
              _saveTemplate();
              setState(() {});
            },
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Lower-third subtitle (designation / place)',
              border: OutlineInputBorder(),
            ),
            controller: _lowerSubtitleCtrl,
            onChanged: (v) {
              _template.lowerSubtitle = v;
              _saveTemplate();
              setState(() {});
            },
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Ticker text (runs below)',
              border: OutlineInputBorder(),
            ),
            controller: _tickerTextCtrl,
            onChanged: (v) {
              _template.tickerText = v;
              _saveTemplate();
              setState(() {});
            },
          ),
          SwitchListTile(
            title: const Text('Live clock / date dikhayein'),
            value: _template.showClock,
            onChanged: (v) {
              setState(() => _template.showClock = v);
              _saveTemplate();
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
                    setState(() => _template.logoPath = picked.path);
                    await _saveTemplate();
                  },
                  icon: const Icon(Icons.image),
                  label: Text(
                    _template.logoPath == null
                        ? 'Choose logo (upload)'
                        : 'Logo badlein',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<LogoPosition>(
                  initialValue: _template.logoPosition,
                  decoration: const InputDecoration(
                    labelText: 'Logo place',
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
                    setState(() => _template.logoPosition = v);
                    _saveTemplate();
                  },
                ),
              ),
            ],
          ),
          SwitchListTile(
            title: const Text('Logo ahista ghoome (rotation)'),
            subtitle: const Text('Live me ghoomega; export me static.'),
            value: _template.logoRotate,
            onChanged: (v) {
              setState(() => _template.logoRotate = v);
              _saveTemplate();
            },
          ),
          const SizedBox(height: 12),
          const Text(
            'Important: sending live on both platforms together will use more battery '
            'and mobile data. The first time, go live private or '
            'go live unlisted as a test, then go public.',
            style: TextStyle(color: Colors.red),
          ),
        ],
      ),
    );
  }
}
