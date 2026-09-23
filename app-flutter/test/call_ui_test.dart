import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/services/sip_channel.dart';
import 'package:ha_phone_test/utils/audio_route_ui.dart';
import 'package:ha_phone_test/utils/call_status.dart';

AudioRoutes _routes(String current, List<String> types) => AudioRoutes(
      currentId: current,
      routes: [for (final t in types) AudioRoute(id: t, name: t, type: t)],
    );

CurrentCall _call({String state = 'connecting', DateTime? connectedAt}) => CurrentCall(
      number: '16',
      name: 'türklingel',
      direction: 'incoming',
      video: false,
      doorCode: '*1',
      state: state,
      connectedAt: connectedAt,
      secure: true,
    );

void main() {
  group('audio routes', () {
    test('toggles earpiece <-> speaker', () {
      expect(toggleTarget(_routes('earpiece', ['earpiece', 'speaker']))?.type, 'speaker');
      expect(toggleTarget(_routes('speaker', ['earpiece', 'speaker']))?.type, 'earpiece');
      expect(toggleTarget(_routes('earpiece', ['earpiece'])), isNull);
    });
    test('needs a picker only with bluetooth or headset', () {
      expect(needsRoutePicker(_routes('earpiece', ['earpiece', 'speaker'])), isFalse);
      expect(needsRoutePicker(_routes('bluetooth', ['earpiece', 'speaker', 'bluetooth'])), isTrue);
      expect(needsRoutePicker(_routes('headset', ['headset', 'speaker'])), isTrue);
    });
    test('labels and icons reflect the route', () {
      expect(audioRouteLabel('earpiece'), 'Hörer');
      expect(audioRouteLabel('speaker'), 'Lautsprecher');
      expect(audioRouteLabel('bluetooth'), 'Bluetooth');
      expect(audioRouteLabel('headset'), 'Headset');
      expect(audioRouteLabel(null), 'Lautsprecher');
      expect(audioRouteIcon('bluetooth'), Icons.bluetooth_audio);
    });
    test('parses the native route map', () {
      final r = AudioRoutes.fromMap({
        'current': 'b1',
        'routes': [
          {'id': 'e', 'name': 'Hörer', 'type': 'earpiece'},
          {'id': 'b1', 'name': 'Jabra', 'type': 'bluetooth'},
        ],
      });
      expect(r.current?.name, 'Jabra');
    });
  });

  group('callStatusText', () {
    final now = DateTime(2026, 9, 23, 14, 5, 0);
    test('shows connecting/ringing before answer', () {
      expect(callStatusText(null, now), 'Verbinde…');
      expect(callStatusText(_call(), now), 'Verbinde…');
      expect(callStatusText(_call(state: 'ringing'), now), 'Klingelt…');
    });
    test('shows the running duration once connected', () {
      final c = _call(state: 'confirmed', connectedAt: now.subtract(const Duration(minutes: 2, seconds: 37)));
      expect(callStatusText(c, now), '02:37');
      expect(callStatusText(c, now, onHold: true), '02:37 · gehalten');
    });
    test('door detection uses the door code', () {
      expect(_call().isDoor, isTrue);
    });
  });
}
