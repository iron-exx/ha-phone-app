import 'dart:async';

import 'package:flutter/material.dart';

import '../services/call_events.dart';
import '../services/call_history_store.dart';
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

  /// Start on Tastatur: calling is the primary job of the app.
  int _index = 2;
  StreamSubscription<CallEvent>? _events;

  CallHistoryStore get _history => CallHistoryStore.instance;

  @override
  void initState() {
    super.initState();
    _events = CallEvents.instance.stream.listen((e) {
      if (e is CallHistoryChangedEvent) unawaited(_reloadHistory());
    });
    unawaited(_reloadHistory());
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  /// While the Anrufe tab is on screen, new missed calls count as seen.
  Future<void> _reloadHistory() async {
    await _history.load();
    if (_index == _callsTab) await _history.markSeen();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const ContactsTab(),
          CallsTab(isActive: _index == _callsTab),
          const KeypadTab(),
          const VoicemailTab(),
          MeTab(onSetupChanged: widget.onSetupChanged, onUnpaired: widget.onUnpaired),
        ],
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: _history,
        builder: (context, _) {
          final missed = _history.unseenMissed;
          return NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
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
              const NavigationDestination(
                icon: Icon(Icons.voicemail_outlined),
                selectedIcon: Icon(Icons.voicemail),
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
