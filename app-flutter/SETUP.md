# app-flutter — Phase 1 setup

This project was hand-written (no Flutter SDK available in the session that
created it) to mirror what `flutter create` generates, plus the native
Android SIP/Telecom/push layer ported in from `../android-app/`. It has
**not been built or run** anywhere yet — do that here first.

## Prerequisites

- Flutter SDK (the old `android-app/local.properties` points `sdk.dir` at
  `/home/roto/android-sdk`, suggesting your Android build environment is
  Linux/WSL, not this Windows checkout — build there).
- Android SDK, platform 35, NDK not required (PJSIP `.so` libs are
  prebuilt and vendored in `android/sip-core/`).
- JDK 17.

## First build

1. `flutter pub get` from `app-flutter/` — this auto-generates
   `android/local.properties` (`sdk.dir` + `flutter.sdk`). **Do not**
   hand-write that file; Flutter tooling owns it and rewrites it on every
   sync.
2. Confirm `android/app/sip-secrets.local.properties` exists (it was
   carried over from `android-app/local.properties`'s `sip.test.*` keys
   during the port — gitignored, holds the real dev/test-extension SIP
   password). If missing, copy
   `android/app/sip-secrets.local.properties.example` and fill it in.
3. Confirm `android/app/google-services.json` exists (copied from
   `android-app/app/google-services.json` — gitignored, Firebase config).
4. `flutter build apk --debug` or `flutter run` on a connected
   device/emulator.

## What to verify (Phase 1's actual milestone)

Enter the dev SIP test-extension credentials on the Settings screen (or
confirm they're already populated from `sip-secrets.local.properties`),
go to the Dialpad screen, dial the test extension, and confirm a real SIP
INVITE reaches the HA-Phone box and the call connects. Per
`.planning/STATE.md` in the repo root, this may be the first time either
app (native or Flutter) has verified a live call end-to-end.

Unit tests (no emulator needed): `./gradlew :app:testDebugUnitTest` from
`android/`.

## Known gaps (deliberately out of Phase 1 scope)

- iOS platform-channel side doesn't exist yet — only Android.
- QR-code pairing isn't implemented (nor is it on the old native apps) —
  manual SIP entry via Settings is the only pairing path right now, and
  even that requires the backend's `mobile_provisioning.py` bugs (double
  `/api` prefix, wrong admin-auth gate) to be fixed before real
  QR-based provisioning could ever work.
- Audio-routing UI (Bluetooth/speaker/earpiece picker,
  `CallControlScope.availableEndpoints`) isn't wired into
  `ActiveCallScreen` yet.
- The `call_events` EventChannel only emits coarse registration/call
  lifecycle state (see `CallEventBus.kt`'s doc comment) — no screen
  consumes it yet, and finer-grained PJSIP-level state isn't wired.
- `android/sip-core/` is a **physical copy** of `../android-app/sip-core`
  (its payload is gitignored there, so there's no git-resolvable relative
  reference) — the two copies are not kept in sync automatically. If you
  rebuild PJSIP, update both.
