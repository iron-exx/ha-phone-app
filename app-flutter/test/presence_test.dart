import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/models/presence.dart';
import 'package:ha_phone_test/theme/app_colors.dart';
import 'package:ha_phone_test/utils/registration_ui.dart';

void main() {
  group('Presence', () {
    test('maps every API value to a German label', () {
      expect(Presence.fromApi('available').label, 'verfügbar');
      expect(Presence.fromApi('away').label, 'abwesend');
      expect(Presence.fromApi('lunch').label, 'Mittagspause');
      expect(Presence.fromApi('off_work').label, 'Feierabend');
      expect(Presence.fromApi('do_not_disturb').label, 'nicht stören');
    });

    test('uses the design-system colours', () {
      expect(Presence.available.color, AppColors.presenceAvailable);
      expect(Presence.away.color, AppColors.presenceAway);
      expect(Presence.lunch.color, AppColors.presenceLunch);
      expect(Presence.offWork.color, AppColors.presenceOffline);
      expect(Presence.doNotDisturb.color, AppColors.presenceBusy);
    });

    test('falls back to unknown for null or unexpected values', () {
      expect(Presence.fromApi(null), Presence.unknown);
      expect(Presence.fromApi('business_trip'), Presence.unknown);
      expect(Presence.fromApi(''), Presence.unknown);
      expect(Presence.unknown.color, AppColors.presenceOffline);
    });
  });

  group('RegistrationUi', () {
    test('maps native registration states', () {
      expect(RegistrationUi.fromState('registered').label, 'Online (TLS)');
      expect(RegistrationUi.fromState('failed'), RegistrationUi.offline);
      expect(RegistrationUi.fromState('unregistered').label, 'Nicht verbunden');
      expect(RegistrationUi.fromState('unknown').label, 'Verbinde…');
    });
  });
}
