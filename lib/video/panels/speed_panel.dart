/// SpeedPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import '../editor_stage.dart';
import '../video_editor_controller.dart';
import '../video_editor_panels.dart';
import '../widgets/panel_controls.dart';

/// SpeedPanel.
class SpeedPanel extends StatelessWidget {
  final VideoEditorController host;
  const SpeedPanel(this.host, {super.key});

  /// Speed › Standard: the legacy speed body (fixed chips + ramp
  /// presets; its Reverse toggle was removed — Reverse is an
  /// instant action now) + Custom ramp widgets + Smooth Slow-Mo
  /// (AI) + the resulting-total readout from the ONE timeline
  /// model.
  List<Widget> buildChildren(BuildContext context) {
    final atSpeed = host.speed == 1 || host.proRamp != 'None'
        ? host.totalDurationSec
        : host.totalDurationSec / host.speed;
    return [
      ...panelBody(host, context, 'speed'),
      if (host.proRamp == 'Custom') ..._customRampWidgets(context),
      SectionTitle('Smooth Slow-Mo (AI)'),
      const Text(
        'RIFE AI creates a new frame between every two frames '
        '— 0.5x slow-mo perfectly smooth. Only up to ~10s of the '
        'on the selected clip; the model pack (rife_v46) is needed.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const SizedBox(height: 6),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: host.busy ? null : host.applySlowMoAi,
          icon: const Icon(Icons.slow_motion_video),
          label: const Text('Apply Smooth Slow-Mo (AI)'),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Timeline total: ${host.totalDurationSec.toStringAsFixed(1)}s'
        '${host.proRamp == 'None' && host.speed != 1 ? ' • speed ke baad ~${atSpeed.toStringAsFixed(1)}s' : ''}',
        style: const TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const Divider(height: 32),
    ];
  }

  List<Widget> curveChildren(BuildContext context) {
    if (host.proRamp != 'Custom') {
      return [
        SectionTitle('Speed curve'),
        ..._rampPresetRail(context),
        const Text(
          'For the curve editor, choose the ramp preset "Custom" — '
          'then the speed of the 3 points is set here.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => host.update(() {
              host.proRamp = 'Custom';
              host.panelTab = 'curve';
            }),
            icon: const Icon(Icons.show_chart),
            label: const Text('Turn on custom ramp'),
          ),
        ),
        const Divider(height: 32),
      ];
    }
    return [
      SectionTitle('Speed curve'),
      ..._rampPresetRail(context),
      ..._customRampWidgets(context),
    ];
  }

  /// Speed › Curve: the Custom-ramp point editors (the preset rail
  /// itself lives in Standard, where the legacy body puts it).
  /// The ramp preset rail — the SAME choices the Standard tab
  /// offers (Build 3: the Curve tab carries its own copy of the
  /// rail so a preset can be picked without leaving the tab; both
  /// rails write the one [_proRamp] state).
  List<Widget> _rampPresetRail(BuildContext context) {
    return [
      const Text('Ramp preset'),
      const SizedBox(height: 4),
      iconChoiceRail(host, [
        for (final e in const [
          ('None', Icons.block),
          ('slowMiddle', Icons.compress),
          ('slowStart', Icons.trending_down),
          ('slowEnd', Icons.trending_up),
          ('pulse', Icons.show_chart),
          ('Custom', Icons.tune),
        ])
          iconChoiceItem(host, 
            icon: e.$2,
            label: e.$1,
            selected: host.proRamp == e.$1,
            onTap: () => host.update(() => host.proRamp = e.$1),
          ),
      ]),
      const SizedBox(height: 4),
    ];
  }

  /// Edit › Speed extras for the Custom ramp (§6.10): three point
  /// speeds + the curve graph. Build 3 (Phase 3): the graph's
  /// points are DRAGGABLE — drag a plateau up/down to set its
  /// speed (the sliders stay, bound to the same values) — and
  /// every change drives the preview's playback rate to the
  /// point being edited, so the speed is felt live.
  List<Widget> _customRampWidgets(BuildContext context) {
    void setPoint(int third, double v) {
      host.update(() {
        if (third == 0) {
          host.rampStart = v;
        } else if (third == 1) {
          host.rampMid = v;
        } else {
          host.rampEnd = v;
        }
      });
      host.applyPreviewSpeed(v);
    }

    return [
      SectionTitle('Custom ramp — 3 points'),
      ProSlider(
        label: 'Start speed',
        value: host.rampStart,
        min: 0.25,
        max: 2,
        divisions: 35,
        onChanged: (v) => setPoint(0, v),
      ),
      ProSlider(
        label: 'Middle speed',
        value: host.rampMid,
        min: 0.25,
        max: 2,
        divisions: 35,
        onChanged: (v) => setPoint(1, v),
      ),
      ProSlider(
        label: 'End speed',
        value: host.rampEnd,
        min: 0.25,
        max: 2,
        divisions: 35,
        onChanged: (v) => setPoint(2, v),
      ),
      Container(
        height: 72,
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1B1B1B),
          borderRadius: BorderRadius.circular(8),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            void drag(Offset pos) {
              final third = SpeedRampMath.thirdForX(pos.dx, size.width);
              setPoint(third, SpeedRampMath.speedForY(pos.dy, size.height));
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) => drag(d.localPosition),
              onPanUpdate: (d) => drag(d.localPosition),
              child: CustomPaint(
                painter: RampCurvePainter(host.rampStart, host.rampMid, host.rampEnd),
                child: const SizedBox.expand(),
              ),
            );
          },
        ),
      ),
      const Text(
        'Curve: the first third is Start speed, the middle is Middle, the last '
        'third End speed par chalega. Graph par point ko ungli se '
        'the speed can also be set by dragging up/down — the preview '
        'plays at that speed.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const Divider(height: 32),
    ];
  }
  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
