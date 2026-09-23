# HA-Phone App – Übergabe

Stand: **2026-09-23**. Für die Fortsetzung in einer neuen Sitzung / auf einem anderen Rechner.
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

## 5. Nächste Schritte (in dieser Reihenfolge)

1. **Test mit der echten Türstation.** Video für die 13 anschalten, Türklingel so konfigurieren, dass *nur* die 13 klingelt, Vorschau prüfen. Logcat: `incoming call from … video=true`, `incoming video window N`.
2. **Klingelgruppen-Problem** (siehe Fallstricke): Die Vorschau an mehrere Geräte gleichzeitig geht nur, wenn die Türstation selbst mehrere Ziele parallel anruft oder die Anlage einen eigenen Türklingel-Modus bekommt. **Offene Frage an den Nutzer: welches Türstationsmodell?**
3. **App speichert das Geräte-Token noch nicht.** `lib/screens/qr_scan_screen.dart` verwirft `device_token`/`device_id` aus `/provision/complete`. Beides nativ in EncryptedSharedPreferences speichern (per Channel), dazu die API-Adresse (`host` aus dem QR). Danach **einmal neu koppeln**.
4. **Phase 2 der App (Linkus-Hülle):** fünf Reiter (Kontakte · Anrufe · Tastatur · Voicemail · Ich)
   - Kontakte aus `/api/mobile/directory` (Backend fertig)
   - Anrufliste: lokal im Nativcode führen (eingehend in `showIncomingSipCall`, ausgehend in `makeCall`, angenommen bei CONFIRMED, Ende in `onCallDisconnected`), per Channel an Dart
5. **Lautsprecher/Bluetooth**: `CallControlScope.availableEndpoints` + `requestEndpointChange`
6. **Video im Gespräch**: Flutter-PlatformView mit **TextureView** (nicht SurfaceView) → `VideoSurfaceBinder.setSurface`
7. **"Tür öffnen"**: DTMF-Code pro Nebenstelle in der Anlage, per Taste im Klingel- und Gesprächsbildschirm senden
8. Danach: Phasen 3–8 laut Schlachtplan (Präsenz, Voicemail, Profi-Gesprächsfunktionen, CDR-Sync, iOS, unterwegs)

Außerdem offen:
- `x86_64`-PJSIP ist **nicht** neu gebaut (hat weder TLS noch Video). BlueStacks funktioniert damit nicht, bis das Skript ohne `ANDROID_ABIS_OVERRIDE` läuft.
- iOS: `ios-app/.../PjsuaBridge.mm` hat dieselbe Lücke (kein `transportCreate`), und dem iOS-PJSIP fehlen vermutlich ebenfalls TLS und Video.
- Kaltstart-Race Dart ↔ Channel-Registrierung ist nur umgangen (`_invokeResilient`), nicht behoben.

## 6. Git-Stand ha-phone-app (Achtung)

- **`app-flutter/` ist nicht versioniert** (untracked im Repo `iron-exx/ha-phone-app`). Nutzerentscheidung offen: committen / eigenes Repo?
- Nicht committet: Änderungen in `android-app/app/.../HAPhoneTestApplication.kt`, `MainActivity.kt`, `TestFcmService.kt`, `ios-app/.../PushHandler.swift`, `android-app/scripts/build_pjsip_android.sh`, `.planning/phases/03–05`, `HANDOFF.md`, `docs/`.
- `android-app/java_pid*.hprof` sind Heap-Dumps von Gradle-Abstürzen, wegwerfbar (nicht committen).
- Die selbst gebauten Libraries (OpenSSL, `libpjsua2.so`) liegen nur auf CCsrv (gitignored). Sie lassen sich per Skript reproduzieren.

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
- **Die Manifest-Permission `RECORD_AUDIO` fehlte**, das ergab `PJMEDIA_EAUD_INIT` beim Wählen.
- Fehler in Kotlin-Lambdas, die später in Coroutines laufen (z. B. `reportOutgoingCall { makeCall }`), liegen **außerhalb** des `try/catch` im MethodChannel-Handler und beenden die App. Dort selbst abfangen.
- Aufgelegt wird immer auch in Telecom (`releaseTelecomCall`), sonst hängt ein "wählt"-Anruf im System fest.
- Das Entfernen von `executeDartEntrypoint()` (Engine-Pre-Warm) wurde probiert und machte es **schlimmer** (weißer Bildschirm). Nicht wiederholen.
- `logcat -s TAG:I TAG:W`: Bei doppeltem Tag gilt nur das letzte. `PJSIP:V` nehmen.

**Arbeitsweise mit dem Nutzer**
- Der Nutzer testet selbst auf dem Handy und erwartet Tests auf dem echten Gerät, nicht nur "Build grün". Bei Abstürzen sofort `logcat` ziehen.
- Der Nutzer schreibt Deutsch, knapp. Er will Ergebnisse, keine langen Wartezeiten ohne Rückmeldung.
