/// Video Editor controller contract (Master Plan Phase 4).
///
/// The editor's panels, timeline, tool rows, stage and export code
/// used to live inside `_VideoEditorScreenState` (directly, or via
/// the panels part-file extension), reading and writing its private
/// members. Phase 4 splits those into real widgets in their own
/// files; this contract is the ONE channel they use to reach the
/// editor's state. Every member is a thin forward to the State's
/// existing private field/method — same objects, same setState
/// timing, same everything. Behaviour is unchanged by construction.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../live/news_template.dart';
import '../news/channel_preset.dart';
import '../news/news_project.dart';
import '../services/caption_service.dart';
import '../services/pro_editor.dart';
import '../services/fx_pack.dart';
import '../services/pro_vision.dart';
import '../services/video_export_service.dart';
import 'editor_models.dart';

/// The surface of the editor State that the split-out widgets use.
///
/// Implemented by `_VideoEditorScreenState`; every member forwards
/// to the State's private member of the same (underscored) name.
abstract class VideoEditorController {
  /// The editor screen's own build context (the exact object the
  /// pre-split code used for dialogs, sheets and lookups).
  BuildContext get context;

  /// Whether the editor State is still mounted.
  bool get mounted;

  /// `setState` under a split-friendly name: runs [fn] and rebuilds,
  /// exactly like the State's own setState calls did.
  void update(VoidCallback fn);

  String? get activeTool;
  set activeTool(String? value);
  Future<void> addClip();
  Future<void> addPhotoClip();
  void addMarkerAtPlayhead();
  bool get adjAuto;
  set adjAuto(bool value);
  double get adjBlacks;
  set adjBlacks(double value);
  double get adjBrilliance;
  set adjBrilliance(double value);
  double get adjClarity;
  set adjClarity(double value);
  double get adjFade;
  set adjFade(double value);
  double get adjGrain;
  set adjGrain(double value);
  double get adjHue;
  set adjHue(double value);
  double get adjSharpen;
  set adjSharpen(double value);
  double get adjVignette;
  set adjVignette(double value);
  double get adjWhites;
  set adjWhites(double value);
  String adjustExtraFilter();
  List<CaptionSegment> adjustedCaptions();
  bool get aicutBusy;
  set aicutBusy(bool value);
  double get aicutMinSilenceSec;
  set aicutMinSilenceSec(double value);
  List<(double, double)> get aicutRanges;
  set aicutRanges(List<(double, double)> value);
  double get aicutThresholdDb;
  set aicutThresholdDb(double value);
  Future<void> applyBackdropAsset(String asset);
  void applyNewsAnchorPreset();
  void applyPreviewSpeed([double? rate]);
  Future<void> applySlowMoAi();
  String get aspect;
  set aspect(String value);
  bool get autoDuck;
  set autoDuck(bool value);
  bool get beatAutoCut;
  set beatAutoCut(bool value);
  List<double> get beats;
  set beats(List<double> value);
  Future<String?> buildOverlayCommand({ required Directory dir, required int stamp, required String input, required String output, required double durationSec, });
  bool get busy;
  set busy(bool value);
  String get canvasFill;
  set canvasFill(String value);
  String get canvasFillColor;
  set canvasFillColor(String value);
  bool get captionDrawtextFallback;
  set captionDrawtextFallback(bool value);
  String get captionLocale;
  set captionLocale(String value);
  CaptionStyle get captionStyle;
  set captionStyle(CaptionStyle value);
  List<CaptionSegment> get captions;
  // v1.16.0 G4 (A18): whether [captions] are timeline-relative
  // (handoff/import) or recorded against the selected clip —
  // the captions lane maps them with the export's own rule.
  bool get captionsTimelineRelative;
  // v1.16.0 G4 (A18): seek to caption [index]'s start and open
  // the caption editor focused on that caption.
  Future<void> editCaptionAt(int index);
  set captions(List<CaptionSegment> value);
  Future<void> captureFrameInsert();
  void checkExportCancelled();
  bool get chromaPreviewBusy;
  set chromaPreviewBusy(bool value);
  String? get chromaPreviewPath;
  set chromaPreviewPath(String? value);
  bool get clipRow;
  set clipRow(bool value);
  double clipStartSec(int index);
  List<VideoClip> get clips;
  TimelineClock get clock;
  bool get comparing;
  set comparing(bool value);
  VideoPlayerController? get controller;
  set controller(VideoPlayerController? value);
  bool get crossfade;
  set crossfade(bool value);
  double get cutEnd;
  set cutEnd(double value);
  double get cutStart;
  set cutStart(double value);
  String get cutoutMode;
  set cutoutMode(String value);
  Future<void> deleteSelectedClip();
  Future<void> runBeatDetection();
  bool get detectingBeats;
  set detectingBeats(bool value);
  void duplicateSelectedClip();
  // v1.16.0 G3 (A23 + C3): disable/enable the selected clip and
  // set its colour label (0 = none).
  void toggleSelectedClipDisabled();
  void setSelectedClipColorLabel(int label);
  Future<void> editCaptions();
  Future<void> importCaptionsFile();
  Future<void> shareCaptionsFile(String kind);
  List<double> get effectiveDurations;
  bool get elementRow;
  set elementRow(bool value);
  Future<void> enhanceSelectedClipAudio({required bool voice});
  Future<void> enhanceSelectedClipHd();
  void ensureMainMaskImage(int width, int height);
  Future<void> ensureMusicWave(String musicPath);
  void ensurePipMaskImage(int width, int height);
  void ensurePipPreview();
  bool get exportCancelRequested;
  set exportCancelRequested(bool value);
  int get exportFps;
  set exportFps(int value);
  bool get exporting;
  set exporting(bool value);
  Future<void> extractClipAudio();
  Future<void> eyedropperPick();
  String get filter;
  set filter(String value);
  double get filterIntensity;
  set filterIntensity(double value);
  String? get fontFile;
  set fontFile(String? value);
  Color frameBackdropColor();
  Future<void> freezeFrameInsert();
  double get fxFadeIn;
  set fxFadeIn(double value);
  double get fxFadeOut;
  set fxFadeOut(double value);
  bool get fxPip;
  set fxPip(bool value);
  String get fxPipVideo;
  set fxPipVideo(String value);
  int get fxQuality;
  set fxQuality(int value);
  bool get fxReverse;
  ShakeFx get fxShake;
  set fxShake(ShakeFx value);
  bool get fxSilenceRemove;
  set fxSilenceRemove(bool value);
  VoiceFx get fxVoice;
  set fxVoice(VoiceFx value);
  Future<void> generateCaptions();
  Future<void> generateUrduCaptions();
  double get globalPositionSec;
  bool get gradeActive;
  String get gradeSlider;
  set gradeSlider(String value);
  ChannelPreset? get handoffPreset;
  set handoffPreset(ChannelPreset? value);
  NewsProject? get handoffProject;
  set handoffProject(NewsProject? value);
  String? get introClipPath;
  set introClipPath(String? value);
  KeyframeEasing get kfEasing;
  set kfEasing(KeyframeEasing value);
  double get kfEndOpacity;
  set kfEndOpacity(double value);
  double get kfEndRotation;
  set kfEndRotation(double value);
  double get kfEndScale;
  set kfEndScale(double value);
  double get kfEndX;
  set kfEndX(double value);
  double get kfEndY;
  set kfEndY(double value);
  int get kfPage;
  set kfPage(int value);
  double get kfStartOpacity;
  set kfStartOpacity(double value);
  double get kfStartRotation;
  set kfStartRotation(double value);
  double get kfStartScale;
  set kfStartScale(double value);
  double get kfStartX;
  set kfStartX(double value);
  double get kfStartY;
  set kfStartY(double value);
  Set<String> get laneHidden;
  Future<void> loadPreview();
  String get mainMask;
  set mainMask(String value);
  double get mainMaskFeather;
  set mainMaskFeather(double value);
  ui.Image? get mainMaskImage;
  set mainMaskImage(ui.Image? value);
  bool get mainMaskInvert;
  set mainMaskInvert(bool value);
  bool get mainTrackLocked;
  set mainTrackLocked(bool value);
  List<double> get markers;
  set markers(List<double> value);
  void removeMarker(double sec);
  String? get musicPath;
  set musicPath(String? value);
  double get musicVolume;
  set musicVolume(double value);
  // v1.16.0 G3 (A3): lane-level controls — the audio lane's
  // mute (binds the export: muted music never reaches the
  // render) and the PIP lane's lock (guards the window drag +
  // the PIP timing controls against accidental changes).
  bool get musicMuted;
  set musicMuted(bool value);
  bool get pipLaneLocked;
  set pipLaneLocked(bool value);
  Map<String, String> get musicWaveCache;
  // v1.16.0 G4 (A16): per-clip waveform PNG cache (path+trim
  // keyed), rendered once per clip by [ensureClipWave] — the
  // timeline block paints it without ever blocking a scroll.
  Map<String, String> get clipWaveCache;
  void ensureClipWave(VideoClip clip);
  String clipWaveKey(VideoClip clip);
  bool get muteOriginal;
  set muteOriginal(bool value);
  NewsTemplate get news;
  set news(NewsTemplate value);
  bool get newsEnabled;
  set newsEnabled(bool value);
  Future<void> onBgRemoverChanged(bool v);
  void onClipDragEnd(int i);
  void onClipDragMove(LongPressMoveUpdateDetails d);
  void onClipDragStart(int i);
  void onPreviewTapDown(TapDownDetails d, Size mediaBox);
  void onStageScaleStart(ScaleStartDetails d);
  void onStageScaleUpdate(ScaleUpdateDetails d);
  void openTool(String? key);
  void openToolTab(String key, String tab);
  String? get outroClipPath;
  set outroClipPath(String? value);
  String? get panelTab;
  set panelTab(String? value);
  Future<bool?> pickExportSettings();
  Future<void> pickMusic();
  Future<void> pickProImage(ValueChanged<String> onPicked);
  ImagePicker get picker;
  double get pinchPipScale;
  set pinchPipScale(double value);
  String get pipBlend;
  set pipBlend(String value);
  BlendMode? pipBlendMode(String key);
  VideoPlayerController? get pipController;
  set pipController(VideoPlayerController? value);
  Offset get pipDragOffset;
  set pipDragOffset(Offset value);
  bool get pipKeyframes;
  set pipKeyframes(bool value);
  String get pipMask;
  set pipMask(String value);
  double get pipMaskFeather;
  set pipMaskFeather(double value);
  ui.Image? get pipMaskImage;
  set pipMaskImage(ui.Image? value);
  bool get pipMaskInvert;
  set pipMaskInvert(bool value);
  double get pipOpacity;
  set pipOpacity(double value);
  PipPosition get pipPosition;
  set pipPosition(PipPosition value);
  double get pipScale;
  set pipScale(double value);
  // v1.16.0 G2 (Motion M3): the PIP window — the inset shows
  // only inside [pipStartSec, pipEndSec) of the timeline.
  // pipEndSec == -1 means "to the end" (the historical default:
  // the window is the whole timeline).
  double get pipStartSec;
  set pipStartSec(double value);
  double get pipEndSec;
  set pipEndSec(double value);
  String pipSnippetAdvanced({ required VideoSize base, required VideoSize pip, required bool hasMask, });
  KeyframeEasing get pkEasing;
  set pkEasing(KeyframeEasing value);
  double get pkEndOpacity;
  set pkEndOpacity(double value);
  double get pkEndX;
  set pkEndX(double value);
  double get pkEndY;
  set pkEndY(double value);
  int get pkPage;
  set pkPage(int value);
  double get pkStartOpacity;
  set pkStartOpacity(double value);
  double get pkStartX;
  set pkStartX(double value);
  double get pkStartY;
  set pkStartY(double value);
  String get proBgColor;
  set proBgColor(String value);
  String? get proBgImage;
  set proBgImage(String? value);
  String get proBgKind;
  set proBgKind(String value);
  bool get proBgRemove;
  set proBgRemove(bool value);
  double get proBrightness;
  set proBrightness(double value);
  bool get proChroma;
  set proChroma(bool value);
  String get proChromaBgColor;
  set proChromaBgColor(String value);
  String? get proChromaBgImage;
  set proChromaBgImage(String? value);
  String get proChromaBgKind;
  set proChromaBgKind(String value);
  double get proChromaBlend;
  set proChromaBlend(double value);
  String get proChromaColor;
  set proChromaColor(String value);
  double get proChromaEdge;
  set proChromaEdge(double value);
  double get proChromaSimilarity;
  set proChromaSimilarity(double value);
  double get proChromaSpill;
  set proChromaSpill(double value);
  double get proContrast;
  set proContrast(double value);
  double get proExposure;
  set proExposure(double value);
  double get proHighlights;
  set proHighlights(double value);
  bool get proKeyframes;
  set proKeyframes(bool value);
  String get proLut;
  set proLut(String value);
  String get proRamp;
  set proRamp(String value);
  double get proSaturation;
  set proSaturation(double value);
  double get proShadows;
  set proShadows(double value);
  bool get proStabilize;
  set proStabilize(bool value);
  String get proSticker;
  set proSticker(String value);
  String get proStickerPreset;
  set proStickerPreset(String value);
  double get proTemperature;
  set proTemperature(double value);
  double get proTint;
  set proTint(double value);
  String get proTitle;
  set proTitle(String value);
  String get proTitlePosition;
  set proTitlePosition(String value);
  String get proTitlePreset;
  set proTitlePreset(String value);
  String get proTransition;
  set proTransition(String value);
  double get proTransitionDur;
  set proTransitionDur(double value);
  double get proVibrance;
  set proVibrance(double value);
  String? get projectTemplateKind;
  set projectTemplateKind(String? value);
  String? get projectVoiceoverPath;
  set projectVoiceoverPath(String? value);
  void pushHistory();
  bool get qualityPicked;
  set qualityPicked(bool value);
  double get rampEnd;
  set rampEnd(double value);
  double get rampMid;
  set rampMid(double value);
  RampPreset? rampPreset();
  double get rampStart;
  set rampStart(double value);
  Future<void> refreshChromaPreview();
  Future<String?> renderMainMaskPng({ required Directory dir, required int stamp, required int width, required int height, });
  Future<String?> renderPipMaskPng({ required Directory dir, required int stamp, required int width, required int height, });
  Future<void> replaceSelectedClip();
  void resetGrade();
  void resetStageTransform();
  Future<void> reverseSelectedClip();
  Future<void> rotateSelectedClip({required bool flip});
  Future<void> saveFrameSnapshot();
  void scheduleChromaPreview();
  void scheduleScrubSeek();
  int get selected;
  set selected(int value);
  void setStatus(String s);
  bool get showGrid;
  set showGrid(bool value);
  Future<void> showWaveform();
  bool get snapOn;
  set snapOn(bool value);
  double get speed;
  set speed(double value);
  void splitSelectedClip();
  int get stabLevel;
  set stabLevel(int value);
  Rect get stageFrameRect;
  set stageFrameRect(Rect value);
  String? get stageLayer;
  set stageLayer(String? value);
  List<double> get stageMatrix;

  /// P1-1: Adjust-extras overlay strengths for the stage
  /// (vignette 0..1, grain opacity 0..~0.35) — derived from the
  /// same AdjustParams as the export chain; 0 while comparing.
  double get adjustVignetteStrength;
  double get adjustGrainOpacity;

  /// P2: a tool-row item was tapped while its op cannot run
  /// (busy / no clip) — explain WHY in the status line instead
  /// of leaving a dead, dimmed button.
  void explainToolTap();
  Rect get stageMediaRect;
  set stageMediaRect(Rect value);
  Matrix4 stageTransformMatrix(Size frameSize);
  String get status;
  set status(String value);
  Future<void> switchPipToMainTrack();
  String get text;
  set text(String value);
  double get tfOpacity;
  set tfOpacity(double value);
  double get tfRot;
  set tfRot(double value);
  double get tfScale;
  set tfScale(double value);
  double get tfX;
  set tfX(double value);
  double get tfY;
  set tfY(double value);
  Map<String, List<String>> get thumbCache;
  String thumbKey(VideoClip clip);
  List<double> get timelineBeats;
  double get tlPxPerSec;
  set tlPxPerSec(double value);
  ScrollController get tlScroll;
  bool get tlUserScrolling;
  set tlUserScrolling(bool value);
  bool get tlProgrammaticScroll;
  set tlProgrammaticScroll(bool value);
  void tlZoomBy(double factor);

  // ---- v1.14.0 timeline (T1 / T2 / T3). ----
  /// T1 (A13): zoom so the whole timeline fits [widthPx].
  void tlZoomToFit(double widthPx);
  void tlPinchStart();
  void tlPinchUpdate(double scale);

  /// T1 (A20): the timeline's own snap switch + strength
  /// (0 Halki / 1 Normal / 2 Mazboot) — NOT [snapOn] (Split's).
  bool get tlSnapOn;
  set tlSnapOn(bool value);
  int get tlSnapStrength;
  set tlSnapStrength(int value);

  /// The live snap threshold (seconds) for these settings;
  /// 0 = snap off (callers skip snapping entirely).
  double tlSnapThreshold(bool forTrim);

  /// T1 (A14): timecode readouts instead of m:ss.
  bool get timecodeOn;
  set timecodeOn(bool value);

  /// T1 (A14): step the playhead one frame (-1 / +1).
  void stepFrame(int direction);

  /// T2: the timeline handles' mode — 'trim' | 'roll' | 'slip'.
  String get trimMode;
  set trimMode(String value);

  /// T2 (A6 / A7 / A25) ops.
  void rollBoundaryBy(int boundaryIndex, double delta);
  void slipSelectedBy(double delta);
  void trimToPlayheadStart();
  void trimToPlayheadEnd();

  /// T3 (A4): multi-select mode + the ticked clip indices.
  bool get multiMode;
  set multiMode(bool value);
  Set<int> get multiSelect;
  void toggleMultiSelect(int i);
  void clearMultiSelect();
  Future<void> deleteMultiSelected();
  void duplicateMultiSelected();
  void moveMultiSelected(int direction);

  /// T3 (A5): range In/Out (timeline seconds) + loop switch.
  double? get rangeIn;
  double? get rangeOut;
  bool get loopRange;
  set loopRange(bool value);
  void setRangeInAtPlayhead();
  void setRangeOutAtPlayhead();
  void clearRange();
  Future<void> deleteRange();
  double get totalDurationSec;
  Future<void> runObjectTracking();
  List<TrackPoint> get trackPoints;
  set trackPoints(List<TrackPoint> value);
  double? get trackStartX;
  set trackStartX(double? value);
  double? get trackStartY;
  set trackStartY(double? value);
  String get trackSticker;
  set trackSticker(String value);
  bool get tracking;
  set tracking(bool value);
  bool get transcribing;
  set transcribing(bool value);
  bool get transformActive;
  bool get trimSnapped;
  set trimSnapped(bool value);
  Future<void> unlinkSelectedClipAudio();
  List<(double, double)> get volumePoints;
  bool get waveformBusy;
  set waveformBusy(bool value);
  String? get waveformPath;
  set waveformPath(String? value);
  Future<Directory> workDir();
  void cancelPanel();
  Future<void> openFullscreen();
  Future<void> redo();
  List<String> get redoStack;
  Future<void> seekToGlobalSec(double sec);
  Future<void> switchSelectedClipToPip();
  String toolDisplayName(String key);
  Future<void> undo();
  List<String> get undoStack;
}
