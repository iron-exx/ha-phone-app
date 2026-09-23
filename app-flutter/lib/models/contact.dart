import 'presence.dart';

/// One callable entry: a PBX extension or a phonebook number.
class Contact {
  const Contact({
    required this.number,
    required this.name,
    this.presence = Presence.unknown,
    this.video = false,
    this.doorOpenCode = '',
    this.isExtension = true,
  });

  /// Tolerant of nulls: the backend sends `door_open_code`/`video` as null
  /// for extensions that never had them set.
  factory Contact.fromJson(Map<String, dynamic> json, {required bool isExtension}) => Contact(
        number: (json['number'] ?? '').toString(),
        name: (json['name'] as String?) ?? '',
        presence: Presence.fromApi(json['presence'] as String?),
        video: json['video'] == true,
        doorOpenCode: (json['door_open_code'] as String?) ?? '',
        isExtension: isExtension,
      );

  final String number;
  final String name;
  final Presence presence;
  final bool video;
  final String doorOpenCode;

  /// false for phonebook entries (no presence, no avatar dot).
  final bool isExtension;

  /// Door stations are recognised by an open code or by video capability.
  bool get isDoorStation => doorOpenCode.isNotEmpty || video;

  String get displayName => name.isNotEmpty ? name : number;

  Map<String, dynamic> toJson() => {
        'number': number,
        'name': name,
        if (isExtension) 'presence': presence.apiValue,
        if (isExtension) 'video': video,
        if (isExtension) 'door_open_code': doorOpenCode,
      };
}
