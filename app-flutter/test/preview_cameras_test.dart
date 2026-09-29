import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ha_phone_test/models/preview_camera.dart';
import 'package:ha_phone_test/screens/preview_cameras_screen.dart';
import 'package:ha_phone_test/services/api_client.dart';
import 'package:ha_phone_test/services/local_store.dart';
import 'package:ha_phone_test/services/preview_cameras_repository.dart';
import 'package:ha_phone_test/theme/app_theme.dart';
import 'package:ha_phone_test/widgets/camera_strip.dart';

const _auth = DeviceAuth(apiHost: 'pbx', deviceId: '1', deviceToken: 't');
const _jpeg = [0xff, 0xd8, 0xff, 0xe0, 1, 2, 3];

final _shared = [
  {'entity_id': 'camera.garten', 'name': 'Garten'},
  {'entity_id': 'camera.einfahrt', 'name': ''},
];

class _Fake {
  _Fake({this.listStatus = 200});
  final int listStatus;
  final snapshots = <String>[];
  final pushed = <List<Map<String, String>>>[];

  PreviewCamerasRepository repo() => PreviewCamerasRepository(
        api: ApiClient(client: MockClient((req) async {
          expect(req.headers['X-Device-Token'], 't');
          if (req.url.path == '/api/mobile/cameras') {
            return http.Response(jsonEncode(_shared), listStatus, headers: {'content-type': 'application/json'});
          }
          snapshots.add(req.url.pathSegments[3]);
          return http.Response.bytes(_jpeg, 200, headers: {'content-type': 'image/jpeg'});
        })),
        authLoader: () async => _auth,
        pushToNative: (list) async => pushed.add(list),
      );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('parses cameras, name falls back to the entity id, drops non-cameras', () {
    final list = parsePreviewCameras([..._shared, {'entity_id': 'light.flur', 'name': 'x'}]);
    expect(list.map((c) => c.name), ['Garten', 'camera.einfahrt']);
    expect(parsePreviewCameras({'no': 'list'}), isEmpty);
  });

  test('nothing is shown until chosen; choice is stored and pushed to the ringing screen', () async {
    final fake = _Fake();
    final repo = fake.repo();
    await repo.refresh();
    expect(repo.available, hasLength(2));
    expect(repo.shown, isEmpty);

    await repo.toggle('camera.einfahrt');
    await repo.toggle('camera.garten');
    // Admin order, not tap order.
    expect(repo.shown.map((c) => c.entityId), ['camera.garten', 'camera.einfahrt']);
    expect(fake.pushed.last, [
      {'entity_id': 'camera.garten', 'name': 'Garten'},
      {'entity_id': 'camera.einfahrt', 'name': 'camera.einfahrt'},
    ]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(StoreKeys.previewCameras), ['camera.einfahrt', 'camera.garten']);

    // A fresh start reads the choice back.
    final again = fake.repo();
    await again.refresh();
    expect(again.shown, hasLength(2));

    await again.clear();
    expect(again.shown, isEmpty);
    expect(prefs.getStringList(StoreKeys.previewCameras), isNull);
    expect(fake.pushed.last, isEmpty);
  });

  test('a camera the admin no longer shares disappears even if chosen', () async {
    SharedPreferences.setMockInitialValues({StoreKeys.previewCameras: ['camera.babyfon', 'camera.garten']});
    final repo = _Fake().repo();
    await repo.refresh();
    expect(repo.shown.map((c) => c.entityId), ['camera.garten']);
  });

  test('old PBX (404) is unsupported', () async {
    final repo = _Fake(listStatus: 404).repo();
    await repo.refresh();
    expect(repo.isUnsupported, isTrue);
    expect(repo.hasLoaded, isTrue);
  });

  testWidgets('settings screen toggles a camera, the strip shows it with a live picture', (tester) async {
    final fake = _Fake();
    final repo = fake.repo();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Column(children: [
          Expanded(child: PreviewCamerasScreen(repository: repo)),
          CameraStrip(repository: repo),
        ]),
      ),
    ));
    await tester.runAsync(() => repo.refresh());
    await tester.pump();
    expect(find.text('Garten'), findsOneWidget);
    expect(find.byKey(const Key('camera-strip')), findsNothing);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('camera-choice-camera.garten')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.byKey(const Key('camera-strip')), findsOneWidget);
    expect(find.byKey(const ValueKey('camera-thumb-camera.garten')), findsOneWidget);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(fake.snapshots, contains('camera.garten'));

    // Unmount before the refresh timers fire again.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('screen explains when nothing is shared', (tester) async {
    final repo = PreviewCamerasRepository(
      api: ApiClient(client: MockClient((req) async =>
          http.Response('[]', 200, headers: {'content-type': 'application/json'}))),
      authLoader: () async => _auth,
      pushToNative: (_) async {},
    );
    await tester.pumpWidget(MaterialApp(theme: AppTheme.dark(), home: PreviewCamerasScreen(repository: repo)));
    await tester.runAsync(() => repo.refresh());
    await tester.pump();
    expect(find.byKey(const Key('cameras-hint')), findsOneWidget);
    expect(find.textContaining('Kameras für die App'), findsOneWidget);
  });
}
