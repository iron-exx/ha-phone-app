import 'dart:async';

import 'package:ha_phone_test/services/pbx_audio.dart';

/// PbxAudio without the just_audio plugin: records what was loaded/played.
class FakeAudio implements PbxAudio {
  final _playing = StreamController<bool>.broadcast();

  /// URLs of the loaded sources.
  final loaded = <Uri>[];
  var plays = 0;

  @override
  Stream<Duration> get position => const Stream.empty();
  @override
  Stream<Duration?> get duration => const Stream.empty();
  @override
  Stream<bool> get playing => _playing.stream;

  @override
  Future<void> load(PbxAudioSource source) async => loaded.add(source.uri);
  @override
  Future<void> play() async {
    plays++;
    _playing.add(true);
  }

  @override
  Future<void> pause() async => _playing.add(false);
  @override
  Future<void> seek(Duration position) async {}

  /// Last speed set (1.0 until changed).
  var speed = 1.0;
  @override
  Future<void> setSpeed(double speed) async => this.speed = speed;
  @override
  Future<void> dispose() => _playing.close();
}
