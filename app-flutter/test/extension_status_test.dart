import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/models/extension_status.dart';
import 'package:ha_phone_test/models/presence.dart';
import 'package:ha_phone_test/theme/app_colors.dart';

void main() {
  group('PresenceSnapshot.fromJson', () {
    final snapshot = PresenceSnapshot.fromJson({
      'self': {'number': '12', 'presence': 'available', 'line': 'idle'},
      'extensions': [
        {'number': '11', 'presence': 'lunch', 'line': 'busy'},
        {'number': 15, 'presence': 'away', 'line': 'offline'},
        {'number': '', 'presence': 'away'},
        'garbage',
        {'number': '16', 'presence': null, 'line': 'teleporting'},
      ],
    });

    test('parses self and extensions by number', () {
      expect(snapshot.selfNumber, '12');
      expect(snapshot.self, const ExtensionStatus(presence: Presence.available, line: LineState.idle));
      expect(snapshot.statusFor('11'), const ExtensionStatus(presence: Presence.lunch, line: LineState.busy));
      expect(snapshot.statusFor('15')?.line, LineState.offline);
      expect(snapshot.extensions.length, 3);
    });

    test('unknown values fall back to unknown', () {
      expect(snapshot.statusFor('16'), const ExtensionStatus());
      expect(snapshot.statusFor('99'), isNull);
    });

    test('missing self is tolerated', () {
      final s = PresenceSnapshot.fromJson({'extensions': null});
      expect(s.self, isNull);
      expect(s.extensions, isEmpty);
    });

    test('withOwnPresence updates self and the own row, keeps the line', () {
      final s = PresenceSnapshot.fromJson({
        'self': {'number': '12', 'presence': 'available', 'line': 'busy'},
        'extensions': [
          {'number': '12', 'presence': 'available', 'line': 'busy'},
        ],
      }).withOwnPresence(Presence.lunch);
      expect(s.self, const ExtensionStatus(presence: Presence.lunch, line: LineState.busy));
      expect(s.extensions['12']?.presence, Presence.lunch);
    });
  });

  group('ExtensionStatus colour and label', () {
    ExtensionStatus s(Presence p, LineState l) => ExtensionStatus(presence: p, line: l);

    test('busy and ringing are red regardless of presence', () {
      expect(s(Presence.available, LineState.busy).color, AppColors.presenceBusy);
      expect(s(Presence.available, LineState.busy).label, 'telefoniert');
      expect(s(Presence.lunch, LineState.ringing).color, AppColors.presenceBusy);
      expect(s(Presence.lunch, LineState.ringing).label, 'klingelt');
    });

    test('offline is grey', () {
      expect(s(Presence.available, LineState.offline).color, AppColors.presenceOffline);
      expect(s(Presence.available, LineState.offline).label, 'offline');
    });

    test('idle shows the presence colour and label', () {
      expect(s(Presence.available, LineState.idle).color, AppColors.presenceAvailable);
      expect(s(Presence.away, LineState.idle).color, AppColors.presenceAway);
      expect(s(Presence.lunch, LineState.idle).color, AppColors.presenceLunch);
      expect(s(Presence.lunch, LineState.idle).label, 'Mittagspause');
      expect(s(Presence.offWork, LineState.idle).color, AppColors.presenceOffline);
      expect(s(Presence.doNotDisturb, LineState.idle).color, AppColors.presenceBusy);
      expect(s(Presence.doNotDisturb, LineState.idle).label, 'nicht stören');
    });

    test('unknown line (older PBX) behaves like idle', () {
      expect(s(Presence.away, LineState.unknown).color, AppColors.presenceAway);
      expect(s(Presence.away, LineState.unknown).label, 'abwesend');
    });
  });
}
