# HA-Phone App

**Die Telefon-App zu [HA-Phone](https://github.com/iron-exx/HA-Phone), der Telefonanlage als Home-Assistant-Add-on.**
Dein Handy wird zur Nebenstelle: Es klingelt wie ein normales Telefon, zeigt an der Haustür das Kamerabild schon *bevor* du abhebst, und die Tür öffnest du mit einem Wisch, zu Hause wie unterwegs.

![HA-Phone App: Türstation klingelt bei gesperrtem Handy, Türgespräch, Start, Klingel-Verlauf](docs/screenshots/hero.png)

> Aktueller Stand: **Android, Version 1.6** (Test-Phase). iOS folgt.
> Voraussetzung: Home Assistant mit dem Add-on **HA-Phone**, empfohlen **ab 0.7.140** (der Schalter „Türstation“ kam mit 0.7.138).
> Alle Screenshots zeigen Beispieldaten.

---

## Was die App kann

### 🚪 Türstation mit Live-Bild
- Klingelt es an der Tür, wacht das Handy auf, auch **gesperrt und mit dunklem Bildschirm**. Das **Live-Bild der Kamera** läuft schon während des Klingelns (SIP Early Media, wie am Tischtelefon). Das funktioniert mit jeder SIP-Türstation mit H.264-Video, z. B. Akuvox, 2N, DoorBird oder Fanvil.
- **„Zum Öffnen nach rechts schieben“**: Der Schieberegler öffnet die Tür über einen **Webhook** (z. B. eine Home-Assistant-Automation), **ohne abzuheben**. Kurzes Schieben schnappt zurück, damit nichts versehentlich aufgeht. Im Gespräch geht es auch per Tür-Code (DTMF).
- **Home-Assistant-Tasten** direkt am Klingel- und Gesprächsbildschirm, z. B. „Licht Eingang“ oder „Garage“. Welche es gibt, legt der Admin in HA-Phone fest.
- **Türklingel auch bei lautlos** (optional): Die Tür klingelt dann wie ein Wecker, auch wenn das Handy auf lautlos oder Vibration steht.

<p>
  <img src="docs/screenshots/tuer-klingelt-gesperrt.png" width="200" alt="Türstation klingelt bei gesperrtem Handy, mit Live-Bild, Home-Assistant-Taste und Schieberegler">
  <img src="docs/screenshots/tuer-klingelt.png" width="200" alt="Türstation klingelt, Live-Bild vor dem Abheben">
  <img src="docs/screenshots/tuergespraech.png" width="200" alt="Türgespräch mit Video, Tür öffnen und Licht-Taste">
</p>

### 🖼 Klingel-Verlauf mit Foto
- Bei jedem Klingeln macht die Anlage ein Foto. Der **Klingel-Verlauf** zeigt, wann es geklingelt hat, **wer angenommen hat** und ob **die Tür geöffnet** wurde. Du öffnest ihn über „× geklingelt“ auf der Startseite oder über „Verlauf ›“ auf der Türkarte.
- Hat niemand abgenommen, meldet sich die App mit **„Es hat geklingelt“** samt Foto.
- Auf der **Startseite** sitzt jede Tür als eigene Karte mit dem letzten Klingelbild, „Tür öffnen“ und den Home-Assistant-Tasten.
- **Weitere Kameras**: Unter *Ich → Weitere Kameras* wählst du Kameras aus Home Assistant, etwa Garten oder Einfahrt. Sie erscheinen als Live-Bilder auf der Startseite, im Klingelbildschirm und im Gespräch mit der Tür. Ein Tipp zeigt das Bild groß. Zur Auswahl stehen nur Kameras, die der Admin in der Anlage freigegeben hat (HA-Phone 0.7.141 oder neuer).
- **Schnell öffnen ohne App zu starten**: Startbildschirm-Widget „Tür öffnen“ mit dem letzten Klingelbild, Kachel in den Schnelleinstellungen und App-Kurzbefehle. Zur Sicherheit wird immer noch einmal nachgefragt.

<p>
  <img src="docs/screenshots/start.png" width="200" alt="Startseite mit Türkarten und Heute-Leiste">
  <img src="docs/screenshots/klingel-verlauf.png" width="200" alt="Klingel-Verlauf mit Fotos">
</p>

### 🌍 Unterwegs erreichbar
- **Eingebautes Tailscale**: Unterwegs im Mobilfunk verbindet sich die App über dein Tailscale-Netz mit der Anlage. Du brauchst keine Portfreigabe und keinen Umbau am Router. Zu Hause oder über ein VPN nimmt sie den direkten Weg und wechselt beim Verlassen des WLANs von selbst.
- **Nur klingeln, wenn es Sinn ergibt** (in HA-Phone einstellbar): Ist jemand zu Hause, klingelt die Tür nicht auf den Handys derer, die unterwegs sind. Ist niemand zu Hause, klingelt sie überall.
- **Rückfall auf die Handynummer** (in HA-Phone einstellbar): Ist die App gerade nicht erreichbar, ruft die Anlage stattdessen deine normale Mobilnummer an.

### 📞 Telefonieren wie mit einer Profi-Anlage
- **Zuverlässig erreichbar, auch nach Tagen ohne Anruf**: Die App bleibt dauerhaft an der Anlage angemeldet (TLS). Ein Wecker, der auch im Android-Tiefschlaf (Doze) feuert, erneuert die Anmeldung rechtzeitig, und ein Wächter prüft alle 15 Minuten. Anrufe erscheinen wie normale Anrufe über das Android-Telefonsystem, auch auf dem Sperrbildschirm, mit Bluetooth-Headset und in Android Auto.
- **Zwei Leitungen**: Anklopfen, Halten, Makeln, Rückfrage, Weiterleiten mit und ohne Rückfrage, 3er-Konferenz.
- **Gespräch umlegen**: Läuft ein Gespräch am Tischtelefon, holst du es mit einem Tipp aufs Handy („Hierher holen“), oder mit `*55` in die andere Richtung.
- **Heranholen**: Klingelt es bei Kolleg:innen, nimmst du den Anruf mit „Heranholen“ an dein Handy.
- **Video**: Rufst du eine videofähige Nebenstelle an, etwa die Türstation, siehst du ihr Bild.
- **Freizeichen** beim Wählen, **Echo-Test** mit `*43`.
- **Übersichtlicher Gesprächsbildschirm**: 6 große Tasten statt eines Tastenmeers. Alles Weitere (Konferenz, Rückfrage, Aufnahme, Audio-Ausgabe mit Bluetooth-Gerätenamen) steckt im Menü „Mehr“.

<p>
  <img src="docs/screenshots/mehr.png" width="200" alt="Menü Mehr im Gespräch">
  <img src="docs/screenshots/waehlen.png" width="200" alt="Wähltastatur">
</p>

### 👥 Kontakte, Status und Verlauf
- **Alle Kontakte in einer Liste**: Türstationen, Nebenstellen der Anlage mit **Live-Status** (frei, klingelt, telefoniert), das Telefonbuch der Anlage und die Kontakte vom Handy.
- **Status** (verfügbar, abwesend, nicht stören, Feierabend) sehen alle anderen sofort, jeweils mit Farbe *und* Zeichen, damit er auch bei Farbschwäche lesbar ist.
- **Weiterleitungen je Status**: z. B. „Nicht rangegangen → nach 20 s → Voicemail“.
- **Verlauf**: Anrufe, **Voicemails** mit eingebautem Player (1×, 1,5×, 2×) und **Aufnahmen** in einer Liste, mit Filtern. Verpasstes ist farbig markiert.

<p>
  <img src="docs/screenshots/verlauf.png" width="200" alt="Verlauf mit Filtern">
  <img src="docs/screenshots/kontakte.png" width="200" alt="Kontakte mit Türstationen und Live-Status">
</p>

### 🔔 Klingeln auf diesem Handy und Erreichbarkeits-Check
- **Status für alle** und getrennt davon **„Klingeln auf diesem Handy“**: stumm für 1 Stunde, bis 17:00 oder bis morgen. Tischtelefon und andere Geräte klingeln weiter, und die **Türklingel kommt auf Wunsch trotzdem durch**, auf Wunsch sogar laut bei lautlos gestelltem Handy.
- **Erreichbarkeit**: Die App prüft alles, was fürs zuverlässige Klingeln nötig ist (Benachrichtigungen, Vollbild-Anrufe, Akku-Optimierung, genaue Wecker, Verbindung zur Anlage), zeigt es grün oder gelb und behebt es mit einem Tipp. Für Samsung, Xiaomi, Huawei, OnePlus und Oppo gibt es passende Schritt-für-Schritt-Hinweise. Mit **„Test-Anruf an mich“** klingelt die Anlage dieses Handy gezielt an.

<p>
  <img src="docs/screenshots/ich.png" width="200" alt="Status und Klingeln auf diesem Handy">
  <img src="docs/screenshots/erreichbarkeit.png" width="200" alt="Erreichbarkeits-Check">
</p>

### ⏺ Gesprächsaufzeichnung
- Taste „Aufnehmen“ im Gespräch, mit rotem REC-Hinweis und Laufzeit. Aufnahmen hörst du in der App ab und löschst sie dort.
- **Standardmäßig aus.** Der Admin schaltet sie pro Nebenstelle frei. Aufzeichnen ist in Deutschland nur mit Zustimmung aller Gesprächsteilnehmer erlaubt (§ 201 StGB).

### 🚗 Android Auto (Beta)
- Anrufe von HA-Phone erscheinen im Auto wie normale Anrufe: klingeln, annehmen, auflegen, halten und stummschalten über das Auto-Display und die Lenkradtasten, Ton über die Auto-Lautsprecher.
- Eigene Auto-Oberfläche mit **Favoriten, Verlauf, Kontakten (mit Status) und Haustür**. „Tür öffnen“ fragt im Auto zur Sicherheit noch einmal nach.
- Google lässt Telefonie-Apps in Android Auto derzeit nur als Beta zu. Für eine selbst installierte App in Android Auto die Entwickleroptionen öffnen (10× auf „Version“ tippen) und **„Unbekannte Quellen“** einschalten. Im Auto noch nicht getestet.

### 🌗 Erscheinungsbild
Dunkel (Standard), Hell oder wie das System, einstellbar im Reiter „Ich“. Die App ist für große Systemschrift ausgelegt (bis 200 %).

---

## Einrichtung in 3 Schritten

1. **HA-Phone installieren**: das Add-on [HA-Phone](https://github.com/iron-exx/HA-Phone) in Home Assistant.
2. **Nebenstellen anlegen**: im HA-Phone-Admin unter *Nebenstellen*, eine pro Handy. Bei der Türstation den Schalter **„Türstation“** einschalten und optional Tür-Öffnen-Webhook oder -Code, Klingelbild-Quelle und Home-Assistant-Tasten eintragen.
3. **Handy koppeln**: im Admin bei der Nebenstelle über **⋯ → „HA-Phone App QR“** den Code anzeigen und mit der App scannen. Alternativ den Kopplungs-Link auf dem Handy öffnen. Eine manuelle SIP-Eingabe ist nicht nötig, die Zugangsdaten überträgt die Anlage verschlüsselt. Ist auf der Home-Assistant-Box das Tailscale-Add-on installiert, richtet die Kopplung den Unterwegs-Zugang gleich mit ein.

Beim ersten Start fragt die App nach den Berechtigungen, die ein Telefon braucht:

| Berechtigung | Wofür |
|---|---|
| Mikrofon | Telefonieren |
| Benachrichtigungen & Vollbild-Anrufe | Klingeln auch bei gesperrtem Handy |
| Akku-Optimierung ausnehmen | Damit Android die App nicht schlafen legt und Anrufe auch nach Tagen ankommen |
| VPN (nur mit Tailscale) | Unterwegs-Zugang zur Anlage |
| Kontakte (optional) | Namen aus dem Handy-Adressbuch anzeigen |

> **Tipp für Samsung, Xiaomi, Huawei und OnePlus:** Diese Hersteller beenden Hintergrund-Apps besonders aggressiv. Nimm HA-Phone zusätzlich in den Hersteller-Einstellungen aus („Nie in Standby versetzte Apps“ bzw. „Autostart“). Der Erreichbarkeits-Check führt dich hin.

---

## Sicherheit und Datenschutz

- Die App spricht **nur mit deiner eigenen HA-Phone-Anlage**, kein Cloud-Dienst dazwischen. Unterwegs läuft die Verbindung durch dein eigenes Tailscale-Netz.
- SIP läuft verschlüsselt über **TLS**, die App-Schnittstelle über **HTTPS mit Zertifikat-Pinning**: Die App vertraut nur dem Zertifikat, das sie beim Koppeln per QR-Code bekommen hat.
- Jede Kopplung erhält ein eigenes Geräte-Token, und die Anlage speichert davon nur den Hash.
- Webhook-Adressen, Kamera-Quellen und Home-Assistant-Dienste bleiben auf der Anlage. Die App bekommt nur Beschriftungen und löst Aktionen über die Anlage aus.

---

## Für Entwickler

- Oberfläche: **Flutter** (`app-flutter/`). Anruf-Kern nativ: **PJSIP/PJSUA2 2.17** mit Android Telecom, Vordergrund-Dienst und MediaCodec H.264, dazu eingebettetes **Tailscale** (libtailscale).
- Der Klingelbildschirm ist nativ (Jetpack Compose), damit er auch beim Kaltstart und über der Sperre sofort da ist.
- Design-System „Nachtwache“: [`docs/design/nachtwache.md`](docs/design/nachtwache.md), Entwürfe unter `docs/design/mockups/`.
- Tests: `flutter test` (Dart) und `./gradlew :app:testDebugUnitTest` (Kotlin) in `app-flutter/`.

## Lizenz

Copyright (C) 2026 Sandro Ahrens. All Rights Reserved.

This repository is source-available for viewing only. No license to use, copy, modify, or distribute this software — commercially or otherwise — is granted. See the LICENSE file for details.
