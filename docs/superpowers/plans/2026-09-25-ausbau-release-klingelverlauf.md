# HA-Phone Ausbau: Release, Klingel-Verlauf, Klingeln unterwegs, Widget – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Die App wird verteilbar (signierter, kleiner Release-Build, am echten Handy getestet). Danach bekommt sie die drei Funktionen mit dem größten Alltagsnutzen: Klingel-Verlauf mit Foto samt neuer Start-Seite, „Klingeln unterwegs nur, wenn keiner zu Hause ist“ und Widget/Schnellzugriff.

**Architecture:** Vier Etappen, jede für sich lieferbar. Etappe 1 ist hier bis auf Befehlsebene ausgeplant. Die Etappen 2–4 berühren jeweils eigene Teilsysteme (Anlage: Snapshot-Aufnahme, HA-Präsenz; App: Start-Reiter, Android-Widgets) und bekommen vor dem Start einen eigenen Detailplan unter `docs/superpowers/plans/`. Die Aufgabenlisten unten legen Umfang und Reihenfolge fest.

**Tech Stack:** Flutter (Dart) + Kotlin (PJSUA2, Telecom, libtailscale), Gradle/AGP 8.5, R8. Anlage: FastAPI/SQLModel, Asterisk 22, GStreamer/ffmpeg im Container, Home-Assistant-Supervisor-API.

**Spec:** Nutzer-Auftrag vom 2026-09-25 („Plan zusammenpacken und beginnen“) auf Basis der Ideenliste im Chat. Reihenfolge: 1 Release + Handy-Test → 2 Klingel-Verlauf mit Foto + Start-Seite → 3 Klingeln unterwegs, wenn keiner zu Hause → 4 Widget/Schnellzugriff. Ergänzend: `HANDOFF.md`, `docs/linkus-schlachtplan.html`, `docs/design/tailscale.md`.

## Global Constraints

- Builds laufen auf CCsrv. Nie ein schwerer Build parallel zum Emulator (OOM-Gefahr, HANDOFF 5).
- Flutter-SDK: `/home/roto/flutter/flutter/bin/flutter`, Android-SDK `~/android-sdk`, NDK 27.0.12077973.
- ABIs nur `arm64-v8a` (Handys) und `x86_64` (Emulator). PJSIP und libtailscale gibt es für andere ABIs nicht.
- Geheimnisse (Keystore, Passwörter, Tokens) liegen nur in `no-git/` und werden nie committet.
- Nach jeder Änderung an der Anlage: `config.yaml`-Version erhöhen + `CHANGELOG.md` (Deutsch), pushen, `no-git/tools/deploy_pbx.py`.
- App-Version in `app-flutter/pubspec.yaml` und `app-flutter/lib/app_info.dart` gemeinsam erhöhen.
- Texte in der App: Deutsch, „du“, keine Gedankenstriche als Satzverbinder.
- `HANDOFF.md` nach jeder Etappe aktualisieren (Nutzungslimit).

## Review Focus

- **Release-Build startet, ruft aber keine SIP-Callbacks mehr auf:** R8 benennt PJSUA2-Klassen um, die der native Code per Name aufruft (SWIG-Directors). Erwartung: Registrierung, eingehender Anruf und Anrufstatus funktionieren im Release-APK wie im Debug-APK → Smoke-Test in Task 4 prüft genau das.
- **Release-APK ersetzt Debug-APK nicht (andere Signatur):** `adb install` scheitert mit `INSTALL_FAILED_UPDATE_INCOMPATIBLE`. Erwartung: klar dokumentiert, dass vorher deinstalliert und neu gekoppelt werden muss → Task 4, Schritt 1 und Handy-Checkliste.
- **Build ohne Keystore (andere Rechner, CI):** Erwartung: Release-Build fällt auf Debug-Signatur zurück, statt abzubrechen → Task 1 prüft beide Fälle.
- **Tailscale im Release-APK:** gomobile-Klassen (`go.*`, `libtailscale.*`) dürfen nicht entfernt werden. Erwartung: Beitritt ins Tailnet klappt im Release-APK → Task 4, Schritt 5.
- **Klingelbildschirm über der Sperre im Release-APK:** Compose/Activity-Flags sind nicht von R8 betroffen, aber Kaltstart-Pfade schon. Erwartung: gesperrter Emulator, Tür-Simulator klingelt → Klingelbildschirm mit Bild → Task 4, Schritt 6.

---

## Etappe 1: Release-Build und Handy-Test (detailliert)

### Task 1: Release-Signatur (Upload-Key) mit Rückfall auf Debug

**Files:**
- Create: `no-git/release/haphone-upload.jks` (Keystore, nie committen)
- Create: `app-flutter/android/key.properties` (verweist auf den Keystore, gitignored)
- Modify: `app-flutter/android/app/build.gradle.kts` (signingConfigs + buildTypes.release)
- Modify: `app-flutter/.gitignore` (key.properties)

**Interfaces:**
- Produces: `signingConfigs["release"]`, das nur existiert, wenn `key.properties` vorhanden ist. Task 3 verlässt sich darauf.

- [ ] **Step 1: Keystore erzeugen (einmalig)**

```bash
mkdir -p /home/roto/projects/ha-phone-app/no-git/release
PW=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)
keytool -genkeypair -v -keystore /home/roto/projects/ha-phone-app/no-git/release/haphone-upload.jks \
  -alias upload -keyalg RSA -keysize 4096 -validity 10000 \
  -storepass "$PW" -keypass "$PW" -dname "CN=HA-Phone, O=systemwerk, C=DE"
printf 'storePassword=%s\nkeyPassword=%s\nkeyAlias=upload\nstoreFile=/home/roto/projects/ha-phone-app/no-git/release/haphone-upload.jks\n' "$PW" "$PW" \
  > /home/roto/projects/ha-phone-app/app-flutter/android/key.properties
chmod 600 /home/roto/projects/ha-phone-app/app-flutter/android/key.properties
```

- [ ] **Step 2: key.properties ignorieren**

`app-flutter/.gitignore` ergänzen: `android/key.properties`. Prüfen: `git check-ignore -v app-flutter/android/key.properties` meldet eine Regel.

- [ ] **Step 3: Gradle liest key.properties**

In `app/build.gradle.kts` vor `android {`:

```kotlin
val releaseKeyProps = java.util.Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.isFile) f.inputStream().use { load(it) }
}
```

In `android { ... }`:

```kotlin
signingConfigs {
    if (releaseKeyProps.getProperty("storeFile") != null) {
        create("release") {
            storeFile = file(releaseKeyProps.getProperty("storeFile"))
            storePassword = releaseKeyProps.getProperty("storePassword")
            keyAlias = releaseKeyProps.getProperty("keyAlias")
            keyPassword = releaseKeyProps.getProperty("keyPassword")
        }
    }
}
buildTypes {
    release {
        // Upload key from key.properties (no-git/); without it (other machines, CI) debug-signed.
        signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        isMinifyEnabled = true
        isShrinkResources = true
        proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
    }
}
```

- [ ] **Step 4: Beide Fälle prüfen**

Run: `cd app-flutter/android && ./gradlew :app:signingReport --console=plain | grep -A3 "Variant: release"`
Expected: `Store: .../no-git/release/haphone-upload.jks`, Alias `upload`.
Danach `key.properties` kurz umbenennen, erneut ausführen → Expected: debug.keystore. Zurückbenennen.

- [ ] **Step 5: Commit**

```bash
git add app-flutter/.gitignore app-flutter/android/app/build.gradle.kts
git commit -m "build(app): Release-Signatur aus key.properties (no-git), sonst Debug"
```

### Task 2: R8-Regeln für PJSUA2, Tailscale und JNI

**Files:**
- Create: `app-flutter/android/app/proguard-rules.pro`

**Interfaces:**
- Consumes: `proguardFiles(..., "proguard-rules.pro")` aus Task 1.

- [ ] **Step 1: Regeln schreiben**

```proguard
# PJSUA2 (SWIG): native code calls SwigDirector_* callbacks and Java classes by name.
-keep class org.pjsip.** { *; }
-keepclassmembers class * { native <methods>; }
# gomobile / libtailscale (also shipped as consumer rules in the AAR, kept explicit).
-keep class go.** { *; }
-keep class libtailscale.** { *; }
# Our classes implementing libtailscale / PJSUA2 interfaces are called from native code.
-keep class de.haphone.app.test.tailscale.** { *; }
-keep class de.haphone.app.test.sip.** { *; }
# Flutter embedding is covered by the Flutter Gradle plugin's own rules.
```

- [ ] **Step 2: Release-Build kompiliert**

Run: `cd app-flutter && /home/roto/flutter/flutter/bin/flutter build apk --release --split-per-abi --target-platform android-arm64,android-x64`
Expected: `✓ Built build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` und `app-x86_64-release.apk`, keine R8-Fehler (fehlende Klassen als `-dontwarn` nur ergänzen, wenn der Build sie nennt, mit Begründung im Kommentar).

- [ ] **Step 3: Commit**

```bash
git add app-flutter/android/app/proguard-rules.pro
git commit -m "build(app): R8-Regeln für PJSUA2, libtailscale, JNI"
```

### Task 3: Release-Skript mit Größenbericht

**Files:**
- Create: `app-flutter/scripts/build_release.sh`

- [ ] **Step 1: Skript**

```bash
#!/usr/bin/env bash
# Release-APKs (pro ABI) + App Bundle. Aufruf auf CCsrv, nicht parallel zum Emulator.
set -euo pipefail
cd "$(dirname "$0")/.."
FLUTTER=/home/roto/flutter/flutter/bin/flutter
$FLUTTER build apk --release --split-per-abi --target-platform android-arm64,android-x64
$FLUTTER build appbundle --release --target-platform android-arm64,android-x64
ls -l build/app/outputs/flutter-apk/*-release.apk build/app/outputs/bundle/release/*.aab
grep -q "no-git/release" android/key.properties 2>/dev/null \
  && echo "signiert mit Upload-Key" || echo "WARNUNG: debug-signiert (kein key.properties)"
```

- [ ] **Step 2: Ausführen, Größen notieren**

Run: `bash app-flutter/scripts/build_release.sh`
Expected: arm64-APK deutlich unter 100 MB (Debug: 333 MB für beide ABIs). Werte ins HANDOFF.

- [ ] **Step 3: Commit**

```bash
git add app-flutter/scripts/build_release.sh
git commit -m "build(app): build_release.sh (APK pro ABI + AAB, Größenbericht)"
```

### Task 4: Smoke-Test des Release-APK im Emulator

**Files:**
- Create: `docs/test/release-smoke.md` (Protokoll mit Ergebnis)

- [ ] **Step 1: Debug-App ersetzen** (andere Signatur, Kopplung geht verloren)

```bash
ADB=~/android-sdk/platform-tools/adb
$ADB uninstall de.haphone.app.test
$ADB install app-flutter/build/app/outputs/flutter-apk/app-x86_64-release.apk
$ADB shell appops set de.haphone.app.test ACTIVATE_VPN allow
```

- [ ] **Step 2: Kaltstart ohne Absturz**

`$ADB shell am start -n de.haphone.app.test/.MainActivity`, 10 s warten, `$ADB logcat -d | grep -E "AndroidRuntime|FATAL"` → Expected: leer.

- [ ] **Step 3: Kopplung per Link** (`no-git/tools/provision_link.py 18`, `am start -a android.intent.action.VIEW -d '<link>' de.haphone.app.test`) → Expected: Erreichbarkeit „Alles bereit“.

- [ ] **Step 4: SIP-Registrierung** → Expected: `pbx_admin.py GET /api/extensions/status` meldet 18 `Online`.

- [ ] **Step 5: Tailscale** → Expected: Logtag `TailnetManager` meldet „PBX route -> tailnet“, `REGISTER sip:100.117.178.114:5063` → 200.

- [ ] **Step 6: Türanruf bei Sperre** → Emulator sperren (`input keyevent 26`), `door_sim.py --to 18 --pbx 192.168.7.10 --duration 25` → Expected: Klingelbildschirm über der Sperre mit Livebild. Annehmen (Tap auf „Annehmen“), Gespräch steht, Auflegen.

- [ ] **Step 7: Ausgehender Anruf** `*43` (Echo) → Expected: CONFIRMED im Log, Auflegen sauber.

- [ ] **Step 8: Protokoll + Commit** — Ergebnisse in `docs/test/release-smoke.md`, `git commit -m "test: Release-Smoke-Test im Emulator"`.

### Task 5: Handy-Test-Checkliste für den Nutzer

**Files:**
- Create: `docs/test/handy-test.md`

- [ ] **Step 1: Checkliste schreiben** — Installation (APK per USB/Download, „Unbekannte Apps“), Kopplung per QR, VPN erlauben, dann: (a) im WLAN anrufen lassen, (b) WLAN aus → Mobilfunk → Anruf von Nebenstelle 11 und Türanruf (Ton beide Richtungen, Türvideo), (c) Handy 30 min gesperrt liegen lassen → Türanruf, (d) Tür per Schieberegler öffnen, (e) Anruf aus dem Handy nach extern. Pro Punkt: erwartetes Ergebnis und was mir bei Fehler geschickt werden soll (Uhrzeit, Screenshot).
- [ ] **Step 2: Commit + dem Nutzer die APK bereitstellen** (Pfad auf `\\192.168.101.113\projects\ha-phone-app\app-flutter\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk`).

---

## Etappe 2: Klingel-Verlauf mit Foto + neue Start-Seite (Detailplan folgt vor Start)

Umfang (festgelegt):
1. **Anlage – Snapshot beim Klingeln:** Ruft eine Türstation (Video im INVITE bzw. Nebenstelle mit Tür-Merkmal) an, nimmt die Anlage einen Frame aus dem H.264-Stream auf (Asterisk-Seitenzweig per `ChanSpy`/`MixMonitor` Video oder eigener RTP-Empfänger mit ffmpeg). Ablage `/data/doorbell/<ext>/<YYYYmmdd-HHMMSS>.jpg`, Aufbewahrung 30 Tage, maximal 500 Einträge.
2. **Anlage – API:** `GET /api/mobile/doorbell?limit=` (Ereignisse: Zeit, Tür, angenommen von, Tür geöffnet ja/nein, Bild-URL), `GET /api/mobile/doorbell/{id}/image`, Admin-Ansicht „Klingel-Verlauf“.
3. **App – Start-Reiter neu:** Die Türkarte zeigt das letzte Klingelbild mit Uhrzeit, darunter HA-Aktionen als Chips. Neue Heute-Leiste (verpasste Anrufe, neue Voicemails). Favoriten mit Vorschlägen (häufigste Kontakte) statt leerer Liste.
4. **App – Klingel-Verlauf:** Liste mit Vorschaubildern, Vollbild, „Zurückrufen“ an die Tür.
5. **App – verpasstes Klingeln:** Benachrichtigung mit Bild (BigPictureStyle).
Tests: Backend (pytest, Snapshot-Pfad mit Test-JPEG), Dart-Widget-Tests für Start-Seite und Verlauf, E2E mit `door_sim.py` (Testbild mit Uhr, Bild muss die Uhrzeit zeigen).

## Etappe 3: Klingeln unterwegs, nur wenn keiner zu Hause ist (Detailplan folgt)

Umfang: Die Anlage liest über die Supervisor-API (`homeassistant_api` ist schon an) die `person.*`-Zustände. Admin-Einstellung pro Nebenstelle/Handy: „Dieses Handy gehört zu Person X“. Neue Klingelregel für Türstationen: „Handys unterwegs klingeln nur, wenn niemand zu Hause ist“, zu Hause verhält sich alles wie heute. Umsetzung im Dialplan per Func/AGI-freier Variante: Die Anlage schreibt bei Zustandswechsel (HA-Websocket-Abo) eine AstDB-Variable `DEVICE_AWAY/<ext>`, der Dialplan filtert Kontakte der Tür-Klingelgruppe. Tests: Backend-Unit für die Regelentscheidung, E2E mit gesetzter AstDB-Variable und `door_sim.py`.

## Etappe 4: Widget und Schnellzugriff (Detailplan folgt)

Umfang: Android-Startbildschirm-Widget (Glance) „Tür öffnen“ + letzte Klingel (Bild aus Etappe 2), Schnelleinstellungs-Kachel „Tür öffnen“ (TileService, mit Bestätigung), App-Shortcuts beim langen Druck aufs Symbol („Tür öffnen“, „Echo-Test“, „Nicht stören 1 h“). Alle Aktionen nutzen `DoorOpenClient`/`DoorActionClient`. Tests: Kotlin-Unit für die Aktionslogik, manuell im Emulator.

---

## Self-Review

- Spec-Abdeckung: Alle vier Punkte der Reihenfolge haben eine Etappe. Punkt 1 ist bis auf Befehle ausgeplant, 2–4 mit festgelegtem Umfang und eigenem Detailplan vor Start (getrennte Teilsysteme).
- Platzhalter: In Etappe 1 keine. Die Etappen 2–4 sind bewusst Umfangsbeschreibungen und kein Ausführungsplan.
- Konsistenz: `signingConfigs["release"]` (Task 1) wird in Task 3 nur über `key.properties` geprüft. Die APK-Namen `app-<abi>-release.apk` kommen aus `--split-per-abi`.
