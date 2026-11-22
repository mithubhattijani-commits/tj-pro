/// Audio enhance — noise reduction + voice enhance (v1.4.0).
///
/// [reduceNoise] runs ffmpeg's `arnndn` filter (RNNoise, BSD — the
/// tool-test battery's PASS at RTF 0.080, +4.5 dB SNR) with the
/// official `cb.rnnn` model from the downloadable `rnnoise_models`
/// pack. When the model pack is unavailable, or the bundled ffmpeg
/// rejects arnndn, it falls back to the built-in `afftdn` FFT
/// denoiser — a weaker but always-present path.
///
/// [enhanceVoice] — DeepFilterNet3 DECISION (read before changing):
/// the DFN3 ONNX graphs were inspected for this build
/// (tool-tests/05-audio-rife/deepfilternet/DeepFilterNet3_onnx.tar.gz):
///   enc.onnx     in  feat_erb [1,1,S,32] + feat_spec [1,2,S,96]
///                out e0..e3 skips, emb [.,S,.], c0, lsnr
///   erb_dec.onnx in  emb [1,S,512] + e0..e3 -> ERB mask [.,1,S,32]
///   df_dec.onnx  in  emb + c0 -> coefs [.,S,.,10] + alpha
///   config.ini   sr 48000, fft_size 960, hop_size 480, nb_erb 32,
///                nb_df 96, df_order 5, df_lookahead 2, norm_tau 1
/// A faithful port needs the OFFICIAL feature pipeline around those
/// graphs: the exact ERB filterbank matrix, the running mean/var
/// feature normalization states, the ERB->FFT gain interpolation,
/// and the deep-filtering stage applying the predicted complex
/// coefficients over 5 frames with lookahead + alpha blending,
/// inside a 48 kHz STFT/ISTFT with the model's window. None of that
/// can be verified against the official runtime from this build
/// environment, and a subtly wrong DSP port would silently corrupt
/// users' audio — so per the build contract's rule ("never ship a
/// guessed DSP port"), [enhanceVoice] ships an ffmpeg chain instead:
/// high-pass -> afftdn denoise -> presence EQ -> gentle compression
/// -> loudnorm. The DFN3 pack stays registered in ModelPackService
/// for the release that ports + verifies the pipeline on-device.
///
/// Both methods NEVER throw: false means "could not enhance, keep
/// the original file".
library;

import 'dart:io';

import 'ffmpeg_service.dart';
import 'model_pack_service.dart';

class AudioEnhanceService {
  AudioEnhanceService._();

  /// Shared instance (the contract API).
  static final AudioEnhanceService instance = AudioEnhanceService._();

  /// Output codec for a path: WAV keeps PCM, everything else AAC
  /// (the app's audio exports are wav/m4a in practice).
  static String _codecFor(String outPath) =>
      outPath.toLowerCase().endsWith('.wav') ? 'pcm_s16le' : 'aac';

  static Future<bool> _outputOk(String outPath) async {
    try {
      final File f = File(outPath);
      return await f.exists() && await f.length() > 0;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _runChain(String inPath, String outPath, String af) async {
    try {
      final FfmpegResult result = await FfmpegService.run(
        '-y -i ${FfmpegService.q(inPath)} -vn -af "$af" '
        '-c:a ${_codecFor(outPath)} ${FfmpegService.q(outPath)}',
      );
      return result.ok && await _outputOk(outPath);
    } catch (_) {
      return false;
    }
  }

  /// Reduces background noise in [inPath], writing [outPath].
  /// RNNoise (arnndn + the pack's cb.rnnn model) first; the afftdn
  /// FFT denoiser as fallback. RNNoise operates at 48 kHz, so the
  /// chain resamples first (the battery's clips were 48 kHz too).
  Future<bool> reduceNoise(String inPath, String outPath) async {
    try {
      File? model;
      try {
        if (await ModelPackService.instance
            .ensurePack('rnnoise_models')) {
          model = await ModelPackService.instance
              .packFile('rnnoise_models', 'cb.rnnn');
        }
      } catch (_) {
        model = null;
      }
      if (model != null) {
        final bool ok = await _runChain(
          inPath,
          outPath,
          'aresample=48000,arnndn=m=${FfmpegService.q(model.path)}',
        );
        if (ok) return true;
        // arnndn missing/rejected in this ffmpeg build -> fallback.
      }
      return _runChain(
        inPath,
        outPath,
        'aresample=48000,afftdn=nf=-25',
      );
    } catch (_) {
      return false;
    }
  }

  /// Enhances a voice recording in [inPath], writing [outPath]:
  /// gentle denoise + presence lift + compression + loudness
  /// normalization to -16 LUFS (podcast/voice level). Ships the
  /// ffmpeg chain documented in the file header — DeepFilterNet3's
  /// ONNX pipeline is NOT ported in v1.4.0 (see header for why).
  /// If the full chain fails, a plain loudnorm pass is tried.
  Future<bool> enhanceVoice(String inPath, String outPath) async {
    try {
      final bool ok = await _runChain(
        inPath,
        outPath,
        'highpass=f=80,afftdn=nf=-25,'
        'equalizer=f=3000:width_type=o:width=2:g=3,'
        'acompressor=threshold=0.5:ratio=3:attack=20:release=200,'
        'loudnorm=I=-16:TP=-1.5:LRA=11',
      );
      if (ok) return true;
      return _runChain(
        inPath,
        outPath,
        'loudnorm=I=-16:TP=-1.5:LRA=11',
      );
    } catch (_) {
      return false;
    }
  }
}
