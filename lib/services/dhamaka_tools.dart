/// "Bara Dhamaka" tools — CapCut-level video/audio editing commands.
///
/// All builders return FFmpeg command strings (same convention as
/// [FfmpegService]). The UI calls these; heavy work stays in FFmpeg.
/// Every method is pure (no I/O) so it's unit-testable.
///
/// Jaani's quality gates: no crashes, no hangs — every command is
/// validated by construction (quoted paths, clamped values).
library;

import 'package:tj_pro/services/ffmpeg_service.dart';

/// Xfade transition types supported by FFmpeg.
enum XfadeTransition {
  fade,
  fadeblack,
  fadewhite,
  distance,
  wipeleft,
  wiperight,
  wipeup,
  wipedown,
  slideleft,
  slideright,
  slideup,
  slidedown,
  smoothleft,
  smoothright,
  smoothup,
  smoothdown,
  circlecrop,
  rectcrop,
  circleopen,
  circleclose,
  vertopen,
  vertclose,
  horzopen,
  horzclose,
  dissolve,
  pixelize,
  radial,
  hblur,
  squeezev,
  squeezeh,
  zoomin,
  fadefast,
  fadeslow,
}

/// Human-readable labels for the transition picker.
const Map<XfadeTransition, String> xfadeLabels = {
  XfadeTransition.fade: 'Fade',
  XfadeTransition.fadeblack: 'Fade Black',
  XfadeTransition.fadewhite: 'Fade White',
  XfadeTransition.distance: 'Distance',
  XfadeTransition.wipeleft: 'Wipe Left',
  XfadeTransition.wiperight: 'Wipe Right',
  XfadeTransition.wipeup: 'Wipe Up',
  XfadeTransition.wipedown: 'Wipe Down',
  XfadeTransition.slideleft: 'Slide Left',
  XfadeTransition.slideright: 'Slide Right',
  XfadeTransition.slideup: 'Slide Up',
  XfadeTransition.slidedown: 'Slide Down',
  XfadeTransition.smoothleft: 'Smooth Left',
  XfadeTransition.smoothright: 'Smooth Right',
  XfadeTransition.smoothup: 'Smooth Up',
  XfadeTransition.smoothdown: 'Smooth Down',
  XfadeTransition.circlecrop: 'Circle Crop',
  XfadeTransition.rectcrop: 'Rect Crop',
  XfadeTransition.circleopen: 'Circle Open',
  XfadeTransition.circleclose: 'Circle Close',
  XfadeTransition.vertopen: 'Vert Open',
  XfadeTransition.vertclose: 'Vert Close',
  XfadeTransition.horzopen: 'Horz Open',
  XfadeTransition.horzclose: 'Horz Close',
  XfadeTransition.dissolve: 'Dissolve',
  XfadeTransition.pixelize: 'Pixelize',
  XfadeTransition.radial: 'Radial',
  XfadeTransition.hblur: 'H-Blur',
  XfadeTransition.squeezev: 'Squeeze V',
  XfadeTransition.squeezeh: 'Squeeze H',
  XfadeTransition.zoomin: 'Zoom In',
  XfadeTransition.fadefast: 'Fade Fast',
  XfadeTransition.fadeslow: 'Fade Slow',
};

/// Video effect presets (ffmpeg filter recipes).
enum VideoEffect {
  none,
  glitch,
  shake,
  vhs,
  blurBg,
  oldFilm,
  rgbSplit,
  zoomPulse,
}

/// Human-readable labels for the effects picker.
const Map<VideoEffect, String> videoEffectLabels = {
  VideoEffect.none: 'None',
  VideoEffect.glitch: 'Glitch',
  VideoEffect.shake: 'Shake',
  VideoEffect.vhs: 'VHS',
  VideoEffect.blurBg: 'Blur',
  VideoEffect.oldFilm: 'Old Film',
  VideoEffect.rgbSplit: 'RGB Split',
  VideoEffect.zoomPulse: 'Zoom Pulse',
};

/// Audio effect presets.
enum AudioEffect {
  none,
  chipmunk,
  robot,
  echo,
  bassBoost,
  trebleBoost,
  nightcore,
  slowed,
}

const Map<AudioEffect, String> audioEffectLabels = {
  AudioEffect.none: 'None',
  AudioEffect.chipmunk: 'Chipmunk',
  AudioEffect.robot: 'Robot',
  AudioEffect.echo: 'Echo',
  AudioEffect.bassBoost: 'Bass Boost',
  AudioEffect.trebleBoost: 'Treble Boost',
  AudioEffect.nightcore: 'Nightcore',
  AudioEffect.slowed: 'Slowed',
};

/// Extended caption styles (beyond the 6 in caption_service.dart).
enum DhamakaCaptionStyle {
  boldBox,
  outline,
  karaoke,
  bounce,
  typewriter,
  glow,
  minimal,
}

const Map<DhamakaCaptionStyle, String> dhamakaCaptionLabels = {
  DhamakaCaptionStyle.boldBox: 'Bold Box',
  DhamakaCaptionStyle.outline: 'Outline',
  DhamakaCaptionStyle.karaoke: 'Karaoke',
  DhamakaCaptionStyle.bounce: 'Bounce',
  DhamakaCaptionStyle.typewriter: 'Typewriter',
  DhamakaCaptionStyle.glow: 'Glow',
  DhamakaCaptionStyle.minimal: 'Minimal',
};

class DhamakaTools {
  /// Reverse video + audio.
  static String reverseCommand({
    required String input,
    required String output,
  }) {
    return '-y -i ${FfmpegService.q(input)} '
        '-vf "reverse" -af "areverse" '
        '-c:v libx264 -preset veryfast -crf 23 -c:a aac '
        '-movflags +faststart ${FfmpegService.q(output)}';
  }

  /// Freeze frame: hold [freezeAt] second as a still for [holdSecs].
  static String freezeFrameCommand({
    required String input,
    required double freezeAt,
    required double holdSecs,
    required String output,
  }) {
    final f = freezeAt.clamp(0.0, 3600.0);
    final h = holdSecs.clamp(0.5, 10.0);
    // trim before + freeze frame + trim after, then concat
    return '-y -i ${FfmpegService.q(input)} '
        '-filter_complex '
        '"[0:v]trim=0:$f,setpts=PTS-STARTPTS[pre];'
        '[0:v]trim=$f:${f + 0.04},setpts=PTS-STARTPTS,'
        'tpad=stop_mode=clone:stop_duration=$h[frz];'
        '[0:v]trim=${f + 0.04},setpts=PTS-STARTPTS[post];'
        '[pre][frz][post]concat=n=3:v=1:a=0[vout]" '
        '-map "[vout]" -map 0:a? '
        '-c:v libx264 -preset veryfast -crf 23 -c:a aac '
        '-movflags +faststart ${FfmpegService.q(output)}';
  }

  /// Crossfade with a specific transition type (replaces the fade-only
  /// xfadeCommand for the transition picker).
  static String? xfadeWithTransitionCommand({
    required List<String> inputs,
    required List<int> durationsMs,
    required XfadeTransition transition,
    double transitionSecs = 0.5,
    required bool hasAudio,
    required String output,
  }) {
    if (inputs.length < 2) return null;
    final t = transition.name;
    final d = transitionSecs.clamp(0.2, 2.0);
    final fadeMs = (d * 1000).round();
    final buf = StringBuffer();
    for (final i in inputs) {
      buf.write('-i ${FfmpegService.q(i)} ');
    }
    buf.write('-filter_complex "');
    var prev = '[0:v]';
    var offsetMs = durationsMs[0] - fadeMs;
    for (var i = 1; i < inputs.length; i++) {
      final out = i == inputs.length - 1 ? '[vout]' : '[vx$i]';
      buf.write('$prev[$i:v]xfade=transition=$t:duration=$d:offset=${offsetMs / 1000.0}$out;');
      prev = out;
      offsetMs += durationsMs[i] - fadeMs;
    }
    if (hasAudio) {
      var aprev = '[0:a]';
      for (var i = 1; i < inputs.length; i++) {
        final out = i == inputs.length - 1 ? '[aout]' : '[ax$i]';
        buf.write('$aprev[$i:a]acrossfade=d=$d$out;');
        aprev = out;
      }
      buf.write('" -map "[vout]" -map "[aout]"');
    } else {
      buf.write('" -map "[vout]"');
    }
    buf.write(' -c:v libx264 -preset veryfast -crf 23 -c:a aac '
        '-movflags +faststart ${FfmpegService.q(output)}');
    return buf.toString();
  }

  /// Color adjustments filter chain.
  /// brightness: -1.0..1.0, contrast: 0.5..2.0, saturation: 0.0..3.0,
  /// sharpness: 0.0..2.0 (unsharp amount).
  static String adjustmentFilter({
    double brightness = 0.0,
    double contrast = 1.0,
    double saturation = 1.0,
    double sharpness = 0.0,
    double temperature = 0.0, // -1.0..1.0 (cool..warm)
  }) {
    final parts = <String>[];
    final b = brightness.clamp(-1.0, 1.0);
    final c = contrast.clamp(0.5, 2.0);
    final s = saturation.clamp(0.0, 3.0);
    if (b != 0.0 || c != 1.0 || s != 1.0) {
      parts.add('eq=brightness=$b:contrast=$c:saturation=$s');
    }
    final sh = sharpness.clamp(0.0, 2.0);
    if (sh > 0.01) {
      parts.add('unsharp=5:5:$sh:5:5:0.0');
    }
    final t = temperature.clamp(-1.0, 1.0);
    if (t.abs() > 0.01) {
      final temp = t > 0 ? 3800 : 8500;
      final mix = t.abs() * 0.6;
      parts.add('colortemperature=temperature=$temp:mix=$mix:pl=1');
    }
    return parts.join(',');
  }

  /// Video effect filter for a preset.
  static String videoEffectFilter(VideoEffect effect) {
    switch (effect) {
      case VideoEffect.none:
        return '';
      case VideoEffect.glitch:
        return 'noise=alls=20:allf=t,'
            'crop=iw-8:ih-4:(iw-8)*0.5*sin(2*PI*t*3):(ih-4)*0.5*sin(2*PI*t*2)';
      case VideoEffect.shake:
        return 'crop=iw-20:ih-20:'
            '10*sin(2*PI*t*8):10*cos(2*PI*t*6)';
      case VideoEffect.vhs:
        return 'noise=alls=12:allf=t,'
            'eq=saturation=1.3:contrast=1.1,'
            'vignette=PI/5';
      case VideoEffect.blurBg:
        return 'gblur=sigma=8';
      case VideoEffect.oldFilm:
        return 'curves=vintage,noise=alls=8:allf=t,vignette=PI/4';
      case VideoEffect.rgbSplit:
        return 'split[a][b];[a]colorchannelmixer=1:0:0:0:0:0:0:0:0:0[r];'
            '[b]colorchannelmixer=0:0:0:0:1:0:0:0:0:1[g];'
            '[r][g]blend=all_mode=screen';
      case VideoEffect.zoomPulse:
        return 'scale=iw*1.1:ih*1.1,'
            'zoompan=z=\'1+0.1*sin(2*PI*t/2)\':d=1:x=iw/2-(iw/zoom/2):y=ih/2-(ih/zoom/2):s=iwxih';
    }
  }

  /// Audio filter chain for volume/fade/normalize/effects.
  static String audioFilterChain({
    double volume = 1.0,
    double fadeInSecs = 0.0,
    double fadeOutSecs = 0.0,
    double? fadeOutFrom, // seconds; null = auto (end)
    bool normalize = false,
    AudioEffect effect = AudioEffect.none,
    double speed = 1.0,
    bool keepPitch = true,
  }) {
    final parts = <String>[];
    final v = volume.clamp(0.0, 3.0);
    if (v != 1.0) parts.add('volume=$v');
    if (fadeInSecs > 0) {
      parts.add('afade=t=in:st=0:d=${fadeInSecs.clamp(0.1, 10.0)}');
    }
    if (fadeOutSecs > 0) {
      final st = fadeOutFrom != null ? ':st=$fadeOutFrom' : '';
      parts.add('afade=t=out$st:d=${fadeOutSecs.clamp(0.1, 10.0)}');
    }
    if (normalize) parts.add('loudnorm');
    switch (effect) {
      case AudioEffect.none:
        break;
      case AudioEffect.chipmunk:
        parts.add('asetrate=48000*1.5,aresample=48000,atempo=1/1.5');
        break;
      case AudioEffect.robot:
        parts.add('afftdn,vibrato=f=8:d=0.8');
        break;
      case AudioEffect.echo:
        parts.add('aecho=0.8:0.7:60:0.4');
        break;
      case AudioEffect.bassBoost:
        parts.add('bass=g=10:f=110:w=0.6');
        break;
      case AudioEffect.trebleBoost:
        parts.add('treble=g=10:f=4000:w=0.5');
        break;
      case AudioEffect.nightcore:
        parts.add('asetrate=48000*1.25,aresample=48000,atempo=1/1.25');
        break;
      case AudioEffect.slowed:
        parts.add('asetrate=48000*0.8,aresample=48000,atempo=1/0.8');
        break;
    }
    if (speed != 1.0) {
      final s = speed.clamp(0.25, 4.0);
      if (keepPitch) {
        // atempo only handles 0.5..2.0 per instance; chain if needed
        var remaining = s;
        while (remaining > 2.0) {
          parts.add('atempo=2.0');
          remaining /= 2.0;
        }
        while (remaining < 0.5) {
          parts.add('atempo=0.5');
          remaining /= 0.5;
        }
        parts.add('atempo=$remaining');
      } else {
        parts.add('asetrate=48000*$s,aresample=48000');
      }
    }
    return parts.join(',');
  }

  /// Voice enhancement: EQ + compression preset.
  static String voiceEnhanceFilter() {
    return 'highpass=f=80,'
        'equalizer=f=3000:t=q:w=1:g=3,'
        'acompressor=threshold=-20dB:ratio=4:attack=5:release=50,'
        'loudnorm';
  }

  /// Noise reduction (light, safe).
  static String noiseReduceFilter() {
    return 'afftdn=nf=-25';
  }

  /// Auto-ducking: music at [musicInput] ducks under voice at [voiceInput].
  static String duckingCommand({
    required String voiceInput,
    required String musicInput,
    double musicVolume = 0.3,
    required String output,
  }) {
    final mv = musicVolume.clamp(0.05, 1.0);
    return '-y -i ${FfmpegService.q(voiceInput)} -i ${FfmpegService.q(musicInput)} '
        '-filter_complex '
        '"[1:a]volume=$mv[m];'
        '[m][0:a]sidechaincompress=threshold=0.02:ratio=8:attack=5:release=400[ducked];'
        '[0:a][ducked]amix=inputs=2:duration=first[aout]" '
        '-map 0:v -map "[aout]" '
        '-c:v copy -c:a aac -movflags +faststart ${FfmpegService.q(output)}';
  }

  /// PIP overlay: [overlayInput] scaled to [overlayWidth] at [x],[y].
  static String pipCommand({
    required String baseInput,
    required String overlayInput,
    int overlayWidth = 480,
    String x = 'W-w-16',
    String y = 'H-h-16',
    required String output,
  }) {
    final w = overlayWidth.clamp(120, 1080);
    return '-y -i ${FfmpegService.q(baseInput)} -i ${FfmpegService.q(overlayInput)} '
        '-filter_complex "[1:v]scale=$w:-1[pip];[0:v][pip]overlay=$x:$y[vout]" '
        '-map "[vout]" -map 0:a? '
        '-c:v libx264 -preset veryfast -crf 23 -c:a aac '
        '-movflags +faststart ${FfmpegService.q(output)}';
  }

  /// GIF export (palette-optimized).
  static String gifCommand({
    required String input,
    required double trimStart,
    required double trimEnd,
    int width = 480,
    int fps = 12,
    required String output,
  }) {
    final w = width.clamp(240, 720);
    final f = fps.clamp(5, 24);
    final dur = (trimEnd - trimStart).clamp(0.5, 15.0);
    return '-y -ss $trimStart -t $dur -i ${FfmpegService.q(input)} '
        '-vf "fps=$f,scale=$w:-1:flags=lanczos,split[s0][s1];'
        '[s0]palettegen=max_colors=128[p];[s1][p]paletteuse" '
        '${FfmpegService.q(output)}';
  }

  /// 60fps interpolation.
  static String sixtyFpsFilter() => 'minterpolate=fps=60:mi_mode=mci';

  /// 4K upscale filter.
  static String upscale4kFilter() => 'scale=3840:2160:flags=lanczos';

  /// ASS subtitle style for a dhamaka caption style.
  /// Returns the [V4+ Styles] Format/Style lines.
  static String assStyle(DhamakaCaptionStyle style, {int fontSize = 56}) {
    const font = 'Roboto';
    switch (style) {
      case DhamakaCaptionStyle.boldBox:
        return 'Style: Default,$font,$fontSize,&H00FFFFFF,&H000019FF,&H96000000,&H00000000,'
            '-1,0,0,0,100,100,0,0,1,3,2,2,10,10,10,1';
      case DhamakaCaptionStyle.outline:
        return 'Style: Default,$font,$fontSize,&H00FFFFFF,&H000019FF,&HFF000000,&HFF000000,'
            '-1,0,0,0,100,100,0,0,1,4,0,2,10,10,10,1';
      case DhamakaCaptionStyle.karaoke:
        return 'Style: Default,$font,$fontSize,&H00FFFFFF,&H0000FFFF,&H96000000,&H00000000,'
            '-1,0,0,0,100,100,0,0,1,2,1,2,10,10,10,1';
      case DhamakaCaptionStyle.bounce:
        return 'Style: Default,$font,${fontSize + 8},&H00FFFFFF,&H000019FF,&H96000000,&H00000000,'
            '-1,0,0,0,100,100,0,0,1,3,2,2,10,10,10,1';
      case DhamakaCaptionStyle.typewriter:
        return 'Style: Default,Courier New,$fontSize,&H0000FF00,&H000019FF,&H96000000,&H00000000,'
            '-1,0,0,0,100,100,0,0,1,2,0,2,10,10,10,1';
      case DhamakaCaptionStyle.glow:
        return 'Style: Default,$font,$fontSize,&H00FFFFFF,&H00FFFF00,&H96000000,&H6400FFFF,'
            '-1,0,0,0,100,100,0,0,1,2,2,2,10,10,10,1';
      case DhamakaCaptionStyle.minimal:
        return 'Style: Default,$font,${fontSize - 8},&H00FFFFFF,&H000019FF,&H00000000,&H00000000,'
            '-1,0,0,0,100,100,0,0,1,0,0,2,10,10,10,1';
    }
  }

  /// ASS event line with karaoke timing for a word list.
  /// [words] = list of (word, startMs, endMs).
  static String assKaraokeLine(
    List<(String, int, int)> words,
    int lineStartMs,
    int lineEndMs,
  ) {
    final buf = StringBuffer();
    buf.write('Dialogue: 0,');
    buf.write(_assTime(lineStartMs));
    buf.write(',');
    buf.write(_assTime(lineEndMs));
    buf.write(',Default,,0,0,0,,');
    for (final (word, s, e) in words) {
      final durCs = ((e - s) / 10).round().clamp(1, 999);
      buf.write('{\\kf$durCs}${_escapeAss(word)} ');
    }
    return buf.toString();
  }

  static String _assTime(int ms) {
    final h = ms ~/ 3600000;
    final m = (ms % 3600000) ~/ 60000;
    final s = (ms % 60000) ~/ 1000;
    final cs = (ms % 1000) ~/ 10;
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.'
        '${cs.toString().padLeft(2, '0')}';
  }

  static String _escapeAss(String s) {
    return s.replaceAll('{', '\\{').replaceAll('}', '\\}');
  }
}
