# Lizenzlage der HA-Phone App (Stand 2026-09-25)

Keine Rechtsberatung. Das hier ist eine technische Bestandsaufnahme als Grundlage für die Entscheidung.

## Was in der App steckt

| Bestandteil | Lizenz | Was sie verlangt |
|---|---|---|
| **PJSIP / pjproject 2.17** (SIP, Audio, Video) | **GPL-2.0-or-later** *oder* kommerzielle Lizenz von Teluu | Wer die App weitergibt, muss den **vollständigen Quelltext der ganzen App** unter der GPL mitliefern bzw. anbieten |
| libsrtp (in PJSIP) | BSD-3-Clause | Lizenztext nennen |
| OpenSSL 3 | Apache-2.0 | Lizenztext nennen |
| Opus | BSD-3-Clause | Lizenztext nennen |
| Tailscale, libtailscale, wireguard-go, Go | BSD-3-Clause / MIT | Lizenztext nennen |
| Flutter und Dart-Pakete | BSD / MIT / Apache | Lizenztext nennen (macht Flutter automatisch) |

Seit App 1.6.1 stehen alle Lizenztexte auf der Lizenzseite der App (Ich → Lizenzen). Damit sind die Nennungspflichten der BSD-, MIT- und Apache-Teile erfüllt.

## Der Konflikt

Die App selbst steht unter „All Rights Reserved“ (`LICENSE`), linkt aber PJSIP (GPL). Das ist erlaubt, **solange die App niemandem außerhalb weitergegeben wird**. Die GPL greift erst bei der Weitergabe.

Sobald die APK an andere HA-Phone-Betreiber geht (Play Store, Download, auch kostenlos), braucht es einen dieser Wege:

1. **App unter die GPL stellen** (GPL-2.0-or-later oder GPL-3.0) und den Quelltext veröffentlichen.
   - Einfach und kostenlos. Play Store und F-Droid sind möglich.
   - Andere dürfen die App forken und weitergeben, allerdings nur unter der GPL.
   - **App Store (iOS):** Apples Nutzungsbedingungen gelten als unvereinbar mit der GPL (bekannter Fall VLC 2011). Für iOS wäre dann Weg 2 nötig, oder man verzichtet auf iOS.
2. **Kommerzielle PJSIP-Lizenz bei Teluu kaufen** (https://www.pjsip.org/licensing.htm, Preis auf Anfrage).
   - Die App bleibt geschlossen. iOS ist unproblematisch.
3. **PJSIP ersetzen** durch einen SIP-Kern unter freizügiger Lizenz.
   - Aufwendig: SIP, TLS, Video-Early-Media und zwei Leitungen müssten neu gebaut werden.
   - Linphone ist ebenfalls GPL bzw. kommerziell, also keine Lösung.

## Empfehlung

- **Solange die App nur im eigenen Haushalt läuft:** nichts tun, es besteht kein Handlungsbedarf.
- **Vor der ersten Weitergabe entscheiden.** Mein Vorschlag:
  - Android-only mit offenem Quelltext → Weg 1 (GPL).
  - iOS oder eine geschlossene App → bei Teluu ein Angebot einholen (Weg 2).
- Die Anlage (HA-Phone-Add-on) ist anders gelagert. Ihr Python-Backend spricht mit Asterisk nur über AMI und Konfigurationsdateien und linkt weder Asterisk noch PJSIP. Das Image liefert aber Asterisk (GPL-2.0) mit. Dafür muss der Quelltext von Asterisk erreichbar sein. Das ist erfüllt, weil das `Dockerfile` Asterisk aus den öffentlichen Upstream-Quellen baut. Gut wäre noch ein Hinweis darauf in der README des Add-ons.
