import 'dart:async';

import 'package:flutter/material.dart';

import '../models/voicemail.dart';
import '../services/api_client.dart';
import '../services/voicemail_audio.dart';
import '../services/voicemail_repository.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';

/// Inline player under an expanded voicemail row: play/pause, seek bar,
/// position/duration, "Zurückrufen" and "Löschen". The audio is only loaded
/// on the first play tap.
class VoicemailPlayerPanel extends StatefulWidget {
  const VoicemailPlayerPanel({
    super.key,
    required this.message,
    required this.repository,
    required this.audioFactory,
    required this.onCallBack,
    required this.onDelete,
  });

  final VoicemailMessage message;
  final VoicemailRepository repository;
  final VoicemailAudioFactory audioFactory;
  final VoidCallback? onCallBack;
  final VoidCallback onDelete;

  @override
  State<VoicemailPlayerPanel> createState() => _VoicemailPlayerPanelState();
}

class _VoicemailPlayerPanelState extends State<VoicemailPlayerPanel> {
  VoicemailAudio? _audio;
  final List<StreamSubscription<Object?>> _subs = [];
  bool _loading = false;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration? _duration;

  Duration get _total {
    final d = _duration;
    return d != null && d > Duration.zero ? d : widget.message.duration;
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

  Future<VoicemailAudio?> _ensureLoaded() async {
    final existing = _audio;
    if (existing != null) return existing;
    setState(() => _loading = true);
    final audio = widget.audioFactory(widget.repository);
    try {
      await audio.load(widget.message);
    } catch (e) {
      unawaited(audio.dispose());
      if (mounted) {
        setState(() => _loading = false);
        final text = e is ApiException ? e.message : 'Nachricht konnte nicht geladen werden.';
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
    unawaited(widget.repository.markHeard(widget.message));
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
