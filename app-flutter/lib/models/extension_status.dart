import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'presence.dart';

/// Live line state of an extension, from Asterisk via GET /api/mobile/presence.
/// [unknown] = the PBX sent nothing (older version, or not in the snapshot).
enum LineState {
  idle('idle', 'frei'),
  ringing('ringing', 'klingelt'),
  busy('busy', 'telefoniert'),
  offline('offline', 'offline'),
  unknown('', 'unbekannt');

  const LineState(this.apiValue, this.label);

  final String apiValue;

  /// German label, e.g. for "11 · telefoniert".
  final String label;

  static LineState fromApi(String? value) {
    for (final s in LineState.values) {
      if (s != unknown && s.apiValue == value) return s;
    }
    return unknown;
  }
}

/// Presence plus line state of one extension. The line state wins over the
/// presence: someone on the phone is "telefoniert" whatever they set.
class ExtensionStatus {
  const ExtensionStatus({this.presence = Presence.unknown, this.line = LineState.unknown});

  factory ExtensionStatus.fromJson(Map<String, dynamic> json) => ExtensionStatus(
        presence: Presence.fromApi(json['presence'] as String?),
        line: LineState.fromApi(json['line'] as String?),
      );

  final Presence presence;
  final LineState line;

  /// Avatar-dot colour: red while busy/ringing, grey when offline, otherwise
  /// the presence colour.
  Color get color => switch (line) {
        LineState.busy || LineState.ringing => AppColors.presenceBusy,
        LineState.offline => AppColors.presenceOffline,
        LineState.idle || LineState.unknown => presence.color,
      };

  /// Subtitle text after the number: "telefoniert", "offline", "Mittagspause".
  String get label => switch (line) {
        LineState.busy || LineState.ringing || LineState.offline => line.label,
        LineState.idle || LineState.unknown => presence.label,
      };

  ExtensionStatus copyWith({Presence? presence, LineState? line}) =>
      ExtensionStatus(presence: presence ?? this.presence, line: line ?? this.line);

  @override
  bool operator ==(Object other) => other is ExtensionStatus && other.presence == presence && other.line == line;

  @override
  int get hashCode => Object.hash(presence, line);
}

/// Parsed response of GET /api/mobile/presence.
class PresenceSnapshot {
  const PresenceSnapshot({this.selfNumber = '', this.self, this.extensions = const {}});

  factory PresenceSnapshot.fromJson(Map<String, dynamic> json) {
    final selfJson = json['self'];
    final raw = json['extensions'];
    final byNumber = <String, ExtensionStatus>{};
    if (raw is List) {
      for (final e in raw.whereType<Map<String, dynamic>>()) {
        final number = (e['number'] ?? '').toString();
        if (number.isNotEmpty) byNumber[number] = ExtensionStatus.fromJson(e);
      }
    }
    final hasSelf = selfJson is Map<String, dynamic> && (selfJson['number'] ?? '').toString().isNotEmpty;
    return PresenceSnapshot(
      selfNumber: hasSelf ? selfJson['number'].toString() : '',
      self: hasSelf ? ExtensionStatus.fromJson(selfJson) : null,
      extensions: byNumber,
    );
  }

  final String selfNumber;

  /// Own extension, null if the PBX didn't find it.
  final ExtensionStatus? self;

  /// Number -> status of every extension.
  final Map<String, ExtensionStatus> extensions;

  ExtensionStatus? statusFor(String number) => number.isNotEmpty && number == selfNumber ? self : extensions[number];

  /// Copy with the own presence replaced (optimistic update after PUT).
  PresenceSnapshot withOwnPresence(Presence presence) {
    final nextSelf = (self ?? const ExtensionStatus()).copyWith(presence: presence);
    final nextExtensions = {...extensions};
    final mine = nextExtensions[selfNumber];
    if (mine != null) nextExtensions[selfNumber] = mine.copyWith(presence: presence);
    return PresenceSnapshot(selfNumber: selfNumber, self: nextSelf, extensions: nextExtensions);
  }
}
