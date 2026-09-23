import 'dart:async';
import 'dart:io' show File, Directory;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/voicemail.dart';
import 'api_client.dart';
import 'voicemail_repository.dart';

/// Player for one voicemail message. An interface so widget tests can run
/// without the just_audio platform plugin.
abstract class VoicemailAudio {
  Stream<Duration> get position;
  Stream<Duration?> get duration;

  /// false again once playback has finished.
  Stream<bool> get playing;

  Future<void> load(VoicemailMessage message);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> dispose();
}

typedef VoicemailAudioFactory = VoicemailAudio Function(VoicemailRepository repository);

VoicemailAudio defaultVoicemailAudio(VoicemailRepository repository) => JustAudioVoicemail(repository);

/// just_audio implementation: streams the WAV with the device headers
/// (sent directly by ExoPlayer, no local proxy); if that fails, downloads it
/// to a temp file and plays from there.
class JustAudioVoicemail implements VoicemailAudio {
  JustAudioVoicemail(this._repository) {
    _completion = _player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) unawaited(_rewind());
    });
  }

  final VoicemailRepository _repository;
  final AudioPlayer _player = AudioPlayer(useProxyForRequestHeaders: false);
  StreamSubscription<ProcessingState>? _completion;
  File? _tempFile;

  @override
  Stream<Duration> get position => _player.positionStream;

  @override
  Stream<Duration?> get duration => _player.durationStream;

  @override
  Stream<bool> get playing =>
      _player.playerStateStream.map((s) => s.playing && s.processingState != ProcessingState.completed);

  @override
  Future<void> load(VoicemailMessage message) async {
    final auth = await _repository.loadAuth();
    final api = _repository.api;
    try {
      await _player.setAudioSource(AudioSource.uri(
        api.voicemailAudioUri(auth, message),
        headers: ApiClient.authHeaders(auth),
      ));
    } on ApiException {
      rethrow;
    } catch (e) {
      debugPrint('voicemail stream failed, downloading instead: $e');
      final bytes = await api.downloadVoicemail(auth, message);
      final name = message.path?.name ?? 'message';
      final file = File('${Directory.systemTemp.path}/voicemail_${name}_${message.heardKey.hashCode}.wav');
      await file.writeAsBytes(bytes, flush: true);
      _tempFile = file;
      await _player.setFilePath(file.path);
    }
  }

  Future<void> _rewind() async {
    await _player.pause();
    await _player.seek(Duration.zero);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> dispose() async {
    await _completion?.cancel();
    await _player.dispose();
    final file = _tempFile;
    if (file != null && await file.exists()) await file.delete();
  }
}
