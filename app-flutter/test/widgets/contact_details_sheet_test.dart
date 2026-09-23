import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/models/contact.dart';
import 'package:ha_phone_test/models/presence.dart';
import 'package:ha_phone_test/services/presence_repository.dart';
import 'package:ha_phone_test/theme/app_colors.dart';
import 'package:ha_phone_test/widgets/contact_avatar.dart';
import 'package:ha_phone_test/widgets/contact_details_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_api.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('details sheet shows the live line state, not the directory presence', (tester) async {
    final fake = FakePbx({
      'GET /api/mobile/presence': (_) => jsonResponse({
            'self': {'number': '13', 'presence': 'available', 'line': 'idle'},
            'extensions': [
              {'number': '11', 'presence': 'available', 'line': 'busy'},
            ],
          }),
    });
    final presence = PresenceRepository(api: fake.api, authLoader: testAuthLoader);
    await tester.runAsync(presence.refresh);
    const contact = Contact(number: '11', name: 'sandro', presence: Presence.lunch);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ContactDetailsSheet(contact: contact, onCall: () {}, presence: presence)),
    ));

    expect(find.text('Nebenstelle 11 · telefoniert'), findsOneWidget);
    expect(tester.widget<ContactAvatar>(find.byType(ContactAvatar)).dotColor, AppColors.presenceBusy);
  });

  testWidgets('without live data the directory presence is shown', (tester) async {
    final presence = PresenceRepository(api: FakePbx({}).api, authLoader: testAuthLoader);
    const contact = Contact(number: '11', name: 'sandro', presence: Presence.lunch);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ContactDetailsSheet(contact: contact, onCall: () {}, presence: presence)),
    ));

    expect(find.text('Nebenstelle 11 · Mittagspause'), findsOneWidget);
  });
}
