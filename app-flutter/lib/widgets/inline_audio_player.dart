import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/pbx_audio.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'nw_widgets.dart';

/// Playback speeds the speed chip cycles through.
const kPlaybackSpeeds = [1.0, 1.5, 2.0];

/// "1×", "1,5×", "2×".
String formatSpeed(double speed) =>
    '${speed == speed.roundToDouble() ? speed.toInt() : speed.toString().replaceAll('.', ',')}×';

/// Next speed after [current] (wraps around).
double nextSpeed(double current) {
  final i = kPlaybackSpeeds.indexOf(current);
  return kPlaybackSpeeds[(i + 1) % kPlaybackSpeeds.length];
}

/// Compact player inside a Verlauf row (voicemail, recording): play/pause,
/// waveform with progress (tap/drag to seek), time and a 1×/1,5×/2× chip.
/// The audio is only loaded on the first play tap.
class InlineAudioPlayer extends StatefulWidget {
  const InlineAudioPlayer({
    super.key,
    required this.source,
    required this.audioFactory,
    required this.fallbackDuration,
    required this.seed,
    this.onPlay,
    this.loadErrorText = 'Aufnahme konnte nicht geladen werden.',
  });

  final Future<PbxAudioSource> Function() source;
  final PbxAudioFactory audioFactory;

  /// Shown until the player knows the real length.
  final Duration fallbackDuration;

  /// Shapes the (decorative) waveform so each message looks different.
  final int seed;

  /// Called on every play tap (voicemail: mark as heard).
  final VoidCallback? onPlay;
  final String loadErrorText;

  @override
  State<InlineAudioPlayer> createState() => _InlineAudioPlayerState();
}

class _InlineAudioPlayerState extends State<InlineAudioPlayer> {
  PbxAudio? _audio;
  final List<StreamSubscription<Object?>> _subs = [];
  bool _loading = false;
  bool _playing = false;
  double _speed = 1.0;
  Duration _position = Duration.zero;
  Duration? _duration;

  Duration get _total {
    final d = _duration;
    return d != null && d > Duration.zero ? d : widget.fallbackDuration;
  }

  @override
  void dispose() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    final audio = _audio;
    if (audio != null) unawaited(audio.dispose());
    super.dispose();
  }

  Future<PbxAudio?> _ensureLoaded() async {
    final existing = _audio;
    if (existing != null) return existing;
    setState(() => _loading = true);
    final audio = widget.audioFactory();
    try {
      await audio.load(await widget.source());
      if (_speed != 1.0) await audio.setSpeed(_speed);
    } catch (e) {
      unawaited(audio.dispose());
      if (mounted) {
        setState(() => _loading = false);
        final text = e is ApiException ? e.message : widget.loadErrorText;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
      }
      return null;
    }
    if (!mounted) {
      unawaited(audio.dispose());
      return null;
    }
    _subs
      ..add(audio.playing.listen((p) => mounted ? setState(() => _playing = p) : null))
      ..add(audio.position.listen((p) => mounted ? setState(() => _position = p) : null))
      ..add(audio.duration.listen((d) => mounted ? setState(() => _duration = d) : null));
    setState(() {
      _audio = audio;
      _loading = false;
    });
    return audio;
  }

  Future<void> _togglePlay() async {
    final audio = await _ensureLoaded();
    if (audio == null) return;
    if (_playing) {
      await audio.pause();
      return;
    }
    // play() completes only when playback stops, so don't wait for it.
    unawaited(audio.play());
    widget.onPlay?.call();
  }

  Future<void> _seekFraction(double f) async {
    final audio = await _ensureLoaded();
    final ms = (_total.inMilliseconds * f.clamp(0.0, 1.0)).round();
    await audio?.seek(Duration(milliseconds: ms));
  }

  Future<void> _cycleSpeed() async {
    final next = nextSpeed(_speed);
    setState(() => _speed = next);
    await _audio?.setSpeed(next);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
    final totalMs = _total.inMilliseconds;
    final progress = totalMs <= 0 ? 0.0 : (_position.inMilliseconds / totalMs).clamp(0.0, 1.0);
    final shown = _playing || _position > Duration.zero ? _position : _total;
    final play = Tooltip(
      message: _playing ? 'Pause' : 'Abspielen',
      child: Semantics(
        button: true,
        label: _playing ? 'Pause' : 'Abspielen',
        enabled: !_loading,
        onTap: _loading ? null : _togglePlay,
        excludeSemantics: true,
        child: InkResponse(
          onTap: _loading ? null : _togglePlay,
          radius: 24,
          child: SizedBox(
            width: kMinTap,
            height: kMinTap,
            child: Center(
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: c.blue, shape: BoxShape.circle),
                child: _loading
                    ? Padding(
                        padding: const EdgeInsets.all(8),
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: c.blueInk),
                      )
                    : Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 20, color: c.blueInk),
              ),
            ),
          ),
        ),
      ),
    );
    final wave = Semantics(
      slider: true,
      label: 'Position',
      value: '${formatCallDuration(_position)} von ${formatCallDuration(_total)}',
      child: LayoutBuilder(
        builder: (context, box) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _seekFraction(d.localPosition.dx / box.maxWidth),
          onHorizontalDragUpdate: (d) => _seekFraction(d.localPosition.dx / box.maxWidth),
          child: SizedBox(
            height: 32,
            child: CustomPaint(
              painter: _WaveformPainter(seed: widget.seed, progress: progress, played: c.blue, rest: c.stroke),
            ),
          ),
        ),
      ),
    );
    final time = Text(
      formatCallDuration(shown),
      key: const ValueKey('player-time'),
      style: NwType.meta.copyWith(color: c.faint, fontSize: 11.5),
    );
    final speed = NwChip(
      key: const ValueKey('player-speed'),
      label: formatSpeed(_speed),
      semanticLabel: 'Geschwindigkeit ${formatSpeed(_speed)}',
      onTap: _cycleSpeed,
    );
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(4, 2, 8, 2),
      decoration: BoxDecoration(color: c.raised, borderRadius: BorderRadius.circular(14)),
      child: LayoutBuilder(builder: (context, box) {
        // Narrow row or large system font: time and speed go below the waveform.
        final stacked = box.maxWidth < 170 + 60 * MediaQuery.textScalerOf(context).scale(1);
        if (!stacked) {
          return Row(
              children: [play, Expanded(child: wave), const SizedBox(width: 8), time, const SizedBox(width: 4), speed]);
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [play, Expanded(child: wave)]),
            // Wraps when even time + speed don't fit side by side (200 % text, 320 dp).
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [time, speed],
              ),
            ),
          ],
        );
      }),
    );
  }
}

/// Decorative bars (no real waveform data from the PBX), deterministic per [seed].
class _WaveformPainter extends CustomPainter {
  _WaveformPainter({required this.seed, required this.progress, required this.played, required this.rest});

  final int seed;
  final double progress;
  final Color played;
  final Color rest;

  @override
  void paint(Canvas canvas, Size size) {
    const barWidth = 3.0;
    const gap = 3.0;
    final count = (size.width / (barWidth + gap)).floor();
    if (count <= 0) return;
    var x = seed.abs() % 9973 + 17;
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < count; i++) {
      x = (x * 1103515245 + 12345) & 0x7fffffff;
      final h = 4 + (x % 17).toDouble();
      final left = i * (barWidth + gap);
      paint.color = (i + 0.5) / count <= progress ? played : rest;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(left + barWidth / 2, size.height / 2), width: barWidth, height: h),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress || old.seed != seed || old.played != played || old.rest != rest;
}
