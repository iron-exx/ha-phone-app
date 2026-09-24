import 'package:flutter/material.dart';

import '../services/directory_repository.dart';
import '../services/presence_repository.dart';
import '../widgets/dialer_view.dart';

/// Wählen tab (the raised centre button of the bottom bar).
class KeypadTab extends StatelessWidget {
  const KeypadTab({super.key, this.directory, this.presence});

  final DirectoryRepository? directory;
  final PresenceRepository? presence;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(bottom: false, child: DialerView(directory: directory, presence: presence)),
    );
  }
}
