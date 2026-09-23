import 'package:flutter/material.dart';

/// First screen when the device isn't provisioned yet. QR pairing is the
/// intended path; manual SIP entry is only a fallback, hence the small button.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key, required this.onScanQr, required this.onManualSetup});

  final VoidCallback onScanQr;
  final VoidCallback onManualSetup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Icon(Icons.phone_in_talk, size: 52, color: theme.colorScheme.onPrimary),
                ),
              ),
              const SizedBox(height: 28),
              Text('HA-Phone', textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
              const SizedBox(height: 12),
              Text(
                'Scannen Sie den QR-Code aus der HA-Phone-Verwaltung '
                '(Nebenstelle → „HA-Phone App QR“), um dieses Handy zu koppeln.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const Spacer(flex: 3),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('QR-Code scannen'),
                onPressed: onScanQr,
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: onManualSetup, child: const Text('Manuell einrichten')),
            ],
          ),
        ),
      ),
    );
  }
}
