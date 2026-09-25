# Etappe 2: Klingel-Verlauf mit Foto + neue Start-Seite – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Jedes Klingeln an einer Türstation wird mit Zeit, Tür, „angenommen von“, „Tür geöffnet“ und einem Foto festgehalten. Die App zeigt das letzte Klingelbild auf der Start-Seite, einen Klingel-Verlauf und bei verpasstem Klingeln eine Benachrichtigung mit Bild.

**Architecture:** Die Anlage abonniert AMI-Ereignisse über eine eigene, dauerhafte Verbindung (`Newchannel` der Tür = Klingeln, `DialEnd` ANSWER = angenommen, `Hangup` = Ende). Eine reine Zustandsmaschine (`DoorbellTracker`) macht daraus Ereignisse. Beim Klingeln holt die Anlage ein Standbild aus der pro Tür konfigurierten Quelle (Home-Assistant-Kamera über die Supervisor-API oder Snapshot-URL der Türstation) und legt es unter `/data/doorbell/` ab. Die App liest Liste und Bilder über `/api/mobile/doorbell` mit Geräte-Token.

**Tech Stack:** FastAPI/SQLModel, panoramisk, httpx (Basic/Digest), React-Admin. Flutter (http), Kotlin (Benachrichtigung mit BigPictureStyle).

**Spec:** `docs/superpowers/plans/2026-09-25-ausbau-release-klingelverlauf.md`, Etappe 2.

## Global Constraints

- „Tür“ = Nebenstelle mit Türcode, Webhook, HA-Aktion **oder** gesetzter Klingelbild-Quelle (gleiche Definition wie in der App).
- Aufbewahrung: 30 Tage, höchstens 500 Ereignisse. Bilder werden beim Löschen des Ereignisses mit gelöscht.
- Bildgröße: höchstens 2 MB pro Bild (größere Antworten werden verworfen), nur `image/jpeg` oder `image/png`.
- Snapshot-Abruf: Zeitlimit 4 s. Er darf das Klingeln nie verzögern (läuft als eigener Task).
- Die App-Endpunkte authentifizieren wie die übrigen mit `X-Device-Id` + `X-Device-Token`.
- Anlage-Version + CHANGELOG pro Auslieferung, App-Version in pubspec + app_info.

## Review Focus

- **Tür klingelt parallel an mehreren Geräten (Klingelgruppe):** Genau ein Ereignis pro Klingeln, nicht eins pro Gerät. → Test im Tracker: ein Newchannel der Tür, mehrere DialEnd.
- **AMI-Verbindung bricht ab (Asterisk-Neustart):** Der Listener verbindet sich neu, ohne das Backend zu blockieren. → Reconnect-Schleife mit Backoff, Test mit einer Fake-Verbindung, die einmal abbricht.
- **Kamera nicht erreichbar oder falsche Zugangsdaten:** Das Ereignis wird trotzdem gespeichert (ohne Bild), mit einem Log-Eintrag. → Test mit einer MockTransport-Antwort 401/Timeout.
- **Ausgehender Anruf AN die Tür** (App ruft Tür an): Das ist kein Klingeln. Newchannel mit der Tür als Ziel darf kein Ereignis erzeugen. → Tracker prüft, dass der Kanal der Tür-Endpunkt selbst ist und der Anruf von ihm ausgeht (Newchannel `CallerIDNum` = Tür und `Exten` ≠ Tür).
- **Pfad-Traversal über die Bild-ID:** Bilder nur über die DB-ID ausliefern, nie über einen Dateinamen aus der Anfrage. → Test mit unbekannter ID → 404.

---

### Task B1: Datenmodell

**Files:** `backend/models.py`, `backend/database.py`, `backend/routers/extensions.py`, Tests `backend/tests/test_doorbell.py`

- [ ] `Extension.doorbell_camera: str = ""` (max 512), plus in `ExtensionCreate`/`ExtensionUpdate`/`ExtensionOut`. Validierung: leer, `camera.<slug>` (`^camera\.[a-z0-9_]+$`) oder `http(s)://…` ohne Leerzeichen/Zeilenumbruch. Die sqlmodel-`regex=` greift nicht (HANDOFF), also `field_validator` wie bei `door_open_code`.
- [ ] Neue Tabelle `DoorbellEvent`: `id`, `door_number:int`, `door_name:str`, `started_at:datetime`, `ended_at:Optional[datetime]`, `answered_by:str=""`, `door_opened:bool=False`, `image_file:str=""` (relativer Name unter `/data/doorbell`).
- [ ] Migration: `ALTER TABLE extension ADD COLUMN doorbell_camera TEXT NOT NULL DEFAULT ''`.
- [ ] Tests: PATCH mit gültigen und ungültigen Quellen (422 bei `camera.Foo Bar`, `ftp://`, Zeilenumbruch).

### Task B2: Tracker, Snapshot, Ablage (`backend/doorbell.py`)

- [ ] `class DoorbellTracker` (rein, ohne I/O): `__init__(is_door: Callable[[str], bool])`, `on_event(ev: dict) -> list[Action]`. Actions: `Ring(uniqueid, door)`, `Answered(uniqueid, by)`, `Ended(uniqueid)`. Regeln: `Newchannel` mit `Channel` = `PJSIP/<door>-…` und `CallerIDNum` = door und `Exten` ≠ door → Ring (einmal pro `Uniqueid`). `DialEnd` mit `DialStatus=ANSWER` und `Uniqueid` einer laufenden Klingel → Answered (erstes gewinnt, `DestCallerIDNum`). `Hangup` mit dieser Uniqueid → Ended und aus dem Speicher.
- [ ] `async def fetch_snapshot(source: str, *, transport=None) -> bytes | None`: `camera.*` → `GET http://supervisor/core/api/camera_proxy/<entity>` mit `SUPERVISOR_TOKEN`. URL → GET, bei 401 mit `WWW-Authenticate: Digest` erneut mit `httpx.DigestAuth` (Userinfo aus der URL). Prüft Content-Type und 2 MB.
- [ ] `class DoorbellStore`: `record_ring`, `mark_answered`, `mark_ended`, `mark_opened(door_number)` (jüngstes Ereignis der Tür, höchstens 5 min alt), `save_image`, `prune()` (30 Tage / 500).
- [ ] Tests: Klingelgruppe (1 Ring, 2 DialEnd → 1 Answered), ausgehend an die Tür → kein Ring, Snapshot 200/401-Digest/Timeout/zu groß, prune.

### Task B3: AMI-Listener im Lifespan

- [ ] `backend/doorbell_listener.py`: eigene panoramisk-Verbindung, `register_event("*")` gefiltert auf Newchannel/DialEnd/Hangup, Reconnect mit Backoff 2→60 s. `Ring` → Store + Snapshot-Task. Door-Set wird bei jedem Ereignis frisch aus der DB bestimmt (gecacht 30 s).
- [ ] In `main.lifespan` starten und stoppen. Tests setzen `BPX_DOORBELL_LISTENER=0`.

### Task B4: API

- [ ] `GET /api/mobile/doorbell?limit=30` (Geräte-Auth) → `[{id, door_number, door_name, started_at, ended_at, answered_by, door_opened, has_image}]`, neueste zuerst.
- [ ] `GET /api/mobile/doorbell/{id}/image` (Geräte-Auth) → Bild, 404 ohne Bild.
- [ ] Admin: `GET /api/doorbell`, `GET /api/doorbell/{id}/image`, `DELETE /api/doorbell/{id}`, `POST /api/doorbell/test-snapshot {source}` (holt ein Bild zum Prüfen der Quelle).
- [ ] `/api/mobile/door-open` markiert das jüngste Ereignis als geöffnet.
- [ ] Directory: `door.has_camera` pro Tür.

### Task B5: Admin-UI

- [ ] Nebenstellen-Editor: Feld „Klingelbild-Quelle“ (Hinweis: `camera.haustuer` oder Snapshot-URL, Knopf „Testbild holen“ mit Vorschau).
- [ ] Seite „Türklingel“: Liste mit Vorschaubild, angenommen von, geöffnet. Löschen.
- [ ] Version, CHANGELOG, Push, Deploy.

### Task A1: App-Daten

- [ ] `lib/models/doorbell_event.dart` (fromJson), `lib/services/doorbell_repository.dart` (ChangeNotifier: `refresh()`, `events`, `latest`, `imageBytes(id)` mit Speicher-Cache), `ApiClient.doorbellEvents/doorbellImage`. Tests mit Fake-Client.

### Task A2: Start-Seite + Verlauf

- [ ] Türkarte: letztes Bild (oder bisheriger Platzhalter), „zuletzt HH:MM“, Chips der HA-Aktionen. Antippen → Verlauf.
- [ ] `DoorbellHistoryScreen`: Liste mit Vorschaubild, Uhrzeit, „angenommen von X“ / „verpasst“, „Tür geöffnet“. Antippen → Vollbild.
- [ ] Refresh bei App-Start, nach jedem Türanruf-Ende und per Pull-to-refresh.
- [ ] Widget-Tests: mit/ohne Bild, verpasst/angenommen, Textgröße ×2 ohne Overflow.

### Task A3: Verpasstes Klingeln mit Bild

- [ ] Kotlin: Endet ein Türanruf unangenommen (vorhandener Pfad für verpasste Anrufe), holt die App das Bild des jüngsten Ereignisses der Tür (`/api/mobile/doorbell?limit=1` + `/image`) und zeigt eine Benachrichtigung „Es hat geklingelt · Haustür · 14:03“ mit BigPictureStyle. Ohne Bild bleibt es beim normalen Text.

### Task A4: E2E

- [ ] Test-Snapshot-Quelle: kleiner HTTP-Server auf CCsrv (`no-git/tools/snapshot_server.py`, liefert ein JPEG mit Uhrzeit), bei Nebenstelle 17 als Quelle eintragen. `door_sim.py --to 18` → Ereignis mit Bild in der API, App-Startseite zeigt es, Ablehnen → Benachrichtigung mit Bild.
- [ ] HANDOFF aktualisieren.
