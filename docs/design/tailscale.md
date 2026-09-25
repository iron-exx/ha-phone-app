# Eingebettetes Tailscale: Machbarkeit und Plan

Stand: 2026-09-25 · Status: Entwurf (Schritt 1 aus HANDOFF 5a8) · App 1.0.1, Anlage 0.7.119

**Festgelegt vom Nutzer:** nur die Vollversion. Der Admin hinterlegt in HA-Phone einen Tailscale-Zugang. Bei der QR-Kopplung erzeugt die Anlage pro Gerät einen Auth-Key und liefert ihn in der Antwort von `POST /api/mobile/provision/complete` aus (nie im QR-Bild). Die App tritt dem Tailnet automatisch bei und erreicht die Anlage unterwegs über deren Tailnet-Adresse.

**Kurzfazit:** Das ist machbar. Empfohlen wird: `libtailscale` aus tailscale-android als gomobile-AAR, ein eigener `VpnService` nur für `100.64.0.0/10` und `fd7a:115c:a1e0::/48`, ein **OAuth-Client** (Trust Credential) in HA-Phone mit den Scopes `auth_keys` und `devices:core` und dem Tag `tag:haphone-phone`, und Keys mit den Einstellungen einmalig, vorab genehmigt und **nicht ephemeral**. Die App nutzt die Tailnet-Adresse der Anlage **immer, sobald der Tunnel steht**. Nur wenn der Tunnel nicht steht und das Handy im Heim-WLAN ist, fällt sie auf die LAN-Adresse zurück. Asterisk ist dafür schon vorbereitet (`local_net = 100.64.0.0/10` steht in `pjsip_local.conf.j2`).

---

## 1. Einbettung in die Android-App

### 1a. libtailscale + VpnService (EMPFOHLEN)

- tailscale-android baut sein Go-Backend `libtailscale/` mit `gomobile bind -target android -androidapi 26` als AAR (`libgojni.so` + Java-Bindings). Die ldflags enthalten schon `-Wl,-z,max-page-size=16384` für 16-KB-Seiten. Quelle: [Makefile](https://raw.githubusercontent.com/tailscale/tailscale-android/main/Makefile).
- Die Schnittstelle nach Kotlin steht in [libtailscale/interfaces.go](https://raw.githubusercontent.com/tailscale/tailscale-android/main/libtailscale/interfaces.go):
  - Einstieg: `Start(dataDir, directFileRoot, hwAttestationPref, appCtx) Application`
  - Die App implementiert `AppContext`: `Log`, `EncryptToPref`/`DecryptFromPref`, `GetDeviceName`, `GetSDKInt`, Hardware-Attestation (die dürfen wir leer lassen bzw. mit `false` beantworten).
  - Die App implementiert `IPNService`: `Protect(fd)`, `NewBuilder()`, `Close`, `DisconnectVPN`, `UpdateVpnStatus`.
  - Die App implementiert `VPNServiceBuilder`: `SetMTU`, `AddDNSServer`, `AddRoute`, `ExcludeRoute`, `Establish() → ParcelFileDescriptor`.
  - Gesteuert wird über die LocalAPI (`localapi.go`), genau wie die offizielle App. Anmelden per Auth-Key heißt: Prefs setzen, dann `start` mit `AuthKey`.
- **Split-Tunnel:** In unserem `VPNServiceBuilder.AddRoute` lassen wir nur `100.64.0.0/10` und `fd7a:115c:a1e0::/48` durch. Die Default-Route und Exit-Node-Routen verwerfen wir, ebenso Subnet-Routen (`accept_routes` bleibt aus). DNS: den MagicDNS-Resolver `100.100.100.100` **nicht** als System-DNS setzen. Die App spricht die Anlage per IP an (siehe 3). Normaler Internetverkehr geht dadurch nie durch den Tunnel.
- `Protect(fd)` auf die eigenen Underlay-Sockets (UDP 41641, DERP über TCP 443) ruft libtailscale selbst auf. Wir leiten das nur an `VpnService.protect()` weiter.
- **PJSIP braucht keine Änderung am Socket-Code.** Die Sockets sind an `0.0.0.0` gebunden, und der Kernel routet Pakete an 100.x ins TUN-Gerät. Größter Vorteil: Die eigene Tailnet-IP bleibt bei einem Wechsel zwischen WLAN und LTE gleich. Die TLS-Verbindung und die RTP-Adressen überleben den Wechsel, weil WireGuard/magicsock nur das Underlay wechselt. Heute baut `NetworkChangeHandler` bei jedem Netzwechsel neu auf.
- Lizenz: tailscale-android und tailscale/tailscale stehen unter **BSD-3-Clause**, wireguard-go unter MIT, gVisor unter Apache-2.0. Das ist kein Copyleft. Pflicht ist nur ein Lizenzhinweis in der App (Bildschirm "Open-Source-Lizenzen" plus NOTICE). Der Name "Tailscale" darf nicht als eigener Produktname erscheinen. Formulierungen wie "verbindet über Tailscale" sind in Ordnung. Das Thema PJSIP-GPL ist davon unabhängig und bleibt offen (Audit).

### 1b. tsnet im Userspace ohne VpnService (Plan B, nicht empfohlen)

[tsnet](https://pkg.go.dev/tailscale.com/tsnet) betreibt einen vollständigen Knoten im Prozess mit gVisor-Netstack. Es gibt kein TUN-Gerät und keinen Zustimmungsdialog. Den Netzverkehr gibt es nur über `Dial`/`Listen`/`ListenPacket`. PJSIP benutzt aber OS-Sockets. Damit das funktioniert, wären lokale Weiterleitungen nötig:

- SIP-TLS ist noch einfach: `127.0.0.1:5061` wird nach `tsnet.Dial("tcp", "<pbx-100.x>:5061")` weitergereicht.
- RTP ist schwierig. PJSIP müsste auf `127.0.0.1` in einem festen Portbereich binden, zum Beispiel 4000–4099. Für **jeden** Port bräuchte es ein `tsnet.ListenPacket(":<gleicher Port>")` mit einem 1:1-Relay in beide Richtungen. Zusätzlich müsste `publicAddress` in PJSIP auf die eigene 100.x-Adresse gesetzt werden, damit SDP und Contact eine erreichbare Adresse tragen. Pro Videogespräch sind das 4 Ports (RTP und RTCP für Audio und Video). STUN, ICE und das neue Keep-Alive-RTP (`PJMEDIA_STREAM_KA_EMPTY_RTP`) müssen zum Relay passen.
- Kosten: Jedes Paket wird zusätzlich kopiert, gVisor verbraucht CPU, und der Portbereich ist fest. Das ist fehleranfällig, und bei Video merkt man die Latenz. Die Tailnet-IP bleibt zwar ebenfalls stabil, aber der Aufwand ist etwa doppelt so hoch wie bei 1a.
- Sinnvoll ist das **nur** als Notlösung, wenn der Nutzer schon ein anderes VPN aktiv hat (siehe 1d). Zunächst nicht bauen.

### 1c. Andere Wege (verworfen)

- **Offizielle Tailscale-App + Intents/MDM:** Einen Auth-Key kann man nur per MDM/Managed Config übergeben. Es gäbe kein automatisches Koppeln und keine Kontrolle über den Status. Verworfen. Ist die offizielle App aber schon installiert und im selben Tailnet, sollten wir sie tolerieren (siehe 1d).
- **Reines WireGuard (wireguard-android) ohne Tailscale:** Dann gäbe es keine NAT-Traversal-Relays (DERP) und keine Schlüsselverwaltung. Verworfen, weil es der Nutzer-Entscheidung widerspricht.

### 1d. Betriebsfragen

| Thema | Bewertung / Maßnahme |
|---|---|
| **Zustimmungsdialog** | Einmalig beim ersten Aufbau erscheint `VpnService.prepare()` → Systemdialog "HA-Phone möchte eine VPN-Verbindung einrichten". Direkt nach der Kopplung zeigen, mit einer Erklärung davor: "Damit du unterwegs erreichbar bist …". Vor jedem Start `prepare()` erneut aufrufen, denn eine andere App kann das VPN übernommen haben ([Android VPN](https://developer.android.com/develop/connectivity/vpn)). |
| **Anderes VPN** | Android erlaubt **nur ein aktives VPN** pro Profil. Startet unseres, stoppt das fremde, und umgekehrt ([Quelle](https://developer.android.com/develop/connectivity/vpn)). Maßnahmen: `onRevoke()` abfangen, im Erreichbarkeits-Screen melden ("Anderes VPN aktiv – unterwegs nicht erreichbar") und auf LAN zurückfallen. Ist ein fremdes VPN aktiv (`NetworkCapabilities.TRANSPORT_VPN`) und die 100.x-Adresse der Anlage trotzdem erreichbar (etwa über die offizielle Tailscale-App im selben Tailnet), nutzen wir diesen Weg ohne eigenen Tunnel ("Fremd-VPN-Modus"). |
| **Always-on VPN** | Kann der Nutzer in den System-Einstellungen für HA-Phone einschalten. Unterstützen wir, weil der Dienst beim Booten ohnehin startet. "Verbindungen ohne VPN blockieren" **nicht** empfehlen, sonst bricht wegen des Split-Tunnels sonstiges Internet ab. Hinweis im UI. |
| **Vordergrunddienst / Doze** | Der Tunnel läuft **im selben Prozess** wie `SipService`. Der `VpnService` ist ein eigener Dienst mit `BIND_VPN_SERVICE`, gestartet aus `SipService`. Die bestehende Akku-Ausnahme (ReachPolicy) und der exakte Wecker (480 s) wecken auch den Tunnel. Nach dem Aufwachen ruft Asterisk `qualify` (OPTIONS) durch den Tunnel auf, und libtailscale hält die DERP-TCP-Verbindung mit eigenen Keepalives. Das muss mit dem vorhandenen 20-min-Deep-Doze-Test geprüft werden. |
| **Akku** | Erwartung: DERP-Keepalive plus die schon vorhandene SIP-TLS-Registrierung. Mehrverbrauch klein bis mittel, genaue Zahlen gibt es nicht. Messen mit `dumpsys batterystats` über 8 h im Vergleich (mit und ohne Tunnel). |
| **MagicDNS** | Nicht nötig und nicht als System-DNS setzen. Die Anlage liefert ihre Tailnet-IP (und zur Anzeige den MagicDNS-Namen). Der Registrar ist `sip:100.x.y.z:5061;transport=tls`. |
| **ABIs / Größe** | `-target android/arm64,android/amd64` für arm64-v8a und x86_64 (Emulator). Die Größe von `libgojni.so` ist geschätzt und nicht gemessen: etwa 25–35 MB je ABI unkomprimiert, im Release-APK pro ABI (Splits/AAB) etwa +10–15 MB. Beim ersten Build messen. |
| **Toolchain auf CCsrv** | **Go ist nicht installiert.** tailscale-android verlangt laut [go.mod](https://raw.githubusercontent.com/tailscale/tailscale-android/main/go.mod) `go 1.27.1`, und das Makefile setzt `GOTOOLCHAIN=local`. Nötig sind Go 1.27.x nach `~/go-sdk` (ohne root), `go install golang.org/x/mobile/cmd/gomobile@latest` und `gobind`, dann `gomobile init`. NDK 27.0.12077973 ist vorhanden. tailscale-android selbst nennt NDK 23.1. Mit 27 sollte es gehen (16-KB-Flag vorhanden), das muss aber im ersten Build geprüft werden. Einen Commit von tailscale-android fest pinnen und `libtailscale/` als Modul im Repo `app-flutter/android/tailscale-core/` einbinden, mit Skript `scripts/build_libtailscale.sh`, genauso wie beim PJSIP-Build. |

## 2. Anlage (HA-Phone)

### 2a. Tailscale-API

- Token: `POST https://api.tailscale.com/api/v2/oauth/token` im Client-Credentials-Verfahren. Das Access-Token gilt **1 Stunde** und lässt sich nicht verlängern. Mit `auth_keys` **muss** der Client Tags haben, und alle damit erzeugten Keys müssen Tags tragen ([OAuth-Clients](https://tailscale.com/kb/1215/oauth-clients)). OAuth-Clients heißen inzwischen "Trust Credentials". Scopes: `auth_keys`, `devices:core`, `devices:core:read` … Für `devices:core` gilt: Keys müssen genau diese Tags haben oder Tags, die diesen gehören ([Trust Credentials](https://tailscale.com/kb/1623/trust-credentials)).
- Key erzeugen: `POST /api/v2/tailnet/-/keys` (`-` steht für das Tailnet des Clients)
  ```json
  {"capabilities":{"devices":{"create":{
      "reusable":false,"ephemeral":false,"preauthorized":true,
      "tags":["tag:haphone-phone"]}}},
   "expirySeconds":3600,
   "description":"HA-Phone Ext 13 Pixel 6"}
  ```
  Feldnamen laut [tailscale-client-go](https://pkg.go.dev/github.com/tailscale/tailscale-client-go/tailscale) und [Issue #11914](https://github.com/tailscale/tailscale/issues/11914). Die Laufzeit darf laut [Auth-Keys](https://tailscale.com/kb/1085/auth-keys) 1–90 Tage betragen. Die API erlaubt Sekunden, wir setzen 1 h, denn der Key wird sofort eingelöst. Läuft der Key ab, bleibt das Gerät angemeldet.
- **Empfehlung für Handys:** einmalig (`reusable:false`), `preauthorized:true` (falls Device-Approval an ist), Tag `tag:haphone-phone`, **nicht ephemeral**. Ephemeral-Knoten werden 30–60 min nach der letzten Aktivität gelöscht ([Ephemeral](https://tailscale.com/kb/1111/ephemeral-nodes)). Ein Handy im Doze, ohne Netz oder im Flugmodus würde dann aus dem Tailnet fliegen und müsste neu gekoppelt werden. Getaggte Knoten haben standardmäßig **keinen Node-Key-Ablauf**. Das ist gewollt, weil sonst nach 180 Tagen alles still ausfällt. Aufgeräumt wird per API beim Entkoppeln.
- Gerät finden und löschen: Die App meldet nach dem Beitritt ihre Tailscale-Node-ID (`StableID`) und ihre 100.x-Adresse an `POST /api/mobile/device/tailscale` (mit Device-Token). Beim Entkoppeln oder Widerrufen folgt `DELETE /api/v2/device/{nodeId}` (Scope `devices:core`). Fallback: `GET /api/v2/tailnet/-/devices` und nach Hostname/Tag suchen.

### 2b. Eigene Tailnet-Adresse der Anlage

Unser Container hat weder `tailscale status` noch den LocalAPI-Socket des Tailscale-Add-ons.

1. **Schnittstelle lesen (Hauptweg):** Das Add-on läuft mit `host_network: true`. Das offizielle Add-on legt ohne `userspace_networking` (Standard: aus) ein Interface `tailscale0` auf dem Host an ([Add-on-Doku](https://github.com/hassio-addons/addon-tailscale/blob/main/tailscale/DOCS.md)). HA-Phone sieht es also direkt: Adressen aus `100.64.0.0/10` bzw. `fd7a:115c:a1e0::/48` per `socket`/`/proc/net` oder `ip -j addr` ermitteln.
2. **Name und Bestätigung per API:** Mit `devices:core:read` in `GET /tailnet/-/devices` das Gerät mit genau dieser Adresse suchen. Das liefert den MagicDNS-Namen (`homeassistant.tailXXXX.ts.net`) und den Tailnet-Namen.
3. Supervisor-API (`/addons/<slug>/info`) liefert keine Tailnet-IP und bräuchte `hassio_role: manager`. Nicht nötig.
4. Ist `userspace_networking` aktiv, gibt es kein `tailscale0`, und die Anlage ist aus dem Tailnet nicht per SIP/RTP erreichbar. Die UI zeigt dann den Fehler "Im Tailscale-Add-on 'Userspace networking' ausschalten".

### 2c. Headscale

Headscale hat **nicht** die Tailscale-API v2. Es benutzt eine eigene REST-API `/api/v1` mit einem API-Key als Bearer ([Headscale-API](https://headscale.net/stable/ref/api/), Details unter `/swagger`). Pre-Auth-Key per `POST /api/v1/preauthkey` (user, reusable, ephemeral, expiration, aclTags), Knoten löschen per `DELETE /api/v1/node/{id}`. Diese beiden Pfade vor der Umsetzung in der Swagger-Doku prüfen. Für die App kommt nur die `ControlURL` dazu. Umsetzung: Adapterklasse `TailnetProvider` mit `TailscaleProvider` und `HeadscaleProvider`. Headscale als Etappe 6 (optional), aber gut als lokales Test-Tailnet (siehe 5).

## 3. Asterisk / SIP

- **`local_net`**: `100.64.0.0/10` und `fd7a:115c:a1e0::/48` stehen schon für alle Transporte in `backend/conf_templates/pjsip_local.conf.j2`. Kommt ein Handy über 100.x, schreibt Asterisk weder Contact noch SDP auf `external_*_address` um. Es gibt keine Änderung.
- **Media-Adressen**: SDP der App = eigene 100.x-Adresse (Ziel des Tunnels), SDP von Asterisk = Adresse der Box auf dem Weg zum Handy (bei `bind 0.0.0.0` die `tailscale0`-IP). Weiter `rtp_symmetric`/`force_rport` an den Endpunkten lassen.
- **STUN**: Im Tunnel gibt es kein NAT. Der STUN-Server der Anlage würde über 100.x die 100.x-Adresse zurückgeben, also harmlos. Trotzdem: Ist das Ziel eine Tailnet-Adresse, gilt `stun_servers` = `[]` bzw. `mediaStunUse` = aus. Das spart Rundläufe und vermeidet Fehlauflösung. Das Keep-Alive-RTP (`PJMEDIA_STREAM_KA_EMPTY_RTP`) bleibt, es schadet nicht.
- **TLS-Zertifikat**: Heute gilt `verifyServer=false` (Audit-Punkt). Für das Tailnet ändert sich daran nichts, denn WireGuard verschlüsselt und authentifiziert die Gegenstelle ohnehin. Später: Zertifikat-Pinning per Fingerprint in der Provisioning-Antwort, unabhängig von IP/SAN. Das ist robuster als SANs für 100.x und MagicDNS. Optional kann das SAN im selbstsignierten Zertifikat die Tailnet-IP und den MagicDNS-Namen bekommen, wenn die Anlage sie kennt (2b).
- **Endpunktwahl in der App** (empfohlen):
  1. Tunnel aktiv und Anlage per 100.x erreichbar → **immer Tailnet**, auch zu Hause. Tailscale verbindet im selben LAN direkt Peer-to-Peer, der Overhead ist klein. Vorteil: keine Umschaltung, kein Neuregistrieren bei WLAN↔LTE, Gespräche überleben den Wechsel.
  2. Tunnel nicht aktiv (fremdes VPN, Zustimmung verweigert, Tailscale-Control nicht erreichbar) → LAN-Adresse (`sip_domain` heute), wie bisher.
  - Umschalten nur, wenn sich der Tunnelstatus ändert, nicht bei jedem Netzwechsel. `PjsuaEndpointHolder` hält zwei Registrar-URIs. Beim Wechsel: `Account.modify()` mit der neuen `registrarUri` plus `natUpdateStunServers`.
  - Einschränkung: Hängt das Handy im LAN und der Tunnel nur per DERP-Relay, läuft Video über das Relay. Für Audio ist das in Ordnung, für H.264-Türvideo testen.
- **Provisioning-Antwort** (neu, abwärtskompatibel, alte Felder bleiben):
  ```json
  "tailscale": {
    "auth_key": "tskey-auth-…",           // einmalig, 1 h gültig
    "control_url": null,                   // Headscale: URL
    "hostname": "haphone-13-pixel6",
    "pbx_tailnet_ip": "100.101.102.103",
    "pbx_tailnet_ipv6": "fd7a:115c:a1e0::1234",
    "pbx_magicdns": "homeassistant.tail1234.ts.net",
    "sip_domain_tailnet": "100.101.102.103:5061",
    "api_base_tailnet": "http://100.101.102.103"
  }
  ```
  Fehlt `tailscale` (Admin hat es nicht eingerichtet), verhält sich die App wie heute.

## 4. Sicherheit

- **Auth-Key**: Er wird erst bei `provision/complete` erzeugt, also nach der Einlösung des einmaligen JWT. Er steht nie im QR-Bild und nie in Logs. Er ist einmalig und 1 h gültig. Wird ein JWT erneut benutzt (Replay, heute re-keyt `complete` das Gerät), gibt es einen neuen Key, und der alte Knoten wird gelöscht.
- **OAuth-Secret in der Anlage**: in der DB als `EncryptedString` (vorhandenes `backend/crypto.py`), nie an das Frontend zurückgeben (nur "hinterlegt ✓"). Access-Token nur im RAM cachen (55 min).
- **App**: Den Auth-Key sofort nach dem Beitritt verwerfen. Die Tailscale-Zustandsdaten (Maschinen- und Node-Key) liegen über `AppContext.EncryptToPref` in der vorhandenen `SecurePrefs` (Android Keystore, AES-GCM). `allowBackup=false` ist schon gesetzt. Beim Entkoppeln (`resetForPairing`) LocalAPI `logout` aufrufen und die Zustandsdaten löschen.
- **Widerruf**: Admin-UI "Gerät entfernen" → `DELETE /api/v2/device/{id}` und `MobileDevice.status=revoked`. Das Handy ist dann sofort nicht mehr im Tailnet, auch wenn es das SIP-Passwort noch kennt.
- **ACL** (Policy-Datei; der Nutzer fügt sie ein, HA-Phone zeigt den Schnipsel zum Kopieren). Die HA-Box bekommt im Tailscale-Add-on `advertise_tags: tag:haphone-pbx` (oder als Host-Alias):
  ```jsonc
  "tagOwners": {
    "tag:haphone-phone": ["autogroup:admin"],
    "tag:haphone-pbx":   ["autogroup:admin"]
  },
  "grants": [
    { "src": ["tag:haphone-phone"], "dst": ["tag:haphone-pbx"],
      "ip": ["tcp:5061", "tcp:80", "udp:3478", "udp:10000-10200"] }
  ]
  ```
  Die Anlage braucht **keinen** Rückweg-Eintrag, denn Antworten auf bestehende Verbindungen erlaubt Tailscale automatisch (stateful). Achtung: Klingelt ein eingehender Anruf, schickt Asterisk ein INVITE über die bestehende TLS-Verbindung. Das ist eine Antwortrichtung und funktioniert. RTP geht von Asterisk an den App-Port: Da die App zuerst sendet (Keep-Alive-RTP), ist auch das stateful erlaubt. Zur Sicherheit optional `tag:haphone-pbx → tag:haphone-phone udp:4000-65535` in der Policy. Handys untereinander sind nicht erlaubt. Der OAuth-Client darf nur `tag:haphone-phone` vergeben, also keine Admin-Rechte im Tailnet.
- Den Portbereich 10000–10200 mit `rtp.conf` der Anlage abgleichen, bevor der Schnipsel festgeschrieben wird.

## 5. Admin-UI "Tailscale" in HA-Phone (so einfach wie möglich)

### 5a. Optionen im Vergleich

| Option | Einfachheit | Dauerbetrieb | Keys für Handys | Urteil |
|---|---|---|---|---|
| **(1) OAuth-Client (Trust Credential) ID + Secret einfügen** | 1× in der Tailscale-Konsole anlegen (Scopes anhaken, Tag wählen), 2 Felder einfügen | **läuft nicht ab** (bis zum Widerruf) | ja, beliebig viele, getaggt ([OAuth](https://tailscale.com/kb/1215/oauth-clients)) | **Empfohlen** |
| (2) API-Access-Token | 1 Feld einfügen, am einfachsten | läuft nach **1–90 Tagen** ab. Danach scheitert jede neue Kopplung still, Widerruf geht nicht mehr | ja, aber Token hat volle Rechte des Nutzers | Nein |
| (3) "Mit Tailscale anmelden" (Login-URL wie `tailscale up`, HA-Phone als eigener Knoten per tsnet) | Klick, einloggen, fertig | Knoten-Login ist **kein API-Zugang**: ein Knoten kann keine Auth-Keys für andere Geräte erzeugen | **nein**: jedes Handy bräuchte eine eigene interaktive Anmeldung (Browser, Tailscale-Konto auf dem Handy) | Widerspricht "automatisch per QR", nein. Außerdem ist die HA-Box über das Add-on schon Knoten |
| (4) Headscale: URL + API-Key | 2 Felder | API-Key-Laufzeit frei wählbar (Standard 90 Tage, per CLI länger) | ja (`/api/v1/preauthkey`) | Als zweite Karteikarte "Eigener Server (Headscale)", Etappe 6 |

Einen echten OAuth-"Mit Tailscale anmelden"-Knopf für Drittanbieter-Apps (Authorization-Code-Flow) bietet Tailscale nicht an. Es gibt nur Client-Credentials. Option (1) lässt sich aber auf **einen Deep-Link und zwei Einfügefelder** reduzieren.

### 5b. Ablauf (neuer Menüpunkt "Tailscale")

Backend: `backend/routers/tailscale.py` (`GET/PUT/DELETE /api/tailscale/config`, `POST /api/tailscale/test`, `GET /api/tailscale/devices`, `DELETE /api/tailscale/devices/{id}`) und `backend/tailnet/` (Provider, Token-Cache, Schnittstellenerkennung). Frontend: `frontend/src/pages/Tailscale.tsx`, Menüeintrag unter "Provisioning".

**Seite ohne Einrichtung – Assistent in 3 Schritten**

> **Unterwegs erreichbar mit Tailscale**
> Deine HA-Phone-Apps verbinden sich unterwegs automatisch über dein Tailscale-Netz mit der Anlage. Kein Portfreigeben, kein Router-Umbau.
>
> **Schritt 1 – Tailscale auf Home Assistant** ✓/✗ *(automatisch geprüft: `tailscale0` mit 100.x gefunden)*
> ✗-Text: "Installiere das Add-on 'Tailscale' in Home Assistant und melde es an. 'Userspace networking' muss aus sein." [Zum Add-on-Store]
> ✓-Text: "Gefunden: 100.101.102.103"
>
> **Schritt 2 – Zugang für HA-Phone anlegen**
> 1. "Öffne die Tailscale-Konsole → **Trust credentials** → **OAuth-Client erstellen**" [Tailscale-Konsole öffnen ↗] (`https://login.tailscale.com/admin/settings/trust-credentials`; die ältere Adresse `/admin/settings/oauth` leitet weiter, vor Umsetzung prüfen)
> 2. "Häkchen bei **Auth Keys – Schreiben** und **Devices Core – Schreiben**, als Tag **tag:haphone-phone** wählen."
> 3. "Gibt es den Tag noch nicht? Füge diesen Abschnitt in **Access controls** ein:" [ACL-Schnipsel kopieren] (Block aus Kapitel 4)
>
> **Schritt 3 – Einfügen**
> Felder: "Client-ID", "Client-Secret" (Passwortfeld, Einfügen-Knopf) → [**Verbindung testen und speichern**]

**"Verbindung testen"** macht live und nacheinander folgende Prüfungen:
1. Token holen → "Zugang gültig ✓" / "Client-ID oder Secret falsch"
2. Probe-Key mit `tag:haphone-phone` erzeugen und sofort wieder löschen (`DELETE /tailnet/-/keys/{id}`) → "Darf Geräte-Schlüssel erstellen ✓" / "Scope 'Auth Keys' fehlt" / "Tag tag:haphone-phone fehlt oder gehört nicht zum Client"
3. `GET /tailnet/-/devices` → HA-Box mit der 100.x aus Schritt 1 finden → "Anlage im Tailnet: homeassistant.tail1234.ts.net ✓" / "Scope 'Devices Core' fehlt"
4. Optional: HA-Box getaggt `tag:haphone-pbx`? Sonst Warnung "ACL-Regel greift nur, wenn die Box den Tag hat" mit Hinweis auf `advertise_tags` im Add-on.
Erst wenn alles grün ist, wird gespeichert (Secret verschlüsselt).

**Seite nach der Einrichtung – Status**

> **Tailscale: verbunden** · Tailnet `tail1234.ts.net` · Anlage `homeassistant.tail1234.ts.net` (100.101.102.103)
> Schalter: "Neue App-Kopplungen mit Tailscale" (Standard an)
>
> **Handys im Tailnet**
> | Gerät | Nebenstelle | Tailnet-IP | Zuletzt online | |
> | Pixel 6 (Sandro) | 13 | 100.80.1.2 | vor 2 min | [Entfernen] |
>
> [Verbindung erneut testen] · [Zugang ändern] · [Tailscale trennen] (Rückfrage: "Alle Handys verlieren den Unterwegs-Zugang. Handys aus dem Tailnet entfernen?" [Ja, entfernen] [Nur Zugang löschen])

**Einbindung in die QR-Kopplung:** Der QR-Dialog im Provisioning zeigt "Mit Unterwegs-Zugang (Tailscale)" als Häkchen, sobald die Einrichtung aktiv ist. In `complete_provisioning` wird dann `TailnetProvider.create_device_key(ext, device_name)` aufgerufen. Scheitert die API, wird die Kopplung **trotzdem** abgeschlossen (nur LAN) und es gibt eine Warnung in der Geräteliste: "Tailscale-Schlüssel konnte nicht erstellt werden, in der App 'Unterwegs-Zugang erneut anfordern'". Dafür gibt es einen neuen Endpunkt `POST /api/mobile/device/tailscale-key` (mit Device-Token, 1/min begrenzt), der auch für eine spätere Nachrüstung ohne neuen QR dient.

## 6. Etappenplan

| # | Etappe | Inhalt | Aufwand |
|---|---|---|---|
| 0 | Spike Toolchain | Go 1.27 + gomobile auf CCsrv. `libtailscale` für arm64 + x86_64 mit NDK 27 bauen, Größe messen. Minimale Kotlin-Test-App: VpnService mit Route 100.64/10, Beitritt per Auth-Key, `ping` auf die HA-Box aus dem Emulator | 1–2 Tage |
| 1 | Anlage: Provider + UI | `backend/tailnet/` (OAuth-Token-Cache, Keys, Geräte, `tailscale0`-Erkennung), Router, `Tailscale.tsx` mit Assistent, Test und Status, DB-Felder (`TailnetConfig`, `MobileDevice.tailscale_node_id/ip`), Tests mit gemockter API. Version plus CHANGELOG | 2–3 Tage |
| 2 | Provisioning-Payload | `tailscale`-Block in `complete`, `device/tailscale` (Node-ID melden), `device/tailscale-key` (Nachrüsten), Widerruf beim Entkoppeln, Replay → alten Knoten löschen | 1 Tag |
| 3 | App: nativer Tailscale-Kern | Modul `tailscale-core` (AAR plus Build-Skript), `TsVpnService` (Split-Routen, Protect, `onRevoke`), `AppContext` auf SecurePrefs, LocalAPI-Wrapper (Login per Key, Status, Logout), Start und Stopp gekoppelt an `SipService`, Manifest (`BIND_VPN_SERVICE`, FGS-Typ `systemExempted` bzw. über `SipService`), Lizenzhinweise | 4–6 Tage |
| 4 | App: UX + Endpunktwahl | Zustimmungs-Erklärung nach der Kopplung, Systemdialog, Erreichbarkeit-Screen: neuer Prüfpunkt "Unterwegs-Zugang" (verbunden direkt/über Relay, Tailnet-IP, anderes VPN aktiv). Registrar-Umschaltung Tailnet/LAN nach Kapitel 3, STUN aus im Tailnet, API-Basis-URL ebenso umschalten, Flutter-Kanal `tailscaleStatus` | 3–4 Tage |
| 5 | Tests / E2E | Unit: Provider (gemockte API), Endpunktwahl, Routenfilter (Kotlin). E2E im Emulator (kann dem Tailnet beitreten, VpnService läuft im AVD): (a) Kopplung → Gerät im Tailnet mit Tag, (b) Registrierung über 100.x, (c) Emulator-WLAN abschalten bzw. `svc wifi disable` + Mobilfunk → Registrierung bleibt, (d) Türsimulator `door_sim.py` → Klingeln + Video über Tunnel, (e) Deep-Doze 20 min + Türanruf, (f) Entfernen im Admin → Tunnel weg, Fallback LAN, (g) zweites VPN (z. B. WireGuard-App) → Fallback + Hinweis. Echter Unterwegs-Test auf einem Handy im Mobilfunk | 3–4 Tage |
| 6 | optional | Headscale-Provider, tsnet-Plan-B bei Fremd-VPN, Zertifikat-Pinning | je 2–3 Tage |

**Summe Etappen 0–5: etwa 14–20 Arbeitstage.**

**Test-Tailnet:** Am besten ein **eigenes Test-Tailnet** des Nutzers (kostenloser Personal-Tarif reicht), damit Test-Tags und ACLs das echte Netz nicht stören. CCsrv muss nicht beitreten, die Pakete fließen Emulator → Tailnet → HA-Box. Zusätzlich für automatische Tests ohne Nutzerkonto: **Headscale lokal auf CCsrv** (Docker), dann läuft E2E auch ohne echtes Konto (braucht den Headscale-Provider aus Etappe 6 bzw. eine minimale Variante).

## 7. Risiken

| Risiko | Wirkung | Gegenmaßnahme |
|---|---|---|
| libtailscale ist keine stabile Bibliothek (interne API von tailscale-android, ändert sich) | Updates sind Handarbeit | Commit pinnen, dünne Kotlin-Fassade, Update bewusst alle 1–3 Monate (Sicherheitsfixes) |
| Go 1.27 / NDK 27 / gomobile-Kombination baut nicht | Etappe 0 blockiert | Spike zuerst. Fallback: NDK 23.1 zusätzlich installieren wie bei tailscale-android |
| Doze trennt DERP, eingehende Anrufe gehen verloren | Kernfunktion | Vorhandener Wecker plus Akku-Ausnahme, Test (e), bei Bedarf OPTIONS-qualify der Anlage auf 60 s |
| Nutzer hat bereits ein VPN (Firma, offizielles Tailscale) | kein Unterwegs-Zugang | Erkennen, klar anzeigen, Fremd-VPN-Modus, Plan B tsnet |
| Relay (DERP) bei symmetrischem NAT (Mobilfunk-CGNAT) | Latenz, Video ruckelt | Audio ist unkritisch. Video-Bitrate der Tür begrenzen, messen |
| APK-Größe | +10–15 MB pro ABI | ABI-Splits / AAB |
| Nutzer vergisst den Tag in der ACL bzw. den Tag für die HA-Box | Key-Erzeugung scheitert / Zugriff blockiert | Live-Test mit genauer Fehlermeldung, ACL-Schnipsel zum Kopieren |

## 8. Was der Nutzer bereitstellen muss

1. **Tailscale-Konto** (für Tests am besten ein eigenes Test-Tailnet, Personal-Tarif).
2. **Tailscale-Add-on in Home Assistant** installiert und angemeldet, `userspace_networking: false` (Standard), besser mit `advertise_tags: ["tag:haphone-pbx"]`.
3. **ACL-Ergänzung** in der Policy-Datei: `tagOwners` für `tag:haphone-phone` und `tag:haphone-pbx` plus Grant (Kapitel 4).
4. **OAuth-Client (Trust Credential)** mit den Scopes **`auth_keys` (Schreiben)** und **`devices:core` (Schreiben)** (enthält Lesen) und dem Tag **`tag:haphone-phone`**. Client-ID und Secret gibt der Nutzer später selbst in der HA-Phone-UI ein, für die Entwicklung einmal in `no-git/` auf CCsrv.
5. Für den echten Unterwegs-Test: ein Android-Handy mit Mobilfunk (das OnePlus ist nicht mehr verfügbar).

## Quellen

- tailscale-android: https://github.com/tailscale/tailscale-android · Makefile: https://raw.githubusercontent.com/tailscale/tailscale-android/main/Makefile · go.mod: https://raw.githubusercontent.com/tailscale/tailscale-android/main/go.mod · interfaces.go: https://raw.githubusercontent.com/tailscale/tailscale-android/main/libtailscale/interfaces.go
- tsnet: https://pkg.go.dev/tailscale.com/tsnet
- OAuth-Clients: https://tailscale.com/kb/1215/oauth-clients · Trust Credentials / Scopes: https://tailscale.com/kb/1623/trust-credentials
- Auth-Keys: https://tailscale.com/kb/1085/auth-keys · Ephemeral-Knoten: https://tailscale.com/kb/1111/ephemeral-nodes
- Key-API-Felder: https://pkg.go.dev/github.com/tailscale/tailscale-client-go/tailscale · https://github.com/tailscale/tailscale/issues/11914 · Terraform `tailscale_tailnet_key`: https://registry.terraform.io/providers/tailscale/tailscale/latest/docs/resources/tailnet_key
- HA-Tailscale-Add-on: https://github.com/hassio-addons/addon-tailscale/blob/main/tailscale/DOCS.md
- Headscale-API: https://headscale.net/stable/ref/api/
- Android VpnService: https://developer.android.com/develop/connectivity/vpn
- Lokal: `Ha-Phone/ha-phone/backend/routers/mobile_provisioning.py` (`complete_provisioning`), `backend/conf_templates/pjsip_local.conf.j2` (local_net), `app-flutter/android/.../sip/PjsuaEndpointHolder.kt` (registrarUri, verifyServer, STUN), `sip/NetworkChangeHandler.kt`
