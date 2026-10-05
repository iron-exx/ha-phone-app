import 'dart:async';

import 'package:flutter/material.dart';

import '../services/preview_cameras_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/camera_strip.dart';
import '../widgets/nw_widgets.dart';

/// Ich → Weitere Kameras: which of the cameras the admin shared this phone shows
/// on the start page, in door calls and on the ringing screen.
class PreviewCamerasScreen extends StatefulWidget {
  const PreviewCamerasScreen({super.key, this.repository});

  final PreviewCamerasRepository? repository;

  @override
  State<PreviewCamerasScreen> createState() => _PreviewCamerasScreenState();
}

class _PreviewCamerasScreenState extends State<PreviewCamerasScreen> {
  PreviewCamerasRepository get _repo => widget.repository ?? PreviewCamerasRepository.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_repo.refresh());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
    return Scaffold(
      appBar: AppBar(title: const Text('Weitere Kameras')),
      body: ListenableBuilder(
        listenable: _repo,
        builder: (context, _) {
          if (!_repo.hasLoaded) return const Center(child: CircularProgressIndicator());
          final cams = _repo.available;
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Text(
                  'Gewählte Kameras erscheinen als kleine Bilder auf der Start-Seite, beim Klingeln und im '
                  'Gespräch mit der Tür. Ein Tipp aufs Bild zeigt es groß.',
                  style: NwType.meta.copyWith(color: c.muted),
                ),
              ),
              if (_repo.isUnsupported)
                _hint(c, 'Die Anlage kennt diese Funktion noch nicht. Bitte HA-Phone auf 0.7.141 oder neuer aktualisieren.')
              else if (cams.isEmpty)
                _hint(c, 'Der Admin hat noch keine Kamera freigegeben (HA-Phone → Türklingel → Kameras für die App).')
              else ...[
                const SectionHeader('Freigegeben'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: NwCard(
                    padding: EdgeInsets.zero,
                    radius: NwRadius.cardMedium,
                    clip: true,
                    child: Column(
                      children: [
                        for (final (i, cam) in cams.indexed) ...[
                          if (i > 0) Divider(height: 1, indent: 16, color: c.stroke),
                          SwitchListTile(
                            key: ValueKey('camera-choice-${cam.entityId}'),
                            value: _repo.isSelected(cam.entityId),
                            onChanged: (_) => _repo.toggle(cam.entityId),
                            title: Text(cam.name),
                            secondary: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 64,
                                height: 36,
                                child: LiveCameraPicture(camera: cam, repository: _repo, interval: const Duration(seconds: 10)),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _hint(NwColors c, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Text(text, key: const Key('cameras-hint'), style: NwType.meta.copyWith(color: c.text)),
      );
}
