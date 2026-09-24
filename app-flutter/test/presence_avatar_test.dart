import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/models/contact.dart';
import 'package:ha_phone_test/models/extension_status.dart';
import 'package:ha_phone_test/models/presence.dart';
import 'package:ha_phone_test/theme/app_colors.dart';
import 'package:ha_phone_test/theme/app_theme.dart';
import 'package:ha_phone_test/utils/contact_filter.dart';
import 'package:ha_phone_test/widgets/inline_audio_player.dart';
import 'package:ha_phone_test/widgets/presence_avatar.dart';

void main() {
  group('avatarPresenceFor', () {
    ExtensionStatus s(Presence p, LineState l) => ExtensionStatus(presence: p, line: l);

    test('line state wins: busy and ringing are "telefoniert", offline has no ring', () {
      expect(avatarPresenceFor(s(Presence.available, LineState.busy)), AvatarPresence.busy);
      expect(avatarPresenceFor(s(Presence.doNotDisturb, LineState.ringing)), AvatarPresence.busy);
      expect(avatarPresenceFor(s(Presence.available, LineState.offline)), AvatarPresence.offline);
    });

    test('idle line shows the presence', () {
      expect(avatarPresenceFor(s(Presence.available, LineState.idle)), AvatarPresence.available);
      expect(avatarPresenceFor(s(Presence.away, LineState.idle)), AvatarPresence.away);
      expect(avatarPresenceFor(s(Presence.lunch, LineState.idle)), AvatarPresence.away);
      expect(avatarPresenceFor(s(Presence.doNotDisturb, LineState.idle)), AvatarPresence.doNotDisturb);
      expect(avatarPresenceFor(s(Presence.offWork, LineState.unknown)), AvatarPresence.offWork);
    });

    test('nothing known: plain avatar; idle without presence: available', () {
      expect(avatarPresenceFor(null), isNull);
      expect(avatarPresenceFor(s(Presence.unknown, LineState.unknown)), isNull);
      expect(avatarPresenceFor(s(Presence.unknown, LineState.idle)), AvatarPresence.available);
    });

    test('every visible state has its own glyph (colour-blind safe)', () {
      final glyphs = [
        for (final p in AvatarPresence.values)
          if (p != AvatarPresence.offline) p.glyph,
      ];
      expect(glyphs.toSet(), hasLength(glyphs.length));
      expect(AvatarPresence.offline.glyph, isNull);
    });

    test('colours come from the theme roles', () {
      const c = NwColors.dark;
      expect(AvatarPresence.available.color(c), c.answer);
      expect(AvatarPresence.away.color(c), c.door);
      expect(AvatarPresence.doNotDisturb.color(c), c.end);
      expect(AvatarPresence.busy.color(c), c.end);
      expect(NwColors.light.blue, const Color(0xFF0369A1));
    });
  });

  group('PresenceAvatar widget', () {
    Future<void> pump(WidgetTester tester, AvatarPresence? p) => tester.pumpWidget(MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: Center(child: PresenceAvatar(name: 'Oma Erika', number: '0171', presence: p))),
        ));

    testWidgets('ring and glyph for available, initials', (tester) async {
      await pump(tester, AvatarPresence.available);
      expect(find.text('OE'), findsOneWidget);
      expect(find.byKey(const ValueKey('presence-ring')), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.bySemanticsLabel('verfügbar'), findsOneWidget);
    });

    testWidgets('offline: neither ring nor glyph', (tester) async {
      await pump(tester, AvatarPresence.offline);
      expect(find.byKey(const ValueKey('presence-ring')), findsNothing);
      expect(find.byKey(const ValueKey('presence-glyph')), findsNothing);
    });

    testWidgets('no presence: plain avatar', (tester) async {
      await pump(tester, null);
      expect(find.byKey(const ValueKey('presence-ring')), findsNothing);
    });
  });

  group('theme', () {
    test('light and dark carry the Nachtwache roles and bundled fonts', () {
      final dark = AppTheme.dark();
      final light = AppTheme.light();
      expect(dark.extension<NwColors>()?.ground, const Color(0xFF0B0F14));
      expect(light.extension<NwColors>()?.ground, const Color(0xFFF4F6F9));
      expect(dark.scaffoldBackgroundColor, const Color(0xFF0B0F14));
      expect(dark.textTheme.headlineLarge?.fontFamily, NwFonts.display);
      expect(dark.textTheme.bodyLarge?.fontFamily, NwFonts.ui);
      expect(NwType.meta.fontFeatures, contains(const FontFeature.tabularFigures()));
    });
  });

  group('resolveFavorites', () {
    test('one tile per number from all sources, own extension excluded, sorted', () {
      const ext = [Contact(number: '11', name: 'sandro'), Contact(number: '12', name: 'Anna')];
      const book = [Contact(number: '11', name: 'Sandro Büro', isExtension: false)];
      const phone = [Contact(number: '0171', name: 'Oma Erika', isExtension: false)];
      final favs = resolveFavorites({'11', '12', '0171'}, extensions: ext, phonebook: book, phone: phone, self: '12');
      expect(favs.map((c) => c.name), ['Oma Erika', 'sandro']);
      expect(resolveFavorites({}, extensions: ext), isEmpty);
    });
  });

  group('playback speed', () {
    test('cycles 1× → 1,5× → 2× → 1×', () {
      expect(formatSpeed(1.0), '1×');
      expect(formatSpeed(1.5), '1,5×');
      expect(nextSpeed(1.0), 1.5);
      expect(nextSpeed(1.5), 2.0);
      expect(nextSpeed(2.0), 1.0);
    });
  });
}
