import 'package:flutter/material.dart';

import '../widgets/dialer_view.dart';

/// Tastatur tab.
class KeypadTab extends StatelessWidget {
  const KeypadTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tastatur')),
      body: const DialerView(),
    );
  }
}
