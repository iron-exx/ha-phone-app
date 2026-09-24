import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/ongoing_call_banner.dart';
import '../services/call_events.dart';
import '../services/call_history_store.dart';
import '../services/presence_repository.dart';
import '../services/voicemail_repository.dart';
import 'calls_tab.dart';
import 'contacts_tab.dart';
import 'keypad_tab.dart';
import 'me_tab.dart';
import 'voicemail_tab.dart';

/// Linkus-style shell with five tabs. Tabs live in an IndexedStack so the
/// search text, scroll position and typed digits survive tab switches.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.onSetupChanged, required this.onUnpaired});

  final Future<void> Function() onSetupChanged;
  final Future<void> Function() onUnpaired;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _callsTab = 1;
  static const _voicemailTab = 3;
  static const _meTab = 4;

  /// Start on Tastatur: calling is the primary job of the app.
  int _index = 2;
  StreamSubscription<CallEvent>? _events;

  CallHistoryStore get _history => CallHistoryStore.instance;
  PresenceRepository get _presence => PresenceRepository.instance;
  VoicemailRepository get _voicemail => VoicemailRepository.instance;

  @override
  void initState() {
    super.initState();
    _events = CallEvents.instance.stream.listen((e) {
      if (e is CallHistoryChangedEvent) unawaited(_reloadHistory());
    });
    unawaited(_reloadHistory());
    // Voicemail badge and the call-flip banner (own line state) are visible
    // on every tab, so both poll for the shell's lifetime (foreground only).
    _voicemail.setPolling(true);
    _presence.setVisible(true);
  }

  @override
  void dispose() {
    _events?.cancel();
    _voicemail.setPolling(false);
    _presence.setVisible(false);
    super.dispose();
  }

  void _select(int i) => setState(() => _index = i);

  /// Local history + PBX log (the badge also counts calls missed on the
  /// desk phone). While the Anrufe tab is on screen the store itself counts
  /// new missed calls as seen and polls the PBX (CallsTab.isActive).
  Future<void> _reloadHistory() => _history.refreshAll();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: OngoingCallBanner(
        presence: _presence,
        child: IndexedStack(
          index: _index,
          children: [
            const ContactsTab(),
            CallsTab(isActive: _index == _callsTab),
            const KeypadTab(),
            VoicemailTab(isActive: _index == _voicemailTab),
            MeTab(
              isActive: _index == _meTab,
              onSetupChanged: widget.onSetupChanged,
              onUnpaired: widget.onUnpaired,
            ),
          ],
        ),
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: Listenable.merge([_history, _voicemail]),
        builder: (context, _) {
          final missed = _history.unseenMissed;
          final unheard = _voicemail.unheardCount;
          return NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _select,
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: 'Kontakte',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: missed > 0,
                  label: Text('$missed'),
                  child: const Icon(Icons.history),
                ),
                selectedIcon: const Icon(Icons.history),
                label: 'Anrufe',
              ),
              const NavigationDestination(
                icon: Icon(Icons.dialpad_outlined),
                selectedIcon: Icon(Icons.dialpad),
                label: 'Tastatur',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: unheard > 0,
                  label: Text('$unheard'),
                  child: const Icon(Icons.voicemail_outlined),
                ),
                selectedIcon: Badge(
                  isLabelVisible: unheard > 0,
                  label: Text('$unheard'),
                  child: const Icon(Icons.voicemail),
                ),
                label: 'Voicemail',
              ),
              const NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Ich',
              ),
            ],
          );
        },
      ),
    );
  }
}
