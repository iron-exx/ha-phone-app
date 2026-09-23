import 'contact.dart';

/// Parsed response of GET /api/mobile/directory.
class Directory {
  const Directory({this.self, this.extensions = const [], this.phonebook = const []});

  factory Directory.fromJson(Map<String, dynamic> json) {
    final selfJson = json['self'];
    return Directory(
      self: selfJson is Map<String, dynamic> && (selfJson['number'] ?? '').toString().isNotEmpty
          ? Contact.fromJson(selfJson, isExtension: true)
          : null,
      extensions: _list(json['extensions'], isExtension: true),
      phonebook: _list(json['phonebook'], isExtension: false),
    );
  }

  static List<Contact> _list(Object? raw, {required bool isExtension}) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map((e) => Contact.fromJson(e, isExtension: isExtension))
        .toList();
  }

  /// This device's own extension, null if the PBX didn't find it.
  final Contact? self;
  final List<Contact> extensions;
  final List<Contact> phonebook;

  Map<String, dynamic> toJson() => {
        if (self != null) 'self': self!.toJson(),
        'extensions': extensions.map((e) => e.toJson()).toList(),
        'phonebook': phonebook.map((e) => e.toJson()).toList(),
      };

  /// Number -> DTMF open code for SipChannel.setDoorCodes.
  Map<String, String> get doorCodes => {
        for (final e in extensions)
          if (e.doorOpenCode.isNotEmpty) e.number: e.doorOpenCode,
      };

  /// Name for a number (extensions first), or '' if unknown.
  String nameFor(String number) {
    for (final c in [...extensions, ...phonebook]) {
      if (c.number == number && c.name.isNotEmpty) return c.name;
    }
    return '';
  }

  Contact? contactFor(String number) {
    for (final c in [...extensions, ...phonebook]) {
      if (c.number == number) return c;
    }
    return null;
  }
}
