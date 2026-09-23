import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/services/call_events.dart';

import 'helpers/fake_sip.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('skips unknown event types instead of failing the stream', () async {
    final sip = FakeSip()..install();
    final received = <CallEvent>[];
    final sub = CallEvents.instance.stream.listen(received.add);
    await Future<void>.delayed(Duration.zero);

    sip.emit({'type': 'somethingNew', 'x': 1});
    sip.emit({'type': 'registrationState', 'state': 'registered'});
    sip.emit({'type': 'callState', 'callId': '1', 'direction': 'outgoing', 'state': 'confirmed'});
    sip.emit({'type': 'callHistoryChanged'});
    sip.emit({
      'type': 'audioRoute',
      'current': 's',
      'routes': [
        {'id': 's', 'name': 'Lautsprecher', 'type': 'speaker'},
      ],
    });
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(4));
    expect((received[0] as RegistrationStateEvent).state, 'registered');
    expect((received[1] as CallStateEvent).state, 'confirmed');
    expect(received[2], isA<CallHistoryChangedEvent>());
    expect((received[3] as AudioRouteEvent).routes.current?.type, 'speaker');
    await sub.cancel();
    sip.uninstall();
  });
}
