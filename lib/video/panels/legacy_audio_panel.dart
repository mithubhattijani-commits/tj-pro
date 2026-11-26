/// LegacyAudioPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../services/fx_pack.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// Legacy 'audio' panel.
class LegacyAudioPanel extends StatelessWidget {
  final VideoEditorController host;
  const LegacyAudioPanel(this.host, {super.key});

  List<Widget> buildChildren(BuildContext context) {
        return [
          SectionTitle('Audio — music + waveform'),
          const SizedBox(height: 8),
// Music
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: host.pickMusic,
                  icon: const Icon(Icons.music_note),
                  label: Text(
                    host.musicPath == null
                        ? 'Add music'
                        : p.basename(host.musicPath!),
                  ),
                ),
              ),
              if (host.musicPath != null)
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => host.update(() => host.musicPath = null),
                ),
            ],
          ),
          // CapCut-style music track gain: silent BGM mixing made common by
          // CapCut/VN's 2026 audio panels; applied to the music audio only.
          if (host.musicPath != null)
            ProSlider(
              label: 'Music volume',
              value: host.musicVolume,
              min: 0,
              max: 1.5,
              divisions: 30,
              onChanged: (double v) {
                host.update(() {
                  host.musicVolume = v;
                });
              },
            ),
          const SizedBox(height: 12),
// Waveform.
              SectionTitle('Waveform'),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (host.waveformBusy || host.busy || host.clips.isEmpty)
                          ? null
                          : host.showWaveform,
                      icon: const Icon(Icons.show_chart),
                      label: Text(
                        host.waveformBusy ? 'Generating…' : 'Show waveform',
                      ),
                    ),
                  ),
                ],
              ),
              if (host.waveformPath != null) ...[
                const SizedBox(height: 8),
                Image.file(
                  File(host.waveformPath!),
                  height: 60,
                  width: double.infinity,
                  fit: BoxFit.contain,
                ),
              ],
              const SizedBox(height: 8),
          const Divider(height: 32),
          SectionTitle('Voice changer'),
          const SizedBox(height: 4),
          const Text('Voice effect'),
          const SizedBox(height: 4),
          iconChoiceRail(host, [
            for (final e in const [
              (VoiceFx.none, 'None', Icons.voice_over_off),
              (VoiceFx.chipmunk, 'Chipmunk', Icons.pets),
              (VoiceFx.deepVoice, 'Deep voice', Icons.graphic_eq),
              (VoiceFx.robot, 'Robot', Icons.smart_toy),
              (VoiceFx.echo, 'Echo', Icons.waves),
            ])
              iconChoiceItem(host, 
                icon: e.$3,
                label: e.$2,
                selected: host.fxVoice == e.$1,
                onTap: () => host.update(() => host.fxVoice = e.$1),
              ),
          ]),
          ProSlider(
            label: 'Fade in (s)',
            value: host.fxFadeIn,
            min: 0,
            max: 3,
            divisions: 30,
            onChanged: (double v) {
              host.update(() {
                host.fxFadeIn = v;
              });
            },
          ),
          ProSlider(
            label: 'Fade out (s)',
            value: host.fxFadeOut,
            min: 0,
            max: 3,
            divisions: 30,
            onChanged: (double v) {
              host.update(() {
                host.fxFadeOut = v;
              });
            },
          ),
          SwitchListTile(
            title: const Text('Mute original audio'),
            subtitle: const Text(
              'Turn off the clip\'s own sound (ignored if music is applied).',
            ),
            value: host.muteOriginal,
            onChanged: (bool v) {
              host.update(() {
                host.muteOriginal = v;
              });
            },
          ),
          const Divider(height: 32),
          SectionTitle('Cleanup'),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Silence remover'),
            value: host.fxSilenceRemove,
            onChanged: (bool v) {
              host.update(() {
                host.fxSilenceRemove = v;
              });
            },
          ),
          const SizedBox(height: 8),
        ];
  }

  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
