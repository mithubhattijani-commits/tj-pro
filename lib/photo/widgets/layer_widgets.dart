/// Layer widgets of the Photo Editor (Master Plan Phase 7 split).
///
/// Was a method of `_PhotoEditorScreenState` in
/// photo_editor_screen.dart; now a real widget in its own file.
/// All editor state is reached through [PhotoEditorController] —
/// behaviour unchanged.
library;


import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../photo_editor_controller.dart';
import '../photo_models.dart';
import 'panel_helpers.dart';

class LayerTextWidget extends StatelessWidget {
  final PhotoEditorController host;
  final TextLayerData layer;
  final double s;
  const LayerTextWidget(this.host, this.layer, this.s, {super.key});

  @override
  Widget build(BuildContext context) {
    final fontPx = layer.size * s;
    final style = host.layerStyle(layer, fontPx, s);
    final align = layer.alignIndex == 0
        ? TextAlign.left
        : layer.alignIndex == 2
        ? TextAlign.right
        : TextAlign.center;
    Widget tw;
    if (layer.outline) {
      tw = Stack(
        alignment: Alignment.center,
        children: [
          Text(
            layer.text,
            textAlign: align,
            style: style.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = layer.outlineWidth * s
                ..color = Color(layer.outlineArgb),
              shadows: [],
            ),
          ),
          Text(layer.text, textAlign: align, style: style),
        ],
      );
    } else {
      tw = Text(layer.text, textAlign: align, style: style);
    }
    if (layer.bg) {
      tw = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Color(layer.bgArgb),
          borderRadius: BorderRadius.circular(10),
        ),
        child: tw,
      );
    }
    return tw;
  }
}

class TextLayerWidget extends StatelessWidget {
  final PhotoEditorController host;
  final TextLayerData layer;
  final int index;
  final Size box;
  const TextLayerWidget(this.host, this.layer, this.index, this.box, {super.key});

  @override
  Widget build(BuildContext context) {
    final isActive = index == host.activeLayer;
    final showHandles = isActive && host.activePhotoTool == 'text';
    final s = host.imgWidth > 0 ? box.width / host.imgWidth : 0.6;
    final w = layer.boxWidth * box.width;
    final center = Offset(
      layer.offset.dx * box.width,
      layer.offset.dy * box.height,
    );
    return Positioned(
      left: center.dx,
      top: center.dy,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Transform.rotate(
          angle: layer.rotation * math.pi / 180,
          child: SizedBox(
            width: w,
            child: GestureDetector(
              onTap: () {
                if (host.activePhotoTool == 'text' && !isActive) {
                  host.update(() {
                    host.saveActiveLayer();
                    host.loadLayer(index);
                  });
                }
              },
              onLongPress: host.activePhotoTool == 'text'
                  ? () => host.layerMenu(index)
                  : null,
              onPanUpdate: (d) {
                if (host.activePhotoTool != 'text') return;
                if (!isActive) {
                  host.update(() {
                    host.saveActiveLayer();
                    host.loadLayer(index);
                  });
                  return;
                }
                host.update(() {
                  layer.offset = Offset(
                    (layer.offset.dx + d.delta.dx / box.width).clamp(
                      0.05,
                      0.95,
                    ),
                    (layer.offset.dy + d.delta.dy / box.height).clamp(
                      0.05,
                      0.95,
                    ),
                  );
                  host.textOffset = layer.offset;
                });
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: w,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    decoration: showHandles
                        ? BoxDecoration(
                            border: Border.all(color: Colors.white, width: 1.2),
                          )
                        : null,
                    child: LayerTextWidget(host, layer, s),
                  ),
                  if (showHandles) ...[
                    // Red ✕ delete handle (top-left).
                    Positioned(
                      left: -11,
                      top: -11,
                      child: GestureDetector(
                        onTap: () {
                          host.update(() {
                            host.loadLayer(index);
                          });
                          host.deleteActiveLayer();
                        },
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    // Rotate/scale handle (bottom-right): circular
                    // drag around the box centre rotates; distance
                    // from the centre scales the font.
                    Positioned(
                      right: -11,
                      bottom: -11,
                      child: GestureDetector(
                        onPanStart: (d) {
                          final local = host.toPreviewLocal(d.globalPosition);
                          final v = local - center;
                          host.handleStartAngle = math.atan2(v.dy, v.dx);
                          host.handleStartDist = math.max(20, v.distance);
                          host.handleStartRot = layer.rotation;
                          host.handleStartSize = layer.size;
                        },
                        onPanUpdate: (d) {
                          final local = host.toPreviewLocal(d.globalPosition);
                          final v = local - center;
                          host.update(() {
                            layer.rotation =
                                host.handleStartRot +
                                (math.atan2(v.dy, v.dx) - host.handleStartAngle) *
                                    180 /
                                    math.pi;
                            layer.size =
                                (host.handleStartSize *
                                        v.distance /
                                        host.handleStartDist)
                                    .clamp(14, 300);
                            host.textRotation = layer.rotation;
                            host.textSize = layer.size;
                          });
                        },
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.rotate_right,
                            size: 14,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                    // White side dots: drag to change the box width.
                    Positioned(
                      left: -6,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: GestureDetector(
                          onPanUpdate: (d) => host.update(() {
                            layer.boxWidth =
                                (layer.boxWidth - d.delta.dx * 2 / box.width)
                                    .clamp(0.15, 0.98);
                            host.textBoxWidth = layer.boxWidth;
                          }),
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: -6,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: GestureDetector(
                          onPanUpdate: (d) => host.update(() {
                            layer.boxWidth =
                                (layer.boxWidth + d.delta.dx * 2 / box.width)
                                    .clamp(0.15, 0.98);
                            host.textBoxWidth = layer.boxWidth;
                          }),
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OverlayWidget extends StatelessWidget {
  final PhotoEditorController host;
  final OverlayData o;
  final int index;
  final Size box;
  const OverlayWidget(this.host, this.o, this.index, this.box, {super.key});

  @override
  Widget build(BuildContext context) {
    final w = o.scaleFrac * box.width;
    final selected =
        index == host.activeOverlay &&
        (host.activePhotoTool == 'sticker' || host.activePhotoTool == 'pip');
    return Positioned(
      left: o.center.dx * box.width,
      top: o.center.dy * box.height,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Transform.rotate(
          angle: o.rotation * math.pi / 180,
          child: GestureDetector(
            onTap: () => host.update(() => host.activeOverlay = index),
            onPanUpdate: (d) => host.update(() {
              host.activeOverlay = index;
              o.center = Offset(
                (o.center.dx + d.delta.dx / box.width).clamp(0.05, 0.95),
                (o.center.dy + d.delta.dy / box.height).clamp(0.05, 0.95),
              );
            }),
            child: Container(
              decoration: selected
                  ? BoxDecoration(
                      border: Border.all(color: Colors.white, width: 1.2),
                    )
                  : null,
              child: o.glyph != null
                  ? Text(o.glyph!, style: TextStyle(fontSize: w * 0.85))
                  : Image.file(File(o.path!), width: w, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }
}

