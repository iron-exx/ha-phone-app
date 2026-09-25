# Handy-Test (echtes Android-Handy)

Ziel: prüfen, was der Emulator nicht kann, also Mobilfunk, echter Ton, lange Sperre.

## Vorbereitung

1. APK aufs Handy: `\\192.168.101.113\projects\ha-phone-app\app-flutter\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk` (per USB kopieren oder als Download). Beim Öffnen „Unbekannte Apps installieren“ für den Dateimanager oder Browser erlauben.
2. Eine vorhandene Debug-Version vorher deinstallieren (andere Signatur).
3. In HA-Phone unter Provisioning eine **eigene Nebenstelle** fürs Handy wählen (nicht 18, die hat der Emulator), QR-Code anzeigen.
4. App öffnen, QR scannen. Alle Nachfragen erlauben: Kamera, Mikrofon, Benachrichtigungen, **VPN-Verbindung**, Akku-Optimierung ausnehmen.
5. Im Bildschirm „Erreichbarkeit“ müssen alle Punkte grün sein, auch „Unterwegs erreichbar“.

## Tests

| # | So geht's | Erwartet | Bei Fehler schicken |
|---|---|---|---|
| a | Im WLAN von Nebenstelle 11 (Fanvil) das Handy anrufen | Klingelt, Ton in beide Richtungen | Uhrzeit, Screenshot |
| b | **WLAN aus**, nur Mobilfunk. 30 s warten, dann von 11 anrufen | Klingelt, Ton in beide Richtungen | Uhrzeit, Screenshot Erreichbarkeit |
| c | Weiter im Mobilfunk: an der Türstation klingeln | Klingelbildschirm mit Livebild vor dem Abheben, Ton nach dem Annehmen | Uhrzeit, Screenshot |
| d | Klingelbildschirm: Schieberegler „Zum Öffnen“ | Tür öffnet | Uhrzeit |
| e | Handy 30 min gesperrt liegen lassen (Mobilfunk), dann klingeln | Klingelt innerhalb weniger Sekunden | Uhrzeit, wie lange es gedauert hat |
| f | WLAN wieder an, während ein Gespräch läuft | Gespräch reißt nicht ab (Tunnel bleibt) | Uhrzeit |
| g | Aus der App eine externe Nummer anrufen | Verbindung, Ton ok | Uhrzeit |

Uhrzeiten reichen mir, die Protokolle von Anlage und Tailscale suche ich dann selbst raus.
