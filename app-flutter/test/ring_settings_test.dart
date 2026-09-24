import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/models/ring_settings.dart';
import 'package:ha_phone_test/services/ring_settings_repository.dart';

import 'helpers/fake_sip.dart';

List<String> _labels(DateTime now) => muteOptions(now).map((o) => o.label).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('muteOptions', () {
    test('in the morning: 1 Std · bis 17:00 · bis morgen (8:00 next day)', () {
      final now = DateTime(2026, 9, 24, 10, 15);
      final o = muteOptions(now);
      expect(_labels(now), ['1 Std', 'bis 17:00', 'bis morgen']);
      expect(o[0].until, DateTime(2026, 9, 24, 11, 15));
      expect(o[1].until, DateTime(2026, 9, 24, 17));
      expect(o[2].until, DateTime(2026, 9, 25, 8));
    });

    test('shortly before 17:00 "bis 17:00" is still offered', () {
      final now = DateTime(2026, 9, 24, 16, 30);
      expect(_labels(now), ['1 Std', 'bis 17:00', 'bis morgen']);
    });

    test('from 17:00 on: "bis 8:00 morgen" replaces "bis 17:00", no duplicate', () {
      for (final now in [DateTime(2026, 9, 24, 17), DateTime(2026, 9, 24, 22, 40)]) {
        final o = muteOptions(now);
        expect(_labels(now), ['1 Std', 'bis 8:00 morgen']);
        expect(o[1].until, DateTime(2026, 9, 25, 8));
      }
    });

    test('before 8:00 the morning chip is today and says "bis 8:00"', () {
      final now = DateTime(2026, 9, 24, 2, 5);
      final o = muteOptions(now);
      expect(_labels(now), ['1 Std', 'bis 8:00', 'bis 17:00']);
      expect(o[1].until, DateTime(2026, 9, 24, 8));
    });

    test('end of month rolls over', () {
      final o = muteOptions(DateTime(2026, 9, 30, 20));
      expect(o.last.until, DateTime(2026, 10, 1, 8));
    });
  });

  group('selectedMuteOption', () {
    final t0 = DateTime(2026, 9, 24, 10, 15);

    test('"1 Std" stays selected minutes later via the chosen label', () {
      final until = t0.add(const Duration(hours: 1));
      final s = const RingSettings().mutedTill(until);
      final later = t0.add(const Duration(minutes: 20));
      expect(selectedMuteOption(muteOptions(later), s, later, chosenLabel: '1 Std', chosenUntil: until), 0);
    });

    test('without a remembered choice: match within ±1 min; fixed ends exactly', () {
      final s1 = const RingSettings().mutedTill(t0.add(const Duration(hours: 1, seconds: 30)));
      expect(selectedMuteOption(muteOptions(t0), s1, t0), 0);
      final s2 = const RingSettings().mutedTill(DateTime(2026, 9, 24, 17));
      expect(selectedMuteOption(muteOptions(t0), s2, t0), 1);
      final s3 = const RingSettings().mutedTill(DateTime(2026, 9, 24, 13));
      expect(selectedMuteOption(muteOptions(t0), s3, t0), -1);
    });

    test('nothing selected when ringing, switched off or the mute ran out', () {
      final until = t0.add(const Duration(hours: 1));
      expect(selectedMuteOption(muteOptions(t0), const RingSettings(), t0), -1);
      expect(selectedMuteOption(muteOptions(t0), const RingSettings().silent(), t0), -1);
      final after = until.add(const Duration(minutes: 1));
      expect(
          selectedMuteOption(muteOptions(after), const RingSettings().mutedTill(until), after,
              chosenLabel: '1 Std', chosenUntil: until),
          -1);
    });
  });

  group('texts', () {
    final now = DateTime(2026, 9, 24, 10);

    test('formatMuteEnd: today, tomorrow, later', () {
      expect(formatMuteEnd(DateTime(2026, 9, 24, 17), now), '17:00');
      expect(formatMuteEnd(DateTime(2026, 9, 25, 8), now), 'morgen 8:00');
      expect(formatMuteEnd(DateTime(2026, 9, 28, 8, 5), now), 'Mo 8:05');
    });

    test('ringStateText for the Start pill', () {
      expect(ringStateText(const RingSettings(), now), 'Klingelt hier');
      expect(ringStateText(RingSettings(mutedUntil: DateTime(2026, 9, 24, 17)), now), 'Stumm bis 17:00');
      expect(ringStateText(const RingSettings(enabled: false), now), 'Stumm auf diesem Handy');
    });

    test('an expired mute rings again', () {
      final s = RingSettings(mutedUntil: now.subtract(const Duration(minutes: 1)));
      expect(s.ringsAt(now), isTrue);
      expect(ringStateText(s, now), 'Klingelt hier');
    });

    test('ringDetailText mentions the door override', () {
      expect(ringDetailText(const RingSettings(enabled: false), now), contains('Türklingel klingelt trotzdem'));
      expect(ringDetailText(const RingSettings(enabled: false, allowDoor: false), now),
          isNot(contains('Türklingel')));
      expect(ringDetailText(RingSettings(mutedUntil: DateTime(2026, 9, 24, 17)), now), startsWith('stumm bis 17:00'));
    });
  });

  group('RingSettings', () {
    test('map round trip and defaults', () {
      final s = RingSettings(enabled: false, mutedUntil: DateTime.fromMillisecondsSinceEpoch(1790000000000), allowDoor: false);
      expect(RingSettings.fromMap(s.toMap()), s);
      expect(RingSettings.fromMap(const {}), const RingSettings());
      expect(RingSettings.fromMap(const {'mutedUntil': 0}).mutedUntil, isNull);
    });

    test('switching keeps the door option and clears the mute', () {
      final muted = RingSettings(mutedUntil: DateTime(2026, 9, 24, 17), allowDoor: false);
      expect(muted.ringing(), const RingSettings(allowDoor: false));
      expect(muted.silent(), const RingSettings(enabled: false, allowDoor: false));
      expect(const RingSettings(enabled: false).mutedTill(DateTime(2026, 9, 24, 17)).enabled, isTrue);
    });
  });

  group('RingSettingsRepository', () {
    late FakeSip sip;
    tearDown(() => sip.uninstall());

    test('loads and stores over the channel', () async {
      Map<Object?, Object?> stored = {'enabled': true, 'mutedUntil': 0, 'allowDoor': true};
      sip = FakeSip({
        'getRingPolicy': (_) => stored,
        'setRingPolicy': (args) => stored = Map<Object?, Object?>.from(args as Map),
      })
        ..install();
      final repo = RingSettingsRepository(clock: () => DateTime(2026, 9, 24, 10));
      await repo.load();
      expect(repo.hasLoaded, isTrue);
      expect(repo.ringsNow, isTrue);

      await repo.update(repo.settings.silent());
      expect(sip.callsTo('setRingPolicy').single.arguments, {'enabled': false, 'mutedUntil': 0, 'allowDoor': true});
      expect(repo.ringsNow, isFalse);
      repo.dispose();
    });

    test('reverts when the native side fails', () async {
      sip = FakeSip({
        'setRingPolicy': (_) => throw PlatformException(code: 'X'),
      })
        ..install();
      final repo = RingSettingsRepository();
      await expectLater(repo.update(const RingSettings(enabled: false)), throwsA(isA<PlatformException>()));
      expect(repo.settings, const RingSettings());
      repo.dispose();
    });
  });
}
