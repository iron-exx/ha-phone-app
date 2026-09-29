import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/preview_camera.dart';
import '../services/preview_cameras_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// How often a visible camera picture is fetched again.
const kCameraRefresh = Duration(seconds: 3);

/// Row of the extra preview cameras chosen in Ich → Weitere Kameras. Invisible
/// while none is chosen. Each picture refreshes every few seconds while it is
/// on screen and the app is in the foreground; a tap opens it large.
class CameraStrip extends StatelessWidget {
  const CameraStrip({super.key, this.repository, this.height = 78, this.padding = EdgeInsets.zero});

  final PreviewCamerasRepository? repository;
  final double height;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final repo = repository ?? PreviewCamerasRepository.instance;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final cams = repo.shown;
        if (cams.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: padding,
          child: SizedBox(
            key: const Key('camera-strip'),
            height: height,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cams.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) => _Thumb(camera: cams[i], repo: repo, height: height),
            ),
          ),
        );
      },
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.camera, required this.repo, required this.height});

  final PreviewCamera camera;
  final PreviewCamerasRepository repo;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
    return Semantics(
      button: true,
      label: 'Kamera ${camera.name}, groß anzeigen',
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('camera-thumb-${camera.entityId}'),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => CameraViewerScreen(camera: camera, repository: repo),
        )),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: height * 16 / 9,
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                LiveCameraPicture(camera: camera, repository: repo),
                Positioned(
                  left: 6,
                  bottom: 6,
                  right: 6,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: c.ground.withOpacity(0.72), borderRadius: BorderRadius.circular(9)),
                      child: Text(camera.name,
                          overflow: TextOverflow.ellipsis,
                          style: NwType.meta.copyWith(color: c.text, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A camera picture that fetches itself again every [interval] while shown and
/// the app is resumed; keeps the last good picture on a failed refresh.
class LiveCameraPicture extends StatefulWidget {
  const LiveCameraPicture({
    super.key,
    required this.camera,
    this.repository,
    this.interval = kCameraRefresh,
    this.fit = BoxFit.cover,
  });

  final PreviewCamera camera;
  final PreviewCamerasRepository? repository;
  final Duration interval;
  final BoxFit fit;

  @override
  State<LiveCameraPicture> createState() => _LiveCameraPictureState();
}

class _LiveCameraPictureState extends State<LiveCameraPicture> with WidgetsBindingObserver {
  Uint8List? _bytes;
  bool _failed = false;
  bool _busy = false;
  bool _covered = false;
  Timer? _timer;

  PreviewCamerasRepository get _repo => widget.repository ?? PreviewCamerasRepository.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bytes = _repo.lastPicture(widget.camera.entityId);
    _start();
  }

  @override
  void didUpdateWidget(LiveCameraPicture old) {
    super.didUpdateWidget(old);
    if (old.camera.entityId != widget.camera.entityId) {
      _bytes = _repo.lastPicture(widget.camera.entityId);
      _start();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _start() {
    _timer?.cancel();
    unawaited(_fetch());
    _timer = Timer.periodic(widget.interval, (_) => _fetch());
  }

  Future<void> _fetch() async {
    // Covered by another page (e.g. the large view): that page fetches, not this one.
    if (_busy || !mounted || _covered) return;
    _busy = true;
    try {
      final bytes = await _repo.snapshot(widget.camera);
      if (!mounted) return;
      setState(() {
        if (bytes != null) _bytes = bytes;
        _failed = bytes == null && _bytes == null;
      });
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Also makes this rebuild when a page is pushed over it or popped again.
    _covered = !(ModalRoute.of(context)?.isCurrent ?? true);
    final c = context.nw;
    final bytes = _bytes;
    if (bytes != null) {
      return Image.memory(bytes, fit: widget.fit, gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _placeholder(c, Icons.videocam_off_outlined));
    }
    return _placeholder(c, _failed ? Icons.videocam_off_outlined : Icons.videocam_outlined);
  }

  Widget _placeholder(NwColors c, IconData icon) => ColoredBox(
        color: c.raised,
        child: Center(child: Icon(icon, color: c.faint, size: 22)),
      );
}

/// One camera large, refreshing faster than the thumbnails.
class CameraViewerScreen extends StatelessWidget {
  const CameraViewerScreen({super.key, required this.camera, this.repository});

  final PreviewCamera camera;
  final PreviewCamerasRepository? repository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(camera.name),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 4,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: LiveCameraPicture(
              key: const Key('camera-viewer-picture'),
              camera: camera,
              repository: repository,
              interval: const Duration(seconds: 2),
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
