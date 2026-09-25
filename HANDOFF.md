# HA-Phone App – Übergabe

Stand: **2026-09-24 (nachts)**. Für die Fortsetzung in einer neuen Sitzung / auf einem anderen Rechner.
Produktplan (Linkus-Vergleich, Bildschirm-Entwürfe, Phasen): [`docs/linkus-schlachtplan.html`](docs/linkus-schlachtplan.html)
(auch online: https://claude.ai/artifact/QsGjhj72xGjUdUrx7ahFg3).

---

## 1. Entscheidungen des Nutzers (gelten vor älterer Doku)

Diese Punkte hat der Nutzer ausdrücklich entschieden. Wo `.planning/` oder `ENTWICKLUNGSPLAN.md` noch etwas anderes sagen, sind sie in diesem Punkt veraltet.

| Thema | Entscheidung |
|---|---|
| UI-Technik | **Flutter**-Oberfläche + native Platform-Channels für PJSIP / Telecom / CallKit. Projekt: `app-flutter/` |
| Einrichtung | **Nur QR-Code**, manuelle SIP-Eingabe ist höchstens Notlösung |
| Linphone-QR im HA-Phone-Admin | **Entfernt**, ersetzt durch "HA-Phone App QR" |
| Erreichbarkeit | **Dauerhaft registriert**, Vordergrund-Dienst hält die App wach, Anrufe erscheinen wie normale Anrufe (Android Telecom, später iOS CallKit) |
| Türstation | **Video-Vorschau per SIP Early Media** (183 + H.264), genau wie am Fanvil-Tischtelefon |
| UX-Vorbild | **Yeastar Linkus Mobile**: möglichst viel übernehmen, siehe Schlachtplan |
| Reihenfolge | Android zuerst, iOS danach |

## 2. Wo was liegt

| Was | Ort |
|---|---|
| Projekt-Freigabe | `\\192.168.101.113\projects` (Windows, Laufwerk `Z:`) = `/home/roto/projects` auf **CCsrv** |
| Build-Host | CCsrv, `ssh CCsrv-ahrens` (Benutzer `roto`). Alle Builds laufen dort, nicht lokal |
| Flutter SDK | `/home/roto/flutter/flutter/bin/flutter` (steht nicht im PATH) |
| Android SDK / NDK | `~/android-sdk`, NDK `27.0.12077973` |
| Flutter-App (aktiv) | `ha-phone-app/app-flutter/`, Android-Nativcode unter `android/app/src/main/kotlin/de/haphone/app/test/` |
| Alte native Apps (Referenz) | `ha-phone-app/android-app/`, `ha-phone-app/ios-app/` |
| PJSIP-Quelle + Build | `ha-phone-app/android-app/third_party/pjproject` (2.17), Skript `android-app/scripts/build_pjsip_android.sh` |
| Selbst gebaute Libs | `android-app/third_party/openssl-android/<abi>`, `.../opus-android/<abi>` |
| sip-core-Module | `app-flutter/android/sip-core/` **und** `android-app/sip-core/` (Kopien; `.so` + SWIG-Java sind gitignored) |
| Anlage (PBX-Add-on) | `Ha-Phone/ha-phone/` → GitHub `iron-exx/HA-Phone`, Branch `main` |
| HA-Box | `192.168.7.10` (Home Assistant, Add-on HA-Phone). SIP-TLS `5061`, Web/API Port 80. Kein SSH-Zugang für Claude |
| Testgerät | OnePlus 3T, Android 9, adb-Serial `81545518`. USB ist wackelig: bei "device not found" `adb kill-server; adb start-server` |
| Test-Nebenstelle | **13** ("Test"), per QR mit der App gekoppelt. 11 = Fanvil (sandro), 16 = türklingel |

## 3. Bauen und installieren

```bash
# App bauen + Unit-Tests (auf CCsrv)
ssh CCsrv-ahrens "cd /home/roto/projects/ha-phone-app/app-flutter && /home/roto/flutter/flutter/bin/flutter analyze && cd android && ./gradlew :app:assembleDebug :app:testDebugUnitTest --console=plain"
# APK: app-flutter/build/app/outputs/apk/debug/app-debug.apk (~270 MB, Debug)
```

Installieren (Windows, adb aus scrcpy). Die APK vorher **lokal kopieren**, die Installation direkt vom UNC-Pfad bricht bei wackeligem USB oft ab:

```powershell
Copy-Item "\\192.168.101.113\projects\ha-phone-app\app-flutter\build\app\outputs\apk\debug\app-debug.apk" "$env:TEMP\haphone.apk" -Force
adb -s 81545518 install -r "$env:TEMP\haphone.apk"
adb -s 81545518 shell am start -n de.haphone.app.test/.MainActivity
adb -s 81545518 logcat -d -s PJSIP:V AndroidRuntime:E   # PJSIP loggt unter Tag "PJSIP"
```

PJSIP neu bauen (nur nötig nach PJSIP-/Config-Änderungen, ~10–15 min):

```bash
ssh CCsrv-ahrens "cd /home/roto/projects/ha-phone-app/android-app && ANDROID_ABIS_OVERRIDE=arm64-v8a bash scripts/build_pjsip_android.sh"
```

Das Skript baut OpenSSL und Opus, setzt `PJ_DEBUG 0` und `PJMEDIA_HAS_VIDEO 1`, baut PJSIP mit `--with-ssl`, verlinkt `libpjsua2.so` erzwungen neu und kopiert alles in **beide** sip-core-Module. Die OpenSSL- und Video-Schritte habe ich am 2026-09-23 von Hand verifiziert. Den kompletten Skriptlauf in dieser Form **noch nicht**. Beim ersten Lauf prüfen, ob `PJ_HAS_SSL_SOCK 1` gesetzt ist und die `.so` einen frischen Zeitstempel hat.

Anlage: Backend-Tests `ssh CCsrv-ahrens "cd /home/roto/projects/Ha-Phone/ha-phone && python3 -m pytest backend/tests -q"` (aktuell 123 passed). Push von CCsrv funktioniert: `git -c safe.directory='*' push origin main`. Damit HA ein Update anzeigt, muss `ha-phone/config.yaml` `version` erhöht werden, mit Eintrag in `CHANGELOG.md` (Deutsch).

## 4. Stand

### Auf dem Gerät verifiziert
- QR-Kopplung → Registrierung per **TLS/5061** → `200 OK`, die Nebenstelle 13 ist im Dashboard online
- Ausgehende Anrufe **mit Ton in beide Richtungen** (vom Nutzer bestätigt)
- Vordergrund-Dienst läuft (`isForeground=true`), Video-Subsystem startet, H.264-Decoder (`OMX.google.h264.decoder`) mit Priorität 255

### Gebaut, aber noch nicht auf dem Gerät getestet
- **Eingehende SIP-Anrufe** → Android Telecom + Vollbild-Klingelbildschirm (`IncomingCallActivity`) + CallStyle-Benachrichtigung mit funktionierenden Annehmen/Ablehnen-Aktionen
- **Video-Vorschau vor dem Abheben**: `onIncomingCall` antwortet bei `m=video` im INVITE mit **183 + SDP** (Audio und Video), zeigt das Video im Klingelbildschirm (SurfaceView → `VideoSurfaceBinder`). Mikrofon und Lautsprecher werden erst bei CONFIRMED verbunden. Ohne Video gibt es ein normales 180.
  - Voraussetzung in HA-Phone: Bei Nebenstelle 13 **"Video" aktivieren**
- Neustart-Autostart des Dienstes (`BootReceiver`), Abfrage der Akku-Optimierungs-Ausnahme
- Aufräumen, wenn der Anrufer auflegt oder ein anderes Gerät abnimmt (Klingelbildschirm schließt sich, Telecom wird freigegeben)

### Anlage (HA-Phone), alles auf `main` gepusht
| Commit | Version | Inhalt |
|---|---|---|
| 56c741d, b39d0ce, d6fcff4, 3ed91d0 | 0.7.100 | QR-Kopplung repariert (Routing, Auth, JWT-Zeit, Schlüsselpaar), Linphone-QR ersetzt, PyJWT in requirements |
| dad497b | 0.7.101 | TLS-Zertifikat wird bei jedem Start erzeugt (vorher nur beim Erststart und per fehlendem `openssl`-CLI → Port 5061 war nie offen) |
| 63a51e0 | 0.7.102 | **Sicherheit:** `/api/mobile/config` gab SIP-Passwörter ohne Anmeldung heraus. Jetzt gibt es ein Geräte-Token pro Kopplung (nur der SHA-256-Hash wird gespeichert) |
| 29b06cb | (keine Versionserhöhung) | `GET /api/mobile/directory`: Nebenstellen + Telefonbuch für die App, mit Geräte-Token |

Auf der HA-Box ist laut Nutzer 0.7.101 oder neuer installiert (TLS funktioniert). Ob 0.7.102 schon drauf ist: offen.

## 5. Stand 2026-09-23 spät (autonom weitergebaut, Nutzer will: "zieh es durch, keine Fragen")

**Arbeitsweise jetzt:** Handy weg → **Emulator** `haphone_test_api35` auf CCsrv (siehe unten), gekoppelt auf **Nebenstelle 12**. Kopplungs-Links und Add-on-Updates holt Claude selbst: Zugangsdaten in `no-git/credentials.json` (HA + HA-Phone-Admin). Hilfsskripte in **`no-git/tools/`** (nicht versioniert): `ha.py` (HA-Login), `hasup.py` (Supervisor über HA-Websocket), `deploy_pbx.py` (nach Push der Anlage: wartet auf das CI-Image, spielt es ein, prüft die Version; aus `no-git/tools/` starten), `provision_link.py [nebenstelle]` (frischer Kopplungs-Link, dann `adb shell "am start -a android.intent.action.VIEW -d '<link>' de.haphone.app.test"`). Die Anlage baut **nicht** auf der Box: GitHub Actions baut `ghcr.io/iron-exx/ha-phone/{arch}:{version}`, die Box zieht das Image (amd64 ~10 min nach Push).
**APK für den Emulator mit `flutter build apk --debug` bauen** (`build/app/outputs/flutter-apk/`), nicht mit `./gradlew assembleDebug`: Die Gradle-APK startet im Emulator nicht ("Could not prepare isolate").

App (aktuell 0.3.0+, alles gepusht, ~110 Dart- + 39 Kotlin-Tests grün):
- Phase 1–2 (siehe Commits): Linkus-Oberfläche, Kopplung per QR **und Link** (`haphone://provision?...`), Tür öffnen, Audio-Umschaltung, Video im Gespräch, native Anrufliste.
- Phase 3: Status setzen (Ich), Live-Leitungsstatus in Kontakten, visuelle Voicemail (just_audio), Badges.
- Phase 4: **zwei Leitungen** (`calls/CallSession.kt` rein & getestet, `CallCoordinator.kt`), Anklopfen (Benachrichtigung + Karte), Rückfrage, Makeln, Weiterleiten mit Rückfrage (REFER/Replaces, `onCallTransferStatus` beendet eigenes Bein), 3er-Konferenz (PJSUA-Audiobrücke), Hinzufügen, Wahlwiederholung. `lockCodecEnabled=false` (kein UPDATE nach Annahme).
- Phase 5 (Dart, Agent lief): Weiterleitungen-Editor, Anrufliste mit CDR der Anlage abgeglichen, Diagnose-Seite.
- **Noch offen App:** Tür-HA-Aktionen in App (Endpunkt fertig, s.u.), Emulator-Test Zwei-Leitungen mit `*43`, Push-Wecken (Phase 8), iOS (Phase 7).

Anlage (gepusht, auf der Box **0.7.110**, 0.7.111 wird eingespielt):
| Version | Inhalt |
|---|---|
| 0.7.103/104 | Tür-Öffnen-Code, Directory, `*97` Mailbox |
| 0.7.105–108 | Ansagen: `menuselect --disable-all` hatte **alle** Sounds abgeschaltet (Mailbox legte sofort auf). Jetzt EN-WAV + **deutsche Ansagen** (joni1802/asterisk-sound-generator v0.2.3, A-law+G.722, `language=de`). `format_g722` gibt es nicht (format_pcm) |
| 0.7.107 | `/api/mobile/presence` GET/PUT, `/api/mobile/voicemail` (+audio, DELETE) |
| 0.7.109 | `*43` Echo-Test |
| 0.7.110 | `/api/mobile/forwarding` GET/PUT, `/api/mobile/calls` (CDR `/data/logs/asterisk/cdr-csv/Master.csv`); **Fix Voicemail-Pfad**: `/data/voicemail/voicemail/default/<n>` (astspooldir), Admin zeigte nie Nachrichten |
| 0.7.111 | Tür-**Home-Assistant-Aktionen** (Extension.door_actions, Admin-Editor, Directory liefert nur Labels, `POST /api/mobile/door-action {extension,index}` → HA-Service via Supervisor), `homeassistant_api`+`hassio_api`; Tür-Code-Validierung beim PATCH (sqlmodel `regex=` wird NICHT geprüft → `field_validator`) |

CCsrv-RAM: Proxmox-Host (62 GB) überbucht, OOM-Killer hat CCsrv am 2026-09-23 16:57 beendet. CCsrv jetzt 32 GB.

## 5a. Im Emulator getestet (2026-09-23 21:40, App 0.4.0, Anlage 0.7.112)

- Kopplung per Link, TLS-Registrierung, Kontakte mit Live-Status, Voicemail-Reiter, Ich (Status), Diagnose ("erreichbar · 624 ms", alle Funktionen "ja"), Anrufliste mit CDR.
- Zwei Leitungen mit `*43`: Rückfrage über "Hinzufügen", Makeln, Konferenz, Auflegen der vorderen Leitung (gehaltene bleibt mit "Fortsetzen"), Auflegen der letzten → zurück zur Hauptansicht.
- Behoben dabei: Kanäle werden jetzt in `HAPhoneTestApplication.onCreate` **vor** dem Dart-Start registriert (Kaltstart verlor sonst das EventChannel-Listen → Gesprächsbildschirm ohne Ereignisse). `_invokeResilient` ist damit eigentlich überflüssig.
- Nicht testbar im Emulator: echter Ton, Bluetooth, Türstation-Video (braucht die Akuvox), Anklopfen (braucht einen zweiten Anrufer).

## 5a2. Nachtrag 2026-09-24

- App **0.5.0**: Handy-Adressbuch (Quelle "Handy", Suche über alle Quellen, Anrufernamen mit +49/0-Abgleich), "Heranholen" bei klingelnden Kontakten, App-Symbol + Splash.
- Anlage **0.7.113** installiert: `**<ext>` Heranholen (app_directed_pickup).
- Weiterleitungen im Emulator gegen die Anlage gespeichert und wieder entfernt: funktioniert.
- `deploy_pbx.py` prüft jetzt die installierte Version (vorher meldete es Erfolg, obwohl noch die alte lief).

## 5a3. Phase 6 (2026-09-24, laufend)

- Anlage **0.7.114** (Commit 5a36bdf): `Extension.recording_allowed` (Standard aus, Schalter im Admin mit Hinweis § 201 StGB), `POST /api/mobile/recording {action: start|stop, peer}` → AMI `MixMonitor`/`StopMixMonitor` auf den `Up`-Kanal der eigenen Nebenstelle (bei zwei Leitungen per `peer` = ConnectedLineNum), Dateien `/data/recordings/<ext>/<YYYYmmdd-HHMMSS>_<peer>.wav`, `GET /api/mobile/recordings`, `/recordings/{id}/audio`, `DELETE`. Directory `self.recording_allowed`. `app_mixmonitor` in Dockerfile **und** `modules.conf` (autoload=no!).
- `*55` Gespräch umlegen: Dialplan ohne `While` (app_while nicht gebaut): `CHANNELS(^PJSIP/<ext>-)` per `SHIFT(…, )` durchlaufen, eigenen Kanal überspringen, `IMPORT(<kanal>,BRIDGEPEER)`, dann `Bridge(peer)`. Asterisk löst die alte Bridge auf ("stolen channel"), das andere Gerät legt auf. **Noch nicht live getestet** (braucht zweites Gerät auf derselben Nebenstelle; Plan: Host-`pjsua` aus `android-app/third_party/pjproject` in eine Kopie bauen, per UDP als zweites Gerät der 12 registrieren).
- App 0.6.0 (in Arbeit): Taste „Aufnehmen" im Gespräch, Liste „Aufnahmen" im Ich-Reiter, Banner „Gespräch auf anderem Gerät → Hierher holen" (wählt `*55`, wenn `presence.self.line == busy` und die App selbst kein Gespräch hat).

## 5a4. Türvideo bei gesperrtem Handy (2026-09-24, im Emulator getestet)

- Test: Emulator mit PIN 1234 gesperrt, Bildschirm aus, `no-git/tools/door_sim.py --to 18 --pbx 192.168.7.10` (Tür-Simulator = Nebenstelle 17: SIP/UDP, PCMA + H.264 per GStreamer, Testbild mit Uhr). Ergebnis: Bildschirm wacht auf, `IncomingCallActivity` über der Sperre, **Live-Bild nach ca. 5 s** (dekodiert ab ca. 1 s, Rest Emulator-Rendering).
- Ursache fürs schwarze Bild war **NAT**: App schickt vor dem Abheben kein RTP, SDP hatte die private Adresse (10.0.2.16). Zwischen CCsrv und HA-Box liegt zusätzlich ein NAT (Box sieht CCsrv als 192.168.178.22). Fix: Anlage 0.7.115 STUN-Server (3478/udp, `backend/stun_server.py`), App 0.6.1 `natUpdateStunServers` + `mediaStunUse` (SIP ohne STUN), und PJSIP mit `PJMEDIA_STREAM_ENABLE_KA PJMEDIA_STREAM_KA_EMPTY_RTP` (leeres RTP beim Stream-Start öffnet das NAT; im Build-Skript). Beides zusammen nötig.
- Emulator mit PIN: nach jedem Emulator-Neustart erst entsperren (Direct Boot, sonst "Activity class does not exist"). Entsperren: `input keyevent 82`, dann Ziffern antippen (1: 266,1148 · 2: 540,1148 · 3: 814,1148 · 4: 266,1400 · OK: 814,1904).
- Emulator ist auf **Nebenstelle 18** gekoppelt (nicht mehr 12, die steckt in der Klingelgruppe "klingel" und hätte echte Klingelrufe mitgenommen). Test-Nebenstellen 17/18 samt Passwörtern in `no-git/test_extensions.json`. Admin-API: `no-git/tools/pbx_admin.py GET /api/extensions`.
- Anlage 0.7.116: Freizeichen nach außen (`Dial(...,r)`, Trunk-Schalter `local_ringback`, Standard an). App 0.6.1: `calls/Ringback.kt` spielt bei abgehenden Anrufen im Zustand EARLY `TONE_SUP_RINGTONE` (noch nicht per Ohr getestet).
- Push ins App-Repo mit Token in der URL wird inzwischen blockiert, den Push macht der Nutzer.

## 5a5. Stand 2026-09-24 nachmittags: App 0.8.0, Anlage 0.7.117 (alles gepusht)

- Redesign "Nachtwache" Etappen 1–4 fertig und im Emulator geprüft (Screens in `docs/screenshots/`, README aktualisiert).
- Dauerhaft erreichbar (0.7.1): `reach/` (ReachPolicy, RegistrationAlarm, WatchdogWorker, ReachabilityMonitor), Ablauf 600 s, Wecker 480 s exakt, Test 20 min Deep-Doze bestanden.
- Klingelbildschirm nativ (Compose, `ring/`), Schieberegler → `POST /api/mobile/door-open` (Webhook, ohne Abheben), getestet.
- **Video-Fix**: `VideoDecodeLimits` (decFmt 1920x1080, fmtp 42e01f/pm=1) — vorher fror das Türbild ein (Puffer 352x288).
- `ring/RingPolicy`: "Klingeln auf diesem Handy" aus/stumm → 480 vor dem Klingeln, Türklingel-Ausnahme (Tür = Türcode/Webhook/HA-Aktion oder Video im INVITE).
- Erreichbarkeit-Screen (6 Prüfpunkte + OEM-Hinweise). Offen: "Test-Anruf an mich" braucht Anlage-Endpunkt (AMI Originate an eigene Nebenstelle, 1/min).
- Test-Tools: `no-git/tools/door_sim.py` (Tür-Simulator, Nebenstelle 17), Webhook-Empfänger `python3 hook.py` (Port 8099; Tür 17 zeigt auf http://192.168.101.113:8099/api/webhook/haustuer), `pbx_admin.py`.
- Hinweis: Video-Nebenstellen haben `max_contacts=1` → "Gespräch umlegen" auf derselben Video-Nebenstelle geht nicht.

## 5a6. Android Auto (2026-09-24, App 0.9.0, nicht committet, nicht im Auto getestet)

- Car App Library 1.7.0, `car/HaPhoneCarAppService` (Kategorie `CALLING`): Tabs Favoriten / Verlauf / Kontakte (Präsenz nativ per `GET /api/mobile/presence`) / Haustür (Anrufen, "Tür öffnen" mit Rückfrage per `POST /api/mobile/door-open`, HA-Aktionen). Unter Car-API 6 ein einfaches Menü statt Tabs.
- Daten: Dart schiebt `setCarDirectory` (nach jedem Verzeichnis-Laden) und `setFavorites`; Verlauf aus `CallHistoryStore`. Wählen über `HAPhoneTestApplication.placeCall` (gleicher Weg wie Dart).
- Telecom-Lücken für AA geschlossen: `setActive()` bei SIP CONFIRMED (sonst "wählt" ewig), Halten/Fortsetzen aus dem Auto (`onSetActive/onSetInactive`), Stumm aus dem Auto gespiegelt, Anzeigename statt "HA-Phone Testanruf", Adresse `sip:<nummer>`, Annehmen aus dem Auto schließt den Klingelbildschirm.
- Google-Vorgabe: Calling-Apps in AA sind Beta, im Play Store nur Internal/Closed Testing. Seitengeladene Debug-APK läuft nur mit AA-Entwicklermodus + "Unbekannte Quellen". DHU liegt unter `~/android-sdk/extras/google/auto` (Emulator-Image hat kein Android Auto -> Test nur am echten Handy).

## 5a7. Audit 2026-09-24 abends (LAUFEND — hier weitermachen)

- Anlage **0.7.119** gepusht + installiert (Audit-Fixes: Login-Bremse/Pflicht-Passwortwechsel, Konfig-Injektion, Module caller_id/nat/refer/mwi/h264/timeout/MoH, *55 `Bridge(...,x)`, Feiertage-Jahr, PJSIP_DIAL_CONTACTS, Trunk identify_by=ip, TLS im Template, SRTP entfernt). Trunk registriert, 11/15/16 online.
- App **1.0.0+15** gebaut, NICHT committet (Working Tree = native + Flutter Audit-Fixes: echter Klingelton `calls/RingtonePlayer.kt` + Kanal `haphone_calls_v2`, Telecom-Registry pro Anruf, Answer-Guard, Notification-ID 1003, Lock, Wake-Locks, FGS phoneCall|microphone im Gespräch, SecurePrefs, allowBackup=false, keine BuildConfig-SIP-Daten; Flutter: lastDisconnected-Fix, TalkBack, Kontraste, "du", resetForPairing …). 386 Dart + 140 Kotlin Tests grün.
- E2E-Test fand 2 Fehler, BEHOBEN + E2E a–d bestanden (MainActivity showWhenLocked während Anruf via `calls/InCallWindow.kt`; IncomingCallActivity eigene taskAffinity, answer() mit NEW_TASK): (A) nach Annehmen bei Sperre liegt der Gesprächsbildschirm HINTER dem Keyguard (MainActivity braucht showWhenLocked während Anruf), (B) zweiter Anruf bei gesperrtem, eingeschaltetem Display zeigt nur Heads-up statt Klingelbildschirm (Task/Affinity?). App 1.0.0 committet + gepusht. Audit-Bericht: docs/audit/2026-09-24-audit.md. Nächster Schritt: offene Punkte dort (Nutzer entscheidet 2–4).
- Nutzer muss: SIP-Passwort von Nebenstelle 13 im Admin ändern (steht im Git-Verlauf; Ändern war für Claude blockiert).
- Offen aus Audit (bewusst später): HTTPS + Zertifikat-Pinning für App↔Anlage und SIP-TLS `verifyServer` (braucht Zertifikats-Fingerprint im QR), Kopplungs-Link-Rückfrage (prüfen ob umgesetzt), Lizenzfrage PJSIP (GPL) vs. "All Rights Reserved", CI für app-flutter, HANDOFF-Aufräumen.

## 5a8. 2026-09-25: App 1.0.1 (Erscheinungsbild Dunkel/Hell/System, Standard Dunkel) gepusht. NÄCHSTES PROJEKT: eingebettetes Tailscale

Nutzer-Entscheidung: nur Vollversion. HA-Phone hinterlegt Tailscale-Zugang (OAuth-Client), QR-Kopplung liefert pro Gerät einen Auth-Key in der Provisioning-Antwort, App bettet Tailscale ein (libtailscale, VpnService nur für 100.x) und ist unterwegs erreichbar. Schritt 1: Machbarkeit + Plan in `docs/design/tailscale.md` (inkl. neuer Admin-Menüpunkt "Tailscale", Einrichtung so einfach wie möglich). Plan liegt vor (docs/design/tailscale.md, ca. 14–20 Arbeitstage, Etappen 0–5). Schritt 2: Etappe 0 (Go 1.27 + gomobile Toolchain-Spike, libtailscale-AAR bauen) — wartet auf Nutzer-Freigabe + Test-Tailnet/OAuth-Client.

## 5a9. >>> NACH /clear HIER STARTEN (2026-09-25) <<<

Auftrag: **Tailscale-Integration bauen** nach `docs/design/tailscale.md` (Etappen 0–5). Nutzer hat einen Tailscale-Account zum Testen (Zugangsdaten/OAuth-Client beim Nutzer erfragen, sobald Etappe 1/2 sie braucht; ablegen nur in `no-git/tailscale.json`, nie committen).
1. Etappe 0: Go 1.27 + gomobile auf CCsrv installieren (nutzerlokal, z. B. ~/go-toolchain), tailscale-android klonen, libtailscale-AAR für arm64-v8a + x86_64 mit NDK 27 bauen, in app-flutter einbinden, Probe-Build. Nie gleichzeitig mit dem Emulator bauen.
2. Etappe 1: Anlage — Admin-Menüpunkt "Tailscale" (Assistent, OAuth-Client, "Verbindung testen", Status, Geräteliste), TailnetProvider, Tailnet-IP von tailscale0.
3. Etappe 2: Provisioning-Antwort mit `tailscale`-Block (Einmal-Key, preauthorized, tag:haphone-phone, nicht ephemeral), Entkoppeln löscht Gerät.
4. Etappe 3/4: App-Modul (VpnService nur 100.64.0.0/10 + fd7a:115c:a1e0::/48, Einwilligungsdialog nach Kopplung, Status in Erreichbarkeit, Registrar tailnet/LAN umschalten).
5. Etappe 5: E2E im Emulator im Tailnet.
Arbeitsweise: pro Etappe committen + pushen (Token-URL erlaubt), Anlage-Version + CHANGELOG erhöhen, HANDOFF nach jedem Schritt aktualisieren (Nutzungslimit!).

## 5a10. Tailscale Etappe 0 (2026-09-25 vormittags, LAUFEND)

- **Toolchain:** Kein eigenes Go nötig. `tool/go` von tailscale-android lädt seinen gepinnten Go-Toolchain nach `~/.cache/tailscale-go`. Checkout: `~/src/tailscale-android`, gepinnt auf `803d938`.
- **Build:** `bash app-flutter/scripts/build_libtailscale.sh` (ca. 5 min kalt, 40 s warm). **NDK 27 funktioniert**, 16-KB-Seiten ok (LOAD-Align 0x4000). Das Skript entfernt die 32-Bit-ABIs und strippt auch x86_64. Das Ergebnis `app-flutter/android/tailscale-core/libs/libtailscale.aar` (19 MB) ist gitignored, genau wie die PJSIP-`.so`.
- **Größe:** `libgojni.so` arm64 27,8 MB entpackt (~9 MB komprimiert), x86_64 29,7 MB. Die Debug-APK wächst von 262 auf 333 MB.
- **Kotlin:** `tailscale/` im App-Paket: `TailnetRoutes` (Split-Tunnel-Filter, getestet), `TsAppContext` (Zustand in SecurePrefs mit dem Präfix `statestore-`, ohne MDM, Attestation und Log-Upload), `TsVpnService` (nur 100.64/10 + fd7a:115c:a1e0::/48, kein DNS), `Tailscale` (LocalAPI: start per AuthKey, connect, disconnect, logout, status), `TsDebugReceiver` (adb, nur Debug, Permission DUMP).
- **Im Emulator verifiziert:** libtailscale startet im App-Prozess, `status` → `NeedsLogin`, kein Absturz. 157 Kotlin-Tests grün.
- **Nächster Schritt:** Beitritt mit Auth-Key des Nutzers (liegt dann in `no-git/tailscale.json`):
  `adb shell appops set de.haphone.app.test ACTIVATE_VPN allow`
  `adb shell am broadcast -n de.haphone.app.test/.tailscale.TsDebugReceiver -a join --es key <tskey> --es host haphone-emu`
  danach `-a status` (Logtag `TsDebug`) und `adb shell ping <100.x der HA-Box>`. Voraussetzung: Tailscale-Add-on auf der HA-Box, `userspace_networking` aus.

## 5a11. Tailscale in der Anlage (2026-09-25, Anlage 0.7.120, Commit 35b6c51)

- Nutzer-Wunsch war „Anmelden-Knopf → Tailscale-Seite → zurück, verbunden“. Das geht **nicht**: Tailscales „OAuth apps“ (Authorization-Code) sind Alpha, nur per API im eigenen Tailnet anlegbar, nicht tailnet-übergreifend, und jede Zustimmung gilt nur für ein Gerät (kein Refresh). Umgesetzt ist deshalb: Assistent mit Link zur Konsole, OAuth-Client (Trust Credential) einmal anlegen, Client-ID + Secret einfügen, Live-Test. Das hat der Nutzer noch nicht ausdrücklich bestätigt.
- Backend: `backend/tailnet.py` (API-Client, Token-Cache, `tailscale0`-Erkennung per ioctl + `/proc/net/if_inet6`), `backend/routers/tailscale.py` (`/api/tailscale/config` GET/PUT/PATCH/DELETE, `/test`, `/devices`, `DELETE /devices/{id}`), `TailnetConfig`-Tabelle, `MobileDevice.tailscale_node_id/ip`. Die Kopplung liefert den Block `tailscale` (Einmal-Key 1 h, preauthorized, tag:haphone-phone). Neue Endpunkte `POST /api/mobile/device/tailscale` (App meldet Node-ID + IP) und `/device/tailscale-key` (Nachrüsten, 1/min). Beim Widerruf oder Löschen der Nebenstelle wird das Gerät auch aus dem Tailnet gelöscht.
- Fix nebenbei: Beim Löschen einer Nebenstelle blieben die MobileDevice-Zeilen stehen. SQLite vergibt die ID neu, dadurch hingen alte Handys an neuen Nebenstellen.
- Frontend: `pages/Tailscale.tsx`, Menüpunkt „Tailscale“ unter Provisioning. 269 Backend-Tests grün.
- App: `Tailscale.loginInteractive` (Browser-Login ohne Key, als Notlösung) + Debug-Aktion `-a login`.
- **Nächster Schritt:** Nutzer verbindet sein Tailnet in der Admin-Seite. Danach Etappe 3/4: App liest den `tailscale`-Block bei der Kopplung, VPN-Zustimmung, meldet Node-ID, Registrar über 100.x.

## 5a12. Tailscale in der App (2026-09-25, App 1.1.0, Anlage 0.7.121)

- Nutzer-Entscheidung: **beides anbieten**. Standard: Das Handy meldet sich selbst an (Browser-Login, „Connect“). Optional die Vollautomatik mit OAuth-Client in HA-Phone (Einmal-Key beim QR-Scan). Die Anlage liefert `tailscale.login = "interactive" | "auth_key"`, der Block kommt nur, wenn `tailscale0` auf der Box existiert.
- App: `tailscale/TailnetManager` (Konfiguration aus der Kopplung, VPN-Erlaubnis über `TsConsentActivity`, Beitritt per Key oder Browser, meldet die Node-ID an die Anlage, `resume()` beim Prozessstart), `TailnetRoute` (SIP-Registrar und API-Host auf 100.x, solange der Tunnel läuft; bei Wechsel `refreshSipCredentials` + register). Kanal: `tailscaleConfigure/Start/Status/Reset`. Dart: Kopplung ruft configure + start auf, `resetForPairing` ruft tailscaleReset auf, im Erreichbarkeits-Bildschirm neue Zeile „Unterwegs erreichbar“ (`models/tailnet_status.dart`).
- Getestet: Unit-Tests (401 Dart, Kotlin grün), Emulator-Neukopplung ohne Tailscale auf der Box (keine Regression). **Noch nicht getestet:** der echte Beitritt, weil das Tailscale-Add-on auf der HA-Box noch fehlt. Der Nutzer installiert es gerade.
- Nächster Test sobald das Add-on läuft: Emulator neu koppeln (`provision_link.py 18`), Erlaubnis bestätigen (bzw. `appops set … ACTIVATE_VPN allow`), Login-Seite im Emulator-Browser. Das muss der Nutzer machen, oder er richtet die Vollautomatik ein. Danach `TailnetManager`-Log: „PBX route -> tailnet“, Registrierung über 100.x.

## 5a13. Tailscale E2E im Emulator BESTANDEN (2026-09-25 mittags, App 1.1.0, Anlage 0.7.124)

- Tailnet des Nutzers: `tail4a5752.ts.net`, HA-Box `homeassistant` = **100.117.178.114**. Die Vollautomatik (OAuth-Client) ist in HA-Phone eingerichtet und grün.
- Emulator (Nebenstelle 18): QR → Einmal-Key → Running in ca. 4 s → Node an die Anlage gemeldet → `REGISTER sip:100.117.178.114:5061;transport=tls` → 200 OK. Neustart der App: verbindet sich von allein (ohne neue Anmeldung), die Route bleibt auf tailnet. Ping auf die Box über den Tunnel geht.
- Dabei behobene Fehler (alles in den Commits):
  1. `start` mit AuthKey allein meldet nicht an. Danach muss `login-interactive` folgen (wie `tailscale up`).
  2. Go braucht den Default-Netz-Namen: `TsNetworkMonitor` → `Libtailscale.onDNSConfigChanged(ifname)` + `onGatewayChanged`. Ohne das sieht Go `defIf=""`, und nach einem Neustart ging es nie wieder online.
  3. `NoState` direkt nach dem Start nicht als „abgemeldet“ werten (`settledState`), sonst erzwingt jeder Neustart eine neue Anmeldung.
  4. **Nie den State-Store löschen** beim Logout: Go benutzt den Machine Key aus dem RAM weiter, ohne ihn neu zu schreiben. Nach dem Neustart kam sonst „bad machine key“.
  5. IPN-Notifications kommen außer der Reihe (ein veraltetes NoState nach Running): Der Zustand wird jetzt immer per `status` gelesen.
  6. Android `optString` gibt für JSON-null den Text "null" zurück (BrowseToURL).
  7. Anlage: Der Verbindungstest nahm ein gecachtes Token (Tags stecken im Token). Die Key-Sperre gilt jetzt pro Kopplung. Neukopplung desselben Handys widerruft die alte Kopplung und löscht deren Tailnet-Gerät.
- Offen: der echte Mobilfunk-Test am Handy, Deep-Doze mit Tunnel, Türvideo über den Tunnel (door_sim über 100.x), Fremd-VPN-Fall, Akku-Messung. Der Nutzer-Weg ohne OAuth (Browser-Login) wurde nur bis zur Login-URL getestet.

## 5a14. Netzwechsel + Türvideo über Tailscale (2026-09-25, App 1.1.1, Anlage 0.7.125)

- WLAN 20 s aus/an: Tunnel bleibt Running, **die SIP-TLS-Verbindung überlebt** (keine Neuregistrierung, 18 durchgehend online, Asterisk qualifiziert über 100.x).
- Gefundener Fehler: Asterisk schrieb über `transport-tls` die **LAN-Adresse** in die SDP (c=192.168.7.10, weil 100.64/10 in local_net steht). Unterwegs wären Ton und Video tot gewesen. Fix (Anlage 0.7.125): `[transport-tls-tailnet]` auf **5063**, external_signaling/media_address = Tailnet-IP, local_net nur RFC1918. Er wird automatisch gerendert, sobald `tailscale0` da ist (`main._watch_tailnet_transport`, alle 60 s, `pjsip_local.refresh_for_tailnet`, merkt sich die öffentliche IP in `/data/asterisk/pjsip_local.ip`). Die Kopplung liefert `sip_port_tailnet: 5063`, die App (1.1.1) nimmt diesen Port im Tunnel (`TailnetRoute.sipPort`).
- Verifiziert: REGISTER auf 100.117.178.114:5063 → 200, INVITE-SDP c=100.117.178.114, Antwort c=100.x der App, Türvideo vor dem Abheben live.
- Policy-Schnipsel enthält jetzt tcp:5063. Beim Nutzer steht noch die alte Variante (nur relevant, falls die Standard-Regel „alles erlaubt“ entfernt wurde).
- Offen: echtes Handy im Mobilfunk, Deep-Doze mit Tunnel, Fremd-VPN, Akku.

## 5a15. Ausbauplan, Etappe 1 fertig (2026-09-25 nachmittags, App 1.1.2)

- **Plan:** `docs/superpowers/plans/2026-09-25-ausbau-release-klingelverlauf.md`. Etappen: 1 Release + Handy-Test (fertig bis auf den Handy-Test des Nutzers) → 2 Klingel-Verlauf mit Foto + neue Start-Seite → 3 Klingeln unterwegs nur, wenn keiner zu Hause ist → 4 Widget/Schnellzugriff. Vor 2–4 jeweils einen eigenen Detailplan schreiben.
- **Release:** Upload-Key `no-git/release/haphone-upload.jks`, Passwort in `app-flutter/android/key.properties` (beides nie committen, **Nutzer soll den Keystore sichern**). Ohne `key.properties` wird der Build debug-signiert. R8 an, Regeln in `app/proguard-rules.pro`. `bash app-flutter/scripts/build_release.sh` → arm64 74 MB, x86_64 78 MB, AAB 64 MB.
- Smoke-Test Release im Emulator bestanden: `docs/test/release-smoke.md`. Fix 1.1.2: Wählen, QR-Kamera und Adressbuch fragen Berechtigungen nur noch bei Bedarf und stürzen nicht mehr, wenn eine andere Anfrage offen ist (`CallLauncher.ensureGranted`).
- Emulator läuft jetzt die **Release**-App (Upload-Signatur). Für Debug-Builds vorher deinstallieren (andere Signatur).
- Handy-Test-Checkliste für den Nutzer: `docs/test/handy-test.md`.
- **Nächster Schritt:** Etappe 2 Detailplan (Snapshot beim Klingeln in der Anlage, API, neue Start-Seite, Verlauf, Benachrichtigung mit Bild).

## 5a16. Etappe 2: Klingel-Verlauf mit Foto (2026-09-25, App 1.2.0, Anlage 0.7.126) — E2E BESTANDEN

- Detailplan: `docs/superpowers/plans/2026-09-25-etappe2-klingelverlauf.md`.
- **Anlage:** `backend/doorbell.py` (DoorbellTracker: Newchannel der Tür = Ring, DialEnd ANSWER = angenommen, Hangup = Ende; fetch_snapshot mit HA-Kamera `camera.*` über Supervisor oder URL mit Basic/Digest, 4 s, max 2 MB; DoorbellStore mit 30 Tagen / 500 Einträgen), `backend/doorbell_listener.py` (eigene AMI-Event-Verbindung im Lifespan, in Tests aus per `BPX_DOORBELL_LISTENER=0`), Feld `Extension.doorbell_camera`, Tabelle `DoorbellEvent`, API `/api/mobile/doorbell` (+`/{id}/image`), Admin `/api/doorbell` + `test-snapshot`, Seite „Türklingel“, Feld „Klingelbild-Quelle“ mit „Testbild holen“. `door-open` markiert „Tür geöffnet“. Directory: `has_camera`. 287 Tests grün.
- **App:** `DoorbellRepository` (Polling 60 s + nach jedem Anruf), Türkarte zeigt das letzte Klingelbild (Tipp → `DoorbellHistoryScreen`), native `calls/DoorbellMissedNotifier.kt` (verpasster Anruf → fragt die Anlage, Benachrichtigung „Es hat geklingelt“ mit BigPicture, Tipp → Verlauf per Route `doorbell`). 408 Dart-Tests grün.
- **Test-Setup:** `no-git/tools/snapshot_server.py` (Port 8098, JPEG mit Uhrzeit) läuft auf CCsrv. Die Nebenstelle 17 (Tür-Simulator) hat als Quelle `http://192.168.101.113:8098/snapshot.jpg`. Ohne laufenden Server gibt es kein Bild (dann: `cd no-git/tools && nohup python3 snapshot_server.py &`).
- E2E: door_sim → 18, nicht angenommen → Ereignis mit Bild in der Anlage, Benachrichtigung mit Bild, Start-Karte zeigt das Bild, Verlauf zeigt „verpasst“.
- Nutzer muss: Bei der echten Akuvox (Nebenstelle 16) die Klingelbild-Quelle eintragen (HA-Kamera oder Akuvox-Snapshot-URL, z. B. `http://user:pass@192.168.7.46/jpeg/image.jpg`, vorher mit „Testbild holen“ prüfen).
- Noch offen aus Etappe 2 (optional, klein): Heute-Leiste und Favoriten-Vorschläge auf der Start-Seite. **Danach Etappe 3** (Klingeln unterwegs nur, wenn keiner zu Hause ist) mit eigenem Detailplan, dann Etappe 4 (Widget/Schnellzugriff).

## 5a17. Etappe 3: Tür klingelt Handys unterwegs nur, wenn niemand zu Hause ist (Anlage 0.7.127)

- `backend/ha_presence.py`: `Extension.ha_person` (z. B. `person.sandro`). Jede Minute werden die `person.*`-Zustände per Supervisor gelesen. `excluded_extensions()`: Ist jemand zu Hause, fallen Nebenstellen mit abwesender Person aus den **Tür-Klingelgruppen**. Ist niemand zu Hause, klingeln alle. Unbekannte Zustände klingeln immer. Ändert sich die Menge, wird `_regenerate_routing_conf` ausgeführt und der Wählplan neu geladen.
- Wählplan: In `from-internal-restricted` (nur Türstationen mit „Nur intern“) steht jetzt `door_ring_group_dials` statt `ring_group_dials`. Ergibt der Filter eine leere Gruppe, klingelt die ungefilterte Gruppe. Direkte Anrufe an eine einzelne Nebenstelle werden nicht gefiltert.
- Admin-Feld „Gehört zu (Home-Assistant-Person)“ im Nebenstellen-Editor. 294 Backend-Tests grün.
- **Noch nicht live getestet** (braucht echte person.*-Zustände, z. B. eine Test-Person in HA oder die Personen des Nutzers). Test: Klingelgruppe mit 18 + 11 anlegen, 18 bekommt eine abwesende Person, 11 eine anwesende, door_sim ruft die Gruppe → 18 darf nicht klingeln.
- Danach: **Etappe 4** Widget/Schnellzugriff (App-only: Glance-Widget „Tür öffnen“ + letztes Klingelbild, TileService, App-Shortcuts).

## 5a18. Etappe 4: Schnellzugriff (App 1.3.0) + Fix Anlage 0.7.128

- `quick/DoorOpenConfirmActivity` (fragt immer nach, eine Tür: „Öffnen“, mehrere: Liste, dann `DoorOpenClient.open`), `quick/DoorOpenTileService` (Schnelleinstellungs-Kachel „Tür öffnen“, bei Sperre `unlockAndRun`), `res/xml/shortcuts.xml` (Kurzbefehle „Tür öffnen“ und „Klingel-Verlauf“ → Route `doorbell`). Türen = `DoorCodes.openRemoteNumbers()` (Türen mit Webhook). Im Emulator getestet: Rückfrage → „Tür 17 geöffnet“.
- Noch nicht gebaut: Startbildschirm-Widget mit Klingelbild (Glance). Das ist optional, Kachel und Kurzbefehle decken den Hauptnutzen ab.
- Anlage 0.7.128: Die HA-Personen des Nutzers melden zu Hause **„Zuhause“** (Name von zone.home) statt `home`. `ha_presence` zählt jetzt `home` plus den friendly_name von `zone.home`. Personen: person.sandro, person.larissa, person.nils, person.smarthome, person.ipad, person.kiosk, person.nfc1.

## 5a19. >>> NACH /clear HIER STARTEN (2026-09-25 abends) <<<

**Stand:** App **1.3.0** (Release-Build signiert, arm64 74 MB), Anlage **0.7.129** auf der Box. Alle vier Etappen des Ausbauplans (`docs/superpowers/plans/2026-09-25-ausbau-release-klingelverlauf.md`) sind fertig und im Emulator getestet. Beide Repos gepusht.
- Anwesenheit **live bestanden** mit 0.7.129: Beim Nutzer ist „Zuhause“ eine eigene Zone (`zone.zuhause`, überlappt `zone.home` „Home“). Als zu Hause zählen jetzt `home`, zone.home und jede mit ihr überlappende Zone (`ha_presence.home_zone_names`). Test-Klingelgruppe 98 und die Test-Personen an 12/18 sind wieder entfernt.
- Emulator: läuft die **Release-App** (Upload-Signatur), gekoppelt auf 18, Tailscale aktiv (100.88.202.107). `snapshot_server.py` (Port 8098) und der Webhook-Empfänger (8099) laufen auf CCsrv. Nebenstelle 17 hat Klingelbild-Quelle `http://192.168.101.113:8098/snapshot.jpg`.
- Arbeitsweise laut Nutzer: **immer weitermachen, nicht warten** (autonom, nur Ergebnisse melden).

**Wartet auf den Nutzer:**
1. Keystore sichern: `no-git/release/haphone-upload.jks` + `app-flutter/android/key.properties`.
2. Akuvox (Nebenstelle 16): Klingelbild-Quelle eintragen (HA-Kamera oder Snapshot-URL), „Testbild holen“.
3. „Gehört zu (HA-Person)“ bei den Handy-Nebenstellen setzen (person.sandro, person.larissa, person.nils).
4. Handy-Test nach `docs/test/handy-test.md` (APK `app-flutter/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`, vorher mit `bash app-flutter/scripts/build_release.sh` neu bauen).

**Nächste sinnvolle Schritte (eigene Vorschläge, noch nicht beauftragt):**
- Start-Seite Rest aus Etappe 2: Heute-Leiste (verpasste Anrufe, neue Voicemails) und Favoriten-Vorschläge statt leerer Liste.
- Startbildschirm-Widget (Glance) mit letztem Klingelbild + „Tür öffnen“.
- Türnamen in Kachel/Kurzbefehl (heute „Tür 17“, Namen aus dem Car-Directory-Store holen).
- Offene Sicherheitspunkte: SIP-TLS `verifyServer` + Zertifikat-Fingerprint im QR, HTTPS zur Anlage, Lizenzfrage PJSIP (GPL).
- Rückfall auf die echte Mobilnummer, wenn die App nicht erreichbar ist.

## 5a20. App 1.4.0 (2026-09-25 abends): Start-Seite fertig + Türnamen

- **Heute-Leiste** auf Start (`utils/today.dart` `todaySummary`): Anrufe heute, verpasst (→ Verlauf „Verpasst“), Türklingeln heute (→ Verlauf „Tür“). Erscheint nur, wenn heute etwas war. Als `Wrap` gebaut, nicht als horizontale Scrollzeile: Eine zweite `Scrollable` bricht `scrollUntilVisible` in den Tests.
- **Favoriten-Vorschläge**, solange keine Favoriten existieren (`suggestFavorites`): Die meistgewählten Nummern aus dem Verlauf, ohne die eigene Nummer, ohne Türen und ohne `*`-Codes. Der Stern auf der Kachel macht daraus einen Favoriten.
- Kachel/Kurzbefehl „Tür öffnen“ zeigen den **Türnamen** aus dem CarDirectoryStore (`CarDirectory.doorLabel`) statt „Tür 17“.
- 414 Dart-Tests grün, Kotlin-Unit grün, Release gebaut und im Emulator installiert (Heute-Leiste sichtbar geprüft).
- Offen aus den eigenen Vorschlägen: Glance-Widget, Sicherheitspunkte (TLS verifyServer + Fingerprint im QR, HTTPS), Rückfall auf die Mobilnummer.

## 5a21. Fix App 1.4.1: Absturz nach dem Koppeln auf Android 8/9 (Mi 6 des Nutzers)

- Symptom: SIGABRT `Unknown reference: 42` in `libgojni.so`, ca. 2 s nach dem Tailscale-Start. Auf einem Android-9-Emulator (`haphone_api28`, Port 5556) nachgestellt.
- Ursache: `VpnService.Builder.setMetered` gibt es erst ab API 29. Der `NoSuchMethodError` in `TsVpnService.newBuilder()` blieb im Go-Callback offen (`NewBuilder` hat keinen Fehler-Rückgabewert), und der nächste JNI-Aufruf (`Seq.getRef` → null) brach die App ab.
- Fix: `setMetered` nur ab Android 10. Alle Go-Callbacks ohne Fehler-Rückgabewert laufen jetzt durch `goSafe` (`tailscale/GoCallback.kt`). Lint `NewApi` ist sauber.
- Anlage 0.7.130 ist eingespielt (HTTPS 8443, Fingerabdruck im QR). Die App-Seite der Absicherung (Pinning) folgt.

## 5a22. Absicherung App 1.5.0 + Anlage 0.7.130: HTTPS und Zertifikat-Pinning

- **Anlage:** `backend/tls_pin.py` (SHA-256 des PJSIP-Zertifikats), `backend/serve.py` (ein Prozess, HTTP :80 mit Lifespan + HTTPS :8443 ohne Lifespan). QR-Link `&fp=<sha256>&https=8443`, `/provision/complete` und `/config` liefern `tls_fingerprint` und `api_https_port`.
- **App:** `net/PbxTls.kt` (Kotlin, alle nativen HTTP-Aufrufe über `PbxTls.open`), `services/pbx_tls.dart` (Dart, `PinnedClients`, keine Stammzertifikate, nur der Pin zählt). `DeviceAuth.baseUri` ist https://host:8443, sobald ein Pin da ist. Die Kopplung läuft gepinnt, wenn der QR `fp` enthält. Bestandskopplungen übernehmen den Pin einmalig aus `/api/mobile/config` (`DirectoryRepository._learnTlsPin`). SIP-TLS: `HAPhoneEndpoint.checkPin` trennt den Transport bei falschem Zertifikat **vor** dem Senden des REGISTER. Voicemail- und Aufnahme-Audio werden bei HTTPS direkt heruntergeladen (ExoPlayer kennt den Pin nicht). Diagnose zeigt „Verbindung zur Anlage: HTTPS · Zertifikat geprüft (…)“.
- Im Emulator geprüft: frische Kopplung (API 35, Nst. 18) und Bestandskopplung (API 28, Nst. 12): beide HTTPS gepinnt, auch über das Tailnet, SIP registriert.
- Ein einzelner Fehlschlag „Netzwerkfehler“ bei der ersten gepinnten Kopplung ließ sich nicht wiederholen. Seitdem loggt `qr_scan_screen` den Fehler (`provisioning failed:`).
- Nicht live getestet: der Negativfall (falsches Zertifikat), nur Unit-Tests (Kotlin `PbxTlsTest`, Dart `pbx_tls_test`).

## 5a23. App 1.6.0: Startbildschirm-Widget „Tür öffnen“ mit letztem Klingelbild

- `quick/DoorWidgetProvider.kt` (klassische RemoteViews, kein Glance): Titel = Türname, „zuletzt 15:13“/„gestern …“ (`DoorWidgetText`, getestet), letztes Klingelbild (in `filesDir/door_widget.jpg`, auf ≤ 480 px verkleinert), „Tür öffnen“ → `DoorOpenConfirmActivity` (fragt immer nach), Tipp aufs Bild → Klingel-Verlauf. Aktualisierung: System alle 30 min, Dart `DoorbellRepository` bei neuem Klingeln (`refreshDoorWidget`), `DoorbellMissedNotifier` nach verpasstem Klingeln. Entkoppeln löscht Bild und Zeit.
- Im Emulator geprüft: Widget hinzugefügt, Bild + Uhrzeit sichtbar, „Tür öffnen“ → Rückfrage „Tür-Simulator wird geöffnet.“ → Webhook `door_open` angekommen, Bild antippen → Klingel-Verlauf.
- Test-Setup: Webhook-Empfänger `hook.py` (Port 8099) loggt nach `/tmp/claude-1000/-home-roto/597bb650-…/scratchpad/hook.log`.
- Nächste eigene Vorschläge: Rückfall auf die Mobilnummer (braucht Entscheidungen des Nutzers: Trunk, Kosten), Lizenzfrage PJSIP (GPL), iOS (Mac nötig).

## 5a24. Rückfall auf die Handynummer (Anlage 0.7.131) + Lizenzen (App 1.6.1)

- Nutzer: „Do it you best“, also habe ich selbst entschieden. Anlage: `Extension.mobile_fallback` (leer = aus, Feld „Rückfall auf Handynummer“ im Nebenstellen-Editor). Im Standard-Landing `ext-N`: keine registrierten Kontakte oder `DIALSTATUS=CHANUNAVAIL` → `Dial(Local/<E.164>@outbound-pstn/n,30)` mit Trunk-CLIP (`__OUTBOUND_CID`), danach die Mailbox. Klingelt ein Gerät, ohne dass jemand abnimmt, geht es wie bisher auf die Mailbox. Greift nicht bei Klingelgruppen, Anwesenheitsregeln (always_dest/ring_then_dest) und im Altgeräte-Modus. Tests: `backend/tests/test_mobile_fallback.py`. **Nicht live getestet** (echter Anruf ins Mobilnetz = Kosten und die Nummer des Nutzers).
- Lizenzen: Die App-Lizenzseite zeigt jetzt auch PJSIP (GPL), libsrtp, OpenSSL, Opus, Tailscale, wireguard-go und Go (`assets/licenses/`, `kBundledLicenses` in main.dart). Entscheidungsgrundlage GPL-Konflikt: `docs/lizenz-pjsip.md`. Kurz: kein Problem, solange die App nicht weitergegeben wird. Vor einer Weitergabe entweder GPL (nur Android) oder eine kommerzielle PJSIP-Lizenz (für iOS).

## 5b. Nächste Schritte (nach /clear hier weitermachen)

**Reihenfolge (Stand 2026-09-24 mittags):** 1. "Dauerhaft erreichbar" (Wecker im Doze, Keep-Alive, Wächter; Test: `dumpsys deviceidle force-idle`, lange warten, Türanruf) → 2. Redesign Etappe 2 (Gespräch, Mehr, zwei Leitungen, Statusleiste im hellen Modus) → 3. Etappe 3 (nativer Klingelbildschirm mit Schieberegler → `POST /api/mobile/door-open`, Webhook; Start-Türkarte auf "Tür öffnen" umstellen, wenn `door_open_remote`) → 4. Etappe 4 (Status-Blatt, "Klingeln auf diesem Handy", Erreichbarkeits-Check) → 5. Android Auto (DHU-Test, Car App Library "Calling") → README-Screenshots erneuern. Nutzer will kein Firebase/Push vorerst.

1. **Phase 6 Extras** (Nutzer: "mach weiter"):
   - Gesprächsaufzeichnung: Anlage `Extension.recording_allowed` (Standard aus, Hinweis zur Rechtslage im Admin), App-Endpunkt `POST /api/mobile/recording {start|stop}` → AMI `MixMonitor` / `StopMixMonitor` auf den Kanal der Nebenstelle; Aufnahmen unter `/data/recordings/<ext>/`, `GET /api/mobile/recordings` + Audio. App: Taste "Aufnehmen" im Gesprächsbildschirm (nur wenn erlaubt), Liste im Ich-Reiter.
   - Gespräch umlegen (Call Flip): Code `*55` in der Anlage holt das laufende Gespräch der eigenen Nebenstelle auf das wählende Gerät (Bridge/Pickup des anderen Kanals derselben Nebenstelle).
2. Anklopfen, Ton, Bluetooth und Akuvox-Video brauchen ein echtes Handy und einen zweiten Anrufer. Noch nicht getestet.
3. Phase 8 (Push-Wecken) braucht ein Firebase-Projekt und einen Service-Account vom Nutzer, Phase 7 (iOS) einen Mac und ein Apple-Konto.

Arbeitsweise: nach jeder Änderung an der Anlage `config.yaml`-Version erhöhen + CHANGELOG (Deutsch), pushen, `cd no-git/tools && python3 deploy_pbx.py` im Hintergrund. App-Tests: `flutter analyze` + `flutter test`, APK mit `flutter build apk --debug`, Emulator per adb. Emulator läuft ggf. noch (sonst starten, siehe unten). Keine schweren Builds parallel zum Emulator.

Türstation / Klingelgruppe:
- **Klingelgruppen-Problem** (siehe Fallstricke): Die Vorschau an mehrere Geräte gleichzeitig geht nur, wenn die Türstation selbst mehrere Ziele parallel anruft oder die Anlage einen eigenen Türklingel-Modus bekommt.
   Türstation: **Akuvox R20K**, Firmware 20.30.4.147, IP `192.168.7.46`, als Nebenstelle **16** an der HA-Box registriert.
   Lösung: Web-UI → **Intercom → Basic → Push Button**: statt der Gruppe die Nebenstellen **mit `;` getrennt** eintragen (z. B. `13;11`). Die Akuvox ruft dann jedes Ziel gleichzeitig mit eigenem INVITE an. Asterisk macht dann pro Anruf einen Dial mit genau einem Ziel, und Early Media geht an jedes Gerät. Das neuere Menü (Call Type → Group Call, Dial Plan Replace) gibt es erst ab Firmware 320.x.
   Dazu auf der Akuvox H.264 als Video-Codec des Accounts aktiv lassen.

Außerdem offen (unverändert):

- `x86_64`-PJSIP ist seit 2026-09-23 abends neu gebaut (TLS + Video). **Emulator statt Handy** (das OnePlus ist nicht mehr verfügbar): AVD `haphone_test_api35` (Android 15, Pixel 6) auf CCsrv, headless starten mit `~/android-sdk/emulator/emulator -avd haphone_test_api35 -no-window -gpu swiftshader_indirect -no-snapshot-save -no-boot-anim -memory 4096 &`, bedienen per `adb` (Screenshots `adb exec-out screencap -p`). Koppeln ohne Kamera: `adb shell am start -a android.intent.action.VIEW -d '<haphone://provision?... aus dem Admin-QR>'`.
- **CCsrv-RAM:** Am 2026-09-23 16:57 hat der OOM-Killer des Proxmox-Hosts (62 GB, überbucht) die VM beendet, während Emulator + PJSIP-Build liefen. CCsrv ist jetzt auf 32 GB begrenzt. Schwere Builds und Emulator nicht gleichzeitig starten.
- iOS: `ios-app/.../PjsuaBridge.mm` hat dieselbe Lücke (kein `transportCreate`), und dem iOS-PJSIP fehlen vermutlich ebenfalls TLS und Video.
- Kaltstart-Race Dart ↔ Channel-Registrierung ist nur umgangen (`_invokeResilient`), nicht behoben.


## 6. Git-Stand ha-phone-app

- Die App hat ihr eigenes Repo **`iron-exx/ha-phone-app`** (dieser Ordner).
- Pushen (Claude darf das selbst, Token liegt in `no-git/token.txt`, nicht versioniert): `git push "https://$(tr -d '[:space:]' < no-git/token.txt)@github.com/iron-exx/ha-phone-app.git" main`. Den Token nie in `.git/config` oder eine Datei im Repo schreiben. Die Anlage liegt getrennt in `Ha-Phone` → `iron-exx/HA-Phone`.
- Seit 2026-09-23 ist alles committet: `app-flutter/`, Build-Skript, Referenz-Apps, `HANDOFF.md`, `docs/`, `.planning/`. `*.hprof` steht in `.gitignore`.
- Die selbst gebauten Libraries (OpenSSL, `libpjsua2.so`, SWIG-Java) liegen nur auf CCsrv (gitignored). Sie lassen sich per Skript reproduzieren.

## 7. Fallstricke (teuer gelernt, bitte nicht wiederholen)

**PJSIP / PJSUA2**
- **Kein Transport → SIGABRT** in `pjsua_acc_add`: Nach `libStart()` muss `transportCreate(TLS)` kommen (`PjsuaEndpointHolder.start()`).
- **`PJ_DEBUG` muss 0 sein** (`config_site.h`). Mit 1 bricht ein internes `pj_assert` in `pjsua_init()` die App ab.
- **TLS braucht `--with-ssl`**. Beim Cross-Compilen deaktiviert configure SSL sonst stillschweigend, und es kommt `PJSIP_EUNSUPTRANSPORT`.
- **SWIG-Makefile verlinkt nicht neu**: vor `make java` die alte `libpjsua2.so` und `output/pjsua2_wrap.*` löschen.
- **srtp-Archiv bleibt nach `make clean` liegen**: nach dem Wechsel auf OpenSSL doppelte Symbole (`aes_icm` / `aes_icm_ossl`). `third_party/lib/libsrtp-*.a` löschen.
- **Registrar-URI braucht `;transport=tls`**, sonst nimmt PJSIP UDP, dafür gibt es keinen Transport.
- **Garbage-Collector-Falle bei Account und Call**: `Account.shutdown()` setzt die ID nicht zurück, und pjsua vergibt IDs neu. Räumt der GC später das alte Objekt ab, löscht `~Account()` das **neue** Konto mit derselben ID (die 13 wurde "grundlos" offline, danach `PJ_EINVALIDOP`). Gleiches gilt für `~Call()`, das einen neuen Anruf auflegen würde. Deshalb **immer sofort `delete()`**: nach `shutdown()` bzw. bei DISCONNECTED.
- **PJSIP nur vom Main-Thread aus steuern.** Callbacks (`onIncomingCall`, `onCallState`, …) kommen auf dem PJSIP-Worker-Thread. Für Telecom, UI und EventSink per `Handler(Looper.getMainLooper()).post` wechseln. Auch `ConnectivityManager`-Callbacks kommen aus einem fremden Thread.
- **Audio verbindet PJSUA2 nicht selbst**: `captureDevMedia.startTransmit(am)` + `am.startTransmit(playbackDevMedia)` bei CONFIRMED (`HAPhoneCall.connectAudio`).
- **Video braucht die `org.pjsip.PjCamera*`-Klassen** im sip-core, sonst stürzt die Video-Initialisierung ab.
- **SRTP** steht auf OPTIONAL: Nebenstellen haben standardmäßig `media_encryption=none`, und bei MANDATORY käme 488.

**Asterisk / Anlage**
- **Early Media nur bei genau einem Ziel.** `app_dial.c` `wait_for_answer`: `if (!single || caller_entertained) break;`. Die Vorschau am Fanvil klappt über die Gruppe "klingel" nur, weil die 12 offline ist. Sobald ein zweites Gerät klingelt, verlieren **alle** die Vorschau.
- Das Runtime-Image hat **kein `openssl`-CLI** (nur libssl3). Für Kryptoarbeit Python `cryptography` nutzen.
- `PATCH /extensions` nutzt `exclude_none`, Felder lassen sich also nicht auf null setzen, nur auf `""`.

**Android / Flutter**
- **Go-Callbacks (gomobile) dürfen nie werfen**, wenn die Go-Methode keinen `error` zurückgibt. Die Java-Ausnahme bleibt sonst offen, und der nächste JNI-Aufruf bricht mit `Unknown reference: <n>` ab. Immer `goSafe` benutzen. APIs über minSdk 26 per `SDK_INT` absichern und bei Android-Code `./gradlew :app:lintDebug` laufen lassen (NewApi).
- **Die Manifest-Permission `RECORD_AUDIO` fehlte**, das ergab `PJMEDIA_EAUD_INIT` beim Wählen.
- Fehler in Kotlin-Lambdas, die später in Coroutines laufen (z. B. `reportOutgoingCall { makeCall }`), liegen **außerhalb** des `try/catch` im MethodChannel-Handler und beenden die App. Dort selbst abfangen.
- Aufgelegt wird immer auch in Telecom (`releaseTelecomCall`), sonst hängt ein "wählt"-Anruf im System fest.
- Das Entfernen von `executeDartEntrypoint()` (Engine-Pre-Warm) wurde probiert und machte es **schlimmer** (weißer Bildschirm). Nicht wiederholen.
- `logcat -s TAG:I TAG:W`: Bei doppeltem Tag gilt nur das letzte. `PJSIP:V` nehmen.

**Arbeitsweise mit dem Nutzer**
- Der Nutzer testet selbst auf dem Handy und erwartet Tests auf dem echten Gerät, nicht nur "Build grün". Bei Abstürzen sofort `logcat` ziehen.
- Der Nutzer schreibt Deutsch, knapp. Er will Ergebnisse, keine langen Wartezeiten ohne Rückmeldung.
