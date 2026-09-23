# Phase 3: QR Provisioning & Device Management - Context

**Gathered:** 2026-08-18
**Status:** Context discussed, proceeding to planning

<domain>
## Phase Boundary

New devices are set up purely by scanning a QR code, and the HA-Phone admin can manage which devices are attached to each extension. The QR code contains a signed JWT (Ed25519) that encodes the provisioning configuration. After scanning, the app completes provisioning by registering its Push-Token and receiving device-specific SIP credentials (mTLS client certificates). No manual SIP server/port/username/password entry is required.

</domain>

<decisions>
## Implementation Decisions

### QR-Code Format & Token Design
- **QR Format:** Custom URI Scheme `haphone://provision?t=<JWT>` with HTTPS fallback (Universal Links / App Links)
- **Token Type:** JWT signed with Ed25519 key from HA-Phone developer account
- **Token Claims:** `{ sub: extension_id, purpose: provision, exp: timestamp, iat: timestamp, jti: random, app_platform: "ios"|"android", device_id: os_native_id }`
- **TTL:** 5 minutes (hard expiration, QR becomes invalid after expiry)
- **One-Time Use:** Token invalidated server-side after first successful `/provision/complete`

### Provisioning API Design
- **Auth:** Bearer JWT (`Authorization: Bearer <jwt>`) validated against HA-Phone's Ed25519 public key
- **Endpoints:**
  - `POST /api/mobile/provision/start` — Response: `{ pbx_url, sip_domain, extension, device_sip_password, transport, stun_servers, turn_servers, codecs, display_name, internal_number, config_version, expires_at, cert_bundle_pem, cert_expires_at }`
  - `POST /api/mobile/provision/complete` — Request: `{ push_token, device_id, app_platform }`; Response: `{ success: true, device_cert_fingerprint }`
  - `POST /api/mobile/device/refresh-token` — Request: `{ old_jti, new_purpose }`; Response: `{ new_jwt, new_expires_at }`
- **Error Codes:** 400 (invalid/expired token), 401 (auth failed), 403 (token already used), 429 (rate limit), 500 (server error)
- **Error Messages in UI:** `'QR-Code abgelaufen (5 Min)', 'QR-Code schon verwendet', 'Netzwerkfehler', 'Ungültige Config', 'Push-Registrierung fehlgeschlagen'`

### Device Credentials: mTLS + Cert Rotation
- **Mechanism:** TLS Client Certificate (mTLS) per device, issued by HA-Phone's own PKI
- **PKI:** Root-CA (self-signed) + Intermediate CA; CRL via HTTPS; Certificate validity 90 Tage
- **Storage:** Software-backed Keychain (iOS) / Keystore (Android); Cert + Private Key never leave device
- **Rotation:** Automatisch alle 30/90 Tage via `/device/refresh-token` — neues Zertifikat wird ausgestellt, altes via CRL widerrufen
- **Fallback:** Bei Zertifikats-Validierungsschritt auf Passwort-authenticated SIP-REGISTER (Phase 4+) als Fallback bei Zertifikatsfehlern

### Device Identity & Multi-Device
- **Device-ID:** iOS `identifierForVendor` (IDFV) + Android `Settings.Secure.ANDROID_ID` (API 26+ stabil pro App-Signing-Key+User+Gerät)
- **1 Gerät = 1 Extension (1 SIP-Identität)** — Matcht Dashboard-Model, sicherer, simpler
- **Multi-Device pro Extension:** Alle Geräte klingeln bei Anruf; Erstannahme gewinnt; andere per Abbruch-Push (serverseitig autoritativer Call-State in HA-Phone) stoppen — Phone 2/3/4 sind separate Devices (jeweils eigene Device-ID + eigenes mTLS-Cert), aber derselben Extension zugeordnet
- **Gerätewechsel:** Admin sperrt/liest altes Gerät im Dashboard → Nutzer scannt neuen QR (neue Provisioning = neues Cert + neues Device-ID). Kein Backup/Restore von Credentials. Optional später: 'Gerät migrieren' mit Migration-Token + Biometrie + Admin-Freigabe

### Push-Token-Registrierung
- **Ablauf:** Nach QR-Scan + `/provision/start` konfiguriert App ihre APNs-/FCM-Token bei HA-Phone
- **iOS:** PushKit VoIP-Push via `PKPushRegistry`; Token wird an HA-Phone Relay gesendet
- **Android:** High-Priority FCM data-only message via `FirebaseMessagingService.onMessageReceived()`; App baut eigene CallStyle/Telecom-Notification
- **Validierung:** HA-Phone speichert Device+Platform+Push-Token Bindung; bei erneutem Scan desselben Geräts wird bestehendes Token bevorzugt (kein Doppel-Registration)

### Dashboard-UI & Aktionen
- **'Mobilgerät hinzufügen':** Extension auswählen (Dropdown) + Gerätename (frei) + optionale Notiz + Button 'QR-Code erzeugen'
- **Geräte-Liste pro Extension:** Spalten: Gerätename, Plattform, Status (Online/Offline/Push-OK), Letzter Kontakt, Zertifikat-Ablauf (Tage verbleibend), Aktionen: Sperren, Löschen, Re-Provisionieren, Push-Test, Zert. erneuern
- **Status-Indikatoren:** Grün (Online + Push OK), Gelb (Online aber Push-Probleme), Rot (Offline)
- **Sperren:** Setzt Device-Status auf 'gesperrt' — klingelt bei nächsten Anruf nicht mehr; Admin kann entsperren
- **Löschen:** Setzt Device-Status auf 'gelöscht' — wird aus Extension entfernt; mTLS-Cert via CRL widerrufen
- **Push-Test:** Sofort versand von signiertem Test-Push (Event-Type=test) an Gerät; App zeigt Toast/Notification 'Test-Push empfangen'; Ergebnis im Dashboard (Success/Timeout)
- **Zertifikat erneuern:** Trigger für `/device/refresh-token`; neues Zertifikat wird heruntergeladen und in Keychain/Keystore installiert

### Cross-Plattform-Implementierung
- Getrennte native Apps (Swift/SwiftUI, Kotlin/Jetpack Compose) — konsistent mit Phase 1/2 Entscheidung
- Kein KMP — shared Business Logic nicht gewünscht
- Beide Apps aus **EINEM OpenAPI-Schema** (HA-Phone Backend) generiert:
  - Kotlin: `openapi-generator` (Maven/Gradle Plugin) → Retrofit + Moshi / Kotlinx.Serialization
  - Swift: `swift-openapi-generator` (Apple-offiziell) → URLSession / AsyncHTTPClient
- API-Änderungen → Schema ändern → CI regeneriert beide Clients → Compile-Fehler zeigen Breaking Changes
- Shared Data Models als separate Type-Definitions-Dateien (nicht runtime-shared)

### Fehlerbehandlung & Edge Cases
- **Abgelaufener QR-Code:** UI zeigt 'QR-Code abgelaufen (5 Min)' + 'Neu scannen' Button
- **Schon genutzter QR-Code:** UI zeigt 'QR-Code schon verwendet' + 'Neu scannen' Button (Admin kann im Dashboard neue Tokens erzeugen)
- **Netzwerkfehler:** Retry-Button startet `/provision/start` neu; Offline-Queue speichert Config-Request für später (App im Vordergrund/Background)
- **Push-Registrierung fehlgeschlagen:** App zeigt detaillierten Fehler (APNs/FCM Specifc); User kann in App-Einstellungen Push-Berechtigungen neu erteilen; 'Retry' Button probiert es erneut
- **Ungültige Config:** App zeigt welche Felder fehlerhaft sind (Pbx-URL Format, Extension-Nummer Bereich); 'Neu scannen' resetet und fängt von vorne an

</decisions>

<canonical_refs>
## Canonical References (MANDATORY for downstream agents)

### Phase-Decision Docs
- `.planning/phases/01-push-wakeup-proof-of-concept/01-CONTEXT.md` — D-11 (zero-budget constraint, directly extended by D-15/D-16/D-17/D-18 here)
- `.planning/phases/01-push-wakeup-proof-of-concept/01-PHASE-SIGNOFF.md` — Sign-off pattern D-17 explicitly replicates
- `.planning/phases/02-pjsip-audio-media-core/02-CONTEXT.md` — D-09 (mid-call network-switch in scope), D-15/D-16/D-17/D-18 (iOS verification gaps)
- `.planning/PROJECT.md` — Constraints section (native Swift/Kotlin, no Flutter/RN; Tailscale transport-only Phase 5)
- `.planning/REQUIREMENTS.md` — PROV-01, PROV-02, PROV-03 requirements + traceability table
- `.planning/ROADMAP.md` — Phase 3: QR Provisioning & Device Management (goal, success criteria)

### Technical Specs
- `.planning/research/STACK.md` — PJSIP build guidance, PushKit/CallKit and FCM/Telecom library choices, what NOT to use
- `.planning/research/PITFALLS.md` — Hard platform rules for this phase: mTLS PKI setup, CRL management, OS-native device IDs, OpenAPI codegen for native apps

### Prior Phase Decisions (Carried Forward)
- D-11 from Phase 1 (zero-budget Apple Developer constraint) → extended by D-15/D-16/D-17/D-18 here
- D-04/D-05 from Phase 1 (test-trigger boundary, superseded now that real SIP/media exists via Phase 2)
- Zero-budget constraint (no paid Apple Developer Program, no paid Google Play Console) directly shapes UI/UX decisions

### HA-Phone Box (cross-repo, real Asterisk backend)
- `~/projects/Ha-Phone/ha-phone/backend/models.py` — `transport` field, extension model; D-06's TLS/SRTP decision applies
- `~/projects/Ha-Phone/ha-phone/backend/routers/extensions.py` — current extension provisioning hardcodes `transport=udp`; D-06 requires changes for new test extension with TLS/SRTP
- `~/projects/Ha-Phone/ha-phone/backend/conf_templates/pjsip_extensions.conf.j2`, `pjsip_trunk.conf.j2` — Asterisk PJSIP config templates the test extension's TLS setup will need to follow/extend
- HA-Phone backend API: `POST /api/mobile/provision/start`, `POST /api/mobile/provision/complete`, `POST /api/mobile/device/register`, `POST /api/mobile/device/refresh-token`, `POST /api/mobile/device/revoke` — OpenAPI schema resides here

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `android-app/app/src/main/java/de/haphone/app/test/sip/SipCallController.kt` — Android SIP Call Controller, already exposes transient registration logic (CALL-05)
- `android-app/app/src/main/java/de/haphone/app/test/CallRegistration.kt` — wraps `CallsManager`, self-managed Telecom registration; PJSIP audio hooks into `onRegistered` callback
- `ios-app/HAPhoneTestApp/Sip/SipCallController.swift` — iOS equivalent; PJSIP audio session setup coordinated with CallKit's `didActivate:`/`didDeactivate:` audio session callbacks
- `android-app/app/src/main/java/de/haphone/app/test/HAPhoneTestApplication.kt` — Test app context; local.properties → BuildConfig fields for HA-Phone host, SIP test extension creds (not hardcoded)
- `ios-app/HAPhoneTestApp/Secrets.xcconfig` → Info.plist `(SIP_TEST_*)` substitution → Bundle.main (not hardcoded Swift literals); mirrors Android local.properties → BuildConfig pattern

### Established Patterns
- Zero-budget constraint — keine Paid-Apple/Google Kosten für Phase 3 (alles via Simulator/Emulator + Free-Tier Firebase)
- Phase sign-off pattern (`0N-PHASE-SIGNOFF.md`) — trägt akzeptierte, undone-but-not-hidden gaps nach vorn
- OpenAPI-Codegen aus HA-Phone Backend schema — verhindert API-Drift zwischen iOS und Android

### Integration Points
- Android: `CallRegistration.reportIncomingCall`'s `onRegistered` callback ist where PJSIP media/audio setup attaches; mTLS Cert installiert in `KeyStore` vor ersten Registrierungsversuch
- iOS: `CallProvider.swift`'s CXProvider delegate callbacks (`didActivate`/`didDeactivate` on `AVAudioSession`) sind where PJSIP's audio session must plug in; mTLS Cert in `Keychain` installiert vor ersten Verbindungsversuch
- HA-Phone backend: new dedicated provisioning endpoints (`/api/mobile/provision/...`) need to be added before app-side code can call them; `/device/refresh-token` for cert rotation; device model fields updated (`transport: "tls"`, `media_encryption: "srtp"`)
- Push-Relay: Phase 6 (Multi-Tenant Push-Relay Formalization) hängt von dieser Phase ab — Provisioning-Flow definiert das Device-Token-Format, das an den Relay weitergegeben wird

</code_context>

<specifics>
## Specific Ideas

- Dialpad UI component designed for three reuse contexts from day one: outgoing-call dialing, in-call DTMF, and blind-transfer target entry — one component, three call sites. Same principle applies to provisioning: QR-Scanner-Logic + Config-Parsing + Push-Reg-Logic ist ein Building Block für den gesamten Device-Lifecycle.

- Device-ID sollte OS-nativ (IDFV/ANDROID_ID) bleiben anstelle einer eigenen UUID-Generierung — überlebt Neuinstallationen naturgemäß und erfordert keine Extra-Permission. Falls doch UUID benötigt wird: Fallback in Keychain/Keystore mit explizitem Hinweis, dass Android Keystore bei Deinstallation gelöscht wird.

- mTLS-Zertifikate mit 90-Tage-Lebensdauer + automatische Rotation via `/device/refresh-token` ist der "sweet spot" für v1: stark genug für Security-Requirements, aber komplexer als reines Passwort-Handling (das in Phase 4+ als Fallback bleibt).

</specifics>

<deferred>
## Deferred Ideas

- Nicht-Pixel Android OEM Testabdeckung (Samsung/Xiaomi) — deferred bis geeignetes Gerät verfügbar; nicht für v1 priorisiert
- Full contacts/address book für Dialing — gehört zu Phase 3 (QR Provisioning), aber Device-ID + Multi-Device sind Phase 3-Kern; Contacts kommen später (Phase 4/5)
- Automatisierte Regressionstest für transienten SIP-Registration — manuelle Verifizierung (D-10 hier) ist akzeptiert für Phase 2; automatisierter Guard wurde jetzt nicht adoptiert (kein explizites zukünftiges Phase zugewiesen — könnte in Phase 5/6 nachgerbeitet werden)
- Backup/Restore von App-Daten inklusive Credentials via iCloud/Google Drive — Sicherheitsrisiko (Backup-Zugriff = Credentials-Zugriff); Keychain Sync nur bei gleicher Apple ID; Android Keystore nicht sync-fähig — deferred bis Nutzer explizit danach fragt
- 'Gerät migrieren' Flow mit einmaligem Migration-Token — Optional für Phase 4+; Standard ist Neu-Provisionierung (sicherer)

### Reviewed Todos (not folded)
None — keine pending todos matched Phase 3's scope (`todo.match-phase` returned zero matches).

</deferred>

---

*Phase: 3-QR-Provisioning-Device-Management*
*Context gathered: 2026-08-18*