# Requirements: HA-Phone App

**Defined:** 2026-07-31
**Core Value:** Ein eingehender Anruf klingelt zuverlässig über die native Anrufoberfläche, egal ob die App geschlossen oder das Gerät gesperrt ist — ohne dauerhaft laufende SIP-Verbindung oder VPN-Tunnel im Hintergrund.

## v1 Requirements

Requirements für die erste Version. Jede wird auf Roadmap-Phasen abgebildet.

### Erreichbarkeit & Call-UI (PUSH)

- [x] **PUSH-01**: iOS-VoIP-Push (PushKit) weckt die App zuverlässig, auch wenn sie vollständig beendet ist
- [x] **PUSH-02**: iOS CallKit meldet den eingehenden Anruf sofort nativ (innerhalb der Apple-Frist, jeder VoIP-Push wird gemeldet)
- [x] **PUSH-03**: Android High-Priority-FCM weckt die App zuverlässig, auch im Hintergrund oder bei gesperrtem Gerät
- [x] **PUSH-04**: Android zeigt den eingehenden Anruf über ein selbstverwaltetes ConnectionService/PhoneAccount mit CallStyle-Notification und Full-Screen-Intent (inkl. Play-Console-"Calling App"-Deklaration)

### Telefonie (CALL)

- [x] **CALL-01**: Audioanruf funktioniert stabil (Opus/G.722/G.711, Mikrofon, Lautsprecher, Bluetooth-Routing)
- [x] **CALL-02**: DTMF im laufenden Gespräch (RFC 2833/4733)
- [x] **CALL-03**: Ausgehende Anrufe sind möglich
- [x] **CALL-04**: Anruf halten und blinde Weiterverbindung
- [x] **CALL-05**: Nach Annahme baut die App die SIP-Verbindung transient auf (kein dauerhaftes Halten der Registrierung im Hintergrund)

### Provisionierung & Geräteverwaltung (PROV)

- [ ] **PROV-01**: Einrichtung der App erfolgt ausschließlich per QR-Code-Scan — keine manuelle Eingabe von SIP-Server/Port/User/Passwort
- [ ] **PROV-02**: HA-Phone-Dashboard bietet "Mobilgerät hinzufügen": erzeugt zeitlich begrenzten Einmal-Provisionierungs-Token + QR-Code
- [ ] **PROV-03**: Geräteverwaltung pro Nebenstelle im HA-Phone-Dashboard (Liste, Status, Sperren, Löschen, Re-Provisionierung)
- [ ] **PROV-04**: Mehrere Mobilgeräte pro Nebenstelle: alle klingeln, Erstannahme gewinnt, andere Geräte werden per Abbruch-Push sofort gestoppt (serverseitig autoritativer Call-State in HA-Phone)

### Türstation (DOOR)

- [ ] **DOOR-01**: Video-Vorschau/Snapshot einer Türstation (Akuvox) wird angezeigt, bevor der Anruf angenommen wird — kurzlebiger, signierter Link getrennt vom Push-Payload
- [ ] **DOOR-02**: Türöffner-Aktion aus der App heraus, mit optionaler Biometrie-Bestätigung (Face ID/Touch ID/Geräte-PIN)

### Betrieb & Infrastruktur (OPS)

- [ ] **OPS-01**: Diagnose-Statusseite in der App (Push-Registrierung, SIP-Status, Berechtigungen, letzter Test-Push, letzter Anruf)
- [ ] **OPS-02**: Zentraler Push-Relay-Dienst mit eigenen APNs-/FCM-Credentials nimmt signierte Call-Events von HA-Phone-Boxen entgegen und leitet sie weiter (kann in Phase 1 durch direkte APNs/FCM-Calls von der eigenen Box gestubbt werden, muss aber vor Multi-Install-Nutzung fertig sein)
- [ ] **OPS-03**: Tailscale wird als Medien-Transportschicht genutzt — Nutzer hinterlegt seinen Tailscale-Account einmal in App und HA-Phone, Verbindung für SIP/RTP wird bei Bedarf automatisch (ephemer, nicht dauerhaft) aufgebaut

## v1.x Requirements

Bewusst nach v1 verschoben, um das Risiko im MVP klein zu halten (Research-Empfehlung).

### Telefonie-Erweiterungen

- **CALL-06**: Attended Call Transfer (Consult + Merge)
- **CALL-07**: Anrufliste-Synchronisierung aus PBX-CDR (lokale Anrufliste reicht für v1)
- **CALL-08**: Favoriten / Kurzwahl

### Türstation-Erweiterungen

- **DOOR-03**: Snapshot aus der Türvorschau speichern (erfordert administrativ freigeschaltete Berechtigung)

### Netzwerk-Härtung

- **OPS-04**: Vertiefte Netzwerkwechsel-Härtung (WLAN↔Mobilfunk-Edge-Cases über die v1-Grundfunktion hinaus)

## v2 Requirements

Anerkannt, aber noch nicht im Blick für die Roadmap.

### Erweiterte Integration

- **FUT-01**: Allgemeine SIP-Videotelefonie (blockiert auf HA-Phones eigener PBX-seitiger Video-Roadmap)
- **FUT-02**: Multi-PBX-Account-Switching innerhalb einer App-Installation
- **FUT-03**: Weitere Home-Assistant-Aktionen über den Türöffner-Webhook hinaus
- **FUT-04**: Weitere Türstations-Hersteller (2N, DoorBird, Fanvil) — aktuell nur Akuvox vorhanden/testbar

## Out of Scope

Explizit ausgeschlossen. Dokumentiert, um Scope Creep zu verhindern.

| Feature | Reason |
|---------|--------|
| Generisches "beliebigen SIP-Server eintragen"-Modus | Widerspricht der Architektur: zuverlässiges Push-Wecken, QR-Provisionierung und Geräte-Widerruf hängen an der festen Kopplung zur HA-Phone-eigenen Backend/Push-Relay. Ein generischer Modus bringt exakt das "Dauerregistrierung/unzuverlässiges Wecken"-Problem zurück, das dieses Projekt lösen soll |
| Reine Web-/PWA-Umsetzung | Kann VoIP-Push, native CallKit/Telecom-Integration und zuverlässiges Klingeln bei gesperrtem Gerät technisch nicht leisten |
| WebRTC/SBC/Cloud-PBX-Szenarien | Folgt HA-Phones eigener Roadmap-Priorität, dort bewusst zurückgestellt |
| Mehrere Admin-Rollen, Mandantenfähigkeit | Kein Bedarf für die Zielgruppe (kleine, selbstgehostete Installationen) |
| Tailscale/VPN als Wake-up-Mechanismus (dauerhafter Hintergrund-Tunnel) | Widerspricht dem Grundprinzip Push-statt-Dauerverbindung; Tailscale wird ausschließlich als Medien-Transportschicht genutzt |
| Enterprise-Callcenter-Features (Queues/Wallboard, Call-Recording, CRM-Integration, Presence-Föderation) | Irrelevant für die Zielgruppe (Home-Office/Kleinbetrieb), hohe Komplexität für nahezu keinen Wert, teils Datenschutz-/Consent-Konflikt |
| Manuelle SIP-Zugangsdaten-Eingabe als "Advanced Mode"-Fallback | Untergräbt exakt das Sicherheitsmodell, das die QR-Provisionierung herstellen soll |
| Vollständige Anrufaufzeichnung / Cloud-Transkripte / KI-Zusammenfassungen | Rechtliche Komplexität (Aufzeichnungsgesetze variieren), widerspricht der expliziten Datenschutz-Haltung des Projekts |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| PUSH-01 | Phase 1 | Complete |
| PUSH-02 | Phase 1 | Complete |
| PUSH-03 | Phase 1 | Complete |
| PUSH-04 | Phase 1 | Complete |
| CALL-01 | Phase 2 | Complete |
| CALL-02 | Phase 2 | Complete |
| CALL-03 | Phase 2 | Complete |
| CALL-04 | Phase 2 | Complete |
| CALL-05 | Phase 2 | Complete |
| PROV-01 | Phase 3 | Pending |
| PROV-02 | Phase 3 | Pending |
| PROV-03 | Phase 3 | Pending |
| PROV-04 | Phase 4 | Pending |
| OPS-01 | Phase 4 | Pending |
| OPS-03 | Phase 5 | Pending |
| OPS-02 | Phase 6 | Pending |
| DOOR-01 | Phase 7 | Pending |
| DOOR-02 | Phase 7 | Pending |

**Coverage:**
- v1 requirements: 18 total
- Mapped to phases: 18
- Unmapped: 0 ✓

---
*Requirements defined: 2026-07-31*
*Last updated: 2026-08-01 after roadmap creation (7 phases, 100% coverage)*
</content>
</invoke>
