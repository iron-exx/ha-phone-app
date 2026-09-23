# Phase 3: QR Provisioning & Device Management - Discussion Log

**Phase:** 3-QR-Provisioning-Device-Management
**Discussion Date:** 2026-08-18
**Discussion Mode:** Default (interactive)

## Areas Discussed & Decisions

### 1. QR-Code Format & Inhalt
- **Decision:** Custom URI Scheme `haphone://provision?t=<JWT>` with HTTPS fallback (Universal Links / App Links)
- **Token:** JWT (Ed25519 signiert), selbstvalidierend, kein Server-State nötig
- **TTL:** 5 Minuten harte Expiration
- **One-Time-Use:** Token serverseitig nach erstmaligem erfolgreichem `/provision/complete` invalidiert
- **Gray Areas Remaining:** Exact JWT Claims-Struktur (sub, purpose, exp, iat, jti, app_platform, device_id) — wurde aber im Kontext festgelegt

### 2. Provisioning API (Backend)
- **Auth:** Bearer JWT (`Authorization: Bearer <jwt>`) validiert gegen HA-Phone Ed25519 Public Key
- **Endpunkte:**
  - `POST /api/mobile/provision/start` → vollständige Device-Config zurückliefern
  - `POST /api/mobile/provision/complete` → Push-Token + Device-ID registrieren
  - `POST /api/mobile/device/refresh-token` → Token-Rotation (neues Zertifikat)
- **Response-Format:** Vollständige Device-Config inkl. mTLS-Zertifikats-Bundle, Ablaufdaten, Codecs, STUN/TURN
- **Error Handling:** Klare Fehlermeldungen im UI pro Fehlerart (abgelaufen, schon genutzt, Netzwerk, Config ungültig, Push-Reg fehlgeschlagen)

### 3. Sicherheit: Token & Geräte-Credentials
- **Token:** JWT (Ed25519), 5 Min TTL, selbstvalidierend, kein Server-State
- **Geräte-Credentials:** mTLS (TLS-Client-Zertifikat pro Gerät) mit HA-Phone-eigener Root-CA + Intermediate
- **CA:** Einfache Root-CA (selbstsigniert) + Intermediate; CRL als Datei via HTTPS; Zert-Lebensdauer 90 Tage
- **Rotation:** Automatische Zertifikats-Rotation (Re-Issue) alle 30/90 Tage via `/device/refresh-token`
- **Speicherung:** Software-backed Keychain (iOS) / Keystore (Android) — nicht hardware-backed
- **Passwort-Fallback:** In Phase 4+ als Fallback bei Zertifikatsfehlern (nicht v1 Standard)

### 4. HA-Phone Dashboard UI
- **'Mobilgerät hinzufügen':** Extension auswählen (Dropdown) + Gerätename (frei) + optionale Notiz + Button 'QR-Code erzeugen'
- **Geräte-Liste pro Extension:** Spalten: Name, Plattform, Status (Online/Offline/Push-OK), Letzter Kontakt, Zertifikat-Ablauf (Tage), Aktionen: Sperren, Löschen, Re-Provisionieren, Push-Test, Zert. erneuern
- **Status-Indikatoren:** Grün (Online + Push OK), Gelb (Online aber Push-Probleme), Rot (Offline)
- **Sperren:** Device-Status auf 'gesperrt' setzen — klingelt bei nächsten Anruf nicht mehr
- **Löschen:** Device-Status auf 'gelöscht' setzen — aus Extension entfernen; mTLS-Cert via CRL widerrufen
- **Push-Test:** Sofort versand von signiertem Test-Push (Event-Type=test); App zeigt Toast/Notification; Ergebnis im Dashboard (Success/Timeout)
- **Zertifikat erneuern:** Trigger für `/device/refresh-token`; neues Zertifikat herunterladen und in Keychain/Keystore installieren

### 5. App-seitiger Provisioning-Flow
- **QR-Scanner:** Eigener Scanner-Screen (Kamera-Vorschau + Overlay-Rahmen); nach Scan: Token-Validierung → `/provision/start` → Config speichern → Push-Token registrieren → `/provision/complete` → Success-Screen
- **Fehlerfälle:** Spezifische Toasts/Alerts pro Fehlerart — jeweils mit 'Erneut scannen' / 'Retry' Button
- **Push-Token-Registrierung:** iOS: PushKit VoIP-Push via `PKPushRegistry`; Android: High-Priority FCM data-only via `FirebaseMessagingService.onMessageReceived()`

### 6. Cross-Plattform-Konsistenz
- Getrennte native Apps (Swift/Kotlin) — konsistent mit Phase 1/2 Entscheidung; kein KMP
- Beide aus **EINEM OpenAPI-Schema** (HA-Phone Backend) generiert:
  - Kotlin: `openapi-generator` (Maven/Gradle) → Retrofit + Moshi / Kotlinx.Serialization
  - Swift: `swift-openapi-generator` (Apple-offiziell) → URLSession / AsyncHTTPClient
- API-Änderungen → Schema ändern → CI regeneriert beide Clients → Compile-Fehler zeigen Breaking Changes
- Shared Data Models als separate Type-Definitions-Dateien (nicht runtime-shared)

### 7. Geräte-Identität & Multi-Device
- **Geräte-ID:** iOS `identifierForVendor` (IDFV) + Android `Settings.Secure.ANDROID_ID` (API 26+ stabil pro App-Signing-Key+User+Gerät)
- **1 Gerät = 1 Extension (1 SIP-Identität)** — Matcht Dashboard-Model, sicherer, simpler
- **Multi-Device pro Extension:** Alle Geräte klingeln bei Anruf; Erstannahme gewinnt; andere per Abbruch-Push stoppen
- **Gerätewechsel:** Admin sperrt/liest altes Gerät → Nutzer scannt neuen QR (neue Provisioning = neues Cert + neues Device-ID). Kein Backup/Restore von Credentials. Optional später: Migration-Flow mit Token + Biometrie + Admin-Freigabe

## Checkpoint
All 7 gray areas discussed completely. All decisions captured in 03-CONTEXT.md. No remaining unresolved questions for Phase 3 discussion.

---

*Checkpoint file to be written after CONTEXT.md creation. Discussion log accumulated per-area with user selections.*