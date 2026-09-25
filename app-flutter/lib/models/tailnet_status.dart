/// State of the embedded Tailscale tunnel ("Unterwegs erreichbar"), as reported by
/// the native TailnetManager.status().
class TailnetStatus {
  const TailnetStatus({
    required this.configured,
    this.consentNeeded = false,
    this.running = false,
    this.revoked = false,
    this.state = -1,
    this.selfIp,
    this.pbxIp,
    this.direct,
    this.loginUrl,
    this.error,
  });

  factory TailnetStatus.fromMap(Map<Object?, Object?> m) => TailnetStatus(
        configured: m['configured'] == true,
        consentNeeded: m['consentNeeded'] == true,
        running: m['running'] == true,
        revoked: m['revoked'] == true,
        state: (m['state'] as num?)?.toInt() ?? -1,
        selfIp: m['selfIp'] as String?,
        pbxIp: m['pbxIp'] as String?,
        direct: m['direct'] as bool?,
        loginUrl: m['loginUrl'] as String?,
        error: m['error'] as String?,
      );

  static const off = TailnetStatus(configured: false);

  /// ipn.State values (tailscale.com/ipn).
  static const stateNeedsLogin = 2;
  static const stateStarting = 5;

  final bool configured;
  final bool consentNeeded;
  final bool running;
  final bool revoked;
  final int state;
  final String? selfIp;
  final String? pbxIp;
  final bool? direct;
  final String? loginUrl;
  final String? error;
}

/// What the reachability row shows. [action] null = nothing to do.
class TailnetRowText {
  const TailnetRowText({required this.ok, required this.detail, this.action});
  final bool ok;
  final String detail;
  final String? action;
}

TailnetRowText describeTailnet(TailnetStatus s) {
  if (s.running) {
    final via = switch (s.direct) {
      true => 'direkt verbunden',
      false => 'über Tailscale-Relay',
      null => 'verbunden',
    };
    return TailnetRowText(ok: true, detail: 'Über Tailscale $via${s.selfIp != null ? ' · ${s.selfIp}' : ''}');
  }
  if (s.revoked) {
    return const TailnetRowText(
      ok: false,
      detail: 'Ein anderes VPN ist aktiv. Unterwegs nicht erreichbar, im WLAN zu Hause schon.',
      action: 'Verbinden',
    );
  }
  if (s.consentNeeded) {
    return const TailnetRowText(
      ok: false,
      detail: 'Einmal die VPN-Verbindung erlauben, dann bist du auch unterwegs erreichbar.',
      action: 'Einrichten',
    );
  }
  if (s.loginUrl != null || s.state == TailnetStatus.stateNeedsLogin) {
    return const TailnetRowText(
      ok: false,
      detail: 'Bei Tailscale anmelden und „Connect“ tippen.',
      action: 'Anmelden',
    );
  }
  if (s.error != null) {
    return TailnetRowText(ok: false, detail: 'Tailscale: ${s.error}', action: 'Erneut');
  }
  return const TailnetRowText(ok: false, detail: 'Verbindet mit Tailscale …', action: 'Verbinden');
}
