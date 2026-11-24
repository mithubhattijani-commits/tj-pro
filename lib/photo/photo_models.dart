/// Photo Editor shared models + constants (Master Plan Phase 7
/// split). Was the top of photo_editor_screen.dart: the text /
/// overlay layer data classes and the editor's colour + filter
/// constants, now public so the split-out panels, helpers and
/// stage can use them. Values unchanged.
library;

import 'package:flutter/material.dart';

import '../services/photo_pipeline.dart';

/// Round-2 theme unification (P13): violet identity, same as the
/// rest of the app. The Export pill wears the approved mockup's
/// coral red (S3).
const kPhotoAccent = Color(0xFF7C3AED);
const kPhotoAccentLight = Color(0xFFA78BFA);
const kPhotoExportRed = Color(0xFFFF4D5E);

const kPhotoFilterLabels = {
  PhotoFilter.normal: 'Normal',
  PhotoFilter.warm: 'Warm',
  PhotoFilter.cool: 'Cool',
  PhotoFilter.blackWhite: 'B&W',
  PhotoFilter.vivid: 'Vivid',
  PhotoFilter.sepia: 'Sepia',
};

/// Filter category chips (requirements #2). Each category lists the
/// look keys it shows: `f:<PhotoFilter name>` or `lut:<LUT name>`.
const kPhotoFilterCategories = <String, List<String>>{
  'Feature': [
    'f:normal',
    'f:warm',
    'f:cool',
    'f:blackWhite',
    'f:vivid',
    'f:sepia',
    'lut:TealOrange',
    'lut:Vintage',
    'lut:Noir',
    'lut:Golden',
    'lut:CoolNight',
  ],
  'Lunar': ['f:blackWhite', 'f:cool', 'lut:Noir', 'lut:CoolNight'],
  'Skin': ['f:warm', 'f:sepia', 'lut:Golden'],
  'Jade': ['f:cool', 'lut:TealOrange', 'lut:CoolNight'],
  'Foodie': ['f:warm', 'f:vivid', 'lut:Golden'],
  'Clear': ['f:normal', 'f:vivid', 'f:cool'],
  'Bright': ['f:vivid', 'f:warm', 'lut:Golden'],
  'Retro': ['f:sepia', 'f:blackWhite', 'lut:Vintage', 'lut:Noir'],
  'Moss': ['f:cool', 'f:sepia', 'lut:TealOrange'],
};

const kPhotoPalette = <Color>[
  Colors.white,
  Colors.black,
  Color(0xFFFFD60A),
  Colors.amber,
  Colors.orange,
  Colors.red,
  Colors.pink,
  Color(0xFF9C27B0),
  Colors.blue,
  Colors.cyan,
  Colors.teal,
  Colors.green,
  Colors.lime,
  Colors.brown,
  Colors.grey,
  Color(0xFFFFD76A),
];

const kPhotoStickerGlyphs = <String>[
  '★',
  '♥',
  '⚡',
  '☀',
  '☾',
  '♠',
  '♣',
  '♦',
  '😊',
  '😂',
  '🔥',
  '👍',
  '🎉',
  '✨',
  '🌟',
  '💛',
];

/// One editable text layer (v1.4.0 Text system). The screen's single
/// set of text fields always mirrors the ACTIVE layer; layers are
/// saved/loaded through saveActiveLayer/loadLayer and every layer
/// is composited at export via exportPhotoWithLayers.
class TextLayerData {
  TextLayerData();

  String text = '';
  int colorArgb = 0xFFFFFFFF;
  double size = 42;
  Offset offset = const Offset(0.5, 0.8); // normalized centre
  double boxWidth = 0.7; // fraction of photo width
  double rotation = 0; // degrees, clockwise
  String font = 'default';
  bool bold = false;
  bool italic = false;
  double opacity = 1.0;
  double letterSpacing = 0.0;
  double lineSpacing = 1.0;
  int alignIndex = 1; // 0 left, 1 centre, 2 right
  bool shadow = true;
  int shadowArgb = 0xDD000000;
  double shadowDx = 2;
  double shadowDy = 3;
  double shadowBlur = 6;
  bool glow = false;
  int glowArgb = 0xFFFFFFFF;
  double glowBlur = 16;
  bool outline = false;
  int outlineArgb = 0xFF000000;
  double outlineWidth = 2.0;
  bool bg = false;
  int bgArgb = 0x8A000000;

  TextLayerData clone() {
    final c = TextLayerData();
    c.text = text;
    c.colorArgb = colorArgb;
    c.size = size;
    c.offset = offset;
    c.boxWidth = boxWidth;
    c.rotation = rotation;
    c.font = font;
    c.bold = bold;
    c.italic = italic;
    c.opacity = opacity;
    c.letterSpacing = letterSpacing;
    c.lineSpacing = lineSpacing;
    c.alignIndex = alignIndex;
    c.shadow = shadow;
    c.shadowArgb = shadowArgb;
    c.shadowDx = shadowDx;
    c.shadowDy = shadowDy;
    c.shadowBlur = shadowBlur;
    c.glow = glow;
    c.glowArgb = glowArgb;
    c.glowBlur = glowBlur;
    c.outline = outline;
    c.outlineArgb = outlineArgb;
    c.outlineWidth = outlineWidth;
    c.bg = bg;
    c.bgArgb = bgArgb;
    return c;
  }
}

/// One PIP photo / sticker-glyph overlay layer.
class OverlayData {
  OverlayData({this.path, this.glyph});

  String? path; // gallery photo (PIP)
  String? glyph; // sticker character
  Offset center = const Offset(0.5, 0.5); // normalized
  double scaleFrac = 0.35; // width as a fraction of photo width
  double rotation = 0; // degrees
}
