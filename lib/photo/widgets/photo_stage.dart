/// PhotoStage of the Photo Editor (Master Plan Phase 7 split).
///
/// Was a method of `_PhotoEditorScreenState` in
/// photo_editor_screen.dart; now a real widget in its own file.
/// All editor state is reached through [PhotoEditorController] —
/// behaviour unchanged.
library;


import 'dart:io';

import 'package:flutter/material.dart';

import '../photo_editor_controller.dart';
import 'layer_widgets.dart';
import 'photo_widgets.dart';

class PhotoStage extends StatelessWidget {
  final PhotoEditorController host;
  final File file;
  const PhotoStage(this.host, this.file, {super.key});

  @override
  Widget build(BuildContext context) {
    final aspect = (host.imgWidth > 0 && host.imgHeight > 0)
        ? host.imgWidth / host.imgHeight
        : 1.0;
    return Center(
      child: AspectRatio(
        aspectRatio: aspect,
        child: LayoutBuilder(
          builder: (ctx, cons) {
            final size = Size(cons.maxWidth, cons.maxHeight);
            return Stack(
              key: host.previewKey2,
              clipBehavior: Clip.none,
              children: [
                if (host.hasTransparency)
                  Positioned.fill(
                    child: CustomPaint(painter: PhotoCheckerPainter()),
                  ),
                Positioned.fill(
                  child: host.comparing && host.originalFile != null
                      ? Image.file(host.originalFile!, fit: BoxFit.fill)
                      : host.previewBytes != null && host.previewKey == file.path
                      ? Image.memory(host.previewBytes!, fit: BoxFit.fill)
                      : ColorFiltered(
                          colorFilter: ColorFilter.matrix(host.matrix),
                          child: Image.file(file, fit: BoxFit.fill),
                        ),
                ),
                for (var i = 0; i < host.overlays.length; i++)
                  OverlayWidget(host, host.overlays[i], i, size),
                for (var i = 0; i < host.layers.length; i++)
                  if (host.layers[i].text.isNotEmpty)
                    TextLayerWidget(host, host.layers[i], i, size),
                if (host.paintMode != null)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (d) => host.paintStart(d.localPosition, size),
                      onPanUpdate: (d) => host.paintUpdate(d.localPosition, size),
                      onPanEnd: (_) => host.paintEnd(),
                      child: CustomPaint(
                        painter: PhotoStrokePainter(
                          strokes: host.strokes,
                          current: host.currentStroke,
                          mode: host.paintMode!,
                          doodleColor: host.doodleColor,
                        ),
                        size: size,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
