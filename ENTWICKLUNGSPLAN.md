# Entwicklungsplan: plattformübergreifende Softphone-App für iOS und Android

## 1. Projektziel

Entwicklung einer eigenen Softphone-App für iOS und Android, die zuverlässig für eingehende Anrufe geweckt wird und sich besonders einfach per QR-Code einrichten lässt.

Die App soll folgende Kernprobleme klassischer Softphones lösen:

- zuverlässiges Klingeln bei geschlossener App
- zuverlässiges Klingeln bei gesperrtem Smartphone
- geringe Akku-Belastung
- Einrichtung ohne manuelle Eingabe von SIP-Zugangsdaten
- vollständige Integration in die System-Telefonoberfläche
- Unterstützung von Audio- und Videoanrufen
- Livebild einer Türstation bereits vor dem Annehmen
- sichere zentrale Verwaltung über die eigene PBX
- einfache Aktualisierung oder Sperrung eingerichteter Geräte

## 2. Grundprinzip

Die App hält im Hintergrund keine dauerhafte SIP-Verbindung aufrecht.

Stattdessen arbeitet sie nach folgendem Prinzip:

1. Die App wird einmal per QR-Code eingerichtet.
2. Sie registriert ihr Smartphone und ihren Push-Token bei der PBX.
3. Die PBX kennt die Zuordnung zwischen Nebenstelle und Smartphone.
4. Bei einem eingehenden Anruf sendet die PBX einen VoIP-Push an das Smartphone.
5. Das Betriebssystem weckt die App.
6. Die App zeigt sofort den System-Anrufbildschirm an.
7. Erst danach stellt die App die SIP-Verbindung zur PBX her.
8. Beim Annehmen wird der Audio- oder Videoanruf aufgebaut.
9. Nach dem Gespräch wird die SIP-Registrierung wieder beendet oder in einen energiesparenden Zustand versetzt.

Dadurch hängt die Erreichbarkeit nicht davon ab, ob iOS oder Android eine dauerhaft laufende SIP-Verbindung beendet.

## 3. Zielplattformen

### iOS

Für eingehende Anrufe werden verwendet:

- Apple PushKit für VoIP-Push-Benachrichtigungen
- Apple CallKit für den nativen Anrufbildschirm
- APNs als Push-Infrastruktur
- AVAudioSession für Mikrofon und Audioausgabe
- native Kamera- und Video-APIs
- Keychain zur sicheren Speicherung lokaler Zugangsdaten

Bei iOS muss nach einem VoIP-Push umgehend ein eingehender Anruf an CallKit gemeldet werden. Erfolgt dies nicht zuverlässig, kann iOS die App beenden und spätere VoIP-Pushs nicht mehr zustellen.

### Android

Für eingehende Anrufe werden verwendet:

- Firebase Cloud Messaging mit hoher Priorität
- Android Telecom Framework
- ConnectionService beziehungsweise die aktuellen Telecom-APIs
- CallStyle-Benachrichtigungen
- Full-Screen-Intent für eingehende Anrufe auf dem Sperrbildschirm
- Android Keystore zur sicheren Speicherung lokaler Zugangsdaten

High-Priority-FCM-Nachrichten sind für zeitkritische, sichtbare Ereignisse wie eingehende Anrufe vorgesehen. Sie müssen tatsächlich zu einer sichtbaren Benachrichtigung führen, da Google andernfalls die Priorität später reduzieren kann.

Ab Android 12 sollte die App CallStyle-Benachrichtigungen verwenden. Für Anrufe bei gesperrtem Gerät ist eine korrekt konfigurierte Full-Screen-Benachrichtigung erforderlich.

## 4. Technische Gesamtarchitektur

```text
Telefonanbieter / SIP-Trunk / Türstation
                  │
                  ▼
                PBX
                  │
        ┌─────────┴─────────┐
        │                   │
        ▼                   ▼
 SIP- und Medienserver   Push-Gateway
        │                   │
        │          ┌────────┴────────┐
        │          ▼                 ▼
        │      Apple APNs        Google FCM
        │          │                 │
        └──────────┴────────┬────────┘
                            ▼
                     Softphone-App
```

Die Lösung besteht aus vier Hauptkomponenten:

### PBX

Die PBX übernimmt:

- SIP-Konten und Nebenstellen
- Rufverteilung
- Rufgruppen
- Trunk-Anbindung
- Anrufstatus
- Video- und Audiosteuerung
- QR-Provisionierung
- Verwaltung der Mobilgeräte
- Auslösen von Push-Benachrichtigungen

### Push-Gateway

Das Push-Gateway kann Bestandteil der PBX sein oder als separater Dienst laufen.

Aufgaben:

- Speicherung der APNs- und FCM-Geräte-Tokens
- Zuordnung von Nebenstelle und Mobilgerät
- Versand eingehender Anrufsignale
- Ende- und Abbruchmeldungen
- Aktualisierung abgelaufener Geräte-Tokens
- Protokollierung der Zustellung
- Schutz vor Wiederholungsangriffen
- Unterstützung mehrerer Smartphones pro Nebenstelle

### SIP- und Medienkomponente

Empfohlene Grundlage:

- PJSIP beziehungsweise PJSUA2
- SIP über TLS
- RTP oder vorzugsweise SRTP
- ICE
- STUN
- TURN
- Audio-Codecs Opus, G.722 und G.711
- Video-Codecs H.264 und optional VP8
- DTMF per RFC 2833 beziehungsweise RFC 4733

PJSIP ist eine freie, plattformübergreifende SIP- und Medienbibliothek mit Unterstützung für SIP, SDP, RTP, STUN, TURN und ICE. Die PJSIP-Dokumentation beschreibt außerdem ausdrücklich die Einbindung von PushKit und CallKit für iOS-Softphones.

### Verwaltungsoberfläche

Im PBX-Dashboard wird je Nebenstelle angezeigt:

- eingerichtete Smartphones
- Plattform und App-Version
- letzter Kontakt
- Push-Status
- letzte erfolgreiche Registrierung
- Berechtigungsstatus
- Gerätename
- Gerätebesitzer
- QR-Code neu erstellen
- Gerät sperren
- Gerät löschen
- Zugangsdaten erneuern
- Testanruf auslösen
- Test-Push senden

## 5. QR-Code-Provisionierung

Die App soll niemals verlangen, dass Benutzer SIP-Server, Port, Benutzername und Passwort manuell eingeben.

### Ablauf

1. Ein Administrator öffnet die gewünschte Nebenstelle.
2. Er wählt „Mobilgerät hinzufügen".
3. Die PBX erstellt einen zeitlich begrenzten Provisionierungs-Token.
4. Das Dashboard zeigt einen QR-Code an.
5. Der Benutzer öffnet die App und wählt „QR-Code scannen".
6. Die App liest nur eine Provisionierungs-URL mit Einmal-Token.
7. Die App verbindet sich verschlüsselt mit der PBX.
8. Die PBX liefert die freigegebene Konfiguration.
9. Das Smartphone erzeugt eine eigene Geräteidentität.
10. Die App übermittelt ihren APNs- oder FCM-Token.
11. Die PBX aktiviert das Gerät.
12. Der Einmal-Token wird sofort ungültig.

### Empfohlener QR-Inhalt

```text
https://pbx.example.de/app/setup?t=EINMAL_TOKEN
```

Der QR-Code sollte nicht direkt das SIP-Passwort enthalten.

### Übertragene Konfiguration

- PBX-Adresse
- SIP-Domain
- Nebenstellen-ID
- gerätespezifisches SIP-Kennwort oder Zertifikat
- Transportart
- Push-Registrierungsadresse
- STUN- und TURN-Konfiguration
- erlaubte Codecs
- Anzeigename
- interne Rufnummer
- Türöffnerfunktionen
- Videoeinstellungen
- Firmenlogo und Farbschema
- Ablaufdatum und Konfigurationsversion

### Sicherheitsvorgaben

- Einmal-Token
- kurze Gültigkeit, beispielsweise fünf Minuten
- nur einmal verwendbar
- Bindung an eine Nebenstelle
- optional zusätzliche Bestätigung im PBX-Dashboard
- vollständige TLS-Verschlüsselung
- keine Passwörter in Protokolldateien
- gerätespezifische Zugangsdaten
- Sperrmöglichkeit für einzelne Geräte
- automatische Erneuerung der Zugangsdaten
- Schutz gegen Screenshots beziehungsweise erneute Nutzung alter QR-Codes

## 6. Ablauf eines eingehenden Anrufs

### Normaler Audioanruf

1. Ein Anruf erreicht die PBX.
2. Die PBX erstellt eine eindeutige Call-ID.
3. Die PBX hält den Anruf serverseitig.
4. Das Push-Gateway sendet einen VoIP-Push.
5. iOS oder Android weckt die App.
6. Die App zeigt den nativen Anrufbildschirm.
7. Die App baut im Hintergrund eine sichere Verbindung zur PBX auf.
8. Der Benutzer nimmt den Anruf an.
9. Die App bestätigt die Annahme.
10. PBX und App handeln SIP und Medien aus.
11. Der Audiokanal wird aktiviert.
12. Beim Auflegen werden SIP-Sitzung und Systemanruf gemeinsam beendet.

### Mehrere Mobilgeräte

Sind mehrere Geräte derselben Nebenstelle zugeordnet:

- alle Geräte klingeln
- das zuerst annehmende Gerät erhält den Anruf
- alle anderen Geräte bekommen sofort einen Abbruch-Push
- deren Anrufoberfläche wird geschlossen
- Doppelannahmen werden serverseitig verhindert

### App ist vollständig beendet

Auch wenn der Benutzer die App nicht geöffnet hat, soll der Push das Betriebssystem veranlassen, den eingehenden Systemanruf anzuzeigen.

Eine Einschränkung muss klar dokumentiert werden: Hat der Benutzer die App unter iOS ausdrücklich aus dem App-Umschalter beendet oder Push-Berechtigungen deaktiviert, kann die Zustellung je nach Betriebssystemzustand eingeschränkt sein. Eine hundertprozentige Zustellgarantie kann keine Drittanbieter-App geben.

## 7. Videoanrufe und Türstationen

Die App soll zwei Videomodi unterstützen.

### Modus A: SIP-Video

- Video wird über den SIP-Anruf ausgehandelt.
- H.264 wird bevorzugt.
- Das Bild erscheint spätestens nach der Rufannahme.
- Geeignet für normale Videotelefonie.

### Modus B: Türstations-Vorschau

Für Akuvox, 2N, DoorBird, Fanvil oder andere Türstationen wird das Vorschaubild vom eigentlichen SIP-Anruf getrennt.

Beim Klingeln kann die App anzeigen:

- aktuelles Snapshot-Bild
- kurzlebigen HTTPS-Videostream
- WebRTC-Stream
- gegebenenfalls RTSP über ein serverseitiges Gateway

Empfohlener Ablauf:

1. Die Akuvox R20 ruft die PBX an.
2. Die PBX erkennt anhand der Rufnummer, dass es sich um eine Türstation handelt.
3. Die PBX erstellt einen geschützten, kurzlebigen Videolink.
4. Der Push enthält eine Call-ID und die Information „Türanruf mit Vorschau".
5. Die App zeigt sofort das Kamerabild.
6. Der Benutzer kann annehmen, ablehnen oder die Tür öffnen.
7. Nach Ende des Anrufs verliert der Videolink automatisch seine Gültigkeit.

Der Push selbst sollte keine dauerhaft gültige Kamera-URL und keine RTSP-Zugangsdaten enthalten.

### Türöffner

Mögliche Verfahren:

- SIP-DTMF
- SIP-INFO
- HTTP-Aufruf über die PBX
- herstellerspezifische API
- Relaissteuerung durch die PBX
- Home-Assistant-Webhook

Die App zeigt einen Türöffner nur an, wenn die angerufene Gegenstelle entsprechend konfiguriert ist.

Vor dem Öffnen sollte optional verlangt werden:

- Face ID
- Touch ID
- Geräte-PIN
- zusätzliche Bestätigung

## 8. Funktionsumfang der ersten Version

### Telefonie

- eingehende und ausgehende Anrufe
- Audioanrufe
- Videoanrufe
- Annehmen und Ablehnen
- Auflegen
- Stummschalten
- Lautsprecher
- Bluetooth
- Wähltastatur
- DTMF
- Halten
- Makeln
- Weiterverbinden
- Anrufliste
- Favoriten
- Kontaktintegration
- Anzeige der Absendernummer
- Anzeige des Namens aus dem PBX-Telefonbuch

### Erreichbarkeit

- VoIP-Push unter iOS
- High-Priority-FCM unter Android
- nativer Sperrbildschirm
- System-Anrufoberfläche
- Wiederaufbau der Verbindung nach Netzwerkwechsel
- Wechsel zwischen WLAN und Mobilfunk
- Push-Test im Einstellungsmenü
- Warnung bei deaktivierten Berechtigungen

### Provisionierung

- QR-Code-Scanner
- automatische Einrichtung
- erneute Provisionierung
- Gerätewechsel
- Abmelden
- Fernsperrung
- automatisches Aktualisieren der Konfiguration

### Türkommunikation

- Video-Vorschau vor Annahme
- Tür öffnen
- Kamera auf Vollbild
- Gegensprechen
- Mikrofon stummschalten
- Snapshot speichern, sofern administrativ erlaubt
- optionale Home-Assistant-Aktion

## 9. Technologieentscheidung

### Empfohlene App-Struktur

Für eine zuverlässige Telefon-App sollte nicht alles ausschließlich in Flutter oder React Native umgesetzt werden.

Empfehlung:

- gemeinsame Geschäftslogik mit Kotlin Multiplatform oder einer klar getrennten Core-Bibliothek
- native iOS-Oberfläche mit Swift und SwiftUI
- native Android-Oberfläche mit Kotlin und Jetpack Compose
- gemeinsamer SIP-Core auf Basis von PJSIP/PJSUA2
- native CallKit-Integration auf iOS
- native Telecom-Integration auf Android
- gemeinsames API-Modell und gemeinsame Verschlüsselungslogik

Alternativ kann Flutter für normale Oberflächen verwendet werden. Push-Wakeup, CallKit, Android Telecom, Audio-Routing und SIP-Lebenszyklus müssen dennoch über native Module umgesetzt werden.

### Warum keine reine Web-App?

Eine Progressive Web App kann:

- nicht zuverlässig VoIP-Anrufe im Hintergrund empfangen
- nicht vollständig in CallKit integriert werden
- keine gleichwertige Audioverwaltung bieten
- keine verlässliche Telefonfunktion bei gesperrtem Gerät gewährleisten

## 10. Backend-Schnittstellen

Die PBX benötigt mindestens folgende API-Bereiche:

```text
POST /api/mobile/provision/start
POST /api/mobile/provision/complete
POST /api/mobile/device/register
POST /api/mobile/device/refresh-token
POST /api/mobile/device/revoke

POST /api/calls/{callId}/accept
POST /api/calls/{callId}/reject
POST /api/calls/{callId}/hangup
POST /api/calls/{callId}/door-open

GET  /api/calls/{callId}
GET  /api/calls/{callId}/preview
GET  /api/mobile/config
```

### Push-Nachricht für iOS

Die Nachricht enthält nur die notwendigsten Informationen:

- Call-ID
- Anzeigename
- Rufnummer
- Audio oder Video
- Türanruf ja oder nein
- Ablaufzeitpunkt
- kryptografische Signatur

Nach Empfang ruft die App aktuelle Details von der PBX ab.

### Push-Nachricht für Android

Auch unter Android wird ein minimales Datenpaket verwendet:

- Eventtyp
- Call-ID
- Anrufer
- Ablaufzeit
- Signatur
- Hinweis auf Türstationsvorschau

Der FCM-Push muss als hohe Priorität versendet werden und unmittelbar eine sichtbare Anrufbenachrichtigung erzeugen.

## 11. Sicherheit

### Transport

- HTTPS mit TLS 1.2 oder neuer
- SIP über TLS
- SRTP für Medien
- DTLS-SRTP bei WebRTC
- TURN über TLS als Option
- Zertifikatsprüfung ohne unsichere Ausnahmen

### Zugangsdaten

- jedes Smartphone erhält eigene Zugangsdaten
- keine gemeinsame Nebenstellenkennung für alle Geräte
- Speicherung in Apple Keychain oder Android Keystore
- Widerruf einzelner Geräte möglich
- automatische Rotation
- keine vollständigen Zugangsdaten im QR-Code
- keine Klartextpasswörter in Backups

### Push-Sicherheit

Ein Push darf allein keinen Anruf übernehmen oder eine Tür öffnen können.

Jeder Push benötigt:

- eindeutige Event-ID
- Call-ID
- kurze Gültigkeit
- serverseitige Zustandsprüfung
- Signatur
- Schutz gegen Wiederholung
- Gerätebindung

### Datenschutz

- keine Audioaufzeichnung ohne ausdrückliche Funktion
- keine Videoaufzeichnung standardmäßig
- keine Kontaktdaten an externe Analysedienste senden
- Telemetrie abschaltbar
- Protokolle ohne SIP-Passwörter
- definierbare Löschfristen
- möglichst eigene Push-Metadaten ohne sensible Gesprächsinhalte

APNs und FCM bleiben technisch für das Aufwecken erforderlich. Die eigentlichen SIP-, Audio- und Videodaten laufen jedoch direkt über die eigene Infrastruktur.

## 12. Entwicklungsphasen

### Phase 1: Technischer Prototyp

Ziel: Nachweis, dass eingehende Anrufe zuverlässig funktionieren.

Umfang:

- einfache PBX-Nebenstelle
- PJSIP-Integration
- Audioanruf
- APNs-VoIP-Push
- FCM-High-Priority-Push
- CallKit
- Android-Anrufbenachrichtigung
- Annehmen und Auflegen
- Test bei geschlossener App
- Test bei gesperrtem Gerät
- Test nach längerem Standby

Abnahmekriterium:

Ein eingehender Anruf wird auf beiden Plattformen zuverlässig über die native Telefonoberfläche signalisiert, ohne dass die App dauerhaft geöffnet bleiben muss.

### Phase 2: QR-Provisionierung

Umfang:

- PBX-Dialog „Mobilgerät hinzufügen"
- einmaliger Provisionierungs-Token
- QR-Code
- Scanner in der App
- automatische Einrichtung
- Geräteübersicht
- Gerät sperren und löschen
- Push-Test
- Konfigurationsaktualisierung

Abnahmekriterium:

Ein neuer Benutzer kann die App ohne Kenntnis der SIP-Daten innerhalb weniger Schritte einrichten.

### Phase 3: Produktionsfähige Audiotelefonie

Umfang:

- Opus, G.722 und G.711
- Mikrofon, Lautsprecher und Bluetooth
- DTMF
- Halten
- Weiterverbinden
- Anrufliste
- Telefonbuch
- WLAN-/Mobilfunkwechsel
- NAT-, STUN- und TURN-Tests
- mehrere Endgeräte pro Nebenstelle
- Fehlerdiagnose

### Phase 4: Videotelefonie

Umfang:

- H.264
- Front- und Rückkamera
- Kamera deaktivieren
- Wechsel zwischen Audio und Video
- Anzeigeformat und Drehung
- Bandbreitenanpassung
- Tests über Mobilfunk
- SIP-Video mit unterschiedlichen Gegenstellen

### Phase 5: Türstationsmodus

Umfang:

- Akuvox-R20-Profil
- Erkennung von Türanrufen
- Snapshot oder Live-Vorschau
- Bild vor Annahme
- Türöffner
- Face-ID- beziehungsweise Biometrie-Bestätigung
- Home-Assistant-Anbindung
- zeitlich begrenzte Stream-Tokens

### Phase 6: Stabilisierung und Veröffentlichung

Umfang:

- Langzeittests
- Akkuverbrauch
- Push-Zuverlässigkeit
- App-Abstürze
- Netzwechsel
- schlechter Mobilfunkempfang
- mehrere gleichzeitige Anrufe
- App-Store- und Play-Store-Vorgaben
- Datenschutzerklärung
- Berechtigungserklärungen
- TestFlight
- geschlossener Play-Store-Test
- automatisierte Builds
- signierte Releases

## 13. Testmatrix

Die App muss mindestens in folgenden Zuständen getestet werden:

- App geöffnet
- App im Hintergrund
- Smartphone gesperrt
- App mehrere Stunden nicht verwendet
- App nach Neustart des Smartphones
- WLAN aktiv
- Mobilfunk aktiv
- Wechsel von WLAN zu Mobilfunk
- schlechter Empfang
- Energiesparmodus
- „Nicht stören"
- Bluetooth-Headset verbunden
- anderes Telefongespräch aktiv
- mehrere Smartphones klingeln gleichzeitig
- PBX kurzzeitig nicht erreichbar
- Push trifft verspätet ein
- Anrufer hat bereits aufgelegt
- Push-Token wurde erneuert
- SIP-Kennwort wurde geändert
- Türstationskamera nicht erreichbar

## 14. Diagnosefunktionen

Die App benötigt eine verständliche Statusseite:

```text
PBX-Verbindung: erreichbar
Push-Dienst: aktiv
VoIP-Push: registriert
SIP-Konto: bereit
Mikrofon: erlaubt
Kamera: erlaubt
Benachrichtigungen: erlaubt
Systemanrufe: aktiviert
Letzter Test-Push: erfolgreich
Letzter eingehender Anruf: 14:32 Uhr
```

Zusätzlich:

- Diagnosebericht erzeugen
- sensible Daten automatisch entfernen
- Verbindungsqualität anzeigen
- SIP-Fehler verständlich übersetzen
- Push-Test starten
- Testanruf starten
- Mikrofon und Lautsprecher testen
- Kamera-Vorschau testen

## 15. Mindestanforderungen an die PBX

Ohne Anpassung der PBX lässt sich die gewünschte Zuverlässigkeit nicht erreichen.

Die PBX muss:

- Mobilgeräte und Push-Tokens verwalten
- bei eingehenden Anrufen Pushs auslösen
- Anrufe bis zur Reaktion der App halten
- verspätete Pushs erkennen
- andere Geräte nach Annahme stoppen
- Call-IDs zentral verwalten
- Geräte einzeln sperren können
- QR-Provisionierung bereitstellen
- APNs und FCM ansprechen können
- TURN-Konfiguration bereitstellen
- Türstationen als eigenen Gerätetyp unterstützen

Ein gewöhnliches SIP-Konto allein genügt nicht. Die Push-Steuerung muss Bestandteil der Gesamtlösung sein.

## 16. Empfohlene Reihenfolge

Die Entwicklung sollte nicht mit Design, Telefonbuch oder Videovorschau beginnen.

Priorität:

1. Push-Wakeup unter iOS
2. Push-Wakeup unter Android
3. native Anrufoberfläche
4. stabiler Audioanruf
5. QR-Provisionierung
6. sichere Geräteverwaltung
7. Netzwerkwechsel und NAT
8. Videotelefonie
9. Akuvox-Vorschau
10. Türöffner und Home Assistant

## 17. Definition der ersten marktfähigen Version

Die erste veröffentlichbare Version gilt als fertig, wenn:

- sie unter iOS und Android verfügbar ist
- sie per QR-Code eingerichtet werden kann
- sie bei geschlossener App klingelt
- sie bei gesperrtem Gerät klingelt
- Audioanrufe stabil funktionieren
- ausgehende Anrufe möglich sind
- mehrere Geräte pro Nebenstelle unterstützt werden
- Geräte zentral widerrufen werden können
- SIP über TLS und Medien über SRTP möglich sind
- Push- und Berechtigungsprobleme diagnostiziert werden
- die Akuvox-Türstation ein Vorschaubild vor Annahme anzeigen kann
- die Tür sicher aus der App geöffnet werden kann

## 18. Wichtigste Architekturentscheidung

Die App wird nicht als eigenständiges Universal-SIP-Softphone entwickelt, in das beliebige SIP-Zugangsdaten eingetragen werden.

Sie wird als Bestandteil der eigenen PBX-Plattform entwickelt:

```text
Eigene PBX (HA-Phone) + eigenes Push-Gateway + eigene App
```

Nur dadurch können QR-Provisionierung, zuverlässiges Aufwecken, Gerätesperrung, Türstationsvorschau und die zentrale Anrufsteuerung sauber miteinander verbunden werden.

Die eigentliche Besonderheit des Produkts wäre damit:

> Eine einfach einzurichtende, cloudunabhängige Telefon-App für die eigene PBX, die auf iOS und Android zuverlässig klingelt und bei Türanrufen das Kamerabild bereits vor dem Annehmen anzeigt.

## 19. Bezug zum bestehenden PBX-Projekt (HA-Phone)

Diese App wird parallel zum bestehenden PBX-Projekt **HA-Phone** entwickelt
(https://github.com/iron-exx/HA-Phone.git, lokal unter `~/projects/Ha-Phone`).

HA-Phone ist bereits eine funktionierende Asterisk-22-PBX (FastAPI-Backend, React-Frontend,
Home-Assistant-Add-on) mit Nebenstellen, Trunks, Routing, Rufgruppen, IVR, Voicemail und
Auto-Provisioning. Aktuell wird für mobile Endgeräte Linphone über Tailscale-VPN empfohlen
(siehe README, Abschnitt "Remote access").

Laut HA-Phone-Roadmap (Stand Juli 2026) sind WebRTC und Videotelefonie explizit als
"nicht in die nächste Phase ziehen" zurückgestellt (Abschnitt 10), da Phase A/B (Stabilität,
Betriebsreife) Vorrang haben. Das heißt für dieses Projekt:

- Die Push-Gateway- und QR-Provisionierungs-Backend-Teile (Kapitel 10, 15 dieses Plans)
  müssen als **neue Erweiterung von HA-Phone** entstehen, nicht als separate PBX.
- Video/Türstations-Funktionen (Phase 4/5 dieses Plans) laufen der aktuellen HA-Phone-Roadmap
  zeitlich voraus — das muss mit dem HA-Phone-Projekt synchronisiert bzw. dort vorgezogen werden.
- Phase 1-3 dieses Plans (Push-Wakeup, native Call-UI, stabile Audiotelefonie, QR-Provisionierung)
  passen gut zu HA-Phones aktuellem Stand und sind eine sinnvolle nächste Ausbaustufe.
