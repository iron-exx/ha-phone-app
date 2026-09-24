import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/pbx_audio.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';

/// Inline player under an expanded voicemail or recording row: play/pause,
/// seek bar, position/duration, "Zurückrufen" and "Löschen". The audio is
/// only loaded on the first play tap.
class AudioPlayerPanel extends StatefulWidget {
  const AudioPlayerPanel({
    super.key,
    required this.source,
    required this.audioFactory,
    required this.fallbackDuration,
    required this.onCallBack,
    required this.onDelete,
    this.onPlay,
    this.loadErrorText = 'Aufnahme konnte nicht geladen werden.',
  });

  /// Resolves the file on the PBX (needs the device auth, so async).
  final Future<PbxAudioSource> Function() source;
  final PbxAudioFactory audioFactory;

  /// Shown until the player knows the real length.
  final Duration fallbackDuration;
  final VoidCallback? onCallBack;
  final VoidCallback onDelete;

  /// Called on every play tap (voicemail: mark as heard).
  final VoidCallback? onPlay;
  final String loadErrorText;

  @override
  State<AudioPlayerPanel> createState() => _AudioPlayerPanelState();
}

class _AudioPlayerPanelState extends State<AudioPlayerPanel> {
  PbxAudio? _audio;
  final List<StreamSubscription<Object?>> _subs = [];
  bool _loading = false;
  bool _playing = false;
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

  Future<void> _seek(double ms) async {
    final audio = await _ensureLoaded();
    await audio?.seek(Duration(milliseconds: ms.round()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalMs = _total.inMilliseconds.toDouble();
    final posMs = _position.inMilliseconds.clamp(0, _total.inMilliseconds).toDouble();
    final timeStyle = tabular(theme.textTheme.bodySmall)?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 16, 8),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: _playing ? 'Pause' : 'Abspielen',
                iconSize: 36,
                onPressed: _loading ? null : _togglePlay,
                icon: _loading
                    ? const SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 3))
                    : Icon(_playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
                        color: theme.colorScheme.primary),
              ),
              Expanded(
                child: Slider(
                  value: totalMs <= 0 ? 0 : posMs,
                  max: totalMs <= 0 ? 1 : totalMs,
                  onChanged: totalMs <= 0 ? null : _seek,
                ),
              ),
              Text('${formatCallDuration(_position)} / ${formatCallDuration(_total)}', style: timeStyle),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.delete_outline, color: AppColors.hangup),
                label: const Text('Löschen', style: TextStyle(color: AppColors.hangup)),
                onPressed: widget.onDelete,
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.answer),
                icon: const Icon(Icons.call),
                label: const Text('Zurückrufen'),
                onPressed: widget.onCallBack,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
