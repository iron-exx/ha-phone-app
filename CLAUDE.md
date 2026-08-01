<!-- GSD:project-start source:PROJECT.md -->
## Project

**HA-Phone App**

Native Softphone-App für iOS und Android als offizielles Companion-Produkt zur selbstgehosteten HA-Phone-PBX (Asterisk-basiert, Home-Assistant-Add-on, https://github.com/iron-exx/HA-Phone). Löst zuverlässig eingehende Anrufe bei geschlossener/gesperrter App über VoIP-Push (APNs/FCM) aus, wird per QR-Code ohne manuelle SIP-Eingabe eingerichtet und zeigt bei Türstationen (z.B. Akuvox) das Kamerabild bereits vor Annahme des Anrufs. Gebaut nicht als generisches SIP-Softphone, sondern fest an HA-Phone gekoppelt — und von Anfang an so, dass auch andere HA-Phone-Betreiber (nicht nur der eigene Haushalt) die App gegen ihre eigene Box nutzen können.

**Core Value:** Ein eingehender Anruf klingelt zuverlässig über die native Anrufoberfläche, egal ob die App geschlossen oder das Gerät gesperrt ist — ohne dauerhaft laufende SIP-Verbindung oder VPN-Tunnel im Hintergrund.

### Constraints

- **Tech-Stack**: Native getrennte Apps — Swift/SwiftUI (iOS) und Kotlin/Jetpack Compose (Android), kein Flutter/React Native — Entscheidung laut Plan-Empfehlung, da CallKit/Telecom/PJSIP-Integration native Zuverlässigkeit braucht
- **SIP/Media-Kern**: PJSIP/PJSUA2 als gemeinsame Grundlage auf beiden Plattformen (SIP über TLS, SRTP, ICE/STUN/TURN)
- **Backend-Kopplung**: Push-Gateway und QR-Provisionierung werden direkt in HA-Phone (FastAPI) integriert, nicht als separater Dienst — App spricht ausschließlich mit HA-Phone
- **Push-Architektur**: Zentraler, vom Projekt selbst betriebener Relay-Dienst hält die APNs-/FCM-App-Credentials; jede HA-Phone-Box sendet signierte Call-Events an diesen Relay. Kein Rückgriff auf Nabu Casa (an offizielle HA-App-Identität gebunden) oder Tailscale (löst Netzwerk-, nicht Push-Credential-Problem)
- **Budget**: Kostenlos im Betrieb angestrebt — FCM ist kostenlos, APNs-Versand ist kostenlos (nur die für die App-Veröffentlichung ohnehin nötige Apple Developer Membership, 99 $/Jahr, fällt an)
- **Zielgruppe**: Von Anfang an auch für fremde HA-Phone-Installationen gedacht (nicht nur eigener Haushalt) — beeinflusst Provisionierung, Gerätesicherheit und Relay-Design
- **Transport für SIP/Media**: Tailscale statt eigenem STUN/TURN-Aufbau — Nutzer hinterlegt seinen Tailscale-Account einmal in App und HA-Phone, Verbindung wird bei Bedarf automatisch (nicht dauerhaft) aufgebaut. Erfordert vermutlich eingebettete `tsnet`-Anbindung oder OAuth-Client/Auth-Key-basierte automatische Node-Registrierung statt der separaten Tailscale-App — technischer Ansatz wird in Architektur-Recherche vertieft
<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->
## Technology Stack

## Recommended Stack
### Core Technologies
| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| PJSIP / PJSUA2 | 2.16 stable (2.17 is dev/trunk as of April 2026) | SIP signaling, SDP, RTP/SRTP, ICE/STUN/TURN, codec negotiation — the shared media/signaling core on both platforms | Free, actively maintained (pjsip/pjproject on GitHub, releases through 2026), C/C++ core with official PJSUA2 (C++) API plus SWIG-generated bindings for Obj-C++ (iOS) and Java/Kotlin (Android). Officially documents PushKit/CallKit integration (`docs.pjsip.org/.../ios_push_notifications.html`) and a Kotlin sample client (`kotlin-sip-client.html`) — this is the only cross-platform SIP core with first-party guidance for exactly this project's requirements (VoIP-push wake, CallKit/Telecom, SRTP/ICE). Confidence: HIGH (official docs). |
| Swift 6.x / SwiftUI | Xcode 16+/current toolchain | Native iOS app UI + CallKit/PushKit glue | Already decided by project constraints; current standard for new iOS apps in 2025/2026, required for CallKit `CXProvider`/`CXCallController` and PushKit `PKPushRegistry` which are Swift/Obj-C only APIs. Confidence: HIGH. |
| Kotlin / Jetpack Compose | Kotlin 2.x, Compose BOM current stable | Native Android app UI + Telecom/FCM glue | Already decided by project constraints; current Google-recommended standard for Android UI, required for `ConnectionService`, `Notification.CallStyle`, and FCM `FirebaseMessagingService`. Confidence: HIGH. |
| FastAPI (existing HA-Phone backend) | current HA-Phone version | QR provisioning, device registry, push-relay endpoints | Already the project's backend; extending it (not adding a separate stack) is the explicitly chosen architecture per PROJECT.md. Confidence: HIGH (project constraint, not a research question). |
### Supporting Libraries — iOS
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| PushKit (`PKPushRegistry`) | iOS SDK, system framework | Receive VoIP pushes, wake app when suspended/terminated | Always, for the VoIP wake path — this is the only Apple-sanctioned mechanism for background VoIP wake since regular APNs pushes cannot reliably launch a terminated app for calls. |
| CallKit (`CXProvider`, `CXCallController`, `CXProviderConfiguration`) | iOS SDK, system framework | Native incoming/in-call UI, Do Not Disturb bypass, CarPlay/lock-screen integration | Always — mandatory companion to PushKit; a VoIP push handler that doesn't report to CallKit within the OS deadline gets the app's VoIP token disabled by Apple (see Pitfalls). |
| AVAudioSession | iOS SDK | Audio routing (speaker/Bluetooth/earpiece), category `.playAndRecord` with `.voiceChat` mode | Always, coordinated with CallKit's own audio session activation callbacks (`didActivate:`/`didDeactivate:` on `CXProvider`) — do not configure the audio session outside those callbacks or you get channel conflicts. |
| PJSUA2 iOS build (self-built static lib via PJSIP's `configure-iphone` + `build_instructions.rst`) | matches PJSIP 2.16 | SIP core linked into the Swift app via an Objective-C++ bridge | Build once per PJSIP release as part of CI; do not hand-roll a CocoaPod unless you specifically want dynamic-framework packaging (see Alternatives). |
### Supporting Libraries — Android
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Firebase Cloud Messaging (Android SDK, `firebase-messaging`) | current BoM (34.x line, verify latest at implementation time) | Receive high-priority data push to wake the app | Always for the Android wake path; use **data-only** messages (no `notification` block) so `FirebaseMessagingService.onMessageReceived()` is invoked in all app states and you build the notification yourself. |
| Telecom framework — self-managed `ConnectionService` + `PhoneAccount` | Android SDK, API 26+ (target current API level, e.g. 35/36) | Register the app as a calling app with the OS, get audio routing / DND bypass / Bluetooth SCO handled by the platform | Recommended over CallStyle-notification-only approach — self-managed ConnectionService is what unlocks proper audio-focus arbitration with other calls, Android Auto handoff, and is what Google Play now requires apps to have if they want default full-screen-intent permission for calling. |
| `Notification.CallStyle` (`NotificationCompat.CallStyle` in AndroidX) | AndroidX Core current | The visible incoming-call notification (Android 12+/API 31+) shown alongside/instead of a custom full-screen activity | Always on API 31+; pair with a full-screen `Intent` for lock-screen display. On API < 31, fall back to a regular high-priority notification with full-screen intent (no CallStyle template available). |
| `USE_FULL_SCREEN_INTENT` permission | manifest permission | Show the incoming-call UI over the lock screen | Required, but as of apps targeting Android 14+ (API 34+), Play Store only auto-grants this to apps that are calling or alarm apps — self-managed ConnectionService registration is what qualifies this app as a "calling app" for that grant. |
| WorkManager / foreground service (`ConnectionService`-bound) | AndroidX current | Keep the process alive long enough to establish SIP/media after the user answers | Use short-lived foreground service tied to the active call, not a permanently running background service — matches the project's "no permanent SIP registration" principle and avoids battery/Doze issues. |
| PJSUA2 Android build (official `pjsua2` Java/Kotlin JNI module, built via `configure-android` NDK build) | matches PJSIP 2.16 | SIP core, exposed to Kotlin via the JNI/SWIG Java bindings PJSIP generates | Build via PJSIP's official Android build instructions; avoid the small number of unofficial prebuilt AARs on Maven Central (e.g. `de.d0pam1n:pjsip-android`) for production — they are unverified third-party builds with unclear provenance/patch history. |
### Backend / Push-Relay Libraries (FastAPI side)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `aioapns` | 3.x (current) | Async APNs HTTP/2 client for sending VoIP pushes from the FastAPI backend | Preferred over `apns2`/`PyAPNs2`: async-native (fits FastAPI's asyncio model), actively maintained, supports Python 3.10+, and supports token-based (.p8/JWT) auth. `apns2` is effectively unmaintained and incompatible with newer Python. |
| `firebase-admin` (Python) | current (`firebase-admin` PyPI, 6.x line) | FCM HTTP v1 message sending, including `AndroidConfig(priority='high')` for data-only high-priority pushes | Official Google SDK; use over hand-rolled HTTP calls to the legacy FCM server-key API, which Google has fully deprecated in favor of HTTP v1 + OAuth2/service-account auth. |
| PyJWT (used internally by APNs auth, or directly if not using aioapns) | current | Sign short-lived ES256 JWTs for APNs token-based auth from the `.p8` key | Needed regardless of APNs client chosen; `aioapns` handles this internally. |
| `cryptography` | current | ES256 signing support for the APNs JWT, HMAC/signing for the app's own push-event signing envelope (call event authenticity, per ENTWICKLUNGSPLAN §11) | Standard, audited crypto primitives library — do not implement JWT signing or HMAC by hand. |
### Development Tools
| Tool | Purpose | Notes |
|------|---------|-------|
| PJSIP official build scripts (`configure-iphone`, `configure-android`, `build_instructions.rst`) | Cross-compile PJSIP for each platform/arch | Not trivial — official docs explicitly call this out. Budget real setup time in Phase 1; script this into CI once working so it isn't a manual per-developer chore. |
| Xcode Cloud or Fastlane + GitHub Actions (macOS runner) | iOS CI/CD, TestFlight distribution | Needed by Phase 6 (App Store/TestFlight); macOS runners are the constraint, not the tooling choice. |
| Gradle + GitHub Actions | Android CI/CD, Play Store internal testing track | Standard. |
| ngrok / a public HTTPS+WSS tunnel for the FastAPI backend during dev | Local testing of QR provisioning and push flows against real iOS/Android devices | APNs/FCM both require reachable, valid-TLS endpoints for device-side testing even in development — self-signed certs will fail silently on iOS. |
## Installation
# Backend (FastAPI push-relay additions)
# iOS: no package manager install for PJSIP — build from source per
# https://docs.pjsip.org/en/latest/get-started/ios/build_instructions.html
# then link the resulting static libs into the Xcode project via an
# Objective-C++ bridging target (do NOT use `pod install pjsip` for production, see below)
# Android: build PJSUA2 JNI module from source per
# https://docs.pjsip.org/en/latest/get-started/android/build_instructions.html
# then depend on the generated pjsua2.jar / .so via a local Gradle module,
# not a third-party Maven artifact
## Alternatives Considered
| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|--------------------------|
| Build PJSIP from source per official docs | Community CocoaPod `Vialer-pjsip-iOS` / `pjsip` pod, or third-party AARs (`de.d0pam1n:pjsip-android`) | Only for early prototyping/spike work where build-pipeline setup time is the bottleneck and you accept an unaudited, possibly stale/patched build. Not recommended for the shipped product — these are unofficial builds maintained by third parties (VoIPGRID/Vialer, individual devs), version provenance and patch parity with upstream PJSIP is unclear, and the CocoaPod is a static "fat" library that is incompatible with `use_frameworks!`. |
| PJSIP/PJSUA2 as the shared SIP core | Linphone SDK (`liblinphone`) | If the team wants to trade some control for a much shorter time-to-first-call: liblinphone is a full, actively maintained (Linphone 6.0 as of 2025/2026) open-source VoIP SDK with native Swift and Kotlin wrappers, its own CallKit integration already built, Maven/CocoaPods packaging, and its own media engine (mediastreamer2) with SRTP/ICE/TURN and Opus/H.264 already wired up. It is heavier (GPL/AGPL or commercial dual-licensing — verify license terms against the project's plan to serve other HA-Phone operators, since AGPL has network-copyleft implications) and less flexible for a PBX-specific SIP dialect, but is the single most complete "reference implementation to study or fork" available. Given the project's explicit choice of PJSIP in ENTWICKLUNGSPLAN.md and its stated goal of being a lean, HA-Phone-specific client, stick with PJSIP for the shipped stack, but strongly recommend cloning `linphone-ios` and `linphone-android` as **study material** for the CallKit/PJSIP-equivalent glue code, since they solve the exact PushKit-report-then-attach-SIP problem this project needs. |
| Self-managed `ConnectionService` + CallStyle notification | CallStyle notification only, no ConnectionService | Acceptable for a fast MVP/spike (Phase 1 prototype) since CallStyle alone can drive answer/decline UI and lock-screen display without Telecom registration. Switch to self-managed ConnectionService before Phase 3 (production audio) once Bluetooth/Android-Auto audio routing and default full-screen-intent permission (Play Store restricts this to "calling apps" from API 34+) become requirements. |
| `aioapns` for APNs sending | `PyAPNs2`/`apns2` | Never for new code in 2026 — unmaintained, `apns2` doesn't support Python 3.10+, uses an outdated JWT library. |
| Token-based APNs auth (.p8 key) | Certificate-based (.p12) auth | Never choose certificate-based for new integrations — Apple is actively deprecating cert-based auth, certs expire annually per-app and are an operational liability for a multi-tenant relay serving many HA-Phone boxes; one .p8 key covers the whole developer account and never expires. |
| FCM HTTP v1 API (OAuth2 service account) | Legacy FCM server-key API | Never — the legacy API is fully deprecated/shut down by Google; `firebase-admin` already targets v1 exclusively. |
## What NOT to Use
| Avoid | Why | Use Instead |
|-------|-----|--------------|
| Regular (non-VoIP) APNs push to wake the app for calls | Regular APNs pushes cannot reliably launch a fully-terminated app, and Apple explicitly reserves guaranteed background wake for PushKit VoIP pushes tied to CallKit reporting | PushKit + CallKit, always for the call-wake path. |
| Calling `reportNewIncomingCall` asynchronously, after network/API calls, inside the PushKit handler | Since iOS 13 the OS requires the call to be reported to CallKit synchronously/immediately in `pushRegistry(_:didReceiveIncomingPushWith:for:completion:)`; delaying it (e.g. to first fetch call details from the PBX) risks the OS killing the app with `0xbaadca11` and eventually disabling the app's VoIP push entitlement entirely | Report the incoming call to CallKit **first**, with whatever caller info is in the push payload, then fetch additional call details (door-station preview, caller name lookup) asynchronously after reporting. |
| Certificate-based (.p12) APNs auth for a multi-box relay service | Per-app yearly cert renewal is an operational hazard for a relay meant to serve many independent HA-Phone installations; a missed renewal silently breaks push for every box using that cert | Token-based (.p8) JWT auth — one long-lived key, no expiry, works across topics. |
| FCM `notification`-only messages for incoming calls | Notification-block-only FCM messages are handled by the OS system tray directly and do not reliably invoke your `onMessageReceived()` when the app is backgrounded/killed, so you cannot build a custom CallStyle/ConnectionService flow from them | Data-only FCM messages with `AndroidConfig(priority='high')`, and build the CallStyle notification + ConnectionService call yourself in `onMessageReceived()`. |
| Relying on `USE_FULL_SCREEN_INTENT` alone without registering a self-managed `ConnectionService`/being a recognized calling app | Starting with apps targeting Android 14 (API 34), Google Play auto-revokes default grant of this permission for apps that aren't calling or alarm apps; a bare notification-only softphone risks losing lock-screen call display entirely on newer Android | Register a self-managed `ConnectionService` + `PhoneAccount` so the app is recognized by the platform as a calling app, which is what preserves the full-screen-intent grant. |
| Third-party/unofficial prebuilt PJSIP binaries (random Maven/CocoaPods artifacts) for the production build | Unclear build provenance, unknown patch/CVE status versus upstream PJSIP, and several (e.g. the CocoaPod) have known packaging limitations (static-only, no `use_frameworks!` support) | Build PJSIP from official source per `docs.pjsip.org`, pin the exact upstream tag, and vendor the build output through project CI. |
| A permanently-registered/always-connected SIP client in the background on either platform | Contradicts the project's core design principle (no permanent SIP registration, push-first) and burns battery/violates the "connect only after push+answer" architecture already decided in PROJECT.md | Register SIP transiently after CallKit/ConnectionService reports the call and the user answers (or, for outbound calls, when the user initiates one); tear down/de-register afterward. |
| Kotlin Multiplatform (KMP) "shared core" as suggested loosely in ENTWICKLUNGSPLAN §9 | The project's own constraints already settled on fully separate native codebases specifically because CallKit/Telecom/PJSIP integration reliability was judged more important than a shared business-logic layer; introducing KMP now would reintroduce the cross-platform abstraction risk the plan explicitly rejected | Two separate native codebases (Swift/SwiftUI, Kotlin/Compose) each linking directly to their own PJSIP build, sharing only the API contract (REST schema) with the FastAPI backend, not runtime code. |
## Stack Patterns by Variant
- Consider starting the spike with a community PJSIP CocoaPod/AAR (accepting the provenance risk) to shave days off setup, then replace with an official from-source build before Phase 3.
- Because Phase 1's abnormal-development goal is proving the push→CallKit/Telecom wake path, not shipping production SIP media; the PJSIP build pipeline is a one-time investment that shouldn't gate that specific proof.
- Use short-lived signed HTTPS snapshot/stream URLs served directly by HA-Phone (as ENTWICKLUNGSPLAN §7 already specifies), not a new WebRTC stack in the app.
- Because introducing WebRTC in the mobile app before HA-Phone's backend supports it duplicates infrastructure that HA-Phone's own roadmap will eventually provide; a time-boxed HTTPS snapshot/stream link keeps the two roadmaps decoupled while still delivering the "see the visitor before answering" value.
- Use a plain shared OpenAPI-generated client (generated separately for Swift and Kotlin from the same FastAPI OpenAPI schema) rather than KMP or Flutter modules.
- Because it gets consistency without introducing a cross-platform runtime into the call-critical path.
## Version Compatibility
| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| PJSIP 2.16/2.17-dev | iOS 15+ / Xcode 16+ toolchains, Android NDK r26+ | Verify exact NDK/Xcode version pins against `docs.pjsip.org` build_instructions at implementation time — these shift with each PJSIP release. |
| `aioapns` 3.x | Python 3.10+ | Older `apns2`/`PyAPNs2` breaks on 3.10+; if the FastAPI backend is already on 3.11/3.12, `aioapns` is the only realistic choice. |
| `firebase-admin` (Python) 6.x | FCM HTTP v1 API only | Do not mix with any legacy server-key code paths still present in older HA-Phone code, if any exists. |
| Self-managed `ConnectionService` | API 26+ (project should target current, e.g. API 34/35 minSdk decision separately) | `CallStyle` notifications specifically require API 31+; below that, fall back to a manually-styled full-screen-intent notification. |
| CallKit `CXProvider` | iOS 10+ (irrelevant floor given modern deployment targets); PushKit VoIP-push-to-CallKit synchronous reporting requirement is enforced since iOS 13 | Treat "report immediately, every time" as a hard requirement, not a best-effort guideline — Apple audits telemetry and can disable the app's VoIP push entitlement for repeated violations. |
## Sources
- https://docs.pjsip.org/en/latest/get-started/ios/build_instructions.html — official iOS build instructions (HIGH confidence)
- https://docs.pjsip.org/en/latest/specific-guides/other/ios_push_notifications.html — official PJSIP guide to PushKit/CallKit integration (HIGH confidence)
- https://docs.pjsip.org/en/latest/get-started/android/build_instructions.html and kotlin-sip-client.html — official Android/Kotlin build + sample docs (HIGH confidence)
- https://github.com/pjsip/pjproject/releases — version history, 2.16/2.17 releases (HIGH confidence)
- https://github.com/VoIPGRID/Vialer-pjsip-iOS, https://cocoapods.org/pods/pjsip — community PJSIP packaging, used only to characterize the "unofficial binary" alternative (MEDIUM confidence)
- Apple Developer Forums threads on CallKit/PushKit `0xbaadca11` kill behavior and VoIP token disabling (MEDIUM confidence — forum-sourced but consistent across multiple independent threads)
- https://developer.android.com/develop/ui/compose/notifications/call-style — official Android CallStyle notification docs (HIGH confidence)
- https://source.android.com/docs/core/permissions/fsi-limits and https://support.google.com/googleplay/android-developer/answer/13392821 — official Android/Play full-screen-intent restriction docs for API 34+ (HIGH confidence)
- https://grokipedia.com/page/Self-managed_ConnectionService_Android — self-managed ConnectionService behavior summary (MEDIUM confidence, cross-checked against Android source docs)
- Apple APNs 2025 token-based vs certificate-based auth transition coverage (Medium/Simform Engineering, PushEngage, OneSignal docs) (MEDIUM confidence, consistent across multiple sources; verify current specifics against developer.apple.com/documentation/usernotifications at implementation time)
- https://firebase.google.com/docs/cloud-messaging/send/v1-api and /server-environment — official FCM HTTP v1 docs (HIGH confidence)
- https://github.com/Fatal1ty/aioapns vs https://github.com/Pr0Ger/PyAPNs2 — maintenance-status comparison for Python APNs clients (MEDIUM confidence, GitHub activity/issue-thread based)
- https://www.linphone.org/en/liblinphone-voip-sdk/, https://www.ow2con.org/view/2025/News/whats_new_with_linphone — Linphone SDK current status, used to characterize the reference-implementation alternative (MEDIUM confidence)
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
