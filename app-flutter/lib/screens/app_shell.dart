import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_navigation.dart';
import '../services/call_events.dart';
import '../services/call_history_store.dart';
import '../services/directory_repository.dart';
import '../services/presence_repository.dart';
import '../services/reachability_repository.dart';
import '../services/recordings_repository.dart';
import '../services/registration_watcher.dart';
import '../services/ring_settings_repository.dart';
import '../services/voicemail_repository.dart';
import '../utils/timeline.dart';
import '../widgets/app_nav_bar.dart';
import '../widgets/ongoing_call_banner.dart';
import 'contacts_tab.dart';
import 'history_tab.dart';
import 'keypad_tab.dart';
import 'me_tab.dart';
import 'start_tab.dart';

/// Nachtwache shell: Start · Verlauf · (Wählen) · Kontakte · Ich. Tabs live
/// in an IndexedStack so search text, scroll position and typed digits
/// survive tab switches. The green "Gespräch läuft" bar sits above all tabs.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.onSetupChanged,
    required this.onUnpaired,
    AppNavigation? navigation,
    CallHistoryStore? history,
    VoicemailRepository? voicemail,
    PresenceRepository? presence,
    DirectoryRepository? directory,
    RecordingsRepository? recordings,
    ReachabilityRepository? reachability,
    RingSettingsRepository? ring,
  })  : _reachability = reachability,
        _ring = ring,
        _navigation = navigation,
        _history = history,
        _voicemail = voicemail,
        _presence = presence,
        _directory = directory,
        _recordings = recordings;

  final Future<void> Function() onSetupChanged;
  final Future<void> Function() onUnpaired;
  final AppNavigation? _navigation;
  final CallHistoryStore? _history;
  final VoicemailRepository? _voicemail;
  final PresenceRepository? _presence;
  final DirectoryRepository? _directory;
  final RecordingsRepository? _recordings;
  final ReachabilityRepository? _reachability;
  final RingSettingsRepository? _ring;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  StreamSubscription<CallEvent>? _events;

  AppNavigation get _nav => widget._navigation ?? AppNavigation.instance;
  CallHistoryStore get _history => widget._history ?? CallHistoryStore.instance;
  PresenceRepository get _presence => widget._presence ?? PresenceRepository.instance;
  VoicemailRepository get _voicemail => widget._voicemail ?? VoicemailRepository.instance;
  ReachabilityRepository get _reach => widget._reachability ?? ReachabilityRepository.instance;
  RingSettingsRepository get _ring => widget._ring ?? RingSettingsRepository.instance;

  @override
  void initState() {
    super.initState();
    _events = CallEvents.instance.stream.listen((e) {
      if (e is CallHistoryChangedEvent) unawaited(_history.refreshAll());
    });
    unawaited(_history.refreshAll());
    unawaited(RegistrationWatcher.instance.start());
    // The Verlauf badge (missed + voicemail) and the call-flip card (own
    // line state) poll for the shell's lifetime (foreground only).
    _voicemail.setPolling(true);
    _presence.setVisible(true);
    // Start pill ("Stumm bis …") and the amber dot on Ich.
    WidgetsBinding.instance.addObserver(this);
    unawaited(_ring.load());
    unawaited(_reach.refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_reach.refresh());
  }

  @override
  void dispose() {
    _events?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _voicemail.setPolling(false);
    _presence.setVisible(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _nav,
      builder: (context, _) {
        final tab = _nav.tab;
        return Scaffold(
          body: OngoingCallBanner(
            child: IndexedStack(
              index: tab.index,
              children: [
                StartTab(
                  directory: widget._directory,
                  presence: _presence,
                  voicemail: _voicemail,
                  history: _history,
                  navigation: _nav,
                  ring: _ring,
                  reachability: _reach,
                ),
                HistoryTab(
                  isActive: tab == AppTab.history,
                  store: _history,
                  voicemail: _voicemail,
                  recordings: widget._recordings,
                  directory: widget._directory,
                  presence: _presence,
                  navigation: _nav,
                ),
                KeypadTab(directory: widget._directory, presence: _presence),
                ContactsTab(repository: widget._directory, presence: _presence, navigation: _nav),
                MeTab(
                  isActive: tab == AppTab.me,
                  recordings: widget._recordings,
                  directory: widget._directory,
                  presence: _presence,
                  ring: _ring,
                  reachability: _reach,
                  onSetupChanged: widget.onSetupChanged,
                  onUnpaired: widget.onUnpaired,
                ),
              ],
            ),
          ),
          bottomNavigationBar: ListenableBuilder(
            listenable: Listenable.merge([_history, _voicemail, _reach]),
            builder: (context, _) => AppNavBar(
              selected: tab,
              onSelect: _nav.select,
              historyBadge: historyBadgeCount(
                unseenMissed: _history.unseenMissed,
                unheardVoicemails: _voicemail.unheardCount,
              ),
              meWarning: _reach.hasProblems,
            ),
          ),
        );
      },
    );
  }
}
