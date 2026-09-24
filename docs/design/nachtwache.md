# Design "Nachtwache" — Vorgabe für die Umsetzung

Ziel: sichtbar besser als Yeastar Linkus und die 3CX-App (Recherche: `docs/research/linkus-3cx-ui-research.md`).
Entwürfe: `docs/design/mockups/*.dc.html` (HTML, erzeugt von `gen.py`; Maße und Farben dort sind maßgeblich),
online: https://claude.ai/artifact/HqTj56a1kVtjLv8Civ45Ne

## Tokens (dunkel = Standard)

| Rolle | Dunkel | Hell (gleiche Rolle) |
|---|---|---|
| ground (Hintergrund) | #0B0F14 | #F4F6F9 |
| surface (Karten, Felder) | #131A22 | #FFFFFF |
| raised (Tasten, Chips) | #1B2430 | #EAEEF3 |
| high (Avatar-Grund) | #243040 | #DCE3EB |
| stroke (Linien) | #2A3544 | #D5DCE4 |
| text | #EAF0F6 | #0F172A |
| muted | #A3B0BF | #475569 |
| faint | #8593A3 | #5B6778 |
| blue (App-Akzent, HA-Blau) | #38BDF8 · Ink #04263A · Soft #0E3148 | #0369A1 · Ink #FFFFFF · Soft #E0F2FE |
| answer (nur Annehmen/Anrufen) | #2FBF71 · Ink #032313 | #177E45 · Ink #FFFFFF |
| end (nur Auflegen, verpasst, REC) | #E5484D · Ink #FFFFFF | #D92D32 · Ink #FFFFFF |
| endStrong (end-Fläche mit Text: „Löschen“, REC-Chip, Zähler) | #CC3338 | #D92D32 |
| door (nur Tür) | #F5A524 · Ink #2A1800 · Soft #3A2A0E | #A86500 · Ink #FFFFFF · Soft #FFF1D6 |
| ok-Fläche (grüne Hinweise) | #0F2A1C, Rand #1E4D33, Text #7EE2A8 | #E7F7EE, Rand #B7E4C9, Text #166534 |

Kontrast (WCAG AA, Text ≥ 4,5:1, geprüft in `app-flutter/test/contrast_test.dart`): text/muted/faint auf
ground, surface und raised; Ink auf blue, door, answer und endStrong – in beiden Themes. Weiß auf dem
dunklen end (#E5484D) hat nur 3,9:1: dort nur Symbole (Auflegen-Taste); Flächen mit Text nutzen endStrong.

Präsenz = Farbe **und** Form (farbenblind-sicher): Ring um den Avatar + Glyph unten rechts.
verfügbar grün ✓ · abwesend bernstein ☾ · nicht stören rot ⊖ · telefoniert rot (Hörer) · offline grau, kein Ring.

## Typografie

- Titel, große Namen, Zahlen/Nummern: **Bricolage Grotesque** (700/800), gebündelt als Asset (kein Laden zur Laufzeit).
- Oberfläche: **Manrope** (500–800), gebündelt.
- Zahlen immer `tabularFigures`. Seitentitel 32/800, Zeilentitel 15/700–800, Meta 12.5/600, Abschnitt 12/800 Versalien +8 % Laufweite.
- Muss bis 200 % Systemschrift ohne Überlauf funktionieren (Tastenfeld/Gesprächsraster umbrechen statt abschneiden).

## Formen

Karten Radius 22 (große 26), Tasten 16–22, Chips voll rund (Höhe 32), Anruf-Tasten rund 76 dp (Auflegen im Gespräch 80),
Steuertasten 72 dp hoch, Radius 22. Touch-Ziele ≥ 48 dp. Keine Schatten außer der Wählen-Taste (blauer Schein).

## Navigation

4 Reiter + erhöhte Mitte: **Start · Verlauf · (Wählen, blaue 68-dp-Taste) · Kontakte · Ich**. Kein Burger-Menü, keine Reiter während eines Gesprächs.
Verpasste + neue Voicemails als roter Zähler am Verlauf.

## Bildschirme (siehe Entwürfe)

1. **Start**: eigener Avatar mit Präsenz + Pille „Klingelt hier · verfügbar“ (öffnet Status-Blatt), Suche. Türkarte (letztes Bild/Platzhalter, „Tür öffnen“ bernstein, HA-Aktionen als Icon-Tasten), Banner „Gespräch am Tischtelefon → Hierher holen“ (wenn `presence.self.line == busy` und kein eigener Anruf), Favoriten als 2-spaltige Kacheln mit Live-Status, Karte „Neue Voicemail“.
2. **Verlauf**: eine Zeitleiste aus Anrufen, Voicemails, Aufnahmen; Filter-Chips Alle · Verpasst · Voicemail · Aufnahmen · Tür; ungelesen = farbiger Balken links + fett; Voicemail mit Inline-Player (Wellenform, 1×/1,5×/2×); Wischen rechts = zurückrufen, links = löschen.
3. **Wählen**: Leitungs-Chip + Bereit-Chip, große Nummer (Bricolage 40), Live-Treffer mit Präsenz unter der Nummer, Tasten 66 dp hoch in `surface`, grüne 76-dp-Anruftaste, Video links, Löschen rechts.
4. **Kontakte**: Suchfeld, Chips Alle · Nebenstellen · Handy · Telefonbuch · Favoriten, Abschnitte Türstationen (bernstein Tür-Symbol, Taste „Öffnen“) · Kolleg:innen · Handy · Telefonbuch; Anruftaste pro Zeile.
5. **Tür klingelt** (nativ, auch gesperrt): Live-Bild oben (bis 316 dp über Unterkante), „LIVE“-Chip rot, „Gesperrt“-Chip, Titel „Es klingelt an der Tür“ (bernstein, Versalien) + Name Bricolage 40; unteres Blatt: HA-Aktions-Chips, **Schieberegler „Zum Öffnen nach rechts schieben“** (bernstein, nie versehentlich), Ablehnen (rot, links) · Mit Video · Annehmen (grün, rechts), Positionen ändern sich nie.
6. **Türgespräch**: Video-Karte oben mit „Haustür“- und REC-Chip, Name + Zeit, 2×3-Raster (Stumm · Lautsprecher · **Tür öffnen** bernstein · Tastatur · erste HA-Aktion · Mehr), Auflegen 80 dp mittig.
7. **Normales Gespräch / zwei Leitungen**: gehaltene Leitung als kompakte Karte oben mit „Tauschen“, großer Avatar 112 dp, „Zusammenführen“-Chip nur bei 2 Leitungen, Raster Stumm · Lautsprecher · Halten · Tastatur · Weiterleiten · Mehr.
8. **Mehr** (Blatt): Konferenz · Rückfrage · Aufnehmen (rot) · Direkt weiterleiten · Audio-Ausgabe · Anruf-Info; darunter Audio-Ausgabe-Liste (Bluetooth-Geräte mit Namen, Hörer, Lautsprecher).
9. **Status & Klingeln** (Ich): Status für alle (4 große Zeilen mit Glyph), „Nur dieses Handy“: Schalter **Klingeln auf diesem Handy** + Stumm-Chips (1 Std · bis 17:00 · bis morgen), Weiterleitungs-Regelkarte.
10. **Erreichbarkeit**: Zusammenfassung (grüne Fläche), Prüfpunkte mit Status und „Beheben“: Benachrichtigungen, Vollbild-Anrufe (`canUseFullScreenIntent`), Akku-Optimierung, Verbindung zur Anlage (TLS · RTT), Türvideo durch NAT (STUN), Nicht stören; Taste „Test-Anruf an mich“.

## Verhalten, das zum Design gehört

- Haptik: leichter Tick beim Tippen im Tastenfeld, mittlerer beim Annehmen/Auflegen, doppelter Impuls bei „Tür geöffnet“.
- „Tür geöffnet ✓“-Zustand (grün, 2 s) nach dem Öffnen.
- Hell/Dunkel folgt dem System, Wechsel ohne Neustart.
