import 'dart:async';
import 'dart:io' show File, Directory;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'api_client.dart';

/// A WAV file on the PBX (voicemail message or call recording): streamed
/// with the device headers, or downloaded when streaming fails.
class PbxAudioSource {
  const PbxAudioSource({
    required this.uri,
    required this.headers,
    required this.download,
    required this.tempFileName,
  });

  final Uri uri;
  final Map<String, String> headers;
  final Future<List<int>> Function() download;

  /// File name for the download fallback in the temp folder.
  final String tempFileName;
}

/// Player for one PBX audio file. An interface so widget tests can run
/// without the just_audio platform plugin.
abstract class PbxAudio {
  Stream<Duration> get position;
  Stream<Duration?> get duration;

  /// false again once playback has finished.
  Stream<bool> get playing;

  Future<void> load(PbxAudioSource source);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);

  /// Playback speed (1.0, 1.5, 2.0).
  Future<void> setSpeed(double speed);
  Future<void> dispose();
}

typedef PbxAudioFactory = PbxAudio Function();

PbxAudio defaultPbxAudio() => JustAudioPbx();

/// just_audio implementation: streams the WAV with the device headers
/// (sent directly by ExoPlayer, no local proxy); if that fails, downloads it
/// to a temp file and plays from there.
class JustAudioPbx implements PbxAudio {
  JustAudioPbx() {
    _completion = _player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) unawaited(_rewind());
    });
  }

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
  Future<void> load(PbxAudioSource source) async {
    try {
      await _player.setAudioSource(AudioSource.uri(source.uri, headers: source.headers));
    } on ApiException {
      rethrow;
    } catch (e) {
      debugPrint('audio stream failed, downloading instead: $e');
      final bytes = await source.download();
      final file = File('${Directory.systemTemp.path}/${source.tempFileName}');
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
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> dispose() async {
    await _completion?.cancel();
    await _player.dispose();
    final file = _tempFile;
    if (file != null && await file.exists()) await file.delete();
  }
}
