# Release-Smoke-Test im Emulator

Stand: 2026-09-25 · App 1.1.1/1.1.2 (Release, x86_64, Upload-Key) · Anlage 0.7.125 · Emulator `haphone_test_api35`, Nebenstelle 18

| # | Prüfung | Ergebnis |
|---|---|---|
| 1 | Debug-App deinstalliert, Release-APK installiert (andere Signatur, Neukopplung nötig) | ok |
| 2 | Kaltstart, kein Absturz (R8 aktiv) | ok |
| 3 | Kopplung per Link | ok |
| 4 | SIP-Registrierung, Anlage meldet 18 `Online` | ok |
| 5 | Tailscale: Einmal-Key, Running, Node gemeldet, `REGISTER sip:100.117.178.114:5063` → 200 | ok |
| 6 | Türanruf bei gesperrtem Bildschirm: Klingelbildschirm über der Sperre, Livebild, SDP über 100.x, Annehmen → ACTIVE, Ende → DISCONNECTED | ok (nach Freigabe von Benachrichtigungen) |
| 7 | Ausgehend `*43` über das Wählfeld, Gespräch steht, Auflegen | ok ab 1.1.2 |

## Gefunden und behoben

- **Wählen brach still ab** (1.1.1): `permission_handler` wirft, wenn noch eine andere Berechtigungsanfrage offen ist (hier: Startdialog nie beantwortet). Das trat unabhängig von R8 auf. Seit 1.1.2 fragt die App nur, wenn die Berechtigung fehlt, und nimmt sonst den aktuellen Stand (`CallLauncher.ensureGranted`, auch für Kamera beim QR-Scan und Adressbuch).
- Nach einer Neuinstallation sind Benachrichtigungen und Vollbild-Anrufe noch nicht erlaubt. Ohne sie gibt es keinen Klingelbildschirm. Die App fragt danach, im Erreichbarkeits-Bildschirm steht „Beheben“. Im Emulator per `pm grant … POST_NOTIFICATIONS` und `appops set … USE_FULL_SCREEN_INTENT allow`.
- Beim Wechsel Debug → Release vergibt Android eine neue Geräte-ID (ANDROID_ID hängt am Signaturschlüssel). Die Anlage sieht das als neues Handy, der alte Tailnet-Eintrag muss einmal von Hand weg (Tailscale-Seite → Entfernen).

## Größen

arm64-v8a 74,4 MB · x86_64 78,0 MB · AAB 63,6 MB (Debug vorher 333 MB).
