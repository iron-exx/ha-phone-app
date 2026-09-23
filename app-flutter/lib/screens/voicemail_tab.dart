import 'package:flutter/material.dart';

import '../services/call_launcher.dart';

/// Mailbox access number. The HA-Phone dialplan has no VoiceMailMain
/// feature code yet (checked backend/conf_templates), so this is the
/// planned default; change it here once the PBX defines one.
const kVoicemailNumber = '*97';

/// Voicemail tab. Visual voicemail needs /api/mobile/voicemail (Phase 3).
class VoicemailTab extends StatelessWidget {
  const VoicemailTab({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Voicemail')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.voicemail, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                'Visuelle Voicemail kommt mit dem nächsten Update',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Bis dahin erreichen Sie Ihre Mailbox per Anruf.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.call),
                label: const Text('Mailbox anrufen'),
                onPressed: () => CallLauncher.call(context, kVoicemailNumber),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
