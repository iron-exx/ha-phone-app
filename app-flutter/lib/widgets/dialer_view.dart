import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/contact.dart';
import '../services/call_launcher.dart';
import '../services/directory_repository.dart';
import '../services/phone_contacts_repository.dart';
import '../services/presence_repository.dart';
import '../services/registration_watcher.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/contact_filter.dart';
import '../utils/registration_ui.dart';
import 'dialpad_grid.dart';
import 'nw_widgets.dart';
import 'presence_avatar.dart';

/// Maximum number of live matches shown under the typed number.
const kDialerMaxMatches = 3;

/// Contacts whose number (or name) matches the typed [digits], one per
/// number, extensions first; nothing below two digits.
List<Contact> dialerMatches(String digits, List<List<Contact>> sources, {int max = kDialerMaxMatches}) {
  if (digits.length < 2) return const [];
  final seen = <String>{};
  final hits = <Contact>[];
  for (final source in sources) {
    for (final c in filterContacts(source, digits)) {
      if (c.number.isEmpty || !seen.add(c.number)) continue;
      hits.add(c);
      if (hits.length >= max) return hits;
    }
  }
  return hits;
}

/// Wählen: line + readiness chips, the typed number (Bricolage 40), live
/// matches with presence, the dialpad and the green 76 dp call button with
/// Mailbox (left) and Löschen (right). Also used by the '/dialpad' route.
class DialerView extends StatefulWidget {
  const DialerView({
    super.key,
    this.showHeader = true,
    DirectoryRepository? directory,
    PresenceRepository? presence,
    PhoneContactsRepository? phoneContacts,
    RegistrationWatcher? registration,
  })  : _directory = directory,
        _presence = presence,
        _phone = phoneContacts,
        _registration = registration;

  /// Line and "bereit" chips at the top.
  final bool showHeader;
  final DirectoryRepository? _directory;
  final PresenceRepository? _presence;
  final PhoneContactsRepository? _phone;
  final RegistrationWatcher? _registration;

  @override
  State<DialerView> createState() => _DialerViewState();
}

class _DialerViewState extends State<DialerView> {
  String _digits = '';

  /// Wahlwiederholung like on a desk phone: call with an empty field brings back the last number.
  static String _lastDialed = '';

  DirectoryRepository get _dir => widget._directory ?? DirectoryRepository.instance;
  PresenceRepository get _presence => widget._presence ?? PresenceRepository.instance;
  PhoneContactsRepository get _phone => widget._phone ?? PhoneContactsRepository.instance;
  RegistrationWatcher get _registration => widget._registration ?? RegistrationWatcher.instance;

  @override
  void initState() {
    super.initState();
    if (widget.showHeader) _registration.start();
  }

  void _append(String d) => setState(() => _digits += d);

  void _backspace() {
    if (_digits.isEmpty) return;
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  Future<void> _call() async {
    final number = _digits;
    if (number.isEmpty) {
      if (_lastDialed.isNotEmpty) setState(() => _digits = _lastDialed);
      return;
    }
    await _dial(number);
  }

  Future<void> _dial(String number) async {
    HapticFeedback.mediumImpact();
    _lastDialed = number;
    setState(() => _digits = '');
    await CallLauncher.call(context, number);
  }

  List<Contact> _matches() {
    final d = _dir.directory;
    return dialerMatches(_digits, [
      d?.extensions.where((c) => c.number != d.self?.number).toList() ?? const [],
      d?.phonebook ?? const [],
      _phone.contacts ?? const [],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Shrink keys on small screens so the call button stays visible.
        final keyHeight = ((constraints.maxHeight - (widget.showHeader ? 330 : 270)) / 4).clamp(46.0, 66.0);
        return Column(
          children: [
            if (widget.showHeader) _header(context),
            Expanded(child: _numberAndMatches(context)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: DialpadGrid(onDigit: _append, keySize: keyHeight),
            ),
            _bottomRow(context),
          ],
        );
      },
    );
  }

  Widget _header(BuildContext context) {
    final c = context.nw;
    return ListenableBuilder(
      listenable: Listenable.merge([_dir, _registration]),
      builder: (context, _) {
        final own = _dir.directory?.self?.number;
        final reg = _registration.state;
        final (IconData icon, Color color) = switch (reg) {
          RegistrationUi.online => (Icons.check_rounded, c.okText),
          RegistrationUi.offline => (Icons.cloud_off_outlined, c.end),
          RegistrationUi.connecting => (Icons.sync, c.door),
        };
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 8,
            runSpacing: 4,
            children: [
              NwChip(
                icon: Icons.smartphone,
                label: own == null ? 'Leitung 1' : 'Leitung 1 · $own',
              ),
              NwChip(
                key: const Key('dialer-ready'),
                icon: icon,
                foreground: color,
                label: reg == RegistrationUi.online ? 'bereit' : reg.label,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _numberAndMatches(BuildContext context) {
    final c = context.nw;
    return ListenableBuilder(
      listenable: Listenable.merge([_dir, _presence, _phone]),
      builder: (context, _) {
        final matches = _matches();
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          children: [
            Semantics(
              liveRegion: true,
              label: _digits.isEmpty ? null : 'Nummer ${_digits.split('').join(' ')}',
              child: SizedBox(
                height: 56,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _digits.isEmpty ? 'Nummer eingeben' : _digits,
                      key: const Key('dialer-display'),
                      style: _digits.isEmpty
                          ? NwType.rowTitle.copyWith(color: c.faint, fontSize: 20)
                          : NwType.display(40, weight: FontWeight.w700).copyWith(color: c.text, letterSpacing: 0.8),
                    ),
                  ),
                ),
              ),
            ),
            for (final m in matches) ...[
              const SizedBox(height: 8),
              _matchRow(context, m),
            ],
          ],
        );
      },
    );
  }

  Widget _matchRow(BuildContext context, Contact m) {
    final c = context.nw;
    final kind = m.isExtension ? avatarPresenceFor(_presence.statusFor(m.number)) : null;
    final source = m.isExtension ? 'Nebenstelle' : (m.label.isNotEmpty ? m.label : 'Telefonbuch');
    final at = m.number.indexOf(_digits);
    final numberStyle = NwType.meta.copyWith(color: c.faint, fontSize: 12);
    final number = at < 0
        ? TextSpan(text: m.number)
        : TextSpan(children: [
            TextSpan(text: m.number.substring(0, at)),
            TextSpan(
              text: _digits,
              style: TextStyle(color: c.text, fontWeight: FontWeight.w800),
            ),
            TextSpan(text: m.number.substring(at + _digits.length)),
          ]);
    return Semantics(
      button: true,
      label: '${m.displayName} anrufen, ${m.number}',
      excludeSemantics: true,
      child: NwCard(
        key: ValueKey('dialer-match-${m.number}'),
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        onTap: () => _dial(m.number),
        child: Row(
          children: [
            PresenceAvatar(name: m.name, number: m.number, presence: kind, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.displayName,
                      style: NwType.rowTitle.copyWith(color: c.text, fontSize: 14.5, fontWeight: FontWeight.w800),
                      overflow: TextOverflow.ellipsis),
                  Text.rich(TextSpan(children: [number, TextSpan(text: ' · $source')]), style: numberStyle),
                ],
              ),
            ),
            Icon(Icons.call, size: 18, color: c.answer),
          ],
        ),
      ),
    );
  }

  Widget _bottomRow(BuildContext context) {
    final c = context.nw;
    final canCall = _digits.isNotEmpty || _lastDialed.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(44, 14, 44, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          NwIconButton(
            key: const Key('dialer-mailbox'),
            icon: Icons.voicemail,
            label: 'Mailbox anrufen',
            size: 56,
            radius: 18,
            color: Colors.transparent,
            iconColor: c.muted,
            iconSize: 24,
            onPressed: () => _dial(kVoicemailNumber),
          ),
          Tooltip(
            message: 'Anrufen',
            child: Semantics(
              button: true,
              enabled: canCall,
              label: _digits.isEmpty && _lastDialed.isNotEmpty ? 'Wahlwiederholung' : 'Anrufen',
              excludeSemantics: true,
              child: Material(
                key: const Key('dialer-call'),
                color: canCall ? c.answer : c.answer.withOpacity(0.4),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  // Empty field + call = Wahlwiederholung (fills in the last number).
                  onTap: canCall ? _call : null,
                  child: SizedBox(width: 76, height: 76, child: Icon(Icons.call, size: 32, color: c.answerInk)),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 56,
            height: 56,
            child: _digits.isEmpty
                ? null
                // IconButton has no long-press and its tooltip would
                // swallow one, hence a plain InkResponse.
                : Semantics(
                    button: true,
                    label: 'Löschen, lang drücken löscht alles',
                    excludeSemantics: true,
                    child: InkResponse(
                      key: const Key('dialer-backspace'),
                      radius: 28,
                      onTap: _backspace,
                      onLongPress: () => setState(() => _digits = ''),
                      child: Icon(Icons.backspace_outlined, size: 26, color: c.muted),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
