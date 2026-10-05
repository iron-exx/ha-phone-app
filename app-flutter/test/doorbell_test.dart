import 'package:ha_phone_test/models/contact.dart';
import 'package:ha_phone_test/widgets/door_card.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ha_phone_test/models/doorbell_event.dart';
import 'package:ha_phone_test/screens/doorbell_history_screen.dart';
import 'package:ha_phone_test/services/api_client.dart';
import 'package:ha_phone_test/services/doorbell_repository.dart';
import 'package:ha_phone_test/theme/app_theme.dart';

const _auth = DeviceAuth(apiHost: 'pbx', deviceId: '1', deviceToken: 't');

final _events = [
  {'id': 2, 'door_number': 17, 'door_name': 'Haustür', 'started_at': '2026-09-25T12:00:00Z',
   'answered_by': '11', 'door_opened': true, 'has_image': false},
  {'id': 1, 'door_number': 17, 'door_name': '', 'started_at': '2026-09-24T08:00:00Z',
   'answered_by': '', 'door_opened': false, 'has_image': false},
];

DoorbellRepository _repo({int status = 200}) => DoorbellRepository(
      api: ApiClient(client: MockClient((req) async {
        expect(req.headers['X-Device-Token'], 't');
        return http.Response(jsonEncode(_events), status, headers: {'content-type': 'application/json'});
      })),
      authLoader: () async => _auth,
    );

void main() {
  test('parses events, missed and title fallback', () {
    final list = parseDoorbellEvents(_events);
    expect(list.first.doorNumber, '17');
    expect(list.first.missed, isFalse);
    expect(list.last.missed, isTrue);
    expect(list.last.title, 'Tür 17');
    expect(parseDoorbellEvents({'not': 'a list'}), isEmpty);
  });

  test('repository loads and picks the newest ring per door', () async {
    final repo = _repo();
    await repo.refresh();
    expect(repo.events, hasLength(2));
    expect(repo.latestFor('17')!.id, 2);
    expect(repo.latestFor('99'), isNull);
    repo.clear();
    expect(repo.events, isEmpty);
  });

  test('old PBX (404) is reported as unsupported', () async {
    final repo = _repo(status: 404);
    await repo.refresh();
    expect(repo.isUnsupported, isTrue);
  });

  testWidgets('door card shows "Verlauf" on the picture and opens the history', (tester) async {
    final repo = _repo();
    await repo.refresh();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: DoorCard(door: const Contact(number: '17', name: 'Haustür', isDoor: true), doorbell: repo)),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('door-history-hint')), findsOneWidget);
    await tester.tap(find.byKey(const Key('door-history-hint')));
    await tester.pumpAndSettle();
    expect(find.byType(DoorbellHistoryScreen), findsOneWidget);
  });

  testWidgets('door card placeholder stays clear of the chips at 200 % text', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      builder: (context, child) =>
          MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2.0)), child: child!),
      home: Scaffold(
        body: DoorCard(
          door: const Contact(number: '17', name: 'Haustür', isDoor: true),
          lastRing: DateTime(2026, 9, 29, 12, 38),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final icon = tester.getRect(find.byIcon(Icons.videocam_outlined));
    final last = tester.getRect(find.textContaining('zuletzt'));
    final name = tester.getRect(find.text('Haustür'));
    expect(icon.overlaps(last), isFalse);
    expect(icon.overlaps(name), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history shows answered, opened and missed rings', (tester) async {
    final repo = _repo();
    await tester.pumpWidget(MaterialApp(theme: AppTheme.dark(), home: DoorbellHistoryScreen(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('Haustür'), findsOneWidget);
    expect(find.text('angenommen von 11'), findsOneWidget);
    expect(find.text('Tür geöffnet'), findsOneWidget);
    expect(find.text('verpasst'), findsOneWidget);
  });
}
