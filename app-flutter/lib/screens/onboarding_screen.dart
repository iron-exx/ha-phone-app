import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// First screen when the device isn't provisioned yet. QR pairing is the
/// intended path; manual SIP entry is only a fallback, hence the small button.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key, required this.onScanQr, required this.onManualSetup});

  final VoidCallback onScanQr;
  final VoidCallback onManualSetup;

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
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
                    color: c.blue,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [BoxShadow(color: c.blue.withOpacity(0.28), blurRadius: 30, offset: const Offset(0, 10))],
                  ),
                  child: Icon(Icons.phone_in_talk, size: 50, color: c.blueInk),
                ),
              ),
              const SizedBox(height: 28),
              Text('HA-Phone', textAlign: TextAlign.center, style: NwType.display(40).copyWith(color: c.text)),
              const SizedBox(height: 12),
              Text(
                'Scannen Sie den QR-Code aus der HA-Phone-Verwaltung '
                '(Nebenstelle → „HA-Phone App QR“), um dieses Handy zu koppeln.',
                textAlign: TextAlign.center,
                style: NwType.rowTitle.copyWith(color: c.muted, fontWeight: FontWeight.w500, height: 1.45),
              ),
              const Spacer(flex: 3),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
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
