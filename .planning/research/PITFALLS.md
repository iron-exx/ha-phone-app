# Pitfalls Research

**Domain:** Native VoIP softphone companion app (iOS PushKit/CallKit + Android FCM/Telecom) backed by self-hosted Asterisk PBX, with door-station video preview
**Researched:** 2026-07-31
**Confidence:** MEDIUM-HIGH (Apple/Google policy items verified against current developer docs and forums; OEM background-kill behavior is community-sourced and inherently a moving target)

## Critical Pitfalls

### Pitfall 1: Not reporting every VoIP push to CallKit synchronously — app termination and permanent token revocation

**What goes wrong:**
The app receives a PushKit VoIP push but doesn't call `reportNewIncomingCall` synchronously and unconditionally inside `pushRegistry(_:didReceiveIncomingPushWith:for:completion:)`. Common causes: doing an async network round-trip to HA-Phone *before* reporting the call, silently swallowing a push that arrives after the call was already cancelled server-side, or a code path where the push payload is malformed and no CallKit call gets reported at all. iOS logs "Killing VoIP app because it failed to post an incoming call in time" and kills the app. On the *second* offense, iOS (SDK targeting iOS 26 confirmed, behavior present since iOS 13) revokes the VoIP push token entirely until the user reinstalls the app — silently breaking all future incoming calls with no warning to the user.

**Why it happens:**
Developers try to "check with the server first" (e.g., is the call still valid, did it already ring on another device) before showing UI, or they add error-handling branches that return early without calling CallKit. Apple's API contract is unconditional: every VoIP push == one `reportNewIncomingCall`, full stop, even if you plan to immediately end it.

**How to avoid:**
- Design the "every push has a CallKit report" invariant into the app's push handler from day one — never conditionally skip it, including for expired/stale/duplicate/cancel pushes. For a cancel push, report the call and then immediately end it via CallKit (`CXEndCallAction`) rather than not reporting at all.
- Do the HA-Phone status fetch / SIP registration *after* `reportNewIncomingCall` returns, never before.
- Add a hard timeout guard (e.g., 2s) so a slow/failed HA-Phone lookup can't block the CallKit report.
- Treat "second offense = permanent token revocation until reinstall" as a release-blocking regression class; add a synthetic test that fires a malformed/edge-case VoIP push in CI/manual QA before every release.

**Warning signs:** Console logs "Killing VoIP app...failed to post an incoming call", `NSInternalInconsistencyException` around CallKit, users reporting the app "just stopped ringing" until reinstall.

**Phase to address:** Phase 1 (Push-Wakeup / Prototype) — this is the very first thing to get right; also needs an explicit regression test in Phase 6 (Stabilisierung).

---

### Pitfall 2: Assuming Android battery optimization exemption = reliable delivery on Samsung/Xiaomi/Huawei/OnePlus

**What goes wrong:**
Team implements `IGNORE_BATTERY_OPTIMIZATIONS` and high-priority FCM, tests fine on a Pixel/AOSP emulator, ships, then gets reports of missed calls specifically from Samsung, Xiaomi (MIUI), Huawei/Honor (EMUI/HarmonyOS, no Google Play Services at all on newer Huawei devices), OnePlus (OxygenOS/ColorOS), and Vivo/Oppo users — often "worked yesterday, stopped after a phone reboot" or "stopped after not opening the app for 2-3 days."

**Why it happens:** OEMs layer their own power-management daemons on top of stock AOSP/Doze that are *not* controlled by the standard Android `PowerManager` battery-optimization API:
- **Xiaomi (MIUI):** separate "Autostart" permission list, resets autostart grants after OTA/system updates; aggressive background-service killing independent of Doze whitelist.
- **Samsung:** kills apps with no foreground activity after ~3 days idle ("Sleeping/Deep sleeping apps" bucket), separate from Android's own App Standby.
- **Huawei/Honor:** PowerGenie flags apps that call `setAlarmClock()`/wake the system too often (~3×/day threshold observed) as "frequently wakes system"; `HwPFWService` kills apps holding wakelocks >~60 min with non-whitelisted tags. Newer Huawei devices lack Google Play Services/FCM entirely (HMS Push Kit required as a separate integration if that market matters).
- **OnePlus/Oppo/Vivo:** similar vendor-specific "Battery Manager"/"Sleep standby optimization" per-app kill lists.
Standard Android's battery-optimization whitelist API has zero effect on any of these vendor layers.

**How to avoid:**
- Do not rely on `IGNORE_BATTERY_OPTIMIZATIONS` alone. Detect OEM via `Build.MANUFACTURER` and deep-link the user, during onboarding/QR-provisioning, to the vendor-specific autostart/battery settings screen (community-maintained intent lists exist, e.g. via the "Don't kill my app" project's documented intents) with an explicit "why this matters" explanation.
- Build the diagnostic status page (already planned in Kapitel 14) to actively re-check OEM allowlist state (where a check is possible) and surface a clear warning if the app appears to be restricted.
- Use a real high-priority FCM data message *plus* a foreground service with the `phoneCall` foreground-service type immediately on receipt, so the OS sees genuine, visible, time-critical activity rather than a silent background wake — this is the behavior least likely to be killed across OEMs.
- Include OEM-specific real-device testing (not just emulators/Pixel) as an explicit release gate — this is called out in the plan's own Kapitel 13 test matrix but must be tracked as a recurring regression risk, not a one-time test, since OEM firmware updates change behavior over time (a MIUI/EMUI update can silently break previously-working delivery).
- Document to end users (in-app) that 100% delivery cannot be guaranteed on heavily customized OEM skins — this is explicitly acknowledged already in Kapitel 6 of the plan, but it should also drive product decisions (e.g., prominent in-app OEM-specific setup guide, not just documentation).

**Warning signs:** Missed-call reports clustering by device manufacturer; "worked after reboot, stopped 2 days later" pattern; delivery works over WiFi/charging but not on battery/idle.

**Phase to address:** Phase 1 (must be proven across real OEM devices, not just one test phone) and explicitly revisited in Phase 6 (Stabilisierung/Langzeittests) with a fixed device matrix (at minimum: one Samsung, one Xiaomi, one Huawei/Honor if targeting that market, one Pixel/AOSP-close device).

---

### Pitfall 3: High-priority FCM data-only message gets silently downgraded by Google

**What goes wrong:** The app sends `data`-only FCM messages (no `notification` payload) at `priority: high` for the VoIP wake signal, intending to build the CallStyle notification itself in code. Google's delivery pipeline tracks, per app instance, whether high-priority messages actually result in a *visible, user-facing notification* within a short window. If they don't (e.g., a bug drops the notification, or the OS suppresses it because the app isn't set up as a calling app), FCM demotes future high-priority messages to normal priority for that installation — normal priority can be delayed arbitrarily (batched, deferred until device is active) or routed through Play Services proxying, both of which break "ring within 1-2 seconds" expectations. This determination uses a rolling ~7-day window per app instance and is silent — there's no error returned to the sending server.

**Why it happens:** Developers don't realize this is being tracked at all, since sending the FCM message always "succeeds" from the server's point of view (HTTP 200 from FCM) even when the client-side outcome is a suppressed/no-op notification.

**How to avoid:**
- Every FCM data message that represents an incoming call must deterministically result in the app showing a real, user-visible notification (CallStyle notification + full-screen intent) within the `onMessageReceived` handler — treat this as a hard invariant, exactly parallel to the iOS CallKit rule.
- Never let error paths (SIP lookup fails, malformed payload, call already ended) skip showing a notification — show a "missed call" notification instead of nothing.
- Instrument delivery: log client-side receipt-to-notification-shown latency and success rate from real devices back to HA-Phone/the push relay, so degraded standing (if it happens) is detectable rather than silently discovered via user complaints.
- If migrating to Android 15+/API 35 behavior changes, revalidate — Google has tightened notification requirements incrementally; check current Firebase docs at implementation time, not just at planning time.

**Warning signs:** Growing delay between push send and app wake on a specific installation over time (starts fast, degrades over days); users on the same OEM/network reporting inconsistent ring timing.

**Phase to address:** Phase 1 (core Android push-wakeup logic) with an explicit rule: "no code path exists that receives a call-type FCM message without producing a visible notification."

---

### Pitfall 4: USE_FULL_SCREEN_INTENT default-deny surprise on Android 14+ and Play Console declaration gaps

**What goes wrong:** Since Android 14, `USE_FULL_SCREEN_INTENT` is only *auto-granted at install* to apps Google's Play Console review recognizes as calling or alarm apps (via a required Play Console declaration flow, enforced since May 2024, with a hard behavior cutover on **January 22, 2025**). Apps that skip the declaration, get rejected for default-enablement, or simply forget to handle the denied case will either (a) have the permission silently not granted and full-screen call UI never appears on lock screen — calls arrive as a normal heads-up notification instead — or (b) crash if the code assumes the permission is always present and calls the full-screen intent API without checking `NotificationManager.canUseFullScreenIntent()`.

**Why it happens:** Teams treat this as a one-time manifest permission the way older Android versions worked, not realizing Play Console now gates it behind an explicit declaration + review + possible runtime prompt flow that must be tested per Android version.

**How to avoid:**
- Complete the Play Console "Full-screen intent" declaration explicitly claiming calling functionality, before submitting the first release targeting Android 14+.
- At runtime, always check `canUseFullScreenIntent()` before launching a full-screen intent; if false, fall back gracefully to a high-priority heads-up CallStyle notification and surface an in-app prompt directing the user to the permission settings screen (`ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT`).
- Add this to the diagnostic status page (Kapitel 14) as an explicit checked item ("Full-screen calls: allowed/denied"), since this is exactly the kind of silent permission gap the diagnostics page is meant to catch.

**Warning signs:** Calls show as background notifications instead of full-screen UI specifically on Android 14+ devices; crash reports referencing full-screen intent on newer OS versions.

**Phase to address:** Phase 1 (native Android call UI) for baseline implementation; Phase 2/6 for Play Console declaration and release-gating checks.

---

### Pitfall 5: Leaking long-lived door-station camera/RTSP credentials or URLs via push payload

**What goes wrong:** For the Akuvox video-preview feature, a tempting shortcut is to put a direct RTSP URL (potentially including embedded credentials, e.g. `rtsp://user:pass@doorstation-ip/stream`) or a long-lived signed HTTPS snapshot/stream URL directly in the push payload so the app can immediately show video with no extra round-trip. Push payloads are logged by APNs/FCM infrastructure, can be inspected by anyone with device/notification access (even a locked device can surface notification previews), persist in OS notification history, and (on Android) may be visible to other apps with notification-listener permission. A leaked long-lived RTSP URL or credential effectively gives permanent access to a live camera feed on someone's front door.

**Why it happens:** It's the path of least engineering effort — skip a server round-trip, put the "final" resource URL right in the payload.

**How to avoid:**
- Push payload contains only: Call-ID, minimal caller/door-station metadata, "is door call" flag, and a signature — never a media URL or credentials (this matches Kapitel 10/11 of the plan's own design intent, so treat any deviation as a regression).
- The app fetches the actual preview stream URL/token from HA-Phone over an authenticated, already-established TLS session *after* waking, using the Call-ID from the push as a lookup key.
- Any stream token/URL issued by HA-Phone must be short-lived (seconds-to-low-minutes, scoped to the specific call), single-purpose, and invalidated the moment the call ends or is answered/declined — never a static per-device or per-door-station credential.
- Never allow RTSP with embedded plaintext credentials to reach the client at all; if RTSP is used internally between HA-Phone and the door station, the client-facing hop should always be WebRTC or a token-gated HTTPS/HLS proxy that HA-Phone brokers, not raw RTSP forwarded to the phone.
- Audit logging: never log full push payloads containing sensitive tokens; redact before persisting.

**Warning signs:** Any code path that constructs a push payload including `rtsp://`, `stream_url`, or credential fields; QA finds a stream still playable minutes/hours after a call ended.

**Phase to address:** Phase 5 (Türstationsmodus) for implementation, but the *architectural rule* ("push payload never contains media URLs/credentials") must be locked in as early as Phase 1's push payload schema design so it isn't retrofitted later.

---

### Pitfall 6: Push replay and call-hijack via unsigned or reused push events

**What goes wrong:** Without per-event signing and replay protection, a captured/leaked push payload (or a malicious HA-Phone-compatible sender, since this system explicitly supports third-party HA-Phone operators sending events to a shared relay) could be replayed to falsely trigger a ringing UI, spoof caller ID, or — worse — if any push-triggered action is trusted for door-opening — open a door without a genuine call. The plan already correctly identifies "a push must never by itself be able to take over a call or open a door" as a requirement; the pitfall is under-implementing this in practice (e.g., signing the push but not checking event freshness/expiry, or not verifying server-side call state before honoring an accept/open action).

**Why it happens:** Signing gets implemented for authentication but expiry/replay/state-check gets treated as a "nice to have" and deferred, especially under time pressure once the happy path works.

**How to avoid:**
- Every push event carries: unique event ID, Call-ID, short absolute expiry timestamp, and a signature from the relay (or from the originating HA-Phone box, verified by the relay) covering all fields.
- The app never trusts the push payload for the actual action (accept/open) — every user-initiated action (accept call, open door) triggers a fresh authenticated API call to HA-Phone, which independently verifies current call state before acting. The push is only ever a *wake signal + UI hint*, never an authorization.
- The relay (and HA-Phone) reject any event ID it has already processed (replay protection) and any event past its expiry window.
- Because the relay is shared across multiple independent HA-Phone installations (multi-tenant), each box's signing key/identity must be scoped so one operator cannot forge events for another operator's devices — this needs explicit design attention given the "also for other HA-Phone operators" requirement.

**Warning signs:** Any endpoint (`/api/calls/{callId}/accept`, `/door-open`) that doesn't re-verify server-side call/device state before acting; push payload fields used directly as authorization for a state change.

**Phase to address:** Phase 1-2 (push payload schema + relay design) for signing/expiry; Phase 5 for door-open action re-verification; this is a cross-cutting concern that should be part of the relay's core design, not bolted on later.

---

### Pitfall 7: NAT/TURN failures on WiFi↔cellular handoff mid-call or mid-registration

**What goes wrong:** A call is in progress (or SIP registration/ICE negotiation is underway) and the phone switches from WiFi to cellular (or vice versa) — common when walking away from the house, or when the OS proactively switches networks for power reasons. The local IP address changes, ICE candidates gathered for the old network become invalid, and without an active re-negotiation (ICE restart) the media path silently dies (one-way or no audio) even though the SIP dialog / app UI shows the call as "connected."

**Why it happens:** Initial implementations often only handle ICE/TURN gathering once at call setup and don't hook into Android/iOS network-change callbacks to trigger ICE restart; NAT rebinding on the new network path may also change the external mapped address the TURN/STUN server sees, invalidating previously negotiated candidates.

**How to avoid:**
- Explicitly implement ICE restart (new ICE ufrag/pwd, re-gather candidates, re-negotiate SDP over existing SIP dialog) triggered by OS network-change notifications (`NWPathMonitor` on iOS, `ConnectivityManager.NetworkCallback` on Android) — this is called out in the plan itself (Kapitel 8/13) but is one of the most commonly under-tested areas in home-grown SIP stacks.
- Always configure and test a real TURN server (not just STUN) since symmetric NAT / carrier-grade NAT (very common on cellular) will not work with pure host/STUN candidates — mobile-to-mobile or mobile-behind-CGNAT scenarios need TURN relay in practice, not just as a fallback.
- Prefer keeping the SIP TLS/registration transport resilient to brief network gaps (short registration expiry + fast re-register on network-available callback) rather than assuming a long-lived registration survives a network switch.
- Explicitly include "start call on WiFi, walk out of range mid-call" and "start call on cellular, arrive home and WiFi auto-connects" in the test matrix (already listed in Kapitel 13 — make sure it's actually exercised every release, not just once).

**Warning signs:** One-way audio or dropped RTP after a network-change log event; calls that show "connected" in UI but have no audio; works on WiFi-only test bench but fails on real-world roaming test.

**Phase to address:** Phase 3 (Produktionsfähige Audiotelefonie) per the plan's own phase ordering — but the underlying PJSIP/ICE configuration groundwork (real TURN, not just STUN) should be validated no later than Phase 1's prototype so it isn't a late surprise.

---

### Pitfall 8: RTSP-to-WebRTC/HTTP gateway and H.264 profile mismatches breaking door-station preview

**What goes wrong:** Door stations like Akuvox typically speak RTSP/ONVIF with H.264 encoded in a profile/level (often High Profile or a specific NAL packetization) chosen for LAN NVR consumption, not for mobile playback. When bridged through a gateway to WebRTC or an HTTP-based stream for the phone app, common failures include: codec/profile not supported by the mobile decoder (crash or black frame), SDP negotiation mismatches (missing SPS/PPS in-band vs out-of-band), excessive keyframe interval causing multi-second black screen before first frame ("time to first frame" pain, critical for a preview-before-answering feature), and gateway transcoding load spiking CPU on HA-Phone's host hardware if software transcoding is required for every concurrent preview.

**Why it happens:** Teams test the door-station stream once on a desktop VLC/browser (which tolerates almost any profile) and assume mobile playback will "just work"; mobile WebRTC/media stacks are much stricter about profile/level compliance and low-latency requirants.

**How to avoid:**
- Verify Akuvox's actual configured H.264 profile/level and keyframe interval early (Phase 5 groundwork can start earlier as a spike, since the hardware is already available per PROJECT.md) and configure the camera for a low-latency-friendly profile (Baseline/Main, short GOP/keyframe interval) rather than accepting NVR-oriented defaults.
- Prefer requesting an immediate keyframe from the camera when a preview session starts (many ONVIF/door-station APIs support this) rather than waiting for the next scheduled I-frame — this directly determines perceived "time to first frame."
- Design the gateway to avoid transcoding where possible (pass-through H.264 into WebRTC when profile is compatible) and only fall back to transcoding when necessary, since transcoding cost scales with concurrent door-calls and will not scale gracefully on typical Home-Assistant-add-on host hardware (often a Raspberry Pi or small NUC).
- Treat "time to first frame < ~1-2s" as an explicit acceptance criterion for the Türstationsmodus phase, not just "video eventually shows."
- Snapshot-first fallback (a single JPEG snapshot shown instantly, replaced by live stream once available) mitigates the worst-case "stream never starts in time" scenario and is cheap to implement — the plan already lists snapshot as an option; treat it as the default fast-path, not just an alternative.

**Warning signs:** Preview takes multiple seconds to show any image; black screen/decoder error on specific phone models; HA-Phone host CPU spikes when a door call triggers a preview.

**Phase to address:** Phase 5 (Türstationsmodus), but an early technical spike against the real Akuvox hardware (available now per PROJECT.md context) should happen well before Phase 5 to de-risk profile/gateway choices before committing to an architecture.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Skipping ICE restart on network change, relying on long call timeouts instead | Faster to ship basic call flow | Silent one-way-audio calls on real-world mobile roaming; hard-to-diagnose "call quality" complaints | Never beyond an internal prototype (Phase 1) |
| Putting stream URL/token directly in push payload "just for now" | Saves one round-trip, faster demo of video preview | Security hole (long-lived credential leak) that is easy to forget to remove before release | Never — not even in prototype, since payload schema decisions are hard to retrofit safely |
| Using STUN-only (no TURN) because it "works on my home network" | Simpler PBX-side setup | Breaks for a large fraction of real users behind symmetric/carrier-grade NAT (cellular is often CGNAT) | Never for anything beyond a same-LAN dev test |
| Deferring OEM-specific autostart/battery guidance to "later, once we see complaints" | Simpler onboarding UI initially | Missed-call complaints are hard to retroactively diagnose per-user and damage trust in a "reliable calling" product | Only acceptable for the very first internal prototype (Phase 1), must be in place before any external/beta users |
| Reusing one push-relay signing key across all HA-Phone tenant boxes | Simpler relay implementation | Compromise of one HA-Phone box can forge events for others; blocks safe key rotation per tenant | Never once "other operators" requirement is in scope (it already is) |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|-------------------|
| APNs (PushKit) | Treating VoIP push as "best effort" and adding conditional CallKit reporting | Unconditional `reportNewIncomingCall` on every VoIP push, synchronously, no exceptions |
| FCM | Sending high-priority data messages without guaranteeing a resulting visible notification every time | Every call-type message must deterministically produce a CallStyle/full-screen notification, with a fallback "missed call" notification on any error path |
| Google Play Console | Forgetting the USE_FULL_SCREEN_INTENT calling-app declaration before targeting Android 14+ | Complete the declaration pre-submission; runtime-check `canUseFullScreenIntent()` and degrade gracefully |
| Akuvox / ONVIF door stations | Assuming NVR-oriented H.264 profile/GOP settings work fine for mobile low-latency preview | Reconfigure camera for low-latency profile/short GOP; request immediate keyframe on preview start; snapshot-first fallback |
| TURN/STUN | Configuring STUN only, assuming direct P2P will usually work on mobile networks | Always provision and test TURN (ideally TURN-over-TLS) since cellular CGNAT is common |
| PJSIP/PJSUA2 | Bundling PJSIP without validating its documented CallKit/PushKit integration hooks match current iOS requirements before committing architecture | Prototype the PJSIP+CallKit+PushKit path first (Phase 1) before building provisioning/UI on top |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Server-side (HA-Phone) transcoding of every door-station preview stream | Host CPU spikes, preview lag, other services (Asterisk core) degrade | Prefer H.264 pass-through into WebRTC when camera profile allows; reserve transcoding as fallback | Breaks at >1-2 concurrent door previews on typical add-on host hardware (Pi/small NUC) |
| Holding SIP registration open indefinitely "just in case" instead of push-then-register | Battery drain, exactly the problem this architecture is meant to avoid | Register only after a genuine incoming/outgoing call event, then drop or minimize-keepalive after call ends | Becomes visible as battery complaints once beta users leave the app installed for days |
| Not rate-limiting/deduplicating "all devices ring" pushes when a subscriber has many devices | Push relay and APNs/FCM quota pressure as user's device count per extension grows | Fan-out with per-event dedup and immediate cancel-push once one device answers | Noticeable once a household has 3+ devices per extension, or across many multi-device HA-Phone tenants at relay scale |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Long-lived/static camera or RTSP URLs in push payloads | Permanent unauthorized access to a live front-door camera feed if payload is logged/leaked/viewed on a notification-listener app | Push carries only Call-ID/metadata; app fetches short-lived, call-scoped stream token from HA-Phone after waking (see Pitfall 5) |
| Unsigned or non-expiring push events | Replay attacks can fake incoming calls or attempt unauthorized door-open if the action is trusted from the push itself | Sign every event, include short expiry + unique event ID, verify server-side state before honoring any action (see Pitfall 6) |
| Shared push-relay signing identity across independent HA-Phone tenant boxes | One compromised box can forge events for other operators' devices | Per-tenant signing keys/identities at the relay, independently revocable |
| SIP credentials or provisioning tokens logged in plaintext (server or client logs) | Credential leak via log access, especially on a self-hosted, community-operated Home Assistant add-on where log access is common (support requests, forums) | Explicit redaction of secrets before any log write, on both HA-Phone and app sides; this is already a plan requirement (Kapitel 5/11) — enforce with automated log-scrubbing tests |
| Door-open action reachable without fresh authorization check | A stale/replayed request could open a door | Every door-open call independently re-verifies current call/device state server-side; require biometric/PIN confirmation client-side before sending the request (already planned in Kapitel 7) |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-------------------|
| No feedback when OS/OEM battery restrictions silently block calls | Users don't know why "sometimes calls don't ring" and lose trust | Active diagnostics page checking known restriction states per OEM, with actionable deep-links to fix settings |
| Full-screen intent permission silently denied on Android 14+ with no fallback UX | Calls degrade to a normal notification with no explanation, looks like a bug | Detect denial via `canUseFullScreenIntent()`, prompt user with a clear explanation and settings deep-link |
| Door-station preview shows a stale/frozen frame indefinitely if stream fails | User thinks camera is broken or an old visitor is still there | Timeout-and-fallback to snapshot or explicit "preview unavailable" state, never leave a stale frame displayed silently |
| Multi-device "all ring, first wins" without instant cancel on other devices | Other household members' phones keep ringing after call was already answered elsewhere, feels broken | Server-side immediate cancel-push fan-out on first accept, and client-side immediate CallKit/Telecom "end call" on cancel receipt |

## "Looks Done But Isn't" Checklist

- [ ] **iOS VoIP push handling:** Often missing coverage for edge-case pushes (expired call, malformed payload, duplicate) — verify every single code path in the PushKit delegate calls `reportNewIncomingCall`, including error branches.
- [ ] **Android call notifications:** Often missing the "no notification shown" error-path case — verify a fallback/missed-call notification exists for every failure branch in the FCM message handler, not just the happy path.
- [ ] **Full-screen intent:** Often missing the Android 14+ permission-denied fallback — verify `canUseFullScreenIntent()` is checked and a graceful degrade path exists, tested on a real Android 14/15 device.
- [ ] **Push payload security:** Often missing an audit that no stream URL, RTSP credential, or long-lived token ever appears in a push payload — verify by inspecting actual wire payloads sent to APNs/FCM, not just the code that constructs them.
- [ ] **NAT/TURN resilience:** Often missing real ICE-restart-on-network-change testing — verify with an actual WiFi→cellular handoff mid-call on a real device, not just a simulator/emulator.
- [ ] **OEM battery testing:** Often missing testing on non-Pixel, non-stock-AOSP devices — verify delivery on at least one Samsung and one Xiaomi/Huawei device after 24-48h of idle, not just immediately after install.
- [ ] **Push replay protection:** Often missing server-side dedup/expiry enforcement even when signing exists — verify a replayed push (same event ID resent) is rejected by the relay/HA-Phone, and an expired push is rejected even with a valid signature.
- [ ] **Door-station preview latency:** Often missing measurement of actual time-to-first-frame — verify with a stopwatch against real Akuvox hardware, not just "it eventually shows video."

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|-----------------|
| VoIP push token revoked after repeat CallKit-report failures | LOW (per-user) / HIGH (trust) | User must reinstall app to get a fresh token; fix the underlying reporting bug immediately, ship a hotfix, and proactively surface an in-app "reinstall required" diagnostic if the app can detect it has a dead token |
| FCM high-priority downgrade detected for an installation | MEDIUM | Fix the missing-notification code path; the 7-day rolling window means recovery is not instant — communicate expected delay to affected users during the observation window |
| Long-lived camera URL/credential already shipped in a push payload in a past release | HIGH | Immediately rotate all camera/door-station credentials, invalidate any previously issued long-lived tokens server-side, force-update the app to the fixed payload schema, audit push/notification logs for exposure |
| Missed calls traced to OEM background-kill on a specific manufacturer | MEDIUM | Ship OEM-specific onboarding guidance and diagnostics quickly; cannot be fully "fixed" in-app since it's OS/OEM-controlled, so managing user expectations is part of the recovery |
| ICE/NAT failures causing one-way audio in production | MEDIUM | Ship ICE-restart-on-network-change fix, add TURN if only STUN was configured, add automated network-change test to prevent regression |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|-------------------|---------------|
| CallKit reporting failures / token revocation | Phase 1 | Automated/manual test firing malformed, duplicate, and expired VoIP pushes; confirm no code path skips `reportNewIncomingCall` |
| OEM background-kill (Samsung/Xiaomi/Huawei/OnePlus) | Phase 1 (baseline), Phase 6 (ongoing regression) | Real-device test matrix covering at least 3 major OEM skins, tested after 24-48h idle and after reboot |
| FCM high-priority silent downgrade | Phase 1 | Verify every call-type FCM message path results in a visible notification; monitor delivery latency over time in diagnostics |
| USE_FULL_SCREEN_INTENT default-deny on Android 14+ | Phase 1 (implementation), Phase 6 (Play Console declaration/release gate) | Test on real Android 14/15 device with permission denied; verify graceful fallback and Play Console declaration completed before submission |
| Long-lived camera/RTSP URL leakage via push | Phase 1 (payload schema lock-in), Phase 5 (feature implementation) | Wire-level audit of actual push payloads sent to APNs/FCM; confirm no media URLs/credentials present |
| Push replay / unsigned events | Phase 1-2 (relay design) | Replay a captured event ID and confirm rejection; send an expired-but-validly-signed event and confirm rejection |
| NAT/TURN failure on network switch | Phase 1 (TURN groundwork), Phase 3 (full verification) | Real-device WiFi↔cellular handoff mid-call test with audio verified both directions |
| RTSP/H.264 gateway + door-station latency | Phase 5 (with early spike before, given hardware available now) | Stopwatch-measured time-to-first-frame against real Akuvox hardware; test on at least two different phone models/decoders |

## Sources

- [Apple Developer Forums — VoIP push report failure counter / PushKit tags](https://developer.apple.com/forums/tags/pushkit/?sortBy=oldest)
- [Apple Developer Forums — CallKit UI not invoked after VoIP push, app killed](https://developer.apple.com/forums/thread/801446)
- [Apple Developer Forums — VoIP/PushKit notification failure on iOS 18](https://developer.apple.com/forums/thread/805127)
- [ConnectyCube — Troubleshooting common issues with VoIP Push Notifications on iOS (2025)](https://connectycube.com/2025/11/06/troubleshooting-common-issues-with-voip-push-notifications-on-ios/)
- [Firebase — Set and manage Android message priority](https://firebase.google.com/docs/cloud-messaging/android-message-priority)
- [Firebase Blog — Understanding FCM Message Delivery on Android (2024)](https://firebase.blog/posts/2024/07/understand-fcm-delivery-rates/)
- [Firebase Blog — Ensure your FCM notifications reach your users on Android (2025)](https://firebase.blog/posts/2025/04/fcm-on-android/)
- [Google Play Console Help — Policy announcement: July 17, 2024 (full-screen intent)](https://support.google.com/googleplay/android-developer/answer/14993590)
- [Google Play Console Help — Understanding foreground service and full-screen intent requirements](https://support.google.com/googleplay/android-developer/answer/13392821)
- [Android Open Source Project — Full-screen intent limits](https://source.android.com/docs/core/permissions/fsi-limits)
- [Android Developers — Behavior changes: Apps targeting Android 14](https://developer.android.com/about/versions/14/behavior-changes-14)
- [Android Developers — Core-Telecom self-managed ConnectionService](https://developer.android.com/develop/connectivity/telecom/selfManaged)
- [Android Open Source Project — Support third-party calling apps](https://source.android.com/docs/core/connect/third-party-call-apps)
- [DEV Community — What Android OEMs do to background apps, and the 11 layers survival guide](https://dev.to/stoyan_minchev/what-android-oems-do-to-background-apps-and-the-11-layers-i-built-to-survive-it-28bb)
- [React Native Background Guardian — OEM restrictions overview](https://ivangonzalezg-react-native-background-guardian.mintlify.app/concepts/oem-restrictions)
- Project's own `ENTWICKLUNGSPLAN.md` (explicit push-security, push-payload-minimization, and delivery-guarantee caveats already identified by the original plan author)

---
*Pitfalls research for: Native VoIP/CallKit softphone companion app with self-hosted PBX backend*
*Researched: 2026-07-31*
