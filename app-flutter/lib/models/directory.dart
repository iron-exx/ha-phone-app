import 'contact.dart';
import '../utils/phone_number.dart';

/// Parsed response of GET /api/mobile/directory.
class Directory {
  const Directory({
    this.self,
    this.extensions = const [],
    this.phonebook = const [],
    this.recordingAllowed = false,
  });

  factory Directory.fromJson(Map<String, dynamic> json) {
    final selfJson = json['self'];
    final hasSelf = selfJson is Map<String, dynamic> && (selfJson['number'] ?? '').toString().isNotEmpty;
    return Directory(
      self: hasSelf ? Contact.fromJson(selfJson, isExtension: true) : null,
      recordingAllowed: hasSelf && selfJson['recording_allowed'] == true,
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

  /// `self.recording_allowed`: the admin lets the own extension record calls
  /// (HA-Phone 0.7.114; false on older versions).
  final bool recordingAllowed;

  Map<String, dynamic> toJson() => {
        if (self != null) 'self': {...self!.toJson(), 'recording_allowed': recordingAllowed},
        'extensions': extensions.map((e) => e.toJson()).toList(),
        'phonebook': phonebook.map((e) => e.toJson()).toList(),
      };

  /// Number -> DTMF open code for SipChannel.setDoorCodes.
  Map<String, String> get doorCodes => {
        for (final e in extensions)
          if (e.doorOpenCode.isNotEmpty) e.number: e.doorOpenCode,
      };

  /// Number -> Home Assistant action labels for SipChannel.setDoorActions.
  Map<String, List<String>> get doorActions => {
        for (final e in extensions)
          if (e.doorActions.isNotEmpty) e.number: e.doorActions,
      };

  /// Name for a number (extensions first), or '' if unknown. Exact match
  /// first, then ignoring formatting and +49 vs. 0 (phonebook numbers).
  String nameFor(String number) {
    final all = [...extensions, ...phonebook];
    for (final c in all) {
      if (c.number == number && c.name.isNotEmpty) return c.name;
    }
    for (final c in phonebook) {
      if (c.name.isNotEmpty && phoneNumbersMatch(c.number, number)) return c.name;
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
