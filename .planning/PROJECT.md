# HA-Phone App

## What This Is

Native Softphone-App für iOS und Android als offizielles Companion-Produkt zur selbstgehosteten HA-Phone-PBX (Asterisk-basiert, Home-Assistant-Add-on, https://github.com/iron-exx/HA-Phone). Löst zuverlässig eingehende Anrufe bei geschlossener/gesperrter App über VoIP-Push (APNs/FCM) aus, wird per QR-Code ohne manuelle SIP-Eingabe eingerichtet und zeigt bei Türstationen (z.B. Akuvox) das Kamerabild bereits vor Annahme des Anrufs. Gebaut nicht als generisches SIP-Softphone, sondern fest an HA-Phone gekoppelt — und von Anfang an so, dass auch andere HA-Phone-Betreiber (nicht nur der eigene Haushalt) die App gegen ihre eigene Box nutzen können.

## Core Value

Ein eingehender Anruf klingelt zuverlässig über die native Anrufoberfläche, egal ob die App geschlossen oder das Gerät gesperrt ist — ohne dauerhaft laufende SIP-Verbindung oder VPN-Tunnel im Hintergrund.

## Requirements

### Validated

- ✓ Android: High-Priority-FCM weckt die App zuverlässig, auch im Hintergrund/bei gesperrtem Gerät (inkl. echtem PIN-Sperrbildschirm und Doze) — Phase 1, verifiziert auf API-35-Emulator mit echtem Firebase-Projekt, 5 Gerätezustände, <2s Latenz
- ✓ Android: eingehender Anruf wird über Telecom-Framework / CallStyle-Notification + Full-Screen-Intent signalisiert — Phase 1, funktioniert nachweislich auch **ohne** Play-Console-Deklaration bei Sideload (D-12-Befund)
- ✓ Nativ getrennte Apps (Swift/Kotlin) sind der richtige Ansatz für Push-Wakeup/CallKit/Telecom — Phase 1, beide Wegwerf-Apps bauten und funktionierten wie erwartet, keine Cross-Platform-Kompromisse nötig

### Active

- [ ] iOS: VoIP-Push via PushKit weckt die App zuverlässig, auch wenn sie vollständig beendet ist — Phase 1 hat dies nur auf Simulator-/Unit-Test-Ebene verifiziert (`.github/workflows/ios-ci.yml`), echtes Gerät noch ungetestet; blockiert auf Entscheidung zur Apple-Developer-Program-Mitgliedschaft (99$/Jahr, D-11)
- [ ] iOS: eingehender Anruf wird sofort nativ über CallKit signalisiert — dito, Code korrekt (report-first-then-verify bestätigt), aber nur Simulator-verifiziert
- [ ] Nach Annahme baut die App im Hintergrund automatisch die SIP-Verbindung zu HA-Phone auf (kein dauerhaftes Halten der Registrierung)
- [ ] Audioanruf funktioniert stabil (Opus/G.722/G.711, Mikrofon, Lautsprecher, Bluetooth, DTMF)
- [ ] Einrichtung der App erfolgt ausschließlich per QR-Code-Scan — keine manuelle Eingabe von SIP-Server/Port/User/Passwort
- [ ] HA-Phone-Dashboard: neuer Dialog "Mobilgerät hinzufügen" erzeugt zeitlich begrenzten Einmal-Provisionierungs-Token + QR-Code
- [ ] HA-Phone verwaltet Geräte pro Nebenstelle (Liste, Status, Sperren, Löschen, Re-Provisionierung)
- [ ] Zentraler Push-Relay-Dienst (eigene APNs/FCM-Credentials) nimmt signierte Call-Events von beliebigen HA-Phone-Boxen entgegen und leitet sie an Apple/Google weiter
- [ ] Mehrere Mobilgeräte pro Nebenstelle: alle klingeln, Erstannahme gewinnt, andere werden per Abbruch-Push gestoppt
- [ ] Ausgehende Anrufe möglich
- [ ] Türstations-Erkennung (Akuvox): Vorschaubild/Snapshot wird angezeigt, bevor der Anruf angenommen wird
- [ ] Türöffner-Funktion aus der App heraus (mit optionaler Biometrie-Bestätigung)
- [ ] Diagnose-Statusseite in der App (Push-Registrierung, SIP-Status, Berechtigungen, letzter Test)
- [ ] Tailscale-Integration als Medien-Transportschicht: Nutzer trägt seinen Tailscale-Account einmal in App und HA-Phone ein, Verbindung für SIP/RTP wird dann automatisch aufgebaut (ephemer bei Bedarf, nicht dauerhaft im Hintergrund) — ersetzt manuelle STUN/TURN-Konfiguration für die Erreichbarkeit unterwegs

### Out of Scope

- Generisches SIP-Softphone mit freier Server-Konfiguration — App ist fest an HA-Phone gekoppelt, keine "beliebige SIP-Zugangsdaten eintragen"-Funktion
- Reine Web-/PWA-Umsetzung — kann VoIP-Push, CallKit und zuverlässiges Hintergrund-Klingeln technisch nicht leisten
- WebRTC/SBC/Cloud-PBX-Szenarien — folgt HA-Phones eigener Roadmap-Priorität, dort bewusst zurückgestellt
- Mehrere Admin-Rollen, Mandantenfähigkeit — kein Bedarf für die Zielgruppe (kleine Installationen)
- Tailscale als Wake-up-Mechanismus (dauerhaft laufender Hintergrund-Tunnel, der die App weckt) — widerspricht dem Grundprinzip (Push statt Dauerverbindung); Tailscale wird ausschließlich als Transportschicht für SIP/Media genutzt, ephemer nach dem Push-Wecken aufgebaut, nicht als Ersatz für APNs/FCM

## Context

- **HA-Phone** (lokal `~/projects/Ha-Phone`, Remote https://github.com/iron-exx/HA-Phone.git) ist die zugehörige PBX: Asterisk 22 LTS, FastAPI-Backend, React-Frontend, läuft als Home-Assistant-Add-on. Aktuell v0.7.7x, Nebenstellen 10-99, Trunks, Routing, Rufgruppen, IVR, Voicemail, Auto-Provisioning, Backup/Restore vorhanden. Mobile Nutzung aktuell nur via Linphone + Tailscale-VPN (README) — genau das soll diese App ablösen.
- HA-Phones eigene Roadmap (Stand Juli 2026) hat WebRTC und Videotelefonie explizit als "nicht in die nächste Phase ziehen" zurückgestellt (Stabilität/Betriebsreife hat Vorrang). Die Push-Gateway- und QR-Provisionierungs-Erweiterungen für diese App entstehen daher als **neue, zusätzliche Backend-Teile in HA-Phone**, parallel zur bestehenden HA-Phone-Roadmap, nicht als Ersetzung.
- Vollständiger ursprünglicher Entwicklungsplan liegt in `ENTWICKLUNGSPLAN.md` im Projektroot — sehr detailliert (18 Kapitel: Architektur, QR-Flow, Sicherheit, Testmatrix, Phasenplan). Dient als Referenz für Roadmap und spätere Phasenplanung.
- Akuvox-Türstation ist bereits vorhanden und kann früh als Testgerät für die Video-Vorschau-Funktion genutzt werden.
- Firebase-Projekt existiert seit Phase 1 (`haphone-e30ca`, kostenloser Spark-Tarif, App-ID `de.haphone.app.test`). Apple Developer Account existiert weiterhin nicht — Nutzer will erst den kostenlosen Nachweis abschließen, bevor investiert wird (99$/Jahr für Push-Notification-Entitlement, siehe Zero-Budget-Entscheidung unten). Bis dahin bleibt echtes iOS-Push-Testen ein offener Punkt.
- Bundle-/Package-ID ist `de.haphone.app` (nicht firmengebunden) — eine erste Version hatte fälschlich die Domain einer unrelated Firma (`systemwerk`) verwendet, wurde in Phase 1 komplett korrigiert.
- Repo für die App: https://github.com/iron-exx/ha-phone-app.git (lokal `~/projects/ha-phone-app`, Remote bereits gesetzt). Zugangstoken liegt lokal in `no-git/token.txt` (git-ignored) — Push erfolgt durch den Nutzer selbst, da die Sandbox hier keinen direkten Push zu externen Remotes erlaubt.

## Constraints

- **Tech-Stack**: Native getrennte Apps — Swift/SwiftUI (iOS) und Kotlin/Jetpack Compose (Android), kein Flutter/React Native — Entscheidung laut Plan-Empfehlung, da CallKit/Telecom/PJSIP-Integration native Zuverlässigkeit braucht
- **SIP/Media-Kern**: PJSIP/PJSUA2 als gemeinsame Grundlage auf beiden Plattformen (SIP über TLS, SRTP, ICE/STUN/TURN)
- **Backend-Kopplung**: Push-Gateway und QR-Provisionierung werden direkt in HA-Phone (FastAPI) integriert, nicht als separater Dienst — App spricht ausschließlich mit HA-Phone
- **Push-Architektur**: Zentraler, vom Projekt selbst betriebener Relay-Dienst hält die APNs-/FCM-App-Credentials; jede HA-Phone-Box sendet signierte Call-Events an diesen Relay. Kein Rückgriff auf Nabu Casa (an offizielle HA-App-Identität gebunden) oder Tailscale (löst Netzwerk-, nicht Push-Credential-Problem)
- **Budget**: Kostenlos im Betrieb angestrebt — FCM ist kostenlos, APNs-Versand ist kostenlos (nur die für die App-Veröffentlichung ohnehin nötige Apple Developer Membership, 99 $/Jahr, fällt an)
- **Zielgruppe**: Von Anfang an auch für fremde HA-Phone-Installationen gedacht (nicht nur eigener Haushalt) — beeinflusst Provisionierung, Gerätesicherheit und Relay-Design
- **Transport für SIP/Media**: Tailscale statt eigenem STUN/TURN-Aufbau — Nutzer hinterlegt seinen Tailscale-Account einmal in App und HA-Phone, Verbindung wird bei Bedarf automatisch (nicht dauerhaft) aufgebaut. Erfordert vermutlich eingebettete `tsnet`-Anbindung oder OAuth-Client/Auth-Key-basierte automatische Node-Registrierung statt der separaten Tailscale-App — technischer Ansatz wird in Architektur-Recherche vertieft

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Volle Integration in HA-Phone statt separater PBX/Dienst | Nur so lassen sich QR-Provisionierung, Gerätesperrung, Push und Anrufsteuerung sauber zentral verwalten | — Pending |
| App für fremde HA-Phone-Nutzer gedacht, nicht nur Eigenbedarf | Größere Zielgruppe von Anfang an mitdenken, spart spätere Migration | — Pending |
| Nativ getrennte Apps (Swift/Kotlin) statt Cross-Platform-Framework | Zuverlässigkeit bei Push-Wakeup/CallKit/Telecom hat Priorität vor gemeinsamer UI-Codebasis | ✓ Good — Phase 1 bestätigt: beide Wegwerf-Apps bauten und funktionierten unabhängig voneinander |
| Zentraler eigener Push-Relay-Dienst statt Nabu Casa/Tailscale | Push-Credentials sind an App-Identität gebunden, nicht an Netzwerk-Erreichbarkeit — Nabu Casa/Tailscale lösen das falsche Problem | — Pending (Relay kommt erst Phase 6) |
| Phase-1-Priorität: Push-Wakeup vor QR-Provisionierung vor Video | Reihenfolge aus dem ursprünglichen Entwicklungsplan — Erreichbarkeit ist das Kernproblem, das zuerst bewiesen werden muss | ✓ Good — Phase 1 hat genau das bewiesen (Android vollständig, iOS strukturell) |
| Tailscale als Medien-Transportschicht statt eigenem STUN/TURN | Nutzer will Erreichbarkeit unterwegs ohne eigenen TURN-Server; Tailscale übernimmt NAT-Traversal. Push bleibt strikt getrennt als Wake-up-Mechanismus, Tailscale wird nur ephemer für die SIP/Media-Verbindung genutzt | — Pending (erst Phase 5) |
| Zero-Budget-Teststrategie für Phase 1 (kein Apple Developer Program, kein Google Play Developer Account) | Nutzer will den Nachweis "funktioniert" kostenlos erbringen, bevor Geld investiert wird | ✓ Good — Android vollständig kostenlos bewiesen (Emulator + Firebase-Free-Tier); iOS-Lücke (echtes Gerät) ist explizit dokumentiert, kein Blocker für Phase 2 |
| KVM-Android-Emulator statt physischem Pixel für den Gerätetest | Nutzer wollte kein Telefon anschließen; Emulator mit Google-APIs-Image liefert echte FCM-Tokens/echte Zustellung, OEM-Stromsparverhalten bleibt separat als Lücke dokumentiert (D-03) | ✓ Good — alle 5 Gerätezustände inkl. echter PIN-Sperre erfolgreich getestet |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-08-03 after Phase 1 (Push-Wakeup Proof of Concept) completion*
