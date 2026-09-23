import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/models/directory.dart';
import 'package:ha_phone_test/models/presence.dart';

const _json = '''
{"self": {"number":"13","name":"Test","presence":"available"},
 "extensions": [
   {"number":"16","name":"türklingel","video":true,"door_open_code":"*1","presence":"available",
    "door_actions":[{"index":1,"label":"Garage"},{"index":0,"label":"Licht"}]},
   {"number":"11","name":"sandro","video":true,"door_open_code":null,"presence":"lunch"},
   {"number":15,"name":"dect","video":null,"door_open_code":"","presence":null}
 ],
 "phonebook": [{"number":"0301234567","name":"Pizzeria"}]}
''';

void main() {
  final directory = Directory.fromJson(jsonDecode(_json) as Map<String, dynamic>);

  test('parses self, extensions and phonebook', () {
    expect(directory.self?.number, '13');
    expect(directory.self?.presence, Presence.available);
    expect(directory.extensions, hasLength(3));
    expect(directory.phonebook.single.name, 'Pizzeria');
    expect(directory.phonebook.single.isExtension, isFalse);
  });

  test('tolerates nulls and numeric numbers', () {
    final dect = directory.extensions[2];
    expect(dect.number, '15');
    expect(dect.video, isFalse);
    expect(dect.doorOpenCode, '');
    expect(dect.presence, Presence.unknown);
    expect(directory.extensions[1].presence, Presence.lunch);
  });

  test('only a door-open code makes a door station, video alone does not', () {
    expect(directory.extensions[0].isDoorStation, isTrue);
    expect(directory.extensions[1].isDoorStation, isFalse);
  });

  test('door actions keep the PBX index order and survive the cache', () {
    expect(directory.doorActions, {'16': ['Licht', 'Garage']});
    final cached = Directory.fromJson(jsonDecode(jsonEncode(directory.toJson())) as Map<String, dynamic>);
    expect(cached.doorActions, {'16': ['Licht', 'Garage']});
  });

  test('builds the door-code map for setDoorCodes', () {
    expect(directory.doorCodes, {'16': '*1'});
  });

  test('resolves names by number', () {
    expect(directory.nameFor('11'), 'sandro');
    expect(directory.nameFor('0301234567'), 'Pizzeria');
    expect(directory.nameFor('999'), '');
  });

  test('survives a cache round trip', () {
    final copy = Directory.fromJson(jsonDecode(jsonEncode(directory.toJson())) as Map<String, dynamic>);
    expect(copy.self?.name, 'Test');
    expect(copy.extensions.map((e) => e.number), ['16', '11', '15']);
    expect(copy.doorCodes, {'16': '*1'});
    expect(copy.phonebook.single.isExtension, isFalse);
  });

  test('handles missing sections', () {
    final empty = Directory.fromJson(const {});
    expect(empty.self, isNull);
    expect(empty.extensions, isEmpty);
    expect(empty.phonebook, isEmpty);
  });
}
