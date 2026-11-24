/// FilterPanel of the Photo Editor (Master Plan Phase 7 split).
///
/// Was a method of `_PhotoEditorScreenState` in
/// photo_editor_screen.dart; now a real widget in its own file.
/// All editor state is reached through [PhotoEditorController] —
/// behaviour unchanged.
library;


import 'package:flutter/material.dart';

import '../photo_editor_controller.dart';
import '../photo_models.dart';
import '../../services/photo_pipeline.dart';
import '../widgets/panel_helpers.dart';
import '../widgets/photo_widgets.dart';

class FilterPanel extends StatelessWidget {
  final PhotoEditorController host;
  const FilterPanel(this.host, {super.key});

  @override
  Widget build(BuildContext context) {
    final catKeys = kPhotoFilterCategories[host.filterCategory]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category chips.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final cat in kPhotoFilterCategories.keys)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(cat),
                    selected: host.filterCategory == cat,
                    onSelected: (_) => host.update(() => host.filterCategory = cat),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Thumbnail strip: every thumbnail is the ACTUAL current
        // photo with that look applied (ORIGINAL first = Normal).
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final key in catKeys)
                if (key.startsWith('f:'))
                  host.lookThumb(
                    label:
                        kPhotoFilterLabels[PhotoFilter.values.firstWhere(
                          (f) => f.name == key.substring(2),
                        )]!,
                    selected:
                        host.selectedLut.isEmpty &&
                        host.filter.name == key.substring(2),
                    thumb:
                        host.filterThumbs[PhotoFilter.values.firstWhere(
                          (f) => f.name == key.substring(2),
                        )],
                    onTap: () {
                      host.update(() {
                        host.filter = PhotoFilter.values.firstWhere(
                          (f) => f.name == key.substring(2),
                        );
                        host.selectedLut = '';
                      });
                      host.schedulePixelPreview();
                    },
                  )
                else
                  host.lookThumb(
                    label: key.substring(4),
                    selected: host.selectedLut == key.substring(4),
                    thumb: host.lutThumbs[key.substring(4)],
                    onTap: () {
                      host.update(() => host.selectedLut = key.substring(4));
                      host.schedulePixelPreview();
                    },
                  ),
            ],
          ),
        ),
        PhotoSliderRow(
          label: 'Intensity',
          value: host.filterIntensity * 100,
          min: 0,
          max: 100,
          onChanged: (v) {
            host.update(() => host.filterIntensity = v / 100);
            host.schedulePixelPreview();
          },
        ),
      ],
    );
  }
}
