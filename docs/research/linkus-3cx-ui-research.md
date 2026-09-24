# Linkus Mobile vs. 3CX Mobile: UI/UX Research for the HA-Phone Redesign

Research date: 2026-09-24. Method: web only (official docs, vendor blogs and release notes, Google Play and App Store listings, and a scrape of recent store reviews). No devices or emulators were used.

**How confident each kind of claim is:**
- **Verified**: taken from official docs, release notes or official screenshots. The URL is given inline.
- **Sampled**: colours measured from official PNG/JPEG screenshots. They are approximate (±4 per channel, JPEG artefacts) and are not published brand tokens.
- **Uncertain**: marked *(uncertain)*. Usually this means no primary source was found, or the only screenshot was old marketing material.

**Review corpus (scraped 2026-09-24 with `google-play-scraper`; the newest ~500 per locale for en-US, en-GB and de-DE, deduplicated):**

| Store | Linkus (`com.yeastar.linkus`) | 3CX (`com.tcx.sipphone14`) |
|---|---|---|
| Google Play rating | **3.70**, 1,852 ratings, 500k+ installs, v5.30.4 (Sep 2026) | **2.58**, 7,088 ratings, 1M+ installs, v20.7.0 (Jun 2026) |
| Play histogram 1-5★ | 324 / 194 / 194 / 129 / 1007 | 3253 / 985 / 276 / 561 / 1981 (46% are 1★) |
| App Store (US) | 3.74 (34 ratings), v5.30.6 | 2.63 (321 ratings), v20.0.22 |
| Reviews analysed | 325 (82 since 2024) | 829 (348 since 2024) |
| Mean score of reviews since 2025 | 2.4 (45% 1★) | 2.3 (48% 1★) |

Sources: [Linkus on Play](https://play.google.com/store/apps/details?id=com.yeastar.linkus), [3CX on Play](https://play.google.com/store/apps/details?id=com.tcx.sipphone14), [3CX on the App Store](https://apps.apple.com/us/app/3cx/id992045982). Linkus iOS reviews came from the Apple RSS feed (id 1158760574). The 3CX iOS RSS feed returned nothing, so 3CX iOS reviews come from the App Store web page only.

---

## 1. Yeastar Linkus Mobile Client (P-Series, v5.2x–5.30, 2025–2026)

### 1.1 Information architecture

- **Bottom navigation, current version (since v5.29.12 on Android, 2026-08-25):** up to **4 main tabs plus "More"**. The defaults are **Calls · Dialpad · Directory · Chat**. The **More** tab holds Conference, Voicemail and Recordings.
  - Users can reorder tabs by drag-and-drop. They can also promote sub-features such as Voicemail or Recordings (normally under Calls or Directory) to their own tab. There is a Reset option.
  - **Dialpad is pinned**: it cannot be moved into More.
  - Sources: [Customize Navigation Bar](https://help.yeastar.com/en/p-series-linkus-cloud-edition/mobile-client-user-guide/customize-navigation-bar.html), [Android release notes](https://help.yeastar.com/en/p-series-linkus-cloud-edition/release-notes/release-notes-for-linkus-android.html), [P-Series V25.2 GA blog](https://www.yeastar.com/blog/p-series-v252-final/).
- **Earlier layout (until v5.27, June 2026):** Calls · Directory · Chat · Conference, with the **dialpad as a floating button** over the Calls list (see the [Play screenshot](https://play.google.com/store/apps/details?id=com.yeastar.linkus) "Call History" and the quick-start images). v5.27.12 "moved the dialpad from a floating icon to a standalone menu".
  - A user review from 2026-07-18: *"Latest UI change is a straight up downgrade, at least let people choose what the default menu should be"*. The customisation in 5.29 looks like the response.
- **Top bar on every root tab:** your own avatar with a presence badge (top-left) opens the **Account** sheet. The title sits in the centre. Search and add (or new chat) sit on the right. A function-keys (BLF) panel icon sits top-right ([Function Keys](https://help.yeastar.com/en/p-series-linkus-cloud-edition/mobile-client-user-guide/use-function-keys-on-linkus-mobile-client.html)).
- **Account sheet** (iOS-26-style card list with coloured rounded-square icons):
  - Current Presence (with status value)
  - Agent Status
  - Personal Information
  - Account Management
  - QR Code Login
  - Play Ringtone (toggle)
  - Stop Push Notifications (toggle)
  - Monitor Call Quality
  - Help & Feedback
  - Settings
  - Source: screenshot in [Configure Call Panel Type](https://help.yeastar.com/en/p-series-linkus-cloud-edition/mobile-client-user-guide/configure-call-panel-type.html).
- **Settings:** Password Management · New Message Alerts · Audio Options · Advanced · AI · Select a Theme · Call Panel Type · About.

### 1.2 Screen by screen

| Area | What Linkus does |
|---|---|
| **Dialpad** | Classic 3×4 keypad with letters, a "Number" placeholder and a round blue call button. In the old layout it opened from a floating button over the call log as a bottom sheet (Play screenshot). It is a pinned tab since 5.27/5.29. Outbound caller ID (DOD) can be picked per call ([select DOD](https://help.yeastar.com/en/p-series-linkus-cloud-edition/mobile-client-user-guide/select-outbound-caller-id-dod-to-call.html)). |
| **Directory** | A segmented control: **Extensions / Phone (native contacts) / Contacts (PBX: Company + Personal)**. A group dropdown sits top-left (e.g. `Default_All_Extensions`, `Favorite Contacts`). Each row shows an avatar with a **presence badge (small glyph icon at the bottom-right)**, the name, and the status in brackets, e.g. `[Available]`. The A-Z index was **removed in 5.29** "to display more entries". Favourites are set with a star on the contact detail page ([favorites](https://help.yeastar.com/en/p-series-linkus-cloud-edition/mobile-client-user-guide/mark-or-remove-favorite-contacts.html)). Search is fuzzy: it ignores symbols, matches numbers, and searches remarks and CRM in real time (release notes 5.10, 5.13, 5.20). A native-contact detail offers "Dial through PBX and Select Prefix" or "Dial through Mobile". Any field can be copied with a long press (5.29). |
| **Calls (history)** | A segmented control: **Call Logs / Voicemail / Recordings**. There is a filter dropdown ("All ▾") and a "Remove" (trash) action. Each row has an avatar with a presence badge, the name, the type ("Extension"), the time and an **(i)** info icon. **Missed calls show the name in red.** Detail pages show the company name. Call notes and call-quality reports attach to log entries. Queue managers can see and delete missed queue calls. |
| **Voicemail** | Inline player card: name, number, timestamp (duration), a scrubber and a round blue play/pause button, plus a **"Callback" text link**. Unread items get a red dot. There is a read/unread filter, and a long press offers Read/Unread, Forward (to extensions) and Delete. AI transcription is editable. A tab badge shows the unread count ([voicemails](https://help.yeastar.com/en/p-series-linkus-cloud-edition/mobile-client-user-guide/check-and-manage-voicemails.html)). |
| **Incoming call** | Full-screen call UI when the OS allows it, otherwise a push-notification answer. It shows the **company name** (5.29) and a **"From AI Receptionist" tag** that opens AI Insights (transcript and summary) (5.26). A **Send to Voicemail** button appears only if voicemail is enabled (5.28). Distinctive ringtones can be set per call source ([ringtones](https://help.yeastar.com/en/p-series-linkus-cloud-edition/mobile-client-user-guide/set-ringtones-for-incoming-calls.html)). **The release notes are full of fixes to the lock-screen and push path** (see §1.4). |
| **In-call** | A **full-bleed blurred avatar background**, then avatar, name, extension and timer in the centre. Top-left has a minimise icon; top-right has **(i)** (contact details during the call, 5.29). The bottom has a **collapsible panel (chevron) of round translucent buttons in 4 columns**:<br>• Row 1: Hold, Mute, Speaker, **End Call (red)**<br>• Row 2: Add Participant, Video, Dialpad, Record<br>• Row 3: Attended, Blind, **Call Flip**, plus **Park** since 5.21.<br>When collapsed, only one row is shown (Hold, Mute, Handset/Earpiece, End Call) and an "AI Transcription" toggle chip appears above it. A recording indicator shows while recording (5.27). **Call Panel Type** (5.27) chooses between **"Top"** (End Call in the top-right cell of the grid) and **"Center"** (End Call centred under the grid). Sources: [quick-start images](https://help.yeastar.com/en/p-series-linkus-cloud-edition/mobile-client-user-guide/linkus-mobile-client-quick-start-guide.html), [call panel](https://help.yeastar.com/en/p-series-linkus-cloud-edition/mobile-client-user-guide/configure-call-panel-type.html). |
| **Call waiting / 2nd line / transfer / conference** | Call waiting plays **two short beeps** (5.21). There are separate **Attended** and **Blind** transfer buttons, so transfer is one level shallower than in 3CX. "Add Participant" upgrades a call to a multi-party call (**up to 5 participants**). The conference screen shows a host row plus an avatar grid of participants with a "+N more" tile. The Conference module (bridge rooms) lives in More. |
| **Call Flip / Call Switch** | **Flip**: tap the button during a call and choose a target device (desk phone or another Linkus). **Switch**: a banner reading "Touch here to start call switch" pulls a call from another device onto the mobile ([flip](https://help.yeastar.com/en/p-series-linkus-cloud-edition/mobile-client-user-guide/flip-an-active-call-between-devices.html), [switch](https://help.yeastar.com/en/p-series-linkus-cloud-edition/mobile-client-user-guide/continue-an-active-call-on-linkus-mobile-client.html)). |
| **Presence** | Tap your own avatar, then **Current Presence**. Defaults: **Available, Away, Business Trip, Do Not Disturb, Lunch Break, Off Work**, each with its own **forwarding rules** and an "accept ring-group calls" option. There is a **temporary presence** with a duration or an end date/time (5.19), and presence can switch automatically by business hours. Admins can add custom statuses with custom icons (June 2025). MS Teams presence can sync. Sources: [manual switch](https://help.yeastar.com/en/p-series-linkus-cloud-edition/mobile-client-user-guide/manually-switch-presence-status.html), [P-Series June 2025](https://www.yeastar.com/blog/p-series-jun-2025-update/). |
| **Settings** | See §1.1. Theme is **System / Light / Dark** (5.14; **on Android the app must be restarted**) ([theme](https://help.yeastar.com/en/p-series-linkus-cloud-edition/mobile-client-user-guide/configure-theme-settings.html)). Auto-answer covers paging/intercom and non-paging calls. Codec order and ICE are configurable. |
| **Onboarding** | Four ways in: **QR code** from the welcome email (valid 24 h, single use), a **login link** (the app detects it on the clipboard: "…information detected. Do you want…account?"), manual login (SN/domain; the last 3 are remembered since 5.29), or SSO (Microsoft, Google, AD) or extension-number login. |
| **Notifications** | Push-based. Badge counters cover missed calls, chats and voicemail. There is a "Poor Network Connection" toast (interval raised from 15 s to 30 s in 5.28). |
| **Widgets** | *None found* in the docs for Android *(uncertain)*. |
| **Car** | **Apple CarPlay** on iOS (June 2025). Android Auto for Linkus: *not found (uncertain)*. |

### 1.3 Visual language (Linkus)

- **Style**: light and airy, "enterprise iOS". The recent help-centre screenshots (2026) show an **iOS 26 / Liquid-Glass look**: pill-shaped "Done" buttons, a round back button, grouped white cards on a light grey background, and settings rows with **coloured rounded-square glyph icons** (green, yellow, blue, orange) like iOS Settings. Android appears to follow the same design *(the 2026 screenshots are iPhone ones; Android parity is likely but not confirmed)*.
- **Colours** (sampled):

  | Element | Colour |
  |---|---|
  | Primary blue: call FAB, play button | **#006CC0** (older) / **#0B7FCC** |
  | Selection accent in 2026 screens | **#2C6CB8** |
  | Background | #F2F2F2–#F4F4F4 |
  | Cards | #FFFFFF |
  | Segmented control track | #EDEDED |
  | End call red | **#E04C44** |
  | Presence "Available" green | ≈ **#1EBA60** |
  | Missed-call name | dark red, approximately #C62828 *(JPEG-blurred)* |
  | Marketing gradient | #2A7EDE → #3084DE |
  | Dark in-call / conference surfaces | #384959 / #435665 (slate) |

- **Typography**: system font (SF Pro or Roboto). The 2026 screens use bold titles ("Call Panel Type", "Custom Menu"). Presence text sits in brackets in grey.
- **Iconography**: thin outline icons for in-call actions; filled circle glyphs for presence (check, clock, plane, minus, cloche, exit arrow).
- **Buttons**: in-call actions are **circles**, translucent white on the blurred background. End call is a red circle. The 2026 design uses pills and circles throughout.
- **Density**: medium. There are about 7 contacts per screen at 720 × 1280.
- **Avatars**: circular photo avatars; initials on a blue circle when there is no photo (e.g. a blue "1" for extension 1002).
- **Motion, haptics, empty states**: not documented. The empty states in screenshots are plain grey space with small "No more data" text *(uncertain)*.

### 1.4 What users love and hate (Linkus)

**Love** (roughly 17 positive reviews since 2024, versus about 60 negative):
- The feature depth and the PBX integration: *"Overall functionality is 10/10"* (Dec 2025), *"Eine komplexe TK in einer APP"*.
- It "works brilliantly paired with the right provider". Admins who use the Yeastar tunnel/FQDN report no issues (App Store DE, 2026-07).
- Support quality is praised in older reviews.

**Hate** (counts are keyword hits in the 325 reviews, for scale only):
1. **Incoming calls are late or never ring when the app is in the background or the phone is locked.** About 20 hits for push/background/ring issues and 8 lock-screen hits since 2024. Examples:
   - *"Calls are handled as notifications, not call events… The call ends before the 'notification' to answer it comes through"* (2026-05).
   - *"klingelt die App deutlich später als das Tischtelefon"* (2026-08).
   - *"won't answer an incoming phone call if the lock screen is locked"* (2025-09).
   - Xiaomi/HyperOS shows only a small pop-up instead of full screen (2025-05).
2. **Audio quality and drops**: 27 negative hits. Complaints include G.729 as the default on iOS and "sounds like a large empty room".
3. **The app hijacks audio**: music does not resume, the car media player stays locked, Bluetooth headsets cannot play music, and the ringer cannot be silenced with the volume keys (18 hits).
4. **Presence/DND does not stick**: *"won't save 'current presence'"*, *"drops preferences so it turns off 'off work' or 'do not disturb'"*.
5. **"Connecting to server…"** after updates, and freezes (12 hits since 2024).
6. **UI and accessibility**:
   - *"You can't make the font bigger… You can't personalize the tabs… The texting box doesn't change size"* (2026-06).
   - *"a bit clunky for mobile"*.
   - The Galaxy Fold 8 crashes on rotation and *"when unfolded everything is enormous"* (2026-09).
   - *"as you click the phone icon to answer again it sometimes changes to the icon that puts the phone down"* (answer and decline targets are too close or shift position).
7. **Ghost ringing**: the app keeps ringing after the call was answered elsewhere (*4, desk phone).

### 1.5 Weaknesses and gaps we can beat (Linkus)

- **The in-call grid is 12–13 buttons in 3–4 dense rows**, with transfer types exposed as separate top-level buttons. Having to ship a "Call Panel Type" setting shows the default layout didn't work for everyone.
- **Presence is buried**: avatar, then Account, then Current Presence, then pick. There is no one-tap status on the main screens.
- **The tab churn** (floating dialpad, then a tab, then customisable) annoyed long-time users.
- **No large-font support** (reported by a user). Foldable and tablet layout is broken.
- **Changing the theme needs an app restart** on Android.
- **Background and lock-screen reliability** is the dominant complaint. Fix after fix in the release notes (Samsung, ViVo and Xiaomi special cases) suggests the Android Telecom and full-screen-intent path is fragile.
- **No door-station experience**: video calls exist, but there is no pre-answer video preview, no door-open action and no smart-home context.
- **No widgets or Quick-Settings tile** found for Android.

---

## 2. 3CX Mobile App (Android V5.x / "20.x", iOS 20.0.x, 2024–2026)

### 2.1 Information architecture

- **Bottom navigation: 6 tabs** — **Team · Contacts · Keypad · Recents · Chat · Voicemail**. Red count badges appear on Recents, Chat and Voicemail. The selected tab gets a shaded grey rectangle behind it (since May 2022: "Light theme users benefit from a shaded background to clearly indicate which tab").
  - The **tab bar stays visible during a call**; the in-call UI lives inside the Keypad tab.
  - Sources: screenshots in [Android call management blog (2023)](https://www.3cx.com/blog/releases/android-call-management/), [BLF blog (2025)](https://www.3cx.com/blog/releases/android-blf-status-control/), [queue blog (Sep 2026)](https://www.3cx.com/blog/releases/android-queue-management/), [refined experience](https://www.3cx.com/blog/releases/android-refined-experience/).
- **Top app bar**, left to right: hamburger, **3CX logo**, then a queue (headset) icon and a **solid square presence indicator** (for example green, meaning Available), plus a "Ready for calls" label on the keypad.
- **Hamburger drawer**:
  - A profile header (avatar, name, extension)
  - **Schedule**, **Meetings**, **Recordings**, **Settings**
  - **Silent**, **Keep active**
  - **Monitor Connection Quality**, **Scan QR Code**
  - **Help**, **About**
  - A **Boss-Secretary** toggle when configured
  - Sources: drawer screenshot in [Android Auto/AI blog](https://www.3cx.com/blog/releases/android-app-auto-support/), [Boss-Secretary](https://www.3cx.com/blog/releases/android-auto-boss-secretary-beta/).
- **Settings**: Accounts (add, edit or switch between multiple PBXs), **Advanced** (Car/Bluetooth support via the Telecom API, silence detection, battery optimisation, mic gain, ringtone), theme, Re-provision and Resend Credentials ([Android guide](https://www.3cx.com/user-manual/installation-android/)).

### 2.2 Screen by screen

| Area | What 3CX does |
|---|---|
| **Keypad** | A large 3×4 keypad on dark #121212. Above it: the dialled number or name plus **the callee's live presence** (e.g. "■ Business Trip") while dialling (2023). Below: a search magnifier on the left, a big **green round call button**, and backspace on the right. The **"Call using"** outbound-number picker (V5.8 beta, Sep 2026) is a popover: "Default route" or specific numbers. "Edit before call" sends a number from Recents or Contacts to the keypad. |
| **Team** | A list of colleagues. Each row: avatar with a **small square presence badge at the bottom-right**, name, "ext · status" (e.g. "004 On a call"), and **three inline actions (call, chat, overflow)**. A filter dropdown (All ▾ / **BLF** / favourites) switches to BLF mode: parking slots, status-change keys and queue login ([BLF](https://www.3cx.com/blog/releases/android-blf-status-control/)). Favourites are starred. Queue info (V5.8): logged-in and logged-out agents, and log agents in or out. |
| **Contacts** | Filters: Personal / Company / **Department** (2025) / CRM / M365 / Google / device. The contact card has separate **Call / SMS / Email** buttons, one row per number with a pencil icon ("edit before call") and chat, plus an edit FAB. Contacts can be added during a call ("Add Contact" label). Search handles diacritics (2026). |
| **Recents** | Rows: avatar, number or name, "via Queue/RingGroup · Heard by X", **a transcript or summary snippet**, time and duration, plus inline call and email/voicemail icons. Filters include **Abandoned** (V5.8). A long press or menu offers **Edit before call, Copy, Send SMS, Send Email, Quality Report, Delete**. |
| **Voicemail** | Its own tab with transcript snippets and shared queue/ring-group voicemail ("Via", "Heard by") (V5.4). |
| **Incoming call** | Android (AI screening screenshot, Nov 2025): grey background, initials avatar, "Call from", extension, name, then **an AI-generated caller summary** ("caller name…, reason…, tone & behaviour: calm"). **Answer (green circle) bottom-left, Decline (red circle) bottom-right, "Send to Voicemail" in the centre.** The **Telecom API is a manual opt-in** ("Car/Bluetooth support"); it was disabled on Pixel/Android 14 and re-enabled on Android 15. iOS uses **CallKit** (merge and transfer via CallKit fixed in 2026) and can be the default calling app on iOS 18.2+. |
| **In-call** | Large circular avatar, extension (big), name, "▮ 00:11 – Connected" with a quality-signal glyph (tap to start monitoring). A **3×3 grid of icon + label with no button containers**:<br>• Row 1: New call, Conference, Transfer<br>• Row 2: Earpiece/Speaker, Keypad, Video<br>• Row 3: Rec, Hold, Mute<br>A **big red hang-up circle** sits below, and the **6-tab bar is still visible**. A green **call badge bar** at the top appears when you leave the call screen. |
| **Multi-call** | A "Connected" header card with the active caller, then a **scrollable list of other calls** with state labels ("Incoming call", "On hold") and icons. Tap a row to swap calls (2023). **Conference**: Direct Add or **Consultative** (then Merge) (V5.4). The host can mute, redial or remove participants. **Transfer**: Blind or Attended (then "Join"). A 2025 user complaint: *"When transferring a call please show a list of people without me having to tap the magnifying glass"*. |
| **Presence** | Tap the square in the top-right. Options: **Available, Away, Do Not Disturb, Lunch, Business Trip**, and "Set Status Temporarily". A pencil icon edits the forwarding rules per status. A status can have "Accept push notifications" turned off. Queue status can change during a call (2025). New colours for Lunch and Business Trip came in May 2025. |
| **Onboarding** | **QR only in practice**: open the Web Client, tap the QR icon and scan (single provisioning attempt). Then permissions and battery-optimisation instructions. **Push subscriptions expire after 14 days offline** (raised from 7 in Sep 2026), after which a fresh QR is needed ([guide](https://www.3cx.com/user-manual/installation-android/)). |
| **Widgets and OS integration** | iOS: **Speed Dial widget** (Buddies, up to 20 contacts plus missed-call and message shortcuts; Cards, 10; List, 5), Siri, and Apple Watch notifications ([iOS guide](https://www.3cx.com/user-manual/installation-iphone/)). Android: **Android Auto** (Team, Contacts and Recents; up to 20 items; voice search) and Google Assistant. An Android home-screen widget: *not found (uncertain)*. Wear OS: users ask for it (2024 review), and none was found. |
| **Dark mode** | Theme choice in Settings. All 2023–2026 Android marketing and blog screenshots are **dark**. |

### 2.3 Visual language (3CX)

- **Style**: a **utilitarian, dense, dark "admin tool"**. Material-ish outline icons with labels. Almost no containers, no cards, no elevation. It is flat #121212 with #242424 separators and surfaces.
- **Colours** (sampled):

  | Element | Colour |
  |---|---|
  | Background | **#121212 / #101010** |
  | Surfaces | #242424, #303034 |
  | Call FAB green | ≈ **#74D470** |
  | Active-call badge bar | **#44985C** |
  | Hang-up / decline red | **#E84C3C** (older marketing: #FC3630) |
  | Presence square: Available | **#34B010** |
  | Presence square: Away | **#FCFC00** |
  | Presence square: DND | red |
  | Brand logo blue | ≈ #1E8ABA–#4E90BA |

- **Presence shape**: **squares, not dots**. The square is distinctive but reads as "legacy"; the 2022 blog says avatars and indicators are "always shown".
- **Typography**: Roboto. Numbers are large on the keypad and in-call. Lists use small 12–14 sp secondary text.
- **Density**: high. About 12 team rows per screen, each with 3 inline icon buttons, so tap targets are small.
- **Avatars**: circular photos, with initials on grey when there is no photo (CRM contacts got initials in 2026).
- **Motion, haptics, empty states**: not documented. The "Unified behaviour of all screens when no internet connection is available" line (2022) suggests an offline empty state *(uncertain)*.
- **Store presence**: the Play listing still uses **old iPhone-frame marketing screenshots** with the 6-tab layout. The brand never presents the app visually.

### 2.4 What users love and hate (3CX)

**Love** (about 64 positive-keyword hits since 2024, but ~48% of 2025+ reviews are 1★):
- *"Life changing untying from the office desk"*.
- Being reachable anywhere without giving out your personal number.
- Everything in one app (calls, chat, WhatsApp/SMS, voicemail).
- Some users say *"Works flawlessly"* and blame admin setup for the bad reviews.

**Hate** (keyword hits in 829 reviews; ≤2★ counts in brackets):
1. **QR-only onboarding: 56 hits (50 of them ≤2★).** Examples:
   - *"what about a person that only has 1 phone"* (2026-09).
   - *"the only way to add the extension is through the QR code but every time I try to scan it fails"*.
   - *"Option to use photo from a library is unavailable"*.
2. **Connection, registration and "update required" lockouts**: 39 hits since 2024. After app auto-updates it says *"Your server version is too old"*.
3. **Audio problems**: 66 negative hits. One-way audio (*"they cannot hear me"*), "sounds very far away", Wi-Fi to mobile handover, and "shows bad connection on 5G".
4. **Can't stop it ringing, and DND is ignored: 38 hits.** Examples:
   - *"when I'm in the office near my desk phone there's no way to turn it off"* (23 👍).
   - *"Es ist nicht möglich die App zu deaktivieren"*.
   - *"rings when DnD is on"*.
   - The app overrides notification settings.
   - *"gotta remember to change from available to ring mobile when I get to work every morning"*.
5. **Ghost ringing and vibration after answer: 24 hits.**
   - *"when I answer on the app… it keeps ringing and vibrating"* (2026-03, 13 👍).
   - The notification still shows an incoming call after hang-up.
   - The smartwatch keeps ringing.
6. **Bluetooth and audio routing: 38 hits.**
   - *"my entire phone audio output is stuck as call audio until I release all Bluetooth connections"*.
   - Swiping away a call keeps ALL device audio muted.
   - Galaxy Buds are not usable.
7. **Late ringing**: *"Calls always come very late, giving only 2 seconds to react"*. "Keep Active" fixes it but costs *"about 31% of my battery"* (2025-11, 10 👍).
8. **UI complaints**:
   - *"the interface is NOT user friendly… You can't even see a list of internal numbers when transferring"*.
   - Hitting the queue login/logout button with your face: *"no confirmation… unless I constantly check that it's blue"*.
   - *"The mute button is in a terrible spot. If you put the phone to your ear, you hit it alot"*.
   - *"Interface is archaic"*.
   - No font or colour options.
9. **The native call log is missing**: *"calls will not appear in my phone call log only within the app"* (2026-09). After an Android update the call-log permission could not be granted.
10. **Company name not shown** on calls (DE 2026-07). Missed calls don't produce Android notifications (2024-10).

### 2.5 Weaknesses and gaps we can beat (3CX)

- **Six tabs** plus a drawer plus top-bar icons give three navigation systems. Voicemail as a whole tab while Recordings hides in the drawer is inconsistent.
- **The in-call screen keeps the tab bar**, and all nine controls are equal-weight icons with no containers. Mute, Hold and Speaker aren't visually stronger than Video or Rec. The in-ear tap-risk is noted by users.
- **Transfer requires searching** because the picker isn't populated with favourites or presence first.
- **Presence as a square in the corner of a dark bar** is low-affordance. The queue toggle has no confirmation.
- **The dark-only aesthetic** in practice gives flat #121212 lists with no hierarchy.
- **Onboarding** is QR from a second screen or nothing.
- **"Stop ringing on this phone" isn't a first-class state.**
- **No door-station or intercom UX. No smart-home actions. No Android widget or tile.**

---

## 3. Side-by-side summary

| Dimension | Linkus | 3CX | Gap for HA-Phone |
|---|---|---|---|
| Tabs | 4 + More, customisable, Dialpad pinned | 6 fixed + drawer | 4 clear tabs, no drawer |
| Presence entry | Avatar → Account → Current Presence (3 taps) | Top-right square → list (2 taps) | 1 tap, visible status pill |
| In-call primary | 4-col grid of 12–13 circles in a collapsible panel | 3×3 labelled icons + big red button, tabs visible | 2×3 primary + "More" sheet, no tabs |
| Transfer | Separate Attended and Blind buttons | Transfer → Blind/Attended → search | Smart picker (favourites + presence first) |
| Call flip | Yes (Flip + Switch) | Not found *(uncertain)* | Yes, with device list |
| Onboarding | QR, link, manual, SSO | QR (practically only) | HA login / QR / manual / scan-from-image |
| Incoming extras | Company name, AI tag, send to VM | AI summary, send to VM | **Live door video, open door, HA context** |
| Theme | System/Light/Dark (restart on Android) | Theme setting, dark in practice | Material 3 dynamic plus brand, live switch |
| Accessibility | No large fonts (user report), foldable issues | No font options (user report) | Dynamic type to 200%, TalkBack labels |
| Widgets | None found | iOS speed dial only | Door + favourites widget, presence QS tile |
| Store rating | 3.70 Play | 2.58 Play | Reliability plus polish is the whole game |

---

## 4. Cross-cutting lessons from the reviews

1. **Reliability of ringing *is* the UX.** More than half of all negative reviews for both apps are about calls not ringing, ringing late, never stopping, or audio routing. No visual polish survives a missed call. The design must make **reachability state visible and self-diagnosable**.
2. **Users want an explicit "ring me here / don't ring me here" control.** Office versus home and work hours versus off hours come up again and again, and neither app makes this a first-class, one-tap, schedulable state.
3. **Audio etiquette**: release audio focus instantly, resume media, never trap Bluetooth, respect the volume keys, DND and smartwatch dismissal.
4. **Onboarding must not assume two screens.**
5. **Big-font users and foldables exist**, and both apps fail them.

---

## 5. Opportunities for HA-Phone (prioritised)

Legend: **P0** means must-have to feel better than both. **P1** is a strong differentiator. **P2** is polish or later.

### 5.1 Proposed tab structure (4 tabs, no hamburger)

```
[ Start ]  [ Verlauf ]  [ ( Wählen ) ]  [ Kontakte ]        top-left: own avatar + presence pill
                         raised centre                        top-right: search
```

1. **Start** (home): a live **door-station card** (last snapshot or live preview, "Tür öffnen" button); **favourites** as large tiles with presence rings and live "on a call" state; a **reachability pill** ("Klingelt auf diesem Handy ✓" or "Stumm bis 17:00"); and the latest unheard voicemail. Neither competitor has a home screen; both open on a list.
2. **Verlauf**: one unified timeline of calls, voicemail and recordings with **filter chips** (Alle · Verpasst · Voicemail · Aufnahmen · Tür). Missed and unheard items get a coloured leading bar plus a bold weight, not just red text. Swipe right to call back, left to delete or mark as heard.
3. **Wählen** (keypad): a raised centre destination. While typing it shows **inline matches with presence** (like the 3CX status-in-dialer, but better), and a line selector if 2 lines or accounts exist.
4. **Kontakte**: extensions and phone contacts **merged**, with source chips (Nebenstellen · Telefon · Favoriten) instead of 3 segmented sub-lists. Presence shows as a coloured ring or dot with a shape plus colour, so it is colour-blind safe.
- The **Account/Presence sheet** opens from the top-left avatar (a Linkus pattern, but the status is **also** shown as a tappable pill next to the avatar, so it takes 1 tap, not 3). Settings, recordings management and help live inside this sheet, so there is no drawer.
- **No tab customisation at first** (Linkus shows the churn cost). Instead ship good defaults and possibly one optional swap later (P2).

### 5.2 Design moves

| # | Pri | Move | Why (evidence) |
|---|---|---|---|
| 1 | P0 | **Door-station ringing moment**: a full-screen intent with **live video *before* answering** (muted). There are 3 large actions: **Annehmen** (audio), **Tür öffnen** (a slide or long press, never an accidental tap, with haptic confirmation), and **Ablehnen**. After the door opens, show a green "Tür geöffnet ✓" state and auto-hang-up after N seconds (configurable). | This is the signature feature; neither app has pre-answer video or door actions. |
| 2 | P0 | **The same moment on the lock screen**: a CallStyle notification with a **snapshot thumbnail** and an "Öffnen" action. The full-screen intent must work locked. Android 14+ requires the `USE_FULL_SCREEN_INTENT` special access, which is allowed by default for calling apps; the app should check it and guide the user. | Lock-screen answering is the #1 Linkus complaint theme and a major 3CX theme. |
| 3 | P0 | **Reachability centre ("Erreichbarkeit")**: a single screen, reachable from the Start pill, that checks notification permission, the full-screen-intent permission, battery optimisation, the registration/push state, the last successful wake-up, and the DND exception. Each item has a green or red status and a one-tap fix. Also run a "Test-Anruf an mich" self-test. | Most negative reviews in both apps are about ringing reliability, and users can't diagnose it themselves. |
| 4 | P0 | **"Klingeln auf diesem Handy" as a first-class toggle plus schedule**. This is separate from PBX presence: on, off, or "off until …". It is also available as a **Quick-Settings tile** and on the Start pill. It can optionally follow HA presence ("zu Hause / im Büro"). | 3CX: *"no way to turn it off"* (23 👍) and *"remember to change… every morning"*. Linkus: DND doesn't stick. |
| 5 | P0 | **In-call layout: 6 primary controls in a 2×3 grid of large tonal buttons** (**Stumm · Lautsprecher · Halten / Tastatur · Weiterleiten · Mehr**), plus a **separate, larger End button** centred at the bottom. "Mehr" opens a bottom sheet with Konferenz, Zweiter Anruf, Aufnahme, Call Flip, Parken and Video. **No tab bar in-call.** Door calls replace "Weiterleiten" with **Tür öffnen**. | Linkus has 12–13 equal circles, and 3CX has 9 equal icons plus tabs. Users hit Mute with their ear (3CX), and Linkus needed a layout setting. |
| 6 | P0 | **Honest ring state**: stop ringing and vibration instantly when the call is answered elsewhere, cancelled, or dismissed on the watch. Remove stale notifications on every call-state change. Never keep a "ghost" incoming UI. | 24 ghost-ringing hits for 3CX and 4 for Linkus; these reviews are very emotional. |
| 7 | P0 | **Audio etiquette**: request and abandon audio focus correctly, resume media, route to Bluetooth when it is connected and let the user pick in a clear output sheet (Earpiece, Speaker, device names), let the volume-down key silence the ringer, and never mute device audio after a dismissed call. | 38 audio-routing hits (3CX) and 18 (Linkus). |
| 8 | P0 | **Answer and decline safety**: large, well-separated targets (bottom-left and bottom-right, each ≥ 72 dp). The answer target must never change position between the ringing and connecting states. An optional swipe-to-answer on the lock screen. | Linkus: *"it sometimes changes to the icon that puts the phone down"*. |
| 9 | P0 | **Accessibility and large fonts**: support system font scale up to 200% with reflowing layouts (the keypad and in-call grid switch to stacked layouts). Minimum targets 48 dp, TalkBack labels on every icon, and presence shown by shape plus colour. Foldable and tablet two-pane layout (P1). | Linkus: *"You can't make the font bigger"*. 3CX: *"No option to change the font"*. Fold 8 is broken in Linkus. |
| 10 | P0 | **Onboarding without a second screen**: log in with HA (URL plus account) and auto-provision the extension from the add-on. Or scan a QR code **with camera or from an image/screenshot**, open a deep link, or enter details manually. After login, go straight to the reachability checklist (#3). | 3CX has 56 QR complaints. Linkus's login-link and clipboard detection is a good pattern to copy. |
| 11 | P1 | **Smart transfer and second-line picker**: open with favourites plus colleagues sorted by presence (available first, "on a call" dimmed), with a search field focused but not required. Show a big **"Verbinden" (attended)** button and a smaller "Direkt" (blind) button. Use the same picker for conference add. | 3CX: *"show a list of people without me having to tap the magnifying glass"*. Linkus exposes 2 transfer buttons at the top level. |
| 12 | P1 | **Two-line UI as stacked call cards**: the active call is a large card, and the held call is a compact card above it with a "Tauschen" swap chip. "Zusammenführen" appears only when 2 calls exist. Show a persistent **green active-call pill** at the top when the user leaves the call screen (3CX call badge, improved). | 3CX's multi-call list is good but visually flat. Neither app makes swap and merge obvious. |
| 13 | P1 | **Call Flip as a clear sheet**: "Gespräch übergeben an…" lists the other registered devices with icons (desk phone, PC, tablet). Show a pulsing state until the target answers, plus a "Zurückholen" option. Also offer the reverse ("Gespräch hierher holen") as a banner on Start when another device has an active call. | Linkus has Flip and Switch, but they are buried among 12 buttons. |
| 14 | P1 | **Presence that feels live**: animated presence rings on avatars (a subtle pulse while ringing, and a solid ring for "on a call"). Allow a one-tap status change from the Start pill. Offer a temporary status with an end time ("bis 14:00"), plus HA automations (for example, set DND when a calendar event starts). | Linkus has good temporary presence but takes 3 taps. 3CX shows presence as a legacy square. |
| 15 | P1 | **Home Assistant context on calls**: on an incoming door call show the doorbell snapshot. On internal calls show the caller's room or area when known. During door calls show 1–3 configurable HA action chips (Licht an, Tor öffnen). | No competitor can do this; it defines the category. |
| 16 | P1 | **Voicemail like messages**: an inline waveform player, 1×/1.5×/2× speed, and a transcript preview when available (the add-on could use HA STT). Actions: "Zurückrufen", "Als gehört", share. Show an unheard count on the Verlauf tab and on the Start card. | Linkus's inline player plus "Callback" is good. 3CX transcript snippets in Recents are good. Combine and polish them. |
| 17 | P1 | **Recording UX**: a clear red "REC" chip with a timer in the in-call header while recording (Linkus added an indicator only in 2026). Recordings sit in Verlauf under a filter chip. | Legal clarity and trust. |
| 18 | P1 | **Forwarding as a visual rule card**: "Wenn ich nicht rangehe → nach 20 s → Handy / Voicemail". This can be edited inline from the presence sheet, and the current forwarding state shows as a subtle banner on Start. | Both apps tie forwarding to per-status settings screens that users can't find. |
| 19 | P1 | **Widgets and tiles**: a home-screen widget (Door snapshot + "Öffnen" + 4 favourites), a Quick-Settings tile ("Klingeln an/aus" or presence), and app shortcuts (long-press icon: "Tür", "Voicemail", "Favorit X"). | 3CX has an iOS-only speed-dial widget. Linkus has none found. |
| 20 | P1 | **Visual language**: see the list below this table. | Positions HA-Phone between Linkus's polish and 3CX's density, with better hierarchy than either. |
| 21 | P1 | **Native call-log integration (optional)** and caller-ID lookup against phone contacts plus PBX/HA contacts, with company name shown. | 3CX: *"calls will not appear in my phone call log"*. DE: *"zeigt den Firmennamen nicht an"*. |
| 22 | P2 | **Empty states with purpose**: "Noch keine Voicemails 🎉", "Keine Favoriten — tippe ☆ bei einem Kontakt", and a **door-station setup card** on Start if none is configured. | Both apps show blank grey space. |
| 23 | P2 | **Haptics vocabulary**: a light tick on keypad presses, a medium tap on answer or hang-up, and a distinct double pulse on "Tür geöffnet". Plus a subtle ring-pulse animation. | Unspecified in both apps, and cheap delight. |
| 24 | P2 | **Car**: Android Auto calling templates (Favourites, Recents, Contacts), following the 3CX V5.4 structure. | 3CX added Android Auto (Nov 2025). Linkus has CarPlay on iOS. |
| 25 | P2 | **Wear OS**: an answer, decline and door-open complication. | Requested for 3CX (2024), and nobody has it on Android. |

**Visual language for move #20:**
- Material 3 with an optional **dynamic colour** mode, but a **fixed brand accent** for call semantics:
  - Answer green ≈ #2E7D32–#34C759
  - End red ≈ #E5484D
  - Door action teal or amber, so it is never confused with answer or decline
- Tonal buttons with a 16–20 dp radius; End as a circle (72 dp).
- Presence as a **ring plus a shape glyph**:
  - ✓ Available
  - ☾ Away
  - ⊖ DND
  - ● On a call
- True-dark theme with elevated surfaces, not flat #121212 lists. **Live theme switching** with no restart.

### 5.3 Signature moments (what reviewers should screenshot)

1. **"Es klingelt an der Tür"**: the phone lights up, live video fills the top two thirds, the name "Haustür" and time sit on the video, three big actions sit below, and a success animation plays when the door opens. On the lock screen it works the same, starting from the snapshot.
2. **One-tap reachability**: the Start pill reads "Klingelt hier ✓ · Verfügbar". One tap opens status, a ring toggle and forwarding in a single sheet.
3. **Clean in-call**: 6 big controls, nothing else, and a "Mehr" sheet for power features. During a door call, "Tür öffnen" is right there.
4. **Call Flip in two taps**: "Übergeben → Tischtelefon Büro", then "Gespräch läuft jetzt am Tischtelefon".
5. **Self-healing setup**: the reachability checklist turns every item green after onboarding, and a test call proves it.

### 5.4 Things to explicitly *not* copy

- The 3CX hamburger drawer plus 6 tabs, and a tab bar during calls.
- Linkus's 12-button equal-weight grid and its "Call Panel Type" setting as a crutch.
- Presence hidden behind the avatar (Linkus) or shown as a tiny square (3CX).
- QR-only provisioning, and push that silently expires. 3CX has a 14-day lifetime; if HA-Phone has similar limits, surface them in the reachability centre.
- Requiring an app restart for a theme change.

---

## 6. Open questions and uncertainties

- The current 3CX **Android** screenshots in blogs are 2023–2026 but partial. No full 2026 screen set exists; the Play listing screenshots are outdated iPhone mock-ups.
- Linkus 2026 help screenshots are iPhone (iOS 26). Android visual parity is assumed.
- Whether 3CX Android has call flip or pull: not found.
- Linkus Android Auto support: not found.
- Android home-screen widgets for either app: not found.
- Hex values are sampled, not official tokens.
- Review counts are keyword-based over the newest ~500 reviews per locale, so they show relative weight, not exact frequencies.
