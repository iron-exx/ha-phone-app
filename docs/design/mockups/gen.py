"""Generates the HA-Phone redesign artboards (.dc.html) + canvas.json."""
import json
from datetime import datetime, timezone
from pathlib import Path

OUT = Path(__file__).parent / "project"
W, H = 390, 844

# ---------- icons (24px stroke paths, lucide-style) ----------
I = {
    "phone": '<path d="M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3.1 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.1 4.2 2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7c.1.9.4 1.8.7 2.7a2 2 0 0 1-.5 2.1L8 9.8a16 16 0 0 0 6 6l1.3-1.3a2 2 0 0 1 2.1-.4c.9.3 1.8.6 2.7.7a2 2 0 0 1 1.7 2z"/>',
    "phone-off": '<path d="M10.7 13.3a16 16 0 0 1-2.7-3.5l1.3-1.3a2 2 0 0 0 .5-2.1c-.3-.9-.6-1.8-.7-2.7A2 2 0 0 0 7.1 2h-3a2 2 0 0 0-2 2.2 19.8 19.8 0 0 0 3.1 8.6"/><path d="M22 2 2 22"/><path d="M14.7 16.4a16 16 0 0 0 1.4.6l1.3-1.3a2 2 0 0 1 2.1-.4c.9.3 1.8.6 2.7.7a2 2 0 0 1 1.7 2v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3.1"/>',
    "mic-off": '<path d="M2 2l20 20"/><path d="M18.9 13A7 7 0 0 0 19 12v-2"/><path d="M5 10v2a7 7 0 0 0 12 5"/><path d="M15 9.3V5a3 3 0 0 0-5.7-1.3"/><path d="M9 9v3a3 3 0 0 0 5.1 2.1"/><path d="M12 19v3"/>',
    "speaker": '<path d="M11 5 6 9H2v6h4l5 4V5z"/><path d="M15.5 8.5a5 5 0 0 1 0 7"/><path d="M19 5a10 10 0 0 1 0 14"/>',
    "pause": '<rect x="6" y="4" width="4" height="16" rx="1"/><rect x="14" y="4" width="4" height="16" rx="1"/>',
    "keypad": '<circle cx="6" cy="5" r="1.2"/><circle cx="12" cy="5" r="1.2"/><circle cx="18" cy="5" r="1.2"/><circle cx="6" cy="11" r="1.2"/><circle cx="12" cy="11" r="1.2"/><circle cx="18" cy="11" r="1.2"/><circle cx="6" cy="17" r="1.2"/><circle cx="12" cy="17" r="1.2"/><circle cx="18" cy="17" r="1.2"/><circle cx="12" cy="22" r="1.2"/>',
    "transfer": '<path d="M16 3h5v5"/><path d="M21 3l-7 7"/><path d="M8 21H3v-5"/><path d="M3 21l7-7"/>',
    "more": '<circle cx="5" cy="12" r="1.5"/><circle cx="12" cy="12" r="1.5"/><circle cx="19" cy="12" r="1.5"/>',
    "door": '<path d="M13 4h3a2 2 0 0 1 2 2v14"/><path d="M2 20h3"/><path d="M13 20h9"/><path d="M10 12v.01"/><path d="M13 4.6v16.2a1 1 0 0 1-1.2 1L5 20V5.6a2 2 0 0 1 1.5-1.9l4-1a2 2 0 0 1 2.5 1.9z"/>',
    "bulb": '<path d="M9 18h6"/><path d="M10 22h4"/><path d="M15.1 14c.2-1 .7-1.7 1.5-2.5A6 6 0 1 0 6 8c0 1.3.5 2.6 1.5 3.5.7.8 1.3 1.5 1.5 2.5"/>',
    "garage": '<path d="M3 21V9l9-6 9 6v12"/><path d="M7 21v-8h10v8"/><path d="M7 16h10"/>',
    "video": '<path d="m16 13 5.2 3.1a.5.5 0 0 0 .8-.4V8.3a.5.5 0 0 0-.8-.4L16 11"/><rect x="2" y="6" width="14" height="12" rx="2"/>',
    "search": '<circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/>',
    "star": '<path d="m12 2 3.1 6.3 6.9 1-5 4.9 1.2 6.8L12 17.8 5.8 21l1.2-6.8-5-4.9 6.9-1z"/>',
    "home": '<path d="M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6h-6v6H4a1 1 0 0 1-1-1z"/>',
    "history": '<path d="M3 12a9 9 0 1 0 3-6.7L3 8"/><path d="M3 3v5h5"/><path d="M12 7v5l4 2"/>',
    "users": '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.9"/><path d="M16 3.1a4 4 0 0 1 0 7.8"/>',
    "voicemail": '<circle cx="6" cy="12" r="4"/><circle cx="18" cy="12" r="4"/><path d="M6 16h12"/>',
    "rec": '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="4" fill="currentColor"/>',
    "shield": '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><path d="m9 12 2 2 4-4"/>',
    "bell": '<path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.9 1.9 0 0 0 3.4 0"/>',
    "bell-off": '<path d="M8.7 3A6 6 0 0 1 18 8a21 21 0 0 0 .6 5"/><path d="M17 17H3s3-2 3-9a4.7 4.7 0 0 1 .3-1.7"/><path d="M10.3 21a1.9 1.9 0 0 0 3.4 0"/><path d="m2 2 20 20"/>',
    "chev": '<path d="m9 18 6-6-6-6"/>',
    "check": '<path d="M20 6 9 17l-5-5"/>',
    "x": '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>',
    "in": '<path d="M17 7 7 17"/><path d="M17 17H7V7"/>',
    "out": '<path d="M7 17 17 7"/><path d="M7 7h10v10"/>',
    "missed": '<path d="m16 2 6 6"/><path d="m22 2-6 6"/><path d="M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3.1 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.1 4.2 2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7c.1.9.4 1.8.7 2.7a2 2 0 0 1-.5 2.1L8 9.8a16 16 0 0 0 6 6l1.3-1.3a2 2 0 0 1 2.1-.4c.9.3 1.8.6 2.7.7a2 2 0 0 1 1.7 2z"/>',
    "smartphone": '<rect x="6" y="2" width="12" height="20" rx="2"/><path d="M11 18h2"/>',
    "desk": '<rect x="3" y="4" width="18" height="12" rx="2"/><path d="M8 20h8"/><path d="M12 16v4"/>',
    "swap": '<path d="m17 2 4 4-4 4"/><path d="M3 11v-1a4 4 0 0 1 4-4h14"/><path d="m7 22-4-4 4-4"/><path d="M21 13v1a4 4 0 0 1-4 4H3"/>',
    "merge": '<circle cx="18" cy="18" r="3"/><circle cx="6" cy="6" r="3"/><path d="M6 21V9a9 9 0 0 0 9 9"/>',
    "lock": '<rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
    "play": '<path d="M7 4v16l13-8z"/>',
    "plus": '<path d="M12 5v14"/><path d="M5 12h14"/>',
    "backspace": '<path d="M21 5H8l-6 7 6 7h13a1 1 0 0 0 1-1V6a1 1 0 0 0-1-1z"/><path d="m17 9-6 6"/><path d="m11 9 6 6"/>',
    "users-plus": '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M19 8v6"/><path d="M22 11h-6"/>',
    "route": '<circle cx="6" cy="19" r="3"/><path d="M9 19h8.5a3.5 3.5 0 0 0 0-7h-11a3.5 3.5 0 0 1 0-7H15"/><circle cx="18" cy="5" r="3"/>',
    "headphones": '<path d="M3 14h3a2 2 0 0 1 2 2v3a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-7a9 9 0 0 1 18 0v7a2 2 0 0 1-2 2h-1a2 2 0 0 1-2-2v-3a2 2 0 0 1 2-2h3"/>',
    "info": '<circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/>',
    "wifi": '<path d="M5 12.6a10 10 0 0 1 14 0"/><path d="M8.5 16.1a5 5 0 0 1 7 0"/><path d="M2 8.8a15 15 0 0 1 20 0"/><path d="M12 20h.01"/>',
    "battery": '<rect x="2" y="7" width="16" height="10" rx="2"/><path d="M22 11v2"/><path d="M6 11v2"/>',
    "moon": '<path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9z"/>',
    "minus-circle": '<circle cx="12" cy="12" r="9"/><path d="M8 12h8"/>',
    "settings": '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>',
    "wave": '<path d="M2 12h2"/><path d="M6 8v8"/><path d="M10 5v14"/><path d="M14 9v6"/><path d="M18 7v10"/><path d="M22 12h-2"/>',
}


def ic(name, size=22, color="currentColor", sw=2):
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 24 24" fill="none" stroke="{color}" '
            f'stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{I[name]}</svg>')


# ---------- tokens ----------
T = dict(
    ground="#0B0F14", surface="#131A22", raised="#1B2430", high="#243040", stroke="#2A3544",
    text="#EAF0F6", muted="#A3B0BF", faint="#7B8898",
    blue="#38BDF8", blue_ink="#04263A", blue_soft="#0E3148",
    answer="#2FBF71", answer_ink="#032313", end="#E5484D",
    door="#F5A524", door_ink="#2A1800", door_soft="#3A2A0E",
    avail="#2FBF71", away="#F5A524", dnd="#E5484D", busy="#E5484D", off="#6B7787",
)

CSS = """
body{margin:0;background:#05080B;font-family:'Manrope',system-ui,sans-serif;color:%(text)s}
*{box-sizing:border-box}
button{font:inherit;color:inherit;border:0;background:none;padding:0;cursor:pointer}
a{color:%(blue)s}a:hover{color:#7DD3FC}
.scr{width:390px;height:844px;background:%(ground)s;color:%(text)s;position:relative;overflow:hidden;display:flex;flex-direction:column}
.disp{font-family:'Bricolage Grotesque','Manrope',sans-serif;letter-spacing:-0.01em}
.num{font-variant-numeric:tabular-nums}
.muted{color:%(muted)s}.faint{color:%(faint)s}
.card{background:%(surface)s;border:1px solid %(stroke)s;border-radius:22px}
.chip{display:inline-flex;align-items:center;gap:6px;height:32px;padding:0 12px;border-radius:999px;background:%(raised)s;border:1px solid %(stroke)s;font-size:13px;font-weight:600;color:%(text)s}
.chip.on{background:%(blue_soft)s;border-color:%(blue)s;color:#BAE6FD}
.av{position:relative;flex:none;display:flex;align-items:center;justify-content:center;border-radius:50%%;font-weight:800;color:%(text)s;background:%(high)s}
.ring{position:absolute;inset:-3px;border-radius:50%%;border:2.5px solid}
.glyph{position:absolute;right:-3px;bottom:-3px;width:18px;height:18px;border-radius:50%%;display:flex;align-items:center;justify-content:center;border:2.5px solid %(ground)s}
.nav{position:absolute;left:0;right:0;bottom:0;height:88px;padding:0 18px 18px;display:flex;align-items:flex-end;justify-content:space-between;background:linear-gradient(to top,%(ground)s 70%%,rgba(11,15,20,0))}
.tab{width:72px;height:56px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:4px;font-size:11px;font-weight:700;color:%(faint)s;border-radius:18px}
.tab.on{color:%(text)s}
.tab.on .pill{background:%(blue_soft)s;color:%(blue)s}
.pill{width:52px;height:30px;border-radius:15px;display:flex;align-items:center;justify-content:center}
.fab{width:68px;height:68px;border-radius:24px;background:%(blue)s;color:%(blue_ink)s;display:flex;align-items:center;justify-content:center;margin-bottom:4px;box-shadow:0 10px 30px rgba(56,189,248,.28)}
.row{display:flex;align-items:center;gap:14px;padding:10px 20px;min-height:64px}
.sec{font-size:12px;font-weight:800;letter-spacing:.08em;text-transform:uppercase;color:%(faint)s;padding:18px 20px 6px}
.ctl{display:flex;flex-direction:column;align-items:center;gap:8px;font-size:12.5px;font-weight:700;color:%(muted)s}
.ctlb{width:100%%;height:72px;border-radius:22px;background:%(raised)s;display:flex;align-items:center;justify-content:center;color:%(text)s}
.ctlb.act{background:%(text)s;color:%(ground)s}
.big{width:76px;height:76px;border-radius:50%%;display:flex;align-items:center;justify-content:center}
.bar{position:absolute;left:0;top:14px;bottom:14px;width:4px;border-radius:0 4px 4px 0}
""" % T

HEAD = """<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<title>{title}</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,500;12..96,700;12..96,800&amp;family=Manrope:wght@500;600;700;800&amp;display=swap">
<style>{css}</style>
</helmet>
"""

TAIL = """
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"$preview":{{"width":{w},"height":{h}}}}}'>
class Component extends DCLogic {{
  renderVals() {{ return {{}}; }}
}}
</script>
</body>
</html>
"""

PRES = {
    "avail": (T["avail"], "check", "verfügbar"),
    "away": (T["away"], "moon", "abwesend"),
    "dnd": (T["dnd"], "minus-circle", "nicht stören"),
    "busy": (T["busy"], "phone", "telefoniert"),
    "off": (T["off"], None, "offline"),
}


def avatar(initials, pres="avail", size=48, bg=None):
    color, glyph, _ = PRES[pres]
    ring = "" if pres == "off" else f'<span class="ring" style="border-color:{color}"></span>'
    g = ""
    if glyph:
        g = f'<span class="glyph" style="background:{color};color:{T["ground"]}">{ic(glyph, 10, T["ground"], 3.2)}</span>'
    return (f'<div class="av" style="width:{size}px;height:{size}px;font-size:{int(size*0.36)}px;'
            f'background:{bg or T["high"]}">{initials}{ring}{g}</div>')


def nav(active):
    tabs = [("start", "Start", "home"), ("verlauf", "Verlauf", "history"), None, ("kontakte", "Kontakte", "users"), ("ich", "Ich", "settings")]
    parts = []
    for t in tabs:
        if t is None:
            parts.append(f'<button class="fab" aria-label="Wählen">{ic("keypad", 26, T["blue_ink"], 2.4)}</button>')
            continue
        key, label, icon = t
        on = " on" if key == active else ""
        badge = ""
        if key == "verlauf":
            badge = f'<span style="position:absolute;margin:-18px 0 0 26px;min-width:18px;height:18px;border-radius:9px;background:{T["end"]};color:#fff;font-size:10.5px;font-weight:800;display:flex;align-items:center;justify-content:center;padding:0 5px">3</span>'
        parts.append(f'<button class="tab{on}"><span class="pill">{ic(icon, 22)}</span>{label}{badge}</button>')
    return f'<nav class="nav">{"".join(parts)}</nav>'


def page(title, body, w=W, h=H):
    return HEAD.format(title=title, css=CSS) + body + TAIL.format(w=w, h=h)


# ======================================================================
def start():
    fav = [("SA", "sandro", "Tischtelefon · 11", "avail", "verfügbar"),
           ("DE", "dect", "DECT · 15", "busy", "telefoniert 04:12"),
           ("LA", "larissa", "Handy · 12", "off", "offline"),
           ("OE", "Oma Erika", "Handy-Kontakt", "avail", "Mobil")]
    tiles = ""
    for ini, name, sub, pres, state in fav:
        col = PRES[pres][0]
        tiles += f'''<button class="card" style="padding:14px;display:flex;flex-direction:column;gap:12px;align-items:flex-start;text-align:left;border-radius:20px">
{avatar(ini, pres, 44)}
<div style="display:flex;flex-direction:column;gap:2px"><span style="font-size:15px;font-weight:800">{name}</span><span class="faint" style="font-size:12px">{sub}</span></div>
<span style="font-size:12px;font-weight:700;color:{col if pres!="off" else T["faint"]}">{state}</span></button>'''
    return page("Start", f'''
<div class="scr">
<header style="display:flex;align-items:center;gap:12px;padding:22px 20px 8px">
{avatar("EM", "avail", 44, T["blue_soft"])}
<button style="flex:1;display:flex;flex-direction:column;align-items:flex-start;gap:3px;text-align:left">
<span style="font-size:13px;font-weight:700" class="muted">Emulator-Test · 18</span>
<span style="display:inline-flex;align-items:center;gap:6px;height:28px;padding:0 11px;border-radius:14px;background:#0F2A1C;color:#7EE2A8;font-size:12.5px;font-weight:800">{ic("bell",14,"#7EE2A8",2.4)} Klingelt hier · verfügbar {ic("chev",14,"#7EE2A8",2.4)}</span>
</button>
<button class="chip" style="width:44px;height:44px;padding:0;justify-content:center" aria-label="Suchen">{ic("search",20)}</button>
</header>

<section class="card" style="margin:12px 16px 0;overflow:hidden;border-radius:26px">
<div style="height:176px;position:relative;background:#1A1410;display:flex;align-items:center;justify-content:center">
<div style="display:flex;flex-direction:column;align-items:center;gap:8px;color:#8A7A66">{ic("video",34,"#8A7A66",1.6)}<span style="font-size:12px;font-weight:700">Letztes Bild der Haustür</span></div>
<span style="position:absolute;left:14px;top:14px;display:inline-flex;align-items:center;gap:6px;height:26px;padding:0 10px;border-radius:13px;background:rgba(11,15,20,.72);font-size:12px;font-weight:800">{ic("door",14,T["door"],2.2)} Haustür</span>
<span class="num" style="position:absolute;right:14px;top:14px;height:26px;padding:0 10px;border-radius:13px;background:rgba(11,15,20,.72);font-size:12px;font-weight:700;display:flex;align-items:center">zuletzt 10:44</span>
</div>
<div style="display:flex;gap:10px;padding:12px">
<button style="flex:1;height:52px;border-radius:16px;background:{T["door"]};color:{T["door_ink"]};font-weight:800;font-size:15px;display:flex;align-items:center;justify-content:center;gap:8px">{ic("door",20,T["door_ink"],2.2)} Tür öffnen</button>
<button style="width:52px;height:52px;border-radius:16px;background:{T["raised"]};display:flex;align-items:center;justify-content:center" aria-label="Licht an">{ic("bulb",20)}</button>
<button style="width:52px;height:52px;border-radius:16px;background:{T["raised"]};display:flex;align-items:center;justify-content:center" aria-label="Live ansehen">{ic("video",20)}</button>
</div>
</section>

<section style="margin:12px 16px 0;padding:12px 14px;border-radius:18px;background:#0F2A1C;border:1px solid #1E4D33;display:flex;align-items:center;gap:12px">
{ic("desk",22,"#7EE2A8",2)}
<div style="flex:1;display:flex;flex-direction:column;gap:2px"><span style="font-size:13.5px;font-weight:800">Gespräch am Tischtelefon</span><span class="num" style="font-size:12px;color:#7EE2A8">mit Oma Erika · 02:31</span></div>
<button style="height:38px;padding:0 14px;border-radius:12px;background:{T["answer"]};color:{T["answer_ink"]};font-weight:800;font-size:13px">Hierher holen</button>
</section>

<div class="sec" style="display:flex;justify-content:space-between"><span>Favoriten</span><span style="color:{T["blue"]};letter-spacing:0;text-transform:none;font-size:13px">Bearbeiten</span></div>
<div style="display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px;padding:0 16px">{tiles}</div>

<section class="card" style="margin:12px 16px 0;padding:12px 14px;display:flex;align-items:center;gap:12px;border-radius:18px">
<button style="width:40px;height:40px;border-radius:50%;background:{T["blue"]};display:flex;align-items:center;justify-content:center" aria-label="Abspielen">{ic("play",16,T["blue_ink"],2.4)}</button>
<div style="flex:1;display:flex;flex-direction:column;gap:3px"><span style="font-size:13.5px;font-weight:800">Neue Voicemail · Tür-Simulator</span><span class="num faint" style="font-size:12px">heute 09:12 · 0:12</span></div>
{ic("chev",18,T["faint"])}
</section>
{nav("start")}
</div>''')


def verlauf():
    def item(ini, name, meta, time, kind, pres="off", unread=False, extra=""):
        colors = {"missed": T["end"], "vm": T["blue"], "rec": T["end"], "door": T["door"], "in": T["muted"], "out": T["muted"]}
        icons = {"missed": "missed", "vm": "voicemail", "rec": "rec", "door": "door", "in": "in", "out": "out"}
        bar = f'<span class="bar" style="background:{colors[kind]}"></span>' if unread else ""
        weight = 800 if unread else 600
        return f'''<div class="row" style="position:relative">{bar}{avatar(ini, pres, 44)}
<div style="flex:1;display:flex;flex-direction:column;gap:3px;min-width:0"><span style="font-size:15px;font-weight:{weight}">{name}</span>
<span style="display:flex;align-items:center;gap:6px;font-size:12.5px;color:{colors[kind] if kind in ("missed","door") else T["muted"]}">{ic(icons[kind],14,colors[kind],2.2)} {meta}</span>{extra}</div>
<span class="num faint" style="font-size:12px;align-self:flex-start;padding-top:4px">{time}</span></div>'''
    player = f'''<div style="margin-top:8px;display:flex;align-items:center;gap:10px;padding:8px 10px;border-radius:14px;background:{T["raised"]}">
<button style="width:30px;height:30px;border-radius:50%;background:{T["blue"]};display:flex;align-items:center;justify-content:center" aria-label="Abspielen">{ic("play",13,T["blue_ink"],2.6)}</button>
<svg width="150" height="22" viewBox="0 0 150 22" aria-hidden="true">{"".join(f'<rect x="{i*6}" y="{11-h/2}" width="3" height="{h}" rx="1.5" fill="{T["blue"] if i<9 else T["stroke"]}"/>' for i,h in enumerate([6,10,16,12,20,14,8,18,12,6,14,10,18,8,12,16,6,10,14,8,12,6,10,4,8]))}</svg>
<span class="num faint" style="font-size:11.5px">0:12</span><span class="chip" style="height:24px;padding:0 8px;font-size:11px">1,5×</span></div>'''
    rows = "".join([
        '<div class="sec">Heute</div>',
        item("TÜ", "Tür-Simulator", "Verpasst · mit Video", "10:45", "door", "avail", True),
        item("TÜ", "Tür-Simulator", "Voicemail · 0:12", "09:12", "vm", "avail", True, player),
        item("OE", "Oma Erika", "Eingehend · 4:31 · aufgezeichnet", "08:40", "in", "avail", False,
             f'<span style="display:flex;align-items:center;gap:6px;font-size:12px;color:{T["end"]};margin-top:2px">{ic("rec",13,T["end"],2)} Aufnahme 4:31</span>'),
        item("SA", "sandro", "Verpasst", "08:02", "missed", "avail", True),
        '<div class="sec">Gestern</div>',
        item("DE", "dect", "Ausgehend · 1:08", "17:21", "out", "busy"),
        item("43", "Echo-Test *43", "Ausgehend · 0:24", "16:05", "out", "off"),
    ])
    chips = "".join(f'<button class="chip{" on" if i==0 else ""}">{l}</button>' for i, l in enumerate(["Alle", "Verpasst · 3", "Voicemail", "Aufnahmen", "Tür"]))
    return page("Verlauf", f'''<div class="scr">
<header style="padding:22px 20px 6px;display:flex;align-items:center;justify-content:space-between"><h1 class="disp" style="margin:0;font-size:32px;font-weight:800">Verlauf</h1>
<button class="chip" style="width:44px;height:44px;padding:0;justify-content:center" aria-label="Suchen">{ic("search",20)}</button></header>
<div style="display:flex;gap:8px;padding:8px 20px 4px;overflow:hidden">{chips}</div>
{rows}
<div style="margin:6px 20px;padding:10px 14px;border-radius:14px;border:1px dashed {T["stroke"]};font-size:12px;display:flex;gap:8px;align-items:center" class="faint">{ic("swap",15,T["faint"])} Nach rechts wischen: zurückrufen · nach links: löschen</div>
{nav("verlauf")}</div>''')


def waehlen():
    keys = [("1", ""), ("2", "ABC"), ("3", "DEF"), ("4", "GHI"), ("5", "JKL"), ("6", "MNO"), ("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ"), ("*", ""), ("0", "+"), ("#", "")]
    k = "".join(f'<button style="height:66px;border-radius:22px;background:{T["surface"]};display:flex;flex-direction:column;align-items:center;justify-content:center;gap:1px"><span class="disp num" style="font-size:28px;font-weight:700">{a}</span><span style="font-size:10px;font-weight:800;letter-spacing:.14em;color:{T["faint"]};height:12px">{b}</span></button>' for a, b in keys)
    return page("Wählen", f'''<div class="scr">
<header style="padding:22px 20px 0;display:flex;align-items:center;justify-content:space-between">
<span class="chip">{ic("smartphone",15)} Leitung 1 · 18</span>
<span class="chip" style="color:#7EE2A8">{ic("check",14,"#7EE2A8",2.6)} bereit</span></header>
<div style="padding:34px 20px 0;text-align:center"><div class="disp num" style="font-size:40px;font-weight:700;letter-spacing:.02em">0171 123 45</div></div>
<div style="margin:16px 20px 0;display:flex;flex-direction:column;gap:8px">
<button class="card" style="display:flex;align-items:center;gap:12px;padding:10px 12px;border-radius:18px;text-align:left">{avatar("OE","avail",40)}
<div style="flex:1;display:flex;flex-direction:column;gap:2px"><span style="font-size:14.5px;font-weight:800">Oma Erika</span><span class="num faint" style="font-size:12px"><b style="color:{T["text"]}">0171 123 45</b>67 · Handy</span></div>{ic("phone",18,T["answer"])}</button>
</div>
<div style="display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px;padding:18px 28px 0">{k}</div>
<div style="display:flex;align-items:center;justify-content:space-between;padding:16px 44px 0">
<button style="width:56px;height:56px;border-radius:18px;display:flex;align-items:center;justify-content:center" aria-label="Video-Anruf">{ic("video",22,T["muted"])}</button>
<button class="big" style="background:{T["answer"]};color:{T["answer_ink"]}" aria-label="Anrufen">{ic("phone",30,T["answer_ink"],2.2)}</button>
<button style="width:56px;height:56px;border-radius:18px;display:flex;align-items:center;justify-content:center" aria-label="Löschen">{ic("backspace",24,T["muted"])}</button></div>
</div>''')


def kontakte():
    def c(ini, name, sub, pres, action=""):
        col, _, label = PRES[pres]
        return f'''<div class="row">{avatar(ini, pres, 46)}<div style="flex:1;display:flex;flex-direction:column;gap:3px"><span style="font-size:15px;font-weight:700">{name}</span>
<span style="font-size:12.5px;display:flex;gap:6px;align-items:center"><span style="color:{col if pres!="off" else T["faint"]};font-weight:700">{label}</span><span class="faint">· {sub}</span></span></div>{action}</div>'''
    call = f'<button style="width:44px;height:44px;border-radius:14px;background:{T["raised"]};display:flex;align-items:center;justify-content:center" aria-label="Anrufen">{ic("phone",18,T["answer"])}</button>'
    door_btn = f'<button style="height:40px;padding:0 12px;border-radius:14px;background:{T["door_soft"]};color:{T["door"]};font-weight:800;font-size:12.5px;display:flex;align-items:center;gap:6px">{ic("door",16,T["door"],2.2)} Öffnen</button>'
    chips = "".join(f'<button class="chip{" on" if i==0 else ""}">{l}</button>' for i, l in enumerate(["Alle", "Nebenstellen", "Handy", "Telefonbuch", "Favoriten"]))
    return page("Kontakte", f'''<div class="scr">
<header style="padding:22px 20px 6px"><h1 class="disp" style="margin:0;font-size:32px;font-weight:800">Kontakte</h1></header>
<label style="margin:6px 16px 0;height:50px;border-radius:16px;background:{T["surface"]};border:1px solid {T["stroke"]};display:flex;align-items:center;gap:10px;padding:0 14px">{ic("search",19,T["faint"])}<input aria-label="Suchen" placeholder="Name, Nummer oder Nebenstelle" style="flex:1;background:none;border:0;color:{T["text"]};font:inherit;font-size:15px;outline:none"></label>
<div style="display:flex;gap:8px;padding:12px 16px 2px;overflow:hidden">{chips}</div>
<div class="sec">Türstationen</div>
<div class="row"><div class="av" style="width:46px;height:46px;border-radius:15px;background:{T["door_soft"]}">{ic("door",22,T["door"],2)}</div>
<div style="flex:1;display:flex;flex-direction:column;gap:3px"><span style="font-size:15px;font-weight:700">Haustür</span><span class="faint" style="font-size:12.5px">türklingel · 16 · Video</span></div>{door_btn}</div>
<div class="sec">Kolleg:innen</div>
{c("SA","sandro","Tischtelefon 11","avail",call)}
{c("DE","dect","DECT 15","busy",call)}
{c("TE","Test","13","dnd",call)}
{c("LA","larissa","Handy 12","off",call)}
<div class="sec">Handy</div>
{c("OE","Oma Erika","Mobil +49 171 1234567","avail",call)}
{nav("kontakte")}</div>''')


def door_ring():
    return page("Tür klingelt (gesperrt)", f'''<div class="scr" style="background:#000">
<div style="position:absolute;inset:0 0 316px 0;background:#15110D;display:flex;align-items:center;justify-content:center">
<div style="display:flex;flex-direction:column;align-items:center;gap:10px;color:#7D6D5A">{ic("video",46,"#7D6D5A",1.4)}<span style="font-size:13px;font-weight:700">Live-Bild der Türstation</span></div>
</div>
<div style="position:absolute;left:0;right:0;top:0;padding:22px 20px;display:flex;justify-content:space-between;align-items:center">
<span style="display:inline-flex;align-items:center;gap:6px;height:28px;padding:0 11px;border-radius:14px;background:rgba(0,0,0,.55);font-size:12px;font-weight:800">{ic("lock",13,T["text"],2.4)} Gesperrt</span>
<span style="display:inline-flex;align-items:center;gap:6px;height:28px;padding:0 11px;border-radius:14px;background:{T["end"]};font-size:12px;font-weight:800;color:#fff"><span style="width:7px;height:7px;border-radius:50%;background:#fff"></span>LIVE</span></div>
<div style="position:absolute;left:20px;right:20px;top:420px;display:flex;flex-direction:column;gap:4px">
<span style="font-size:13px;font-weight:800;letter-spacing:.08em;text-transform:uppercase;color:{T["door"]}">Es klingelt an der Tür</span>
<span class="disp" style="font-size:40px;font-weight:800;line-height:1.05">Haustür</span>
<span class="num muted" style="font-size:14px">türklingel · 16 · 10:44</span></div>
<div style="position:absolute;left:0;right:0;bottom:0;height:316px;background:{T["ground"]};border-radius:30px 30px 0 0;padding:20px;display:flex;flex-direction:column;gap:16px">
<div style="display:flex;gap:8px">
<button class="chip" style="height:40px">{ic("bulb",16)} Licht an</button><button class="chip" style="height:40px">{ic("garage",16)} Garage</button></div>
<div style="height:64px;border-radius:32px;background:{T["door_soft"]};border:1px solid #5A4216;position:relative;display:flex;align-items:center;justify-content:center">
<span style="position:absolute;left:6px;top:6px;width:52px;height:52px;border-radius:50%;background:{T["door"]};display:flex;align-items:center;justify-content:center">{ic("door",24,T["door_ink"],2.2)}</span>
<span style="font-weight:800;color:{T["door"]};font-size:15px">Zum Öffnen nach rechts schieben</span></div>
<div style="display:flex;justify-content:space-between;align-items:flex-end;padding:6px 18px 0">
<div class="ctl"><button class="big" style="background:{T["end"]};color:#fff" aria-label="Ablehnen">{ic("phone-off",30,"#fff",2.2)}</button>Ablehnen</div>
<div class="ctl"><button class="big" style="width:64px;height:64px;background:{T["raised"]}" aria-label="Mit Video annehmen">{ic("video",24)}</button>Mit Video</div>
<div class="ctl"><button class="big" style="background:{T["answer"]};color:{T["answer_ink"]}" aria-label="Annehmen">{ic("phone",30,T["answer_ink"],2.2)}</button>Annehmen</div>
</div></div></div>''')


def grid(items):
    cells = ""
    for label, icon, state in items:
        cls = "ctlb"
        style = ""
        if state == "act":
            cls += " act"
        if state == "door":
            style = f'background:{T["door"]};color:{T["door_ink"]}'
        cells += f'<div class="ctl"><button class="{cls}" style="{style}" aria-label="{label}">{ic(icon, 26, "currentColor", 2)}</button>{label}</div>'
    return f'<div style="display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:14px 14px;padding:0 24px">{cells}</div>'


def end_btn():
    return f'<div style="display:flex;justify-content:center;padding:22px 0 30px"><button class="big" style="width:80px;height:80px;background:{T["end"]};color:#fff" aria-label="Auflegen">{ic("phone-off",32,"#fff",2.2)}</button></div>'


def door_call():
    return page("Türgespräch", f'''<div class="scr">
<div style="margin:16px 16px 0;height:300px;border-radius:26px;background:#15110D;position:relative;display:flex;align-items:center;justify-content:center;overflow:hidden">
<div style="display:flex;flex-direction:column;align-items:center;gap:8px;color:#7D6D5A">{ic("video",40,"#7D6D5A",1.4)}<span style="font-size:12px;font-weight:700">Live-Bild</span></div>
<span style="position:absolute;left:12px;top:12px;display:inline-flex;align-items:center;gap:6px;height:28px;padding:0 10px;border-radius:14px;background:rgba(11,15,20,.72);font-size:12px;font-weight:800">{ic("door",14,T["door"],2.2)} Haustür</span>
<span style="position:absolute;right:12px;top:12px;display:inline-flex;align-items:center;gap:6px;height:28px;padding:0 10px;border-radius:14px;background:{T["end"]};color:#fff;font-size:12px;font-weight:800"><span style="width:7px;height:7px;border-radius:50%;background:#fff"></span>REC 00:18</span>
</div>
<div style="text-align:center;padding:16px 0 18px"><div class="disp" style="font-size:26px;font-weight:800">Haustür</div><div class="num muted" style="font-size:14px;margin-top:2px">00:42 · HD-Audio</div></div>
{grid([("Stumm","mic-off",""),("Lautsprecher","speaker","act"),("Tür öffnen","door","door"),("Tastatur","keypad",""),("Licht an","bulb",""),("Mehr","more","")])}
<div style="flex:1"></div>{end_btn()}</div>''')


def two_lines():
    return page("Zwei Leitungen", f'''<div class="scr">
<div style="margin:16px 16px 0;padding:10px 12px;border-radius:18px;background:{T["surface"]};border:1px solid {T["stroke"]};display:flex;align-items:center;gap:12px">
{avatar("SA","avail",38)}<div style="flex:1;display:flex;flex-direction:column;gap:2px"><span style="font-size:14px;font-weight:800">sandro</span><span class="num" style="font-size:12px;color:{T["away"]}">gehalten · 01:02</span></div>
<button class="chip" style="height:36px">{ic("swap",15)} Tauschen</button></div>
<div style="display:flex;flex-direction:column;align-items:center;gap:12px;padding:44px 0 0">
{avatar("OE","busy",112,T["blue_soft"])}
<div class="disp" style="font-size:30px;font-weight:800;margin-top:8px">Oma Erika</div>
<div class="num muted" style="font-size:15px">Handy · 04:31</div>
<button class="chip" style="margin-top:6px;height:38px;background:{T["blue_soft"]};border-color:{T["blue"]};color:#BAE6FD">{ic("merge",15,"#BAE6FD")} Zusammenführen</button></div>
<div style="flex:1"></div>
{grid([("Stumm","mic-off",""),("Lautsprecher","speaker",""),("Halten","pause",""),("Tastatur","keypad",""),("Weiterleiten","transfer",""),("Mehr","more","")])}
{end_btn()}</div>''')


def more_sheet():
    tiles = [("Konferenz", "users-plus"), ("Rückfrage", "plus"), ("Aufnehmen", "rec"), ("Direkt weiterleiten", "route"), ("Audio-Ausgabe", "headphones"), ("Anruf-Info", "info")]
    t = "".join(f'<button style="height:92px;border-radius:20px;background:{T["raised"]};display:flex;flex-direction:column;align-items:center;justify-content:center;gap:8px;font-size:12.5px;font-weight:700">{ic(i,24,T["end"] if l=="Aufnehmen" else T["text"])}{l}</button>' for l, i in tiles)
    return page("Mehr im Gespräch", f'''<div class="scr">
<div style="position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;padding-top:110px;gap:10px;opacity:.35">
{avatar("OE","busy",112,T["blue_soft"])}<div class="disp" style="font-size:30px;font-weight:800;margin-top:8px">Oma Erika</div></div>
<div style="position:absolute;inset:0;background:rgba(3,5,8,.55)"></div>
<div style="position:absolute;left:0;right:0;bottom:0;background:{T["surface"]};border-radius:30px 30px 0 0;border-top:1px solid {T["stroke"]};padding:10px 20px 28px">
<div style="width:40px;height:5px;border-radius:3px;background:{T["stroke"]};margin:0 auto 16px"></div>
<div style="display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px">{t}</div>
<div class="sec" style="padding:20px 0 8px">Audio-Ausgabe</div>
<div style="display:flex;flex-direction:column;gap:6px">
<button style="height:54px;border-radius:16px;background:{T["blue_soft"]};border:1px solid {T["blue"]};display:flex;align-items:center;gap:12px;padding:0 14px;font-weight:700">{ic("headphones",20,T["blue"])} Pixel Buds<span style="flex:1"></span>{ic("check",18,T["blue"],2.6)}</button>
<button style="height:54px;border-radius:16px;background:{T["raised"]};display:flex;align-items:center;gap:12px;padding:0 14px;font-weight:700">{ic("smartphone",20)} Hörer</button>
<button style="height:54px;border-radius:16px;background:{T["raised"]};display:flex;align-items:center;gap:12px;padding:0 14px;font-weight:700">{ic("speaker",20)} Lautsprecher</button></div>
</div></div>''')


def status_sheet():
    opts = [("avail", "Verfügbar", "Anrufe klingeln wie eingestellt"), ("away", "Abwesend", "Nach 20 s zur Voicemail"), ("dnd", "Nicht stören", "Direkt zur Voicemail"),
            ("off", "Feierabend", "Nur Tür und Favoriten")]
    rows = ""
    for i, (p, label, sub) in enumerate(opts):
        col = PRES[p][0] if p != "off" else T["faint"]
        glyph = PRES[p][1] or "moon"
        sel = i == 0
        rows += f'''<button style="height:62px;border-radius:18px;background:{T["blue_soft"] if sel else T["raised"]};border:1px solid {T["blue"] if sel else "transparent"};display:flex;align-items:center;gap:14px;padding:0 14px;text-align:left">
<span style="width:34px;height:34px;border-radius:50%;background:{col};display:flex;align-items:center;justify-content:center">{ic(glyph,17,T["ground"],2.6)}</span>
<span style="flex:1;display:flex;flex-direction:column;gap:2px"><span style="font-weight:800;font-size:15px">{label}</span><span class="faint" style="font-size:12px">{sub}</span></span>{ic("check",20,T["blue"],2.6) if sel else ""}</button>'''
    return page("Status und Klingeln", f'''<div class="scr">
<div style="display:flex;align-items:center;gap:14px;padding:22px 20px 14px">{avatar("EM","avail",60,T["blue_soft"])}
<div style="display:flex;flex-direction:column;gap:3px"><span class="disp" style="font-size:24px;font-weight:800">Emulator-Test</span><span class="faint" style="font-size:13px">Nebenstelle 18 · HA-Phone 0.7.116</span></div></div>
<div class="sec" style="padding-top:4px">Status für alle</div>
<div style="display:flex;flex-direction:column;gap:8px;padding:0 16px">{rows}</div>
<div class="sec">Nur dieses Handy</div>
<div class="card" style="margin:0 16px;padding:14px;display:flex;flex-direction:column;gap:12px;border-radius:20px">
<div style="display:flex;align-items:center;gap:12px">{ic("bell",22,T["answer"])}<div style="flex:1;display:flex;flex-direction:column;gap:2px"><span style="font-weight:800">Klingeln auf diesem Handy</span><span class="faint" style="font-size:12px">Tischtelefon klingelt weiter</span></div>
<button role="switch" aria-checked="true" aria-label="Klingeln auf diesem Handy" style="width:52px;height:32px;border-radius:16px;background:{T["answer"]};position:relative"><span style="position:absolute;right:3px;top:3px;width:26px;height:26px;border-radius:50%;background:#fff"></span></button></div>
<div style="display:flex;gap:8px"><button class="chip">{ic("bell-off",14)} 1 Std</button><button class="chip">bis 17:00</button><button class="chip">bis morgen</button></div></div>
<div class="card" style="margin:10px 16px 0;padding:12px 14px;display:flex;align-items:center;gap:12px;border-radius:18px">{ic("route",20,T["blue"])}
<div style="flex:1;font-size:13px;line-height:1.35"><b>Nicht rangegangen</b> → nach 20 s → <b>Voicemail</b></div>{ic("chev",18,T["faint"])}</div>
{nav("ich")}</div>''')


def reach():
    items = [("ok", "bell", "Benachrichtigungen", "erlaubt"), ("ok", "smartphone", "Anrufe im Vollbild", "auch bei Sperre"),
             ("ok", "battery", "Akku-Optimierung", "ausgenommen"), ("ok", "wifi", "Verbindung zur Anlage", "TLS · 18 ms"),
             ("ok", "video", "Türvideo durch NAT", "STUN · Keep-Alive"), ("warn", "moon", "Nicht stören", "Anrufe werden stummgeschaltet")]
    rows = ""
    for st, icon, label, sub in items:
        col = T["answer"] if st == "ok" else T["door"]
        right = (f'<span style="width:28px;height:28px;border-radius:50%;background:{col};display:flex;align-items:center;justify-content:center">{ic("check",15,T["ground"],3)}</span>'
                 if st == "ok" else f'<button style="height:34px;padding:0 12px;border-radius:12px;background:{T["door"]};color:{T["door_ink"]};font-weight:800;font-size:12.5px">Beheben</button>')
        rows += f'''<div style="display:flex;align-items:center;gap:14px;padding:12px 14px;border-radius:18px;background:{T["surface"]};border:1px solid {T["stroke"] if st=="ok" else "#5A4216"}">
<span style="width:40px;height:40px;border-radius:13px;background:{T["raised"]};display:flex;align-items:center;justify-content:center">{ic(icon,20,col)}</span>
<span style="flex:1;display:flex;flex-direction:column;gap:2px"><span style="font-weight:800;font-size:14.5px">{label}</span><span class="faint" style="font-size:12px">{sub}</span></span>{right}</div>'''
    return page("Erreichbarkeit", f'''<div class="scr">
<header style="padding:22px 20px 0"><h1 class="disp" style="margin:0;font-size:32px;font-weight:800">Erreichbarkeit</h1></header>
<div style="margin:14px 16px 0;padding:18px;border-radius:24px;background:#0F2A1C;border:1px solid #1E4D33;display:flex;gap:14px;align-items:center">
{ic("shield",40,"#7EE2A8",1.8)}<div style="display:flex;flex-direction:column;gap:4px"><span class="disp" style="font-size:20px;font-weight:800">Fast alles bereit</span><span style="font-size:13px;color:#A7EBC4">5 von 6 Punkten erfüllt. Anrufe kommen auch bei gesperrtem Handy.</span></div></div>
<div style="display:flex;flex-direction:column;gap:8px;padding:14px 16px 0">{rows}</div>
<div style="flex:1"></div>
<div style="padding:0 16px 34px;display:flex;flex-direction:column;gap:8px">
<button style="height:56px;border-radius:18px;background:{T["blue"]};color:{T["blue_ink"]};font-weight:800;font-size:15px;display:flex;align-items:center;justify-content:center;gap:10px">{ic("phone",20,T["blue_ink"],2.2)} Test-Anruf an mich</button>
<span class="faint" style="font-size:12px;text-align:center">Die Anlage ruft dieses Handy in 10 Sekunden an. Sperr es ruhig.</span></div></div>''')


def system():
    sw = [("Grund", T["ground"]), ("Fläche", T["surface"]), ("Erhöht", T["raised"]), ("Linie", T["stroke"]), ("Text", T["text"]), ("Leise", T["muted"]),
          ("HA-Blau", T["blue"]), ("Annehmen", T["answer"]), ("Auflegen", T["end"]), ("Tür", T["door"])]
    s = "".join(f'<div style="display:flex;flex-direction:column;gap:8px"><div style="height:72px;border-radius:18px;background:{c};border:1px solid {T["stroke"]}"></div><span style="font-size:13px;font-weight:800">{n}</span><span class="num faint" style="font-size:12px">{c}</span></div>' for n, c in sw)
    pres = "".join(f'<div style="display:flex;align-items:center;gap:12px">{avatar(i,p,48)}<span style="font-weight:700">{PRES[p][2]}</span></div>' for i, p in [("VF","avail"),("AB","away"),("NS","dnd"),("TL","busy"),("OF","off")])
    return page("Design-System", f'''<div style="width:1280px;height:844px;background:{T["ground"]};color:{T["text"]};padding:56px 64px;display:flex;flex-direction:column;gap:36px;box-sizing:border-box">
<div style="display:flex;justify-content:space-between;align-items:flex-end"><div><div class="disp" style="font-size:56px;font-weight:800;line-height:1">Nachtwache</div><div class="muted" style="font-size:16px;margin-top:10px">Design-System der HA-Phone App · dunkel zuerst, helles Thema mit denselben Rollen</div></div>
<div class="faint" style="font-size:13px;text-align:right;line-height:1.6">Bricolage Grotesque · Titel und Zahlen<br>Manrope · Oberfläche und Text</div></div>
<div style="display:grid;grid-template-columns:repeat(10,minmax(0,1fr));gap:14px">{s}</div>
<div style="display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:40px">
<div style="display:flex;flex-direction:column;gap:12px"><div class="sec" style="padding:0">Schrift</div>
<span class="disp" style="font-size:40px;font-weight:800;line-height:1.05">Haustür</span><span class="disp num" style="font-size:28px;font-weight:700">0171 123 45</span>
<span style="font-size:15px;font-weight:700">Oma Erika · Zeilentitel 15</span><span class="muted" style="font-size:13px">Metazeile 12,5 · leise, 4,5:1 Kontrast</span></div>
<div style="display:flex;flex-direction:column;gap:14px"><div class="sec" style="padding:0">Präsenz = Farbe + Form</div>{pres}</div>
<div style="display:flex;flex-direction:column;gap:16px"><div class="sec" style="padding:0">Anrufaktionen</div>
<div style="display:flex;gap:18px;align-items:center">
<button class="big" style="background:{T["answer"]}" aria-label="Annehmen">{ic("phone",30,T["answer_ink"],2.2)}</button>
<button class="big" style="background:{T["end"]}" aria-label="Auflegen">{ic("phone-off",30,"#fff",2.2)}</button>
<button class="big" style="background:{T["door"]}" aria-label="Tür öffnen">{ic("door",28,T["door_ink"],2.2)}</button>
<button class="big" style="border-radius:24px;background:{T["raised"]}" aria-label="Stumm">{ic("mic-off",26)}</button></div>
<span class="muted" style="font-size:13px;line-height:1.5">Grün nur für Annehmen, Rot nur für Auflegen und Aufnahme, Bernstein nur für die Tür. Runde 76-dp-Tasten, Steuertasten 72 dp hoch mit 22 dp Radius.</span></div></div></div>''', 1280, 844)


BOARDS = [
    ("Main.dc.html", "Start", start, 0, 0),
    ("Verlauf.dc.html", "Verlauf", verlauf, 1, 0),
    ("Waehlen.dc.html", "Wählen", waehlen, 2, 0),
    ("Kontakte.dc.html", "Kontakte", kontakte, 3, 0),
    ("TuerKlingelt.dc.html", "Tür klingelt (gesperrt)", door_ring, 0, 1),
    ("TuerGespraech.dc.html", "Türgespräch", door_call, 1, 1),
    ("ZweiLeitungen.dc.html", "Zwei Leitungen", two_lines, 2, 1),
    ("Mehr.dc.html", "Mehr im Gespräch", more_sheet, 3, 1),
    ("Status.dc.html", "Status und Klingeln", status_sheet, 0, 2),
    ("Erreichbarkeit.dc.html", "Erreichbarkeit", reach, 1, 2),
    ("DesignSystem.dc.html", "Design-System", system, 2, 2),
]

ROW_Y = [0, 844 + 400, 2 * (844 + 400)]
boards, order = {}, []
for fname, title, fn, col, row in BOARDS:
    (OUT / fname).write_text(fn())
    w = 1280 if fname == "DesignSystem.dc.html" else W
    boards[fname] = {"x": col * (W + 80), "y": ROW_Y[row], "w": w, "h": H, "title": title}
    order.append(fname)

notes = {
    "t1": {"x": 0, "y": -300, "text": "Alltag: Start, Verlauf, Wählen, Kontakte", "kind": "title1", "maxW": 1800},
    "t2": {"x": 0, "y": ROW_Y[1] - 300, "text": "Anrufe: Tür, Gespräch, zwei Leitungen", "kind": "title1", "maxW": 1800},
    "t3": {"x": 0, "y": ROW_Y[2] - 300, "text": "Ich, Erreichbarkeit, Design-System", "kind": "title1", "maxW": 1800},
}
canvas = {"v": 3, "createdOnFiles": {"v": 1, "at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")},
          "title": "HA-Phone App Redesign", "launch": {"view": "canvas"}, "pages": [], "boards": boards,
          "order": order, "notes": notes, "designSystems": []}
(OUT / "canvas.json").write_text(json.dumps(canvas, ensure_ascii=False, indent=1))
print("ok", len(boards))
