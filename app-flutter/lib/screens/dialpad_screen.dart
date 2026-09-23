import 'package:flutter/material.dart';

import '../widgets/dialer_view.dart';

/// Standalone '/dialpad' route (kept for existing callers); the main entry
/// point is the Tastatur tab, which shows the same [DialerView].
class DialpadScreen extends StatelessWidget {
  const DialpadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Anrufen')),
      body: const SafeArea(child: DialerView()),
    );
  }
}
